/**
 * physicsBench.mjs — speed and sanity benchmark for the car physics.
 *
 *   node tools/physicsBench.mjs [cars=80] [seconds=20]
 *
 * 1. Cost of one stepCar() call (µs) on every track: a simple autopilot
 *    drives one lap (cornering, braking, the odd wall scrape), its controls
 *    are recorded, then the same lap is replayed and only stepCar() is timed.
 * 2. A training-like loop: N cars on each track, every step doing what the
 *    trainer does per car — sense() (wall raycasts), net.forward(),
 *    stepCar() and race.update() — reported as "× real time" (simulated
 *    seconds per wall-clock second). Every car stays alive the whole time
 *    (worst case: the real trainer drops cars as they crash). The cars are
 *    steered by a cheap table-driven autopilot so they really go round the
 *    track; the network is still evaluated, for its cost.
 *    A second, shorter pass times each part separately.
 * 3. Walls: what a hit costs (5-90°, coasting, on a straight test road),
 *    and what grinding along a wall at full throttle settles at.
 * 4. Sanity: no NaN, no car outside the walls.
 *
 * Sections 1-3 use the racer (CAR, the default car; the AI trains with it).
 * Every car of src/physics/cars.js (v4) gets its own lines too:
 * 1b. µs per stepCar() and lap times over every track (its own autopilot,
 *     corner speeds scaled by its skidpad grip).
 * 3b. Walls: the 30° and 90° hits, a 30° hit at its top speed with nitro,
 *     and grinding along a wall at full throttle with nitro held.
 * 3c. Its stats measured with the physics (tools/carStats.mjs) and whether
 *     they still match the ones stored in cars.js (the car picker shows them).
 * Their cars count in the sanity totals of section 4.
 *
 * Plain Node, no dependencies, no DOM.
 */
import { TRACKS } from '../src/tracks/trackData.js';
import { buildTrack } from '../src/tracks/trackBuilder.js';
import { createCar, placeCar, stepCar, addNitro, CAR, PHYSICS_VERSION } from '../src/physics/car.js';
import { CARS, CAR_IDS } from '../src/physics/cars.js';
import { measureCar, statsMismatch } from './carStats.mjs';
import { RaceState } from '../src/game/race.js';
import { NeuralNetwork } from '../src/ai/network.js';
import * as sensors from '../src/ai/sensors.js';

const N_CARS = Number(process.argv[2] ?? 80);
const SECONDS = Number(process.argv[3] ?? 20);
const DT = 1 / 60;
const now = () => performance.now(); // ms

let hidden = [12];
try {
  const tr = await import('../src/ai/trainer.js');
  if (Array.isArray(tr.DEFAULT_TRAINING?.hidden)) hidden = tr.DEFAULT_TRAINING.hidden;
} catch { /* keep the default */ }
const netSizes = [sensors.INPUT_COUNT, ...hidden, sensors.OUTPUT_COUNT];

/**
 * Autopilot: aim at a point ahead (optionally offset from the centre line),
 * speed target from a per-sample table (corner speed for `aLat` m/s² of
 * lateral grip, with braking distance at 9 m/s²). O(1) per call.
 */
