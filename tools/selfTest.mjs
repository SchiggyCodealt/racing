/**
 * selfTest.mjs — quick headless checks, run by `npm test` and CI.
 *
 *   1. every track builds and has checkpoints
 *   2. a look-ahead autopilot (brakes for corners using the v2 grip and
 *      braking limits) finishes every track, so every track is drivable
 *   3. checkpoints only count in order (driving backwards scores nothing)
 *   4. car physics: no wall bounce (30° hit at 50 m/s), and that hit costs
 *      at least half the speed (walls must cost time, physics v3); a car
 *      pressed nose-in against a wall steers off it at full throttle; on
 *      Hairpin Valley the clean autopilot beats one that never brakes and
 *      bounces off the walls instead; no tunnelling through walls at
 *      300-360 km/h, no NaN under random controls
 *      4e (v4). every car of src/physics/cars.js: the racer is CAR and nitro
 *      left alone changes nothing; a stored hash of its state after fixed
 *      autopilot and random-control runs pins it to the v3 physics; stored
 *      stats match the physics; each car
 *      finishes every track, walls (no bounce, no tunnelling at its top speed
 *      with nitro), no NaN with random nitro, the nitro rules, keyboard lane
 *      keeping without fishtails, jumps without bounces or spins
 *   5. AI sensors: inputs finite and in range, left/right mirror symmetry
 *   6. short neuroevolution runs with the 'crash' wall rule (it must drive
 *      clean) produce a car that finishes Rookie Oval and one that brakes its
 *      way round Hairpin Valley (population 80); the 'ride' wall rule keeps a
 *      car that hits a wall in the run, 'crash' puts it out; training with
 *      'ride' (the default) raises the population's average fitness
 *   7. a saved network round-trips through JSON exactly (drives the same
 *      lap); a v1 network is rejected with a clear message
 *   8. Max-speed hand-over: a training session exported mid-run, trained in
 *      the worker's TrainerHost and handed back continues exactly like one
 *      that never moved (with the same random numbers for breeding)
 *   9. player ghosts: a recorded run (with a respawn and wall hits) packs to
 *      ~20 KB per minute and replays within a few cm at every physics step on
 *      the race clock; foreign or broken saved ghosts, records and settings
 *      are ignored without throwing
 *  10. medal times: src/tracks/medals.js covers every track's Drive race with
 *      every car (v4) for the current physics and scoring rules, author <
 *      gold < silver < bronze, and the autopilot runs (nitro with the score's
 *      refills) behind one short race's author times still drive them
 *  11. car models (v4, src/game/carMesh.js): every car's model builds with
 *      finite geometry about the size of the physics capsule, an unknown car
 *      id draws the racer, the menu silhouettes cover every car and the nitro
 *      jets burn exactly while the car boosts
 *  12. style score (v4, src/game/score.js): a clean autopilot race scores
 *      exactly what the rules say, the same every time; a clean run beats a
 *      wall-hitting one; handbrake slides score drifts and Seaside Stunts'
 *      jumps score air; banked points refill nitro (a nitro autopilot gets
 *      faster with refills), respawns cost points and refill nothing; best
 *      scores per track and car ignore junk in localStorage
 *  13. best times and ghosts per track and car (v4): v3 best times read as
 *      the racer's and are copied over by the first v4 save; a ghost keeps
 *      its car and when it burned nitro (a v3 ghost is the racer's); one
 *      ghost per track and car in storage; junk ignored, a full storage
 *      handled
 *
 * Run from anywhere: node tools/selfTest.mjs (about 10-30 s).
 */
import { TRACKS } from '../src/tracks/trackData.js';
import { buildTrack, raceLength } from '../src/tracks/trackBuilder.js';
import { createCar, placeCar, stepCar, CAR } from '../src/physics/car.js';
import { RaceState, formatTime } from '../src/game/race.js';
import { Trainer, parseNetworkFile } from '../src/ai/trainer.js';
import { NeuralNetwork } from '../src/ai/network.js';
import { sense, mirrorInputs, driveNetwork, AIDriver, INPUT_COUNT, INPUT_LABELS } from '../src/ai/sensors.js';

