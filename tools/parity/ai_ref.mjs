// The browser version's numbers that tests/test_ai.gd checks the Godot sensors and driver
// against (its JS_REF): the saved fixture network driving the racer from the start of two
// tracks for 120 steps; inputs and controls at steps 0 and 120 as 32-bit float bits, the
// car's x, z, yaw and speed after them as 64-bit float bits (hex).
//   node tools/parity/ai_ref.mjs
import { readFileSync } from 'node:fs';
const web = new URL('../../web/', import.meta.url);
const { TRACKS } = await import(new URL('src/tracks/trackData.js', web));
const { buildTrack } = await import(new URL('src/tracks/trackBuilder.js', web));
const { createCar, stepCar } = await import(new URL('src/physics/car.js', web));
const { sense, driveNetwork, INPUT_COUNT } = await import(new URL('src/ai/sensors.js', web));
const { parseNetworkFile } = await import(new URL('src/ai/trainer.js', web));

const net = parseNetworkFile(readFileSync(new URL('../../tests/fixtures/ai_web_network.json', import.meta.url), 'utf8')).net;
const f32 = new Float32Array(1), u32 = new Uint32Array(f32.buffer);
const f64 = new Float64Array(1), u64 = new BigUint64Array(f64.buffer);
const bits32 = (v) => { f32[0] = v; return u32[0]; };
const hex64 = (v) => { f64[0] = v; return u64[0].toString(16).padStart(16, '0'); };
const out = {};
for (const id of ['rookie-oval', 'hairpin-valley']) {
  const t = buildTrack(TRACKS.find((d) => d.id === id));
  const car = createCar(t);
  const inputs = new Float32Array(INPUT_COUNT), mirrored = new Float32Array(INPUT_COUNT), ctrl = {};
  const rec = {};
  for (let s = 0; s <= 120; s++) {
    sense(t, car, null, inputs);
    driveNetwork(net, inputs, mirrored, ctrl);
    if (s === 0 || s === 120) rec['s' + s] = { inputs: Array.from(inputs, bits32), steer: bits32(ctrl.steer), throttle: bits32(ctrl.throttle) };
    stepCar(car, t, ctrl, 1 / 60);
  }
  Object.assign(rec, { x: hex64(car.x), z: hex64(car.z), yaw: hex64(car.yaw), speed: hex64(car.speed) });
  out[id] = rec;
}
console.log(JSON.stringify(out));
