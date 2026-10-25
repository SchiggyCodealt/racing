/**
 * collision.js
 * ------------------------------------------------------------------
 * Fast 2D queries against a built track:
 *   - locate():        where a point is relative to the centre line
 *                      (segment index, lateral offset, ground height, ...)
 *   - buildWallGrid(): wall segments bucketed in a uniform grid
 *   - raycast():       distance to the nearest wall along a ray
 *                      (used by the AI distance sensors)
 *   - collideCapsule(): car-shaped capsule against the wall segments
 *                      (used by the car physics)
 *
 * The world is treated as 2.5D: walls are vertical, so all wall tests
 * happen on the X/Z plane and height comes from the road surface.
 *
 * Coordinate conventions used across the project:
 *   forward(yaw) = (sin yaw, cos yaw)   on the (x, z) plane
 *   left(yaw)    = (cos yaw, -sin yaw)
 *   A positive yaw change is a turn to the LEFT.
 *
 * v2: locate() uses a *smooth* track frame. Between two samples i and j
 * the centre point and the left normal are both interpolated linearly
 * (C(t) = lerp(p_i, p_j, t), N(t) = lerp(n_i, n_j, t)) and a point P is
 * mapped to (t, lat) with P = C(t) + lat * N(t). Unlike v1 (perpendicular
 * distance to the nearest straight segment) this is continuous across
 * segment boundaries, so `lat`, the ground height on banked corners and
 * the progress no longer jump by up to ~15 cm on the outside of tight
 * corners (one of the causes of "glitchy corners" in v1). At lat = ±hw
 * the mapping traces exactly the wall polylines built below.
 */

/** How many segments either side of the hint locate() searches. */
const SEARCH_WINDOW = 8;
/** cos of the normal change across one segment above which the segment counts as a kink. */
const KINK_DOT = 0.5;

/**
 * Locate a point on the track, searching around a hint segment index.
 * Searching locally (instead of the whole track) keeps it fast and stops
 * the car from "snapping" to a different part of the track that happens
 * to be close by in 2D.
 *
 * @param {object} track  built track (see trackBuilder.js)
 * @param {number} x
 * @param {number} z
 * @param {number} hint   segment index near the point (e.g. last frame's)
 * @param {object} out    result object, filled in place:
 *   idx      segment index (from sample idx to idx+1)
 *   t        0..1 position along that segment
 *   tRaw     unclamped t (open tracks: <0 before start, >1 past the end)
 *   prog     idx + t, "local progress" in sample units
 *   lat      signed lateral offset from the centre line (+ = left)
 *   nx, nz   unit left normal of the track at the point (smooth)
 *   groundY  road surface height at the point (includes banking)
 *   bank     signed bank angle in radians at the point
 *   hw       road half-width at the point
 */
export function locate(track, x, z, hint, out) {
  // Coarse: nearest straight segment in a window around the hint.
  const { N, closed, px, pz } = track;
  const segCount = track.segCount;
  let best = Infinity;
  let bi = 0;
  hint = hint | 0;
  for (let k = -SEARCH_WINDOW; k <= SEARCH_WINDOW; k++) {
    let i = hint + k;
    if (closed) i = ((i % N) + N) % N;
    else if (i < 0 || i >= segCount) continue;
    const j = closed ? (i + 1) % N : i + 1;
    const ax = px[i];
    const az = pz[i];
    const ex = px[j] - ax;
    const ez = pz[j] - az;
    let t = ((x - ax) * ex + (z - az) * ez) / (ex * ex + ez * ez);
    t = t < 0 ? 0 : t > 1 ? 1 : t;
    const qx = ax + ex * t - x;
    const qz = az + ez * t - z;
    const d2 = qx * qx + qz * qz;
    if (d2 < best) {
      best = d2;
      bi = i;
    }
  }
  // Fine: smooth projection, walking to the neighbour segment if needed.
  return locateNear(track, x, z, bi, out);
}

/**
 * Smooth projection starting at segment `i`, walking forwards/backwards
 * (at most a few segments) until the point projects inside a segment.
 * O(1) when `i` is already right (the car physics calls this every
 * sub-step with last sub-step's segment). Fills `out` like locate().
 */