const dt = 1 / 60;
let failures = 0;
const check = (ok, msg) => {
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${msg}`);
  if (!ok) failures++;
};
const finite = (car) => Number.isFinite(car.x + car.y + car.z + car.vx + car.vy + car.vz + car.yaw + car.yawRate + car.pitch + car.roll);

/**
 * Look-ahead autopilot: steers at a point on the centre line ahead and keeps
 * to a speed profile computed from the road curvature (corner speed for
 * `grip` m/s² of lateral grip, braking at `brake` m/s² before corners).
 */
function makeAutopilot(track, grip = 11, brake = 7.5, top = CAR.maxSpeed) {
  const N = track.count, closed = track.closed;
  const at = (i) => (closed ? ((i % N) + N) % N : Math.max(0, Math.min(N - 1, i)));
  const wrap = (a) => Math.atan2(Math.sin(a), Math.cos(a));
  const vmax = new Float32Array(N);
  for (let i = 0; i < N; i++) {
    const a = at(i - 4), b = at(i + 4);
    const turn = Math.abs(wrap(Math.atan2(track.tx[b], track.tz[b]) - Math.atan2(track.tx[a], track.tz[a])));
    const radius = turn > 1e-4 ? (8 * track.segLen) / turn : 1e5;
    vmax[i] = Math.min(top, Math.sqrt(grip * radius));
  }
  for (let pass = 0; pass < (closed ? 2 : 1); pass++) {
    for (let i = N - 1; i >= 0; i--) {
      const j = closed ? (i + 1) % N : i + 1;
      if (j < N) vmax[i] = Math.min(vmax[i], Math.sqrt(vmax[j] * vmax[j] + 2 * brake * track.segLen));
    }
  }
  const ctrl = { steer: 0, throttle: 0, handbrake: false };
  return (car) => {
    const look = Math.max(4, Math.min(14, Math.round((6 + car.speed * 0.35) / track.segLen)));
    const i = at(car.idx + look);
    const gx = track.px[i] - car.x, gz = track.pz[i] - car.z;
    const fx = Math.sin(car.yaw), fz = Math.cos(car.yaw);
    ctrl.steer = Math.max(-1, Math.min(1, 3 * Math.atan2(gx * fz - gz * fx, gx * fx + gz * fz)));
    const target = vmax[at(car.idx + 1)];
    ctrl.throttle = car.speed < target - 1 ? 1 : car.speed > target + 1.5 ? -1 : 0.3;
    return ctrl;
  };
}

// ---- 1 + 2: build and drive every track ---------------------------------------
const tracks = TRACKS.map((def) => buildTrack(def));
check(tracks.length === 12, `${tracks.length} tracks defined (expected 12)`);
for (const track of tracks) {
  const def = track.def;
  check(track.cpSamples.length > 0 && track.length > 1000,
    `${def.name}: builds, ${(raceLength(track, 1) / 1000).toFixed(2)} km${track.closed ? '/lap' : ''}, ${track.cpSamples.length} checkpoints, ${track.closed ? `${track.laps} laps` : 'sprint'}`);
  const car = createCar(track);
  const race = new RaceState(track);
  const drive = makeAutopilot(track);
  let t = 0, wall = 0, bad = false;
  while (!race.finished && t < 600) {
    stepCar(car, track, drive(car), dt);
    race.update(car, dt);
    if (car.hitWall) wall++;
    if (!finite(car)) { bad = true; break; }
    t += dt;
  }
  check(race.finished && !bad, `${def.name}: autopilot finishes (${formatTime(race.finishTime)}, wall contact in ${wall} steps)`);
}

// ---- 3: driving backwards from the start must not pass any gate ----------------
{
  const track = tracks[0];
  const car = createCar(track);
  car.yaw += Math.PI;
  const race = new RaceState(track);
  for (let k = 0; k < 60 * 15; k++) {
    stepCar(car, track, { steer: 0, throttle: 1 }, dt);
    race.update(car, dt);
  }
  check(race.nextGate === 0, 'driving backwards over the line scores no checkpoints');
}

// ---- 4: physics ------------------------------------------------------------------
/** Car on sample i of a track, `lat` m left of the centre, heading `angle` rad left of the road, at `speed`. */
function launch(track, i, lat, angle, speed) {
  const car = createCar(track, i);
  const yaw = Math.atan2(track.tx[i], track.tz[i]) + angle;
  const x = track.px[i] + track.nx[i] * lat, z = track.pz[i] + track.nz[i] * lat;
  placeCar(car, track, i, { x, z, yaw, vx: Math.sin(yaw) * speed, vz: Math.cos(yaw) * speed, idx: i, laps: 0 });
  return car;
}

// 4a. no bounce: 30° into the left wall at 50 m/s on a straight, wheels straight.
// The same hit (180 km/h) must also cost at least half the speed within 0.5 s: walls
// cost time, so the racing line matters (physics v2 kept about 60 %, v3 stops the car).
{
  let worst = 0, kept = Infinity, loss = Infinity;
  for (const track of tracks) {
    const i = track.startIdx + 15; // the start straight (at least ~150 m long on every track)
    const car = launch(track, i, 0, Math.PI / 6, 50);
    let touched = false, reb = 0, t = 0, before = car.speed, tHit = 0, after = NaN;
    while (t < 1.5) {
      const v = car.speed;
      stepCar(car, track, { steer: 0, throttle: 0 }, dt);
      t += dt;
      const n = car.idx;
      const vn = car.vx * track.nx[n] + car.vz * track.nz[n]; // + = towards the left wall
      if (car.hitWall && !touched) { touched = true; before = v; tHit = t; }
      if (touched) reb = Math.max(reb, -vn);
      if (touched && Number.isNaN(after) && t - tHit > 0.5 - 1e-6) after = car.speed;
    }
    worst = Math.max(worst, reb);
    kept = Math.min(kept, car.speed);
    loss = Math.min(loss, 1 - after / before);
    if (!touched) worst = Infinity;
  }
  check(worst <= 1.0 + 1e-3, `no wall bounce: 30° hit at 50 m/s rebounds at most ${worst.toFixed(2)} m/s (limit 1.0), car keeps ≥ ${(kept * 3.6).toFixed(0)} km/h`);
  check(loss >= 0.5, `walls cost speed: that 30° hit at 180 km/h takes at least ${(loss * 100).toFixed(0)} % of the speed within 0.5 s (limit 50 %)`);
}

// 4a2. no sticking: a car its own drive holds nose-in against a wall (45-85°) steers off at
// full throttle (CAR.wallSlide; without it a steep nose-in took up to 17 s, or never came off)
{
  let worst = 0, where = '';
  for (const track of tracks) {
    const i = track.startIdx + 15;
    for (const deg of [45, 55, 65, 75, 85]) {
      const car = launch(track, i, track.hw[i] - 3.5, (deg * Math.PI) / 180, 5);
      for (let k = 0; k < 60; k++) stepCar(car, track, { steer: 0, throttle: 1 }, dt); // pressed into the left wall
      let free = 0, k = 0;
      for (; k < 600 && free < 30; k++) { stepCar(car, track, { steer: -1, throttle: 1 }, dt); free = car.hitWall ? 0 : free + 1; }
      const t = (k - 30) / 60;
      if (free < 30 || t > worst) { worst = free < 30 ? Infinity : t; where = `${track.name} ${deg}°`; }
    }
  }
  check(worst <= 3, `no sticking: a car pressed nose-in against a wall at 45-85° steers off at full throttle within ${worst.toFixed(2)} s (worst: ${where}; limit 3 s)`);
}

// 4b. no tunnelling: shots at 300 and 360 km/h into the walls at many angles and places
{
  let shots = 0, escapes = 0, worstLat = -Infinity;
  for (const track of tracks) {
    for (let f = 0.05; f < 1; f += 0.15) {
      const i = Math.floor(track.count * f);
      for (const speed of [83.3, 100]) {
        for (const deg of [10, 30, 50, 70, 90, -20, -45, -80]) {
          const car = launch(track, i, 0, (deg * Math.PI) / 180, speed);
          let prevIdx = car.idx;
          for (let k = 0; k < 90; k++) {
            stepCar(car, track, { steer: 0, throttle: 1 }, dt);
            const out = Math.abs(car.lat) - (car._hw ?? track.hw[car.idx]);
            worstLat = Math.max(worstLat, out);
            let jump = Math.abs(car.idx - prevIdx);
            if (track.closed) jump = Math.min(jump, track.N - jump);
            if (out > 0 || jump > 30 || !finite(car)) { escapes++; break; }
            prevIdx = car.idx;
          }
          shots++;
        }
      }
    }
  }
  check(escapes === 0, `no tunnelling: ${shots} wall shots at 300-360 km/h, ${escapes} cars left the road (closest centre ${(-worstLat).toFixed(2)} m inside the wall line)`);
}

// 4c. no NaN: random controls, random respawns, on every track
{
  let steps = 0, bad = 0, below = 0;
  let seed = 12345;
  const rnd = () => ((seed = (seed * 1103515245 + 12345) >>> 0) / 4294967296);
  for (const track of tracks) {
    const car = createCar(track);
    const ctrl = { steer: 0, throttle: 0, handbrake: false };
    for (let k = 0; k < 6000; k++) {
      if (k % 30 === 0) {
        ctrl.steer = rnd() * 2 - 1;
        ctrl.throttle = rnd() * 2.4 - 1.2 > 0 ? 1 : rnd() * 2 - 1;
        ctrl.handbrake = rnd() < 0.15;
      }
      if (k % 900 === 0) placeCar(car, track, Math.floor(rnd() * (track.count - 1)));
      stepCar(car, track, ctrl, dt);
      steps++;
      if (!finite(car)) { bad++; placeCar(car, track, track.startIdx); }
      if (car.grounded && car.y < car.groundY - 0.05) below++;
    }
  }
  check(bad === 0 && below === 0, `no NaN: ${steps} random-control steps, ${bad} non-finite states, ${below} steps below the road`);
}

// 4d. the racing line pays: on Hairpin Valley the clean autopilot (brakes for every corner)
// is faster over a lap than the same autopilot that never brakes and turns the hairpins off
// the walls instead (physics v2: 1:08.6 vs 1:24.2, the wall-rider won by 16 s)
{
  const track = tracks.find((t) => t.id === 'hairpin-valley');
  const lap = (grip) => {
    const car = createCar(track), race = new RaceState(track, 1), drive = makeAutopilot(track, grip);
    let wall = 0;
    while (!race.finished && race.time < 300) {
      stepCar(car, track, drive(car), dt);
      race.update(car, dt);
      if (car.hitWall) wall++;
    }
    return { time: race.finished ? race.finishTime : Infinity, wall };
  };
  const clean = lap(11), rider = lap(Infinity);
  check(clean.wall === 0 && clean.time < rider.time,
    `walls cost time: Hairpin Valley lap, clean autopilot ${formatTime(clean.time)} (${clean.wall} wall steps) beats never braking ${formatTime(rider.time)} (wall contact in ${rider.wall} steps)`);
}

// ---- 4e: cars and nitro (v4, src/physics/cars.js) ------------------------------------
// Four cars share the physics through per-car specs; the racer is the v3 car, bit for bit, when
// nitro isn't used (the autopilot times above, the medal author run and the AI checks below show
// it too). Every car must be as sound as the racer: it finishes every track, walls stop it without
// a bounce or a tunnel even at its top speed with nitro, random controls give no NaN, keyboard lane
// keeping doesn't fishtail and jumps land without bounces or spins. Its stats (shown on the car
// picker) must still match the physics: after changing a spec run `node tools/carStats.mjs`.
{
  const { CARS, CAR_IDS, getCar } = await import('../src/physics/cars.js');
  const { addNitro, PHYSICS_VERSION } = await import('../src/physics/car.js');
  const { measureCar, statsMismatch } = await import('./carStats.mjs');
  const rookie = tracks.find((t) => t.id === 'rookie-oval');

  // the racer: CAR, the default, and nitro left alone changes nothing
  {
    const lapState = (ctrlFor) => {
      const car = createCar(rookie), drive = makeAutopilot(rookie);
      for (let k = 0; k < 60 * 60; k++) stepCar(car, rookie, ctrlFor(drive(car), car, k), dt);
      return JSON.stringify(car);
    };
    const plain = lapState((c) => c);
    const same = [
      lapState((c) => ({ ...c, nitro: false })),
      lapState((c) => ({ ...c, nitro: 0 })),
      lapState((c, car, k) => { if (k === 0) car.nitro = 0; return { ...c, nitro: true }; }), // empty tank: no push
    ].every((s) => s.replace(/"nitro":[0-9.e-]+,/, '') === plain.replace(/"nitro":[0-9.e-]+,/, ''));
    const car = createCar(rookie);
    check(CARS.racer.spec === CAR && getCar('nope') === CARS.racer && car.spec === CAR && !('spec' in JSON.parse(JSON.stringify(car))) &&
      PHYSICS_VERSION === 3 && same && CAR_IDS.length === 4 && CAR_IDS.every((id) => CARS[id].spec.id === id),
      `cars: ${CAR_IDS.join(', ')}; the racer (default) is CAR, physics v${PHYSICS_VERSION}; with nitro off, 0 or an empty ` +
      `tank it drives a minute of Rookie Oval bit for bit as without; car.spec stays out of saved car states`);
  }

  // the racer is pinned to physics v3 (v4 review fix): a hash of its whole state (every field v3 had, as exact JSON
  // numbers) every 10 s of a minute of the autopilot on Hairpin Valley and on Ramp Rally (jumps) and a minute of
  // seeded random controls on Canyon Run (walls, handbrake, reverse). RACER_V3_HASH is what the v3 code (3.0.0)
  // gives. If this fails, the racer's physics moved: saved best times, ghosts, medal times and trained networks
  // no longer fit it. Undo the change, or, if it is meant, bump PHYSICS_VERSION, run npm run medals and store the new hash.
  {
    const RACER_V3_HASH = 'b9f58c60';
    const V4_FIELDS = new Set(['nitro', 'boost', 'boosting']); // car fields v3 didn't have
    let h = 0x811c9dc5, walls = 0, air = 0, hb = 0;
    const fold = (car) => { // FNV-1a over the state as JSON
      const s = JSON.stringify(car, (k, v) => (V4_FIELDS.has(k) ? undefined : v));
      for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 0x01000193);
    };
    const byId = (id) => tracks.find((t) => t.id === id);
    for (const id of ['hairpin-valley', 'ramp-rally']) {
      const track = byId(id), car = createCar(track), drive = makeAutopilot(track);
      for (let k = 1; k <= 3600; k++) { stepCar(car, track, drive(car), dt); if (!car.grounded) air++; if (k % 600 === 0) fold(car); }
    }
    {
      const track = byId('canyon-run'), car = createCar(track), ctrl = { steer: 0, throttle: 0, handbrake: false };
      let seed = 20261020; // mulberry32
      const rnd = () => { seed = (seed + 0x6d2b79f5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
      for (let k = 1, hold = 0; k <= 3600; k++) {
        if (--hold <= 0) { hold = 6 + Math.floor(rnd() * 54); ctrl.steer = rnd() * 2 - 1; ctrl.throttle = rnd() * 2.4 - 0.9; ctrl.handbrake = rnd() < 0.15; }
        stepCar(car, track, ctrl, dt);
        if (car.hitWall) walls++;
        if (ctrl.handbrake) hb++;
        if (k % 600 === 0) fold(car);
      }
    }
    const hash = (h >>> 0).toString(16).padStart(8, '0');
    check(hash === RACER_V3_HASH, `the racer is still the v3 car: state hash ${hash} after 2 autopilot minutes (${air} airborne steps) and a ` +
      `random-control minute (${walls} wall-contact steps, handbrake in ${hb}) = the v3 code's ${RACER_V3_HASH}`);
  }

  // stats on the car picker = the physics
  {
    const off = [];
    for (const id of CAR_IDS) for (const o of statsMismatch(CARS[id].stats, measureCar(CARS[id].spec))) off.push(`${id} ${o.key} ${o.stored} -> ${o.measured}`);
    const s = (id, k) => CARS[id].stats[k];
    check(off.length === 0, `car stats match the physics (top speed ${CAR_IDS.map((id) => `${id} ${s(id, 'top')}`).join(', ')} km/h; ` +
      `with nitro ${CAR_IDS.map((id) => s(id, 'topNitro')).join(', ')})${off.length ? `; OFF: ${off.join(', ')} (run node tools/carStats.mjs)` : ''}`);
  }

  // every car finishes every track (the autopilot plans corners for that car's grip and braking)
  for (const id of CAR_IDS.filter((c) => c !== 'racer')) {
    const def = CARS[id], r = CARS.racer.stats;
    const grip = 11 * (def.stats.grip / r.grip), brake = 7.5 * (r.brake100 / def.stats.brake100);
    let done = 0, wall = 0, bad = 0, total = 0;
    const slow = [];
    for (const track of tracks) {
      const car = createCar(track, track.startIdx, def.spec), race = new RaceState(track), drive = makeAutopilot(track, grip, brake, def.spec.maxSpeed);
      while (!race.finished && race.time < 600) {
        stepCar(car, track, drive(car), dt);
        race.update(car, dt);
        if (car.hitWall) wall++;
        if (!finite(car)) { bad++; break; }
      }
      if (race.finished) { done++; total += race.finishTime; } else slow.push(track.def.name);
    }
    check(done === tracks.length && bad === 0, `${def.name}: the autopilot (grip ${grip.toFixed(1)}, braking ${brake.toFixed(1)} m/s²) finishes ` +
      `${done} of ${tracks.length} tracks in ${formatTime(total)} in all (wall contact in ${wall} steps)${slow.length ? `; NOT: ${slow.join(', ')}` : ''}`);
  }

  // walls, every car: no bounce (30° at 50 m/s) and no tunnelling at its top speed with nitro (+10 %), nitro held
  {
    let worst = 0, shots = 0, escapes = 0, where = '';
    for (const id of CAR_IDS) {
      const spec = CARS[id].spec, vTop = (CARS[id].stats.topNitro / 3.6) * 1.1;
      for (const track of tracks) {
        const i = track.startIdx + 15;
        const car = launch(track, i, 0, Math.PI / 6, 50);
        car.spec = spec;
        let touched = false, reb = 0;
        for (let k = 0; k < 90; k++) {
          stepCar(car, track, { steer: 0, throttle: 0 }, dt);
          const vn = car.vx * track.nx[car.idx] + car.vz * track.nz[car.idx];
          if (car.hitWall) touched = true;
          if (touched) reb = Math.max(reb, -vn);
        }
        if (!touched) reb = Infinity;
        if (reb > worst) { worst = reb; where = `${id} on ${track.def.name}`; }
        for (const f of [0.2, 0.55, 0.85]) {
          const j = Math.floor(track.count * f);
          for (const deg of [10, 30, 60, 90, -25, -60]) {
            const c = launch(track, j, 0, (deg * Math.PI) / 180, vTop);
            c.spec = spec;
            let prevIdx = c.idx;
            for (let k = 0; k < 90; k++) {
              addNitro(c, 1);
              stepCar(c, track, { steer: 0, throttle: 1, nitro: true }, dt);
              let jump = Math.abs(c.idx - prevIdx);
              if (track.closed) jump = Math.min(jump, track.N - jump);
              if (Math.abs(c.lat) > c._hw || jump > 30 || !finite(c)) { escapes++; break; }
              prevIdx = c.idx;
            }
            shots++;
          }
        }
      }
    }
    check(worst <= 1.0 + 1e-3 && escapes === 0, `walls, every car: a 30° hit at 50 m/s rebounds at most ${worst.toFixed(2)} m/s (${where}; ` +
      `limit 1.0); ${shots} wall shots at each car's top speed with nitro + 10 % (up to ${(CARS.thunder.stats.topNitro * 1.1).toFixed(0)} km/h), ${escapes} left the road`);
  }

  // no NaN, every car: random controls with nitro (on/off/analogue, refills), handbrake and respawns
  {
    let steps = 0, bad = 0, below = 0, boosted = 0;
    let seed = 4242;
    const rnd = () => ((seed = (seed * 1103515245 + 12345) >>> 0) / 4294967296);
    for (const id of CAR_IDS) for (const track of tracks) {
      const car = createCar(track, track.startIdx, CARS[id].spec);
      const ctrl = { steer: 0, throttle: 0, handbrake: false, nitro: false };
      for (let k = 0; k < 1500; k++) {
        if (k % 30 === 0) {
          ctrl.steer = rnd() * 2 - 1;
          ctrl.throttle = rnd() * 2.4 - 1.2 > 0 ? 1 : rnd() * 2 - 1;
          ctrl.handbrake = rnd() < 0.15;
          const n = rnd();
          ctrl.nitro = n < 0.4 ? false : n < 0.8 ? true : rnd();
          if (rnd() < 0.3) addNitro(car, rnd());
        }
        if (k % 500 === 0) placeCar(car, track, Math.floor(rnd() * (track.count - 1)));
        stepCar(car, track, ctrl, dt);
        steps++;
        if (car.boosting) boosted++;
        if (!finite(car) || !(car.nitro >= 0 && car.nitro <= 1)) { bad++; placeCar(car, track, track.startIdx); }
        if (car.grounded && car.y < car.groundY - 0.05) below++;
      }
    }
    check(bad === 0 && below === 0 && boosted > steps / 10, `no NaN, every car: ${steps} random-control steps with nitro (boosting in ${boosted}), ` +
      `${bad} non-finite states or tanks out of 0..1, ${below} steps below the road`);
  }

  // nitro rules: full tank at the start, kept on respawn; burns spec.nitroTime s at full nitro (half rate at 0.5) on the
  // ground in a forward gear; no push or burn in the air, in reverse, while braking or with the handbrake held; it
  // makes every car faster
  {
    const straight = buildTrack({ id: 'nitro-straight', name: 'Nitro straight', type: 'sprint', laps: 1, width: 30, checkpoints: [],
      points: Array.from({ length: 31 }, (_, k) => [0, k * 200, 0]) });
    const ok = [];
    for (const id of CAR_IDS) {
      const spec = CARS[id].spec;
      const car = createCar(straight, 5, spec);
      let rules = car.nitro === 1;
      car.nitro = 0.4; placeCar(car, straight, 20); rules &&= car.nitro === 0.4;
      rules &&= addNitro(car, 5) === 1 && addNitro(car, -7) === 0 && addNitro(car, 0.25) === 0.25;
      // full tank, full nitro from a standstill: lasts nitroTime (to the step), boosting all along
      const a = createCar(straight, 5, spec);
      let steps = 0;
      for (let k = 0; k < 6000 && a.nitro > 0; k++) { stepCar(a, straight, { steer: 0, throttle: 0, nitro: true }, dt); if (a.boosting) steps++; }
      rules &&= Math.abs(steps * dt - spec.nitroTime) < dt + 1e-9;
      // half nitro burns at half rate
      const b = createCar(straight, 5, spec);
      for (let k = 0; k < 60; k++) stepCar(b, straight, { steer: 0, throttle: 1, nitro: 0.5 }, dt);
      rules &&= Math.abs(1 - b.nitro - (0.5 * 60 * dt) / spec.nitroTime) < 1e-9 && b.boost === 0.5;
      // braking from 108 km/h, then reversing: no boost, no burn
      const c = createCar(straight, 100, spec); // 200 m in, room to reverse
      placeCar(c, straight, 100, { x: straight.px[100], z: straight.pz[100], yaw: 0, vx: 0, vz: 30, idx: 100, laps: 0 });
      let pushed = 0;
      for (let k = 0; k < 60 * 6; k++) { stepCar(c, straight, { steer: 0, throttle: -1, nitro: true }, dt); if (c.boosting) pushed++; }
      rules &&= c.nitro === 1 && pushed === 0 && c.forwardSpeed < -1;
      // handbrake held (v4 review fix): no boost and no burn, standing for 2 s or at 100 km/h with the throttle open
      const h = createCar(straight, 100, spec), hf = createCar(straight, 100, spec);
      for (let k = 0; k < 120; k++) { stepCar(h, straight, { steer: 0, throttle: 0, handbrake: true, nitro: true }, dt); if (h.boosting) pushed++; }
      placeCar(hf, straight, 100, { x: straight.px[100], z: straight.pz[100], yaw: 0, vx: 0, vz: 100 / 3.6, idx: 100, laps: 0 });
      for (let k = 0; k < 60; k++) { stepCar(hf, straight, { steer: 0, throttle: 1, handbrake: true, nitro: true }, dt); if (hf.boosting) pushed++; }
      rules &&= pushed === 0 && h.nitro === 1 && hf.nitro === 1 && Math.hypot(h.x - straight.px[100], h.z - straight.pz[100]) < 0.05;
      ok.push(rules ? id : `${id} FAILED`);
    }
    // airborne: on a kicker track, holding nitro over a jump burns nothing while in the air
    let airSteps = 0, airBurn = 0;
    for (const track of tracks.filter((t) => (t.kickers ?? []).length)) {
      const car = createCar(track, track.startIdx, CARS.racer.spec), drive = makeAutopilot(track, 14);
      for (let k = 0; k < 60 * 120 && airSteps < 200; k++) {
        const c = drive(car);
        if (!car.grounded) {
          addNitro(car, 1); // nitro held with a full tank through the whole flight
          stepCar(car, track, { ...c, throttle: 1, nitro: true }, dt);
          airSteps++;
          if (car.nitro !== 1 || car.boosting) airBurn++;
        } else stepCar(car, track, c, dt);
      }
    }
    // faster: 0-200 km/h and top speed, from the stored (and checked) stats
    const faster = CAR_IDS.every((id) => CARS[id].stats.accel200n < CARS[id].stats.accel200 - 0.5 && CARS[id].stats.topNitro > CARS[id].stats.top + 5);
    check(ok.every((s) => !s.includes('FAILED')) && airSteps > 100 && airBurn === 0 && faster,
      `nitro: full tank at the start and kept on respawn, lasts its nitroTime (${CAR_IDS.map((id) => `${CARS[id].spec.nitroTime} s`).join(' / ')}), ` +
      `half nitro burns half as fast, nothing in reverse, braking, with the handbrake or in the air (${airSteps} airborne steps); 0-200 km/h with nitro ` +
      `${CAR_IDS.map((id) => `${CARS[id].stats.accel200n} s (${CARS[id].stats.accel200})`).join(', ')} [${ok.join(', ')}]`);
  }

  // keyboard lane keeping, every car: a digital-steering driver holding speed on a straight never builds a fishtail
  // (from the v2 physics review: 4 speeds × 3 dead bands × 3 aim distances, the input.js key ramp)
  {
    const lane = buildTrack({ id: 'lane', name: 'Lane', type: 'sprint', laps: 1, width: 40, checkpoints: [], points: Array.from({ length: 41 }, (_, k) => [0, k * 200, 0]) });
    const wrapA = (a) => Math.atan2(Math.sin(a), Math.cos(a));
    const res = [];
    let fails = 0;
    for (const id of CAR_IDS) {
      let fish = 0;
      for (const kmh of [120, 160, 200, 240]) for (const dead of [0.02, 0.04, 0.08]) for (const look of [20, 35, 50]) {
        const v = kmh / 3.6, i0 = 20;
        const car = createCar(lane, i0, CARS[id].spec);
        placeCar(car, lane, i0, { x: lane.px[i0] + 2, z: lane.pz[i0], yaw: 0, vx: 0, vz: v, idx: i0, laps: 0 });
        let steer = 0, maxSlip = 0, late = 0;
        for (let s = 0; s < 60 * 15; s++) {
          const gx = -car.x, gz = look, fx = Math.sin(car.yaw), fz = Math.cos(car.yaw);
          const ang = Math.atan2(gx * fz - gz * fx, gx * fx + gz * fz);
          const target = ang > dead ? 1 : ang < -dead ? -1 : 0;
          const rate = target === 0 || target * steer < 0 ? 10 : 7 + (3.2 - 7) * Math.min(1, car.speed / 50);
          steer += Math.sign(target - steer) * Math.min(Math.abs(target - steer), rate * dt);
          stepCar(car, lane, { steer, throttle: car.forwardSpeed < v ? 1 : 0 }, dt);
          maxSlip = Math.max(maxSlip, Math.abs(Math.atan2(car.sideSpeed, car.forwardSpeed)) * 57.3);
          if (s > 600) late = Math.max(late, Math.abs(wrapA(car.yaw)) * 57.3);
        }
        if (late > 5 || maxSlip > 10) fish++;
      }
      fails += fish;
      res.push(`${id} ${fish}/36`);
    }
    check(fails === 0, `keyboard lane keeping at 120-240 km/h, no fishtail with any car: ${res.join(', ')}`);
  }

  // jumps, every car: the autopilot over every kicker (a steer key held through some flights): no bounce, no spin
  {
    const wrapA = (a) => Math.atan2(Math.sin(a), Math.cos(a));
    let jumps = 0, bounces = 0, spins = 0, maxAir = 0;
    for (const id of CAR_IDS) for (const track of tracks.filter((t) => (t.kickers ?? []).length)) for (const hold of [0, 1]) {
      const car = createCar(track, track.startIdx, CARS[id].spec), drive = makeAutopilot(track, 13);
      const goal = track.closed ? car.prog + track.N : track.count - 12;
      let yaw0 = 0, landed = -1e9, watch = 0;
      for (let k = 0; k < 60 * 300 && car.prog < goal; k++) {
        const c = drive(car);
        if (!car.grounded && hold) c.steer = 1;
        const g0 = car.grounded;
        stepCar(car, track, c, dt);
        if (g0 && !car.grounded) { jumps++; if (k - landed < 30) bounces++; yaw0 = car.yaw; }
        if (!g0 && car.grounded) { maxAir = Math.max(maxAir, Math.abs(wrapA(car.yaw - yaw0)) * 57.3); landed = k; watch = 120; }
        if (watch > 0 && watch-- && Math.abs(wrapA(car.yaw - Math.atan2(track.tx[car.idx], track.tz[car.idx]))) > Math.PI / 2) { spins++; watch = 0; }
      }
    }
    check(jumps >= 40 && bounces === 0 && spins === 0 && maxAir < 35, `jumps, every car: ${jumps} jumps, ${bounces} bounces, ${spins} spins; ` +
      `holding a steer key through a whole flight turns the car at most ${maxAir.toFixed(1)}° (limit 35°)`);
  }
}