function makeAutopilot(track, lineOffset = 0, aLat = 12.5) {
  const N = track.count, closed = track.closed;
  const wrap = (a) => Math.atan2(Math.sin(a), Math.cos(a));
  const at = (i) => (closed ? ((i % N) + N) % N : Math.max(0, Math.min(N - 1, i)));
  const vt = new Float32Array(N);
  for (let i = 0; i < N; i++) {
    const a = at(i - 3), b = at(i + 3);
    const d = Math.abs(wrap(Math.atan2(track.tx[b], track.tz[b]) - Math.atan2(track.tx[a], track.tz[a])));
    vt[i] = Math.min(100, Math.sqrt(aLat * (d > 1e-4 ? (6 * track.segLen) / d : 1e4)));
  }
  const brake = 2 * 9 * track.segLen;
  for (let pass = 0; pass < (closed ? 2 : 1); pass++) {
    for (let i = N - 1; i >= 0; i--) {
      const j = closed ? (i + 1) % N : i + 1;
      if (j < N) vt[i] = Math.min(vt[i], Math.sqrt(vt[j] * vt[j] + brake));
    }
  }
  return (car, ctrl) => {
    const look = Math.max(4, Math.min(14, Math.round((6 + car.speed * 0.35) / track.segLen)));
    const i = at(car.idx + look);
    const off = lineOffset * Math.max(0, track.hw[i] - 2.5);
    const gx = track.px[i] + track.nx[i] * off - car.x, gz = track.pz[i] + track.nz[i] * off - car.z;
    const fx = Math.sin(car.yaw), fz = Math.cos(car.yaw);
    ctrl.steer = Math.max(-1, Math.min(1, 3 * Math.atan2(gx * fz - gz * fx, gx * fx + gz * fz)));
    const target = vt[at(car.idx + 1)];
    ctrl.throttle = car.speed < target - 1 ? 1 : car.speed > target + 1.5 ? -1 : 0.3;
    ctrl.handbrake = false;
  };
}

const tracks = TRACKS.map((def) => buildTrack(def));
let bad = 0, outside = 0;
const checkCar = (car) => {
  if (!Number.isFinite(car.x + car.y + car.z + car.vx + car.vy + car.vz + car.yaw + car.yawRate)) bad++;
  if (Math.abs(car.lat) > car._hw + 0.01) outside++;
};
const wrapSprint = (track, car, race) => {
  if (!track.closed && car.idx > track.count - 12) { placeCar(car, track, track.startIdx); if (race) race.reset(); }
};

console.log(`Track Rush physics bench — ${tracks.length} tracks, CAR.substeps ${CAR.substeps}, Node ${process.version}`);

// --- 1. single car: µs per stepCar -------------------------------------------
console.log('\n1) one car, one lap with an autopilot, µs per stepCar() (controls replayed, only stepCar timed)');
const single = [];
for (let pass = 0; pass < 2; pass++) { // pass 0 warms up the JIT
  for (const track of tracks) {
    const ap = makeAutopilot(track);
    const ctrl = { steer: 0, throttle: 0, handbrake: false };
    let car = createCar(track);
    const rec = [];
    const goal = car.prog + (track.closed ? track.N : track.count - 12 - car.prog);
    for (let s = 0; s < 60 * 400 && car.prog < goal; s++) {
      ap(car, ctrl);
      rec.push(ctrl.steer, ctrl.throttle);
      stepCar(car, track, ctrl, DT);
    }
    const steps = rec.length / 2;
    car = createCar(track);
    let wall = 0;
    const t0 = now();
    for (let s = 0; s < steps; s++) {
      ctrl.steer = rec[2 * s]; ctrl.throttle = rec[2 * s + 1];
      stepCar(car, track, ctrl, DT);
      if (car.hitWall) wall++;
    }
    const us = ((now() - t0) * 1000) / steps;
    checkCar(car);
    if (pass === 1) {
      single.push(us);
      console.log(`   ${track.id.padEnd(22)} ${us.toFixed(2).padStart(6)} µs/step   lap ${(steps * DT).toFixed(1)} s, wall contact ${((wall / steps) * 100).toFixed(1)} % of steps`);
    }
  }
}
console.log(`   average ${(single.reduce((a, b) => a + b, 0) / single.length).toFixed(2)} µs/step`);

