/**
 * medals.mjs — computes the medal times of every built-in track for every
 * car (author, gold, silver and bronze, like Trackmania) and writes
 * src/tracks/medals.js.
 *
 *   node tools/medals.mjs           run the sweep, print a table, write medals.js
 *   node tools/medals.mjs --check   run the sweep and compare with medals.js;
 *                                   writes nothing, exits 1 when it is out of date
 *   --jobs=N                        sweep on N threads (default: one per CPU core,
 *                                   at most 4; --jobs=1 runs in this thread). The
 *                                   result is the same whatever N is.
 *
 * Re-run it (`npm run medals`) after changing the car physics (and
 * PHYSICS_VERSION in src/physics/car.js), a car's spec (src/physics/cars.js),
 * the scoring rules (src/game/score.js: its points refill the nitro; bump
 * SCORE_RULES there), a track or its laps. The game shows no medals for a
 * track whose layout, laps, physics or scoring rules no longer match
 * medals.js, and `npm test` fails until it is regenerated.
 *
 * The race is exactly the one the player drives in Drive (PlayMode), with
 * each car of src/physics/cars.js: circuits over all their laps
 * (track.laps), sprints from start to finish, from a standing start at GO
 * with a full nitro tank, 60 Hz physics: stepCar, RaceState.update, then the
 * style score (ScoreState, src/game/score.js), whose banked points refill
 * the nitro tank as they do for the player.
 *
 * Author time: the best finish of a deterministic sweep of a look-ahead
 * autopilot (makeAutopilot below, the same kind of driver npm test sends round
 * every track). It plans a speed for every sample of road from the curvature,
 * brakes for the corners ahead at DECEL m/s², steers at a point on the
 * centre line ahead and burns nitro on the straights (whenever it is at full
 * throttle with the wheel within NITRO_STEER of straight). Two cornering
 * settings are swept over GRID:
 *   aLat   the sideways grip (m/s²) it plans corner speeds for: low is
 *          cautious, high goes into corners too fast, slides and uses the walls
 *   lookK  how far ahead it aims: 6 m + lookK × speed, at most 80 m. The
 *          further ahead, the more it cuts across corners (a simple racing line)
 * (The braking rate made little difference: 9-13 m/s² moved the times by
 * about 0.2 %, against several % for these two, so it is fixed.)
 * Every run that finishes counts, wall touches or not: the player may use the
 * walls too (a wall contact costs points, though, so less nitro comes back).
 * A run that gains no ground for 3 s (stuck) or takes longer than 15 min
 * doesn't. The fastest run wins (the first in grid order on a tie); its time
 * to the millisecond, as the HUD shows it, is the author time. Then
 *   gold = author × 1.06, silver = author × 1.2, bronze = author × 1.5,
 * each rounded up to a whole second.
 *
 * The autopilot only follows the centre line and burns nitro the simple way,
 * so a player who drives a real racing line can beat the author time; gold
 * is meant to take practice.
 */
