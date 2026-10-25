/**
 * trackBuilder.js
 * ------------------------------------------------------------------
 * Turns a track definition from trackData.js (a list of control points
 * [x, z, height, bankDeg?, widthM?]) into a "built" track: a dense list of
 * centre-line samples spaced ~SAMPLE_SPACING metres apart, with everything
 * physics, AI and rendering need (tangents, normals, per-sample width,
 * banking, checkpoints, wall grid).
 *
 * How each attribute is made:
 *   - plan (x/z): a centripetal Catmull-Rom spline through the control
 *     points on the ground plane. Samples are evenly spaced in plan
 *     distance, so (py[i+1] - py[i]) / segLen is exactly the road grade.
 *   - height: a monotone cubic (PCHIP) through the control-point heights
 *     over plan distance. It never overshoots (no hidden bumps, no dips
 *     below the lowest control point) and keeps kicker lips sharp when the
 *     control points are dense around them.
 *   - width and bank magnitude: the same monotone cubic. The 5th element
 *     of a point is the road width in metres at that point (falls back to
 *     def.width), so hw[i] varies smoothly along the track.
 *   - bank sign: from the curvature, so a positive bank angle always leans
 *     into the corner (+ = left-hand turn, raises the right edge).
 *
 * Built-track fields (all kept from v1): def, id, name, closed, laps, N,
 * count, segLen, length, segCount, px, py, pz, tx, tz, nx, nz, hw, bank,
 * cpSamples, startIdx, finishIdx, grid, gateCache.
 *
 * Start and finish: on a circuit the start/finish line is at sample 0 and
 * the cars start 12 m past it (startIdx 6), so the chase camera isn't under
 * the gate. A sprint's road can run on beyond both lines: def.startAt is
 * where the cars start, in metres from the beginning of the road (default
 * 6), with the START line 12 m behind them (startLine), and def.runOff is
 * the road left after the FINISH line (default 10 m). The built-in sprints
 * have 36 m before the start and 250 m of straight run-off, so a car that
 * crosses the line flat out can brake to a stop before the end of the road.
 *
 * New in v2 (optional extras): startLine (sample of the start line; 0 on
 * circuits), theme (def.theme or 'meadow') and kickers:
 * [{foot, lip, land, height}] = sample indices of each kicker ramp (ramp
 * foot, lip the car takes off from, bottom of the landing slope) and the
 * lip height above the foot in metres.
 */
import * as THREE from '../../vendor/three.module.min.js';
import { buildWallGrid } from '../physics/collision.js';

export const SAMPLE_SPACING = 2; // metres between centre-line samples
/** Road grades (rise/run) steeper than this only appear on kicker ramps and their landings. */
export const KICKER_GRADE = 0.12;
const DEG = Math.PI / 180;
const DIV = 48; // arc-length table resolution per spline piece

