/**
 * car.js
 * ------------------------------------------------------------------
 * Car physics v3 (PHYSICS_VERSION), shared by the player, the AI cars and the ghost.
 * No Three.js and no DOM here: a car is a plain object so hundreds of AI
 * cars can be simulated cheaply, in the browser or in Node.
 *
 * The model, per fixed 60 Hz step (split into CAR.substeps sub-steps):
 *
 *  1. Driver inputs. The steering command is rate limited (a real steering
 *     rack can't jump), then turned into a front wheel angle. The lock is
 *     speed sensitive: full steer asks for about the car's grip limit at
 *     the current speed (the geometric angle for CAR.steerRefAccel of
 *     lateral acceleration), plus a margin that is the tyre's peak slip
 *     angle at parking speeds but only CAR.steerExtraFast at speed, never
 *     more than the mechanical lock CAR.steerLock. So a digital keyboard
 *     can't overdrive the front tyres at 250 km/h (that is what used to
 *     start fishtails), yet still gets full lock in hairpins. When the rear
 *     slides beyond normal cornering slip, a countersteer assist turns the
 *     front wheels towards the slide (like a driver's hands), which also
 *     damps the slide; it fades in smoothly and is off in normal driving.
 *
 *  2. Drivetrain: engine torque curve -> automatic 6-speed gearbox
 *     (shift time, launch rpm, rev limiter, engine braking) -> all-wheel
 *     drive with a rear-biased split. Brakes with a front bias.
 *
 *  3. Two-axle "bicycle" model in the car's frame: forward speed u,
 *     sideways speed v, yaw rate r. Each axle has a normal load from
 *     static weight + dynamic longitudinal weight transfer (braking moves
 *     load to the front, so the rear gets lighter) + aerodynamic downforce
 *     (∝ v²) + road banking and crests/dips. Tyre grip:
 *       - lateral force from a simplified Pacejka "magic formula" of the
 *         slip angle (rises linearly, peaks at ~8°, then falls to ~90 %),
 *       - mild load sensitivity (twice the load gives a bit less than
 *         twice the grip),
 *       - friction circle: longitudinal force (drive/brake) uses up part
 *         of the available grip. Front axle: braking/driving takes priority
 *         (brake while turning = understeer). Rear axle: cornering takes
 *         priority (like ABS/EBD/traction control keeping the rear rolling),
 *         so a full keyboard brake gives a little oversteer, not a spin.
 *       - handbrake: a strong rear brake (the lever ramps in) that bypasses
 *         the electronics and uses up most of the rear tyres' friction
 *         circle, so they have little grip left for cornering and the rear
 *         steps out; drifting emerges from this, there is no "drift mode"
 *         (car.drifting is just a flag derived from the rear slip angle).
 *     The tyre/yaw equations are integrated semi-implicitly (a 2x2 linear
 *     solve with the tyres' secant stiffness), which is stable at any speed
 *     and needs no special-casing near standstill (it smoothly becomes the
 *     kinematic "no sideways slip" car). Aero drag ∝ v², rolling
 *     resistance, and gravity along the road (hills and banking: the
 *     component of gravity in the banked surface pulls the car into the
 *     corner, and the extra normal load adds grip).
 *     Stability control (ESC, like a road car's): it compares the yaw rate
 *     with what the steering asks for, capped at the grip-limited yaw rate
 *     for the current speed, and brakes single wheels (a bounded yaw moment
 *     plus a little speed loss) when the car rotates too much. Quick
 *     left-right keyboard steering at speed therefore can't build up a
 *     pendulum. It is off while the handbrake is used and for 1.5 s after
 *     (so drifts can be held), and while the car scrapes a wall.
 *
 *  4. Walls: the car is a capsule (half length CAR.halfLength, radius
 *     CAR.radius) tested against the real wall segments (collision.js),
 *     every sub-step, so it can't tunnel through at any reachable speed.
 *     Penetration is pushed out; the velocity into the wall is removed with
 *     almost no restitution (capped bounce-back). Walls are meant to cost
 *     time (v3), so the racing line matters:
 *       - a hit takes speed along the wall in proportion to the speed into
 *         it, with a friction that grows with that speed (CAR.wallFriction
 *         + CAR.wallCrush × it): a 5° touch at 150 km/h costs about
 *         15-20 km/h, a 15° hit at 200 km/h about half the speed, 30° at
 *         180 km/h or a head-on hit stops the car;
 *       - while the car touches a wall it rubs along it, losing CAR.wallRub
 *         of its sliding speed per second, building up over
 *         CAR.wallRubBuild s of contact (a brief touch costs little;
 *         grinding along a wall at full throttle settles at 85-100 km/h,
 *         v2: 160-220). The rub only slows the sliding, it never holds the
 *         car to the wall;
 *       - below CAR.wallSlide of sliding speed the hit friction fades out,
 *         so a car its own drive presses nose-in against a wall slides along
 *         it and steers off (at full throttle within about 2 s at any
 *         angle; at half throttle a steep nose-in takes 4-16 s from 65°
 *         and needs reversing from about 80°: the tyres can't push the
 *         car sideways).
 *     Rotation that would swing a corner of the car into the wall is taken
 *     away over a few sub-steps (no dead stop in one step), and a quick but
 *     rate-limited yaw turns the nose along the wall while scraping. No
 *     spin-off, no ping-pong. hitWall stays on while the car scrapes along
 *     within a few cm of the wall (no flicker). The latest contact is kept
 *     for effects (car.wall* fields, see below).
 *     A car flying higher than the barriers (CAR.wallHeight) touches no
 *     wall; only its capsule is kept inside the barrier line so it lands on the road.
 *
 *  5. Vertical: the car is glued to the road (suspension absorbs crests
 *     and dips) unless the road really drops away faster than gravity +
 *     downforce can pull the car down AND a short look-ahead confirms the
 *     car would separate noticeably (kicker ramps at speed). In the air it
 *     is ballistic and keeps the rotation it took off with; steering adds
 *     only a small correction (CAR.airSteer) that dies away when released.
 *     Landings are fully damped (never bounce) and a hard landing costs a
 *     little speed.
 *
 *  6. Smoothed visual attitude: car.pitch / car.roll = road slope/bank
 *     under the car + squat/dive and body roll from the accelerations,
 *     through a damped spring, so rendering can use them directly.
 *
 *  7. Nitro (v4): see "Nitro" below.
 *
 * Car specs (v4). Every number above comes from the car's spec, a plain
 * object with the same fields as CAR (CAR itself is the default car,
 * 'racer', unchanged since physics v3). createCar(track, idx, spec) keeps
 * the spec on the car as car.spec (not enumerable, so copying, cloning or
 * JSON-saving a car's state leaves it out and a restored state keeps the
 * car it was created with). The constants derived from a spec (wheelbase,
 * the tyre's peak slip, ...) are computed once per spec object, the first
 * time a car with it is stepped: treat a spec as read-only once it is used,
 * and make a new one to tune (makeSpec). The four built-in cars are in
 * cars.js. Every car has the same collision capsule (CAR.radius,
 * CAR.halfLength) and the same wall constants, so the track width rules
 * and the wall behaviour hold for all of them.
 *
 * Nitro (v4). car.nitro is the tank, 0..1 (a new car starts full; placeCar,
 * i.e. a restart or respawn, keeps it; addNitro(car, amount) tops it up,
 * clamped to 0..1). ctrl.nitro (true or 0..1) burns it while the car is on
 * the ground in a forward gear, not braking and without the handbrake: a
 * full tank lasts spec.nitroTime seconds at full nitro. While boosting, the
 * throttle is at least the nitro amount (nitro alone drives the car) and the
 * drive gets an extra push of min(spec.nitroForce, spec.nitroPower / speed)
 * (N): it goes through the tyres like the engine's drive (traction control
 * and the friction circle still apply), is not cut by gear shifts, and fades
 * out over the last spec.nitroFade m/s below spec.nitroTop (the top speed
 * with nitro). No thrust and no burn in the air, in reverse, while braking
 * or while the handbrake is held.
 * car.boost is the nitro amount used this step (0..1) and car.boosting is
 * boost > 0 (for flames, sound and scoring). Without ctrl.nitro nothing
 * changes: the racer is bit-for-bit the physics v3 car (PHYSICS_VERSION 3).
 *
 * Public API (from v1): CAR, createCar, placeCar, snapshotCar,
 * stepCar; v4 adds makeSpec, addNitro and createCar's spec argument.
 * Car fields (v1): x,y,z, vx,vy,vz, yaw, speed, forwardSpeed,
 * sideSpeed, grounded, airTime, drifting, idx, lat, bank, groundY, prog,
 * laps, hitWall, wallHits, steer, throttle. New in v2: yawRate (rad/s),
 * steerAngle (front wheel angle, rad, + = left), pitch (rad, + = nose up),
 * roll (rad, + = left side up), rpm, gear (-1 reverse, 0 neutral, 1..6),
 * braking (bool), slip (0..1 tyre sliding amount, for smoke/skids),
 * wheelRot (wheel spin angle, rad, wrapped to 0..2π).
 * New in v3 (wall contact, for sparks, sound and camera shake):
 * wallImpact (m/s of speed into a wall removed during the last step, 0 if
 * none), wallScrape (m/s the car slides along a wall while touching it,
 * else 0), wallX / wallY / wallZ (the latest contact point, at about bumper
 * height; kept after the contact ends), wallNx / wallNz (that wall's normal,
 * pointing back to the road). New in v4: spec (the car's spec, see above;
 * not enumerable), nitro (tank 0..1), boost (nitro used this step, 0..1),
 * boosting (bool). PHYSICS_VERSION tags saved data that depends on the
 * exact physics.
 * Fields starting with "_" are internal.
 */