import { readFileSync, writeFileSync, realpathSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { Worker, isMainThread, parentPort, workerData } from 'node:worker_threads';
import os from 'node:os';
import { TRACKS } from '../src/tracks/trackData.js';
import { buildTrack, raceLength } from '../src/tracks/trackBuilder.js';
import { createCar, stepCar, PHYSICS_VERSION } from '../src/physics/car.js';
import { CAR_IDS, DEFAULT_CAR, getCar } from '../src/physics/cars.js';
import { RaceState, formatTime } from '../src/game/race.js';
import { ScoreState, SCORE_RULES } from '../src/game/score.js';

const dt = 1 / 60;
export const DECEL = 11;                     // m/s², the braking the autopilot plans with
export const GRID = {
  aLat: [14, 16, 18, 20, 22, 24, 26, 28, 32, 40],
  lookK: [0.35, 0.55, 0.75, 1, 1.3],
};
export const FACTORS = { gold: 1.06, silver: 1.2, bronze: 1.5 };
export const NITRO_STEER = 0.25;             // the autopilot burns nitro at full throttle with |steer| below this
const LOOK_MAX = 80;                         // m, the furthest the autopilot aims
const STUCK_STEPS = 180;                     // 3 s without gaining 3 samples (~6 m): stuck, the run doesn't count
const MAX_STEPS = 60 * 60 * 15;              // 15 min

const wrap = (a) => Math.atan2(Math.sin(a), Math.cos(a));

/**
 * The sweep's autopilot for one setting: (car) => controls. With `nitro` it
 * holds the nitro on the straights (full throttle, wheel nearly straight);
 * without, ctrl.nitro stays false.
 */
export function makeAutopilot(track, { aLat, lookK, decel = DECEL, nitro = false }) {
  const N = track.count, closed = track.closed;
  const at = (i) => (closed ? ((i % N) + N) % N : Math.max(0, Math.min(N - 1, i)));
  // speed target per sample: corner speed from the heading change over ±3 samples,
  // then lowered backwards from every corner so the car can brake down to it
  const vt = new Float64Array(N);
  for (let i = 0; i < N; i++) {
    const a = at(i - 3), b = at(i + 3);
    const turn = Math.abs(wrap(Math.atan2(track.tx[b], track.tz[b]) - Math.atan2(track.tx[a], track.tz[a])));
    vt[i] = Math.min(100, Math.sqrt(aLat * (turn > 1e-4 ? (6 * track.segLen) / turn : 1e4)));
  }
  for (let pass = 0; pass < (closed ? 2 : 1); pass++) {
    for (let i = N - 1; i >= 0; i--) {
      const j = closed ? (i + 1) % N : i + 1;
      if (j < N) vt[i] = Math.min(vt[i], Math.sqrt(vt[j] * vt[j] + 2 * decel * track.segLen));
    }
  }
  const maxLook = Math.round(LOOK_MAX / track.segLen);
  const ctrl = { steer: 0, throttle: 0, handbrake: false, nitro: false };
  return (car) => {
    const look = Math.max(3, Math.min(maxLook, Math.round((6 + car.speed * lookK) / track.segLen)));
    const i = at(car.idx + look);
    const gx = track.px[i] - car.x, gz = track.pz[i] - car.z;
    const fx = Math.sin(car.yaw), fz = Math.cos(car.yaw);
    ctrl.steer = Math.max(-1, Math.min(1, 3 * Math.atan2(gx * fz - gz * fx, gx * fx + gz * fz)));
    const target = vt[at(car.idx + 1)];
    ctrl.throttle = car.speed < target - 1 ? 1 : car.speed > target + 1.5 ? -1 : 0.3;
    ctrl.nitro = nitro && ctrl.throttle === 1 && Math.abs(ctrl.steer) < NITRO_STEER;
    return ctrl;
  };
}

/**
 * One Drive race with one autopilot setting and car `carId` (cars.js), burning
 * nitro on the straights with the score's refills (opts.nitro false: no nitro,
 * no score). Returns {finished, time, steps, wall (steps touching a wall), laps,
 * score (points), burned, refilled (nitro, in tanks)}.
 */
export function driveRace(track, setting, carId = DEFAULT_CAR, { nitro = true } = {}) {
  const car = createCar(track, track.startIdx, getCar(carId).spec), race = new RaceState(track);
  const drive = makeAutopilot(track, { ...setting, nitro });
  const score = nitro ? new ScoreState(track, { nitro: true }) : null;
  let steps = 0, wall = 0, best = car.prog, gained = 0, burned = 0;
  while (!race.finished && steps < MAX_STEPS && steps - gained <= STUCK_STEPS) {
    const tank = car.nitro;
    stepCar(car, track, drive(car), dt);
    if (car.nitro < tank) burned += tank - car.nitro;
    race.update(car, dt);
    score?.update(car, race, dt); // after race.update, as in PlayMode: banked points refill the tank
    steps++;
    if (car.hitWall) wall++;
    if (car.prog > best + 3) { best = car.prog; gained = steps; }
  }
  return {
    finished: race.finished, time: race.finishTime, steps, wall, laps: race.laps,
    score: score?.total ?? 0, burned, refilled: score?.nitro ?? 0,
  };
}

/** A track's layout fingerprint (the same as the ghosts' trackSignature in src/game/replay.js). */
export const layoutSig = (track) => `${track.count}:${Math.round(track.length)}`;

/** The medal times from an author time (s, to the ms): the others rounded up to a whole second. */
export function medalSet(author) {
  const up = (f) => Math.ceil(Math.round(author * f * 1000) / 1000); // ms first, so 132.0000001 stays 132
  return { author, gold: up(FACTORS.gold), silver: up(FACTORS.silver), bronze: up(FACTORS.bronze) };
}

/**
 * Sweep one track with one car: {runs, finished, entry (for medals.js; null
 * when no run finished), best (the winning run, for the table)}.
 */
export function carMedals(track, carId) {
  let best = null, finished = 0, runs = 0;
  for (const lookK of GRID.lookK) {
    for (const aLat of GRID.aLat) {
      const r = driveRace(track, { aLat, lookK }, carId);
      runs++;
      if (!r.finished) continue;
      finished++;
      if (!best || r.steps < best.steps) best = { ...r, aLat, lookK };
    }
  }
  if (!best) return { runs, finished, entry: null, best };
  const author = Math.round(best.time * 1000) / 1000; // what the HUD shows for that run
  return {
    runs, finished, best,
    entry: { ...medalSet(author), run: { aLat: best.aLat, lookK: best.lookK, steps: best.steps, wallSteps: best.wall } },
  };
}

// ---- medals.js -----------------------------------------------------------------------
function medalsJS(results) {
  const rows = results.map(({ track, laps, cars }) =>
    `  '${track.id}': { laps: ${laps}, sig: '${layoutSig(track)}', cars: { // ${track.name}\n` +
    CAR_IDS.map((id) => {
      const e = cars[id];
      return `    ${id}: { author: ${e.author}, gold: ${e.gold}, silver: ${e.silver}, bronze: ${e.bronze}, ` +
        `run: { aLat: ${e.run.aLat}, lookK: ${e.run.lookK}, steps: ${e.run.steps}, wallSteps: ${e.run.wallSteps} } },`;
    }).join('\n') + '\n  } },');
  return `/**
 * medals.js
 * ------------------------------------------------------------------
 * GENERATED by tools/medals.mjs (npm run medals): don't edit by hand.
 * Re-run it after changing the physics, a car, the scoring rules, a track
 * or its laps.
 *
 * Medal times (seconds) for the race driven in Drive on each track with
 * each car (v4: per car): circuits over all their laps, sprints start to
 * finish, nitro burned on the straights and refilled by the style score's
 * points (src/game/score.js), as it is for the player.
 *   author  the fastest finish of a deterministic sweep of a look-ahead
 *           autopilot over two cornering settings (MEDAL_METHOD)
 *   gold    author × ${FACTORS.gold}, rounded up to a whole second
 *   silver  author × ${FACTORS.silver}, rounded up
 *   bronze  author × ${FACTORS.bronze}, rounded up
 * run: the winning setting, its race length in physics steps and how many
 * of them touched a wall (npm test drives some again and expects the same time).
 * A time earns a medal when it is no slower, to the millisecond the HUD shows.
 * Medals only apply to the layout (sig), laps, physics and scoring rules
 * they were made for.
 */
import { PHYSICS_VERSION } from '../physics/car.js';
import { DEFAULT_CAR } from '../physics/cars.js';
import { SCORE_RULES } from '../game/score.js';

export const MEDALS_PHYSICS = ${PHYSICS_VERSION};
export const MEDALS_SCORE_RULES = ${SCORE_RULES}; // the nitro refills depend on the scoring rules
export const MEDAL_METHOD = 'author: fastest finish of the look-ahead autopilot in tools/medals.mjs over aLat ' +
  '${GRID.aLat.join('/')} m/s² × lookK ${GRID.lookK.join('/')} (braking ${DECEL} m/s², aim at most ${LOOK_MAX} m ahead), ' +
  'nitro at full throttle with |steer| < ${NITRO_STEER}, refilled by the style score; wall touches allowed; ' +
  'gold/silver/bronze = author × ${FACTORS.gold}/${FACTORS.silver}/${FACTORS.bronze}, rounded up to a whole second';

export const MEDALS = {
${rows.join('\n')}
};

/** Best first. */
export const MEDAL_ORDER = ['author', 'gold', 'silver', 'bronze'];
export const MEDAL_NAMES = { author: 'Author', gold: 'Gold', silver: 'Silver', bronze: 'Bronze' };

/**
 * A track's medal times {author, gold, silver, bronze} with car \`car\` (an id
 * from src/physics/cars.js) for a race of \`laps\` laps, or null (none made
 * for this car, layout, these laps, this physics or these scoring rules).
 */
export function medalTimes(track, car = DEFAULT_CAR, laps = track.laps) {
  const m = MEDALS[track.id];
  const sig = \`\${track.count}:\${Math.round(track.length)}\`;
  const fits = m && MEDALS_PHYSICS === PHYSICS_VERSION && MEDALS_SCORE_RULES === SCORE_RULES &&
    m.sig === sig && m.laps === (track.closed ? laps : 1);
  return fits && Object.hasOwn(m.cars, car) ? m.cars[car] : null;
}

const ms = (t) => Math.round(t * 1000);

/** The medal a time earns ('author' | 'gold' | 'silver' | 'bronze'), or null (none, or no time / medal times). */
export function medalFor(medals, time) {
  if (!medals || !(time > 0)) return null;
  return MEDAL_ORDER.find((m) => ms(time) <= ms(medals[m])) ?? null;
}

/**
 * The next medal to aim for with a best time of \`time\` (null: none yet):
 * {medal, time}, or null when the author medal is already won (or no medals).
 */
export function nextMedal(medals, time) {
  if (!medals) return null;
  const got = medalFor(medals, time);
  const k = got ? MEDAL_ORDER.indexOf(got) - 1 : MEDAL_ORDER.length - 1;
  return k >= 0 ? { medal: MEDAL_ORDER[k], time: medals[MEDAL_ORDER[k]] } : null;
}
`;
}

// ---- the sweep, on worker threads -----------------------------------------------------------
const built = new Map(); // track index -> built track (each thread builds its own)
const trackAt = (ti) => built.get(ti) ?? built.set(ti, buildTrack(TRACKS[ti])).get(ti);

/** Every track × car, longest races first (so the threads finish together): [{ti, car}]. */
function jobList() {
  const jobs = [];
  TRACKS.forEach((def, ti) => { for (const car of CAR_IDS) jobs.push({ ti, car, km: raceLength(trackAt(ti), trackAt(ti).laps) }); });
  return jobs.sort((a, b) => b.km - a.km).map(({ ti, car }) => ({ ti, car }));
}

/** carMedals for every track × car on `threads` worker threads (1: in this thread): {'<track index> <car>': result}. */
async function sweep(threads) {
  const jobs = jobList(), out = {};
  if (threads <= 1) {
    for (const { ti, car } of jobs) out[`${ti} ${car}`] = carMedals(trackAt(ti), car);
    return out;
  }
  await Promise.all(Array.from({ length: threads }, () => new Promise((resolve, reject) => {
    const w = new Worker(new URL(import.meta.url), { workerData: { medalSweep: true } });
    const next = () => {
      const job = jobs.shift();
      if (job) w.postMessage(job);
      else w.terminate().then(resolve, resolve);
    };
    w.on('message', ({ ti, car, r }) => { out[`${ti} ${car}`] = r; next(); });
    w.on('error', reject);
    w.on('online', next);
  })));
  return out;
}

// a sweep thread: one job ({ti, car}) per message
if (!isMainThread && workerData?.medalSweep) {
  parentPort.on('message', ({ ti, car }) => parentPort.postMessage({ ti, car, r: carMedals(trackAt(ti), car) }));
}

// run main() only when executed directly (selfTest imports driveRace), as in generateTracks.mjs
const invokedAs = (() => { try { return pathToFileURL(realpathSync(process.argv[1] ?? '')).href; } catch { return ''; } })();
if (isMainThread && import.meta.url === invokedAs) main();

async function main() {
  const CHECK = process.argv.includes('--check');
  const jobsArg = process.argv.find((a) => a.startsWith('--jobs='));
  const cores = os.availableParallelism?.() ?? os.cpus().length;
  const threads = Math.max(1, Math.min(16, jobsArg ? parseInt(jobsArg.slice(7), 10) || 1 : Math.min(4, cores)));
  const t0 = performance.now();
  console.log(`physics v${PHYSICS_VERSION}, scoring rules v${SCORE_RULES}; ${CAR_IDS.length} cars × ${TRACKS.length} tracks × ` +
    `${GRID.aLat.length * GRID.lookK.length} autopilot settings, nitro on the straights with the score's refills; ` +
    `${threads} thread${threads > 1 ? 's' : ''}\n`);
  const done = await sweep(threads);
  console.log(`${'track'.padEnd(16)} ${'race'.padEnd(7)} ${'car'.padEnd(8)} finished  author     (setting, wall steps)       ` +
    `nitro burned / refilled   gold      silver    bronze`);
  const results = [];
  let missing = false;
  TRACKS.forEach((def, ti) => {
    const track = trackAt(ti), cars = {};
    CAR_IDS.forEach((id, k) => {
      const r = done[`${ti} ${id}`], e = r.entry;
      const head = `${(k ? '' : track.id).padEnd(16)} ${(k ? '' : track.closed ? `${track.laps} laps` : 'sprint').padEnd(7)} ${id.padEnd(8)}`;
      if (!e) { console.log(`${head} no run finished`); missing = true; return; }
      cars[id] = e;
      console.log(`${head} ${String(r.finished).padStart(2)}/${r.runs}    ` +
        `${formatTime(e.author)}  (aLat ${e.run.aLat}, lookK ${e.run.lookK}, ${e.run.wallSteps})`.padEnd(37) +
        `${r.best.burned.toFixed(2).padStart(5)} / ${r.best.refilled.toFixed(2).padStart(4)} tanks      ` +
        `${formatTime(e.gold)}  ${formatTime(e.silver)}  ${formatTime(e.bronze)}`);
    });
    results.push({ track, laps: track.closed ? track.laps : 1, cars });
  });
  console.log(`\n${((performance.now() - t0) / 1000).toFixed(1)} s`);
  if (missing) {
    console.log('a track has no finishing run with some car: medals.js NOT written');
    process.exit(1);
  }
  const out = medalsJS(results);
  const file = new URL('../src/tracks/medals.js', import.meta.url);
  if (CHECK) {
    let old = '';
    try { old = readFileSync(file, 'utf8'); } catch { /* missing */ }
    console.log(old === out ? 'src/tracks/medals.js is up to date' : 'src/tracks/medals.js is OUT OF DATE: run npm run medals');
    process.exit(old === out ? 0 : 1);
  }
  writeFileSync(file, out);
  console.log('wrote src/tracks/medals.js');
}