// ---- 5: sensors ------------------------------------------------------------------
{
  check(INPUT_LABELS.length === INPUT_COUNT, `sensor inputs: ${INPUT_COUNT} (${INPUT_LABELS.join(', ')})`);
  let bad = 0, n = 0;
  const inputs = new Float32Array(INPUT_COUNT);
  for (const track of tracks) {
    const car = createCar(track);
    const race = new RaceState(track, 1);
    const drive = makeAutopilot(track);
    for (let k = 0; k < 60 * 40; k++) {
      stepCar(car, track, drive(car), dt);
      race.update(car, dt);
      if (k % 10) continue;
      sense(track, car, race, inputs);
      n++;
      for (const v of inputs) if (!(v >= -1.0001 && v <= 1.0001)) { bad++; break; }
    }
  }
  check(bad === 0, `sensor inputs finite and within -1..1 (${n} samples on all tracks, ${bad} bad)`);

  const net = new NeuralNetwork([INPUT_COUNT, 12, 2]);
  const x = Float32Array.from({ length: INPUT_COUNT }, () => Math.random() * 2 - 1);
  const xm = mirrorInputs(x, new Float32Array(INPUT_COUNT));
  const a = { ...driveNetwork(net, x, new Float32Array(INPUT_COUNT), {}) };
  const b = { ...driveNetwork(net, xm, new Float32Array(INPUT_COUNT), {}) };
  check(Math.abs(a.steer + b.steer) < 1e-5 && Math.abs(a.throttle - b.throttle) < 1e-5,
    'AI driver is left/right symmetric (mirrored inputs: opposite steer, same throttle)');
}

