/**
 * turtle.mjs — helper for designing tracks (v2).
 * ------------------------------------------------------------------
 * Writing control points by hand works for simple shapes, but it is much
 * easier to "drive" a turtle around and let it write the points:
 *
 *   const t = turtle({ width: 14, y: 2 });   // start at (0, 0), heading +z, 2 m up
 *   t.S(200);                     // straight 200 m
 *   t.L(90, 40, { bank: 12 });    // left turn: 90°, radius 40 m, 12° banking
 *   t.S(150, { y: 8 });           // straight, climbing smoothly to 8 m
 *   t.hairpin('R', 16);           // right 180° switchback, radius 16 m
 *   t.width(10, 40);              // narrow the road to 10 m over the next 40 m
 *   t.hill(240, 5);               // a smooth 5 m crest over 240 m of straight
 *   t.kicker({ h: 5 });           // kicker jump with a straight landing zone
 *   const { points, checkpoints } = t.finish({ closed: true });
 *
 * Plan (x/z):
 *   S(len, o)              straight of len metres.
 *   L(deg, r, o) / R(...)  left / right turn of `deg` degrees, tightest
 *                          radius r. Turns get clothoid (spiral) entries and
 *                          exits like real roads: the curvature ramps up over
 *                          o.lt metres (default 0.8 r, clamped to 8-50 m), so
 *                          steering and banking build up smoothly instead of
 *                          jumping. The heading change is exactly `deg`.
 *                          o.lt = 0 gives a plain circular arc.
 *                          o.bank = banking in degrees (leans into the turn,
 *                          follows the curvature through the spirals).
 *   SL / SR(deg, r, o, gap) S-bend: left-then-right / right-then-left, each
 *                          `deg` degrees, with `gap` m of straight between.
 *   hairpin(dir, r, o)     180° switchback, dir = 'L' or 'R'.
 * Height (y):
 *   Heights are keyframes along the distance driven. Between keyframes the
 *   height follows a smooth monotone curve (PCHIP: no overshoot), so a
 *   straight with { y } becomes a hill road, not a ramp with kinks.
 *   Every plan command accepts o.y = height at its end.
 *   y(h)                   keyframe at the current position; y() holds the
 *                          current height constant up to here.
 *   climb(len, y1)         straight that climbs (or descends) from the
 *                          current height to y1 over exactly len metres.
 *   hill(len, dh)          straight with a smooth crest (dh > 0) or dip (< 0).
 *   kicker({h, ramp, land, run, lead, drop})
 *                          straight kicker jump: `lead` m flat run-up, a
 *                          ramp of `ramp` m (curved foot, then a constant
 *                          grade) up to a sharp lip `h` m high, a landing
 *                          slope of `land` m back down (ending `drop` m below
 *                          the start for a step-down) and `run` m of flat
 *                          straight. land + run = straight landing zone.
 *                          ramp/land/run are lengthened when needed so the
 *                          ramp is <= 22 %, the landing <= 13 % and the
 *                          landing zone >= 170 m (a car taking off at
 *                          ~210 km/h flies about 150 m).
 * Width:
 *   width(w, len)          change the road width to w metres smoothly over
 *                          the next len metres (default 40). Every plan
 *                          command also accepts o.w (and o.wLen).
 * Checkpoints:
 *   cp()                   checkpoint at the current position. If a track has
 *                          none, finish() spaces them evenly (cpSpacing,
 *                          default 400 m), never on a jump and preferring
 *                          straights.
 * Output:
 *   finish({ closed, cpSpacing, startAt, runOff }) -> { points, checkpoints, length,
 *     closure, kickers, cpDistances, profile, state }
 *   points are [x, z, height, bankDeg, widthM] for trackData.js, emitted
 *   adaptively (dense in turns and on kickers, sparse on straights) so the
 *   spline in trackBuilder.js reproduces the designed shape. closure = gap
 *   between the end and the start in metres (closed tracks). state =
 *   { x, z, yaw, s, y, width } = where the turtle is now. profile(s) =
 *   the designed height at distance s. kickers = [{foot, lip, landEnd, h,
 *   grade, landGrade, ...}] (distances in m).
 *   closeLoop(make) solves two straight lengths so a circuit closes exactly.
 *   Sprints: startAt = metres of road before the cars' start position,
 *   runOff = metres of road after the finish line (both also go into the
 *   track definition); automatic checkpoints stay between the two.
 *
 * Coordinates: forward(yaw) = (sin yaw, cos yaw), positive yaw = left turn.
 */
