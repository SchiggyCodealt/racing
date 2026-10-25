/**
 * cars.js
 * ------------------------------------------------------------------
 * The four cars (v4). Each is a physics spec for car.js (the same fields as
 * CAR) plus what the menu, HUD and car models need. No DOM, no Three.js.
 *
 *   racer    the v3 car, unchanged (CAR in car.js; the default)
 *   kestrel  light and grippy, quick off the line, lower top speed
 *   thunder  heavy and powerful, the highest top speed, less grip, slower turn-in
 *   drifter  loose rally car: slides and drifts easily, lands jumps softly
 *
 * Use:
 *   import { CARS, CAR_IDS, DEFAULT_CAR, getCar } from './cars.js';
 *   const def = getCar(id);                    // unknown ids give the racer
 *   const car = createCar(track, track.startIdx, def.spec);
 *
 * A car definition has:
 *   id, name, description   one line each, for the car picker
 *   look                    hints for the car model: body colour, accent colour and a shape note
 *   spec                    the physics spec (createCar's third argument; car.spec on the car)
 *   stats                   measured with the real physics by tools/carStats.mjs (npm test checks
 *                           they still match; after changing a spec run `node tools/carStats.mjs`
 *                           and paste the lines it prints):
 *     mass        kg
 *     accel100    s, 0-100 km/h, full throttle from a standstill
 *     accel200    s, 0-200 km/h
 *     top         km/h, top speed on the flat
 *     accel200n   s, 0-200 km/h with nitro from a full tank
 *     topNitro    km/h, top speed with nitro (tank kept full)
 *     tankTime    s, one full tank at full nitro (spec.nitroTime)
 *     tankDist    m, distance covered while one full tank burns, from a standstill
 *     brake100    m, 100-0 km/h, full brakes
 *     grip        g, steady cornering on a 30 m circle (skidpad)
 *     gripFast    g, steady cornering on a 120 m circle (downforce helps)
 *     drift       s, how long a keyboard driver holds a handbrake-started drift on an open pad
 *                 (body slip above 12°, countersteering with the keys; median of 192 tries)
 *   bars        0..1 for the car picker's stat bars, from the stats (statBars below):
 *               speed, acceleration, grip, drift, nitro
 *
 * Specs are read-only once a car uses them (car.js caches constants derived
 * from them); every car shares the racer's collision capsule and wall
 * constants, so track width rules and wall behaviour hold for all of them.
 * The AI is trained with the racer and never uses nitro.
 */
import { CAR, makeSpec } from './car.js';

/** Light, grippy and nimble: wins where the corners come thick and fast. */
const KESTREL = makeSpec({
  id: 'kestrel',
  mass: 950, inertia: 1250, cgToFront: 1.12, cgToRear: 1.33, cgHeight: 0.38, wheelRadius: 0.32,
  mu: 1.72, loadSensitivity: 0.08,
  drag: 0.75, downforce: 0, aeroFront: 0.44,
  idleRpm: 1100, redline: 9400, upshiftRpm: 9000, downshiftRpm: 5200, launchRpm: 6200,
  torque: [[1000, 220], [3000, 300], [5000, 335], [6500, 340], [8000, 300], [9000, 240], [9400, 210]],
  gears: [3.6, 2.55, 2.0, 1.6, 1.32, 1.1], finalDrive: 4.2, reverseRatio: 3.3, shiftTime: 0.08,
  driveFront: 0.4,
  brakeForce: 11600, brakeFront: 0.66,
  steerRate: 8, steerRefAccel: 19, airSteer: 0.17,
  nitroTime: 4, nitroForce: 3500, nitroPower: 90000, nitroTop: 67.9, nitroFade: 3,
  maxSpeed: 63.9,
});

/** Heavy and powerful: the fastest on long straights and fast sweepers, slow to turn and stop. */
const THUNDER = makeSpec({
  id: 'thunder',
  mass: 1650, inertia: 3000, cgToFront: 1.35, cgToRear: 1.55, cgHeight: 0.45, wheelRadius: 0.35,
  mu: 1.37, loadSensitivity: 0.09,
  drag: 0.66, downforce: 2.2, aeroFront: 0.5,
  idleRpm: 900, redline: 7500, upshiftRpm: 7100, downshiftRpm: 3800, launchRpm: 4800,
  torque: [[1000, 450], [2500, 640], [4000, 760], [5500, 790], [6500, 760], [7200, 715], [7500, 670]],
  gears: [3.2, 2.35, 1.8, 1.45, 1.18, 0.985], finalDrive: 3.0, reverseRatio: 3.0,
  driveFront: 0.3,
  brakeForce: 17000, brakeFront: 0.66,
  steerRefAccel: 15.5, steerLock: 0.62,
  escMoment: 7800,
  nitroTime: 6, nitroForce: 6000, nitroPower: 170000, nitroTop: 92.7, nitroFade: 3,
  maxSpeed: 86.9,
});