// ---- 6 + 7: short training run, save / load ---------------------------------------
{
  const track = tracks[0];
  // 'crash': a random network rarely gets round cleanly, so finishing shows evolution at work
  // (with 'ride' a random generation-0 car often bounces its way round; see 6d)
  const trainer = new Trainer({ tracks: [track], populationSize: 60, mutationRate: 0.1, hidden: [12], laps: 1, walls: 'crash' });
  while (trainer.generation < 40 && !trainer.bestTimes[track.id]?.finish) trainer.step(dt);
  const fin = trainer.bestTimes[track.id]?.finish;
  check(fin != null, `neuroevolution finishes ${track.name} in generation ${trainer.generation} (${formatTime(fin)})`);
  // finish the generation, so the best network (the finisher or better) has been picked
  for (const g = trainer.generation; trainer.generation === g;) trainer.step(dt);

  const saved = JSON.parse(JSON.stringify(trainer.exportBest()));
  const { net } = parseNetworkFile(saved);
  const input = new Float32Array(net.sizes[0]).fill(0.5);
  const a = Array.from(trainer.bestNet.forward(input));
  const b = Array.from(net.forward(input));
  check(saved.version === 2 && a.every((v, i) => v === b[i]), 'saved network (file version 2) gives exactly the same outputs after loading');
  check(saved.settings?.walls === 'crash', `the saved file records the wall rule (settings.walls = ${saved.settings?.walls})`);

  // The loaded network must drive exactly the same race (watch / ghost replay what training saw).
  const lap = (n) => {
    const car = createCar(track), race = new RaceState(track, 1), ai = new AIDriver(n);
    while (!race.finished && race.time < 300) { stepCar(car, track, ai.drive(track, car, race), dt); race.update(car, dt); }
    return race.finished ? race.finishTime : null;
  };
  const t1 = lap(trainer.bestNet), t2 = lap(net);
  check(t1 != null && t1 === t2, `the loaded network drives the identical lap (${formatTime(t1)} = ${formatTime(t2)})`);

  const v1 = { format: 'trackmania-lite-network', version: 1, network: new NeuralNetwork([11, 12, 2]).toJSON() };
  let msg = '';
  try { parseNetworkFile(v1); } catch (e) { msg = e.message; }
  check(/v1/.test(msg) && /train/i.test(msg), `a v1 network file is rejected with a clear message ("${msg.slice(0, 60)}...")`);
}

// ---- 6b: the AI learns to brake for hairpins (Hairpin Valley, five 16 m switchbacks) ----
{
  const track = tracks.find((t) => t.id === 'hairpin-valley');
  let gens = null, tries = 0, time = null;
  while (gens == null && tries < 2) { // one retry: evolution is random (typically 5-45 generations)
    tries++;
    const trainer = new Trainer({ tracks: [track], populationSize: 80, mutationRate: 0.1, hidden: [12], laps: 1, walls: 'crash' });
    while (trainer.generation < 100 && !trainer.bestTimes[track.id]?.finish) trainer.step(dt);
    if (trainer.bestTimes[track.id]?.finish) { gens = trainer.generation; time = trainer.bestTimes[track.id].finish; }
  }
  check(gens != null, `neuroevolution finishes ${track.name} (brakes for hairpins) in generation ${gens}${tries > 1 ? ' (second try)' : ''}, lap ${formatTime(time)}`);
}

// ---- 6c: wall rules: 'ride' keeps a car that hits a wall, 'crash' puts it out ----
{
  const track = tracks[0];
  const outcome = {};
  for (const walls of ['ride', 'crash']) {
    const trainer = new Trainer({ tracks: [track], populationSize: 4, laps: 1, walls });
    const a = trainer.agents[0];
    const i = track.startIdx + 40;
    const yaw = Math.atan2(track.tx[i], track.tz[i]) + 0.5; // 29° towards the left wall
    const lat = track.hw[i] - 2.5;
    placeCar(a.car, track, i, { x: track.px[i] + track.nx[i] * lat, z: track.pz[i] + track.nz[i] * lat, yaw,
      vx: Math.sin(yaw) * 30, vz: Math.cos(yaw) * 30, idx: i, laps: 0 });
    a.maxProg = a.car.prog;
    for (let k = 0; k < 30 && !a.touchedWall; k++) trainer.step(dt);
    for (let k = 0; k < 5; k++) trainer.step(dt);
    outcome[walls] = { touched: a.touchedWall, alive: a.alive, reason: a.deathReason };
  }
  const { ride, crash } = outcome;
  check(ride.touched && ride.alive && crash.touched && !crash.alive && crash.reason === 'wall',
    `wall rules: a car that hits a wall keeps driving with 'ride' (alive ${ride.alive}) and is out with 'crash' (${crash.reason || 'still alive'})`);
}

// ---- 6d: training still learns with the default 'ride' rule ----
// A random 'ride' car often finishes Rookie Oval already, so "a car finished" proves nothing here
// (nor does a faster best lap: fresh random cars every generation find one too). Evolution shows
// in the whole population (30 cars, measured over 45 runs, and 20 with selection switched off):
// a random population averages 130-520 fitness with 0-6 finishers; after 8 generations of
// evolution the average is 760-1460 with 9-27 finishers. (Physics v2 walls cost so little that
// these were 220-730 and 1060-1570, and the limit was 900; v3 walls stop more random cars.)
{
  const track = tracks[0];
  let trainer, finishers, tries = 0;
  do { // one retry: evolution is random
    tries++;
    trainer = new Trainer({ tracks: [track], populationSize: 30, mutationRate: 0.1, hidden: [12], laps: 1 });
    finishers = [];
    trainer.onRunEnd = (t, d) => finishers.push(d.finished ?? 0);
    while (trainer.generation < 8) trainer.step(dt);
  } while (trainer.history[7].avg < 700 && tries < 2);
  const h = trainer.history;
  check(trainer.cfg.walls === 'ride' && h[7].avg >= 700,
    `'ride' (the default) training learns on ${track.name}: average fitness ${h[0].avg.toFixed(0)} -> ${h[7].avg.toFixed(0)} ` +
    `(need 700), finishers ${finishers[0]} -> ${finishers[7]} of 30 in 8 generations${tries > 1 ? ' (second try)' : ''}`);
  check(trainer.exportBest().settings?.walls === 'ride', `a 'ride' network file records the wall rule (settings.walls = ride)`);
}