import { locate, locateNear, collideCapsule } from './collision.js';

const G = 9.81;

/** Tags saved data that depends on the exact physics (player ghosts, best times, medal times); data without a tag counts as 2. */
export const PHYSICS_VERSION = 3;

/** The default car's spec ('racer', see cars.js): every car spec has these fields. */
export const CAR = {
  id: 'racer',         // the car's id in cars.js
  // --- chassis ---------------------------------------------------------
  mass: 1250,          // kg
  inertia: 1850,       // kg m², yaw
  cgToFront: 1.2,      // m, centre of gravity to front axle
  cgToRear: 1.4,       // m, centre of gravity to rear axle (front ~54 % of the weight)
  cgHeight: 0.42,      // m, for longitudinal weight transfer
  wheelRadius: 0.34,   // m
  // --- tyres -----------------------------------------------------------
  mu: 1.6,             // peak friction coefficient at the static axle load
  handbrake: 0.8,      // handbrake rear brake force, fraction of the rear tyres' grip (≤ 25 m/s)
  handbrakeFast: 0.55, // ... and at ≥ 55 m/s (a handbrake at 200 km/h shouldn't be instant death)
  handbrakeRate: 6,    // how fast the handbrake lever comes on (1/s); releases twice as fast
  loadSensitivity: 0.08, // grip per load falls 8 % per extra 100 % load
  pacB: 13, pacC: 1.9, pacE: 0.97, // magic formula shape (peak at ~8°)
  // --- aero --------------------------------------------------------------
  drag: 0.62,          // N per (m/s)²  (½ ρ Cd A)
  downforce: 0.65,     // N per (m/s)²  (½ ρ Cl A)
  aeroFront: 0.42,     // share of downforce on the front axle
  rollResist: 0.013,   // rolling resistance coefficient
  // --- engine and gearbox ----------------------------------------------
  idleRpm: 1000,
  redline: 8200,       // rev limiter
  upshiftRpm: 7700,
  downshiftRpm: 4200,
  launchRpm: 5500,     // clutch slip rpm at full throttle from standstill
  torque: [[1000, 260], [2500, 380], [4500, 470], [6000, 480], [7000, 455], [7800, 420], [8200, 380]], // [rpm, Nm]
  gears: [3.55, 2.78, 2.17, 1.70, 1.33, 1.04],
  finalDrive: 3.4,
  reverseRatio: 3.2,
  efficiency: 0.88,
  shiftTime: 0.12,     // s without drive while shifting
  driveFront: 0.35,    // all-wheel drive split (front share)
  slideDrive: 1.2,     // rear slip (× peak) above which throttle keeps the rear sliding (power slide); Infinity = never
  maxReverse: 15,      // m/s
  // --- brakes ----------------------------------------------------------
  brakeForce: 13800,   // N total at full pedal (≈1.12 g)
  brakeFront: 0.68,    // brake bias
  // --- steering --------------------------------------------------------
  steerLock: 0.7,      // rad, front wheel angle at full lock (low speed, and the countersteer limit)
  steerRate: 7,        // steering command units per second (lock to lock ≈ 0.3 s)
  steerRefAccel: 18,   // m/s², lateral acceleration full steer asks for (≈ the grip limit; sets the speed-sensitive lock)
  steerSlipGain: 1.15, // below steerSlowSpeed full lock adds 1.15 × the tyre's peak slip angle on top ...
  steerExtraFast: 0.04, // rad, ... fading to only this much above steerFastSpeed (a keyboard can't overdrive the front tyres at speed)
  steerSlowSpeed: 12,  // m/s
  steerFastSpeed: 35,  // m/s
  steerAssist: 0.65,   // countersteer assist in slides: share of the rear slip angle added to the steering
  assistFrom: 0.12,    // rad of rear slip where the assist starts (normal cornering stays below)
  assistFull: 0.25,    // rad of rear slip where it is fully on
  // --- stability control (ESC) ------------------------------------------
  esc: 1,             // 0 = off, 1 = on
  escGain: 8,          // 1/s, how hard it pulls the yaw rate back towards what the steering asks for
  escMoment: 5000,     // N m, largest corrective yaw moment (braking single wheels)
  escUnder: 0.3,       // share of that moment used against understeer
  escDeadband: 0.04,   // rad/s of yaw-rate error it ignores
  escSlow: 0.25,       // share of the implied single-wheel braking that slows the car
  escFrom: 8,          // m/s, active above this speed
  escHandbrakeHold: 1.5, // s it stays off after the handbrake is released (so slides can be held)
  // --- body / collision ------------------------------------------------
  radius: 1.0,         // m, capsule radius (half width of the car)
  halfLength: 2.2,     // m, half length of the car (capsule tip to centre)
  wallRestitution: 0.05,
  maxRebound: 1,       // m/s, cap on the bounce-back speed
  wallFriction: 0.5,   // a hit takes this much speed along the wall per m/s of speed into it ...
  wallCrush: 0.06,     // ... plus this much per (m/s)² (s/m): hard hits cost far more than glancing ones
  wallSlide: 5,        // m/s, below this speed along the wall that friction fades out (a car pinned nose-in by its own drive slides off)
  wallRub: 0.15,       // 1/s, share of its speed along the wall a car touching the wall loses per second ...
  wallRubBuild: 1,     // s, ... building up over this much contact (fading as fast off the wall)
  wallAlign: 1.5,      // rad/s, top yaw rate of the alignment with a wall the car is scraping ...
  wallAlignGain: 12,   // 1/s, ... per rad of angle between the heading and the wall
  wallAlignAccel: 15,  // rad/s², how quickly that alignment builds up
  wallYawStop: 0.4,    // share of the into-wall rotation a scraping corner removes per sub-step
  wallLatch: 0.12,     // m, a scraping car counts as touching while this close to the wall ...
  wallLatchSteps: 10,  // ... for up to this many steps after its last real contact
  wallHeight: 1.1,     // m, barrier height: a car flying higher than this is only kept inside the barrier line
  // --- vertical ----------------------------------------------------------
  gravity: G,
  liftSeparation: 0.15, // m the car must be predicted to rise above the road before it takes off
  minFlight: 0.25,     // s of predicted flight needed to take off
  hardLanding: 4,      // m/s vertical impact speed above which landings cost speed ...
  landingLoss: 0.012,  // ... this share of the speed per m/s above it (at most 15 %)
  airSteer: 0.2,       // rad/s of yaw rate full steer gives in the air (a little correction, no more)
  airSteerTau: 0.2,    // s, how quickly that steering yaw builds up and dies away
  airYawDamp: 0.6,     // 1/s, decay of the yaw rate the car had at take-off
  // --- nitro (v4) ---------------------------------------------------------
  nitroTime: 5,        // s a full tank lasts at full nitro
  nitroForce: 4500,    // N, largest extra push (at low speed) ...
  nitroPower: 130000,  // W, ... and at speed: push = min(nitroForce, nitroPower / speed)
  nitroTop: 82.3,      // m/s, the push fades out over the last ... (keep it below the rev limiter in top gear)
  nitroFade: 3,        // m/s ... below this speed (top speed with nitro ≈ 292 km/h)
  // --- simulation --------------------------------------------------------
  substeps: 2,
  maxSpeed: 77,        // m/s: top speed on the flat (≈277 km/h); CAR.maxSpeed also normalises the AI speed input
};

