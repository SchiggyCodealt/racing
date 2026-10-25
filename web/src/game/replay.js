/**
 * replay.js
 * ------------------------------------------------------------------
 * Ghost runs: the player's race recorded as sampled poses, packed into a
 * short string for localStorage and played back on the race clock.
 * Pure logic (no DOM, no Three.js), so it runs in Node as well (npm test).
 *
 * Poses, not inputs: replaying inputs needs bit-identical physics, which any
 * later tuning (or another browser's Math.sin) breaks; poses replay the same
 * anywhere. They cost more bytes, so they are packed:
 *   - a sample every GHOST_EVERY physics steps (30 Hz), one at the finish,
 *     two around each landing or wall hit (the path bends within a step),
 *     and one on each side of a respawn (two samples at the same step = a
 *     jump, never interpolated across);
 *   - per sample: position and height (1 cm), yaw, pitch and roll (1 mrad),
 *     front wheel angle (2 mrad) and forward speed (0.1 m/s, for the wheel
 *     spin), each stored as its difference from a prediction (position,
 *     height and yaw: the last value plus the last change; the rest: the
 *     last value) as a zigzag varint, plus the step gap: about 9 bytes a
 *     sample; then written 15 bits to a character (U+0800-U+87FF, which
 *     JSON leaves as they are), ~8.5 K characters per minute of racing.
 *     (Format 1, before v4, used base64: 6 bits a character, ~21 K per
 *     minute. Browsers limit a site's storage to about 5 M characters, so
 *     v4's ghost per track and car needed the denser text; format 1 ghosts
 *     are still read.)
 * Playback interpolates linearly between samples (at 30 Hz the chord of a
 * 16 m hairpin is within 3 mm of the arc).
 *
 * Timing: sample n is the pose after physics step n since GO (step 0 = the
 * start), i.e. at race time n × 1/60 s. PlayMode counts the same steps, so
 * the ghost is exactly on the race clock, respawns included.
 *
 * v4: a ghost also keeps the car that drove it (`car`, an id from
 * src/physics/cars.js; ghosts saved before v4 have none and were all driven
 * with the racer) and when it burned nitro (`boost`: every physics step where
 * the nitro amount changed, as varints: the step gap and the new amount in
 * tenths; a few dozen bytes a race), so its flames show on replay.
 *
 * A saved ghost is a small JSON object (see packGhost) tagged with the
 * format version, track id and layout, laps, car and PHYSICS_VERSION;
 * unpackGhost returns null for anything that doesn't match or decode.
 */
import { PHYSICS_VERSION } from '../physics/car.js';
import { CAR_IDS, DEFAULT_CAR } from '../physics/cars.js';

export const GHOST_FORMAT = 2;                  // v4: 15 bits a character (1: base64, still read)
export const GHOST_EVERY = 2;                   // physics steps per sample (60 Hz / 2 = 30 Hz)
export const GHOST_MAX_STEPS = 60 * 60 * 15;    // runs longer than 15 minutes are not kept

// Channels: x, z, y (m), yaw (unwrapped), pitch, roll, steer angle (rad), forward speed (m/s).
const CH = 8;
const SCALE = [100, 100, 100, 1000, 1000, 1000, 500, 10];
const ORDER2 = [true, true, true, true, false, false, false, false]; // predict with the last change too

const wrapAngle = (a) => Math.atan2(Math.sin(a), Math.cos(a));

/** Records one run. add() after every physics step; it keeps the samples it needs. */
export class GhostRecorder {
  constructor(every = GHOST_EVERY, maxSteps = GHOST_MAX_STEPS) {
    this.every = every;
    this.maxSteps = maxSteps;
    this._pose = new Array(CH).fill(0);
    this._prev = new Array(CH).fill(0); // the pose after the previous step, kept for a kink
    this.reset();
  }