const DEG = Math.PI / 180;
const DS = 0.25; // integration step (m)
const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
const smoothstep = (f) => { f = clamp(f, 0, 1); return f * f * (3 - 2 * f); };

export function turtle(opts = {}) {
  const st = {
    x: opts.x ?? 0, z: opts.z ?? 0, yaw: opts.yaw ?? 0,
    s: 0, y: opts.y ?? 0, width: opts.width ?? 14,
  };
  const start = { ...st };
  // dense path, every ~DS metres: distance, position, heading, curvature, bank magnitude
  const P = { s: [0], x: [st.x], z: [st.z], yaw: [st.yaw], k: [0], b: [0] };
  const hKeys = [{ s: 0, h: st.y, flat: false }];
  const kickers = [];                // { s0, s1, foot, lip, landEnd, h, grade, landGrade, fn }
  const wKeys = [];                  // { s0, s1, w0, w1 }
  const cps = [];
  let heightFn = null;

  function addSeg(len, k0, k1, b0, b1) {
    if (!(len > 1e-6)) return;
    heightFn = null;
    const steps = Math.max(1, Math.ceil(len / DS));
    const ds = len / steps;
    for (let i = 0; i < steps; i++) {
      const ka = k0 + ((k1 - k0) * i) / steps, kb = k0 + ((k1 - k0) * (i + 1)) / steps;
      const dyaw = ((ka + kb) / 2) * ds;
      const ym = st.yaw + dyaw / 2;
      st.x += Math.sin(ym) * ds;
      st.z += Math.cos(ym) * ds;
      st.yaw += dyaw;
      st.s += ds;
      P.s.push(st.s); P.x.push(st.x); P.z.push(st.z); P.yaw.push(st.yaw);
      P.k.push((ka + kb) / 2); P.b.push(b0 + ((b1 - b0) * (i + 1)) / steps);
    }
  }

  function key(h, flat = false) {
    heightFn = null;
    const last = hKeys[hKeys.length - 1];
    if (Math.abs(last.s - st.s) < 1e-6) { last.h = h; last.flat = last.flat || flat; } else hKeys.push({ s: st.s, h, flat });
    st.y = h;
  }

  function after(o) {
    if (o && o.y !== undefined) key(o.y);
    if (o && o.w !== undefined) api.width(o.w, o.wLen ?? 40);
    return api;
  }

  function turn(dir, deg, r, o = {}, y1) {
    if (typeof o === 'number') o = { bank: o, y: y1 };
    o = o ?? {};
    const rad = deg * DEG;
    const k = dir / r;
    let lt = o.lt ?? clamp(0.8 * r, 8, 50);
    lt = Math.min(lt, r * rad);
    const bank = o.bank ?? 0;
    addSeg(lt, 0, k, 0, bank);
    addSeg(r * rad - lt, k, k, bank, bank);
    addSeg(lt, k, 0, bank, 0);
    return after(o);
  }

  const api = {
    state: st,
    /** Straight of `len` metres. o = { y, w } (or a number = end height, v1 style). */
    S(len, o) {
      if (typeof o === 'number') o = { y: o };
      addSeg(len, 0, 0, 0, 0);
      return after(o);
    },
    /** Left turn: `deg` degrees, tightest radius r. o = { bank, y, lt, w }. */
    L(deg, r, o, y1) { return turn(1, deg, r, o, y1); },
    /** Right turn. */
    R(deg, r, o, y1) { return turn(-1, deg, r, o, y1); },
    /** S-bend left then right (each `deg`), with `gap` m of straight between. */
    SL(deg, r, o = {}, gap = 0) {
      turn(1, deg, r, { ...o, y: undefined, w: undefined });
      if (gap) addSeg(gap, 0, 0, 0, 0);
      return turn(-1, deg, r, o);
    },
    /** S-bend right then left. */
    SR(deg, r, o = {}, gap = 0) {
      turn(-1, deg, r, { ...o, y: undefined, w: undefined });
      if (gap) addSeg(gap, 0, 0, 0, 0);
      return turn(1, deg, r, o);
    },
    /** 180° switchback, dir 'L' or 'R'. */
    hairpin(dir, r, o = {}) { return turn(dir === 'L' ? 1 : -1, 180, r, o); },
    /** Height keyframe at the current position (no argument: hold the current height up to here). */
    y(h = st.y) { key(h); return api; },
    /** Straight whose height changes smoothly from the current height to y1 (flat before and after). */
    climb(len, y1, o = {}) {
      key(st.y);
      addSeg(len, 0, 0, 0, 0);
      key(y1);
      return after({ ...o, y: undefined });
    },
    /** Straight with a smooth crest (dh > 0) or dip (dh < 0) in the middle; o.y = end height. */
    hill(len, dh, o = {}) {
      const y0 = st.y;
      key(y0);
      addSeg(len / 2, 0, 0, 0, 0); key(y0 + dh);
      addSeg(len / 2, 0, 0, 0, 0); key(o.y ?? y0);
      return api;
    },
    /** Kicker jump on a straight (see the header). */
    kicker({ h = 5, ramp = 26, land = 45, run = 125, lead = 20, drop = 0 } = {}) {
      const y0 = st.y;
      key(y0, true);
      const s0 = st.s;
      const T1 = 10, T2 = 14;                           // curved foot of the ramp / bottom of the landing
      ramp = Math.max(ramp, h / 0.22 + T1 / 2);         // ramp grade <= 22 %
      land = Math.max(land, (h + drop) / 0.13 + T2 / 2); // landing slope <= 13 %
      run = Math.max(run, 170 - land);                  // >= 170 m of straight after the lip
      const g = h / (ramp - T1 / 2);                    // ramp grade
      const gd = (h + drop) / (land - T2 / 2);          // landing grade
      const foot = s0 + lead, lip = foot + ramp, landEnd = lip + land, s1 = landEnd + run;
      const fn = (s) => {
        if (s <= foot) return y0;
        if (s <= foot + T1) { const x = s - foot; return y0 + (g * x * x) / (2 * T1); }
        if (s <= lip) return y0 + (g * T1) / 2 + g * (s - foot - T1);
        if (s <= landEnd - T2) return y0 + h - gd * (s - lip);
        if (s <= landEnd) { const x = landEnd - s; return y0 - drop + (gd * x * x) / (2 * T2); }
        return y0 - drop;
      };
      addSeg(s1 - s0, 0, 0, 0, 0);
      kickers.push({ s0, s1, foot, lip, landEnd, h, grade: g, landGrade: gd, fn });
      key(y0 - drop, true);
      return api;
    },
    /** Change the road width to w metres over the next len metres. */
    width(w, len = 40) {
      wKeys.push({ s0: st.s, s1: st.s + len, w0: st.width, w1: w });
      st.width = w;
      return api;
    },
    /** Checkpoint at the current position. */
    cp() { cps.push(st.s); return api; },
    /** Height of the designed profile at distance s. */
    heightAt: (s) => getHeight(false)(s),
    /** The dense path so far: {s, x, z, yaw} arrays every ~0.25 m (for sketches). */
    path: () => ({ s: P.s, x: P.x, z: P.z, yaw: P.yaw }),

    finish({ closed = true, cpSpacing = 400, startAt = 6, runOff = 12 } = {}) {
      const L = st.s;
      const closure = Math.hypot(st.x - start.x, st.z - start.z);
      const lastKey = hKeys[hKeys.length - 1];
      if (closed && Math.abs(lastKey.s - L) < 1e-6 && Math.abs(lastKey.h - hKeys[0].h) > 0.01) {
        throw new Error(`turtle: a circuit must end at its start height (${hKeys[0].h} m), the last height key is ${lastKey.h} m`);
      }
      if (closed && Math.abs(st.width - start.width) > 0.01) {
        throw new Error(`turtle: a circuit must end with its start width (${start.width} m), not ${st.width} m`);
      }
      const H = getHeight(closed);
      let cpS = cps.slice();
      if (!cpS.length) cpS = autoCheckpoints(L, closed, cpSpacing, startAt, runOff);

      // control points: a graded mesh. Every metre gets a largest allowed
      // spacing (fine in tight turns and where height, width or banking bend,
      // up to 40 m on plain straights), smoothed so neighbouring pieces differ
      // by at most ~25 % (the spline stays accurate). Only kicker lips are
      // fixed points; checkpoints snap to the nearest point.
      const M = Math.ceil(L) + 1;
      const hs = new Float64Array(M);
      const bend = (fn, s, tol) => {
        const d2 = Math.abs(fn(Math.min(L, s + 2)) - 2 * fn(s) + fn(Math.max(0, s - 2))) / 4;
        return d2 > 1e-9 ? Math.sqrt((8 * tol) / d2) : Infinity;
      };
      for (let j = 0; j < M; j++) {
        const sj = Math.min(j, L);
        const k = Math.abs(curvAt(sj));
        let h = k > 1e-6 ? Math.min(8, 0.15 / k) : 40;
        h = Math.min(h, bend(H, sj, 0.03), bend(widthAt, sj, 0.05), bend(bankAt, sj, 0.3));
        hs[j] = Math.max(1, h);
      }
      for (let j = 1; j < M; j++) hs[j] = Math.min(hs[j], hs[j - 1] + 0.25);
      for (let j = M - 2; j >= 0; j--) hs[j] = Math.min(hs[j], hs[j + 1] + 0.25);
      const hAt = (x) => hs[Math.max(0, Math.min(M - 1, Math.round(x)))];
      const hard = [];
      for (const k of kickers) hard.push(k.foot, k.lip - 1, k.lip, k.lip + 1, k.landEnd);
      const must = [0, ...[...new Set(hard.map(round3))].filter((b) => b > 0.01 && b < L - 0.01).sort((a, b) => a - b), L];
      const sList = [];
      for (let m = 0; m < must.length - 1; m++) {
        const a = must[m], b = must[m + 1];
        let p = a;
        sList.push(a);
        for (;;) {
          let step = hAt(p);
          for (let x = p; x < p + step; x += 1) step = Math.min(step, hAt(x) + (x - p) * 0.25);
          const rest = b - p;
          if (rest <= step * 1.05) break;
          if (rest <= step * 2) { p += rest / 2; sList.push(p); break; }
          p += step;
          sList.push(p);
        }
      }
      if (!closed) sList.push(L);
      const points = sList.map((s) => {
        const [x, z] = posAt(s);
        return [r2(x), r2(z), r2(H(s)), r1(bankAt(s)), r1(widthAt(s))];
      });
      const checkpoints = cpS.map((c) => {
        let best = 0, bd = Infinity;
        sList.forEach((s, i) => { const d = Math.abs(s - c); if (d < bd) { bd = d; best = i; } });
        return best;
      }).sort((a, b) => a - b);
      return {
        points, checkpoints, length: L, closure, state: { ...st },
        kickers: kickers.map(({ fn, ...k }) => k),
        cpDistances: cpS,
        profile: H, // designed height at distance s
      };
    },
  };

  // ---- profile evaluation ----------------------------------------------------
  function getHeight(closed) {
    if (heightFn && heightFn.closed === closed) return heightFn;
    const keys = hKeys.slice();
    if (closed && keys.length > 1 && Math.abs(keys[keys.length - 1].s - st.s) < 1e-6) keys.pop();
    const base = pchipKeys(keys, closed, st.s);
    heightFn = (s) => {
      for (const k of kickers) if (s >= k.s0 && s <= k.s1) return k.fn(s);
      return base(s);
    };
    heightFn.closed = closed;
    return heightFn;
  }

  function idxAt(s) {
    let lo = 0, hi = P.s.length - 1;
    if (s <= 0) return [0, 0];
    if (s >= P.s[hi]) return [hi - 1, 1];
    while (hi - lo > 1) { const m = (lo + hi) >> 1; if (P.s[m] <= s) lo = m; else hi = m; }
    return [lo, (s - P.s[lo]) / (P.s[lo + 1] - P.s[lo])];
  }
  function posAt(s) {
    const [i, f] = idxAt(s);
    const j = Math.min(i + 1, P.s.length - 1);
    return [P.x[i] + (P.x[j] - P.x[i]) * f, P.z[i] + (P.z[j] - P.z[i]) * f, P.yaw[i] + (P.yaw[j] - P.yaw[i]) * f];
  }
  function curvAt(s) { const [i] = idxAt(s); return P.k[Math.min(i + 1, P.k.length - 1)]; }
  function bankAt(s) { const [i, f] = idxAt(s); const j = Math.min(i + 1, P.s.length - 1); return P.b[i] + (P.b[j] - P.b[i]) * f; }
  function widthAt(s) {
    let w = start.width;
    for (const k of wKeys) {
      if (s >= k.s1) w = k.w1;
      else if (s > k.s0) { w = k.w0 + (k.w1 - k.w0) * smoothstep((s - k.s0) / (k.s1 - k.s0)); break; }
      else break;
    }
    return w;
  }

  function autoCheckpoints(L, closed, spacing, startAt, runOff) {
    const s0 = closed ? 0 : startAt, s1 = closed ? L : L - runOff;
    const bad = (s) => kickers.some((k) => s > k.foot - 30 && s < k.s1 + 10);
    const first = Math.max(2, Math.round((s1 - s0) / spacing));
    // evenly spaced targets, each moved to the nearest good spot (not on a
    // jump, preferably not in a tight turn); add a gate if a gap gets too long
    for (let gaps = first; gaps <= first + 3; gaps++) {
      const step = (s1 - s0) / gaps;
      const out = [];
      for (let g = 1; g < gaps; g++) {
        const target = s0 + g * step;
        let best = null, bc = Infinity;
        for (let d = -150; d <= 150; d += 1) {
          const s = target + d;
          if (s <= s0 + 200 || s >= s1 - 200 || bad(s)) continue;
          const cost = Math.abs(d) + (Math.abs(curvAt(s)) > 1 / 80 ? 25 : 0);
          if (cost < bc) { bc = cost; best = s; }
        }
        if (best !== null) out.push(best);
      }
      const all = [s0, ...out, s1];
      if (out.length === gaps - 1 && all.slice(1).every((v, k) => v - all[k] >= 260 && v - all[k] <= 490)) return out;
    }
    throw new Error('turtle: could not place checkpoints 260-490 m apart off the jumps');
  }

  return api;
}