export function locateNear(track, x, z, i, out) {
  const { N, closed, px, pz, nx, nz } = track;
  const segCount = track.segCount;
  if (closed) i = ((i % N) + N) % N;
  else i = i < 0 ? 0 : i >= segCount ? segCount - 1 : i;

  let t = 0, dir = 0;
  for (let iter = 0; iter < 8; iter++) {
    t = smoothT(track, x, z, i);
    if (t < 0) {
      if (!closed && i === 0) break;
      if (dir === 1) { t = 0; break; } // ping-pong between two segments: on the boundary
      dir = -1;
      i = closed ? (i - 1 + N) % N : i - 1;
    } else if (t > 1) {
      if (!closed && i === segCount - 1) break;
      if (dir === -1) { t = 1; break; }
      dir = 1;
      i = closed ? (i + 1) % N : i + 1;
    } else break;
  }

  const j = closed ? (i + 1) % N : i + 1;
  const tRaw = t;
  const tc = t < 0 ? 0 : t > 1 ? 1 : t;
  // For points beyond the ends of an open track, extrapolate along the end segment.
  const te = closed ? tc : tRaw;
  const cx = px[i] + (px[j] - px[i]) * te;
  const cz = pz[i] + (pz[j] - pz[i]) * te;
  let mx = nx[i] + (nx[j] - nx[i]) * tc;
  let mz = nz[i] + (nz[j] - nz[i]) * tc;
  if (nx[i] * nx[j] + nz[i] * nz[j] < KINK_DOT) {
    // kink: use the segment's own left normal (see smoothT)
    const ex = px[j] - px[i], ez = pz[j] - pz[i];
    const el = Math.sqrt(ex * ex + ez * ez) || 1;
    mx = ez / el; mz = -ex / el;
  }
  const m2 = mx * mx + mz * mz;
  const lat = ((x - cx) * mx + (z - cz) * mz) / m2;
  const inv = 1 / Math.sqrt(m2);
  const bank = track.bank[i] + (track.bank[j] - track.bank[i]) * tc;
  const cy = track.py[i] + (track.py[j] - track.py[i]) * tc;

  out.idx = i;
  out.t = tc;
  out.tRaw = tRaw;
  out.prog = i + tc;
  out.lat = lat;
  out.nx = mx * inv;
  out.nz = mz * inv;
  out.bank = bank;
  out.hw = track.hw[i] + (track.hw[j] - track.hw[i]) * tc;
  // Positive bank (left-hand turn) raises the right edge (negative lat).
  out.groundY = cy - lat * Math.tan(bank);
  return out;
}

/**
 * Parameter t of the smooth projection of (x, z) on segment i:
 * solves (P - C(t)) · T(t) = 0 with T(t) = perp(N(t)), a quadratic in t.
 */
function smoothT(track, x, z, i) {
  const { px, pz, nx, nz } = track;
  const j = track.closed ? (i + 1) % track.N : i + 1;
  const wx = x - px[i], wz = z - pz[i];
  const ex = px[j] - px[i], ez = pz[j] - pz[i];
  // A kink (the normal turns by more than 60° within one segment) would make the
  // smooth frame singular: fall back to a plain projection on the segment there.
  if (nx[i] * nx[j] + nz[i] * nz[j] < KINK_DOT) return (wx * ex + wz * ez) / (ex * ex + ez * ez || 1e-9);
  // tangent = perp(normal): normal (nx, nz) -> tangent (-nz, nx)
  const tix = -nz[i], tiz = nx[i];
  const dtx = -nz[j] - tix, dtz = nx[j] - tiz;
  const a2 = -(ex * dtx + ez * dtz);
  const a1 = wx * dtx + wz * dtz - (ex * tix + ez * tiz);
  const a0 = wx * tix + wz * tiz;
  if (Math.abs(a2) < 1e-9 * Math.abs(a1)) return -a0 / a1;
  const disc = a1 * a1 - 4 * a2 * a0;
  if (disc < 0) return -a0 / a1;
  const q = -0.5 * (a1 + (a1 < 0 ? -1 : 1) * Math.sqrt(disc));
  return a0 / q; // the root that matches the linear solution when the normals are parallel
}

/**
 * Build the wall segments and a uniform grid that buckets them,
 * so ray casts and car collisions only test walls in nearby cells.
 *
 * Returned fields: segs (Float32Array, 4 numbers per segment: ax, az, bx, bz),
 * inward (Float64Array, 2 per segment: unit normal pointing into the road),
 * cell, minX, minZ, cols, rows, cells (Int32Array of segment ids per cell),
 * and the same data in flat, faster forms used by the queries: segD
 * (Float64Array, 4 per segment: ax, az, bx - ax, bz - az), cellStart /
 * cellSegs (segment ids of cell c are cellSegs[cellStart[c] .. cellStart[c+1]]),
 * stamp (scratch for de-duplication).
 */