  reset() {
    this.steps = [];
    this.vals = [];      // CH numbers per sample
    this.boostSteps = []; // v4: the steps where the nitro amount (car.boost, in tenths) changed ...
    this.boostLevels = []; // ... and the new amount (0..10)
    this._boost = 0;
    this.lastStep = -1;
    this.full = false;   // ran past maxSteps: this run can't become a ghost
    this._prevStep = -1;
    this._grounded = true;
  }

  get count() {
    return this.steps.length;
  }

  /**
   * The car's pose after physics step `step`: kept on the 30 Hz grid, or always
   * with `force`. A landing or a wall hit bends the path within one step, so
   * the poses on both sides of that step are kept (no corner cut, no ghost
   * dipping into the road or a wall between samples).
   */
  add(step, car, force = false) {
    if (this.full) return;
    if (step > this.maxSteps) { this.full = true; return; }
    const boost = Math.round(Math.max(0, Math.min(1, car.boost || 0)) * 10);
    if (boost !== this._boost) { this.boostSteps.push(step); this.boostLevels.push(boost); this._boost = boost; }
    const kink = this.lastStep >= 0 && (car.grounded !== this._grounded || car.wallImpact > WALL_KINK);
    this._grounded = car.grounded;
    if (kink && this._prevStep > this.lastStep) this._push(this._prevStep, this._prev);
    const p = poseOf(car, this._pose);
    if (force || kink || (step % this.every === 0 && step !== this.lastStep)) this._push(step, p);
    this._prev.splice(0, CH, ...p);
    this._prevStep = step;
  }

  /** Call before a respawn moves the car (keeps its pose at this step) ... */
  beforeJump(step, car) {
    if (step > this.lastStep) this.add(step, car, true);
  }

  /** ... and after it (the new pose at the same step). */
  afterJump(step, car) {
    this._push(step, poseOf(car, this._pose));
    this._grounded = car.grounded;
  }

  _push(step, p) {
    const n = this.steps.length;
    // unwrapped yaw, so the stored differences stay small through full turns
    const last = n ? this.vals[(n - 1) * CH + 3] : 0;
    this.steps.push(step);
    this.vals.push(p[0], p[1], p[2], n ? last + wrapAngle(p[3] - last) : p[3], p[4], p[5], p[6], p[7]);
    this.lastStep = step;
  }
}

const WALL_KINK = 0.3; // m/s into a wall removed in one step: keep the samples around it

function poseOf(car, out) {
  out[0] = car.x; out[1] = car.z; out[2] = car.y; out[3] = car.yaw;
  out[4] = car.pitch ?? 0; out[5] = car.roll ?? 0; out[6] = car.steerAngle ?? 0; out[7] = car.forwardSpeed ?? 0;
  return out;
}

// ---- bytes ---------------------------------------------------------------------

class Bytes {
  constructor(size = 4096) { this.a = new Uint8Array(size); this.n = 0; }
  push(b) {
    if (this.n === this.a.length) { const b2 = new Uint8Array(this.a.length * 2); b2.set(this.a); this.a = b2; }
    this.a[this.n++] = b;
  }
  /** Unsigned varint (7 bits per byte, low first); plain arithmetic, so values past 2^31 are fine. */
  uint(u) {
    while (u >= 128) { this.push((u % 128) + 128); u = Math.floor(u / 128); }
    this.push(u);
  }
  int(v) { this.uint(v >= 0 ? 2 * v : -2 * v - 1); } // zigzag
}

class Reader {
  constructor(a) { this.a = a; this.i = 0; }
  uint() {
    let u = 0, mul = 1;
    for (let k = 0; k < 7; k++) {
      if (this.i >= this.a.length) throw new Error('ghost data truncated');
      const b = this.a[this.i++];
      u += (b & 127) * mul;
      if (b < 128) return u;
      mul *= 128;
    }
    throw new Error('ghost varint too long');
  }
  int() { const u = this.uint(); return u % 2 ? -(u + 1) / 2 : u / 2; }
}

