/**
 * trainer.js
 * ------------------------------------------------------------------
 * Runs a generation of AI cars on the track(s) and scores them.
 * Pure simulation (no rendering): the training mode calls step() as often
 * as it likes. At "Max" speed the session moves to a Web Worker
 * (trainWorker.js) and back with exportState() / Trainer.fromState().
 *
 * One generation = every selected track driven in turn by the whole
 * population. A car's fitness is its average score over those tracks.
 *
 * Score for one track run (0 .. ~1950):
 *   1000 × fraction of the race distance covered
 * +  200 × fraction of checkpoints reached
 * +  finished ? 500 × (reference time / your time, capped at 1.5)
 *             : 50 × average speed / 50 m/s (small tie-breaker)
 *
 * Walls (setting `walls`):
 *   'ride'  (default) a car may hit and scrape the walls and keeps driving,
 *           so it can learn where a wall beats braking. Since physics v3 a
 *           hit costs speed by how hard it is (a 5° touch at 150 km/h about
 *           15-20 km/h, 30° at 180 km/h stops the car) and scraping slows
 *           the car further; a hard hit still slows it faster than the
 *           brakes, so 'ride' networks still tend to turn hairpins off the
 *           outside wall instead of braking. The rules below still remove
 *           cars that get stuck or turn around.
 *   'crash' touching a wall (the 4.4 × 2 m car body) puts the car out,
 *           so it learns to drive clean lines (the v1/v2.0 behaviour).
 *
 * A car is out of the run when it
 *   - touches a wall, with walls: 'crash',
 *   - stalls (less than 6 m of progress in RULES.stallTime seconds),
 *   - drives backwards (RULES.backwards metres behind its best progress),
 *   - is too slow between two checkpoints: it must reach the next gate
 *     within (gate distance / RULES.minPace) + RULES.gateSlack seconds,
 *     which keeps crawling cars from stretching a generation on long tracks,
 *   - is still driving well after the first car finished
 *     (RULES.finishCutoff × the winner's time + RULES.finishSlack), or
 *   - runs out of time (race distance / RULES.minPace + RULES.timeSlack).
 * Cars that drop out keep the score they had reached.
 */
import { NeuralNetwork } from './network.js';
import { Population } from './genetic.js';
import { sense, driveNetwork, INPUT_COUNT, OUTPUT_COUNT, SENSOR_ANGLES, SENSOR_VERSION, INPUT_LABELS } from './sensors.js';
import { createCar, stepCar } from '../physics/car.js';
import { RaceState } from '../game/race.js';
import { raceLength } from '../tracks/trackBuilder.js';

export const DEFAULT_TRAINING = {
  populationSize: 80,
  mutationRate: 0.1,
  hidden: [12],
  laps: 1,
  walls: 'ride', // 'ride' = cars keep going after a wall hit, 'crash' = a wall hit puts the car out
};

/** Training wall rules (see the header): value -> label in the training form's Walls menu. */
export const WALL_RULES = { ride: 'Ride them (car keeps going)', crash: 'Crash out (car is out)' };

/**
 * The wall rule a saved network file was trained with: a WALL_RULES key, or null
 * for a bare network without training info (or an unknown rule). Files saved
 * before the setting existed used 'crash'.
 */
export function savedWallRule(meta) {
  if (!meta || !Array.isArray(meta.trainedOn)) return null;
  const rule = meta.settings?.walls ?? 'crash';
  return Object.hasOwn(WALL_RULES, rule) ? rule : null;
}

/** Elimination rules (see the header). Times in seconds, distances in metres, speeds in m/s. */
export const RULES = {
  stallTime: 3,
  backwards: 20,
  minPace: 8,
  gateSlack: 10,
  timeSlack: 20,
  finishCutoff: 1.25,
  finishSlack: 5,
  refSpeed: 50, // m/s: finishing at this average speed earns the full 500 bonus
};

/** Format identifier and version of saved network files. */
export const NETWORK_FORMAT = 'trackmania-lite-network';
export const NETWORK_FILE_VERSION = 2;