/** A new car spec: `base` (default CAR) with `changes` on top. Specs are read-only once used. */
export function makeSpec(changes = {}, base = CAR) {
  return { ...base, ...changes };
}

// Derived constants (per spec) ---------------------------------------------
const SKIN = 0.03; // m, contact skin around the capsule
const WALL_Y = 0.45; // m above the car's base where car.wallY puts a contact (bumper height)
const DERIVED = Symbol('derived');
const derivedFrozen = new WeakMap(); // for specs that can't hold their own (frozen)

/** Constants derived from a spec, computed once per spec object. */
function derived(P) {
  let D = P[DERIVED];
  if (D) return D;
  D = derivedFrozen.get(P);
  if (D) return D;
  /** Slip (tan of the slip angle) where the magic formula peaks. */
  let best = 0, bx = 0;
  for (let x = 0.001; x < 0.6; x += 0.0005) {
    const f = pacejka(P, x);
    if (f > best) { best = f; bx = x; }
  }
  D = {
    L: P.cgToFront + P.cgToRear,         // wheelbase
    CORE: P.halfLength - P.radius,        // half length of the capsule's core segment
    PEAK_SLIP: bx,
    PAC_SLOPE0: P.pacB * P.pacC,          // d(force ratio)/d(slip) at zero slip
    PEAK_STEER: Math.atan(bx * P.steerSlipGain), // front slip angle full steer adds at speed
  };
  if (Object.isExtensible(P)) Object.defineProperty(P, DERIVED, { value: D, enumerable: false, configurable: true });
  else derivedFrozen.set(P, D);
  return D;
}

function pacejka(P, x) {
  const bx = P.pacB * x;
  return Math.sin(P.pacC * Math.atan(bx - P.pacE * (bx - Math.atan(bx))));
}

const scratch = {};
const contact = {};

/**
 * Create a car standing on the given track sample, with a full nitro tank.
 * `spec`: the car's spec (default CAR, the 'racer'; see cars.js for the others).
 */
export function createCar(track, sampleIdx = track.startIdx, spec = CAR) {
  const car = {
    x: 0, y: 0, z: 0, vx: 0, vy: 0, vz: 0, yaw: 0,
    speed: 0, forwardSpeed: 0, sideSpeed: 0,
    grounded: true, airTime: 0, drifting: false,
    idx: sampleIdx, lat: 0, bank: 0, groundY: 0,
    prog: 0, laps: 0, // unwrapped progress (sample units) and wrap counter
    hitWall: false, wallHits: 0,
    steer: 0, throttle: 0,
    // v2
    yawRate: 0, steerAngle: 0, pitch: 0, roll: 0, rpm: spec.idleRpm, gear: 0,
    braking: false, slip: 0, wheelRot: 0,
    // v3: wall contact
    wallImpact: 0, wallScrape: 0, wallX: 0, wallY: 0, wallZ: 0, wallNx: 0, wallNz: 0,
    // v4: nitro
    nitro: 1, boost: 0, boosting: false,
    // internal state
    _sc: 0, _ax: 0, _ay: 0, _fyr: 0, _shift: 0, _gear: 1, _pitchV: 0, _rollV: 0,
    _t: 0, _nx: 1, _nz: 0, _hw: 7, _ground: 0, _slipF: 0, _slipR: 0, _tcCut: 0, _hb: 0, _escOff: 0, _airRs: 0, _wallT: 1e6,
    _wallNow: false, _rubT: 0,
  };
  // the spec stays out of copies, clones and JSON of the car's state (see "Car specs" above)
  Object.defineProperty(car, 'spec', { value: spec, writable: true, enumerable: false, configurable: true });
  placeCar(car, track, sampleIdx);
  return car;
}

/** Add `amount` (a share of a full tank, may be negative) to a car's nitro tank, clamped to 0..1. Returns the new level. */
export function addNitro(car, amount) {
  const n = (car.nitro ?? 0) + (+amount || 0);
  car.nitro = n < 0 ? 0 : n > 1 ? 1 : n;
  return car.nitro;
}

/** Teleport a car onto a sample, facing along the track, optionally with a velocity. Keeps the nitro tank. */
export function placeCar(car, track, sampleIdx, state = null) {
  const P = car.spec || CAR;
  const i = Math.max(0, Math.min(track.count - 1, sampleIdx));
  car.x = state ? state.x : track.px[i];
  car.z = state ? state.z : track.pz[i];
  car.yaw = state ? state.yaw : Math.atan2(track.tx[i], track.tz[i]);
  car.vx = state ? state.vx : 0;
  car.vz = state ? state.vz : 0;
  car.vy = 0;
  car.idx = state ? state.idx : Math.min(i, track.segCount - 1);
  car.laps = state ? state.laps : 0;
  const loc = locate(track, car.x, car.z, car.idx, scratch);
  car.idx = loc.idx;
  car.y = loc.groundY;
  car.groundY = loc.groundY;
  car.prog = car.laps * track.N + loc.prog;
  car.lat = loc.lat;
  car.bank = loc.bank;
  car._t = loc.t; car._nx = loc.nx; car._nz = loc.nz; car._hw = loc.hw;
  car.grounded = true;
  car.airTime = 0;
  car.drifting = false;
  car.hitWall = false;
  car.steer = 0;
  car.throttle = 0;
  car.yawRate = 0;
  car.steerAngle = 0;
  car.braking = false;
  car.slip = 0;
  car.wallImpact = 0; car.wallScrape = 0;
  car.wallX = 0; car.wallY = 0; car.wallZ = 0; car.wallNx = 0; car.wallNz = 0;
  car._sc = 0; car._ax = 0; car._ay = 0; car._fyr = 0; car._shift = 0; car._ground = 1;
  car._slipF = 0; car._slipR = 0; car._tcCut = 0; car._hb = 0; car._escOff = 0;
  car._airRs = 0; car._wallT = 1e6; car._wallNow = false; car._rubT = 0;
  car.boost = 0; car.boosting = false;
  const fx = Math.sin(car.yaw), fz = Math.cos(car.yaw);
  car.speed = Math.hypot(car.vx, car.vz);
  car.forwardSpeed = car.vx * fx + car.vz * fz;
  car.sideSpeed = car.vx * fz - car.vz * fx;
  // pick the gear that suits the speed
  car._gear = 1;
  const wheelRpm = (Math.abs(car.forwardSpeed) / P.wheelRadius) * (30 / Math.PI);
  while (car._gear < P.gears.length && wheelRpm * P.gears[car._gear - 1] * P.finalDrive > P.upshiftRpm - 600) car._gear++;
  car.gear = car.speed < 0.3 ? 0 : car._gear;
  car.rpm = Math.max(P.idleRpm, wheelRpm * P.gears[car._gear - 1] * P.finalDrive);
  // body attitude straight from the road, no spring transient
  const ph = trackPhys(track);
  roadAttitude(car, track, ph, loc, attTmp);
  car.pitch = attTmp.pitch; car.roll = attTmp.roll;
  car._pitchV = 0; car._rollV = 0;
}

/** Snapshot of the state needed to respawn a car here later. */
export function snapshotCar(car) {
  return { x: car.x, z: car.z, yaw: car.yaw, vx: car.vx, vz: car.vz, idx: car.idx, laps: car.laps };
}

// Per-step environment, shared by the sub-steps (no allocation per step).
const env = { gx: 0, gz: 0, gn: G, drive: 0, brake: 0, hb: 0, esc: 1 };
const attTmp = { pitch: 0, roll: 0 };

/**
 * Advance one fixed physics step.
 * @param ctrl {steer: -1..1 (+ = left), throttle: -1..1 (- = brake/reverse), handbrake: bool,
 *              nitro: bool or 0..1 (optional, v4)}
 */