// format 1 (before v4)
function toBase64(bytes) {
  let s = '';
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
  return btoa(s);
}

function fromBase64(str) {
  const s = atob(str);
  const a = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) a[i] = s.charCodeAt(i);
  return a;
}

// format 2 (v4): 15 bits a character, from U+0800 (no control characters, quotes, backslashes or
// surrogates, so JSON.stringify leaves every character as it is: one character in storage)
const TEXT0 = 0x800;

function toText(bytes) {
  const codes = new Uint16Array(Math.ceil((bytes.length * 8) / 15));
  let acc = 0, bits = 0, n = 0;
  for (let i = 0; i < bytes.length; i++) {
    acc = (acc << 8) | bytes[i];
    bits += 8;
    if (bits >= 15) { bits -= 15; codes[n++] = TEXT0 + (acc >> bits); acc &= (1 << bits) - 1; }
  }
  if (bits > 0) codes[n++] = TEXT0 + (acc << (15 - bits)); // the last character is padded with zero bits
  let s = '';
  for (let i = 0; i < n; i += 0x8000) s += String.fromCharCode.apply(null, codes.subarray(i, i + 0x8000));
  return s;
}

/** The bytes of toText's string; the padding can make one zero byte more than were written. Throws on a foreign character. */
function fromText(str) {
  const a = new Uint8Array(Math.floor((str.length * 15) / 8));
  let acc = 0, bits = 0, n = 0;
  for (let i = 0; i < str.length; i++) {
    const v = str.charCodeAt(i) - TEXT0;
    if (!(v >= 0 && v < 0x8000)) throw new Error('bad ghost text');
    acc = (acc << 15) | v;
    bits += 15;
    while (bits >= 8) { bits -= 8; a[n++] = acc >> bits; acc &= (1 << bits) - 1; }
  }
  return a;
}

/** True when a reader has read all its bytes but (format 2) a padding zero byte. */
const readAll = (r, format) => r.i === r.a.length || (format !== 1 && r.i === r.a.length - 1 && r.a[r.i] === 0);

// ---- pack / unpack ---------------------------------------------------------------

/** Short fingerprint of a track's layout, so a ghost of an edited track isn't replayed off the road. */
export function trackSignature(track) {
  return `${track.count}:${Math.round(track.length)}`;
}

/** Encode a recorder's samples: {n, data (text; format 1: base64)}. */
export function encodeSamples(rec, format = GHOST_FORMAT) {
  const n = rec.count, out = new Bytes(n * 10 + 16);
  const q1 = new Array(CH).fill(0), q2 = new Array(CH).fill(0); // last two quantized values per channel
  for (let i = 0; i < n; i++) {
    out.uint(i ? rec.steps[i] - rec.steps[i - 1] : rec.steps[0]);
    for (let c = 0; c < CH; c++) {
      const q = Math.round(rec.vals[i * CH + c] * SCALE[c]);
      const pred = i === 0 ? 0 : ORDER2[c] && i > 1 ? 2 * q1[c] - q2[c] : q1[c];
      out.int(q - pred);
      q2[c] = q1[c]; q1[c] = q;
    }
  }
  const bytes = out.a.subarray(0, out.n);
  return { n, data: format === 1 ? toBase64(bytes) : toText(bytes) };
}

