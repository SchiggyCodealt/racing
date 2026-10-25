/**
 * carStats.mjs — measures every car's stats with the real physics (cars.js).
 *
 *   node tools/carStats.mjs           measure, print a table and the `stats:` line of every car
 *   node tools/carStats.mjs --check   measure and compare with the stats stored in cars.js;
 *                                     exits 1 when one is off by more than its tolerance
 *
 * npm test runs the same check (measureCar + statsMismatch), so the numbers on the car picker
 * can't go stale: after changing a spec, run this and paste the printed stats lines into
 * src/physics/cars.js. About 1 s per car, no DOM.
 *
 * What is measured (all on flat synthetic roads, 60 Hz like the game):
 *   accel100 / accel200   s from a standstill, full throttle, a light hand keeping the car straight
 *   top                   km/h, the highest speed in 150 s of full throttle on a 25 km straight
 *   accel200n             s, 0-200 km/h with nitro held from a full tank (as at the start of a race)
 *   topNitro              km/h, top speed with nitro held and the tank kept full
 *   tankTime              s a full tank lasts with nitro held from a standstill
 *   tankDist              m covered in that time
 *   brake100              m, 100-0 km/h, full brakes, wheels straight
 *   grip / gripFast       g, the fastest steady lap of a 30 / 120 m circle (speed² / radius) that
 *                         a look-ahead driver holds within 4 m of the line, without touching a wall
 *   drift                 s, how long a keyboard driver holds a drift: on an open pad at 60-130 km/h, a
 *                         handbrake pull with a steer key held (0.2-0.8 s), then throttle and digital
 *                         countersteer (a key towards the slide above a target body slip angle of 15-35°,
 *                         the turn key below it). The longest stretch above 12° of body slip in each of
 *                         192 runs (a spin counts as 0); the median of those
 */
import { realpathSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { buildTrack } from '../src/tracks/trackBuilder.js';
import { createCar, placeCar, stepCar, addNitro } from '../src/physics/car.js';
import { CARS, CAR_IDS } from '../src/physics/cars.js';

const DT = 1 / 60;
const KMH = 3.6;

/** How far a stored stat may be from a fresh measurement (absolute, in its unit). */
export const TOLERANCE = {
  mass: 0, accel100: 0.03, accel200: 0.05, top: 0.5, accel200n: 0.05, topNitro: 0.5,
  tankTime: 0.05, tankDist: 3, brake100: 0.3, grip: 0.02, gripFast: 0.02, drift: 0.05,
};
export const STAT_KEYS = Object.keys(TOLERANCE);

let straight = null;
const road = () => (straight ??= buildTrack({ id: 'stats-straight', name: 'Stats straight', type: 'sprint', laps: 1, width: 30,
  checkpoints: [], points: Array.from({ length: 126 }, (_, k) => [0, k * 200, 0]) }));
const circles = {};
const circle = (R) => (circles[R] ??= buildTrack({ id: `stats-circle-${R}`, name: 'Stats circle', type: 'circuit', laps: 1,
  width: Math.min(30, 2 * (R - 4)), checkpoints: [],
  points: Array.from({ length: 96 }, (_, k) => { const a = (k / 96) * Math.PI * 2; return [R * Math.sin(a), R * Math.cos(a) - R, 0]; }) }));

/** Keep a car going straight down the stats road. */
const keepStraight = (car, ctrl) => { ctrl.steer = Math.max(-1, Math.min(1, -car.lat * 0.05 - car.yaw * 2)); return ctrl; };

/** Full throttle from a standstill, with or without nitro; `refill` keeps the tank full. */
function run(spec, { nitro = false, refill = false, seconds = 150 } = {}) {
  const tr = road();
  const car = createCar(tr, 3, spec);
  const ctrl = { steer: 0, throttle: 1, handbrake: false, nitro };
  const out = { t100: NaN, t200: NaN, top: 0, tankTime: NaN, tankDist: NaN };
  const z0 = car.z;
  for (let s = 1; s <= seconds * 60; s++) {
    if (refill) addNitro(car, 1);
    stepCar(car, tr, keepStraight(car, ctrl), DT);
    const t = s * DT, kmh = car.speed * KMH;
    if (Number.isNaN(out.t100) && kmh >= 100) out.t100 = t;
    if (Number.isNaN(out.t200) && kmh >= 200) out.t200 = t;
    if (nitro && !refill && Number.isNaN(out.tankTime) && car.nitro <= 0) { out.tankTime = t; out.tankDist = car.z - z0; }
    if (kmh > out.top) out.top = kmh;
    if (car.idx > tr.count - 30) break;
  }
  return out;
}

function brake100(spec) {
  const tr = road();
  const car = createCar(tr, 10, spec);
  placeCar(car, tr, 10, { x: tr.px[10], z: tr.pz[10], yaw: 0, vx: 0, vz: 100 / KMH, idx: 10, laps: 0 });
  const z0 = car.z;
  for (let s = 0; s < 60 * 20 && car.forwardSpeed > 0.05; s++) stepCar(car, tr, { steer: 0, throttle: -1, handbrake: false }, DT);
  return car.z - z0;
}

/** Fastest steady speed round a circle of radius R (m/s), as lateral g. */
function skidpad(spec, R) {
  const tr = circle(R);
  let best = 0;
  for (let vT = Math.sqrt(6 * R); vT < Math.min(95, Math.sqrt(30 * R)); vT *= 1.01) {
    const car = createCar(tr, 0, spec);
    placeCar(car, tr, 0, { x: tr.px[0], z: tr.pz[0], yaw: Math.atan2(tr.tx[0], tr.tz[0]), vx: tr.tx[0] * vT * 0.7, vz: tr.tz[0] * vT * 0.7, idx: 0, laps: 0 });
    const ctrl = { steer: 0, throttle: 0, handbrake: false };
    let latMax = 0, us = 0, n = 0, wall = false;
    for (let s = 0; s < 60 * 10 && !wall; s++) {
      const look = Math.max(2, Math.round((4 + car.speed * 0.3) / tr.segLen));
      const i = (car.idx + look) % tr.N;
      const gx = tr.px[i] - car.x, gz = tr.pz[i] - car.z;
      const fx = Math.sin(car.yaw), fz = Math.cos(car.yaw);
      ctrl.steer = Math.max(-1, Math.min(1, 3 * Math.atan2(gx * fz - gz * fx, gx * fx + gz * fz)));
      ctrl.throttle = Math.max(-1, Math.min(1, (Math.min(vT, 0.7 * vT + s * DT * 2) - car.forwardSpeed) * 0.8));
      stepCar(car, tr, ctrl, DT);
      wall = car.hitWall;
      if (s > 60 * 6) { latMax = Math.max(latMax, Math.abs(car.lat)); us += car.speed; n++; }
    }
    const v = us / n;
    if (!wall && latMax < 4 && v > vT - 1) best = Math.max(best, v);
  }
  return (best * best) / R / 9.81;
}

let pad = null;
const KEYS = { rateSlow: 7, rateFast: 3.2, fastSpeed: 50, ret: 10 }; // the keyboard steering ramp of src/game/input.js

/** One keyboard drift: the longest stretch (s) above 12° of body slip, 0 after a spin. */
function driftRun(spec, kmh, hbT, betaT, band, lift) {
  pad ??= buildTrack({ id: 'stats-pad', name: 'Stats pad', type: 'circuit', laps: 1, width: 1200, checkpoints: [],
    points: Array.from({ length: 400 }, (_, k) => { const a = (k / 400) * Math.PI * 2; return [3000 * Math.sin(a), 3000 * Math.cos(a) - 3000, 0]; }) });
  const v = kmh / KMH, y0 = Math.atan2(pad.tx[0], pad.tz[0]);
  const car = createCar(pad, 0, spec);
  placeCar(car, pad, 0, { x: pad.px[0], z: pad.pz[0], yaw: y0, vx: Math.sin(y0) * v, vz: Math.cos(y0) * v, idx: 0, laps: 0 });
  const ctrl = { steer: 0, throttle: 0, handbrake: false };
  let held = 0, longest = 0;
  for (let s = 0; s < 60 * 8; s++) {
    const t = s * DT;
    const beta = (Math.atan2(-car.sideSpeed, Math.max(0.5, car.forwardSpeed)) * 180) / Math.PI; // + = nose left of travel
    let target;
    if (t < hbT) { target = 1; ctrl.handbrake = true; ctrl.throttle = 0; }
    else {
      target = beta > betaT + band ? -1 : beta < betaT - band ? 1 : 0;
      ctrl.handbrake = false;
      ctrl.throttle = lift && beta > betaT + 15 ? 0 : 1;
    }
    const rate = target === 0 || target * ctrl.steer < 0 ? KEYS.ret
      : KEYS.rateSlow + (KEYS.rateFast - KEYS.rateSlow) * Math.min(1, car.speed / KEYS.fastSpeed);
    ctrl.steer += Math.sign(target - ctrl.steer) * Math.min(Math.abs(target - ctrl.steer), rate * DT);
    stepCar(car, pad, ctrl, DT);
    const ab = Math.abs(beta);
    if (ab > 90) return 0; // spun
    if (ab > 12 && car.speed > 6) { held += DT; if (held > longest) longest = held; } else held = 0;
  }
  return longest;
}

/** Median keyboard drift (s) over the grid of speeds, handbrake pulls, target angles and throttle styles. */
function drift(spec) {
  const all = [];
  for (const kmh of [60, 80, 100, 130]) for (const hbT of [0.2, 0.35, 0.5, 0.8]) for (const betaT of [15, 25, 35])
    for (const band of [3, 8]) for (const lift of [false, true]) all.push(driftRun(spec, kmh, hbT, betaT, band, lift));
  all.sort((a, b) => a - b);
  return all[all.length >> 1];
}

const r2 = (x) => Math.round(x * 100) / 100;
const r1 = (x) => Math.round(x * 10) / 10;

/** Measure one car spec: the stats object stored in cars.js. */
export function measureCar(spec) {
  const plain = run(spec);
  const boost = run(spec, { nitro: true, seconds: 30 });
  const flat = run(spec, { nitro: true, refill: true, seconds: 150 });
  return {
    mass: spec.mass,
    accel100: r2(plain.t100), accel200: r2(plain.t200), top: r1(plain.top),
    accel200n: r2(boost.t200), topNitro: r1(flat.top),
    tankTime: r2(boost.tankTime), tankDist: Math.round(boost.tankDist),
    brake100: r1(brake100(spec)),
    grip: r2(skidpad(spec, 30)), gripFast: r2(skidpad(spec, 120)),
    drift: r2(drift(spec)),
  };
}

/** Stats that differ from a fresh measurement by more than TOLERANCE: [{key, stored, measured}]. */
export function statsMismatch(stored, measured) {
  return STAT_KEYS.filter((k) => !(Math.abs((stored?.[k] ?? NaN) - measured[k]) <= TOLERANCE[k] + 1e-9))
    .map((k) => ({ key: k, stored: stored?.[k], measured: measured[k] }));
}

const invokedAs = (() => { try { return pathToFileURL(realpathSync(process.argv[1] ?? '')).href; } catch { return ''; } })();
if (import.meta.url === invokedAs) main();

function main() {
  const CHECK = process.argv.includes('--check');
  const t0 = performance.now();
  let bad = 0;
  const lines = [];
  console.log('car       kg    0-100  0-200   top    0-200N  topN    tank       100-0   grip  fast  drift');
  for (const id of CAR_IDS) {
    const def = CARS[id], m = measureCar(def.spec);
    console.log(`${id.padEnd(9)} ${String(m.mass).padStart(4)}  ${m.accel100.toFixed(2)} s ${m.accel200.toFixed(2).padStart(5)} s ${m.top.toFixed(1)}  ` +
      `${m.accel200n.toFixed(2).padStart(5)} s ${m.topNitro.toFixed(1)}  ${m.tankTime.toFixed(2)} s ${String(m.tankDist).padStart(4)} m  ` +
      `${m.brake100.toFixed(1)} m  ${m.grip.toFixed(2)}  ${m.gripFast.toFixed(2)}  ${m.drift.toFixed(2)} s`);
    lines.push(`    stats: ${JSON.stringify(m).replace(/"(\w+)":/g, '$1: ').replace(/,/g, ', ').replace(/^\{/, '{ ').replace(/\}$/, ' }')},  // ${id}`);
    const off = statsMismatch(def.stats, m);
    if (off.length) { bad++; console.log(`   cars.js differs: ${off.map((o) => `${o.key} ${o.stored} -> ${o.measured}`).join(', ')}`); }
  }
  console.log(`\n${((performance.now() - t0) / 1000).toFixed(1)} s`);
  if (!CHECK) console.log(`\nstats lines for src/physics/cars.js:\n${lines.join('\n')}`);
  else console.log(bad ? `${bad} car(s) OUT OF DATE in cars.js: run node tools/carStats.mjs and paste the stats` : 'cars.js stats are up to date');
  if (CHECK) process.exit(bad ? 1 : 0);
}