export function stepCar(car, track, ctrl, dt) {
  const P = car.spec || CAR;
  const D = derived(P);
  const steerIn = clamp(+ctrl.steer || 0, -1, 1);
  let thr = clamp(+ctrl.throttle || 0, -1, 1);
  const hb = !!ctrl.handbrake;
  // nitro: on the ground, in a forward gear, not braking, no handbrake, with something in the
  // tank; holding it opens the throttle at least as far (nitro alone drives the car)
  let boost = 0;
  const nIn = ctrl.nitro;
  if (nIn && !hb && car.nitro > 0 && car.grounded && car._gear >= 1 && thr > -0.02) {
    boost = nIn === true ? 1 : clamp(+nIn || 0, 0, 1);
    if (thr < boost) thr = boost;
  }
  car.steer = steerIn;
  car.throttle = thr;
  car.hitWall = false;
  car.wallImpact = 0;
  car._wallNow = false;
  const ph = trackPhys(track);
  const prevIdx = car.idx;

  // --- 1. steering command (rate limited) -------------------------------
  {
    const d = steerIn - car._sc, m = P.steerRate * dt;
    car._sc += d > m ? m : d < -m ? -m : d;
  }

  // --- 2. surface under the car, drivetrain, nitro ---------------------------
  surfaceEnv(car, track, ph);
  drivetrain(car, P, thr, hb, dt);
  if (boost > 0) {
    // extra push through the tyres (on top of the engine's drive, also during shifts),
    // fading out just below the top speed with nitro
    const u = car.vx * Math.sin(car.yaw) + car.vz * Math.cos(car.yaw);
    const fade = clamp((P.nitroTop - u) / P.nitroFade, 0, 1);
    env.drive += boost * fade * Math.min(P.nitroForce, P.nitroPower / (u > 1 ? u : 1));
    const left = car.nitro - (boost * dt) / P.nitroTime;
    car.nitro = left > 1e-9 ? left : 0; // (a full tank lasts exactly nitroTime, no rounding crumb left)
  }
  car.boost = boost;
  car.boosting = boost > 0;

  // --- 3 + 4. planar dynamics and walls, in sub-steps ---------------------
  const n = P.substeps;
  const h = dt / n;
  let loc = null;
  for (let s = 0; s < n; s++) {
    planarStep(car, P, D, h);
    loc = walls(car, P, D, track, h);
  }

  // --- 5. locate, vertical ------------------------------------------------
  if (!loc) loc = locateNear(track, car.x, car.z, car.idx, scratch);
  vertical(car, P, track, ph, loc, dt);

  // --- bookkeeping ------------------------------------------------------
  if (track.closed) {
    if (loc.idx - prevIdx < -track.N / 2) car.laps++;
    else if (loc.idx - prevIdx > track.N / 2) car.laps--;
  }
  if (car.hitWall) car.wallHits++;
  if (car._wallT < 1e6) car._wallT++;
  // wall contact for effects; the rub memory fades while off the wall
  if (car._wallNow) car.wallY = car.y + WALL_Y;
  if (car.hitWall) {
    const vn = car.vx * car.wallNx + car.vz * car.wallNz;
    car.wallScrape = Math.sqrt(Math.max(0, car.vx * car.vx + car.vz * car.vz - vn * vn));
  } else {
    car.wallScrape = 0;
    if (car._rubT > 0) car._rubT = Math.max(0, car._rubT - dt);
  }
  car.idx = loc.idx;
  car.prog = car.laps * track.N + loc.prog;
  car.lat = loc.lat;
  car.bank = loc.bank;
  car._t = loc.t; car._nx = loc.nx; car._nz = loc.nz; car._hw = loc.hw;
  const fx = Math.sin(car.yaw), fz = Math.cos(car.yaw);
  car.forwardSpeed = car.vx * fx + car.vz * fz;
  car.sideSpeed = car.vx * fz - car.vz * fx;
  car.speed = Math.sqrt(car.vx * car.vx + car.vz * car.vz);
  car.wheelRot = (car.wheelRot + (car.forwardSpeed / P.wheelRadius) * dt) % (2 * Math.PI);
  if (car.wheelRot < 0) car.wheelRot += 2 * Math.PI;

  // derived "drifting" flag and slip amount (for effects)
  const aR = Math.abs(car._slipR), aF = Math.abs(car._slipF);
  const fast = car.speed > 8;
  const hbOn = car._hb > 0.5 && car.speed > 12;
  if (car.drifting) car.drifting = car.grounded && fast && (aR > 0.1 || hbOn);
  else car.drifting = car.grounded && fast && (aR > 0.16 || hbOn);
  let slip = 0;
  if (car.grounded && car.speed > 3) {
    const lateral = (Math.max(aR, aF) - 0.8 * D.PEAK_SLIP) / (2.2 * D.PEAK_SLIP);
    slip = Math.max(lateral, car._tcCut, car._hb * 0.9);
    slip *= Math.min(1, (car.speed - 3) / 6);
  }
  car.slip = clamp(slip, 0, 1);

  attitude(car, track, ph, loc, dt);
}

// ===========================================================================
// Surface: gravity along the road, normal load, cached track data
// ===========================================================================

/**
 * Derived per-sample data cached on the track (computed once, lazily):
 * slope (dy/ds along the centre line) and vertical curvature (d²y/ds²,
 * smoothed) for crest/dip detection and normal load.
 */
export function trackPhys(track) {
  if (track._phys) return track._phys;
  const { count, closed, segLen, py } = track;
  const n = count;
  const at = (i) => (closed ? py[((i % n) + n) % n] : py[Math.max(0, Math.min(n - 1, i))]);
  const slope = new Float32Array(n), kvRaw = new Float32Array(n), kv = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    slope[i] = (at(i + 1) - at(i - 1)) / (2 * segLen);
    kvRaw[i] = (at(i + 1) - 2 * at(i) + at(i - 1)) / (segLen * segLen);
  }
  // smooth the curvature over ±3 samples (±6 m), twice (triangle-ish kernel)
  const box = (src, dst, r) => {
    for (let i = 0; i < n; i++) {
      let s = 0, c = 0;
      for (let k = -r; k <= r; k++) {
        let j = i + k;
        if (closed) j = ((j % n) + n) % n;
        else if (j < 0 || j >= n) continue;
        s += src[j]; c++;
      }
      dst[i] = s / c;
    }
  };
  const tmp = new Float32Array(n);
  box(kvRaw, tmp, 3);
  box(tmp, kv, 3);
  track._phys = { slope, kv };
  return track._phys;
}

function surfaceEnv(car, track, ph) {
  const i = car.idx;
  const j = track.closed ? (i + 1) % track.N : Math.min(i + 1, track.count - 1);
  const t = car._t;
  const slopeT = ph.slope[i] + (ph.slope[j] - ph.slope[i]) * t;
  const tb = Math.tan(car.bank);
  // gradient of the road height on the x/z plane: along the tangent + across (bank)
  const nx = car._nx, nz = car._nz;     // left normal
  const tx = -nz, tz = nx;              // tangent
  const gx = slopeT * tx - tb * nx;
  const gz = slopeT * tz - tb * nz;
  const g2 = gx * gx + gz * gz;
  const invS = 1 / Math.sqrt(1 + g2);   // cos of the surface tilt
  // gravity's component in the road surface (≈ horizontal): -g sinθ along the gradient
  env.gx = -G * gx * invS;
  env.gz = -G * gz * invS;
  if (!car.grounded) { env.gn = 0; return; }
  // normal acceleration: g cosθ + (lateral acceleration into the slope) sinθ + vertical curvature
  const fx = Math.sin(car.yaw), fz = Math.cos(car.yaw);
  const u = car.vx * fx + car.vz * fz;
  const aLat = u * car.yawRate;          // centripetal, towards the car's left
  const lx = fz, lz = -fx;
  const gl = Math.sqrt(g2);
  let into = 0;
  if (gl > 1e-4) into = -aLat * (lx * gx + lz * gz) / gl; // acceleration towards down-slope
  const sinS = gl * invS;
  const kvT = ph.kv[i] + (ph.kv[j] - ph.kv[i]) * t;
  const vt = car.vx * tx + car.vz * tz;
  let gn = G * invS + into * sinS + kvT * vt * vt;
  env.gn = gn < 0 ? 0 : gn > 2.2 * G ? 2.2 * G : gn;
}

// ===========================================================================
// Drivetrain: gearbox, engine, brakes (once per 60 Hz step)
// ===========================================================================

function engineTorque(P, rpm) {
  const T = P.torque;
  if (rpm <= T[0][0]) return T[0][1];
  for (let k = 1; k < T.length; k++) {
    if (rpm <= T[k][0]) {
      const a = T[k - 1], b = T[k];
      return a[1] + ((b[1] - a[1]) * (rpm - a[0])) / (b[0] - a[0]);
    }
  }
  return T[T.length - 1][1];
}