// --- 1b. every car ---------------------------------------------------------------
console.log('\n1b) every car: one lap of every track with its own autopilot (corner speeds scaled by its skidpad grip), µs per stepCar()');
for (const id of CAR_IDS) {
  const def = CARS[id], aLat = (12.5 * def.stats.grip) / CARS.racer.stats.grip;
  let ms = 0, steps = 0, wall = 0;
  for (const track of tracks) {
    const ap = makeAutopilot(track, 0, aLat);
    const ctrl = { steer: 0, throttle: 0, handbrake: false };
    let car = createCar(track, track.startIdx, def.spec);
    const rec = [];
    const goal = car.prog + (track.closed ? track.N : track.count - 12 - car.prog);
    for (let s = 0; s < 60 * 400 && car.prog < goal; s++) {
      ap(car, ctrl);
      rec.push(ctrl.steer, ctrl.throttle);
      stepCar(car, track, ctrl, DT);
    }
    const n = rec.length / 2;
    car = createCar(track, track.startIdx, def.spec);
    const t0 = now();
    for (let s = 0; s < n; s++) {
      ctrl.steer = rec[2 * s]; ctrl.throttle = rec[2 * s + 1];
      stepCar(car, track, ctrl, DT);
      if (car.hitWall) wall++;
    }
    ms += now() - t0;
    steps += n;
    checkCar(car);
  }
  console.log(`   ${id.padEnd(8)} ${((ms * 1000) / steps).toFixed(2).padStart(6)} µs/step   ${tracks.length} laps in ${(steps * DT).toFixed(1)} s ` +
    `(autopilot grip ${aLat.toFixed(1)} m/s²), wall contact ${((wall / steps) * 100).toFixed(1)} % of steps`);
}

// --- 2. training-like loop ---------------------------------------------------
console.log(`\n2) ${N_CARS} cars per track, each step per car: sense() + network ${netSizes.join('-')} + stepCar() + race.update(); ${SECONDS} s simulated per track`);
function makeAgents(track) {
  const agents = [];
  for (let k = 0; k < N_CARS; k++) {
    const car = createCar(track);
    agents.push({
      car,
      race: new RaceState(track, 1),
      ap: makeAutopilot(track, ((k % 9) - 4) / 5, 11 + (k % 5)),
      net: new NeuralNetwork(netSizes),
      inputs: new Float32Array(sensors.INPUT_COUNT),
      rays: new Float32Array(sensors.SENSOR_ANGLES.length),
      ctrl: { steer: 0, throttle: 0, handbrake: false },
    });
  }
  // stagger the cars along the first stretch so they don't all sit on one spot
  for (let s = 0; s < 120; s++) {
    for (let k = 0; k < agents.length; k++) {
      if (s >= k * 1.5) continue;
      const a = agents[k];
      a.ap(a.car, a.ctrl);
      stepCar(a.car, track, a.ctrl, DT);
    }
  }
  return agents;
}
const outCtrl = { steer: 0, throttle: 0, handbrake: false };
const results = [];
for (const track of tracks) {
  // a) headline: the whole loop, untimed inside
  let agents = makeAgents(track);
  const steps = Math.round(SECONDS / DT);
  let wallSteps = 0;
  const t0 = now();
  for (let s = 0; s < steps; s++) {
    for (let k = 0; k < agents.length; k++) {
      const a = agents[k], c = a.car;
      sensors.sense(track, c, a.race, a.inputs, a.rays);
      sensors.outputsToControls(a.net.forward(a.inputs), outCtrl);
      a.ap(c, a.ctrl);
      stepCar(c, track, a.ctrl, DT);
      if (a.race.update(c, DT) === null && a.race.finished) a.race.reset();
      wrapSprint(track, c, a.race);
      if (c.hitWall) wallSteps++;
    }
  }
  const wallMs = now() - t0;
  for (const a of agents) checkCar(a.car);
  const x = (steps * DT * 1000) / wallMs;

  // b) breakdown: a shorter pass, each part timed separately (timer overhead included)
  agents = makeAgents(track);
  const bSteps = Math.round(Math.min(SECONDS, 5) / DT);
  const tm = { sense: 0, net: 0, ap: 0, phys: 0, race: 0 };
  for (let s = 0; s < bSteps; s++) {
    let t = now(), t2;
    for (const a of agents) sensors.sense(track, a.car, a.race, a.inputs, a.rays);
    t2 = now(); tm.sense += t2 - t; t = t2;
    for (const a of agents) sensors.outputsToControls(a.net.forward(a.inputs), outCtrl);
    t2 = now(); tm.net += t2 - t; t = t2;
    for (const a of agents) a.ap(a.car, a.ctrl);
    t2 = now(); tm.ap += t2 - t; t = t2;
    for (const a of agents) stepCar(a.car, track, a.ctrl, DT);
    t2 = now(); tm.phys += t2 - t; t = t2;
    for (const a of agents) { if (a.race.update(a.car, DT) === null && a.race.finished) a.race.reset(); wrapSprint(track, a.car, a.race); }
    tm.race += now() - t;
  }
  for (const a of agents) checkCar(a.car);
  const per = (ms) => ((ms * 1000) / (bSteps * N_CARS)).toFixed(2);
  results.push(x);
  console.log(`   ${track.id.padEnd(22)} ${x.toFixed(1).padStart(6)}× real time  (${((wallMs * 1000) / (steps * N_CARS)).toFixed(2)} µs per car-step: sense ${per(tm.sense)}, network ${per(tm.net)}, autopilot ${per(tm.ap)}, physics ${per(tm.phys)}, race ${per(tm.race)}; wall contact ${((wallSteps / (steps * N_CARS)) * 100).toFixed(1)} %)`);
}
const minX = Math.min(...results);
const avgX = results.reduce((a, b) => a + b, 0) / results.length;
console.log(`   slowest track ${minX.toFixed(1)}× real time, average ${avgX.toFixed(1)}×  (target ≥ 40× with 80 cars)`);

