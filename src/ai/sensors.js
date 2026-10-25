/**
 * sensors.js
 * ------------------------------------------------------------------
 * What the AI "sees", and the glue that turns network outputs into car
 * controls. v2 inputs (18, all within -1..1):
 *
 *   0-8   distance rays fanning out from the car's nose (-90°..+90°),
 *         distance / SENSOR_RANGE (1 = no wall within 100 m)
 *   9     forward speed / CAR.maxSpeed
 *   10    side slip: sideways speed (+ = sliding to the left) / 8 m/s
 *   11    yaw rate (+ = turning left) / 1.5 rad/s
 *   12    aim near: direction to the point on the centre line
 *         L = 10 m + 0.6 s × speed ahead (+ = left) / 90°
 *   13    aim far: direction to the centre line 2.5 L ahead / 180°
 *   14    road turn: how much the road turns between 25 and 60 m ahead
 *         (+ = left), tanh(angle / 1.6 rad)
 *   15-17 corner margin: (corner speed - car speed) / 20 m/s for the
 *         tightest bend 0-50 m, 50-110 m and 110-200 m ahead, where the
 *         corner speed is sqrt(CORNER_GRIP × radius) (~55 km/h for a 16 m
 *         hairpin). Negative = faster than that corner allows.
 *
 * Why these: with the v2 physics a car must brake well before a corner
 * (100-0 km/h takes ~31 m, 200-60 km/h ~130 m), earlier than wall rays can
 * show it, and must steer smoothly through hairpins. The road inputs are
 * what a driver who knows the track has: where the road goes and how fast
 * the next corners are. "Brake when the margin goes negative" and "steer
 * towards the aim point" are then simple weighted sums that evolution finds
 * quickly (Hairpin Valley: first finish in ~20-35 generations instead of
 * none in 150 with v1-style inputs). The rays still matter: they show the
 * walls, the road width and the room to use. Everything except the rays is
 * O(1) per car (the track data is pre-computed once per track).
 *
 * The driver is left/right symmetric by construction (driveNetwork): the
 * network also sees the mirrored situation and the answers are combined.
 */
import { raycast } from '../physics/collision.js';
import { CAR } from '../physics/car.js';

/** Ray angles in degrees relative to the car's heading (+ = left). */
export const SENSOR_ANGLES = [90, 60, 35, 15, 0, -15, -35, -60, -90];
export const SENSOR_RANGE = 100; // metres
/** Aim points: near = AIM_BASE + AIM_TIME × speed metres ahead, far = AIM_FAR × that. */
const AIM_BASE = 10, AIM_TIME = 0.6, AIM_FAR = 2.5;
/** Stretch of road ahead [from, to] in metres whose total turn is an input. */
export const TURN_WINDOW = [25, 60];
const TURN_SCALE = 1.6; // rad: input = tanh(turn / TURN_SCALE)
/** Stretches of road ahead [from, to] in metres: margin to the tightest bend's speed. */
export const CORNER_WINDOWS = [[0, 50], [50, 110], [110, 200]];
const CORNER_GRIP = 14.5; // m/s², lateral grip used for the corner speed sqrt(grip × radius)
const MARGIN_SCALE = 20; // m/s
const CURV_HALF = 3; // samples either side used to measure the road curvature (±6 m)

const SENSOR_RAD = SENSOR_ANGLES.map((a) => (a * Math.PI) / 180);
const RAY_COS = SENSOR_RAD.map(Math.cos);
const RAY_SIN = SENSOR_RAD.map(Math.sin);
const NR = SENSOR_ANGLES.length;

export const INPUT_LABELS = [
  ...SENSOR_ANGLES.map((a) => (a === 0 ? 'ray front' : `ray ${a > 0 ? 'left' : 'right'} ${Math.abs(a)}°`)),
  'speed',
  'side slip',
  'yaw rate',
  'aim near',
  'aim far',
  `road turn ${TURN_WINDOW[0]}-${TURN_WINDOW[1]} m`,
  ...CORNER_WINDOWS.map(([a, b]) => `corner margin ${a}-${b} m`),
];
export const OUTPUT_LABELS = ['steer', 'throttle'];
export const INPUT_COUNT = INPUT_LABELS.length;
export const OUTPUT_COUNT = OUTPUT_LABELS.length;
/** Bumped whenever the inputs change meaning, so old network files are rejected clearly. */
export const SENSOR_VERSION = 2;
/** Inputs that change sign in a mirror image (left <-> right); the rays swap order. */
const MIRROR_NEGATE = [NR + 1, NR + 2, NR + 3, NR + 4, NR + 5];