export class Trainer {
  /**
   * @param {object} opts
   *   tracks          built tracks to train on (at least one)
   *   populationSize, mutationRate, hidden (array of hidden layer sizes), laps,
   *   walls ('ride' or 'crash', see the header)
   *   seed            optional NeuralNetwork to continue training from
   *   seedMeta        optional {generation, fitness, history, bestTimes}
   *   (Trainer.fromState passes `state` instead, to continue an exported session)
   */
  constructor(opts) {
    this.cfg = { ...DEFAULT_TRAINING, ...opts };
    if (!Object.hasOwn(WALL_RULES, this.cfg.walls)) this.cfg.walls = DEFAULT_TRAINING.walls;
    this.tracks = opts.tracks;
    const saved = opts.state ?? null;
    delete this.cfg.state;
    if (saved) {
      this.population = Population.fromState(saved.population);
      this.sizes = this.population.cfg.sizes.slice();
      this.generation = saved.generation;
      this.history = saved.history.map((h) => ({ ...h }));
      this.bestTimes = structuredClone(saved.bestTimes);
    } else {
      const seed = opts.seed ?? null;
      const meta = opts.seedMeta ?? null;
      this.sizes = seed ? seed.sizes.slice() : [INPUT_COUNT, ...this.cfg.hidden, OUTPUT_COUNT];
      // A saved fitness only counts as "best ever" when it was scored on the same tracks, laps and wall rule.
      // Otherwise (e.g. a network from an easy oval continued on a hard track) the first generation
      // sets the best, or an old high score would hide every improvement on the new track.
      const sameTask = !!meta && Array.isArray(meta.trainedOn) &&
        meta.trainedOn.join(',') === this.tracks.map((t) => t.id).join(',') &&
        (meta.settings?.laps ?? 1) === this.cfg.laps &&
        savedWallRule(meta) === this.cfg.walls;
      this.population = new Population({
        size: this.cfg.populationSize,
        sizes: this.sizes,
        mutationRate: this.cfg.mutationRate,
        seed,
        seedFitness: sameTask && Number.isFinite(meta.fitness) ? meta.fitness : null,
      });
      this.generation = opts.seedMeta?.generation ?? 0;
      this.history = opts.seedMeta?.history?.slice() ?? []; // [{gen, best, avg}]
      this.bestTimes = {}; // trackId -> {lap, finish}
    }
    this.deaths = {}; // reason -> count, for the run in progress
    this.wallCars = 0; // cars that touched a wall in the run in progress
    this.onTrackChange = null; // (track) => void
    this.onGeneration = null; // (stats) => void
    this.onRunEnd = null; // (track, deaths {reason: count}) => void, after each track run
    this.ctrl = { steer: 0, throttle: 0, handbrake: false };
    this.mirrored = new Float32Array(INPUT_COUNT);
    if (saved?.run) this.restoreRun(saved.run);
    else this.beginGeneration();
  }

  /**
   * A Trainer that continues a session saved by exportState(), from the very step it
   * was saved at. `tracks`: built tracks that include the ones it names (matched by id).
   * It draws no random numbers.
   */
  static fromState(state, tracks) {
    const byId = new Map(tracks.map((t) => [t.id, t]));
    const own = state.tracks.map((id) => byId.get(id));
    if (!own.length || own.some((t) => !t)) throw new Error(`Training state names unknown tracks (${state.tracks.join(', ')})`);
    return new Trainer({ ...state.settings, tracks: own, state });
  }

  get bestFitness() {
    return this.population.bestEver?.fitness ?? 0;
  }

  get bestNet() {
    return this.population.bestEver?.net ?? null;
  }

  get aliveCount() {
    let n = 0;
    for (const a of this.agents) if (a.alive) n++;
    return n;
  }

  beginGeneration() {
    this.trackPos = 0;
    this.genScores = new Float32Array(this.population.size);
    this.beginTrackRun();
  }

  beginTrackRun() {
    const track = this.useTrack(this.tracks[this.trackPos]);
    this.simTime = 0;
    this.firstFinish = null;
    this.deaths = {};
    this.wallCars = 0;
    this.agents = this.population.genomes.map((g, i) => this.newAgent(g, i));
    for (const a of this.agents) a.gateDeadline = this.gateDeadline(a, a.startProg, 0);
    if (this.onTrackChange) this.onTrackChange(track);
  }