/** Monotone cubic through height keyframes {s, h, flat}; flat keys get a zero slope. */
function pchipKeys(keys, closed, L) {
  const n = keys.length;
  if (n === 1) return () => keys[0].h;
  const X = (k) => (closed ? keys[((k % n) + n) % n].s + Math.floor(k / n) * L : keys[clamp(k, 0, n - 1)].s);
  const Y = (k) => (closed ? keys[((k % n) + n) % n].h : keys[clamp(k, 0, n - 1)].h);
  const sec = (k) => { const h = X(k + 1) - X(k); return h > 1e-9 ? (Y(k + 1) - Y(k)) / h : 0; };
  const m = keys.map((key, k) => {
    if (key.flat) return 0;
    if (!closed && (k === 0 || k === n - 1)) return 0;
    const d0 = sec(k - 1), d1 = sec(k);
    if (d0 * d1 <= 0) return 0;
    const h0 = X(k) - X(k - 1), h1 = X(k + 1) - X(k);
    const w1 = 2 * h1 + h0, w2 = h1 + 2 * h0;
    return (w1 + w2) / (w1 / d0 + w2 / d1);
  });
  return (s) => {
    let k;
    if (closed) {
      s = ((s % L) + L) % L;
      k = n - 1;
      for (let j = 1; j < n; j++) if (keys[j].s > s) { k = j - 1; break; }
    } else {
      if (s <= keys[0].s) return keys[0].h;
      if (s >= keys[n - 1].s) return keys[n - 1].h;
      k = 0;
      while (k < n - 2 && s >= keys[k + 1].s) k++;
    }
    const x0 = X(k), h = X(k + 1) - x0;
    if (h <= 1e-9) return Y(k);
    const t = clamp((s - x0) / h, 0, 1), t2 = t * t, t3 = t2 * t;
    return (2 * t3 - 3 * t2 + 1) * Y(k) + (t3 - 2 * t2 + t) * h * m[k % n] + (-2 * t3 + 3 * t2) * Y(k + 1) + (t3 - t2) * h * m[(k + 1) % n];
  };
}