// ---- 8: Max-speed hand-over: the session moves to the worker and back mid-run, losing nothing ----
// TrainerHost (src/ai/trainWorker.js) is what the Web Worker runs; here structuredClone stands in
// for postMessage. The genetic algorithm draws from Math.random, whose state can't be handed over,
// so both copies get the same seeded sequence: then the handed-over session must match one that
// never moved, step for step (physics and scoring are deterministic).
{
  const { TrainerHost } = await import('../src/ai/trainWorker.js');
  const track = tracks[0];
  const flat = (x) => JSON.stringify(x, (k, v) => (ArrayBuffer.isView(v) ? Array.from(v) : v));
  const seeded = (s) => () => ((s = (s * 1103515245 + 12345) >>> 0) / 4294967296);
  const random = Math.random;
  let page, ref, samePop = false, followed = true, inWorker = 0;
  try {
    Math.random = seeded(7);
    ref = new Trainer({ tracks: [track], populationSize: 12, walls: 'crash' });
    for (let k = 0; k < 400; k++) ref.step(dt); // mid-run
    page = Trainer.fromState(structuredClone(ref.exportState()), tracks);
    samePop = flat(page.population.exportState()) === flat(ref.population.exportState()) && page.simTime === ref.simTime;
    const sent = [];
    const host = new TrainerHost((msg) => sent.push(structuredClone(msg)));
    Math.random = seeded(99);
    for (let run = 1; run <= 3; run++) { // 300 steps here (1× / 6×), 2000 in the worker (Max), back
      for (let k = 0; k < 300; k++) page.step(dt);
      host.handle(structuredClone({ type: 'start', runId: run, state: page.exportState(), defs: [track.def], selected: -1 }));
      host.advance(2000);
      host.handle({ type: 'return', runId: run });
      host.handle({ type: 'return', runId: run - 1 }); // stale: no answer
      let state = null;
      for (const m of sent.splice(0)) {
        if (m.type === 'generation' && m.runId === run) { page.followGeneration(m); inWorker++; }
        else if (m.type === 'state' && m.runId === run && !state) state = m.state;
        else followed = false;
      }
      // until the session comes back, the page's copy follows the worker generation by generation
      followed &&= !!state && page.generation === state.generation && flat(page.history) === flat(state.history) &&
        flat(page.population.exportState()) === flat(state.population);
      page = Trainer.fromState(state, tracks);
    }
    Math.random = seeded(99);
    for (let k = 0; k < 3 * 2300; k++) ref.step(dt);
  } finally {
    Math.random = random;
  }
  check(samePop && followed && inWorker > 0 && flat(page.exportState()) === flat(ref.exportState()),
    `Max-speed hand-over: 3 trips to the worker and back mid-run (${inWorker} generations bred there) end in exactly the ` +
    `same state as a session that never moved (generation ${page.generation}, ${page.aliveCount} cars at ${page.simTime.toFixed(2)} s)`);
}

// ---- 9: player ghosts: a recorded run packs small and replays on the race clock ----
// Recorded like PlayMode does: after every physics step, with the step count since GO as the
// clock, and a respawn (back to the last checkpoint) in the middle. The packed run goes through
// JSON and must replay within a few cm at every physics step (exactly the respawn's jump at its
// step, gone after the finish). Saved data that doesn't match or decode is ignored, never thrown.
{
  const { GhostRecorder, GhostPlayer, packGhost, unpackGhost } = await import('../src/game/replay.js');
  let worst = 0, worstAt = '', worstYaw = 0, atSamples = 0, bytes = 0, minutes = 0, wallSteps = 0, synced = true;
  // Hairpin Valley with a corner-cutting autopilot that hits the walls; Ramp Rally (jumps) driven clean
  for (const [track, grip] of [[tracks[1], 21], [tracks[2], 11]]) {
    const car = createCar(track), race = new RaceState(track), drive = makeAutopilot(track, grip);
    const rec = new GhostRecorder();
    const truth = []; // [step, x, y, z, yaw] after each step (after the jump at the respawn step)
    rec.add(0, car, true);
    truth.push([0, car.x, car.y, car.z, car.yaw]);
    let step = 0, jumped = false;
    while (!race.finished && step < 60 * 600) {
      stepCar(car, track, drive(car), dt);
      step++;
      race.update(car, dt);
      if (car.hitWall) wallSteps++;
      rec.add(step, car, race.finished);
      if (!jumped && race.nextGate === 3 && step % 2) { // respawn at the last checkpoint, off the 30 Hz grid
        jumped = true;
        rec.beforeJump(step, car);
        const r = race.respawn, j = r.idx + 6;
        placeCar(car, track, j, { ...r, idx: j, x: track.px[j], z: track.pz[j] });
        rec.afterJump(step, car);
      }
      truth.push([step, car.x, car.y, car.z, car.yaw]);
    }
    const saved = JSON.parse(JSON.stringify(packGhost(rec, { track, laps: race.laps, time: race.finishTime })));
    const ghost = unpackGhost(saved, track, race.laps);
    if (!ghost) { synced = false; continue; }
    const play = new GhostPlayer(ghost), sampled = new Set(rec.steps);
    for (const [s, x, y, z, yaw] of truth) {
      if (!play.pose(s)) { synced = false; break; }
      const e = Math.hypot(play.car.x - x, play.car.y - y, play.car.z - z);
      if (e > worst) { worst = e; worstAt = `${track.def.name} step ${s}`; }
      if (sampled.has(s)) atSamples = Math.max(atSamples, e);
      worstYaw = Math.max(worstYaw, Math.abs(Math.atan2(Math.sin(play.car.yaw - yaw), Math.cos(play.car.yaw - yaw))));
    }
    synced &&= jumped && ghost.end === step && Math.abs(ghost.end * dt - race.finishTime) < 1e-6 && !play.pose(step + 0.01);
    bytes += JSON.stringify(saved).length;
    minutes += race.finishTime / 60;
  }
  const perMin = bytes / 1024 / minutes;
  // v4: a ghost per track and car; at the bronze time of each (a slow best run) they would take this much
  const { MEDALS } = await import('../src/tracks/medals.js');
  const everyGhost = Object.values(MEDALS).flatMap((m) => Object.values(m.cars));
  const bronzeMin = everyGhost.reduce((sum, m) => sum + m.bronze, 0) / 60;
  check(synced && worst < 0.03 && atSamples < 0.01 && worstYaw < 0.005 && perMin < 30,
    `ghost replay: 2 recorded autopilot runs (one respawn each, ${wallSteps} wall-contact steps) replay within ` +
    `${(worst * 100).toFixed(1)} cm at every physics step (worst: ${worstAt}; ${(atSamples * 100).toFixed(2)} cm at the ` +
    `samples, yaw ${(worstYaw * 1000).toFixed(1)} mrad), on the race clock; packed ${perMin.toFixed(1)} K characters per minute ` +
    `(${everyGhost.length} ghosts, one per track and car, at their bronze times: ${((perMin * bronzeMin) / 1024).toFixed(2)} M characters)`);

  // bad saved data: anything foreign or broken is ignored without throwing
  const track = tracks[0], rec = new GhostRecorder(), car = createCar(track);
  for (let s = 0; s <= 120; s++) { if (s) stepCar(car, track, { steer: 0, throttle: 1 }, dt); rec.add(s, car, s === 120); }
  const good = packGhost(rec, { track, laps: 3, time: 2 });
  const bad = [null, 'ghost', 42, [], {}, { ...good, format: 3 }, { ...good, format: 1 }, { ...good, physics: 2 }, { ...good, track: 'hairpin-valley' },
    { ...good, laps: 1 }, { ...good, sig: '1:1' }, { ...good, time: NaN }, { ...good, time: 9 }, { ...good, n: good.n + 1 },
    { ...good, n: 1e9 }, { ...good, steps: 118 }, { ...good, data: good.data.slice(0, -8) }, { ...good, data: `${good.data}AAAA` },
    { ...good, data: '%%%not base64%%%' }, { ...good, data: null }];
  let ignored = 0, threw = 0;
  for (const b of bad) {
    try { if (unpackGhost(b, track, 3) === null) ignored++; } catch { threw++; }
  }
  // records and settings in localStorage (a stand-in for the browser's) behave the same
  const store = new Map();
  globalThis.localStorage = { getItem: (k) => store.get(k) ?? null, setItem: (k, v) => store.set(k, String(v)), removeItem: (k) => store.delete(k) };
  const S = await import('../src/game/storage.js');
  let storeOk = true;
  try {
    for (const junk of ['null', '[]', '7', '{"rookie-oval":5}', '{"rookie-oval":{"time":50,"splits":[]}}', '{"rookie-oval":{"time":"x","physics":3}}', '{oops']) {
      store.set('trackrush.records.v3', junk);
      storeOk &&= S.getRecord('rookie-oval') === null;
      store.set('trackrush.settings', junk);
      storeOk &&= S.getSetting('ghost') === true;
      store.set('trackrush.ghost.rookie-oval', junk);
      storeOk &&= unpackGhost(S.loadGhost('rookie-oval'), track, 3) === null;
    }
    store.clear();
    storeOk &&= S.submitRecord('rookie-oval', 'racer', 60, [20, 40, 60]) && !S.submitRecord('rookie-oval', 'racer', 61, []) && S.getRecord('rookie-oval')?.time === 60;
    storeOk &&= S.saveGhost('rookie-oval', 'racer', good) && unpackGhost(S.loadGhost('rookie-oval'), track, 3)?.end === 120;
    S.setSetting('ghost', false);
    storeOk &&= S.getSetting('ghost') === false;
    // storage full: the new ghost isn't saved and the old one goes (it no longer matches the best time)
    globalThis.localStorage.setItem = () => { throw new Error('QuotaExceededError'); };
    storeOk &&= !S.saveGhost('rookie-oval', 'racer', good) && S.loadGhost('rookie-oval') === null;
  } catch {
    storeOk = false;
  } finally {
    delete globalThis.localStorage;
  }
  check(ignored === bad.length && threw === 0 && unpackGhost(good, track, 3) !== null && storeOk,
    `ghost data: ${ignored} of ${bad.length} foreign or broken saved ghosts ignored (${threw} threw); junk records and ` +
    `settings in storage read as none / defaults; a record, a ghost and a setting round-trip; a full storage drops the old ghost`);
}

