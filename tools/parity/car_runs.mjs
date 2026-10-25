// Car physics parity, JS side: drives scenarios with the browser game's car.js and writes
// every step's controls and whole car state as raw float64 (exact), for
// tools/parity/check_cars.gd, which steps the GDScript car from the same states.
//   node tools/parity/car_runs.mjs <out-prefix>      writes <out-prefix>.json + <out-prefix>.bin
//   node tools/parity/car_runs.mjs <out-prefix> --races   also drives full races (finish steps)
// Scenarios: the medal autopilot (nitro on) on every track with the racer and on two tracks
// with every car; every car over the first kickers of the two jump tracks; seeded random
// keyboard-like controls (steer, throttle/brake/reverse, handbrake, nitro) on a narrow and a
// twisty track with every car (wall hits, drifts, reverse).
import { writeFileSync } from 'node:fs';
import { stringifyHex } from './hexjson.mjs';
const web = new URL('../../web/', import.meta.url);
const { TRACKS } = await import(new URL('src/tracks/trackData.js', web));
const { buildTrack } = await import(new URL('src/tracks/trackBuilder.js', web));
const { createCar, stepCar } = await import(new URL('src/physics/car.js', web));
const { CAR_IDS, getCar } = await import(new URL('src/physics/cars.js', web));
const { RaceState } = await import(new URL('src/game/race.js', web));
const { makeAutopilot } = await import(new URL('tools/medals.mjs', web));

// = Car.STATE_KEYS in sim/car.gd
export const KEYS = [
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
const dt = 1 / 60;
const tracks = Object.fromEntries(TRACKS.map((d) => [d.id, buildTrack(d)]));
const mulberry = (seed) => () => {
  seed = (seed + 0x6d2b79f5) | 0;
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};
const tape = (seed) => {
  const rnd = mulberry(seed), ctrl = { steer: 0, throttle: 0, handbrake: false, nitro: false };
  let hold = 0;
  return () => {
    if (--hold <= 0) {
      hold = 6 + Math.floor(rnd() * 54);
      ctrl.steer = [-1, 0, 1][Math.floor(rnd() * 3)] * (rnd() < 0.7 ? 1 : rnd()); // mostly keys, some analogue
      ctrl.throttle = Math.max(-1, Math.min(1, rnd() * 2.4 - 0.9));
      ctrl.handbrake = rnd() < 0.15;
      ctrl.nitro = rnd() < 0.2;
    }
    return ctrl;
  };
};

const scenarios = [];
for (const id of Object.keys(tracks)) scenarios.push({ name: `auto ${id} racer`, track: id, car: 'racer', driver: 'auto', steps: 1500 });
for (const id of ['hairpin-valley', 'canyon-run']) for (const car of CAR_IDS.slice(1)) scenarios.push({ name: `auto ${id} ${car}`, track: id, car, driver: 'auto', steps: 1500 });
for (const id of ['ramp-rally', 'seaside-stunts']) {
  const k = tracks[id].kickers[0];
  for (const car of CAR_IDS) scenarios.push({ name: `jump ${id} ${car}`, track: id, car, driver: 'auto', start: Math.max(0, k.foot - 100), steps: 900 });
}
let seed = 1;
for (const id of ['canyon-run', 'hairpin-valley']) for (const car of CAR_IDS) scenarios.push({ name: `tape ${id} ${car}`, track: id, car, driver: 'tape', seed: seed++, steps: 1500 });

const chunks = [];
let offset = 0;
for (const s of scenarios) {
  const track = tracks[s.track];
  const car = createCar(track, s.start ?? track.startIdx, getCar(s.car).spec);
  const drive = s.driver === 'auto' ? makeAutopilot(track, { aLat: 24, lookK: 0.75, nitro: true }) : tape(s.seed);
  const data = new Float64Array(KEYS.length + s.steps * (4 + KEYS.length));
  let p = 0;
  const put = () => { for (const k of KEYS) data[p++] = +car[k]; };
  put();
  let air = 0, wall = 0, hb = 0, boost = 0;
  for (let k = 0; k < s.steps; k++) {
    const c = drive(car);
    data[p++] = c.steer; data[p++] = c.throttle; data[p++] = c.handbrake ? 1 : 0; data[p++] = c.nitro === true ? 1 : +c.nitro || 0;
    stepCar(car, track, c, dt);
    put();
    if (!car.grounded) air++;
    if (car.hitWall) wall++;
    if (car._hb > 0) hb++;
    if (car.boosting) boost++;
  }
  Object.assign(s, { offset, count: data.length, air, wall, hb, boost });
  offset += data.length;
  chunks.push(data);
}

const races = [];
if (process.argv.includes('--races')) {
  for (const id of Object.keys(tracks)) {
    for (const carId of CAR_IDS) {
      const track = tracks[id];
      const car = createCar(track, track.startIdx, getCar(carId).spec), race = new RaceState(track);
      const drive = makeAutopilot(track, { aLat: 24, lookK: 0.75, nitro: true });
      let steps = 0, wall = 0;
      while (!race.finished && steps < 54000) {
        stepCar(car, track, drive(car), dt);
        race.update(car, dt);
        steps++;
        if (car.hitWall) wall++;
      }
      races.push({ track: id, car: carId, finished: race.finished, steps, time: race.finishTime, wall, x: car.x, z: car.z });
    }
  }
}

const out = process.argv[2];
writeFileSync(out + '.bin', Buffer.concat(chunks.map((c) => Buffer.from(c.buffer))));
writeFileSync(out + '.json', stringifyHex({ keys: KEYS, scenarios, races }));
console.log(`${scenarios.length} scenarios, ${offset} numbers; ${races.length} races`);