/** Build a track. Pure data, works in the browser and in Node. */
export function buildTrack(def) {
  const closed = def.type !== 'sprint';
  const n = def.points.length;
  const nSeg = closed ? n : n - 1; // spline pieces between control points
  const width = def.width ?? 14;

  // ---- plan: Catmull-Rom on the ground plane -----------------------------
  const ctrl = def.points.map((p) => new THREE.Vector3(p[0], 0, p[1]));
  const curve = new THREE.CatmullRomCurve3(ctrl, closed, 'centripetal');
  curve.arcLengthDivisions = nSeg * DIV;
  const lengths = curve.getLengths(); // cumulative plan length at t = j / (nSeg * DIV)
  const length = lengths[lengths.length - 1];
  // plan distance of every control point (closed: sCtrl[n] = length = point 0 again)
  const sCtrl = new Float64Array(nSeg + 1);
  for (let k = 0; k <= nSeg; k++) sCtrl[k] = lengths[k * DIV];

  const N = Math.max(16, Math.round(length / SAMPLE_SPACING)); // segments along the spline
  const count = closed ? N : N + 1; // samples (closed: sample N == sample 0)
  const segLen = length / N;

  const arr = () => new Float32Array(count);
  const px = arr(), py = arr(), pz = arr();
  const tx = arr(), tz = arr(), nx = arr(), nz = arr();
  const hw = arr(), bank = arr(), bankMag = arr();

  // height, bank magnitude and width: smooth monotone curves over plan distance
  const height = pchip(sCtrl, def.points.map((p) => p[2] ?? 0), closed, length);
  const bankAt = pchip(sCtrl, def.points.map((p) => Math.abs(p[3] ?? 0)), closed, length);
  const widthAt = pchip(sCtrl, def.points.map((p) => p[4] ?? width), closed, length);
  const v = new THREE.Vector3();
  for (let i = 0; i < count; i++) {
    const s = Math.min(i * segLen, length);
    curve.getPoint(curve.getUtoTmapping(s / length), v);
    px[i] = v.x; pz[i] = v.z;
    py[i] = height(s);
    bankMag[i] = bankAt(s) * DEG;
    hw[i] = widthAt(s) / 2;
  }

  const wrap = (i) => (closed ? ((i % N) + N) % N : Math.max(0, Math.min(count - 1, i)));

  // Tangents (central difference) and left normals.
  for (let i = 0; i < count; i++) {
    const a = wrap(i - 1), b = wrap(i + 1);
    const dx = px[b] - px[a], dz = pz[b] - pz[a];
    const l = Math.hypot(dx, dz) || 1;
    tx[i] = dx / l; tz[i] = dz / l;
    nx[i] = tz[i]; nz[i] = -tx[i];
  }

  // Signed curvature (+ = left turn) -> the bank leans into the corner.
  // Corners tighter than ~400 m radius get the full bank angle given in
  // the data; it fades out towards straights.
  const heading = (i) => Math.atan2(tx[i], tz[i]);
  const w = 3;
  for (let i = 0; i < count; i++) {
    const a = closed ? i - w : Math.max(0, i - w), b = closed ? i + w : Math.min(count - 1, i + w);
    let d = heading(wrap(b)) - heading(wrap(a));
    d = Math.atan2(Math.sin(d), Math.cos(d));
    const curvature = b > a ? d / ((b - a) * segLen) : 0;
    bank[i] = bankMag[i] * Math.max(-1, Math.min(1, curvature * 400));
  }
  smooth(bank, 3, closed);

  // Lift the road where banking would push the low edge under the ground.
  // (The built-in tracks are designed so this is a no-op; it protects
  // hand-written tracks.)
  const deficit = arr();
  for (let i = 0; i < count; i++) {
    deficit[i] = Math.max(0, hw[i] * Math.tan(Math.abs(bank[i])) - py[i]);
  }
  dilate(deficit, 20, closed);
  smooth(deficit, 20, closed);
  for (let i = 0; i < count; i++) py[i] += deficit[i];

  // Checkpoints are given as control-point indices; find the matching sample.
  const sampleForControlPoint = (c) => {
    const i = Math.round(sCtrl[Math.max(0, Math.min(nSeg, c))] / segLen);
    return closed ? i % N : Math.max(0, Math.min(count - 1, i));
  };
  const cpSamples = (def.checkpoints ?? []).map(sampleForControlPoint).sort((a, b) => a - b);

  const track = {
    def,
    id: def.id,
    name: def.name,
    theme: def.theme ?? 'meadow',
    closed,
    laps: closed ? def.laps ?? 3 : 1,
    N, count, segLen, length,
    segCount: closed ? N : count - 1,
    px, py, pz, tx, tz, nx, nz, hw, bank,
    cpSamples,
    // see "Start and finish" above
    startIdx: closed ? 6 : Math.max(3, Math.round((def.startAt ?? 6) / segLen)),
    finishIdx: closed ? 0 : Math.min(count - 6, count - 1 - Math.round((def.runOff ?? 10) / segLen)),
  };
  track.startLine = closed ? 0 : Math.max(0, track.startIdx - 6);
  track.kickers = findKickers(track);
  track.grid = buildWallGrid(track);
  track.gateCache = new Map();
  return track;
}

/**
 * Gates are every line the car must cross, in order, for a whole race:
 * each checkpoint of each lap, then the finish line. Positions are given in
 * "unwrapped progress" (sample units that keep counting up across laps),
 * which makes ordering and timing trivial.
 */
export function getGates(track, laps) {
  const key = laps;
  if (track.gateCache.has(key)) return track.gateCache.get(key);
  const gates = [];
  if (track.closed) {
    for (let lap = 0; lap < laps; lap++) {
      track.cpSamples.forEach((s, k) => {
        gates.push({ prog: lap * track.N + s, sample: s, kind: 'cp', lap, cp: k });
      });
      gates.push({ prog: (lap + 1) * track.N, sample: 0, kind: lap === laps - 1 ? 'finish' : 'lap', lap, cp: track.cpSamples.length });
    }
  } else {
    track.cpSamples.forEach((s, k) => gates.push({ prog: s, sample: s, kind: 'cp', lap: 0, cp: k }));
    gates.push({ prog: track.finishIdx, sample: track.finishIdx, kind: 'finish', lap: 0, cp: track.cpSamples.length });
  }
  track.gateCache.set(key, gates);
  return gates;
}

/** Race distance in metres for a given number of laps. */
export function raceLength(track, laps) {
  return track.closed ? laps * track.length : (track.finishIdx - track.startIdx) * track.segLen;
}