// ---- 10: medal times (src/tracks/medals.js, written by tools/medals.mjs; v4: per track and car) ----
// Every track has medal times for its Drive race (all its laps, this layout) with every car, made with the
// current physics and scoring rules (the score's points refill the nitro the author runs burn), in order
// and rounded as documented; and the autopilot runs behind one short race's author times (every car, nitro
// on the straights with the score's refills) still drive exactly those times. A failure here usually
// means: run `npm run medals`.
{
  const { MEDALS, MEDALS_PHYSICS, MEDALS_SCORE_RULES, medalTimes, medalFor, nextMedal } = await import('../src/tracks/medals.js');
  const { driveRace, medalSet } = await import('./medals.mjs');
  const { PHYSICS_VERSION } = await import('../src/physics/car.js');
  const { SCORE_RULES } = await import('../src/game/score.js');
  const { CAR_IDS } = await import('../src/physics/cars.js');
  let covered = 0, ordered = 0;
  for (const track of tracks) {
    for (const car of CAR_IDS) {
      const m = medalTimes(track, car); // null unless the id, car, layout, laps, physics and scoring rules all match
      if (!m) continue;
      covered++;
      const tidy = medalSet(m.author);
      if (m.author < m.gold && m.gold < m.silver && m.silver < m.bronze &&
        tidy.gold === m.gold && tidy.silver === m.silver && tidy.bronze === m.bronze) ordered++;
    }
  }
  const pairs = tracks.length * CAR_IDS.length, t0 = tracks[0];
  const none = medalTimes(t0, 'bus') === null && medalTimes(t0, '__proto__') === null && medalTimes(t0, 'racer', t0.laps + 1) === null &&
    medalTimes(t0) === medalTimes(t0, 'racer');
  check(MEDALS_PHYSICS === PHYSICS_VERSION && MEDALS_SCORE_RULES === SCORE_RULES && covered === pairs && ordered === pairs &&
    Object.keys(MEDALS).length === tracks.length && none,
    `medal times: ${covered} of ${pairs} tracks × cars have them for their Drive race under physics v${MEDALS_PHYSICS} ` +
    `(car.js: v${PHYSICS_VERSION}) and scoring rules v${MEDALS_SCORE_RULES} (score.js: v${SCORE_RULES}); author < gold < silver < bronze ` +
    `on ${ordered}; none for an unknown car or another lap count`);

  // the shortest race whose racer author run touched a wall (so a change to the wall physics shows up too), with every car
  const runs = tracks.filter((t) => MEDALS[t.id]?.cars?.racer?.run);
  const key = (t) => (MEDALS[t.id].cars.racer.run.wallSteps > 0 ? 0 : 1e6) + MEDALS[t.id].cars.racer.author;
  const track = runs.reduce((a, b) => (key(b) < key(a) ? b : a), runs[0]);
  if (!track) check(false, 'medal author runs: medals.js has no runs');
  else {
    const res = CAR_IDS.map((car) => {
      const m = MEDALS[track.id].cars[car], r = driveRace(track, m.run, car);
      return { car, m, r, same: r.finished && r.steps === m.run.steps && Math.round(r.time * 1000) === Math.round(m.author * 1000) };
    });
    const m = MEDALS[track.id].cars.racer, r = res[0].r;
    const rules = medalFor(m, r.time) === 'author' && medalFor(m, m.author + 0.001) === 'gold' && medalFor(m, m.bronze + 0.001) === null &&
      nextMedal(m, null)?.medal === 'bronze' && nextMedal(m, m.gold)?.medal === 'author' && nextMedal(m, r.time) === null;
    check(res.every((x) => x.same) && rules,
      `medal author runs: on ${track.def.name} the sweep's autopilot (nitro on the straights, the score's refills) drives ` +
      res.map((x) => `${x.car} ${formatTime(x.r.finished ? x.r.time : null)} (aLat ${x.m.run.aLat}, lookK ${x.m.run.lookK}, ${x.r.steps} steps` +
        `${x.same ? '' : `; medals.js: ${formatTime(x.m.author)}, ${x.m.run.steps} steps`})`).join(', ') +
      `, as in medals.js; medals are awarded to the millisecond`);
  }
}

// ---- 11: car models (v4, src/game/carMesh.js: CarModel({car}), carProfile, the nitro jets) ----
// Each car's look is the racer's model reshaped; it must stay finite and about the size of the physics
// capsule (radius 1 m, 2.2 m half length), so what you see is what hits the walls. Ghost models need no DOM.
{
  const THREE = await import('../vendor/three.module.min.js');
  const { CarModel, carProfile } = await import('../src/game/carMesh.js');
  const { CAR_IDS, CARS } = await import('../src/physics/cars.js');
  const rookie = tracks.find((t) => t.id === 'rookie-oval');
  const out = [];
  let bad = 0;
  for (const id of [...CAR_IDS, 'no-such-car']) {
    const m = new CarModel({ car: id, ghost: true });
    const box = new THREE.Box3();
    let nan = 0;
    m.root.updateMatrixWorld(true);
    m.body.traverse((o) => {
      if (!o.isMesh) return;
      for (const v of o.geometry.attributes.position.array) if (!Number.isFinite(v)) nan++;
      box.expandByObject(o);
    });
    const profile = carProfile(id);
    // the jets: lit while boosting, out once it stops (after their fade)
    const car = createCar(rookie, rookie.startIdx, (CARS[id] ?? CARS.racer).spec);
    const lit = [];
    for (const boosting of [true, false]) {
      car.boosting = boosting; car.boost = boosting ? 1 : 0;
      for (let k = 0; k < 30; k++) m.update(car, rookie, dt);
      lit.push(m.flame.jets.visible);
    }
    const ok = nan === 0 && box.max.x < 1.25 && box.min.x > -1.25 && box.max.z < 2.8 && box.min.z > -2.8 && box.max.y < 1.7 &&
      profile.parts.length > 0 && m.flame.pipes.length > 0 && lit[0] && !lit[1] && m.carId === (CAR_IDS.includes(id) ? id : 'racer');
    if (!ok) bad++;
    out.push(`${id} ${box.max.x.toFixed(2)} x ${box.min.z.toFixed(2)}..${box.max.z.toFixed(2)} m`);
    m.dispose();
  }
  check(bad === 0, `car models: ${out.join(', ')} (half width x length); finite, |x| < 1.25 m, |z| < 2.8 m, ` +
    'unknown id -> racer, silhouettes for the menu, nitro jets lit only while boosting');
}