/** Loose rally car: slides on demand, catches itself, and shrugs off hard landings. */
const DRIFTER = makeSpec({
  id: 'drifter',
  mass: 1150, inertia: 1500, cgToFront: 1.15, cgToRear: 1.35, cgHeight: 0.5, wheelRadius: 0.33,
  mu: 1.57, pacB: 12, pacC: 2.0, pacE: 0.95, loadSensitivity: 0.07,
  handbrake: 0.95, handbrakeFast: 0.7,
  drag: 0.7, downforce: 0.35, aeroFront: 0.45,
  idleRpm: 1000, redline: 7600, upshiftRpm: 7200, downshiftRpm: 4000, launchRpm: 5000,
  torque: [[1000, 308], [2500, 506], [4000, 550], [5500, 534], [6500, 484], [7200, 435], [7600, 396]],
  gears: [3.1, 2.3, 1.8, 1.45, 1.18, 0.92], finalDrive: 3.6, reverseRatio: 3.2,
  driveFront: 0.2, slideDrive: 0.6,
  brakeForce: 13000, brakeFront: 0.64,
  steerRate: 7.5, steerLock: 0.8, steerAssist: 0.5, assistFrom: 0.1,
  escHandbrakeHold: 2,
  hardLanding: 10, landingLoss: 0.003, airYawDamp: 1.5,
  nitroTime: 5, nitroForce: 4500, nitroPower: 110000, nitroTop: 79, nitroFade: 3,
  maxSpeed: 73.4,
});

/** 0..1 bars for the car picker, from a car's measured stats (fixed scales, so the cars compare). */
export function statBars(stats, spec) {
  const bar = (x) => Math.round(Math.max(0.05, Math.min(1, x)) * 100) / 100;
  return {
    speed: bar((stats.top - 200) / 130),                                                  // top speed 200 -> 0, 330 km/h -> 1
    acceleration: bar((0.6 * (3.2 - stats.accel100)) / 1 + (0.4 * (13 - stats.accel200)) / 6), // 0-100 3.2 s -> 0, 2.2 s -> 1 (60 %); 0-200 13 s -> 0, 7 s -> 1 (40 %)
    grip: bar(((stats.grip + stats.gripFast) / 2 - 1.3) / 0.6),                             // average of the two skidpads, 1.3 -> 0, 1.9 g -> 1
    drift: bar(stats.drift / 2),                                                          // keyboard drift held 0 -> 0, 2 s -> 1
    nitro: bar((spec.nitroPower * spec.nitroTime) / spec.mass / 700),                     // boost energy per tank per kg, 0 -> 0, 700 J/kg -> 1
  };
}

/** Every car, by id. `stats`: pasted from `node tools/carStats.mjs` (npm test checks them). */
export const CARS = {
  racer: {
    id: 'racer', name: 'Racer',
    description: 'The all-rounder: quick, grippy and stable, never far off the pace anywhere.',
    look: { color: '#d7263d', accent: '#1b1b1e', shape: 'the v3 sports car as it is (low wedge, rear wing)' },
    spec: CAR,
    stats: { mass: 1250, accel100: 2.7, accel200: 9.78, top: 277.7, accel200n: 7.57, topNitro: 291.8, tankTime: 5, tankDist: 145, brake100: 30.7, grip: 1.68, gripFast: 1.58, drift: 0.83 },
  },
  kestrel: {
    id: 'kestrel', name: 'Kestrel',
    description: 'Light and nimble: the most grip, the shortest braking and the quickest launch, but a low top speed.',
    look: { color: '#f2c14e', accent: '#2b2d42', shape: 'small, short, low roadster or hot hatch; narrow track look, small lip spoiler, no big wing' },
    spec: KESTREL,
    stats: { mass: 950, accel100: 2.43, accel200: 11.28, top: 230.2, accel200n: 9.78, topNitro: 239.8, tankTime: 4, tankDist: 102, brake100: 27.7, grip: 1.78, gripFast: 1.59, drift: 0.75 },
  },
  thunder: {
    id: 'thunder', name: 'Thunder',
    description: 'Heavy and brutal: the most power and top speed. Grips more the faster it goes; slow in tight turns.',
    look: { color: '#3a86ff', accent: '#0b0c10', shape: 'long, wide grand tourer: long bonnet, fat rear tyres, big rear wing and splitter' },
    spec: THUNDER,
    stats: { mass: 1650, accel100: 2.68, accel200: 8.2, top: 312.7, accel200n: 6.08, topNitro: 328.9, tankTime: 6, tankDist: 194, brake100: 33.8, grip: 1.47, gripFast: 1.56, drift: 1.07 },
  },
  drifter: {
    id: 'drifter', name: 'Drifter',
    description: 'Loose rally car: slides on demand, holds long drifts and lands jumps without losing speed.',
    look: { color: '#2ec4b6', accent: '#ff9f1c', shape: 'tall rally hatchback: roof scoop, mud flaps, light pod on the bonnet, raised ride height' },
    spec: DRIFTER,
    stats: { mass: 1150, accel100: 2.5, accel200: 9.23, top: 264.3, accel200n: 7.57, topNitro: 278.9, tankTime: 5, tankDist: 142, brake100: 33.1, grip: 1.59, gripFast: 1.52, drift: 1.63 },
  },
};
for (const def of Object.values(CARS)) def.bars = statBars(def.stats, def.spec);

/** Car ids in picker order. */
export const CAR_IDS = ['racer', 'kestrel', 'thunder', 'drifter'];
export const DEFAULT_CAR = 'racer';

/** The definition of car `id` (unknown or missing ids give the racer). */
export function getCar(id) {
  return Object.hasOwn(CARS, id) ? CARS[id] : CARS[DEFAULT_CAR];
}