const r1 = (v) => Math.round(v * 10) / 10;
const r2 = (v) => Math.round(v * 100) / 100;
const round3 = (v) => Math.round(v * 1000) / 1000;

/**
 * Close a circuit. make(a, b) runs a turtle program in which a and b are the
 * lengths of two straights that point in different directions; closeLoop
 * finds a and b so the turtle ends exactly where it started (the turns must
 * add up to ±360°). Throws if that needs a < minA or b < minB.
 * Returns { t, a, b, error } with the final (unfinished) turtle.
 */
export function closeLoop(make, { a0 = 100, b0 = 100, minA = 0, minB = 0 } = {}) {
  const end = (a, b) => {
    const t = make(a, b), P = t.path();
    return [t.state.x - P.x[0], t.state.z - P.z[0], t.state.yaw - P.yaw[0], t];
  };
  const [x0, z0] = end(a0, b0);
  const [xa, za] = end(a0 + 10, b0);
  const [xb, zb] = end(a0, b0 + 10);
  const ja = [(xa - x0) / 10, (za - z0) / 10], jb = [(xb - x0) / 10, (zb - z0) / 10];
  const det = ja[0] * jb[1] - ja[1] * jb[0];
  if (Math.abs(det) < 1e-6) throw new Error('closeLoop: the two straights are parallel');
  const da = (-x0 * jb[1] + z0 * jb[0]) / det;
  const db = (-z0 * ja[0] + x0 * ja[1]) / det;
  const a = a0 + da, b = b0 + db;
  const [xf, zf, yawf, t] = end(a, b);
  const turns = yawf / (2 * Math.PI);
  if (Math.abs(Math.abs(turns) - 1) > 1e-6) throw new Error(`closeLoop: the turns add up to ${(turns * 360).toFixed(2)}°, not ±360°`);
  if (a < minA || b < minB) throw new Error(`closeLoop: straights would be ${a.toFixed(1)} m and ${b.toFixed(1)} m (minimum ${minA} / ${minB})`);
  return { t, a, b, error: Math.hypot(xf, zf) };
}