// ---- 12: style score (v4, src/game/score.js: points for clean driving, nitro refills, best scores) ----
// The scorer reads only the car's state and the race's gates, once per physics step, so a run always scores
// the same. Clean driving must pay: a clean run beats a wall-hitting one; drifts and jumps score; banked
// points refill the nitro tank (a nitro-using autopilot gets faster with the refills); respawns cost points
// and refill nothing; stored best scores (per track and car) survive junk in localStorage.
{
  const { ScoreState, SCORE, formatPoints } = await import('../src/game/score.js');
  const { addNitro } = await import('../src/physics/car.js');
  const { CARS } = await import('../src/physics/cars.js');
  const { makeAutopilot: medalPilot } = await import('./medals.mjs'); // aims further ahead: a smoother line
  const byId = (id) => tracks.find((t) => t.id === id);
  /** One scored Drive race: drive(car) gives the controls; opts {spec, nitro (use it on straights), refill}. */
  const scoredRace = (track, drive, { spec = CAR, nitro = false, refill = true } = {}) => {
    const car = createCar(track, track.startIdx, spec), race = new RaceState(track), score = new ScoreState(track, { nitro: refill });
    const events = [];
    let steps = 0;
    while (!race.finished && steps < 60 * 900) {
      const c = drive(car);
      c.nitro = nitro && c.throttle === 1 && Math.abs(c.steer) < 0.25;
      stepCar(car, track, c, dt);
      race.update(car, dt);
      const ev = score.update(car, race, dt);
      if (ev) events.push(...ev);
      steps++;
    }
    return { race, score, events, car };
  };
  const sig = (r) => r.events.map((e) => `${e.kind}${e.points}`).join(',');

  // 12a. deterministic, and a clean race scores exactly what the rules say
  const rookie = byId('rookie-oval');
  const a = scoredRace(rookie, makeAutopilot(rookie)), b = scoredRace(rookie, makeAutopilot(rookie));
  const gates = a.race.gates.length;
  const cps = Array.from({ length: gates }, (_, i) => SCORE.cpPoints * Math.min(SCORE.comboMax, i + 1)).reduce((x, y) => x + y, 0);
  const expect = cps + SCORE.cleanLap * a.race.laps + SCORE.cleanRun;
  check(a.score.total === b.score.total && sig(a) === sig(b) && a.score.counts.wallHits === 0 && a.score.total === expect,
    `score: the clean autopilot on ${rookie.def.name} scores ${formatPoints(a.score.total)} twice in a row with the same ${a.events.length} events ` +
    `(${gates} clean gates up to x${SCORE.comboMax}, ${a.race.laps} clean laps, clean run: ${formatPoints(expect)} expected)`);

  // 12b. clean driving pays: on Hairpin Valley the clean autopilot outscores a corner-cutting one that hits the walls
  const hairpin = byId('hairpin-valley');
  const clean = scoredRace(hairpin, makeAutopilot(hairpin)), rough = scoredRace(hairpin, makeAutopilot(hairpin, 21));
  const rc = rough.score.counts;
  check(clean.score.counts.wallHits === 0 && rc.wallHits > 0 && rc.cleanGates < rc.gates && clean.score.total > rough.score.total + 10000,
    `score: clean driving pays on ${hairpin.def.name}: clean ${formatPoints(clean.score.total)} vs ${formatPoints(rough.score.total)} for a ` +
    `wall-hitting run (${rc.wallHits} wall contacts, ${rc.cleanGates} of ${rc.gates} clean checkpoints)`);

  // 12c. a handbrake slide scores a drift: a "player" who pulls the handbrake into the bends of Lighthouse Bay,
  // then countersteers towards where the car is going, on the throttle
  const bay = byId('lighthouse-bay');
  const driftDriver = (track) => {
    const base = medalPilot(track, { aLat: 14, lookK: 0.55 }), N = track.count;
    const wrapA = (x) => Math.atan2(Math.sin(x), Math.cos(x));
    const turn = (i) => { const p = (i - 3 + N) % N, q = (i + 3) % N; return wrapA(Math.atan2(track.tx[q], track.tz[q]) - Math.atan2(track.tx[p], track.tz[p])); };
    let pull = 0, wait = 0;
    return (car) => {
      const c = base(car);
      c.handbrake = false;
      wait -= dt;
      const ahead = (car.idx + Math.round((8 + car.speed * 0.4) / track.segLen)) % N;
      if (pull <= 0 && wait <= 0 && Math.abs(turn(ahead)) > 0.12 && car.speed > 16 && car.grounded) { pull = 0.35; wait = 3; }
      if (pull > 0) {
        pull -= dt;
        Object.assign(c, { handbrake: true, steer: Math.sign(turn(ahead)), throttle: 0 });
      } else {
        const slip = wrapA(Math.atan2(car.vx, car.vz) - car.yaw);
        if (Math.abs(slip) > 0.15) { c.steer = Math.max(-1, Math.min(1, c.steer * 0.5 + slip * 1.5)); c.throttle = Math.max(c.throttle, 0.5); }
      }
      return c;
    };
  };
  const drift = scoredRace(bay, driftDriver(bay)), plain = scoredRace(bay, medalPilot(bay, { aLat: 14, lookK: 0.55 }));
  const drifts = drift.events.filter((e) => e.kind === 'drift');
  check(drifts.length >= 10 && drifts.every((e) => e.points > 0 && e.time >= SCORE.driftMin) && plain.score.counts.drifts === 0 &&
    drift.race.finished && drift.score.total > plain.score.total && drift.score.counts.wallHits === 0,
    `score: handbrake slides score drifts: ${drifts.length} drifts on ${bay.def.name} (${formatPoints(drift.score.points.drift)}, best ` +
    `${formatPoints(drift.score.counts.bestDrift)}, no wall contact); total ${formatPoints(drift.score.total)} vs ${formatPoints(plain.score.total)} driving it without drifts (0 drifts)`);

  // 12d. jumps score air: every kicker of Seaside Stunts, landed cleanly
  const stunts = byId('seaside-stunts');
  const jumps = scoredRace(stunts, makeAutopilot(stunts));
  const airs = jumps.events.filter((e) => e.kind === 'air');
  check(airs.length === 6 && airs.every((e) => e.time >= SCORE.airMin && e.points > 0) && !jumps.events.some((e) => e.kind === 'airLost'),
    `score: jumps score air: ${airs.length} of 6 kickers on ${stunts.def.name} (${airs.map((e) => `${e.time.toFixed(1)} s`).join(', ')}; ` +
    `${formatPoints(jumps.score.points.air)})`);

  // 12e. nitro: banked points refill the tank, so a nitro-using autopilot gets faster with the refills;
  // respawns cost points, lose the combo and refill nothing; penalties never take the score below zero
  const night = byId('night-highway');
  const one = scoredRace(night, makeAutopilot(night), { nitro: true, refill: false });
  const refilled = scoredRace(night, makeAutopilot(night), { nitro: true });
  const kestrel = scoredRace(night, makeAutopilot(night), { nitro: true, spec: CARS.kestrel.spec });
  const sc = new ScoreState(rookie), car = createCar(rookie);
  addNitro(car, -0.5);
  const race = new RaceState(rookie);
  let resp = null;
  for (let s = 0; s < 60 * 40 && !resp; s++) {
    stepCar(car, rookie, { steer: 0, throttle: 1 }, dt); race.update(car, dt); sc.update(car, race, dt);
    if (sc.combo >= 1 && sc.total >= SCORE.cpPoints) resp = { before: sc.total, nitro: car.nitro, ev: sc.respawn() };
  }
  const zero = new ScoreState(rookie).respawn(); // nothing to take yet
  check(refilled.score.nitro > 2 && refilled.race.finishTime < one.race.finishTime - 1 && kestrel.score.nitro > 2 &&
    resp && sc.total === resp.before - SCORE.respawnPoints && sc.multiplier === 1 && car.nitro === resp.nitro && resp.ev[0].kind === 'respawn' &&
    zero[0].points === 0,
    `score: points refill nitro: on ${night.def.name} the nitro autopilot gets ${refilled.score.nitro.toFixed(2)} tanks back ` +
    `(${(one.race.finishTime - refilled.race.finishTime).toFixed(2)} s faster than with one tank, ${formatTime(refilled.race.finishTime)}; ` +
    `kestrel ${kestrel.score.nitro.toFixed(2)} tanks); a respawn costs ${SCORE.respawnPoints}, resets the combo, refills nothing; the score never goes below 0`);

  // 12g (v4 review fixes). No farming: on Seaside Stunts, respawning to the checkpoint before a kicker after
  // every landing (speed kept, as in Drive), or going back 150 m before the kicker to jump it again, banks no
  // more air and earns no more nitro than the clean run. A wall touch that ended just before a gate spoils only
  // its own section; another touch inside the same contact after the gate spoils the next one too.
  {
    const farm = (mode) => {
      const car = createCar(stunts), race = new RaceState(stunts), score = new ScoreState(stunts), drive = makeAutopilot(stunts);
      let loops = 0, flight = 0, wait = 0, kick = null, air = 0;
      while (!race.finished && race.time < 600) {
        stepCar(car, stunts, drive(car), dt);
        race.update(car, dt);
        for (const e of score.update(car, race, dt) ?? []) if (e.kind === 'air') air += e.points;
        if (!car.grounded) { if ((flight += dt) > 0.2) kick ??= stunts.kickers.reduce((b, k) => (Math.abs(k.lip - car.idx) < Math.abs(b.lip - car.idx) ? k : b)); continue; }
        if (flight >= SCORE.airMin) wait = 0.6;
        flight = 0;
        if (wait > 0 && (wait -= dt) <= 0 && kick && loops < 30 && (mode === 'back' || race.respawn)) {
          const r = race.respawn, i = mode === 'respawn' ? Math.min(r.idx + 6, stunts.finishIdx - 1) : Math.max(1, kick.lip - Math.round(150 / stunts.segLen));
          const yaw = Math.atan2(stunts.tx[i], stunts.tz[i]), v = mode === 'respawn' ? Math.hypot(r.vx, r.vz) : car.speed;
          if (mode === 'respawn') score.respawn();
          placeCar(car, stunts, i, { x: stunts.px[i], z: stunts.pz[i], yaw, vx: Math.sin(yaw) * v, vz: Math.cos(yaw) * v, idx: i, laps: 0 });
          loops++;
          kick = null;
        }
      }
      return { loops, air, tanks: score.nitroEarned, done: race.finished };
    };
    const cleanAir = jumps.score.points.air, cleanTanks = jumps.score.nitroEarned;
    const resp = farm('respawn'), back = farm('back');
    // a scripted wall touch (4 steps) on a car standing still, gates passed by hand
    const gateTest = (touch) => {
      const sc = new ScoreState(rookie, { nitro: false }), race = { nextGate: 0, gates: [{ kind: 'cp' }, { kind: 'cp' }] };
      const car = { hitWall: false, wallImpact: 0, grounded: true, prog: 0, speed: 0, sideSpeed: 0, forwardSpeed: 0, lat: 0, yaw: 0, idx: 0 };
      for (let k = 0; k < 120; k++) {
        car.hitWall = touch.includes(k);
        if (k === 20 || k === 100) race.nextGate++;
        sc.update(car, race, dt);
      }
      return sc.counts.cleanGates;
    };
    const ended = gateTest([10, 11, 12, 13]), merged = gateTest([10, 11, 12, 13, 26]), atGate = gateTest([10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]);
    check(resp.loops >= 5 && back.loops >= 5 && resp.done && back.done && resp.air <= cleanAir && back.air <= cleanAir + 100 &&
      resp.tanks <= cleanTanks && back.tanks <= cleanTanks + 0.01 && ended === 1 && merged === 0 && atGate === 0,
      `score: no farming on ${stunts.def.name}: ${resp.loops} respawns before kickers bank ${formatPoints(resp.air)} air, ${back.loops} re-jumps from ` +
      `150 m back ${formatPoints(back.air)} (clean run ${formatPoints(cleanAir)}; nitro ${resp.tanks.toFixed(2)} / ${back.tanks.toFixed(2)} / ` +
      `${cleanTanks.toFixed(2)} tanks); a touch ending 0.12 s before a gate leaves the next section clean, one more touch after it doesn't`);
  }

  // 12f. best scores in localStorage: per track and car, junk and scores made under other rules or physics ignored
  const store = new Map();
  globalThis.localStorage = { getItem: (k) => store.get(k) ?? null, setItem: (k, v) => store.set(k, String(v)), removeItem: (k) => store.delete(k) };
  const S = await import('../src/game/storage.js');
  const { SCORE_RULES } = await import('../src/game/score.js');
  const { PHYSICS_VERSION } = await import('../src/physics/car.js');
  let ok = true, threw = 0;
  try {
    const entry = (e) => JSON.stringify({ 'rookie-oval': { racer: e } });
    for (const junk of ['null', '[]', '7', '"x"', '{oops', '{"rookie-oval":5}', '{"rookie-oval":[]}', '{"rookie-oval":{"racer":3}}',
      entry({ score: 'x', rules: SCORE_RULES, physics: PHYSICS_VERSION }), entry({ score: -5, rules: SCORE_RULES, physics: PHYSICS_VERSION }),
      entry({ score: 1e999, rules: SCORE_RULES, physics: PHYSICS_VERSION }), entry({ score: 500, physics: PHYSICS_VERSION }),
      entry({ score: 500, rules: SCORE_RULES + 1, physics: PHYSICS_VERSION }), entry({ score: 500, rules: SCORE_RULES, physics: PHYSICS_VERSION - 1 })]) {
      store.set('trackrush.scores.v1', junk);
      try { ok &&= S.getBestScore('rookie-oval', 'racer') === null; } catch { threw++; }
      try { ok &&= S.submitScore('rookie-oval', 'racer', 1200) && S.getBestScore('rookie-oval', 'racer')?.score === 1200; } catch { threw++; }
    }
    store.clear();
    ok &&= S.submitScore('rookie-oval', 'racer', 5000) && !S.submitScore('rookie-oval', 'racer', 4000) && S.submitScore('rookie-oval', 'kestrel', 3000) &&
      !S.submitScore('rookie-oval', 'thunder', 0) && S.getBestScore('rookie-oval', 'racer').score === 5000 &&
      S.getBestScore('rookie-oval', 'kestrel').score === 3000 && S.getBestScore('rookie-oval', 'thunder') === null && S.getBestScore('hairpin-valley', 'racer') === null;
    globalThis.localStorage.setItem = () => { throw new Error('QuotaExceededError'); };
    ok &&= S.submitScore('rookie-oval', 'racer', 9000) === true && S.getBestScore('rookie-oval', 'racer').score === 5000; // (not kept: storage full)
    globalThis.localStorage = { getItem: () => { throw new Error('SecurityError'); }, setItem: () => { throw new Error('SecurityError'); } };
    ok &&= S.getBestScore('rookie-oval', 'racer') === null && S.submitScore('rookie-oval', 'racer', 100) === true;
  } catch {
    threw++;
  } finally {
    delete globalThis.localStorage;
  }
  check(ok && threw === 0, `best scores: stored per track and car; junk, negative, infinite and other-rules / other-physics entries ignored (${threw} threw); storage off or full never throws`);
}