function drivetrain(car, P, thr, hb, dt) {
  const fx = Math.sin(car.yaw), fz = Math.cos(car.yaw);
  const u = car.vx * fx + car.vz * fz;
  const wheelRpm = (Math.abs(u) / P.wheelRadius) * (30 / Math.PI);

  // Direction logic: brake to a stop first, then reverse (and the other way round).
  let drive = 0, brake = 0;
  if (car._gear === -1) {
    if (thr > 0.02 && u > -1) car._gear = 1;
  } else if (thr < -0.02 && u < 1) {
    car._gear = -1;
  }
  if (car._gear >= 1 && thr < -0.02) brake = -thr;
  else if (car._gear === -1 && thr > 0.02) brake = thr;

  if (car._gear >= 1) {
    // automatic gearbox
    if (car._shift > 0) car._shift -= dt;
    const fd = P.finalDrive;
    let rpm = wheelRpm * P.gears[car._gear - 1] * fd;
    if (car._shift <= 0 && car.grounded) {
      if (rpm > P.upshiftRpm && car._gear < P.gears.length && thr > 0.02) {
        car._gear++; car._shift = P.shiftTime;
      } else if (car._gear > 1 && rpm < P.downshiftRpm && wheelRpm * P.gears[car._gear - 2] * fd < P.upshiftRpm - 700) {
        car._gear--; car._shift = P.shiftTime * 0.5;
      }
      rpm = wheelRpm * P.gears[car._gear - 1] * fd;
    }
    const ratio = P.gears[car._gear - 1] * fd;
    // clutch slip when pulling away in first gear
    let rpmEng = rpm;
    if (car._gear === 1 && thr > 0.02) rpmEng = Math.max(rpm, P.idleRpm + (P.launchRpm - P.idleRpm) * thr);
    rpmEng = Math.max(P.idleRpm, rpmEng);
    if (thr > 0.02) {
      if (car._shift <= 0 && rpm < P.redline) {
        drive = (engineTorque(P, rpmEng) * thr * ratio * P.efficiency) / P.wheelRadius;
      }
    } else if (car.grounded && rpm > P.idleRpm * 1.2) {
      // engine braking (friction + pumping torque grows with rpm)
      drive = -((25 + 0.009 * rpm) * ratio) / P.wheelRadius * Math.sign(u);
    }
    car.gear = car.speed < 0.3 && thr <= 0.02 ? 0 : car._gear;
    const rpmTarget = car.grounded ? rpmEng : Math.max(rpmEng, P.idleRpm + (P.redline - P.idleRpm) * Math.max(0, thr));
    car.rpm += (Math.min(P.redline, rpmTarget) - car.rpm) * Math.min(1, dt * 18);
  } else {
    // reverse gear
    const ratio = P.reverseRatio * P.finalDrive;
    const rpm = wheelRpm * ratio;
    const rpmEng = Math.max(rpm, P.idleRpm + 2500 * Math.max(0, -thr));
    if (thr < -0.02 && u > -P.maxReverse) drive = -(engineTorque(P, rpmEng) * -thr * ratio * P.efficiency * 0.6) / P.wheelRadius;
    car.gear = -1;
    car.rpm += (Math.min(P.redline, rpmEng) - car.rpm) * Math.min(1, dt * 18);
  }
  env.drive = drive;
  env.brake = brake * P.brakeForce;
  // handbrake lever: ramps in (a keyboard tap gives a short, partial pull)
  if (hb) car._hb = Math.min(1, car._hb + P.handbrakeRate * dt);
  else car._hb = Math.max(0, car._hb - 2 * P.handbrakeRate * dt);
  env.hb = car._hb;
  // stability control: off while the handbrake is used and for a moment after, then fades back in
  if (car._hb > 0.02) car._escOff = P.escHandbrakeHold;
  else if (car._escOff > 0) car._escOff = Math.max(0, car._escOff - dt);
  env.esc = P.esc * (car._escOff <= 0 ? 1 : car._escOff >= 0.5 ? 0 : 1 - car._escOff / 0.5);
  // ... and while scraping a wall (the wall, not the tyres, sets the rotation then)
  const wt = car._wallT;
  if (wt < 45) env.esc *= wt < 15 ? 0 : (wt - 15) / 30;
  car.braking = brake > 0.02 || (car._hb > 0.1 && car.speed > 1);
}

// ===========================================================================
// Planar dynamics: bicycle model, one sub-step
// ===========================================================================

function muAt(P, fz, fz0) {
  const r = fz / fz0;
  const k = 1 - P.loadSensitivity * (r - 1);
  return P.mu * (k < 0.6 ? 0.6 : k > 1.2 ? 1.2 : k);
}

