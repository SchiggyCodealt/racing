// AI training speed, JS side: one generation of the browser game's Trainer (what its Max
// speed runs in a Web Worker) on a fixed population, timed; writes the population for
// tools/parity/ai_bench.gd, which times the Godot paths on the same networks.
//   node tools/parity/ai_bench.mjs <out.json> <network.json> [cars=80] [tracks=rookie-oval,...] [walls=ride]
// The population is the network plus seeded mutations (so most cars drive a long way, like a
// population after a few generations). Prints car steps per second (one car through one
// step: sensors, network, physics, rules) and the real-time factor (simulated seconds per
// second of wall-clock time for the whole population).
import { readFileSync, writeFileSync } from 'node:fs';
import { stringifyHex } from './hexjson.mjs';
const web = new URL('../../web/', import.meta.url);
const { TRACKS } = await import(new URL('src/tracks/trackData.js', web));
const { buildTrack } = await import(new URL('src/tracks/trackBuilder.js', web));
const { Trainer, parseNetworkFile } = await import(new URL('src/ai/trainer.js', web));
const { netParams } = await import(new URL('src/ai/genetic.js', web));

const [outFile, netFile] = process.argv.slice(2, 4);
const n = Number(process.argv[4] ?? 80);
const ids = (process.argv[5] ?? 'rookie-oval,hairpin-valley,technical-trial,canyon-run').split(',');
const walls = process.argv[6] ?? 'ride';
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
const net = parseNetworkFile(readFileSync(netFile, 'utf8')).net;
const base = netParams(net);
const rnd = mulberry(99);
const params = new Float32Array(base.length * n);
for (let k = 0; k < n; k++) {
  params.set(base, k * base.length);
  if (k === 0) continue;
  for (let i = k * base.length; i < (k + 1) * base.length; i++) {
    if (rnd() < 0.1) params[i] = Math.max(-5, Math.min(5, params[i] + gauss(rnd) * 0.5));
  }
}
const tracks = TRACKS.map((d) => buildTrack(d));
const state = {
  tracks: ids,
  settings: { populationSize: n, mutationRate: 0.1, hidden: net.sizes.slice(1, -1), laps: 1, walls },
  generation: 0, history: [], bestTimes: {},
  population: { sizes: net.sizes.slice(), mutationRate: 0.1, params: params.slice(), fitness: new Float64Array(n), bestEver: null },
  run: null,
};
const tr = Trainer.fromState(state, tracks);
let steps = 0, carSteps = 0;
const t0 = performance.now();
while (tr.generation === 0) {
  for (const a of tr.agents) if (a.alive) carSteps++;
  tr.step(1 / 60);
  steps++;
}
const secs = (performance.now() - t0) / 1000;
console.log(`JS (node ${process.version}): ${n} cars, ${ids.join('+')}, walls ${walls}: ${steps} steps, ${carSteps} car steps in ` +
  `${secs.toFixed(2)} s = ${(carSteps / secs).toFixed(0)} car steps/s, ${(steps / 60 / secs).toFixed(1)}x real time; ` +
  `generation best ${tr.history[0].best.toFixed(1)} avg ${tr.history[0].avg.toFixed(1)}`);
writeFileSync(outFile, stringifyHex({ tracks: ids, walls, n, sizes: net.sizes, params: Array.from(params), steps, carSteps, secs }));
