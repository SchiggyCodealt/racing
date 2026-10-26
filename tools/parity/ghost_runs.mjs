// Ghost parity, JS side: records ghosts with the browser game's replay.js (a medal-autopilot
// race over the kickers of Ramp Rally with nitro, and 40 s of autopilot + random keys with
// respawns on Canyon Run: landings, wall hits and respawn jumps all add samples), and writes
// the recorder's samples, the encoded bytes (base64), decoded channels and some GhostPlayer
// poses, for tools/parity/check_ghosts.gd.   node tools/parity/ghost_runs.mjs <out.json>
import { writeFileSync } from 'node:fs';
import { stringifyHex } from './hexjson.mjs';
const web = new URL('../../web/', import.meta.url);
const { TRACKS } = await import(new URL('src/tracks/trackData.js', web));
const { buildTrack } = await import(new URL('src/tracks/trackBuilder.js', web));
const { createCar, stepCar, placeCar } = await import(new URL('src/physics/car.js', web));
const { getCar } = await import(new URL('src/physics/cars.js', web));
const { RaceState } = await import(new URL('src/game/race.js', web));
const { GhostRecorder, GhostPlayer, encodeSamples, packGhost, unpackGhost } = await import(new URL('src/game/replay.js', web));
const { makeAutopilot } = await import(new URL('tools/medals.mjs', web));

const dt = 1 / 60;
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
      ctrl.steer = [-1, 0, 1][Math.floor(rnd() * 3)] * (rnd() < 0.7 ? 1 : rnd());
      ctrl.throttle = Math.max(-1, Math.min(1, rnd() * 2.4 - 0.9));
      ctrl.handbrake = rnd() < 0.15;
      ctrl.nitro = rnd() < 0.2;
    }
    return ctrl;
  };
};
const bytesOf = (rec) => {
  // the varint bytes behind encodeSamples (format 1 is base64 of exactly those bytes)
  const { data } = encodeSamples(rec, 1);
  return data;
};

// the varint bytes behind encodeBoost (the same writer, before the text layer)
function encodeBoostBytes(rec) {
  const a = [];
  const uint = (u) => { while (u >= 128) { a.push((u % 128) + 128); u = Math.floor(u / 128); } a.push(u); };
  rec.boostSteps.forEach((step, i) => { uint(step - (i ? rec.boostSteps[i - 1] : 0)); uint(rec.boostLevels[i]); });
  return a;
}

const out = [];
for (const [id, carId, kind, steps] of [['ramp-rally', 'drifter', 'race', 54000], ['canyon-run', 'racer', 'tape', 2400]]) {
  const track = buildTrack(TRACKS.find((d) => d.id === id));
  const car = createCar(track, track.startIdx, getCar(carId).spec), race = new RaceState(track), rec = new GhostRecorder();
  const auto = makeAutopilot(track, { aLat: 24, lookK: 0.75, nitro: true }), rand = tape(7);
  rec.add(0, car);
  let k = 0;
  for (; k < steps && !race.finished; k++) {
    const ctrl = kind === 'race' || k % 300 < 180 ? auto(car) : rand();
    stepCar(car, track, ctrl, dt);
    race.update(car, dt);
    rec.add(k + 1, car, race.finished);
    if (kind === 'tape' && k % 600 === 599 && race.respawn) {
      rec.beforeJump(k + 1, car);
      placeCar(car, track, race.respawn.idx, race.respawn);
      rec.afterJump(k + 1, car);
    }
  }
  const time = race.finished ? race.finishTime : k / 60;
  const packed = packGhost(rec, { track, laps: race.laps, time, car: carId });
  const g = unpackGhost(packed, track, race.laps, carId);
  const player = g ? new GhostPlayer(g) : null;
  const poses = [];
  if (player) for (let s = 0; s <= rec.lastStep + 3; s += 37.25) {
    const ok = player.pose(s);
    const c = player.car;
    poses.push([s, ok, c.x, c.z, c.y, c.yaw, c.pitch, c.roll, c.steerAngle, c.forwardSpeed, c.boost]);
  }
  out.push({
    track: id, car: carId, kind, steps: k, laps: race.laps, time, finished: race.finished,
    recSteps: rec.steps, recVals: rec.vals, boostSteps: rec.boostSteps, boostLevels: rec.boostLevels, lastStep: rec.lastStep,
    bytes: bytesOf(rec), boostBytes: Buffer.from(encodeBoostBytes(rec)).toString('base64'),
    n: rec.count, dataLength: packed.data.length, unpacked: !!g,
    decoded: g ? { steps: Array.from(g.steps), ch: g.ch.map((a) => Array.from(a)) } : null,
    poses,
  });
}
writeFileSync(process.argv[2], stringifyHex(out));
console.log(out.map((r) => `${r.track} ${r.kind}: ${r.n} samples, ${r.boostSteps.length} nitro changes, ${r.bytes.length} base64 chars, ${r.dataLength} chars as web text`).join('\n'));