// ---- 13: best times and ghosts per track and car (v4, src/game/storage.js, src/game/replay.js) ----
// Best times moved from one per track (trackrush.records.v3, all set with the racer, the only car
// before v4) to one per track and car (trackrush.records.v4): the v3 times read as the racer's until
// the first v4 save copies them over, so none is lost, and the other cars start empty. A ghost keeps the
// car that drove it (a v3 ghost, which has none, is the racer's) and when it burned nitro, and is stored
// per track and car (a v3 racer ghost is read until a new racer ghost replaces it). Junk is ignored,
// never thrown; a full storage first makes room by dropping the ghosts being replaced.
{
  const { GhostRecorder, GhostPlayer, packGhost, unpackGhost, ghostFits, encodeBoost } = await import('../src/game/replay.js');
  const { PHYSICS_VERSION } = await import('../src/physics/car.js');
  const { CARS } = await import('../src/physics/cars.js');
  const store = new Map();
  let quota = Infinity; // characters, keys and values, like a browser's per-site limit (a replaced value frees its own room)
  const used = () => [...store].reduce((n, [k, v]) => n + k.length + v.length, 0);
  globalThis.localStorage = {
    getItem: (k) => store.get(k) ?? null,
    setItem: (k, v) => {
      if (used() - (store.has(k) ? k.length + store.get(k).length : 0) + k.length + String(v).length > quota) throw new Error('QuotaExceededError');
      store.set(k, String(v));
    },
    removeItem: (k) => store.delete(k),
  };
  const S = await import('../src/game/storage.js');
  let threw = 0;
  const safe = (f) => { try { return f(); } catch { threw++; return false; } };

  // 13a. records: the v3 ones become the racer's, nothing lost; per car from then on; junk ignored
  const v3 = JSON.stringify({ 'rookie-oval': { time: 125.5, splits: [40, 80, 125.5], physics: PHYSICS_VERSION, date: 'then' },
    'hairpin-valley': { time: 200, splits: [], physics: PHYSICS_VERSION - 1 }, 'ramp-rally': 7 });
  store.set('trackrush.records.v3', v3);
  const read = safe(() => S.getRecord('rookie-oval')?.time === 125.5 && S.getRecord('rookie-oval', 'racer').splits.join() === '40,80,125.5' &&
    S.getRecord('rookie-oval', 'kestrel') === null && S.getRecord('hairpin-valley') === null && S.getRecord('ramp-rally') === null);
  const saved = safe(() => S.submitRecord('rookie-oval', 'kestrel', 130, [45, 90, 130]) && !S.submitRecord('rookie-oval', 'racer', 126, []) &&
    S.submitRecord('ramp-rally', 'racer', 170, [60, 120, 170]) && !S.submitRecord('ramp-rally', 'bus', 100, []) && !S.submitRecord('ramp-rally', 'racer', NaN, []));
  const v4 = JSON.parse(store.get('trackrush.records.v4') ?? 'null');
  const copied = v4?.['rookie-oval']?.racer?.time === 125.5 && v4['rookie-oval'].kestrel?.time === 130 && store.get('trackrush.records.v3') === v3;
  store.delete('trackrush.records.v3'); // (the v3 key is left alone by the game; without it nothing changes)
  const after = safe(() => S.getRecord('rookie-oval').time === 125.5 && S.getRecord('rookie-oval', 'kestrel').time === 130 &&
    S.getRecord('ramp-rally').time === 170 && S.submitRecord('rookie-oval', 'racer', 124, []) && S.getRecord('rookie-oval').time === 124 &&
    S.getRecord('rookie-oval', 'kestrel').time === 130 && S.getRecord('rookie-oval', 'thunder') === null);
  // an unreadable v4 key falls back to the v3 records
  store.set('trackrush.records.v3', v3);
  store.set('trackrush.records.v4', '{oops');
  const fallback = safe(() => S.getRecord('rookie-oval')?.time === 125.5);
  const rec = (e) => JSON.stringify({ 'rookie-oval': { racer: e } });
  let junkOk = 0;
  const junk = ['null', '[]', '7', '"x"', '{"rookie-oval":5}', '{"rookie-oval":[]}', '{"rookie-oval":{"racer":3}}', '{"rookie-oval":{"racer":[]}}',
    rec({ time: 'x', physics: PHYSICS_VERSION }), rec({ time: -1, physics: PHYSICS_VERSION }), rec({ time: 0, physics: PHYSICS_VERSION }),
    rec({ time: 60 }), rec({ time: 60, physics: PHYSICS_VERSION - 1 }), rec({ time: 60, physics: String(PHYSICS_VERSION) })];
  store.delete('trackrush.records.v3');
  for (const j of junk) {
    store.set('trackrush.records.v4', j);
    if (safe(() => S.getRecord('rookie-oval') === null && S.getRecord('rookie-oval', 'kestrel') === null &&
      S.submitRecord('rookie-oval', 'kestrel', 99, []) && S.getRecord('rookie-oval', 'kestrel').time === 99)) junkOk++;
  }
  store.set('trackrush.records.v4', rec({ time: 60, physics: PHYSICS_VERSION, splits: ['x', 20, null, 1e400] }));
  const splits = safe(() => S.getRecord('rookie-oval').splits.join('|') === '|20||');
  check(read && saved && copied && after && fallback && junkOk === junk.length && splits && threw === 0,
    `best times per track and car: v3 records read as the racer's (other cars none, other physics ignored) and copied over by the ` +
    `first v4 save, the v3 key untouched; an unreadable v4 key falls back to them; ${junkOk} of ${junk.length} kinds of junk ignored ` +
    `and replaced by the next save, unknown cars not saved, broken splits read as none (${threw} threw)`);

  // 13b. a ghost keeps its car and its nitro: a Kestrel run that burns nitro in bursts (with the score's refills off)
  const track = tracks[0], kestrel = CARS.kestrel.spec;
  const car = createCar(track, track.startIdx, kestrel), race = new RaceState(track), drive = makeAutopilot(track), recd = new GhostRecorder();
  const boosts = [0];
  recd.add(0, car, true);
  for (let step = 1; step <= 900; step++) {
    const c = drive(car);
    c.nitro = step % 150 < 70; // on and off
    stepCar(car, track, c, dt);
    race.update(car, dt);
    recd.add(step, car, step === 900);
    boosts.push(car.boost);
  }
  const ghost = JSON.parse(JSON.stringify(packGhost(recd, { track, laps: 3, time: 15, car: 'kestrel' })));
  const g = unpackGhost(ghost, track, 3, 'kestrel'), play = g && new GhostPlayer(g);
  let boostOk = !!play, burned = 0;
  for (let st = 0; play && st <= 900; st++) {
    play.pose(st);
    boostOk &&= play.car.boost === boosts[st] && play.car.boosting === boosts[st] > 0;
    if (boosts[st] > 0) burned++;
  }
  play?.pose(450.5); // between steps: the step before
  boostOk &&= !!play && play.car.boost === boosts[450] && (play.pose(10), play.car.boost === boosts[10]); // and back in time
  const asV3 = JSON.parse(JSON.stringify(packGhost(recd, { track, laps: 3, time: 15, format: 1 }))); // as v3 saved it: base64, no car, no nitro
  const old = unpackGhost(asV3, track, 3);
  const carOk = ghost.car === 'kestrel' && g?.car === 'kestrel' && unpackGhost(ghost, track, 3)?.car === 'kestrel' &&
    unpackGhost(ghost, track, 3, 'racer') === null && !ghostFits(ghost, track, 3, 'thunder') && ghostFits(ghost, track, 3, 'kestrel') &&
    !('car' in asV3) && !('boost' in asV3) && /^[A-Za-z0-9+/=]+$/.test(asV3.data) && old?.car === 'racer' && old.boost === null &&
    old.ch[0].every((x, i) => x === g.ch[0][i]) && unpackGhost(asV3, track, 3, 'kestrel') === null && new GhostPlayer(old).pose(300) &&
    unpackGhost(packGhost(recd, { track, laps: 3, time: 15 }), track, 3, 'racer') !== null; // (no car given: the racer)
  const changes = (boostSteps, boostLevels) => encodeBoost({ boostSteps, boostLevels });
  const badGhosts = [{ ...ghost, car: 'bus' }, { ...ghost, car: 42 }, { ...ghost, car: null }, { ...ghost, car: '__proto__' }, { ...ghost, boost: 5 },
    { ...ghost, boost: null }, { ...ghost, boost: '%%%' }, { ...ghost, boost: 'AAAA' }, { ...ghost, boost: changes([5, 901], [10, 0]) },
    { ...ghost, boost: changes([5], [11]) }, { ...ghost, boost: changes([5, 5], [10, 0]) }, { ...ghost, boost: `${ghost.boost}\u0800\u0800` }];
  let badOk = 0;
  for (const bg of badGhosts) if (safe(() => unpackGhost(bg, track, 3) === null && unpackGhost(bg, track, 3, 'kestrel') === null)) badOk++;
  check(boostOk && burned > 100 && carOk && badOk === badGhosts.length && threw === 0,
    `ghost car and nitro: a Kestrel ghost (${recd.boostSteps.length} nitro changes, ${ghost.boost.length} characters) replays as the ` +
    `Kestrel with its nitro exactly at every physics step (${burned} steps burning) and only for the Kestrel; a v3 ghost (no car) is the ` +
    `racer's; ${badOk} of ${badGhosts.length} broken car / nitro tags ignored (${threw} threw)`);

  // 13c. one ghost per track and car in storage; the v3 racer ghost is read until a new racer ghost replaces it;
  // a full storage first drops the ghosts being replaced, then gives up without throwing (and without a ghost)
  store.clear();
  const racer = JSON.parse(JSON.stringify(packGhost(recd, { track, laps: 3, time: 15, car: 'racer' })));
  store.set('trackrush.ghost.rookie-oval', JSON.stringify(asV3));
  const fits = (c) => unpackGhost(S.loadGhost('rookie-oval', c), track, 3, c);
  let storeOk = safe(() => fits('racer')?.car === 'racer' && S.loadGhost('rookie-oval', 'kestrel') === null &&
    S.saveGhost('rookie-oval', 'kestrel', ghost) && fits('kestrel')?.car === 'kestrel' && fits('racer')?.boost === null &&
    S.saveGhost('rookie-oval', 'racer', racer) && !store.has('trackrush.ghost.rookie-oval') && fits('racer')?.boost !== null &&
    fits('kestrel') !== null && fits('thunder') === null);
  // full: the old v3 racer ghost takes the room a new racer ghost needs
  store.clear();
  store.set('trackrush.ghost.rookie-oval', JSON.stringify(asV3));
  store.set('trackrush.ghost.hairpin-valley.thunder', 'x'.repeat(5000));
  quota = used() + 200;
  storeOk &&= safe(() => S.saveGhost('rookie-oval', 'racer', racer) && !store.has('trackrush.ghost.rookie-oval') && fits('racer') !== null &&
    store.has('trackrush.ghost.hairpin-valley.thunder'));
  // no room even then: no ghost for that track and car (the best time stays), other ghosts untouched
  quota = used() - 100;
  storeOk &&= safe(() => !S.saveGhost('rookie-oval', 'racer', { ...racer, pad: 'y'.repeat(9000) }) && S.loadGhost('rookie-oval', 'racer') === null &&
    store.has('trackrush.ghost.hairpin-valley.thunder'));
  // storage switched off: nothing throws
  globalThis.localStorage = { getItem: () => { throw new Error('SecurityError'); }, setItem: () => { throw new Error('SecurityError'); }, removeItem: () => { throw new Error('SecurityError'); } };
  storeOk &&= safe(() => S.loadGhost('rookie-oval', 'kestrel') === null && S.loadGhost('rookie-oval') === null && !S.saveGhost('rookie-oval', 'kestrel', ghost) &&
    S.getRecord('rookie-oval', 'kestrel') === null && S.submitRecord('rookie-oval', 'kestrel', 50, []) === true);
  delete globalThis.localStorage;
  check(storeOk && threw === 0,
    `ghost storage: one per track and car; the v3 racer ghost is read as the racer's until a new racer ghost replaces it; a full ` +
    `storage drops the ghost being replaced to make room, else keeps no ghost for that track and car and leaves the others; storage ` +
    `off never throws (${threw} threw)`);
}

check(formatTime(119.9996) === '2:00.000' && formatTime(61.5) === '1:01.500', 'formatTime rounds correctly (119.9996 s -> 2:00.000)');

console.log(failures ? `\n${failures} check(s) failed` : '\nall checks passed');
process.exit(failures ? 1 : 0);