export function buildWallGrid(track) {
  const { count, closed, px, pz, nx, nz, hw } = track;
  const segs = [];
  const inward = [];
  const edge = (i, side) => [px[i] + nx[i] * hw[i] * side, pz[i] + nz[i] * hw[i] * side];

  const last = closed ? count : count - 1;
  for (let i = 0; i < last; i++) {
    const j = (i + 1) % count;
    for (const side of [1, -1]) {
      const a = edge(i, side);
      const b = edge(j, side);
      segs.push(a[0], a[1], b[0], b[1]);
      // The road is on the right of the left wall (side +1) and on the left of the right wall.
      let dx = b[0] - a[0], dz = b[1] - a[1];
      const l = Math.hypot(dx, dz) || 1;
      dx /= l; dz /= l;
      // left normal of the direction (dx, dz) is (dz, -dx)
      inward.push(-side * dz, side * dx);
    }
  }
  if (!closed) {
    // End caps so the sprint track is fully enclosed.
    for (const i of [0, count - 1]) {
      const a = edge(i, 1);
      const b = edge(i, -1);
      segs.push(a[0], a[1], b[0], b[1]);
      const s = i === 0 ? 1 : -1; // inward = along the track at the start, backwards at the end
      inward.push(track.tx[i] * s, track.tz[i] * s);
    }
  }

  const segArr = new Float32Array(segs);
  let minX = Infinity, minZ = Infinity, maxX = -Infinity, maxZ = -Infinity;
  for (let k = 0; k < segArr.length; k += 2) {
    minX = Math.min(minX, segArr[k]);
    maxX = Math.max(maxX, segArr[k]);
    minZ = Math.min(minZ, segArr[k + 1]);
    maxZ = Math.max(maxZ, segArr[k + 1]);
  }
  const cell = 12;
  minX -= cell; minZ -= cell; maxX += cell; maxZ += cell;
  const cols = Math.ceil((maxX - minX) / cell);
  const rows = Math.ceil((maxZ - minZ) / cell);
  const buckets = Array.from({ length: cols * rows }, () => []);

  for (let s = 0; s < segArr.length / 4; s++) {
    const o = s * 4;
    const c0 = Math.floor((Math.min(segArr[o], segArr[o + 2]) - minX) / cell);
    const c1 = Math.floor((Math.max(segArr[o], segArr[o + 2]) - minX) / cell);
    const r0 = Math.floor((Math.min(segArr[o + 1], segArr[o + 3]) - minZ) / cell);
    const r1 = Math.floor((Math.max(segArr[o + 1], segArr[o + 3]) - minZ) / cell);
    for (let r = r0; r <= r1; r++) for (let c = c0; c <= c1; c++) buckets[r * cols + c].push(s);
  }

  const nSeg = segArr.length / 4;
  const segD = new Float64Array(nSeg * 4);
  for (let k = 0; k < nSeg; k++) {
    const o = k * 4;
    segD[o] = segArr[o];
    segD[o + 1] = segArr[o + 1];
    segD[o + 2] = segArr[o + 2] - segArr[o];
    segD[o + 3] = segArr[o + 3] - segArr[o + 1];
  }
  const cellStart = new Int32Array(buckets.length + 1);
  let total = 0;
  for (let c = 0; c < buckets.length; c++) { cellStart[c] = total; total += buckets[c].length; }
  cellStart[buckets.length] = total;
  const cellSegs = new Int32Array(total);
  for (let c = 0; c < buckets.length; c++) cellSegs.set(buckets[c], cellStart[c]);

  return {
    segs: segArr,
    inward: new Float64Array(inward),
    cell, minX, minZ, cols, rows,
    cells: buckets.map((b) => Int32Array.from(b)),
    segD, cellStart, cellSegs,
    stamp: new Uint32Array(nSeg),
    stampId: 0,
  };
}

/**
 * Cast a 2D ray against the track walls (grid DDA traversal).
 * @returns distance to the first wall hit, or maxDist if nothing is hit.
 */
