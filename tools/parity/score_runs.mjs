// Race + score parity, JS side: full races driven by the medal autopilot (nitro on, banked
// points refilling the tank, as in Drive) on every track with every car, plus random
// keyboard tapes with respawns to the last checkpoint; records every race and score event.
// Also formats a list of numbers with formatTime / formatDelta / formatPoints.
//   node tools/parity/score_runs.mjs <out.json>     (read by tools/parity/check_score.gd)
import { writeFileSync } from 'node:fs';
import { stringifyHex } from './hexjson.mjs';
const web = new URL('../../web/', import.meta.url);
const { TRACKS } = await import(new URL('src/tracks/trackData.js', web));
const { buildTrack } = await import(new URL('src/tracks/trackBuilder.js', web));
const { createCar, stepCar, placeCar } = await import(new URL('src/physics/car.js', web));
const { CAR_IDS, getCar } = await import(new URL('src/physics/cars.js', web));
const { RaceState, formatTime, formatDelta } = await import(new URL('src/game/race.js', web));
const { ScoreState, formatPoints } = await import(new URL('src/game/score.js', web));
const { makeAutopilot } = await import(new URL('tools/medals.mjs', web));

const dt = 1 / 60;
const mulberry = (seed) => () => {
  seed = (seed + 0x6d2b79f5) | 0;
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};
// the same tape as car_runs.mjs, with a throttle bias so the car gets round
const tape = (seed) => {
  const rnd = mulberry(seed), ctrl = { steer: 0, throttle: 0, handbrake: false, nitro: false };
  let hold = 0;
  return () => {
    if (--hold <= 0) {
      hold = 6 + Math.floor(rnd() * 54);
      ctrl.steer = [-1, 0, 1][Math.floor(rnd() * 3)] * (rnd() < 0.7 ? 1 : rnd());
      ctrl.throttle = Math.max(-1, Math.min(1, rnd() * 2.4 - 0.9));
      ctrl.handbrake = rnd() < 0.15;
      ctrl.nitro = rnd() < 0.2;
    }
    return ctrl;
  };
};

const runs = [];
let seed = 100;
for (const def of TRACKS) {
  const track = buildTrack(def);
  for (const carId of CAR_IDS) {
    for (const driver of ['auto', 'tape']) {
      if (driver === 'tape' && carId !== 'drifter' && carId !== 'racer') continue;
      const s = driver === 'tape' ? seed++ : 0;
      const car = createCar(track, track.startIdx, getCar(carId).spec), race = new RaceState(track), score = new ScoreState(track);
      const auto = makeAutopilot(track, { aLat: 24, lookK: 0.75, nitro: true });
      const rand = tape(s);
      const steps = driver === 'tape' ? 5400 : 54000;
      const events = [];
      let k = 0;
      for (; k < steps && !race.finished; k++) {
        // the tape alternates 3 s of autopilot and 2 s of random keys, and respawns every 15 s
        const ctrl = driver === 'auto' || k % 300 < 180 ? auto(car) : rand();
        stepCar(car, track, ctrl, dt);
        for (const e of race.update(car, dt) ?? []) events.push([k, 'race:' + e.kind, e.gateIndex]);
        for (const e of score.update(car, race, dt) ?? []) events.push([k, e.kind, e.points, e.mult ?? null, e.comboLost ?? null]);
        if (driver === 'tape' && k % 900 === 899 && race.respawn) {
          placeCar(car, track, race.respawn.idx, race.respawn);
          for (const e of score.respawn() ?? []) events.push([k, e.kind, e.points, null, e.comboLost ?? null]);
        }
      }
      runs.push({
        track: def.id, car: carId, driver, seed: s, steps: k, finished: race.finished, total: score.total, nitro: car.nitro,
        refilled: score.nitro, earned: score.nitroEarned, counts: score.counts, points: score.points, live: score.live,
        breakdown: score.breakdown(), events, splits: race.splits, lapTimes: race.lapTimes,
      });
    }
  }
}
const numbers = [0, 0.0625, 0.1875, 59.9995, 59.9994, 119.9996, 61.25, 3599.999, -0.0004, -1.5, 1e-9, 7.125, 0.3125, 123.4565, 1234.5678];
const formats = numbers.map((v) => [v, formatTime(v), formatDelta(v), formatPoints(v * 1000)]);
formats.push([null, formatTime(null), '', formatPoints(-1234567.5)]);
writeFileSync(process.argv[2], stringifyHex({ runs, formats }));
console.log(`${runs.length} runs, ${runs.reduce((a, r) => a + r.events.length, 0)} events`);