/**
 * Per-track data for the road inputs, computed once and cached on the track:
 *   theta   unwrapped road heading at every sample (rad, + = left turn)
 *   total   total turn over one lap (closed tracks, ±2π)
 *   sparse  range-maximum table of the road curvature (1/m) for O(1) queries;
 *           closed tracks are laid out twice so a range can run over the line
 */
export function trackHeadings(track) {
  if (track._aiHead) return track._aiHead;
  const { count, closed, N, tx, tz, segLen } = track;
  const n = closed ? N : count;
  const theta = new Float64Array(n);
  let prev = Math.atan2(tx[0], tz[0]);
  theta[0] = prev;
  for (let i = 1; i < n; i++) {
    const a = Math.atan2(tx[i], tz[i]);
    theta[i] = theta[i - 1] + wrapAngle(a - prev);
    prev = a;
  }
  const total = closed ? theta[n - 1] + wrapAngle(Math.atan2(tx[0], tz[0]) - prev) - theta[0] : 0;
  const h = { theta, total, n, closed, sparse: null, len: 0 };
  const len = closed ? 2 * n : n;
  const curv = new Float32Array(len);
  for (let i = 0; i < len; i++) {
    const a = closed ? i - CURV_HALF : Math.max(0, i - CURV_HALF);
    const b = closed ? i + CURV_HALF : Math.min(n - 1, i + CURV_HALF);
    curv[i] = b > a ? Math.abs(headingAt(h, b) - headingAt(h, a)) / ((b - a) * segLen) : 0;
  }
  const levels = [curv];
  for (let w = 1; 2 * w <= len; w *= 2) {
    const p = levels[levels.length - 1];
    const q = new Float32Array(len - 2 * w + 1);
    for (let i = 0; i < q.length; i++) q[i] = p[i] > p[i + w] ? p[i] : p[i + w];
    levels.push(q);
  }
  h.sparse = levels;
  h.len = len;
  track._aiHead = h;
  return h;
}

/** Unwrapped road heading at a fractional sample position s (may run past the lap end). */
function headingAt(h, s) {
  const { theta, n } = h;
  if (h.closed) {
    const lap = Math.floor(s / n);
    const r = s - lap * n;
    const i = Math.min(n - 1, Math.floor(r)), t = r - i;
    const a = theta[i];
    const b = i + 1 < n ? theta[i + 1] : theta[0] + h.total;
    return a + (b - a) * t + lap * h.total;
  }
  if (s <= 0) return theta[0];
  if (s >= n - 1) return theta[n - 1];
  const i = Math.floor(s), t = s - i;
  return theta[i] + (theta[i + 1] - theta[i]) * t;
}

/** Largest road curvature between samples l and r (integers, r >= l; may run past the lap end on closed tracks). */
function sharpest(h, l, r) {
  if (h.closed) {
    const span = Math.min(r - l, h.n - 1);
    l = ((l % h.n) + h.n) % h.n;
    r = l + span;
  } else {
    if (l < 0) l = 0;
    if (r > h.len - 1) r = h.len - 1;
    if (r < l) return 0;
  }
  const k = 31 - Math.clz32(r - l + 1);
  const t = h.sparse[k];
  const a = t[l], b = t[r - (1 << k) + 1];
  return a > b ? a : b;
}

/** Angle (rad, + = left) from the car's heading to the centre line at sample position s. */
function bearing(track, car, s, fx, fz) {
  let i, t;
  if (track.closed) {
    const n = track.N;
    s = ((s % n) + n) % n;
    i = Math.min(n - 1, Math.floor(s));
    t = s - i;
  } else if (s >= track.count - 1) {
    i = track.count - 2; t = 1;
  } else if (s <= 0) {
    i = 0; t = 0;
  } else {
    i = Math.floor(s); t = s - i;
  }
  const j = track.closed ? (i + 1) % track.N : i + 1;
  const x = track.px[i] + (track.px[j] - track.px[i]) * t - car.x;
  const z = track.pz[i] + (track.pz[j] - track.pz[i]) * t - car.z;
  return Math.atan2(x * fz - z * fx, x * fx + z * fz);
}

/**
 * Fill `inputs` (length INPUT_COUNT) for this car.
 * `rays` (optional, length SENSOR_ANGLES.length) receives raw distances in metres.
 * `race` is kept for API compatibility (v1 read the next checkpoint from it).
 */