  /** Make `track` the one driven, with its race length and limits. */
  useTrack(track) {
    this.track = track;
    this.raceLen = raceLength(track, this.cfg.laps);
    this.refTime = this.raceLen / RULES.refSpeed;
    this.timeLimit = this.raceLen / RULES.minPace + RULES.timeSlack;
    return track;
  }

  /** A car on the start line, driven by genome `g`. */
  newAgent(g, i) {
    const car = createCar(this.track);
    return {
      index: i,
      net: g.net,
      car,
      prev: { x: car.x, y: car.y, z: car.z, yaw: car.yaw }, // pose before the last step (for smooth rendering)
      race: new RaceState(this.track, this.cfg.laps),
      alive: true,
      finished: false,
      fitness: 0,
      startProg: car.prog,
      maxProg: car.prog,
      lastImprove: 0,
      gateDeadline: 0,
      inputs: new Float32Array(INPUT_COUNT),
      rays: new Float32Array(SENSOR_ANGLES.length),
      deathReason: '',
      touchedWall: false,
    };
  }

  /** Time by which a car that passed a gate at `fromProg` at time `now` must reach the next one. */
  gateDeadline(a, fromProg, now) {
    const g = a.race.gates[Math.min(a.race.nextGate, a.race.gates.length - 1)];
    const metres = Math.max(0, (g.prog - fromProg) * this.track.segLen);
    return now + metres / RULES.minPace + RULES.gateSlack;
  }

  /** Advance the whole population by one fixed step. */
  step(dt) {
    const track = this.track;
    this.simTime += dt;
    const now = this.simTime;
    const cutoff = this.firstFinish != null ? this.firstFinish * RULES.finishCutoff + RULES.finishSlack : Infinity;
    let anyAlive = false;
    for (const a of this.agents) {
      if (!a.alive) continue;
      const car = a.car;
      const p = a.prev;
      p.x = car.x; p.y = car.y; p.z = car.z; p.yaw = car.yaw;
      sense(track, car, a.race, a.inputs, a.rays);
      driveNetwork(a.net, a.inputs, this.mirrored, this.ctrl);
      stepCar(car, track, this.ctrl, dt);
      const events = a.race.update(car, dt);
      if (events) {
        for (const ev of events) this.recordTime(track, ev);
        if (!a.race.finished) a.gateDeadline = this.gateDeadline(a, a.race.gates[a.race.nextGate - 1].prog, now);
      }

      if (car.prog > a.maxProg + 3) {
        a.maxProg = car.prog;
        a.lastImprove = now;
      }
      a.fitness = this.score(a);
      if (car.hitWall && !a.touchedWall) { a.touchedWall = true; this.wallCars++; }

      let reason = '';
      if (a.race.finished) {
        reason = 'finished';
        a.finished = true;
        if (this.firstFinish == null) this.firstFinish = a.race.finishTime;
      } else if (car.hitWall && this.cfg.walls === 'crash') reason = 'wall';
      else if ((a.maxProg - car.prog) * track.segLen > RULES.backwards) reason = 'backwards';
      else if (now - a.lastImprove > RULES.stallTime) reason = 'stalled';
      else if (now > a.gateDeadline) reason = 'too slow';
      else if (now > cutoff) reason = 'cut off';
      else if (now > this.timeLimit) reason = 'time';
      if (reason) {
        a.alive = false;
        a.deathReason = reason;
        this.deaths[reason] = (this.deaths[reason] ?? 0) + 1;
        p.x = car.x; p.y = car.y; p.z = car.z; p.yaw = car.yaw; // parked: no interpolation wobble
      } else anyAlive = true;
    }
    if (!anyAlive) this.endTrackRun();
  }

  score(a) {
    const metres = Math.max(0, (Math.max(a.car.prog, a.maxProg - 3) - a.startProg) * this.track.segLen);
    const frac = Math.min(1, metres / this.raceLen);
    let f = 1000 * frac + (200 * a.race.nextGate) / a.race.totalGates;
    if (a.race.finished) f += 500 * Math.min(1.5, this.refTime / a.race.finishTime);
    else if (this.simTime > 1) f += 50 * Math.min(1, metres / this.simTime / RULES.refSpeed);
    return f;
  }