function planarStep(car, P, D, h) {
  const L = D.L;
  const m = P.mass, Iz = P.inertia, a = P.cgToFront, b = P.cgToRear;
  const yaw = car.yaw;
  const fx = Math.sin(yaw), fz = Math.cos(yaw);
  const lx = fz, lz = -fx;
  const u = car.vx * fx + car.vz * fz;
  const v = car.vx * lx + car.vz * lz;
  const r = car.yawRate;
  const spd = Math.sqrt(u * u + v * v);

  // External forces in the car frame: aero drag, gravity along the road.
  const dragK = P.drag * spd;
  let FxE = -dragK * u + m * (env.gx * fx + env.gz * fz);
  let FyE = -dragK * v + m * (env.gx * lx + env.gz * lz);

  if (!car.grounded) {
    // In the air: no tyre forces. The car keeps the yaw rate it took off with
    // (slowly damped); steering only adds a small, quickly fading correction
    // (a car in the air gets almost no yaw torque from its wheels).
    const r0 = (r - car._airRs) * Math.exp(-P.airYawDamp * h); // take-off rotation (+ any wall knock)
    car._airRs += (car._sc * P.airSteer - car._airRs) * (1 - Math.exp(-h / P.airSteerTau));
    car.yawRate = r0 + car._airRs;
    car.vx += ((FxE * fx + FyE * lx) / m) * h;
    car.vz += ((FxE * fz + FyE * lz) / m) * h;
    car.yaw = yaw + car.yawRate * h;
    car.x += car.vx * h;
    car.z += car.vz * h;
    car.steerAngle = car._sc * P.steerLock * 0.5;
    car._slipF = car._slipR = 0;
    car._tcCut = 0;
    car._ax += (0 - car._ax) * Math.min(1, h * 10);
    car._ay = 0;
    return;
  }

  // --- normal loads ------------------------------------------------------
  const down = P.downforce * spd * spd;
  const W = m * env.gn;
  const tr = (m * car._ax * P.cgHeight) / L; // longitudinal weight transfer
  let fzF = (W * b) / L + down * P.aeroFront - tr;
  let fzR = (W * a) / L + down * (1 - P.aeroFront) + tr;
  const minFz = 0.03 * W;
  if (fzF < minFz) fzF = minFz;
  if (fzR < minFz) fzR = minFz;
  const fzF0 = (m * G * b) / L, fzR0 = (m * G * a) / L;
  const capF = muAt(P, fzF, fzF0) * fzF;
  const capR = muAt(P, fzR, fzR0) * fzR;

  // rolling resistance (opposes u, never reverses it)
  const sgnU = u > 0 ? 1 : u < 0 ? -1 : 0;
  const stopF = (m * Math.abs(u)) / h; // force that would stop the car this sub-step
  let roll = P.rollResist * (fzF + fzR);
  if (roll > stopF * 0.5) roll = stopF * 0.5;
  FxE -= roll * sgnU;

  // --- longitudinal tyre forces --------------------------------------------
  let brake = env.brake;
  if (brake > stopF * 0.9) brake = stopF * 0.9;
  const hb = env.hb; // handbrake lever 0..1
  let driveF = env.drive * P.driveFront;
  let driveR = env.drive - driveF;
  // Rear: cornering has priority (EBD / traction control), unless the handbrake is on.
  let fxR = 0, fyCapR = capR;
  let tcCut = 0;
  if (hb > 0) {
    // Handbrake: a strong rear brake that bypasses the electronics. It uses up most
    // of the rear tyres' friction circle, so they have little left for cornering and
    // the rear steps out. The drive the rear can't take goes to the front.
    driveF += driveR * hb;
    driveR *= 1 - hb;
    const hbk = u < 25 ? P.handbrake : u > 55 ? P.handbrakeFast : P.handbrake + ((P.handbrakeFast - P.handbrake) * (u - 25)) / 30;
    let fb = hb * hbk * capR;
    if (fb > stopF * 0.5) fb = stopF * 0.5;
    fxR = driveR - fb * sgnU - brake * (1 - P.brakeFront) * sgnU;
    if (fxR > 0.97 * capR) fxR = 0.97 * capR; else if (fxR < -0.97 * capR) fxR = -0.97 * capR;
    fyCapR = Math.sqrt(Math.max(0, capR * capR - fxR * fxR));
  } else {
    const fyPrev = Math.abs(car._fyr) < capR ? Math.abs(car._fyr) : capR;
    const longCap = 0.97 * Math.sqrt(capR * capR - fyPrev * fyPrev);
    let want = driveR - brake * (1 - P.brakeFront) * sgnU;
    const sliding = Math.abs(car._slipR) > D.PEAK_SLIP * P.slideDrive;
    if (sliding && want > 0) {
      // rear already sliding: the driven wheels spin up and keep it loose (power slide)
      if (want > 0.97 * capR) want = 0.97 * capR;
      fyCapR = Math.sqrt(Math.max(0, capR * capR - want * want));
    } else if (want > longCap) {
      // traction control: cut what the rear can't use without losing cornering grip
      if (driveR > 0) tcCut = Math.max(tcCut, (want - longCap) / (Math.abs(env.drive) + 1));
      want = longCap;
    } else if (want < -longCap) want = -longCap;
    fxR = want;
  }
  // Front: driving/braking has priority, cornering gets what is left.
  let fxF = driveF - brake * P.brakeFront * sgnU;
  const fxCapF = 0.97 * capF;
  if (fxF > fxCapF) { tcCut = Math.max(tcCut, (fxF - fxCapF) / (Math.abs(env.drive) + 1)); fxF = fxCapF; }
  else if (fxF < -fxCapF) fxF = -fxCapF;
  const fyCapF = Math.sqrt(Math.max(0, capF * capF - fxF * fxF));
  car._tcCut = tcCut;

  // --- steering angle --------------------------------------------------------
  // Speed-sensitive lock: full steer asks for about the grip limit at this speed
  // (the kinematic angle for the car's maximum lateral acceleration plus the
  // tyre's peak slip angle), never more than the mechanical lock.
  // Countersteer assist: when the rear slides beyond its normal cornering slip
  // angle, the front wheels turn by the rear slip angle (towards the slide),
  // like a driver's hands. It fades in smoothly, so in normal cornering the
  // steering is a plain fixed angle and the tyres keep the yaw well damped;
  // in a slide it also opposes yaw rate, which damps the slide.
  const sc = car._sc;
  let delta, deltaCmd = 0;
  if (u > 0.5) {
    let wf = (u - P.steerSlowSpeed) / (P.steerFastSpeed - P.steerSlowSpeed);
    wf = wf <= 0 ? 0 : wf >= 1 ? 1 : wf * wf * (3 - 2 * wf);
    const lock = Math.atan((L * P.steerRefAccel) / (u * u)) + D.PEAK_STEER + (P.steerExtraFast - D.PEAK_STEER) * wf;
    delta = sc * (lock < P.steerLock ? lock : P.steerLock);
    deltaCmd = delta;
    if (u > 3) {
      const slideR = Math.atan((v - b * r) / u); // rear slip angle
      const ab = slideR < 0 ? -slideR : slideR;
      if (ab > P.assistFrom) {
        let w = (ab - P.assistFrom) / (P.assistFull - P.assistFrom);
        w = w > 1 ? 1 : w * w * (3 - 2 * w);
        const fade = u < 8 ? (u - 3) / 5 : 1;
        delta += slideR * w * fade * P.steerAssist;
      }
    }
  } else {
    const rev = u < -0.5 ? Math.min(1, 6 / -u) : 1;
    delta = sc * P.steerLock * rev;
  }
  if (delta > P.steerLock) delta = P.steerLock;
  else if (delta < -P.steerLock) delta = -P.steerLock;
  car.steerAngle = delta;
  const c = Math.cos(delta), s = Math.sin(delta);

  // --- lateral tyre stiffness (secant of the magic formula) -------------------
  const U_MIN = 1.5;
  // front wheel frame velocities
  const vfa = v + a * r;
  const uw = u * c + vfa * s;
  const vw = -u * s + vfa * c;
  const Uf = Math.abs(uw) > U_MIN ? Math.abs(uw) : U_MIN;
  const xF = vw / Uf;
  const kF = (fyCapF * secant(P, D, xF)) / Uf;  // N per (m/s) of lateral wheel velocity
  const vr = v - b * r;
  const Ur = Math.abs(u) > U_MIN ? Math.abs(u) : U_MIN;
  const xR = vr / Ur;
  const kR = (fyCapR * secant(P, D, xR)) / Ur;
  car._slipF = xF;
  car._slipR = xR;

  // --- semi-implicit solve for the new sideways speed v' and yaw rate r' ------
  const kfc2 = kF * c * c;
  const hm = h / m, hI = h / Iz;
  const A11 = 1 + hm * (kfc2 + kR);
  const A12 = hm * (kfc2 * a - kR * b) + h * u;
  const B1 = v + hm * (fxF * s + kF * c * u * s + FyE);
  const A21 = hI * (a * kfc2 - b * kR);
  const A22 = 1 + hI * (a * a * kfc2 + b * b * kR);
  const B2 = r + hI * (a * (fxF * s + kF * c * u * s));
  const det = A11 * A22 - A12 * A21;
  const v1 = (B1 * A22 - A12 * B2) / det;
  const r1 = (A11 * B2 - A21 * B1) / det;

  // tyre forces at the solved state, clamped to their grip
  let fyF = kF * (u * s - c * (v1 + a * r1));
  if (fyF > fyCapF) fyF = fyCapF; else if (fyF < -fyCapF) fyF = -fyCapF;
  let fyR = -kR * (v1 - b * r1);
  if (fyR > fyCapR) fyR = fyCapR; else if (fyR < -fyCapR) fyR = -fyCapR;
  car._fyr = fyR;

  // body-frame totals
  const Fx = fxF * c - fyF * s + fxR + FxE;
  const Fy = fxF * s + fyF * c + fyR + FyE;
  const Mz = a * (fxF * s + fyF * c) - b * fyR;

  // integrate (world frame for velocity, so turning never creates speed)
  let rN = r + (Mz / Iz) * h;
  let vxN = car.vx + ((Fx * fx + Fy * lx) / m) * h;
  let vzN = car.vz + ((Fx * fz + Fy * lz) / m) * h;

  // --- stability control (ESC) ---------------------------------------------
  // Like a road car's ESC: it compares the yaw rate with what the steering asks
  // for (never more than the tyres can hold at this speed) and brakes single
  // wheels to pull the car back: a strong correction when the car rotates too
  // much (oversteer, fishtailing after quick left-right steering), a weaker one
  // when it plows on (understeer). Off with the handbrake (see drivetrain).
  if (env.esc > 0 && u > P.escFrom) {
    const rLim = (fyCapF + fyCapR) / (m * u); // yaw rate of a grip-limited steady turn
    let rRef = (u * Math.tan(deltaCmd)) / L;
    if (rRef > rLim) rRef = rLim; else if (rRef < -rLim) rRef = -rLim;
    const e = rN - rRef;
    const ae = (e < 0 ? -e : e) - P.escDeadband;
    if (ae > 0) {
      const under = e * rRef < 0 && rN * rRef > 0;
      const fadeIn = u < P.escFrom + 4 ? (u - P.escFrom) / 4 : 1;
      let M = Iz * P.escGain * ae;
      const Mmax = P.escMoment * (under ? P.escUnder : 1);
      if (M > Mmax) M = Mmax;
      M *= env.esc * fadeIn;
      rN -= (e > 0 ? M : -M) * (h / Iz);
      // the single-wheel braking that makes the moment also slows the car a little
      const sp = Math.sqrt(vxN * vxN + vzN * vzN);
      if (sp > 1) {
        let dv = ((M / 0.8) * P.escSlow * h) / m;
        if (dv > sp * 0.5) dv = sp * 0.5;
        vxN -= (vxN / sp) * dv; vzN -= (vzN / sp) * dv;
      }
    }
  }
  car.yawRate = rN;
  car.vx = vxN;
  car.vz = vzN;
  car.yaw = yaw + car.yawRate * h;
  car.x += car.vx * h;
  car.z += car.vz * h;
  // filtered accelerations for weight transfer and body attitude (suspension lag)
  const kf = Math.min(1, h * 12);
  car._ax += ((Fx - FxE + (-dragK * u)) / m - car._ax) * kf;
  car._ay += (Fy / m + 0 - car._ay) * kf;
}

