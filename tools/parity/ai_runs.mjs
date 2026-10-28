// AI parity, JS side: runs one generation of the browser game's Trainer (web/src/ai/trainer.js:
// sensors, mirrored network, car physics, race, fitness and elimination rules) on populations
// made by a seeded generator (no Math.random), for tools/parity/check_ai.gd.
//   node tools/parity/ai_runs.mjs <out-prefix> [network.json]
// writes <out-prefix>.json (scenarios: tracks, rules, the population's weights, every track
// run's per-car fitness, deaths and wall count, the generation's {best, avg} and best times)
// and <out-prefix>.bin (Float64 samples: every 10th step, every car alive before it:
// scenario, run, step, car index, the whole car state BEFORE the step (KEYS below),
// the 18 inputs the car sensed and the 2 controls its network gave).
// network.json (a saved network file): scenarios whose population is that network plus
// seeded mutations, so cars finish (laps, finish times, the cut-off rule).
import { readFileSync, writeFileSync } from 'node:fs';
import { stringifyHex } from './hexjson.mjs';
const web = new URL('../../web/', import.meta.url);
const { TRACKS } = await import(new URL('src/tracks/trackData.js', web));
const { buildTrack } = await import(new URL('src/tracks/trackBuilder.js', web));
const { Trainer, parseNetworkFile } = await import(new URL('src/ai/trainer.js', web));
const { netParams, paramCount } = await import(new URL('src/ai/genetic.js', web));

const out = process.argv[2] ?? '/tmp/ai_runs';
const netFile = process.argv[3];
// = Car.STATE_KEYS in sim/car.gd (car_runs.mjs KEYS; not imported: that file runs on import)
const KEYS = [
  'x', 'y', 'z', 'vx', 'vy', 'vz', 'yaw', 'speed', 'forwardSpeed', 'sideSpeed',
  'grounded', 'airTime', 'drifting', 'idx', 'lat', 'bank', 'groundY', 'prog', 'laps',
  'hitWall', 'wallHits', 'steer', 'throttle',
  'yawRate', 'steerAngle', 'pitch', 'roll', 'rpm', 'gear', 'braking', 'slip', 'wheelRot',
  'wallImpact', 'wallScrape', 'wallX', 'wallY', 'wallZ', 'wallNx', 'wallNz',
  'nitro', 'boost', 'boosting',
  '_sc', '_ax', '_ay', '_fyr', '_shift', '_gear', '_pitchV', '_rollV',
  '_t', '_nx', '_nz', '_hw', '_ground', '_slipF', '_slipR', '_tcCut', '_hb', '_escOff', '_airRs', '_wallT',
  '_wallNow', '_rubT',
];
const tracks = Object.fromEntries(TRACKS.map((d) => [d.id, buildTrack(d)]));
const mulberry = (seed) => () => {
  seed = (seed + 0x6d2b79f5) | 0;
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};
const gauss = (rnd) => {
  let u = 0, v = 0;
  while (u === 0) u = rnd();
  while (v === 0) v = rnd();
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
};

/** Random networks like NeuralNetwork's constructor, from a seeded generator. */
function randomParams(sizes, n, seed) {
  const rnd = mulberry(seed);
  const per = paramCount(sizes);
  const p = new Float32Array(per * n);
  let o = 0;
  for (let k = 0; k < n; k++) {
    for (let l = 0; l < sizes.length - 1; l++) {
      const scale = 1 / Math.sqrt(sizes[l]);
      for (let w = 0; w < sizes[l] * sizes[l + 1]; w++) p[o++] = gauss(rnd) * scale * 1.5;
      for (let b = 0; b < sizes[l + 1]; b++) p[o++] = gauss(rnd) * 0.2;
    }
  }
  return p;
}

/** A trained network and n - 1 seeded mutations of it (rate 0.1, amount 0.5, like mutate()). */
function mutatedParams(net, n, seed) {
  const rnd = mulberry(seed);
  const base = netParams(net);
  const p = new Float32Array(base.length * n);
  for (let k = 0; k < n; k++) {
    p.set(base, k * base.length);
    if (k === 0) continue;
    for (let i = k * base.length; i < (k + 1) * base.length; i++) {
      if (rnd() < 0.1) p[i] = Math.max(-5, Math.min(5, p[i] + gauss(rnd) * 0.5));
    }
  }
  return p;
}