  recordTime(track, ev) {
    const rec = (this.bestTimes[track.id] ??= { lap: null, finish: null });
    if (ev.lapTime != null && (rec.lap == null || ev.lapTime < rec.lap)) rec.lap = ev.lapTime;
    if (ev.kind === 'finish' && (rec.finish == null || ev.time < rec.finish)) rec.finish = ev.time;
  }

  endTrackRun() {
    for (const a of this.agents) this.genScores[a.index] += a.fitness;
    if (this.onRunEnd) this.onRunEnd(this.track, this.deaths);
    this.trackPos++;
    if (this.trackPos < this.tracks.length) this.beginTrackRun();
    else this.endGeneration();
  }

  endGeneration() {
    const genomes = this.population.genomes;
    for (let i = 0; i < genomes.length; i++) genomes[i].fitness = this.genScores[i] / this.tracks.length;
    const stats = this.population.evolve();
    const entry = { gen: this.generation, best: stats.best, avg: stats.avg };
    this.history.push(entry);
    this.generation++;
    if (this.onGeneration) this.onGeneration(entry);
    this.beginGeneration();
  }

  /** Index of the alive car with the highest live fitness (or the best overall). */
  leaderIndex() {
    let best = -1, bf = -Infinity, bestAny = 0, bfa = -Infinity;
    for (const a of this.agents) {
      if (a.fitness > bfa) { bfa = a.fitness; bestAny = a.index; }
      if (a.alive && a.fitness > bf) { bf = a.fitness; best = a.index; }
    }
    return best >= 0 ? best : bestAny;
  }

  /** The numbers the training dashboard shows for the run in progress (plain data). */
  liveStats() {
    let leader = 0;
    for (const a of this.agents) leader = Math.max(leader, a.fitness);
    return {
      generation: this.generation,
      alive: this.aliveCount,
      size: this.population.size,
      bestFitness: this.population.bestEver ? this.bestFitness : null,
      leaderFitness: leader,
      trackPos: this.trackPos,
      simTime: this.simTime,
      deaths: { ...this.deaths },
      wallCars: this.wallCars,
      bestTimes: structuredClone(this.bestTimes),
    };
  }

  // ---- hand-over between threads (Max speed trains in a Web Worker, see trainWorker.js) ----

  /**
   * The whole session as plain data that survives postMessage (structured clone): settings,
   * track ids, generation, chart history, best times, the population (one Float32Array) with
   * its best network and, with `run` (the default), the track run in progress: every car's
   * physics, race and scoring state. Trainer.fromState() continues from it exactly.
   * The genetic algorithm draws from Math.random, which has no state to save: generations
   * bred after a hand-over are as random as any, not the ones this copy would have bred.
   */
  exportState({ run = true } = {}) {
    const { populationSize, mutationRate, hidden, laps, walls } = this.cfg;
    return {
      tracks: this.tracks.map((t) => t.id),
      settings: { populationSize, mutationRate, hidden: [...(hidden ?? DEFAULT_TRAINING.hidden)], laps, walls },
      generation: this.generation,
      history: this.history.map((h) => ({ ...h })),
      bestTimes: structuredClone(this.bestTimes),
      population: this.population.exportState(),
      run: run ? {
        trackPos: this.trackPos,
        simTime: this.simTime,
        firstFinish: this.firstFinish,
        deaths: { ...this.deaths },
        wallCars: this.wallCars,
        genScores: this.genScores.slice(),
        // every field of every agent, its car and race state, except what restoreRun rebuilds
        agents: this.agents.map(({ net, race, ...a }) => {
          const { track, gates, ...raceState } = race;
          return structuredClone({ ...a, race: raceState });
        }),
      } : null,
    };
  }