// --- 3. walls ------------------------------------------------------------------
console.log(`\n3) walls (physics v${PHYSICS_VERSION}): hits on a straight 14 m road, wheels straight, coasting`);
{
  const road = buildTrack({ id: 'bench-straight', name: 'Bench straight', type: 'sprint', laps: 1, width: 14, checkpoints: [],
    points: Array.from({ length: 21 }, (_, k) => [0, k * 200, 0]) });
  const i0 = 40;
  // car `lat` m left of the centre line, heading `deg` towards the left wall at `kmh`
  const launch = (deg, kmh, lat, spec = CAR) => {
    const car = createCar(road, i0, spec);
    const yaw = Math.atan2(road.tx[i0], road.tz[i0]) + (deg * Math.PI) / 180, v = kmh / 3.6;
    placeCar(car, road, i0, { x: road.px[i0] + road.nx[i0] * lat, z: road.pz[i0] + road.nz[i0] * lat, yaw,
      vx: Math.sin(yaw) * v, vz: Math.cos(yaw) * v, idx: i0, laps: 0 });
    return car;
  };
  // a hit `deg` towards the left wall at `kmh`, coasting with the wheels straight: speed 0.5 s after it
  const hitWall = (deg, kmh, spec = CAR) => {
    const car = launch(deg, kmh, road.hw[i0] - 3.5, spec), coast = { steer: 0, throttle: 0, handbrake: false };
    let hit = -1, before = 0, after = NaN, rebound = 0, impact = 0;
    for (let s = 0; s < 180 && Number.isNaN(after); s++) {
      const v = car.speed;
      stepCar(car, road, coast, DT);
      checkCar(car);
      if (car.hitWall && hit < 0) { hit = s; before = v; }
      if (hit < 0) continue;
      rebound = Math.max(rebound, -(car.vx * road.nx[car.idx] + car.vz * road.nz[car.idx]));
      impact = Math.max(impact, car.wallImpact);
      if (s - hit >= 30) after = car.speed;
    }
    return { before, after, lost: 1 - after / before, rebound, impact };
  };
  // grinding: steering into the wall at full throttle (the wall sets the speed, not the engine); km/h after 2, 4, 10 s
  const grind = (kmh, spec = CAR, nitro = false) => {
    const car = launch(3, kmh, road.hw[i0] - 2.5, spec), drive = { steer: 1, throttle: 1, handbrake: false, nitro };
    const at = {};
    let touching = 0;
    for (let s = 1; s <= 600; s++) {
      if (nitro) addNitro(car, 1);
      stepCar(car, road, drive, DT);
      checkCar(car);
      if (car.hitWall) touching++;
      if (s % 120 === 0) at[s / 60] = (car.speed * 3.6).toFixed(0);
    }
    return { at, touching: touching / 600 };
  };
  for (const [deg, kmh] of [[5, 150], [10, 150], [15, 200], [30, 180], [45, 150], [90, 100]]) {
    const { before, after, lost, rebound, impact } = hitWall(deg, kmh);
    console.log(`   ${String(deg).padStart(2)}° at ${String(kmh).padStart(3)} km/h: ${(before * 3.6).toFixed(0).padStart(3)} -> ${(after * 3.6).toFixed(0).padStart(3)} km/h ` +
      `0.5 s after the hit (${(lost * 100).toFixed(0).padStart(3)} % lost), into the wall ${impact.toFixed(1)} m/s, rebound ${rebound.toFixed(2)} m/s`);
  }
  for (const kmh of [250, 60]) {
    const { at, touching } = grind(kmh);
    console.log(`   steering into the wall at full throttle from ${kmh} km/h: ${at[2]} km/h after 2 s, ${at[4]} after 4 s, ${at[10]} after 10 s ` +
      `(touching in ${(touching * 100).toFixed(0)} % of steps; top speed on the open road ${(CAR.maxSpeed * 3.6).toFixed(0)})`);
  }

  // --- 3b. walls, every car ---
  console.log('\n3b) walls, every car: % of the speed lost 0.5 s after a hit / rebound m/s; grinding into the wall from its top speed with nitro held');
  for (const id of CAR_IDS) {
    const spec = CARS[id].spec, vTop = Math.round(CARS[id].stats.topNitro);
    const parts = [[30, 180], [90, 100], [30, vTop]].map(([deg, kmh]) => {
      const r = hitWall(deg, kmh, spec);
      return `${deg}° ${kmh}: ${(r.lost * 100).toFixed(0).padStart(3)} % / ${r.rebound.toFixed(2)}`;
    });
    const g = grind(vTop, spec, true);
    console.log(`   ${id.padEnd(8)} ${parts.join(',  ')};  grinding from ${vTop} km/h with nitro: ${g.at[2]} / ${g.at[4]} / ${g.at[10]} km/h after 2 / 4 / 10 s`);
  }
}

