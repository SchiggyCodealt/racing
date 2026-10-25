/**
 * headlessTrain.mjs — train without a browser (handy for long runs).
 *
 *   node tools/headlessTrain.mjs [trackIds,comma,separated] [generations] [out.json] [seed.json] [options]
 *   node tools/headlessTrain.mjs rookie-oval,hairpin-valley 100 my-driver.json
 *
 * Options:
 *   --pop N          population size (default 80)
 *   --hidden 12      hidden layer size(s), e.g. 16,8
 *   --mutation 0.1   mutation rate
 *   --laps 1         laps per circuit run
 *   --walls ride     'ride' (cars keep going after a wall hit) or 'crash' (a wall hit puts the car out)
 *   --stop-after N   stop N generations after every track has been finished
 *   --quiet          only print every 10th generation
 *
 * The output file is the same format as "Save best network" in the browser,
 * so you can load it there to watch it drive or keep training. It is written
 * whenever the best network improves, so you can stop the run at any time.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { TRACKS } from '../src/tracks/trackData.js';
import { buildTrack, raceLength } from '../src/tracks/trackBuilder.js';
import { Trainer, parseNetworkFile, DEFAULT_TRAINING, WALL_RULES, savedWallRule } from '../src/ai/trainer.js';
import { formatTime } from '../src/game/race.js';

const pos = [];
const opt = {};
for (let k = 2; k < process.argv.length; k++) {
  const a = process.argv[k];
  if (a.startsWith('--')) {
    const key = a.slice(2);
    if (key === 'quiet') opt.quiet = true;
    else opt[key] = process.argv[++k];
  } else pos.push(a);
}
const ids = (pos[0] ?? 'rookie-oval').split(',');
const gens = Number(pos[1] ?? 30);
const outFile = pos[2] ?? 'best-network.json';
const seedFile = pos[3];

const tracks = ids.map((id) => {
  const def = TRACKS.find((t) => t.id === id);
  if (!def) throw new Error(`Unknown track "${id}". Known: ${TRACKS.map((t) => t.id).join(', ')}`);
  return buildTrack(def);
});

if (opt.walls != null && !Object.hasOwn(WALL_RULES, opt.walls)) {
  throw new Error(`--walls must be one of: ${Object.keys(WALL_RULES).join(', ')} (got "${opt.walls}")`);
}

let seed = null, seedMeta = null;
if (seedFile) ({ net: seed, meta: seedMeta } = parseNetworkFile(readFileSync(seedFile, 'utf8')));

const cfg = {
  tracks,
  populationSize: Number(opt.pop ?? DEFAULT_TRAINING.populationSize),
  mutationRate: Number(opt.mutation ?? DEFAULT_TRAINING.mutationRate),
  hidden: opt.hidden ? String(opt.hidden).split(',').map(Number) : DEFAULT_TRAINING.hidden,
  laps: Number(opt.laps ?? DEFAULT_TRAINING.laps),
  walls: opt.walls ?? DEFAULT_TRAINING.walls,
  seed,
  seedMeta,
};
const trainer = new Trainer(cfg);
console.log(`training a ${trainer.sizes.join('-')} network, population ${cfg.populationSize}, mutation ${cfg.mutationRate}, ` +
  `${cfg.laps} lap(s) per circuit, walls: ${trainer.cfg.walls}, on ${tracks.map((t) => `${t.id} (${(raceLength(t, 1) / 1000).toFixed(2)} km${t.closed ? '/lap' : ''})`).join(', ')}`);
const seedRule = savedWallRule(seedMeta);
if (seedRule && seedRule !== trainer.cfg.walls) {
  console.log(`note: ${seedFile} was trained with walls: ${seedRule}; this run uses walls: ${trainer.cfg.walls}, ` +
    `so its old best fitness doesn't carry over (pass --walls ${seedRule} to keep its rule)`);
}

const dt = 1 / 60;
const t0 = Date.now();
const firstFinish = {};
let allFinishedAt = null;
let saved = -Infinity;
let deaths = {};
let wallCars = 0;
trainer.onRunEnd = (track, d) => {
  for (const [k, v] of Object.entries(d)) deaths[k] = (deaths[k] ?? 0) + v;
  wallCars += trainer.wallCars;
};
trainer.onGeneration = (s) => {
  for (const t of tracks) if (firstFinish[t.id] == null && trainer.bestTimes[t.id]?.finish != null) firstFinish[t.id] = s.gen;
  if (allFinishedAt == null && tracks.every((t) => firstFinish[t.id] != null)) allFinishedAt = s.gen;
  if (trainer.bestFitness > saved) {
    saved = trainer.bestFitness;
    writeFileSync(outFile, JSON.stringify(trainer.exportBest()));
  }
  if (!opt.quiet || s.gen % 10 === 0 || s.gen === allFinishedAt) {
    const times = tracks.map((t) => {
      const r = trainer.bestTimes[t.id];
      return `${t.id}: ${t.closed ? `lap ${formatTime(r?.lap)} ` : ''}finish ${formatTime(r?.finish)}`;
    }).join('  ');
    const out = Object.entries(deaths).map(([k, v]) => `${k} ${v}`).join(', ');
    const walls = trainer.cfg.walls === 'ride' ? `, ${wallCars} touched a wall` : '';
    console.log(`gen ${s.gen}  best ${s.best.toFixed(0)}  avg ${s.avg.toFixed(0)}  ${times}  [cars: ${out}${walls}]  (${((Date.now() - t0) / 1000).toFixed(1)} s)`);
  }
  deaths = {};
  wallCars = 0;
};
const target = trainer.generation + gens;
const stopAfter = opt['stop-after'] != null ? Number(opt['stop-after']) : Infinity;
while (trainer.generation < target && !(allFinishedAt != null && trainer.generation > allFinishedAt + stopAfter)) trainer.step(dt);
writeFileSync(outFile, JSON.stringify(trainer.exportBest()));
for (const t of tracks) {
  const r = trainer.bestTimes[t.id];
  console.log(`${t.id}: first finish in generation ${firstFinish[t.id] ?? 'none'}, best ${t.closed ? `lap ${formatTime(r?.lap)}, ` : ''}finish ${formatTime(r?.finish)}`);
}
console.log(`saved ${outFile} (generation ${trainer.generation}, best fitness ${trainer.bestFitness.toFixed(0)}, ${((Date.now() - t0) / 1000).toFixed(0)} s)`);