/** Decode {n, data} (of ghost format `format`) back to {steps: Int32Array, ch: Float64Array[CH]}; throws on bad data. */
export function decodeSamples(n, data, format = GHOST_FORMAT) {
  if (!Number.isInteger(n) || n < 1 || n > GHOST_MAX_STEPS + 64 || typeof data !== 'string') throw new Error('bad ghost header');
  const r = new Reader(format === 1 ? fromBase64(data) : fromText(data));
  const steps = new Int32Array(n);
  const ch = Array.from({ length: CH }, () => new Float64Array(n));
  const q1 = new Array(CH).fill(0), q2 = new Array(CH).fill(0);
  for (let i = 0; i < n; i++) {
    steps[i] = (i ? steps[i - 1] : 0) + r.uint();
    if (steps[i] > GHOST_MAX_STEPS) throw new Error('ghost too long');
    for (let c = 0; c < CH; c++) {
      const pred = i === 0 ? 0 : ORDER2[c] && i > 1 ? 2 * q1[c] - q2[c] : q1[c];
      const q = pred + r.int();
      if (!Number.isFinite(q)) throw new Error('bad ghost value');
      ch[c][i] = q / SCALE[c];
      q2[c] = q1[c]; q1[c] = q;
    }
  }
  if (!readAll(r, format)) throw new Error('ghost data has trailing bytes');
  return { steps, ch };
}

/** The nitro changes of a recorder (v4) as text: per change, the step gap and the new level (0..10). */
export function encodeBoost(rec) {
  const out = new Bytes(rec.boostSteps.length * 3 + 8);
  rec.boostSteps.forEach((step, i) => { out.uint(step - (i ? rec.boostSteps[i - 1] : 0)); out.uint(rec.boostLevels[i]); });
  return toText(out.a.subarray(0, out.n));
}

/** Decode encodeBoost's string to {steps: Int32Array, level: Float32Array (0..1)}; throws on bad data or a change after `end`. */
export function decodeBoost(data, end) {
  if (typeof data !== 'string') throw new Error('bad ghost boost');
  const r = new Reader(fromText(data)), steps = [], level = [];
  while (r.a.length - r.i >= 2) { // (a change takes two bytes or more; one byte left over is the padding)
    const gap = r.uint(), b = r.uint();
    const step = (steps.length ? steps[steps.length - 1] : 0) + gap;
    if ((steps.length && gap < 1) || step > end || b > 10) throw new Error('bad ghost boost');
    steps.push(step);
    level.push(b / 10);
  }
  if (!readAll(r, GHOST_FORMAT)) throw new Error('ghost boost has trailing bytes');
  return { steps: Int32Array.from(steps), level: Float32Array.from(level) };
}

/**
 * The object to save for a finished run (JSON-safe).
 * @param info {track, laps, time (finish time, s), car? (the car's id, default the racer),
 *              format? (1: exactly what v3 saved, base64 with no car or nitro; for tests)}
 */
export function packGhost(rec, info) {
  const format = info.format ?? GHOST_FORMAT;
  const { n, data } = encodeSamples(rec, format);
  return {
    format, physics: PHYSICS_VERSION,
    track: info.track.id, sig: trackSignature(info.track), laps: info.laps,
    ...(format === 1 ? {} : { car: info.car ?? DEFAULT_CAR }),
    time: info.time, steps: rec.lastStep, every: rec.every,
    date: new Date().toISOString(), n, data,
    ...(format !== 1 && rec.boostSteps.length ? { boost: encodeBoost(rec) } : {}),
  };
}

/** The car that drove saved ghost data: its car tag (a ghost saved before v4 has none: the racer). */
export function ghostCarOf(saved) {
  return saved?.car === undefined ? DEFAULT_CAR : saved.car;
}

/**
 * True when saved ghost data is tagged for this format, physics, track layout
 * and lap count, and for a known car (car `car` when given), without decoding it.
 */
export function ghostFits(saved, track, laps, car) {
  return !!saved && typeof saved === 'object' &&
    (saved.format === GHOST_FORMAT || saved.format === 1) && saved.physics === PHYSICS_VERSION &&
    saved.track === track.id && saved.sig === trackSignature(track) && saved.laps === laps &&
    CAR_IDS.includes(ghostCarOf(saved)) && (car == null || ghostCarOf(saved) === car) &&
    saved.time > 0 && saved.time < GHOST_MAX_STEPS / 60;
}

/**
 * A playable ghost from saved data ({time, date, steps, ch, end, car, boost}),
 * or null when it is missing, from another format / physics version / track
 * layout / lap count / car (when `car` is given), or doesn't decode.
 * Never throws.
 */