export function sense(track, car, race, inputs, rays = null) {
  const fx = Math.sin(car.yaw), fz = Math.cos(car.yaw);
  const lx = fz, lz = -fx;
  const ox = car.x + fx * 1.5, oz = car.z + fz * 1.5;
  const grid = track.grid;
  for (let k = 0; k < NR; k++) {
    const c = RAY_COS[k], s = RAY_SIN[k];
    const d = raycast(grid, ox, oz, fx * c + lx * s, fz * c + lz * s, SENSOR_RANGE);
    inputs[k] = d / SENSOR_RANGE;
    if (rays) rays[k] = d;
  }
  const u = car.forwardSpeed;
  inputs[NR] = u / CAR.maxSpeed;
  inputs[NR + 1] = clamp1(car.sideSpeed / 8); // sideSpeed: + = moving to the car's left
  inputs[NR + 2] = clamp1((car.yawRate || 0) / 1.5);

  // Where the road goes, and how fast the next corners can be taken.
  const h = trackHeadings(track);
  const s0 = track.closed ? car.prog - car.laps * track.N : car.prog; // progress within the lap, samples
  const inv = 1 / track.segLen;
  const L = (AIM_BASE + AIM_TIME * (u > 0 ? u : 0)) * inv;
  inputs[NR + 3] = clamp1(bearing(track, car, s0 + L, fx, fz) / (Math.PI / 2));
  inputs[NR + 4] = clamp1(bearing(track, car, s0 + AIM_FAR * L, fx, fz) / Math.PI);
  const turn = headingAt(h, s0 + TURN_WINDOW[1] * inv) - headingAt(h, s0 + TURN_WINDOW[0] * inv);
  inputs[NR + 5] = Math.tanh(turn / TURN_SCALE);
  const i0 = Math.round(s0);
  for (let w = 0; w < CORNER_WINDOWS.length; w++) {
    const kappa = sharpest(h, i0 + Math.round(CORNER_WINDOWS[w][0] * inv), i0 + Math.round(CORNER_WINDOWS[w][1] * inv));
    let vc = kappa > 1e-6 ? Math.sqrt(CORNER_GRIP / kappa) : CAR.maxSpeed;
    if (vc > CAR.maxSpeed) vc = CAR.maxSpeed;
    inputs[NR + 6 + w] = clamp1((vc - u) / MARGIN_SCALE);
  }
  return inputs;
}

function clamp1(v) {
  return v > 1 ? 1 : v < -1 ? -1 : v;
}

function wrapAngle(a) {
  return Math.atan2(Math.sin(a), Math.cos(a));
}

/** Map network outputs (tanh, -1..1) onto car controls. */
export function outputsToControls(out, ctrl) {
  ctrl.steer = out[0];
  ctrl.throttle = out[1];
  ctrl.handbrake = false;
  return ctrl;
}

/**
 * The same situation seen in a mirror (left and right swapped): rays in
 * reverse order, sideways quantities and directions negated, speeds and
 * corner margins unchanged.
 */
export function mirrorInputs(src, dst) {
  for (let k = 0; k < NR; k++) dst[k] = src[NR - 1 - k];
  for (let k = NR; k < INPUT_COUNT; k++) dst[k] = src[k];
  for (const k of MIRROR_NEGATE) dst[k] = -src[k];
  return dst;
}

/**
 * Run a driver network and fill the car controls. The network is evaluated
 * on the inputs and on their mirror image, and the two answers are combined
 * so the driver is exactly left/right symmetric: steer = (s - s') / 2,
 * throttle = (t + t') / 2. A network that has learned a left hairpin can
 * then also take a right one, which roughly halves what evolution has to
 * find. The real (unmirrored) pass runs last, so net.acts holds its
 * activations for the network diagram, with the combined controls written
 * into the output layer.
 */
export function driveNetwork(net, inputs, mirrored, ctrl) {
  mirrorInputs(inputs, mirrored);
  const m = net.forward(mirrored);
  const ms = m[0], mt = m[1];
  const out = net.forward(inputs);
  out[0] = 0.5 * (out[0] - ms);
  out[1] = 0.5 * (out[1] + mt);
  return outputsToControls(out, ctrl);
}

/**
 * Convenience driver for a single AI car (watch mode / ghost).
 * Call drive() once per physics step before stepCar().
 */
export class AIDriver {
  constructor(net) {
    this.net = net;
    this.inputs = new Float32Array(INPUT_COUNT);
    this.mirrored = new Float32Array(INPUT_COUNT);
    this.rays = new Float32Array(SENSOR_ANGLES.length);
    this.ctrl = { steer: 0, throttle: 0, handbrake: false };
  }

  drive(track, car, race) {
    sense(track, car, race, this.inputs, this.rays);
    return driveNetwork(this.net, this.inputs, this.mirrored, this.ctrl);
  }
}