  /** Continue the track run saved by exportState() (see fromState). */
  restoreRun(run) {
    this.trackPos = run.trackPos;
    this.useTrack(this.tracks[run.trackPos]);
    this.simTime = run.simTime;
    this.firstFinish = run.firstFinish;
    this.deaths = { ...run.deaths };
    this.wallCars = run.wallCars;
    this.genScores = Float32Array.from(run.genScores);
    this.agents = run.agents.map((saved, i) => {
      const a = this.newAgent(this.population.genomes[i], i);
      const { car, prev, race, inputs, rays, ...rest } = structuredClone(saved);
      Object.assign(a.car, car);
      Object.assign(a.prev, prev);
      Object.assign(a.race, race);
      a.inputs.set(inputs);
      a.rays.set(rays);
      Object.assign(a, rest);
      // the network's activations after its last step, for the network view (changes nothing else)
      driveNetwork(a.net, a.inputs, this.mirrored, this.ctrl);
      return a;
    });
  }

  /** What a copy of this session needs after each generation to follow it (see followGeneration). */
  generationUpdate() {
    return {
      generation: this.generation,
      entry: { ...this.history[this.history.length - 1] },
      bestTimes: structuredClone(this.bestTimes),
      population: this.population.exportState(),
    };
  }

  /**
   * Follow a copy of this session that trains elsewhere (the Max-speed worker), one generation
   * at a time: take over its new population, best network, generation counter, chart history
   * and best times. The run in progress here no longer matches the population after that:
   * don't step it again before replacing this trainer with fromState(), or restarting the
   * generation with beginGeneration().
   */
  followGeneration(u) {
    if (u.generation <= this.generation) return;
    this.population = Population.fromState(u.population);
    this.generation = u.generation;
    this.history.push({ ...u.entry });
    this.bestTimes = structuredClone(u.bestTimes);
  }

  /** Everything needed to continue later, as plain JSON. */
  exportBest() {
    const net = this.bestNet ?? this.population.genomes[0].net;
    return {
      format: NETWORK_FORMAT,
      version: NETWORK_FILE_VERSION,
      sensorVersion: SENSOR_VERSION,
      inputs: INPUT_LABELS,
      savedAt: new Date().toISOString(),
      generation: this.generation,
      fitness: this.bestFitness,
      trainedOn: this.tracks.map((t) => t.id),
      settings: { populationSize: this.cfg.populationSize, mutationRate: this.cfg.mutationRate, laps: this.cfg.laps, walls: this.cfg.walls },
      bestTimes: this.bestTimes,
      history: this.history.slice(-500),
      network: net.toJSON(),
    };
  }
}

/** Wrap a bare network (e.g. one loaded from a minimal file) in the current file format. */
export function networkFile(net, meta = {}) {
  return {
    format: NETWORK_FORMAT,
    version: NETWORK_FILE_VERSION,
    sensorVersion: SENSOR_VERSION,
    inputs: INPUT_LABELS,
    ...meta,
    network: net.toJSON(),
  };
}

/**
 * Parse a saved network file (as produced by exportBest, or a bare
 * {sizes, weights, biases} network). Throws an Error with a message meant
 * for the player when the file can't drive this version of the game.
 */
export function parseNetworkFile(json) {
  const obj = typeof json === 'string' ? JSON.parse(json) : json;
  if (!obj || typeof obj !== 'object') throw new Error('Not a network file');
  const net = NeuralNetwork.fromJSON(obj.network ?? obj);
  const nIn = net.sizes[0], nOut = net.sizes[net.sizes.length - 1];
  const oldFile = (typeof obj.version === 'number' && obj.version < NETWORK_FILE_VERSION) ||
    (typeof obj.sensorVersion === 'number' && obj.sensorVersion !== SENSOR_VERSION);
  if (nIn !== INPUT_COUNT || nOut !== OUTPUT_COUNT || oldFile) {
    if (oldFile || nIn === 11) {
      throw new Error(`This network was trained for Track Rush v1 (${nIn} inputs). v2 has new car physics and ` +
        `${INPUT_COUNT} inputs, so v1 networks can't drive it. Train a new one on the training screen.`);
    }
    throw new Error(`This network has ${nIn} inputs and ${nOut} outputs; Track Rush v2 needs ${INPUT_COUNT} inputs and ${OUTPUT_COUNT} outputs.`);
  }
  return { net, meta: obj };
}