export function unpackGhost(saved, track, laps, car) {
  try {
    if (!ghostFits(saved, track, laps, car)) return null;
    const { steps, ch } = decodeSamples(saved.n, saved.data, saved.format);
    // the last sample is the finish; the samples must not run backwards
    if (steps[0] !== 0 || steps[saved.n - 1] !== saved.steps) return null;
    if (Math.abs(saved.steps / 60 - saved.time) > 0.02) return null;
    for (let i = 1; i < saved.n; i++) if (steps[i] < steps[i - 1]) return null;
    const boost = saved.boost === undefined ? null : decodeBoost(saved.boost, saved.steps);
    return { time: saved.time, date: saved.date, steps, ch, end: saved.steps, car: ghostCarOf(saved), boost };
  } catch {
    return null;
  }
}

/** Plays an unpacked ghost: pose(step) for any (fractional) step since GO. */
export class GhostPlayer {
  constructor(ghost) {
    this.g = ghost;
    this.i = 0;
    this.k = -1; // the last nitro change at or before the pose (-1: none yet)
    // a car-like object for CarModel.update (no wheelRot: the model spins the wheels from forwardSpeed;
    // boost / boosting light its nitro flames)
    this.car = {
      x: 0, y: 0, z: 0, yaw: 0, pitch: 0, roll: 0, steerAngle: 0, forwardSpeed: 0, speed: 0,
      vx: 0, vz: 0, sideSpeed: 0, steer: 0, throttle: 0, grounded: true, drifting: false, braking: false, slip: 0,
      boost: 0, boosting: false,
    };
  }

  get end() {
    return this.g.end;
  }

  /**
   * Move this.car to the ghost's pose at `s` steps after GO (s may be fractional).
   * Returns false after the ghost's finish (it is then gone).
   */
  pose(s, out = this.car) {
    const { steps, ch } = this.g;
    const n = steps.length;
    if (!(s <= steps[n - 1])) return false;
    if (s < 0) s = 0;
    // last sample at or before s (the later one of a respawn pair)
    let i = this.i;
    if (i >= n || steps[i] > s) {
      let lo = 0, hi = n - 1;
      while (lo < hi) { const m = (lo + hi + 1) >> 1; if (steps[m] <= s) lo = m; else hi = m - 1; }
      i = lo;
    }
    while (i + 1 < n && steps[i + 1] <= s) i++;
    this.i = i;
    const j = Math.min(i + 1, n - 1);
    const u = j > i ? (s - steps[i]) / (steps[j] - steps[i]) : 0;
    const v = (c) => ch[c][i] + (ch[c][j] - ch[c][i]) * u;
    out.x = v(0); out.z = v(1); out.y = v(2);
    out.yaw = v(3); out.pitch = v(4); out.roll = v(5); out.steerAngle = v(6);
    out.forwardSpeed = v(7);
    out.speed = Math.abs(out.forwardSpeed);
    out.vx = Math.sin(out.yaw) * out.forwardSpeed;
    out.vz = Math.cos(out.yaw) * out.forwardSpeed;
    out.boost = this.boostAt(s);
    out.boosting = out.boost > 0;
    return true;
  }

  /** The nitro amount (0..1) the ghost burned at step `s` (0 for a ghost without nitro data). */
  boostAt(s) {
    const b = this.g.boost;
    if (!b || !b.steps.length) return 0;
    let k = this.k;
    if (k >= 0 && b.steps[k] > s) {
      let lo = -1, hi = k; // the last change at or before s (-1: none)
      while (lo < hi) { const m = (lo + hi + 1) >> 1; if (b.steps[m] <= s) lo = m; else hi = m - 1; }
      k = lo;
    }
    while (k + 1 < b.steps.length && b.steps[k + 1] <= s) k++;
    this.k = k;
    return k >= 0 ? b.level[k] : 0;
  }
}