/** Magic formula force ratio divided by slip (secant stiffness), finite at 0. */
function secant(P, D, x) {
  const ax = x < 0 ? -x : x;
  if (ax < 1e-4) return D.PAC_SLOPE0;
  return pacejka(P, ax) / ax;
}

// ===========================================================================
// Walls
// ===========================================================================

/** Wall collisions for one sub-step. Returns the locate() result for the car's final position, or null. */
function walls(car, P, D, track, h) {
  const R = P.radius, CORE = D.CORE;
  // Broad phase: far from both walls and from the ends of a sprint track -> nothing to do.
  const loc = locateNear(track, car.x, car.z, car.idx, scratch);
  car.idx = loc.idx;
  car._t = loc.t; car._nx = loc.nx; car._nz = loc.nz; car._hw = loc.hw;
  const nearEnd = !track.closed && (loc.idx < 4 || loc.idx > track.segCount - 5);
  const reach = P.halfLength + 1.5;
  if (!nearEnd && Math.abs(loc.lat) < loc.hw - reach) return loc;

  // Flying higher than the barriers: there is nothing to hit up there (no invisible
  // wall, no friction, no knock to the rotation). The whole capsule is only kept inside
  // the barrier line, so the car comes down on the road with nothing to push out (a nose
  // pointing at the barrier doesn't make the car jump sideways when it drops below it).
  if (!car.grounded && car.y - loc.groundY > P.wallHeight && !nearEnd) {
    const ax = Math.sin(car.yaw) * loc.nx + Math.cos(car.yaw) * loc.nz; // how far the capsule's axis points across the road
    const lim = loc.hw - R - CORE * (ax < 0 ? -ax : ax);
    if (Math.abs(loc.lat) <= lim) return loc;
    const sgn = loc.lat > 0 ? 1 : -1;
    const push = Math.abs(loc.lat) - lim;
    car.x -= loc.nx * push * sgn;
    car.z -= loc.nz * push * sgn;
    const vn = (car.vx * loc.nx + car.vz * loc.nz) * sgn;
    if (vn > 0) { car.vx -= loc.nx * vn * sgn; car.vz -= loc.nz * vn * sgn; }
    return locateNear(track, car.x, car.z, car.idx, scratch);
  }

  const grid = track.grid;
  let touched = false;
  for (let iter = 0; iter < 4; iter++) {
    const fx = Math.sin(car.yaw), fz = Math.cos(car.yaw);
    const p0x = car.x - fx * CORE, p0z = car.z - fz * CORE;
    const p1x = car.x + fx * CORE, p1z = car.z + fz * CORE;
    // a thin skin keeps the contact (and hitWall) steady while scraping along a wall
    if (!collideCapsule(grid, p0x, p0z, p1x, p1z, R + SKIN, contact)) {
      // contact hysteresis: a car that touched in the last few steps still counts as
      // scraping while it stays within CAR.wallLatch of the wall (no on/off flicker
      // from the micro-separations while it is pressed along a wall)
      // and a corner still swinging towards the wall keeps losing that rotation, so a
      // scrape settles along the wall over a few sub-steps instead of freezing in one
      if (iter === 0 && car._wallT < P.wallLatchSteps && collideCapsule(grid, p0x, p0z, p1x, p1z, R + P.wallLatch, contact)) {
        car.hitWall = true;
        touched = true;
        wallContact(car, contact.px, contact.pz, contact.nx, contact.nz);
        stopRotation(car, P, contact.px - car.x, contact.pz - car.z, contact.nx, contact.nz);
      }
      break;
    }
    touched = true;
    car.hitWall = true;
    car._wallT = -1;
    const nx = contact.nx, nz = contact.nz;
    const depth = contact.depth - SKIN;
    contact.px += nx * SKIN; contact.pz += nz * SKIN;
    if (depth <= 1e-5) {
      // touching: only stop motion into the wall
      wallContact(car, contact.px, contact.pz, nx, nz);
      if (car.vx * nx + car.vz * nz < 0) impulse(car, P, contact.px - car.x, contact.pz - car.z, nx, nz, h);
      break;
    }
    // push out (no velocity change from the push)
    car.x += nx * depth;
    car.z += nz * depth;
    // contact point relative to the centre (after the push)
    const dx = contact.px + nx * depth - car.x, dz = contact.pz + nz * depth - car.z;
    wallContact(car, car.x + dx, car.z + dz, nx, nz);
    impulse(car, P, dx, dz, nx, nz, h);
  }
  if (touched) rub(car, P, h);

  // Safety net: the centre must stay on the road whatever happens (a small,
  // bounded nudge per sub-step, so a badly shaped track can never fling the car).
  const l2 = locateNear(track, car.x, car.z, car.idx, scratch);
  const lim = l2.hw - 0.3;
  if (Math.abs(l2.lat) > lim) {
    const sgn = l2.lat > 0 ? 1 : -1;
    let push = Math.abs(l2.lat) - lim;
    if (!(push < 0.5)) push = 0.5;
    car.x -= l2.nx * push * sgn;
    car.z -= l2.nz * push * sgn;
    const vn = (car.vx * l2.nx + car.vz * l2.nz) * sgn;
    if (vn > 0) { car.vx -= l2.nx * vn * sgn; car.vz -= l2.nz * vn * sgn; car.wallImpact += vn; }
    const gap = l2.hw - Math.abs(l2.lat) + push; // from the centre (after the nudge) out to the wall line
    wallContact(car, car.x + l2.nx * gap * sgn, car.z + l2.nz * gap * sgn, -l2.nx * sgn, -l2.nz * sgn);
    car.hitWall = true;
    car._wallT = -1;
    return null;
  }
  return l2;
}

/** Remember the latest wall contact (point and normal back to the road) for effects. */
function wallContact(car, px, pz, nx, nz) {
  car.wallX = px; car.wallZ = pz;
  car.wallNx = nx; car.wallNz = nz;
  car._wallNow = true;
}

/**
 * Rubbing along a wall: a car touching a wall loses CAR.wallRub of its speed
 * along it per second, building up over CAR.wallRubBuild s of contact. Only
 * the sliding is slowed (nothing pulls the car to the wall), and it is
 * proportional to the sliding speed, so a car that hit nose first can
 * always grind or steer its way off again.
 */
function rub(car, P, h) {
  const nx = car.wallNx, nz = car.wallNz;
  const vn = car.vx * nx + car.vz * nz;
  const tvx = car.vx - vn * nx, tvz = car.vz - vn * nz;
  car._rubT = Math.min(P.wallRubBuild, car._rubT + h);
  const k = P.wallRub * h * (P.wallRubBuild > 0 ? car._rubT / P.wallRubBuild : 1);
  car.vx -= tvx * k;
  car.vz -= tvz * k;
}

/** Remove part (CAR.wallYawStop) of the rotation that swings the contact point (dx, dz from the centre) into the wall. */
function stopRotation(car, P, dx, dz, nx, nz) {
  const kn = dz * nx - dx * nz; // normal velocity of the contact point per unit yaw rate
  const wn = car.yawRate * kn;
  if (wn < 0 && Math.abs(kn) > 0.05) car.yawRate -= (P.wallYawStop * wn) / kn;
}

/**
 * Velocity response at a wall contact.
 *  - The velocity of the car's centre into the wall is removed (restitution
 *    CAR.wallRestitution, i.e. almost none) and friction along the wall
 *    takes away (CAR.wallFriction + CAR.wallCrush × jn) × jn of the speed
 *    along it for a normal impulse jn (m/s): a glancing scrape costs a
 *    little, a hard hit far more (a crumpling car, not just a sliding one).
 *    Below CAR.wallSlide m/s along the wall the friction fades out.
 *  - Rotation that drives the touching corner into the wall is stopped (as the
 *    second corner of a real car would), so the car never pivots off the wall
 *    and back (no ping-pong).
 *  - A yaw alignment turns the nose towards the wall's direction while the
 *    car scrapes along it (CAR.wallAlignGain per rad, at most CAR.wallAlign
 *    rad/s), so a touch doesn't leave the car scrubbing its tyres at an angle.
 * Impulses act on the centre of the car, so a hit can't flick it round.
 */