export function raycast(grid, ox, oz, dx, dz, maxDist) {
  const { cell, minX, minZ, cols, rows, segD, cellStart, cellSegs } = grid;
  let cx = Math.floor((ox - minX) / cell);
  let cz = Math.floor((oz - minZ) / cell);
  const stepX = dx > 0 ? 1 : -1;
  const stepZ = dz > 0 ? 1 : -1;
  const tDeltaX = dx !== 0 ? cell / Math.abs(dx) : Infinity;
  const tDeltaZ = dz !== 0 ? cell / Math.abs(dz) : Infinity;
  let tMaxX = dx !== 0 ? ((cx + (dx > 0 ? 1 : 0)) * cell + minX - ox) / dx : Infinity;
  let tMaxZ = dz !== 0 ? ((cz + (dz > 0 ? 1 : 0)) * cell + minZ - oz) / dz : Infinity;
  let best = maxDist;

  while (cx >= 0 && cz >= 0 && cx < cols && cz < rows) {
    const ci = cz * cols + cx;
    const end = cellStart[ci + 1];
    for (let k = cellStart[ci]; k < end; k++) {
      const o = cellSegs[k] << 2;
      const ex = segD[o + 2], ez = segD[o + 3];
      const denom = dx * ez - dz * ex;
      if (denom > -1e-9 && denom < 1e-9) continue;
      const wx = segD[o] - ox, wz = segD[o + 1] - oz;
      const t = (wx * ez - wz * ex) / denom;
      if (t < 0 || t >= best) continue;
      const s = (wx * dz - wz * dx) / denom;
      if (s >= 0 && s <= 1) best = t;
    }
    const tNext = tMaxX < tMaxZ ? tMaxX : tMaxZ;
    if (best <= tNext || tNext > maxDist) break;
    if (tMaxX < tMaxZ) { cx += stepX; tMaxX += tDeltaX; }
    else { cz += stepZ; tMaxZ += tDeltaZ; }
  }
  return best;
}

/**
 * Deepest contact between a capsule (core segment P0-P1, radius R) and the
 * walls. Only walls whose grid cells overlap the capsule are tested.
 *
 * One-sided walls: each wall segment knows which side the road is on
 * (grid.inward). If the capsule's core has crossed a wall line (it can't
 * at the speeds and sub-steps the car uses, but this keeps it tunnel-proof
 * anyway) it is pushed back to the road side, not through. Cores more than
 * `maxBehind` metres behind a wall are ignored, so a wall of another part
 * of the track that runs back-to-back with this one is never "hit" from
 * behind.
 *
 * @param out  filled with {depth, nx, nz (unit, from wall into the road),
 *             px, pz (contact point on the capsule surface), seg}
 * @returns true if there is a contact (depth > 0)
 */