/**
 * Find kicker ramps: runs of samples climbing steeper than KICKER_GRADE.
 * Returns [{foot, lip, land, height}] (sample indices, in track order):
 *   foot    where the ramp starts to rise
 *   lip     the crest the car takes off from
 *   land    the bottom of the landing slope after the lip
 *   height  lip height above the foot (m)
 */
export function findKickers(track) {
  const { closed, count, N, py, segLen } = track;
  const n = closed ? N : count;
  const norm = (j) => (closed ? ((j % N) + N) % N : Math.max(0, Math.min(count - 1, j)));
  const at = (i) => py[norm(i)];
  const grade = (i) => (at(i + 1) - at(i - 1)) / (2 * segLen);
  // start scanning at a sample that is not on a ramp (closed tracks wrap)
  let i0 = 0;
  if (closed) while (i0 < n && grade(i0) > KICKER_GRADE) i0++;
  const out = [];
  for (let k = 0; k < n; k++) {
    const i = i0 + k;
    if (grade(i) <= KICKER_GRADE || (k > 0 && grade(i - 1) > KICKER_GRADE)) continue;
    let foot = i;
    while (foot > i - 200 && (closed || foot > 0) && grade(foot - 1) > 0.005) foot--;
    let lip = i;
    while (lip < i + 400 && (closed || lip < count - 1) && at(lip + 1) > at(lip)) lip++;
    let land = lip;
    while (land < lip + 400 && (closed || land < count - 1) && at(land + 1) < at(land) - 1e-4) land++;
    out.push({ foot: norm(foot), lip: norm(lip), land: norm(land), height: at(lip) - at(foot) });
    k += Math.max(0, lip - i);
  }
  return out.sort((a, b) => a.lip - b.lip);
}

// ---- interpolation helpers ------------------------------------------------

/**
 * Monotone piecewise-cubic interpolation (PCHIP, Fritsch-Carlson) of ys over
 * the knots xs. closed: periodic, the knot after the last one is the first
 * one again at x + period. Returns f(x); fastest when called with
 * increasing x.
 */
function pchip(xs, ys, closed, period) {
  const n = ys.length;
  const X = (k) => (closed ? xs[((k % n) + n) % n] + Math.floor(k / n) * period : xs[Math.max(0, Math.min(n - 1, k))]);
  const Y = (k) => (closed ? ys[((k % n) + n) % n] : ys[Math.max(0, Math.min(n - 1, k))]);
  const secant = (k) => {
    const h = X(k + 1) - X(k);
    return h > 1e-9 ? (Y(k + 1) - Y(k)) / h : 0;
  };
  const m = new Float64Array(n);
  for (let k = 0; k < n; k++) {
    if (!closed && (k === 0 || k === n - 1)) {
      m[k] = n < 2 ? 0 : k === 0 ? secant(0) : secant(n - 2);
      continue;
    }
    const d0 = secant(k - 1), d1 = secant(k);
    if (d0 * d1 <= 0) { m[k] = 0; continue; }
    const h0 = X(k) - X(k - 1), h1 = X(k + 1) - X(k);
    const w1 = 2 * h1 + h0, w2 = h1 + 2 * h0;
    m[k] = (w1 + w2) / (w1 / d0 + w2 / d1);
  }
  const pieces = closed ? n : n - 1;
  let k = 0;
  return (x) => {
    if (pieces < 1) return Y(0);
    if (x < X(k)) k = 0;
    while (k < pieces - 1 && x >= X(k + 1)) k++;
    const x0 = X(k), h = X(k + 1) - x0;
    if (h <= 1e-9) return Y(k);
    const t = Math.max(0, Math.min(1, (x - x0) / h));
    const t2 = t * t, t3 = t2 * t;
    return (2 * t3 - 3 * t2 + 1) * Y(k) + (t3 - 2 * t2 + t) * h * m[k % n] +
      (-2 * t3 + 3 * t2) * Y(k + 1) + (t3 - t2) * h * m[(k + 1) % n];
  };
}

// ---- small array helpers ------------------------------------------------

function smooth(a, r, closed) {
  const n = a.length;
  const src = Float32Array.from(a);
  for (let i = 0; i < n; i++) {
    let s = 0, c = 0;
    for (let k = -r; k <= r; k++) {
      let j = i + k;
      if (closed) j = ((j % n) + n) % n;
      else if (j < 0 || j >= n) continue;
      s += src[j]; c++;
    }
    a[i] = s / c;
  }
}

function dilate(a, r, closed) {
  const n = a.length;
  const src = Float32Array.from(a);
  for (let i = 0; i < n; i++) {
    let mx = 0;
    for (let k = -r; k <= r; k++) {
      let j = i + k;
      if (closed) j = ((j % n) + n) % n;
      else if (j < 0 || j >= n) continue;
      if (src[j] > mx) mx = src[j];
    }
    a[i] = mx;
  }
}