function impulse(car, P, dx, dz, nx, nz, h) {
  const vn = car.vx * nx + car.vz * nz;
  if (vn < 0) {
    car.wallImpact -= vn;
    // almost no bounce, and never more than CAR.maxRebound m/s (a big hit crumples, it doesn't spring back)
    const reb = -vn * P.wallRestitution;
    const jn = -vn + (reb < P.maxRebound ? reb : P.maxRebound);
    car.vx += nx * jn;
    car.vz += nz * jn;
    const vn2 = car.vx * nx + car.vz * nz;
    const tvx = car.vx - vn2 * nx, tvz = car.vz - vn2 * nz;
    const vt = Math.sqrt(tvx * tvx + tvz * tvz);
    if (vt > 1e-6) {
      let dv = (P.wallFriction + P.wallCrush * jn) * jn;
      // slow sliding: the friction fades out, so a car its own drive pushes nose-in
      // against the wall slides along it and can steer off instead of sticking
      if (vt < P.wallSlide) dv *= vt / P.wallSlide;
      if (dv > vt) dv = vt;
      car.vx -= (tvx / vt) * dv;
      car.vz -= (tvz / vt) * dv;
    }
  }
  // rotation pushing the contact point into the wall: take it away (over a few sub-steps)
  stopRotation(car, P, dx, dz, nx, nz);
  // gentle alignment with the wall, in the direction the car is sliding
  const fx = Math.sin(car.yaw), fz = Math.cos(car.yaw);
  const u = car.vx * fx + car.vz * fz;
  if (Math.abs(u) > 2) {
    const dir = u > 0 ? 1 : -1;             // the end of the car that leads
    const fn = (fx * nx + fz * nz) * dir;    // < 0: leading end points into the wall
    if (fn < 0) {
      const ln = (fz * nx - fx * nz) * dir;  // left(yaw)·n: turning left lifts the nose off the wall if > 0
      const ang = Math.asin(Math.min(1, -fn)); // angle between heading and wall
      const target = (ln >= 0 ? 1 : -1) * dir * Math.min(P.wallAlign, ang * P.wallAlignGain);
      if (car.yawRate * target < target * target) {
        const m = P.wallAlignAccel * h;
        const d = target - car.yawRate;
        car.yawRate += d > m ? m : d < -m ? -m : d;
      }
    }
  }
}

// ===========================================================================
// Vertical: glued to the road, real jumps only, damped landings
// ===========================================================================

function roadHeightAt(track, prog, lat) {
  let k = Math.floor(prog);
  let t = prog - k;
  const n = track.count;
  if (track.closed) { k = ((k % track.N) + track.N) % track.N; }
  else if (k >= n - 1) { k = n - 2; t = 1; }
  else if (k < 0) { k = 0; t = 0; }
  const j = track.closed ? (k + 1) % track.N : k + 1;
  const py = track.py[k] + (track.py[j] - track.py[k]) * t;
  const bank = track.bank[k] + (track.bank[j] - track.bank[k]) * t;
  return py - lat * Math.tan(bank);
}

function vertical(car, P, track, ph, loc, dt) {
  const gY = loc.groundY;
  const spd2 = car.vx * car.vx + car.vz * car.vz;
  const gEff = P.gravity + (P.downforce * spd2) / P.mass;
  if (car.grounded) {
    const vGround = (gY - car.y) / dt; // vertical speed of the road under the car
    car._ground += dt;
    // Could the road be dropping away faster than the car can follow?
    const i = loc.idx, j = track.closed ? (i + 1) % track.N : Math.min(i + 1, track.count - 1);
    const kv = ph.kv[i] + (ph.kv[j] - ph.kv[i]) * loc.t;
    const tx = -loc.nz, tz = loc.nx;
    const vt = car.vx * tx + car.vz * tz;
    let takeOff = false;
    if (kv * vt * vt < -gEff && car._ground > 0.05 && Math.abs(vt) > 5) {
      // The smoothed road curves down faster than gravity can follow. Confirm by
      // flying the ballistic path forward against the actual road ahead: take off
      // only if the car would stay clear of the road from the very next step and
      // rise more than CAR.liftSeparation, for at least CAR.minFlight seconds.
      // (Anything less is a crest the suspension soaks up: no micro-hops.)
      const v0 = vGround;
      let maxSep = 0, flight = 0;
      const n = 36;
      for (let k = 1; k <= n; k++) {
        const T = k * dt;
        const road = roadHeightAt(track, loc.prog + (vt * T) / track.segLen, loc.lat);
        const sep = gY + v0 * T - 0.5 * gEff * T * T - road;
        if (sep < 0) break;
        flight = T;
        if (sep > maxSep) maxSep = sep;
      }
      takeOff = maxSep > P.liftSeparation && flight >= P.minFlight;
    }
    if (takeOff) {
      car.grounded = false;
      car.airTime = 0;
      car._airRs = 0;
      car.vy = vGround;
      car.y = gY;
    } else {
      car.y = gY;
      car.vy = vGround;
      car.airTime = 0;
    }
  } else {
    car.airTime += dt;
    car.y += car.vy * dt - 0.5 * gEff * dt * dt; // exact ballistic step (matches the take-off prediction)
    car.vy -= gEff * dt;
    // Just after take-off the path skims the road: don't let rounding end the jump.
    if (car.airTime < 0.1 && car.y < gY && car.y > gY - 0.02) car.y = gY;
    else if (car.y < gY) {
      // Landing: the vertical speed relative to the road under the car.
      const slopeAlong = (roadHeightAt(track, loc.prog + 0.5, loc.lat) - roadHeightAt(track, loc.prog - 0.5, loc.lat)) / track.segLen;
      const tx = -loc.nz, tz = loc.nx;
      const vt = car.vx * tx + car.vz * tz;
      const vRoad = slopeAlong * vt;
      const impact = vRoad - car.vy; // > 0 when hitting the road
      if (impact > P.hardLanding) {
        const loss = Math.min(0.15, P.landingLoss * (impact - P.hardLanding));
        car.vx *= 1 - loss;
        car.vz *= 1 - loss;
      }
      car._pitchV -= Math.min(0.6, 0.03 * impact); // nose dips as the suspension compresses
      car.y = gY;
      car.vy = vRoad;
      car.grounded = true;
      car._ground = 0;
    }
  }
  car.groundY = gY;
}

// ===========================================================================
// Visual body attitude
// ===========================================================================

/** Pitch/roll of the road surface under the car, in the car's frame. */
function roadAttitude(car, track, ph, loc, out) {
  const i = loc.idx, j = track.closed ? (i + 1) % track.N : Math.min(i + 1, track.count - 1);
  const slopeT = ph.slope[i] + (ph.slope[j] - ph.slope[i]) * loc.t;
  const tb = Math.tan(loc.bank);
  const nx = loc.nx, nz = loc.nz, tx = -nz, tz = nx;
  const gx = slopeT * tx - tb * nx, gz = slopeT * tz - tb * nz; // height gradient
  const fx = Math.sin(car.yaw), fz = Math.cos(car.yaw);
  out.pitch = Math.atan(gx * fx + gz * fz);          // uphill ahead -> nose up
  out.roll = Math.atan(gx * fz - gz * fx);           // ground rising to the left -> left side up
  return out;
}

function attitude(car, track, ph, loc, dt) {
  let tp, tr, w;
  if (car.grounded) {
    roadAttitude(car, track, ph, loc, attTmp);
    // squat under acceleration (nose up), dive under braking; roll out of corners
    const ax = clamp(car._ax, -20, 20), ay = clamp(car.forwardSpeed * car.yawRate, -25, 25);
    tp = attTmp.pitch + 0.0032 * ax;
    tr = attTmp.roll + 0.0035 * ay;
    w = 11;
  } else {
    const vh = Math.max(4, car.speed);
    tp = clamp(Math.atan2(car.vy, vh) * 0.6, -0.4, 0.4);
    tr = car.roll * 0.98;
    w = 3;
  }
  // critically-damped-ish spring (semi-implicit, stable at 60 Hz)
  const zeta = 0.8;
  car._pitchV += (w * w * (tp - car.pitch) - 2 * zeta * w * car._pitchV) * dt;
  car._rollV += (w * w * (tr - car.roll) - 2 * zeta * w * car._rollV) * dt;
  car.pitch += car._pitchV * dt;
  car.roll += car._rollV * dt;
}

function clamp(v, a, b) {
  return v < a ? a : v > b ? b : v;
}