export function collideCapsule(grid, p0x, p0z, p1x, p1z, R, out, maxBehind = 1.6) {
  const { cell, minX, minZ, cols, rows, segD, cellStart, cellSegs, inward } = grid;
  const stamp = grid.stamp;
  let sid = (grid.stampId = (grid.stampId + 1) >>> 0);
  if (sid === 0) { stamp.fill(0); sid = grid.stampId = 1; }
  const x0 = Math.min(p0x, p1x) - R, x1 = Math.max(p0x, p1x) + R;
  const z0 = Math.min(p0z, p1z) - R, z1 = Math.max(p0z, p1z) + R;
  const c0 = Math.max(0, Math.floor((x0 - minX) / cell)), c1 = Math.min(cols - 1, Math.floor((x1 - minX) / cell));
  const r0 = Math.max(0, Math.floor((z0 - minZ) / cell)), r1 = Math.min(rows - 1, Math.floor((z1 - minZ) / cell));
  let bestDepth = 0;
  let found = false;
  const ux = p1x - p0x, uz = p1z - p0z;
  const uu = ux * ux + uz * uz || 1e-9;

  for (let r = r0; r <= r1; r++) {
    for (let c = c0; c <= c1; c++) {
      const ci = r * cols + c;
      const end = cellStart[ci + 1];
      for (let k = cellStart[ci]; k < end; k++) {
        const s = cellSegs[k];
        if (stamp[s] === sid) continue;
        stamp[s] = sid;
        const o = s * 4;
        const ax = segD[o], az = segD[o + 1], ex = segD[o + 2], ez = segD[o + 3];
        const bx = ax + ex, bz = az + ez;
        // quick reject: segment bounding box vs capsule bounding box
        if ((ax < x0 && bx < x0) || (ax > x1 && bx > x1) || (az < z0 && bz < z0) || (az > z1 && bz > z1)) continue;
        const mx = inward[s * 2], mz = inward[s * 2 + 1];
        const ee = ex * ex + ez * ez || 1e-9;
        // signed distances of the core ends to the wall line (+ = road side)
        const s0 = (p0x - ax) * mx + (p0z - az) * mz;
        const s1 = (p1x - ax) * mx + (p1z - az) * mz;
        let depth, nX, nZ, cpx, cpz;
        const minS = s0 < s1 ? s0 : s1;
        if (minS < 0) {
          // Some of the core is behind the wall line: inside the wall's span?
          if (minS < -maxBehind) continue;
          const qx = s0 < s1 ? p0x : p1x, qz = s0 < s1 ? p0z : p1z;
          // where along the wall does the crossing (or the deepest end) sit?
          let tc;
          if (s0 * s1 < 0) {
            const f = s0 / (s0 - s1);
            tc = ((p0x + ux * f - ax) * ex + (p0z + uz * f - az) * ez) / ee;
          } else tc = ((qx - ax) * ex + (qz - az) * ez) / ee;
          if (tc < 0 || tc > 1) {
            // beyond the wall's ends: treat as an ordinary distance test below
          } else {
            depth = R - minS;
            nX = mx; nZ = mz;
            cpx = qx - mx * R; cpz = qz - mz * R;
            if (depth > bestDepth) {
              bestDepth = depth; found = true;
              out.depth = depth; out.nx = nX; out.nz = nZ; out.px = cpx; out.pz = cpz; out.seg = s;
            }
            continue;
          }
        }
        // Closest points between the two segments (they don't cross here):
        // the minimum is at an endpoint of one of them.
        let bd = Infinity, bcx = 0, bcz = 0, bwx = 0, bwz = 0;
        // core ends against the wall segment
        let t = ((p0x - ax) * ex + (p0z - az) * ez) / ee;
        t = t < 0 ? 0 : t > 1 ? 1 : t;
        let wx = ax + ex * t, wz = az + ez * t;
        let d = (p0x - wx) * (p0x - wx) + (p0z - wz) * (p0z - wz);
        if (d < bd) { bd = d; bcx = p0x; bcz = p0z; bwx = wx; bwz = wz; }
        t = ((p1x - ax) * ex + (p1z - az) * ez) / ee;
        t = t < 0 ? 0 : t > 1 ? 1 : t;
        wx = ax + ex * t; wz = az + ez * t;
        d = (p1x - wx) * (p1x - wx) + (p1z - wz) * (p1z - wz);
        if (d < bd) { bd = d; bcx = p1x; bcz = p1z; bwx = wx; bwz = wz; }
        // wall ends against the core
        t = ((ax - p0x) * ux + (az - p0z) * uz) / uu;
        t = t < 0 ? 0 : t > 1 ? 1 : t;
        let cx = p0x + ux * t, cz = p0z + uz * t;
        d = (cx - ax) * (cx - ax) + (cz - az) * (cz - az);
        if (d < bd) { bd = d; bcx = cx; bcz = cz; bwx = ax; bwz = az; }
        t = ((bx - p0x) * ux + (bz - p0z) * uz) / uu;
        t = t < 0 ? 0 : t > 1 ? 1 : t;
        cx = p0x + ux * t; cz = p0z + uz * t;
        d = (cx - bx) * (cx - bx) + (cz - bz) * (cz - bz);
        if (d < bd) { bd = d; bcx = cx; bcz = cz; bwx = bx; bwz = bz; }
        if (bd >= R * R) continue;
        const dist = Math.sqrt(bd);
        if (dist > 1e-6) {
          nX = (bcx - bwx) / dist; nZ = (bcz - bwz) / dist;
          // never push towards the back of the wall
          if (nX * mx + nZ * mz < 0) { nX = mx; nZ = mz; }
        } else { nX = mx; nZ = mz; }
        depth = R - dist;
        if (depth > bestDepth) {
          bestDepth = depth; found = true;
          out.depth = depth; out.nx = nX; out.nz = nZ; out.px = bcx - nX * R; out.pz = bcz - nZ * R; out.seg = s;
        }
      }
    }
  }
  if (!found) out.depth = 0;
  return found;
}