// --- 3c. car stats ------------------------------------------------------------------
console.log('\n3c) every car\'s stats, measured (tools/carStats.mjs; the car picker shows the copy stored in src/physics/cars.js)');
let statsOff = 0;
console.log('   car       mass  0-100  0-200  0-200 nitro  top km/h  nitro  tank s / m  100-0 m  grip 30 m / 120 m  drift s');
for (const id of CAR_IDS) {
  const m = measureCar(CARS[id].spec), off = statsMismatch(CARS[id].stats, m);
  statsOff += off.length;
  console.log(`   ${id.padEnd(8)} ${String(m.mass).padStart(5)} ${m.accel100.toFixed(2).padStart(6)} ${m.accel200.toFixed(2).padStart(6)} ${m.accel200n.toFixed(2).padStart(12)} ` +
    `${m.top.toFixed(1).padStart(9)} ${m.topNitro.toFixed(1).padStart(6)} ${`${m.tankTime.toFixed(2)} / ${m.tankDist.toFixed(0)}`.padStart(11)} ${m.brake100.toFixed(1).padStart(8)} ` +
    `${`${m.grip.toFixed(2)} / ${m.gripFast.toFixed(2)} g`.padStart(18)} ${m.drift.toFixed(2).padStart(8)}` +
    `${off.length ? `   OFF from cars.js: ${off.map((o) => `${o.key} ${o.stored} -> ${o.measured}`).join(', ')}` : ''}`);
}
console.log(statsOff ? '   cars.js stats are out of date: run node tools/carStats.mjs and paste its lines' : '   cars.js stats match');

// --- 4. sanity ---------------------------------------------------------------
console.log(`\n4) sanity: non-finite car states ${bad}, cars outside the walls ${outside}`);
console.log(bad === 0 && outside === 0 && minX >= 40 && statsOff === 0 ? '\nbench OK' : '\nbench: CHECK THE NUMBERS ABOVE');
process.exit(bad || outside ? 1 : 0);