const scenarios = [
  { tracks: ['rookie-oval'], walls: 'ride', laps: 1, n: 20, seed: 1 },
  { tracks: ['hairpin-valley'], walls: 'crash', laps: 1, n: 20, seed: 2 },
  { tracks: ['ramp-rally', 'seaside-stunts'], walls: 'ride', laps: 1, n: 12, seed: 3 },
];
let trained = null;
if (netFile) {
  trained = parseNetworkFile(readFileSync(netFile, 'utf8')).net;
  scenarios.push({ tracks: ['rookie-oval'], walls: 'ride', laps: 2, n: 24, seed: 4, trained: true });
  scenarios.push({ tracks: ['hairpin-valley', 'technical-trial'], walls: 'crash', laps: 1, n: 16, seed: 5, trained: true });
  scenarios.push({ tracks: ['canyon-run'], walls: 'ride', laps: 1, n: 16, seed: 6, trained: true });
}

const samples = [];
const result = [];
scenarios.forEach((sc, si) => {
  const sizes = trained && sc.trained ? trained.sizes.slice() : [18, 12, 2];
  const params = sc.trained ? mutatedParams(trained, sc.n, sc.seed) : randomParams(sizes, sc.n, sc.seed);
  const state = {
    tracks: sc.tracks,
    settings: { populationSize: sc.n, mutationRate: 0.1, hidden: sizes.slice(1, -1), laps: sc.laps, walls: sc.walls },
    generation: 0, history: [], bestTimes: {},
    population: { sizes, mutationRate: 0.1, params: params.slice(), fitness: new Float64Array(sc.n), bestEver: null },
    run: null,
  };
  const tr = Trainer.fromState(state, Object.values(tracks));
  const rec = { ...sc, sizes, params: Array.from(params), runs: [], entry: null, bestTimes: null };
  let steps = 0;
  let run = 0;
  tr.onRunEnd = (track, deaths) => {
    rec.runs.push({
      track: track.id, steps, simTime: tr.simTime,
      fitness: tr.agents.map((a) => a.fitness), reasons: tr.agents.map((a) => a.deathReason),
      deaths: { ...deaths }, wallCars: tr.wallCars,
    });
    steps = 0;
    run++;
  };
  tr.onGeneration = (entry) => { rec.entry = { ...entry }; };
  const t0 = Date.now();
  while (tr.generation === 0) {
    const sample = steps % 10 === 0;
    let before = null;
    if (sample) before = tr.agents.filter((a) => a.alive).map((a) => ({ a, state: KEYS.map((k) => +a.car[k]) }));
    const r = run, s0 = steps; // (onRunEnd resets steps inside the run's last step)
    tr.step(1 / 60);
    steps++;
    if (sample) {
      for (const { a, state: st } of before) {
        const outL = a.net.acts[a.net.acts.length - 1];
        samples.push(si, r, s0, a.index, ...st, ...a.inputs, outL[0], outL[1]);
      }
    }
  }
  rec.bestTimes = JSON.parse(JSON.stringify(tr.bestTimes));
  result.push(rec);
  console.log(`scenario ${si}: ${sc.tracks.join('+')} walls ${sc.walls} laps ${sc.laps} n ${sc.n}: ` +
    `${rec.runs.map((r) => `${r.track} ${r.steps} steps ${JSON.stringify(r.deaths)}`).join('; ')}; best ${rec.entry.best.toFixed(1)} ` +
    `avg ${rec.entry.avg.toFixed(1)} times ${JSON.stringify(rec.bestTimes)} (${Date.now() - t0} ms)`);
});
const per = 4 + KEYS.length + 18 + 2;
writeFileSync(`${out}.json`, stringifyHex({ keys: KEYS, per, scenarios: result }));
writeFileSync(`${out}.bin`, Buffer.from(new Float64Array(samples).buffer));
console.log(`wrote ${out}.json and ${out}.bin (${samples.length / per} samples)`);
