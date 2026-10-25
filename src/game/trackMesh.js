/**
 * trackMesh.js
 * ------------------------------------------------------------------
 * Builds the visible 3D world of one built track:
 *
 *   - road: procedural asphalt (colour, roughness and normal maps) with
 *     rubbered racing line, painted edge/centre lines, start grid boxes
 *   - raised 3D curbs on corners, concrete barriers with coloured panels,
 *     embankments under raised road
 *   - checkpoint and start/finish gates with emissive light strips
 *   - trackside props: lamp posts, chevron boards, banners, a grandstand
 *   - a large terrain: flat under and around the road, gentle hills further
 *     out and a ring of mountains (or mesas) towards the horizon
 *   - themed, instanced scenery (trees, cacti, rocks, ...) never on the road
 *   - theme extras: glowing barrier stripes and a lit city skyline (night);
 *     the sea on one side of the track with a beach, a lighthouse and
 *     boats (seaside)
 *
 * Everything is merged or instanced to keep draw calls low. The look
 * follows track.def.theme (see THEMES in scene.js).
 */
import * as THREE from '../../vendor/three.module.min.js';
import { getTheme } from './scene.js';

const BARRIER_H = 1.1;   // barrier height (m)
const BARRIER_W = 0.66;  // barrier footprint beyond the road edge (m)
const ZONE = 12;         // the terrain stays under the road up to this far beyond the edge (m)

export function buildTrackMesh(track) {
  const t0 = performance.now();
  const theme = getTheme(track.def?.theme);
  const group = new THREE.Group();
  group.name = 'track';
  const disposables = [];
  const keep = (x) => (disposables.push(x), x);

  const ctx = analyseTrack(track, theme);
  const t1 = performance.now();
  ctx.terrain = buildTerrain(ctx, keep);
  group.add(ctx.terrain.mesh, ctx.terrain.farPlane);
  if (ctx.terrain.water) group.add(ctx.terrain.water);
  const t2 = performance.now();

  const lap = {};
  let tl = performance.now();
  const tick = (k) => { const n = performance.now(); lap[k] = Math.round(n - tl); tl = n; };
  group.add(buildRoad(ctx, keep)); tick('road');
  group.add(buildLines(ctx, keep)); tick('lines');
  const curbs = buildCurbs(ctx, keep);
  if (curbs) group.add(curbs);
  tick('curbs');
  group.add(buildBarriers(ctx, keep));
  if (theme.glow) group.add(buildGlowStripes(ctx, keep));
  tick('barriers');
  group.add(buildEmbankments(ctx, keep)); tick('embank');
  group.add(buildStartLines(ctx, keep));
  const gates = buildGates(ctx, keep); tick('gates');
  group.add(gates.group);
  const t3 = performance.now();
  addProps(ctx, group, keep);
  const t4 = performance.now();
  addScenery(ctx, group, keep);
  addSetPieces(ctx, group, keep);
  // Big meshes -> spatial chunks, so the camera and the small shadow frustum
  // only draw the parts near them. Short tracks stay whole.
  for (const child of [...group.children]) {
    if (!child.isMesh || child.isInstancedMesh) continue;
    let cell = 0, minTris = 0;
    if (child.name === 'terrain') {
      const bb = child.geometry.boundingBox ?? (child.geometry.computeBoundingBox(), child.geometry.boundingBox);
      cell = Math.max(bb.max.x - bb.min.x, bb.max.z - bb.min.z) / 3 + 1;
    } else if (CHUNKED.has(child.name)) {
      cell = 500;
      minTris = 30000;
    }
    if (!cell) continue;
    const parts = splitMesh(child, cell, keep, minTris);
    if (parts.length > 1) {
      group.remove(child);
      group.add(...parts);
    }
  }
  const t5 = performance.now();

  const stats = {
    buildMs: Math.round(t5 - t0),
    analyseMs: Math.round(t1 - t0),
    terrainMs: Math.round(t2 - t1),
    trackMs: Math.round(t3 - t2),
    propsMs: Math.round(t4 - t3),
    sceneryMs: Math.round(t5 - t4),
    terrainVerts: ctx.terrain.vertexCount,
    sceneryInstances: ctx.sceneryCount ?? 0,
    lap,
  };
  group.userData.stats = stats;

  return {
    group,
    stats,
    /** Colour a checkpoint gate: 'next' (cyan), 'passed' (green) or 'idle'. */
    setCheckpointState(k, state) {
      const g = gates.cp[k];
      if (!g) return;
      const s = GATE_STATE[state] ?? GATE_STATE.idle;
      g.color.setHex(s.color);
      g.emissive.setHex(s.color);
      g.emissiveIntensity = s.glow * (theme.lamps ? 1.25 : 1);
    },
    dispose() {
      for (const d of disposables) d.dispose();
    },
  };
}

// Only shadow casters gain from chunking: the main camera sees most of the
// track anyway (more draw calls for nothing), the 128 m shadow box does not.
const CHUNKED = new Set(['barriers']);

/**
 * Splits a mesh into a grid of spatial chunks that share its vertex buffers
 * (each chunk has its own index list and bounds). Returns [mesh] unchanged
 * when it is small or fits in one cell.
 */
function splitMesh(mesh, cell, keep, minTris = 0) {
  const g = mesh.geometry;
  if (!g.index || Array.isArray(mesh.material) || g.groups.length > 1) return [mesh];
  const idx = g.index.array, pos = g.attributes.position.array;
  const tris = idx.length / 3;
  if (tris < minTris) return [mesh];
  let minX = Infinity, minZ = Infinity, maxX = -Infinity, maxZ = -Infinity;
  for (let v = 0; v < pos.length; v += 3) {
    const x = pos[v], z = pos[v + 2];
    if (x < minX) minX = x; if (x > maxX) maxX = x;
    if (z < minZ) minZ = z; if (z > maxZ) maxZ = z;
  }
  const nx = Math.max(1, Math.ceil((maxX - minX) / cell)), nz = Math.max(1, Math.ceil((maxZ - minZ) / cell));
  if (nx * nz === 1) return [mesh];
  const cellOf = new Int32Array(tris), counts = new Int32Array(nx * nz);
  for (let t = 0; t < tris; t++) {
    const a = idx[3 * t] * 3, b = idx[3 * t + 1] * 3, c = idx[3 * t + 2] * 3;
    const cx = (pos[a] + pos[b] + pos[c]) / 3, cz = (pos[a + 2] + pos[b + 2] + pos[c + 2]) / 3;
    const ix = Math.min(nx - 1, Math.floor((cx - minX) / cell)), iz = Math.min(nz - 1, Math.floor((cz - minZ) / cell));
    const k = iz * nx + ix;
    cellOf[t] = k;
    counts[k]++;
  }
  const lists = [], fill = new Int32Array(nx * nz);
  for (let k = 0; k < nx * nz; k++) lists.push(counts[k] ? new idx.constructor(counts[k] * 3) : null);
  for (let t = 0; t < tris; t++) {
    const k = cellOf[t], o = fill[k];
    const L = lists[k];
    L[o] = idx[3 * t]; L[o + 1] = idx[3 * t + 1]; L[o + 2] = idx[3 * t + 2];
    fill[k] = o + 3;
  }
  const out = [];
  lists.forEach((L) => {
    if (!L) return;
    const geo = keep(new THREE.BufferGeometry());
    for (const name in g.attributes) geo.setAttribute(name, g.attributes[name]);
    geo.setIndex(new THREE.BufferAttribute(L, 1));
    const box = new THREE.Box3();
    for (let q = 0; q < L.length; q++) {
      const v = L[q] * 3;
      box.expandByPoint(_split.set(pos[v], pos[v + 1], pos[v + 2]));
    }
    geo.boundingBox = box;
    geo.boundingSphere = box.getBoundingSphere(new THREE.Sphere());
    const m = new THREE.Mesh(geo, mesh.material);
    m.name = mesh.name;
    m.castShadow = mesh.castShadow;
    m.receiveShadow = mesh.receiveShadow;
    m.renderOrder = mesh.renderOrder;
    m.frustumCulled = mesh.frustumCulled;
    out.push(m);
  });
  return out;
}
const _split = new THREE.Vector3();

const GATE_STATE = {
  next: { color: 0x19d3ff, glow: 3.2 },
  passed: { color: 0x2ee66a, glow: 2.2 },
  idle: { color: 0x56636f, glow: 0.25 },
  start: { color: 0xfff1c8, glow: 2.6 },
};

// =============================================================================
// Track analysis: per-sample helpers shared by all builders
// =============================================================================

function analyseTrack(track, theme) {
  const { count, closed, px, py, pz, tx, tz, hw, bank } = track;
  const segs = closed ? count : count - 1;
  const wrap = closed ? (i) => ((i % count) + count) % count : (i) => Math.max(0, Math.min(count - 1, i));
  const tanB = Float32Array.from(bank, Math.tan);
  const surfY = (i, lat) => py[i] - lat * tanB[i];
  const edgeY = (i, s) => py[i] - s * hw[i] * tanB[i];

  // Signed curvature (+ = left turn), 1/m.
  const heading = (i) => Math.atan2(tx[i], tz[i]);
  const kappa = new Float32Array(count);
  for (let i = 0; i < count; i++) {
    const a = wrap(i - 2), b = wrap(i + 2);
    const n = closed ? 4 : b - a;
    if (n <= 0) continue;
    let d = heading(b) - heading(a);
    d = Math.atan2(Math.sin(d), Math.cos(d));
    kappa[i] = d / (n * track.segLen);
  }

  // Lowest road edge and the terrain level next to the road. erode+blur with
  // the same radius guarantees G[i] <= low[i] (terrain never above the road).
  const low = new Float32Array(count);
  for (let i = 0; i < count; i++) low[i] = py[i] - hw[i] * Math.abs(tanB[i]);
  const G = blur(erode(low, 30, closed), 30, closed);
  for (let i = 0; i < count; i++) G[i] -= 0.35;

  // Corners get curbs: radius under ~150 m, short runs removed.
  const corner = new Uint8Array(count);
  for (let i = 0; i < count; i++) corner[i] = Math.abs(kappa[i]) > 1 / 150 ? 1 : 0;
  dilateMask(corner, 2, closed);
  removeShortRuns(corner, 6);

  let seed = 1234;
  for (const ch of String(track.id)) seed = (Math.imul(seed, 31) + ch.charCodeAt(0)) | 0;

  const ctx = {
    track, theme, segs, wrap, tanB, surfY, edgeY, kappa, G, corner, seed,
    P: (i, lat, dy = 0) => [track.px[i] + track.nx[i] * lat, surfY(i, lat) + dy, track.pz[i] + track.nz[i] * lat],
    gateSamples: [],
    pads: [],
  };
  ctx.gateSamples = closed ? [0, ...track.cpSamples] : [track.startLine ?? track.startIdx, track.finishIdx, ...track.cpSamples];
  ctx.nearGate = (i, r) => ctx.gateSamples.some((g) => {
    let d = Math.abs(g - i);
    if (closed) d = Math.min(d, count - d);
    return d <= r;
  });
  planGrandstand(ctx);
  if (theme.sea) planCoast(ctx);
  return ctx;
}

/** Find a free spot for the grandstand next to the start; reserves a flat pad. */
function planGrandstand(ctx) {
  const { track, G } = ctx;
  const { count, closed, px, pz, nx, nz, tx, tz, hw } = track;
  const anchor = closed ? 0 : Math.min(count - 1, track.startIdx + 12);
  const L = 40, D = 13, gap = 5;
  for (const s of [-1, 1]) {
    const off = s * (hw[anchor] + BARRIER_W + gap + D / 2);
    const cx = px[anchor] + nx[anchor] * off, cz = pz[anchor] + nz[anchor] * off;
    const ax = tx[anchor], az = tz[anchor];
    const ox = nx[anchor] * s, oz = nz[anchor] * s;
    let ok = true;
    for (let a = -1; a <= 1 && ok; a += 0.25) {
      for (let b = -1; b <= 1 && ok; b += 0.5) {
        const qx = cx + ax * a * (L / 2 + 4) + ox * b * (D / 2 + 2);
        const qz = cz + az * a * (L / 2 + 4) + oz * b * (D / 2 + 2);
        for (let j = 0; j < count; j += 1) {
          const dx = px[j] - qx, dz = pz[j] - qz;
          const r = hw[j] + 3.5;
          if (dx * dx + dz * dz < r * r) { ok = false; break; }
        }
      }
    }
    if (!ok) continue;
    const pts = [];
    for (let a = -L / 2; a <= L / 2; a += 5) pts.push([cx + ax * a, cz + az * a]);
    ctx.pads.push({ kind: 'grandstand', cx, cz, ax, az, ox, oz, L, D, y: G[anchor], r: D / 2 + 2, pts });
    return;
  }
}

/**
 * Seaside themes: put the sea on the side of the track that runs along it
 * most (one of 16 directions), with the shoreline following the outermost
 * parts of the track on that side, and reserve a pad for the lighthouse.
 * ctx.coast = {dx, dz (towards the sea), env(u) (outermost road edge across
 * the coast at u = position along it), off (shore distance beyond that),
 * plus the theme's sea colours and level}.
 */
function planCoast(ctx) {
  const { track, theme } = ctx;
  const { count, px, pz, hw } = track;
  let best = null;
  for (let k = 0; k < 16; k++) {
    const a = (k / 16) * Math.PI * 2, dx = Math.sin(a), dz = Math.cos(a);
    const env = coastEnvelope(track, dx, dz);
    let along = 0; // samples of road within 30 m of the coast-side envelope
    for (let i = 0; i < count; i++) if (px[i] * dx + pz[i] * dz + hw[i] > env(pz[i] * dx - px[i] * dz) - 30) along++;
    if (!best || along > best.along) best = { along, dx, dz, env };
  }
  ctx.coast = { ...theme.sea, dx: best.dx, dz: best.dz, env: best.env, off: 42 };
  planLighthouse(ctx);
}

/** Outermost road edge towards (dx, dz) as a function of the position across it, widened and smoothed. */
function coastEnvelope(track, dx, dz, bin = 20, reach = 140) {
  const { count, px, pz, hw } = track;
  const U = new Float32Array(count), Q = new Float32Array(count);
  let u0 = Infinity, u1 = -Infinity;
  for (let i = 0; i < count; i++) {
    U[i] = pz[i] * dx - px[i] * dz;
    Q[i] = px[i] * dx + pz[i] * dz + hw[i];
    u0 = Math.min(u0, U[i]); u1 = Math.max(u1, U[i]);
  }
  const n = Math.max(2, Math.ceil((u1 - u0) / bin) + 1);
  const mx = new Float32Array(n).fill(-1e9);
  for (let i = 0; i < count; i++) { const b = Math.round((U[i] - u0) / bin); if (Q[i] > mx[b]) mx[b] = Q[i]; }
  // dilate (the shore never cuts in between two parts of the track), then smooth over half that reach
  const r = Math.round(reach / bin), r2 = Math.max(1, Math.round(r / 2));
  const dil = new Float32Array(n), env = new Float32Array(n);
  for (let b = 0; b < n; b++) { let m = -1e9; for (let k = Math.max(0, b - r); k <= Math.min(n - 1, b + r); k++) m = Math.max(m, mx[k]); dil[b] = m; }
  for (let b = 0; b < n; b++) { let sum = 0; for (let k = -r2; k <= r2; k++) sum += dil[Math.max(0, Math.min(n - 1, b + k))]; env[b] = sum / (2 * r2 + 1); }
  return (u) => {
    const f = clamp((u - u0) / bin, 0, n - 1), b = Math.min(n - 2, Math.floor(f));
    return env[b] + (env[b + 1] - env[b]) * (f - b);
  };
}

/** A flat pad for the lighthouse on the shore, seaward of the outermost road (away from the gates). */
function planLighthouse(ctx) {
  const { track, G, coast } = ctx;
  const { count, px, pz, hw } = track;
  const out = (i) => px[i] * coast.dx + pz[i] * coast.dz + hw[i];
  const order = Array.from({ length: count }, (_, i) => i).sort((a, b) => out(b) - out(a));
  for (const i of order.slice(0, Math.min(count, 600))) {
    if (ctx.nearGate(i, 12)) continue;
    const off = hw[i] + BARRIER_W + 34;
    const cx = px[i] + coast.dx * off, cz = pz[i] + coast.dz * off;
    let ok = true;
    for (let j = 0; j < count && ok; j += 2) {
      const r = hw[j] + 22;
      if ((px[j] - cx) ** 2 + (pz[j] - cz) ** 2 < r * r) ok = false;
    }
    if (!ok) continue;
    ctx.pads.push({ kind: 'lighthouse', cx, cz, y: G[i], r: 9, pts: [[cx, cz]] });
    return;
  }
}

// =============================================================================
// Terrain
// =============================================================================

function buildTerrain(ctx, keep) {
  const { track, theme, G, seed } = ctx;
  const { count, px, pz, hw } = track;
  let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
  for (let i = 0; i < count; i++) {
    minX = Math.min(minX, px[i]); maxX = Math.max(maxX, px[i]);
    minZ = Math.min(minZ, pz[i]); maxZ = Math.max(maxZ, pz[i]);
  }
  const margin = 1150;
  const x0 = minX - margin, z0 = minZ - margin;
  const W = maxX - minX + 2 * margin, H = maxZ - minZ + 2 * margin;
  const cell = Math.max(6, Math.sqrt((W * H) / 78000));
  const NX = Math.ceil(W / cell) + 1, NZ = Math.ceil(H / cell) + 1;
  const NV = NX * NZ;

  const E = new Float32Array(NV).fill(1e9); // distance beyond the nearest road edge
  const WS = new Float32Array(NV), WG = new Float32Array(NV);
  const CAP = new Float32Array(NV).fill(1e9);

  const BLEND_R = 190;
  const stamp = (x, z, h, g, capOnly) => {
    const capR = h + ZONE + cell * 1.5;
    const R = capOnly ? capR : h + BLEND_R;
    const i0 = Math.max(0, Math.floor((x - R - x0) / cell)), i1 = Math.min(NX - 1, Math.ceil((x + R - x0) / cell));
    const k0 = Math.max(0, Math.floor((z - R - z0) / cell)), k1 = Math.min(NZ - 1, Math.ceil((z + R - z0) / cell));
    const R2 = R * R, capR2 = capR * capR;
    for (let k = k0; k <= k1; k++) {
      const dz = z0 + k * cell - z;
      const dz2 = dz * dz;
      if (dz2 > R2) continue;
      const row = k * NX;
      for (let i = i0; i <= i1; i++) {
        const dx = x0 + i * cell - x;
        const d2 = dx * dx + dz2;
        if (d2 > R2) continue;
        const v = row + i;
        const e = Math.sqrt(d2) - h;
        if (e < E[v]) E[v] = e;
        if (d2 <= capR2 && g < CAP[v]) CAP[v] = g;
        if (!capOnly) {
          const q = (e > 0 ? e : 0) / 22;
          const q2 = q * q;
          const w = 1 / (1 + q2 * q2);
          WS[v] += w;
          WG[v] += w * g;
        }
      }
    }
  };
  for (let i = 0; i < count; i++) stamp(px[i], pz[i], hw[i], G[i], i % 3 !== 0);
  for (const pad of ctx.pads) for (const [x, z] of pad.pts) stamp(x, z, pad.r, pad.y, false);

  // Chamfer distance transform: approximate distance far from the track.
  const dS = cell, dD = cell * Math.SQRT2;
  for (let k = 0; k < NZ; k++) {
    for (let i = 0; i < NX; i++) {
      const v = k * NX + i;
      let m = E[v];
      if (i > 0) m = Math.min(m, E[v - 1] + dS);
      if (k > 0) {
        m = Math.min(m, E[v - NX] + dS);
        if (i > 0) m = Math.min(m, E[v - NX - 1] + dD);
        if (i < NX - 1) m = Math.min(m, E[v - NX + 1] + dD);
      }
      E[v] = m;
    }
  }
  for (let k = NZ - 1; k >= 0; k--) {
    for (let i = NX - 1; i >= 0; i--) {
      const v = k * NX + i;
      let m = E[v];
      if (i < NX - 1) m = Math.min(m, E[v + 1] + dS);
      if (k < NZ - 1) {
        m = Math.min(m, E[v + NX] + dS);
        if (i < NX - 1) m = Math.min(m, E[v + NX + 1] + dD);
        if (i > 0) m = Math.min(m, E[v + NX - 1] + dD);
      }
      E[v] = m;
    }
  }

  // Base level of the land: a low percentile of the road-side level.
  const sorted = Float32Array.from(G).sort();
  const base = Math.min(sorted[Math.floor(sorted.length * 0.25)], 0.5);

  let minG = base;
  for (let i = 0; i < count; i++) minG = Math.min(minG, G[i]);
  const planeY = Math.min(base - 2 - theme.hills, minG - 2);
  const hgt = new Float32Array(NV);
  const style = theme.mountainStyle;
  // Seaside: the share of sea at each vertex (0 = land, 1 = open water) and the water level.
  const coast = ctx.coast;
  const waterY = coast ? Math.min(base, minG) - coast.level : null; // below the lowest ground beside the road
  const SEA = coast ? new Float32Array(NV) : null;
  for (let k = 0; k < NZ; k++) {
    const z = z0 + k * cell;
    for (let i = 0; i < NX; i++) {
      const x = x0 + i * cell;
      const v = k * NX + i;
      const e = E[v];
      const gN = WS[v] > 1e-4 ? WG[v] / WS[v] : base;
      const t1 = smoothstep(ZONE, BLEND_R, e);
      let h = gN;
      if (t1 > 0) {
        const n1 = fbm(x * 0.0032, z * 0.0032, 4, seed);
        const hills = theme.hills * (n1 - 0.4) * 2.2 + theme.hills * 0.25 * (fbm(x * 0.011, z * 0.011, 2, seed + 5) - 0.5);
        h = gN + (base + hills - gN) * t1;
      }
      const t2 = smoothstep(330, 950, e);
      if (t2 > 0) h += theme.mountains * t2 * mountainShape(x, z, style, seed);
      if (coast) {
        // no inland ponds: the land stays `level` m or more above the water (a smooth floor, so the
        // depth buffer never mixes land and water far away); beyond a ragged shoreline (at least
        // ~25 m off the road) the land slopes down under the water
        const fl = waterY + coast.level;
        h = (h + fl + Math.sqrt((h - fl) * (h - fl) + 1)) / 2;
        const p = x * coast.dx + z * coast.dz;
        const shore = coast.env(z * coast.dx - x * coast.dz) + coast.off + 44 * (fbm(x * 0.005, z * 0.005, 2, seed + 13) - 0.5);
        const t = smoothstep(shore - 15, shore + 40, p) * smoothstep(ZONE + 10, ZONE + 45, e);
        if (t > 0) h += (waterY - 1 - 7 * smoothstep(shore, shore + 260, p) - h) * t;
        SEA[v] = t;
      }
      if (h < planeY + 0.3) h = planeY + 0.3;
      const de = Math.min(x - x0, x0 + W - x, z - z0, z0 + H - z);
      const f = smoothstep(0, 280, de);
      h = (planeY - 1) + (h - (planeY - 1)) * f;
      if (CAP[v] < h) h = CAP[v];
      hgt[v] = h;
    }
  }

  // Geometry: regular grid, triangles (a,c,b) and (b,c,d) per cell.
  const pos = new Float32Array(NV * 3), uv = new Float32Array(NV * 2);
  for (let k = 0; k < NZ; k++) {
    for (let i = 0; i < NX; i++) {
      const v = k * NX + i;
      const x = x0 + i * cell, z = z0 + k * cell;
      pos[v * 3] = x; pos[v * 3 + 1] = hgt[v]; pos[v * 3 + 2] = z;
      uv[v * 2] = x / 7; uv[v * 2 + 1] = z / 7;
    }
  }
  const idx = new Uint32Array((NX - 1) * (NZ - 1) * 6);
  let p = 0;
  for (let k = 0; k < NZ - 1; k++) {
    for (let i = 0; i < NX - 1; i++) {
      const a = k * NX + i, b = a + 1, c = a + NX, d = c + 1;
      idx[p++] = a; idx[p++] = c; idx[p++] = b;
      idx[p++] = b; idx[p++] = c; idx[p++] = d;
    }
  }
  const geo = keep(new THREE.BufferGeometry());
  geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  geo.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
  geo.setIndex(new THREE.BufferAttribute(idx, 1));
  geo.computeVertexNormals();

  // Vertex colours from slope, height, noise and distance to the road.
  const nor = geo.attributes.normal.array;
  const colors = new Float32Array(NV * 3);
  const gc = theme.ground;
  const cA = new THREE.Color(gc.a), cB = new THREE.Color(gc.b), cDry = new THREE.Color(gc.dry);
  const cDirt = new THREE.Color(gc.dirt), cRock = new THREE.Color(gc.rock), cSnow = gc.snow ? new THREE.Color(gc.snow) : null;
  const cStrata = [new THREE.Color(gc.rock), new THREE.Color(gc.dry), new THREE.Color(gc.dirt), new THREE.Color(gc.b)];
  const cSand = coast && new THREE.Color(coast.sand), cShallow = coast && new THREE.Color(coast.shallow), cDeep = coast && new THREE.Color(coast.deep);
  const c = new THREE.Color();
  const boost = 1 / 0.86; // the detail texture darkens by ~14 % on average
  for (let k = 0; k < NZ; k++) {
    const z = z0 + k * cell;
    for (let i = 0; i < NX; i++) {
      const x = x0 + i * cell;
      const v = k * NX + i;
      const slope = 1 - nor[v * 3 + 1];
      const h = hgt[v] - base;
      const n = fbm(x * 0.018, z * 0.018, 3, seed + 3);
      const n2 = vnoise(x * 0.11, z * 0.11, seed + 4);
      c.copy(cA).lerp(cB, smoothstep(0.35, 0.65, n));
      c.lerp(cDry, smoothstep(0.55, 0.8, fbm(x * 0.005, z * 0.005, 2, seed + 9)) * 0.55);
      const e = E[v];
      if (e < 6) c.lerp(cDirt, 0.3 * (1 - Math.max(0, e) / 6));
      if (style === 'mesa' && h > 6) {
        const band = Math.floor(h / 7 + n * 0.8) & 3;
        c.lerp(cStrata[band], smoothstep(6, 22, h) * 0.85);
      }
      c.lerp(cRock, smoothstep(0.2, 0.42, slope + (n2 - 0.5) * 0.12));
      if (cSnow) {
        const line = 70 + n * 50;
        c.lerp(cSnow, smoothstep(line, line + 30, h) * (1 - smoothstep(0.38, 0.6, slope)));
      }
      if (SEA && SEA[v] > 0.001) {
        // a sandy beach down to the water line, then the sea bed darkening with depth
        // (seen through the water, which is slightly see-through)
        c.lerp(cSand, smoothstep(0, 0.2, SEA[v] + (n2 - 0.5) * 0.06));
        const depth = waterY - hgt[v];
        if (depth > 0) c.lerp(cShallow, smoothstep(0, 1.5, depth)).lerp(cDeep, smoothstep(1.5, 6, depth));
      }
      const j = (0.93 + n2 * 0.14) * boost;
      colors[v * 3] = c.r * j; colors[v * 3 + 1] = c.g * j; colors[v * 3 + 2] = c.b * j;
    }
  }
  geo.setAttribute('color', new THREE.BufferAttribute(colors, 3));

  const mat = keep(new THREE.MeshStandardMaterial({ vertexColors: true, map: detailTexture(), roughness: 0.94, metalness: 0 }));
  const mesh = new THREE.Mesh(geo, mat);
  mesh.receiveShadow = true;
  mesh.name = 'terrain';

  const farPlane = new THREE.Mesh(
    keep(new THREE.CircleGeometry(16000, 48).rotateX(-Math.PI / 2)),
    keep(new THREE.MeshStandardMaterial({ color: gc.far, roughness: 1, metalness: 0 })),
  );
  farPlane.position.set((minX + maxX) / 2, planeY, (minZ + maxZ) / 2);
  farPlane.name = 'far-ground';

  // The sea: one big, slightly see-through plane at the water level, with drifting ripples.
  let water = null;
  if (coast) {
    const nm = waterNormalTexture();
    const wmat = keep(new THREE.MeshStandardMaterial({
      color: coast.water, roughness: 0.07, metalness: 0, transparent: true, opacity: 0.84,
      normalMap: nm, normalScale: new THREE.Vector2(0.32, 0.32),
    }));
    water = new THREE.Mesh(keep(new THREE.CircleGeometry(16000, 64).rotateX(-Math.PI / 2)), wmat);
    water.position.set((minX + maxX) / 2, waterY, (minZ + maxZ) / 2);
    water.renderOrder = 1; // after the opaque world, before the lamp pools and smoke
    water.name = 'sea';
    water.onBeforeRender = () => { const t = performance.now() / 1000; nm.offset.set(t * 0.011, t * 0.007); };
  }

  /** Terrain height at (x, z), exactly as the triangles interpolate it. */
  const heightAt = (x, z) => {
    let fx = (x - x0) / cell, fz = (z - z0) / cell;
    fx = Math.max(0, Math.min(NX - 1.001, fx)); fz = Math.max(0, Math.min(NZ - 1.001, fz));
    const i = Math.floor(fx), k = Math.floor(fz), u = fx - i, w = fz - k;
    const a = k * NX + i;
    const ha = hgt[a], hb = hgt[a + 1], hc = hgt[a + NX], hd = hgt[a + NX + 1];
    if (u + w <= 1) return ha + (hb - ha) * u + (hc - ha) * w;
    return hd + (hc - hd) * (1 - u) + (hb - hd) * (1 - w);
  };
  /** Approximate distance beyond the nearest road edge (bilinear). */
  const edgeDist = (x, z) => {
    let fx = (x - x0) / cell, fz = (z - z0) / cell;
    if (fx < 0 || fz < 0 || fx > NX - 1.001 || fz > NZ - 1.001) return 1e9;
    const i = Math.floor(fx), k = Math.floor(fz), u = fx - i, w = fz - k;
    const a = k * NX + i;
    return (E[a] * (1 - u) + E[a + 1] * u) * (1 - w) + (E[a + NX] * (1 - u) + E[a + NX + 1] * u) * w;
  };
  /** Up-facing component of the terrain normal (1 = flat). */
  const flatness = (x, z) => {
    const i = Math.max(0, Math.min(NX - 1, Math.round((x - x0) / cell)));
    const k = Math.max(0, Math.min(NZ - 1, Math.round((z - z0) / cell)));
    return nor[(k * NX + i) * 3 + 1];
  };

  /** Share of open water at (x, z): 0 on land (and off the terrain), 1 out at sea (bilinear). */
  const seaAt = (x, z) => {
    if (!SEA) return 0;
    const fx = (x - x0) / cell, fz = (z - z0) / cell;
    if (fx < 0 || fz < 0 || fx > NX - 1.001 || fz > NZ - 1.001) return 0;
    const i = Math.floor(fx), k = Math.floor(fz), u = fx - i, w = fz - k;
    const a = k * NX + i;
    return (SEA[a] * (1 - u) + SEA[a + 1] * u) * (1 - w) + (SEA[a + NX] * (1 - u) + SEA[a + NX + 1] * u) * w;
  };

  return {
    mesh, farPlane, water, material: mat, heightAt, edgeDist, flatness, seaAt, waterY, base, vertexCount: NV,
    bounds: { x0, z0, W, H, minX, maxX, minZ, maxZ },
  };
}

function mountainShape(x, z, style, seed) {
  if (style === 'mesa') {
    const n = fbm(x * 0.0021, z * 0.0021, 4, seed + 7);
    const v = clamp((n - 0.43) * 3.2, 0, 1);
    const steps = 3, t = v * steps, fl = Math.min(steps - 1, Math.floor(t)), fr = t - fl;
    const stepped = (fl + smoothstep(0.68, 0.93, fr)) / steps;
    return stepped * 0.85 + v * 0.15;
  }
  let sum = 0, amp = 0.55, freq = 0.0019, prev = 1;
  for (let o = 0; o < 5; o++) {
    let r = 1 - Math.abs(vnoise(x * freq, z * freq, seed + 11 + o) * 2 - 1);
    r *= r;
    sum += r * amp * prev;
    prev = r;
    amp *= 0.5;
    freq *= 2.1;
  }
  return Math.max(0, sum * 1.35 - 0.18);
}

// =============================================================================
// Road, lines, curbs, start line
// =============================================================================

function buildRoad(ctx, keep) {
  const { track, segs, wrap, surfY, seed } = ctx;
  const { px, pz, nx, nz, hw, segLen } = track;
  // Lateral columns (fraction of half width) and their wear tint.
  const cols = [1, 0.78, 0.45, 0, -0.45, -0.78, -1];
  const wear = [1.06, 0.98, 0.84, 0.93, 0.84, 0.98, 1.06];
  const C = cols.length;
  const rows = segs + 1;
  const pos = new Float32Array(rows * C * 3), uv = new Float32Array(rows * C * 2), col = new Float32Array(rows * C * 3);
  for (let k = 0; k < rows; k++) {
    const i = wrap(k);
    const s = k * segLen;
    const patch = 0.94 + 0.12 * fbm(s * 0.02, 3.7, 2, seed + 21);
    for (let c = 0; c < C; c++) {
      const lat = cols[c] * hw[i];
      const v = k * C + c;
      pos[v * 3] = px[i] + nx[i] * lat;
      pos[v * 3 + 1] = surfY(i, lat);
      pos[v * 3 + 2] = pz[i] + nz[i] * lat;
      uv[v * 2] = lat / 7;
      uv[v * 2 + 1] = s / 7;
      const t = wear[c] * patch;
      col[v * 3] = t; col[v * 3 + 1] = t; col[v * 3 + 2] = t;
    }
  }
  const idx = [];
  for (let k = 0; k < segs; k++) {
    for (let c = 0; c < C - 1; c++) {
      const a = k * C + c, b = a + 1, d = a + C, cc = d + 1;
      idx.push(a, b, d, b, cc, d);
    }
  }
  const geo = keep(new THREE.BufferGeometry());
  geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  geo.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
  geo.setAttribute('color', new THREE.BufferAttribute(col, 3));
  geo.setIndex(idx);
  geo.computeVertexNormals();
  const tex = asphaltTextures();
  const mat = keep(new THREE.MeshStandardMaterial({
    map: tex.map, roughnessMap: tex.rough, normalMap: tex.normal, normalScale: new THREE.Vector2(0.55, 0.55),
    vertexColors: true, roughness: 1, metalness: 0,
  }));
  const mesh = new THREE.Mesh(geo, mat);
  mesh.receiveShadow = true;
  mesh.name = 'road';
  return mesh;
}

/** Painted edge lines, dashed centre line and the start grid boxes. */
function buildLines(ctx, keep) {
  const { track, segs, wrap, P, corner } = ctx;
  const { hw, segLen } = track;
  const b = new GeoBuilder();
  const white = new THREE.Color(0xe8e8e2);
  const lift = 0.012;
  const strip = (i, j, la, lb, laj, lbj, color = white) => b.flatQuad(P(i, la, lift), P(j, laj, lift), P(j, lbj, lift), P(i, lb, lift), color);
  for (let k = 0; k < segs; k++) {
    const i = wrap(k), j = wrap(k + 1);
    if (!corner[i] || !corner[j]) {
      for (const s of [1, -1]) {
        strip(i, j, s * (hw[i] - 0.38), s * (hw[i] - 0.62), s * (hw[j] - 0.38), s * (hw[j] - 0.62));
      }
    }
    if (Math.floor((k * segLen) / 4) % 3 === 0) strip(i, j, 0.12, -0.12, 0.12, -0.12);
  }
  // Start grid: the player's box at the start sample, staggered boxes behind the line.
  const { px, pz, nx, nz } = track;
  const at = (fi, lat) => {
    const i0 = Math.floor(fi), f = fi - i0, a = wrap(i0), c = wrap(i0 + 1);
    const ux = nx[a] + (nx[c] - nx[a]) * f, uz = nz[a] + (nz[c] - nz[a]) * f;
    const y = ctx.surfY(a, lat) + (ctx.surfY(c, lat) - ctx.surfY(a, lat)) * f;
    return [px[a] + (px[c] - px[a]) * f + ux * lat, y + lift, pz[a] + (pz[c] - pz[a]) * f + uz * lat];
  };
  const rect = (f0, f1, l0, l1) => b.flatQuad(at(f0, l0), at(f1, l0), at(f1, l1), at(f0, l1), white);
  const box = (i, lat) => {
    const w = 1.45, t = 0.16, df = 2.7 / segLen, dt = t / segLen;
    rect(i - df, i + df, lat + w, lat + w - t);
    rect(i - df, i + df, lat - w + t, lat - w);
    rect(i - df, i - df + dt, lat + w - t, lat - w + t);
    rect(i + df - dt * 2.5, i + df, lat + w - t, lat - w + t);
  };
  box(track.startIdx, 0);
  if (track.closed) {
    for (let g = 0; g < 4; g++) box(track.count - 8 - g * 5, (g % 2 ? -1 : 1) * Math.min(4, track.hw[0] * 0.45));
  }
  const mat = keep(new THREE.MeshStandardMaterial({
    vertexColors: true, roughness: 0.62, metalness: 0,
    polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2,
  }));
  const mesh = new THREE.Mesh(keep(b.build()), mat);
  mesh.receiveShadow = true;
  mesh.name = 'lines';
  return mesh;
}

/** Raised red/white curbs on both edges of every corner. */
function buildCurbs(ctx, keep) {
  const { track, segs, wrap, corner, surfY } = ctx;
  const { px, pz, nx, nz, hw } = track;
  const b = new GeoBuilder();
  const red = new THREE.Color(0xd8322b), white = new THREE.Color(0xf2f2f2);
  // curbs ramp up over the first and last few samples of a corner
  const taper = (i) => {
    for (let d = 1; d <= 3; d++) if (!corner[wrap(i - d)] || !corner[wrap(i + d)]) return d / 4;
    return 1;
  };
  const H = 0.075, W = 1.5, ramp = 0.35;
  const pt = (i, f, lat, dy) => {
    // point between sample i (f=0) and its successor (f=1)
    const j = wrap(i + 1);
    const x = px[i] + (px[j] - px[i]) * f, z = pz[i] + (pz[j] - pz[i]) * f;
    const ux = nx[i] + (nx[j] - nx[i]) * f, uz = nz[i] + (nz[j] - nz[i]) * f;
    const y = surfY(i, lat) + (surfY(j, lat) - surfY(i, lat)) * f;
    return [x + ux * lat, y + dy, z + uz * lat];
  };
  let n = 0;
  for (let k = 0; k < segs; k++) {
    const i = wrap(k), j = wrap(k + 1);
    if (!corner[i] || !corner[j]) continue;
    const hi = H * taper(i), hj = H * taper(j);
    for (let half = 0; half < 2; half++) {
      const f0 = half * 0.5, f1 = f0 + 0.5;
      const h0 = hi + (hj - hi) * f0, h1 = hi + (hj - hi) * f1;
      const color = (k * 2 + half) % 2 ? red : white;
      for (const s of [1, -1]) {
        const w0 = hw[i] + (hw[j] - hw[i]) * f0, w1 = hw[i] + (hw[j] - hw[i]) * f1;
        const inA = s * (w0 - W), inB = s * (w1 - W);
        const topA = s * (w0 - W + ramp), topB = s * (w1 - W + ramp);
        const outA = s * (w0 - 0.01), outB = s * (w1 - 0.01);
        // ramp up from the road, then the flat top to the barrier
        b.flatQuad(pt(i, f0, inA, 0.004), pt(i, f1, inB, 0.004), pt(i, f1, topB, h1), pt(i, f0, topA, h0), color);
        b.flatQuad(pt(i, f0, topA, h0), pt(i, f1, topB, h1), pt(i, f1, outB, h1), pt(i, f0, outA, h0), color);
        n++;
      }
    }
  }
  if (!n) return null;
  const mat = keep(new THREE.MeshStandardMaterial({
    vertexColors: true, roughness: 0.5, metalness: 0,
    polygonOffset: true, polygonOffsetFactor: -1, polygonOffsetUnits: -1,
  }));
  const mesh = new THREE.Mesh(keep(b.build()), mat);
  mesh.receiveShadow = true;
  mesh.name = 'curbs';
  return mesh;
}

/** Checkered start (and finish) lines across the road. */
function buildStartLines(ctx, keep) {
  const { track, wrap, P } = ctx;
  const { hw, segLen } = track;
  const b = new GeoBuilder();
  const white = new THREE.Color(1, 1, 1);
  const line = (i) => {
    const a = wrap(i - 1), c = wrap(i + 1);
    const u = (lat) => (lat + 40) / 1.6;
    const v0 = 0, v1 = (2 * segLen) / 1.6;
    b.quadUV(P(a, hw[a], 0.02), P(c, hw[c], 0.02), P(c, -hw[c], 0.02), P(a, -hw[a], 0.02),
      [u(hw[a]), v0], [u(hw[c]), v1], [u(-hw[c]), v1], [u(-hw[a]), v0], white, UP);
  };
  if (track.closed) line(0);
  else { line(track.startLine ?? track.startIdx); line(track.finishIdx); }
  const mat = keep(new THREE.MeshStandardMaterial({
    map: checkerTexture(), roughness: 0.6, metalness: 0,
    polygonOffset: true, polygonOffsetFactor: -3, polygonOffsetUnits: -3,
  }));
  const mesh = new THREE.Mesh(keep(b.build()), mat);
  mesh.receiveShadow = true;
  mesh.name = 'start-line';
  return mesh;
}

// =============================================================================
// Barriers and embankments
// =============================================================================

// Barrier cross-section: [outward offset from the road edge, height, part]
// part 0 = concrete, 1 = coloured panel, 2 = top cap
const BARRIER_PROFILE = [
  [0.0, 0.0], [0.05, 0.26], [0.12, 0.32], [0.2, 0.96], [0.24, 1.05], [0.3, BARRIER_H], [0.58, BARRIER_H], [BARRIER_W, 0.0],
];
const BARRIER_PART = [0, 0, 1, 0, 2, 2, 0];

function buildBarriers(ctx, keep) {
  const { track, theme, segs, wrap, edgeY } = ctx;
  const { px, pz, nx, nz, hw, segLen } = track;
  const b = new GeoBuilder();
  const concrete = new THREE.Color(0xb9bbbd), cap = new THREE.Color(0xd9dadb);
  const panelA = new THREE.Color(theme.accent[0]), panelB = new THREE.Color(theme.accent[1]);
  const nP = BARRIER_PROFILE.length - 1;
  // 2D normals of each profile segment (outward, up)
  const pn = [];
  for (let p = 0; p < nP; p++) {
    const [o0, y0] = BARRIER_PROFILE[p], [o1, y1] = BARRIER_PROFILE[p + 1];
    const dO = o1 - o0, dY = y1 - y0, l = Math.hypot(dO, dY);
    pn.push([-dY / l, dO / l]);
  }
  for (const s of [1, -1]) {
    for (let k = 0; k < segs; k++) {
      const i = wrap(k), j = wrap(k + 1);
      const panel = Math.floor(k / 5) % 2 ? panelA : panelB;
      const u0 = (k * segLen) / 3, u1 = ((k + 1) * segLen) / 3;
      const oix = nx[i] * s, oiz = nz[i] * s, ojx = nx[j] * s, ojz = nz[j] * s;
      const exi = px[i] + oix * hw[i], ezi = pz[i] + oiz * hw[i], eyi = edgeY(i, s);
      const exj = px[j] + ojx * hw[j], ezj = pz[j] + ojz * hw[j], eyj = edgeY(j, s);
      for (let p = 0; p < nP; p++) {
        const oa = BARRIER_PROFILE[p][0], ya = BARRIER_PROFILE[p][1];
        const ob = BARRIER_PROFILE[p + 1][0], yb = BARRIER_PROFILE[p + 1][1];
        const nO = pn[p][0], nY = pn[p][1];
        const color = BARRIER_PART[p] === 1 ? panel : BARRIER_PART[p] === 2 ? cap : concrete;
        const v0 = b.vert(exi + oix * oa, eyi + ya, ezi + oiz * oa, oix * nO, nY, oiz * nO, u0, ya / 3, color);
        const v1 = b.vert(exj + ojx * oa, eyj + ya, ezj + ojz * oa, ojx * nO, nY, ojz * nO, u1, ya / 3, color);
        const v2 = b.vert(exj + ojx * ob, eyj + yb, ezj + ojz * ob, ojx * nO, nY, ojz * nO, u1, yb / 3, color);
        const v3 = b.vert(exi + oix * ob, eyi + yb, ezi + oiz * ob, oix * nO, nY, oiz * nO, u0, yb / 3, color);
        // counter-clockwise around the outward profile normal
        if (s > 0) b.quad(v0, v1, v2, v3); else b.quad(v0, v3, v2, v1);
      }
    }
  }
  // Sprint tracks: a barrier across each end of the road.
  if (!track.closed) {
    for (const [i, dir] of [[0, -1], [track.count - 1, 1]]) {
      const ox = track.tx[i] * dir, oz = track.tz[i] * dir;
      const steps = 8;
      for (let q = 0; q < steps; q++) {
        const la = -hw[i] - BARRIER_W + ((2 * (hw[i] + BARRIER_W)) * q) / steps;
        const lb = -hw[i] - BARRIER_W + ((2 * (hw[i] + BARRIER_W)) * (q + 1)) / steps;
        const ya = ctx.surfY(i, Math.max(-hw[i], Math.min(hw[i], la))), yb = ctx.surfY(i, Math.max(-hw[i], Math.min(hw[i], lb)));
        for (let p = 0; p < nP; p++) {
          const [o0, y0] = BARRIER_PROFILE[p], [o1, y1] = BARRIER_PROFILE[p + 1];
          const at = (lat, yy, o, y) => [px[i] + nx[i] * lat + ox * o, yy + y, pz[i] + nz[i] * lat + oz * o];
          const color = BARRIER_PART[p] === 1 ? panelB : BARRIER_PART[p] === 2 ? cap : concrete;
          const n = [ox * pn[p][0], pn[p][1], oz * pn[p][0]];
          b.sweepQuad(at(la, ya, o0, y0), at(lb, yb, o0, y0), at(lb, yb, o1, y1), at(la, ya, o1, y1), n, n, color,
            [la / 3, y0 / 3], [lb / 3, y0 / 3], [lb / 3, y1 / 3], [la / 3, y1 / 3]);
        }
      }
    }
  }
  const mat = keep(new THREE.MeshStandardMaterial({ vertexColors: true, map: detailTexture(), roughness: 0.82, metalness: 0 }));
  const mesh = new THREE.Mesh(keep(b.build()), mat);
  mesh.castShadow = true;
  mesh.receiveShadow = true;
  mesh.name = 'barriers';
  return mesh;
}

/** Night: an emissive stripe along the coloured panel of every barrier, for the bloom to pick up. */
function buildGlowStripes(ctx, keep) {
  const { track, theme, segs, wrap, edgeY } = ctx;
  const { px, pz, nx, nz, hw } = track;
  const b = new GeoBuilder();
  const y0 = 0.5, y1 = 0.66;
  // just in front of the sloping panel face (BARRIER_PROFILE points 2-3)
  const off = (y) => 0.12 + ((y - 0.32) * 0.08) / 0.64 - 0.015;
  for (const s of [1, -1]) {
    for (let k = 0; k < segs; k++) {
      const i = wrap(k), j = wrap(k + 1);
      const at = (n, y) => { const o = hw[n] + off(y); return [px[n] + nx[n] * s * o, edgeY(n, s) + y, pz[n] + nz[n] * s * o]; };
      b.quadUV(at(i, y0), at(j, y0), at(j, y1), at(i, y1), [0, 0], [1, 0], [1, 1], [0, 1], WHITE, [-nx[i] * s, 0, -nz[i] * s]);
    }
  }
  const mat = keep(new THREE.MeshStandardMaterial({ color: 0x06242e, emissive: theme.accent[0], emissiveIntensity: 1.4, roughness: 0.4, metalness: 0 }));
  const mesh = new THREE.Mesh(keep(b.build()), mat);
  mesh.name = 'glow-stripes';
  return mesh;
}

/** Earth slopes from the outside of the barriers down into the terrain. */
function buildEmbankments(ctx, keep) {
  const { track, theme, segs, wrap, edgeY, kappa, terrain } = ctx;
  const { px, pz, nx, nz, hw, closed } = track;
  const rows = segs + 1;
  const b = new GeoBuilder();
  const verge = new THREE.Color(theme.ground.a).multiplyScalar(0.85 / 0.86);
  const earth = new THREE.Color(theme.ground.dirt).multiplyScalar(1 / 0.86);
  const rock = new THREE.Color(theme.ground.rock).multiplyScalar(1 / 0.86);
  const tmp = new THREE.Color();
  for (const s of [1, -1]) {
    const start = b.count;
    for (let k = 0; k < rows; k++) {
      const i = wrap(k);
      const eY = edgeY(i, s);
      const inner = s * kappa[i] > 0;
      const maxExt = inner ? clamp(1 / Math.max(1e-4, Math.abs(kappa[i])) - hw[i] - BARRIER_W - 1, 0.4, 10) : 10;
      const o0 = hw[i] + BARRIER_W, o1 = o0 + 0.35;
      const at = (o) => [px[i] + nx[i] * s * o, pz[i] + nz[i] * s * o];
      let [qx, qz] = at(o1 + 2);
      const drop = eY - terrain.heightAt(qx, qz);
      const ext = clamp(drop * 1.15, 0.6, maxExt);
      [qx, qz] = at(o1 + ext);
      const toeY = Math.min(terrain.heightAt(qx, qz) - 0.9, eY - 0.5);
      const steep = (eY - toeY) / ext;
      const [ax, az] = at(o0), [bx, bz] = at(o1);
      tmp.copy(earth).lerp(rock, smoothstep(0.9, 1.6, steep));
      b.vert(ax, eY - 0.02, az, 0, 1, 0, ax / 7, az / 7, verge);
      b.vert(bx, eY - 0.1, bz, 0, 1, 0, bx / 7, bz / 7, verge);
      b.vert(qx, toeY, qz, 0, 1, 0, qx / 7, qz / 7, tmp);
    }
    for (let k = 0; k < rows - 1; k++) {
      const a = start + k * 3, c = a + 3;
      // counter-clockwise seen from above on both sides
      if (s > 0) { b.quad(a, c, c + 1, a + 1); b.quad(a + 1, c + 1, c + 2, a + 2); }
      else { b.quad(a, a + 1, c + 1, c); b.quad(a + 1, a + 2, c + 2, c + 1); }
    }
  }
  if (!closed) {
    // end of a sprint: slope down behind the end barriers
    for (const [i, dir] of [[0, -1], [track.count - 1, 1]]) {
      const ox = track.tx[i] * dir, oz = track.tz[i] * dir;
      const start = b.count;
      const steps = 8;
      for (let q = 0; q <= steps; q++) {
        const lat = -hw[i] - BARRIER_W + ((2 * (hw[i] + BARRIER_W)) * q) / steps;
        const y = ctx.surfY(i, Math.max(-hw[i], Math.min(hw[i], lat)));
        const ax = px[i] + nx[i] * lat + ox * BARRIER_W, az = pz[i] + nz[i] * lat + oz * BARRIER_W;
        const ext = clamp((y - terrain.heightAt(ax + ox * 3, az + oz * 3)) * 1.15, 0.6, 10);
        const qx = ax + ox * ext, qz = az + oz * ext;
        const toeY = Math.min(terrain.heightAt(qx, qz) - 0.9, y - 0.5);
        b.vert(ax, y - 0.02, az, 0, 1, 0, ax / 7, az / 7, verge);
        b.vert(qx, toeY, qz, 0, 1, 0, qx / 7, qz / 7, earth);
      }
      for (let q = 0; q < steps; q++) {
        const a = start + q * 2;
        if (dir < 0) b.quad(a, a + 2, a + 3, a + 1);
        else b.quad(a, a + 1, a + 3, a + 2);
      }
    }
  }
  const geo = keep(b.build());
  geo.computeVertexNormals();
  const mat = terrain.material;
  const mesh = new THREE.Mesh(geo, mat);
  mesh.receiveShadow = true;
  mesh.name = 'embankments';
  return mesh;
}

// =============================================================================
// Gates
// =============================================================================

function buildGates(ctx, keep) {
  const { track, theme, P } = ctx;
  const { px, py, pz, tx, tz, hw, bank } = track;
  const defs = [];
  if (track.closed) defs.push({ i: 0, kind: 'start', label: 'START · FINISH' });
  else {
    defs.push({ i: track.startLine ?? track.startIdx, kind: 'start', label: 'START' });
    defs.push({ i: track.finishIdx, kind: 'start', label: 'FINISH' });
  }
  track.cpSamples.forEach((s, k) => defs.push({ i: s, kind: 'cp', k, label: `CHECKPOINT ${k + 1}` }));

  const atlas = keep(gateAtlas(defs, theme));
  const frame = new GeoBuilder(), banner = new GeoBuilder();
  const group = new THREE.Group();
  group.name = 'gates';
  const dark = new THREE.Color(0x2b2f37), steel = new THREE.Color(0x8b9099), foot = new THREE.Color(0xa9abad);
  const cp = [];
  const startMat = keep(stripMaterial(GATE_STATE.start, theme));
  const m = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler(0, 0, 0, 'YXZ');
  defs.forEach((d, row) => {
    const i = d.i;
    const big = d.kind === 'start';
    const cb = Math.cos(bank[i]);
    const W = (hw[i] + 0.38) / cb; // pillar centre, in the frame tilted with the road
    const Hh = big ? 8.2 : 7.2;
    e.set(0, Math.atan2(tx[i], tz[i]), -bank[i]);
    m.compose(new THREE.Vector3(px[i], py[i], pz[i]), q.setFromEuler(e), new THREE.Vector3(1, 1, 1));
    const pw = big ? 1.0 : 0.8;
    for (const s of [1, -1]) {
      frame.box(m, s * W, (Hh - 2.5) / 2, 0, pw, Hh + 2.5, big ? 1.2 : 0.9, dark);
      frame.box(m, s * W, 0.3, 0, pw + 0.4, 0.6, (big ? 1.2 : 0.9) + 0.4, foot);
      frame.box(m, s * (W + pw / 2 + 0.02), Hh * 0.5, 0, 0.06, Hh * 0.8, 0.3, steel);
    }
    const beamH = big ? 2.0 : 1.6, beamD = big ? 1.4 : 1.0;
    frame.box(m, 0, Hh - beamH / 2, 0, 2 * W + pw, beamH, beamD, dark);
    // banner on both faces of the beam
    const v0 = 1 - (row + 1) / defs.length, v1 = 1 - row / defs.length;
    const bx = W - pw / 2 - 0.05, by0 = Hh - beamH + 0.12, by1 = Hh - 0.12, bz = beamD / 2 + 0.02;
    const tp = (x, y, z) => new THREE.Vector3(x, y, z).applyMatrix4(m).toArray();
    banner.quadUV(tp(bx, by0, -bz), tp(-bx, by0, -bz), tp(-bx, by1, -bz), tp(bx, by1, -bz), [0, v0], [1, v0], [1, v1], [0, v1], WHITE);
    banner.quadUV(tp(-bx, by0, bz), tp(bx, by0, bz), tp(bx, by1, bz), tp(-bx, by1, bz), [0, v0], [1, v0], [1, v1], [0, v1], WHITE);
    // emissive light strips: inside the pillars and under the beam
    const sb = new GeoBuilder();
    const ix = W - pw / 2 - 0.05;
    for (const s of [1, -1]) sb.box(m, s * ix, 0.65 + (Hh - beamH - 0.75) / 2, 0, 0.12, Hh - beamH - 0.75, 0.42, WHITE);
    sb.box(m, 0, Hh - beamH - 0.06, 0, 2 * ix, 0.12, 0.42, WHITE);
    for (const z of [-1, 1]) sb.box(m, 0, Hh - 0.06, z * (beamD / 2 + 0.03), 2 * W + pw - 0.2, 0.1, 0.08, WHITE);
    const mat = d.kind === 'cp' ? keep(stripMaterial(GATE_STATE.next, theme)) : startMat;
    const strips = new THREE.Mesh(keep(sb.build()), mat);
    strips.name = `gate-lights-${row}`;
    group.add(strips);
    if (d.kind === 'cp') cp[d.k] = mat;
  });
  const frameMesh = new THREE.Mesh(keep(frame.build()), keep(fadeNearCamera(new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.42, metalness: 0.55 }))));
  frameMesh.castShadow = true;
  frameMesh.receiveShadow = true;
  const bannerMesh = new THREE.Mesh(keep(banner.build()), keep(fadeNearCamera(new THREE.MeshStandardMaterial({
    map: atlas, emissiveMap: atlas, emissive: 0xffffff, emissiveIntensity: theme.lamps ? 0.55 : 0.12, roughness: 0.55, metalness: 0,
  }))));
  group.add(frameMesh, bannerMesh);
  return { group, cp };
}

function stripMaterial(state, theme) {
  return fadeNearCamera(new THREE.MeshStandardMaterial({
    color: state.color, emissive: state.color, emissiveIntensity: state.glow * (theme.lamps ? 1.25 : 1), roughness: 0.35, metalness: 0,
  }));
}

/**
 * Dissolves the surface (screen-door dither) where it comes within a few
 * metres of the camera, so a gate beam or lamp post the chase camera passes
 * through never blacks out the view. Shadows are unaffected (the shadow pass
 * uses its own depth material). Works for meshes and instanced meshes.
 */
function fadeNearCamera(mat, near = 1.2, far = 4.5) {
  mat.onBeforeCompile = (sh) => {
    sh.vertexShader = sh.vertexShader
      .replace('#include <common>', '#include <common>\nvarying vec3 vFadeW;')
      .replace('#include <project_vertex>', `#include <project_vertex>
        vec4 fadeW = vec4(transformed, 1.0);
        #ifdef USE_INSTANCING
          fadeW = instanceMatrix * fadeW;
        #endif
        vFadeW = (modelMatrix * fadeW).xyz;`);
    sh.fragmentShader = sh.fragmentShader
      .replace('#include <common>', '#include <common>\nvarying vec3 vFadeW;')
      .replace('#include <clipping_planes_fragment>', `#include <clipping_planes_fragment>
        {
          float fadeT = (distance(vFadeW, cameraPosition) - ${near.toFixed(2)}) / ${(far - near).toFixed(2)};
          if (fadeT < 1.0 && fadeT < fract(dot(floor(gl_FragCoord.xy), vec2(0.7548776662, 0.5698402910)))) discard;
        }`);
  };
  mat.customProgramCacheKey = () => `fadeNearCamera${near},${far}`;
  return mat;
}

// =============================================================================
// Props: lamps, chevrons, banners, grandstand
// =============================================================================

function addProps(ctx, group, keep) {
  const { track, theme, segs, wrap, edgeY, kappa, nearGate } = ctx;
  const { px, pz, nx, nz, hw, tx, tz, segLen } = track;

  // ---- lamp posts on the barrier tops ----
  const lamps = [];
  {
    const step = Math.max(14, Math.round(46 / segLen));
    let n = 0;
    for (let k = 6; k < segs - 2; k += step) {
      const i = wrap(k);
      if (nearGate(i, 6)) continue;
      const s = n++ % 2 ? 1 : -1;
      lamps.push({ i, s });
    }
    const poleGeo = keep(lampPostGeometry());
    const headGeo = keep(new THREE.BoxGeometry(1.0, 0.16, 0.42).translate(2.25, 7.38, 0));
    const poles = new THREE.InstancedMesh(poleGeo, keep(fadeNearCamera(new THREE.MeshStandardMaterial({ color: 0x5b6069, roughness: 0.45, metalness: 0.7 }))), Math.max(1, lamps.length));
    const heads = new THREE.InstancedMesh(headGeo, keep(fadeNearCamera(new THREE.MeshStandardMaterial({
      color: 0xfff4e0, emissive: 0xffd9a0, emissiveIntensity: theme.lamps ? 7 : 0.25, roughness: 0.3,
    }))), Math.max(1, lamps.length));
    const m = new THREE.Matrix4(), q = new THREE.Quaternion(), up = new THREE.Vector3(0, 1, 0), one = new THREE.Vector3(1, 1, 1);
    lamps.forEach(({ i, s }, k) => {
      const o = hw[i] + 0.44;
      const p = new THREE.Vector3(px[i] + nx[i] * s * o, edgeY(i, s) + BARRIER_H, pz[i] + nz[i] * s * o);
      q.setFromAxisAngle(up, Math.atan2(s * nz[i], -s * nx[i]));
      m.compose(p, q, one);
      poles.setMatrixAt(k, m);
      heads.setMatrixAt(k, m);
    });
    poles.count = heads.count = lamps.length;
    poles.castShadow = true;
    group.add(poles, heads);

    if (theme.lamps && lamps.length) {
      // light pools on the road under the lamps (additive decals)
      const b = new GeoBuilder();
      const warm = new THREE.Color(1, 1, 1);
      for (const { i, s } of lamps) {
        const c = s * (hw[i] + 0.44 - 2.25);
        const R = 8;
        const rows = 4;
        let prev = null;
        for (let r = -rows; r <= rows; r++) {
          const j = wrap(i + r);
          const la = Math.min(hw[j], c + R), lb = Math.max(-hw[j], c - R);
          const v = (r * segLen) / (2 * R) + 0.5;
          const ua = (la - c) / (2 * R) + 0.5, ub = (lb - c) / (2 * R) + 0.5;
          const row = [ctx.P(j, la, 0.03), ctx.P(j, lb, 0.03), [ua, v], [ub, v]];
          if (prev) b.quadUV(prev[0], row[0], row[1], prev[1], prev[2], row[2], row[3], prev[3], warm, UP);
          prev = row;
        }
      }
      const pool = new THREE.Mesh(keep(b.build()), keep(new THREE.MeshBasicMaterial({
        map: glowTexture(), color: 0xffb877, transparent: true, opacity: 0.5, blending: THREE.AdditiveBlending,
        depthWrite: false, polygonOffset: true, polygonOffsetFactor: -4, polygonOffsetUnits: -4,
      })));
      pool.renderOrder = 2;
      pool.name = 'lamp-pools';
      group.add(pool);
    }
  }

  // ---- chevron boards on the outside of tight corners ----
  {
    const b = new GeoBuilder();
    for (let k = 0; k < segs; k += 4) {
      const i = wrap(k), j = wrap(k + 1);
      if (Math.abs(kappa[i]) < 1 / 55 || nearGate(i, 5)) continue;
      const s = kappa[i] > 0 ? -1 : 1; // outer side
      const o = hw[i] + 0.3, oj = hw[j] + 0.3;
      const y0 = edgeY(i, s) + BARRIER_H + 0.05, y0j = edgeY(j, s) + BARRIER_H + 0.05;
      const A = [px[i] + nx[i] * s * o, y0, pz[i] + nz[i] * s * o];
      const B = [px[j] + nx[j] * s * oj, y0j, pz[j] + nz[j] * s * oj];
      b.quadUV(A, B, [B[0], y0j + 1.0, B[2]], [A[0], y0 + 1.0, A[2]], [0, 0], [1, 0], [1, 1], [0, 1], WHITE);
    }
    if (b.count) {
      const mesh = new THREE.Mesh(keep(b.build()), keep(fadeNearCamera(new THREE.MeshStandardMaterial({
        map: chevronTexture(), side: THREE.DoubleSide, roughness: 0.5,
        emissive: 0xffffff, emissiveMap: chevronTexture(), emissiveIntensity: theme.lamps ? 0.5 : 0.08,
      }))));
      mesh.castShadow = true;
      mesh.name = 'chevrons';
      group.add(mesh);
    }
  }

  // ---- banners on the barrier tops along straights ----
  const bannerB = new GeoBuilder();
  {
    const lampAt = new Set(lamps.map((l) => `${l.s}:${l.i}`));
    const nearLamp = (i, s) => { for (let d = -4; d <= 4; d++) if (lampAt.has(`${s}:${wrap(i + d)}`)) return true; return false; };
    const step = Math.max(20, Math.round(130 / segLen));
    let n = 0;
    for (let k = 10; k < segs - 4; k += step) {
      const i = wrap(k);
      let straight = true;
      for (let d = -2; d <= 4; d++) if (Math.abs(kappa[wrap(i + d)]) > 1 / 300) straight = false;
      if (!straight || nearGate(i, 8)) continue;
      const s = n % 2 ? 1 : -1;
      if (nearLamp(i, s)) continue;
      const row = n++ % 4;
      let prev = null;
      for (let d = 0; d <= 3; d++) {
        const j = wrap(i + d);
        const o = hw[j] + 0.32;
        const y = edgeY(j, s) + BARRIER_H + 0.02;
        const p0 = [px[j] + nx[j] * s * o, y, pz[j] + nz[j] * s * o];
        const p1 = [p0[0], y + 1.25, p0[2]];
        // banners read left to right from the road
        const u = s > 0 ? d / 3 : 1 - d / 3;
        const v0 = 1 - (row + 1) / 4, v1 = 1 - row / 4;
        if (prev) bannerB.quadUV(prev[0], p0, p1, prev[1], [prev[2], v0], [u, v0], [u, v1], [prev[2], v1], WHITE);
        prev = [p0, p1, u];
      }
    }
  }

  // ---- grandstand ----
  const pad = ctx.pads.find((p) => p.kind === 'grandstand');
  if (pad) {
    const gs = grandstandGeometry(pad, theme, ctx.seed, bannerB);
    const mesh = new THREE.Mesh(keep(gs), keep(new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.75, metalness: 0.05 })));
    mesh.castShadow = true;
    mesh.receiveShadow = true;
    mesh.name = 'grandstand';
    group.add(mesh);
  }

  if (bannerB.count) {
    const tex = bannerTexture();
    const mesh = new THREE.Mesh(keep(bannerB.build()), keep(fadeNearCamera(new THREE.MeshStandardMaterial({
      map: tex, side: THREE.DoubleSide, roughness: 0.6, emissive: 0xffffff, emissiveMap: tex, emissiveIntensity: theme.lamps ? 0.45 : 0.06,
    }))));
    mesh.castShadow = true;
    mesh.name = 'banners';
    group.add(mesh);
  }
}

function lampPostGeometry() {
  const b = new GeoBuilder();
  const grey = new THREE.Color(1, 1, 1);
  const pole = new THREE.CylinderGeometry(0.09, 0.13, 7.6, 8).translate(0, 3.8, 0);
  b.addGeometry(pole, new THREE.Matrix4(), grey);
  const arm = new THREE.CylinderGeometry(0.06, 0.06, 2.4, 6).rotateZ(Math.PI / 2 + 0.08).translate(1.15, 7.5, 0);
  b.addGeometry(arm, new THREE.Matrix4(), grey);
  const base = new THREE.CylinderGeometry(0.2, 0.24, 0.3, 8).translate(0, 0.15, 0);
  b.addGeometry(base, new THREE.Matrix4(), grey);
  pole.dispose(); arm.dispose(); base.dispose();
  return b.build();
}

/** Tiered seating with a crowd, roof and a sponsor banner. Local x along the track, z away from it. */
function grandstandGeometry(pad, theme, seed, bannerB) {
  const b = new GeoBuilder();
  const rnd = mulberry32(seed ^ 0x51a7);
  const m = new THREE.Matrix4().makeBasis(
    new THREE.Vector3(pad.ax, 0, pad.az),
    new THREE.Vector3(0, 1, 0),
    new THREE.Vector3(pad.ox, 0, pad.oz),
  );
  // the basis may be mirrored: keep it right-handed by flipping x
  if (m.determinant() < 0) m.makeBasis(new THREE.Vector3(-pad.ax, 0, -pad.az), new THREE.Vector3(0, 1, 0), new THREE.Vector3(pad.ox, 0, pad.oz));
  m.setPosition(pad.cx - pad.ox * (pad.D / 2), pad.y, pad.cz - pad.oz * (pad.D / 2));
  const L = pad.L, D = pad.D;
  const concrete = new THREE.Color(0xb7b4ae), darkC = new THREE.Color(0x8d8a85), seat = new THREE.Color(theme.accent[0]);
  const roofC = new THREE.Color(0xe9ecef), steel = new THREE.Color(0x5b6069);
  // foundation and front wall
  b.box(m, 0, -1.2, D / 2, L + 1, 3.0, D + 1, darkC);
  b.box(m, 0, 0.9, 0.9, L, 1.2, 0.3, concrete);
  const rows = 9, tread = 1.15, rise = 0.55;
  const crowd = [0xe8423f, 0x2f7de1, 0xf5c542, 0xffffff, 0x2a2a2a, 0x46b05a, 0xf08a3c, 0x9b59d0, 0x1fb6c9];
  for (let r = 0; r < rows; r++) {
    const z = 1.6 + r * tread, y = 0.6 + r * rise;
    b.box(m, 0, y / 2, z + tread / 2, L, y, tread, concrete);
    b.box(m, 0, y + 0.18, z + tread * 0.55, L - 0.4, 0.12, 0.45, seat);
    for (let x = -L / 2 + 0.6; x < L / 2 - 0.4; x += 0.75) {
      if (rnd() < 0.18) continue;
      const cc = new THREE.Color(crowd[Math.floor(rnd() * crowd.length)]);
      const h = 0.75 + rnd() * 0.2;
      b.box(m, x + (rnd() - 0.5) * 0.15, y + 0.2 + h / 2, z + tread * 0.5, 0.42, h, 0.32, cc);
      b.box(m, x, y + 0.28 + h, z + tread * 0.5, 0.24, 0.24, 0.24, new THREE.Color(0xe0b48a).multiplyScalar(0.6 + rnd() * 0.5));
    }
  }
  const backZ = 1.6 + rows * tread, topY = 0.6 + rows * rise;
  b.box(m, 0, topY / 2 + 1.0, backZ + 0.2, L, topY + 2.0, 0.4, darkC);
  for (const s of [-1, 1]) b.box(m, s * (L / 2 + 0.15), (topY + 2) / 2, D / 2 + 0.3, 0.3, topY + 2, D - 1.2, darkC);
  // roof on columns, cantilevered towards the track
  const roofY = topY + 4.2;
  for (const x of [-L / 2 + 1, -L / 6, L / 6, L / 2 - 1]) b.box(m, x, roofY / 2, backZ, 0.35, roofY, 0.35, steel);
  const roof = new THREE.Matrix4().makeRotationX(-0.12);
  roof.premultiply(new THREE.Matrix4().makeTranslation(0, roofY, backZ - D / 2 + 0.5));
  b.box(new THREE.Matrix4().multiplyMatrices(m, roof), 0, 0, 0, L + 2, 0.25, D + 1.5, roofC);
  // sponsor banner along the front wall (banner mesh, shared atlas)
  const tp = (x, y, z) => new THREE.Vector3(x, y, z).applyMatrix4(m).toArray();
  const fx = L / 2 - 1;
  bannerB.quadUV(tp(fx, 0.35, 0.73), tp(-fx, 0.35, 0.73), tp(-fx, 1.45, 0.73), tp(fx, 1.45, 0.73), [0, 0.75], [1, 0.75], [1, 1], [0, 1], WHITE);
  return b.build();
}

// =============================================================================
// Scenery
// =============================================================================

function addScenery(ctx, group, keep) {
  const { theme, terrain, seed } = ctx;
  const rnd = mulberry32(seed ^ 0x9e3779b9);
  const species = theme.scenery.map((name) => SPECIES[name]);
  // cumulative weights: the big set pieces (hoodoos) are rarer than shrubs
  const wsum = species.reduce((a, sp) => a + (sp.weight ?? 1), 0);
  let acc = 0;
  const cum = species.map((sp) => (acc += (sp.weight ?? 1) / wsum));
  const { minX, maxX, minZ, maxZ } = terrain.bounds;
  const reach = 650;
  const area = (maxX - minX + 2 * reach) * (maxZ - minZ + 2 * reach);
  const spacing = Math.max(11, Math.sqrt(area / 60000));
  const maxTotal = 2600;
  const lists = species.map(() => []);
  const tufts = [];
  let total = 0;
  // Candidates first, then thin them evenly so a big map stays under the cap
  // everywhere (instead of filling up row by row and leaving the rest bare).
  const cand = [];
  let sumP = 0;
  for (let z = minZ - reach; z < maxZ + reach; z += spacing) {
    for (let x = minX - reach; x < maxX + reach; x += spacing) {
      const jx = x + (rnd() - 0.5) * spacing, jz = z + (rnd() - 0.5) * spacing;
      const e = terrain.edgeDist(jx, jz);
      if (e < 16 || e > reach) continue;
      const forest = fbm(jx * 0.004, jz * 0.004, 3, seed + 31);
      const mask = forest > 0.5 ? 1 : 0.18;
      const p = 0.5 * Math.exp(-(e - 16) / 260) * mask + 0.03;
      cand.push(jx, jz, p);
      sumP += p;
    }
  }
  const thin = Math.min(1, (maxTotal * 0.97) / Math.max(1, sumP));
  for (let c = 0; c < cand.length; c += 3) {
    const jx = cand[c], jz = cand[c + 1], p = cand[c + 2] * thin;
    const r = rnd();
    if (r > p || total >= maxTotal) continue;
    const flat = terrain.flatness(jx, jz);
    // pick a species: noise decides the local mix
    const pick = vnoise(jx * 0.01, jz * 0.01, seed + 41) * 0.6 + rnd() * 0.4;
    let sIdx = 0;
    while (sIdx < species.length - 1 && pick >= cum[sIdx]) sIdx++;
    const sp = species[sIdx];
    if (flat < sp.minFlat) continue;
    const y = terrain.heightAt(jx, jz);
    if (sp.maxHeight != null && y - terrain.base > sp.maxHeight) continue;
    if (terrain.waterY != null && (y < terrain.waterY + 0.8 || terrain.seaAt(jx, jz) > 0.12)) continue; // not in the sea or on the wet sand
    lists[sIdx].push([jx, y, jz, sp.scale[0] + rnd() * (sp.scale[1] - sp.scale[0]), rnd() * Math.PI * 2, rnd()]);
    total++;
  }
  // small tufts close to the track for ground detail
  const tuftSpec = theme.tuft;
  if (tuftSpec) {
    const tr = ctx.track;
    const tStep = Math.max(1, Math.ceil((tr.count * 2) / 4800)); // spread evenly on long tracks
    for (let i = 0; i < tr.count && tufts.length < 5000; i += tStep) {
      for (let n = 0; n < 2; n++) {
        const s = rnd() < 0.5 ? 1 : -1;
        const o = tr.hw[i] + ZONE + 1 + rnd() * 45;
        const x = tr.px[i] + tr.nx[i] * s * o + (rnd() - 0.5) * 3, z = tr.pz[i] + tr.nz[i] * s * o + (rnd() - 0.5) * 3;
        if (terrain.edgeDist(x, z) < ZONE + 1 || terrain.seaAt(x, z) > 0.12) continue;
        tufts.push([x, terrain.heightAt(x, z), z, 0.7 + rnd() * 0.8, rnd() * Math.PI * 2, rnd()]);
      }
    }
  }

  const m = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler(), sc = new THREE.Vector3(), p = new THREE.Vector3();
  const tint = new THREE.Color();
  // Split each species into a 3x3 grid of chunks so the camera and the
  // shadow pass can skip the far ones.
  const cx0 = minX - reach, cz0 = minZ - reach;
  const cw = (maxX - minX + 2 * reach) / 3, ch = (maxZ - minZ + 2 * reach) / 3;
  const place = (geo, mat, list, sp, shadow) => {
    const chunks = Array.from({ length: 9 }, () => []);
    for (const it of list) {
      const a = Math.min(2, Math.max(0, Math.floor((it[0] - cx0) / cw)));
      const c = Math.min(2, Math.max(0, Math.floor((it[2] - cz0) / ch)));
      chunks[c * 3 + a].push(it);
    }
    // Lower graphics quality draws only the first part of each chunk (World.applyDetail),
    // so put the instances in a scattered order (a hash of the position: no rnd() draws,
    // the scenery stays the same), not the row-by-row order they were generated in.
    const hash = (it) => { const v = Math.sin(it[0] * 12.9898 + it[2] * 78.233) * 43758.5453; return v - Math.floor(v); };
    for (const chunk of chunks) {
      const order = chunk.map((it) => [hash(it), it]).sort((a, b) => a[0] - b[0]).map((o) => o[1]);
      placeChunk(geo, mat, order, sp, shadow);
    }
  };
  const placeChunk = (geo, mat, list, sp, shadow) => {
    if (!list.length) return;
    const mesh = new THREE.InstancedMesh(geo, mat, list.length);
    list.forEach(([x, y, z, s, yaw, r], k) => {
      e.set((r - 0.5) * sp.tilt, yaw, (r * 7 % 1 - 0.5) * sp.tilt);
      q.setFromEuler(e);
      sc.set(s * (0.9 + r * 0.2), s * (0.85 + ((r * 13) % 1) * 0.3), s * (0.9 + ((r * 5) % 1) * 0.2));
      m.compose(p.set(x, y - sp.sink * s, z), q, sc);
      mesh.setMatrixAt(k, m);
      const br = 1 + ((r * 17) % 1 - 0.5) * sp.light * 2, warm = ((r * 3) % 1 - 0.5) * sp.hue * 4;
      tint.setRGB(br * (1 + warm), br, br * (1 - warm));
      mesh.setColorAt(k, tint);
    });
    mesh.castShadow = shadow;
    mesh.receiveShadow = !!sp.receive;
    mesh.computeBoundingSphere();
    // the graphics quality level thins these out (World.applyDetail in scene.js)
    mesh.userData.detail = shadow ? 'scenery' : 'tuft';
    mesh.userData.fullCount = list.length;
    group.add(mesh);
  };
  const mat = keep(new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.88, metalness: 0 }));
  species.forEach((sp, k) => place(keep(sp.build(ctx.seed + k)), mat, lists[k], sp, true));
  if (tuftSpec && tufts.length) {
    const tmat = keep(new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.9, side: THREE.DoubleSide }));
    // one mesh: tiny, no shadows, and mostly in view along the track anyway
    placeChunk(keep(tuftGeometry(tuftSpec)), tmat, tufts, { tilt: 0.2, sink: 0.05, hue: 0.03, light: 0.12 }, false);
  }
  ctx.sceneryCount = total + tufts.length;
}

/**
 * Theme set pieces: the lighthouse and boats (seaside) and a lit city on the
 * horizon (night). Boats and buildings are instanced and thinned by the
 * graphics quality level like the rest of the scenery.
 */
function addSetPieces(ctx, group, keep) {
  const { theme, terrain, seed } = ctx;
  const { x0, z0, W, H } = terrain.bounds;
  // scattered order, so a lower quality level (which draws the first part) thins evenly
  const scatter = (list) => list.map((it) => [Math.sin(it.x * 12.9898 + it.z * 78.233) * 43758.5453 % 1, it]).sort((a, b) => a[0] - b[0]).map((o) => o[1]);
  const instanced = (geo, mat, list, matrixOf, name) => {
    if (!list.length) return;
    const mesh = new THREE.InstancedMesh(geo, mat, list.length);
    const m = new THREE.Matrix4();
    scatter(list).forEach((it, k) => mesh.setMatrixAt(k, matrixOf(it, m)));
    mesh.computeBoundingSphere();
    mesh.name = name;
    mesh.userData.detail = 'scenery';
    mesh.userData.fullCount = list.length;
    group.add(mesh);
  };

  const pad = ctx.pads.find((p) => p.kind === 'lighthouse');
  if (pad) {
    const lh = lighthouseGeometry();
    const body = new THREE.Mesh(keep(lh.body), keep(new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.6, metalness: 0.05 })));
    const lamp = new THREE.Mesh(keep(lh.lamp), keep(new THREE.MeshStandardMaterial({ color: 0xfff3c4, emissive: 0xffd77a, emissiveIntensity: 2.6, roughness: 0.2 })));
    const yaw = Math.atan2(ctx.coast.dx, ctx.coast.dz); // the keeper's house on the landward side
    for (const mesh of [body, lamp]) {
      mesh.position.set(pad.cx, pad.y - 0.15, pad.cz);
      mesh.rotation.y = yaw;
      mesh.name = 'lighthouse';
    }
    body.castShadow = body.receiveShadow = true;
    group.add(body, lamp);
  }

  if (ctx.coast) {
    // boats out on the water, at least 3 m deep and apart from each other
    const rnd = mulberry32(seed ^ 0xb0a75);
    const boats = [];
    for (let k = 0; k < 600 && boats.length < 10; k++) {
      const x = x0 + 250 + rnd() * (W - 500), z = z0 + 250 + rnd() * (H - 500);
      if (terrain.seaAt(x, z) < 0.999 || terrain.waterY - terrain.heightAt(x, z) < 3 || terrain.edgeDist(x, z) > 900) continue;
      if (boats.some((b) => Math.hypot(b.x - x, b.z - z) < 90)) continue;
      boats.push({ x, z, yaw: rnd() * Math.PI * 2, s: 0.85 + rnd() * 0.4 });
    }
    const q = new THREE.Quaternion(), up = new THREE.Vector3(0, 1, 0), sc = new THREE.Vector3(), pos = new THREE.Vector3();
    instanced(keep(boatGeometry()), keep(new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.55, metalness: 0.05 })), boats,
      (b, m) => m.compose(pos.set(b.x, terrain.waterY - 0.35, b.z), q.setFromAxisAngle(up, b.yaw), sc.set(b.s, b.s, b.s)), 'boats');
  }

  if (theme.skyline) {
    // city blocks 450-1000 m out, in a few clusters; windows are lit by the material (skylineMaterial)
    const rnd = mulberry32(seed ^ 0x5c1e);
    const blocks = [];
    for (let k = 0; k < 9000 && blocks.length < 170; k++) {
      const x = x0 + 300 + rnd() * (W - 600), z = z0 + 300 + rnd() * (H - 600);
      const e = terrain.edgeDist(x, z);
      if (e < 450 || e > 1000 || fbm(x * 0.0022, z * 0.0022, 2, seed + 61) < 0.52) continue;
      const w = 14 + rnd() * 26, d = 14 + rnd() * 26, h = 12 + rnd() * rnd() * 120;
      if (blocks.some((b) => Math.abs(b.x - x) < (b.w + w) / 2 + 5 && Math.abs(b.z - z) < (b.d + d) / 2 + 5)) continue;
      // stand on the lowest corner of the footprint, so no block floats over a slope
      let y = Infinity;
      for (const [a, c] of [[-1, -1], [1, -1], [-1, 1], [1, 1], [0, 0]]) y = Math.min(y, terrain.heightAt(x + (a * w) / 2, z + (c * d) / 2));
      blocks.push({ x, y: y - 1.5, z, w, d, h: h + 1.5 });
    }
    const q = new THREE.Quaternion(), sc = new THREE.Vector3(), pos = new THREE.Vector3();
    instanced(keep(new THREE.BoxGeometry(1, 1, 1).translate(0, 0.5, 0)), keep(skylineMaterial()), blocks,
      (b, m) => m.compose(pos.set(b.x, b.y, b.z), q, sc.set(b.w, b.h, b.d)), 'skyline');
  }
}

/** Lighthouse: a banded, tapering tower with a gallery, a lit lantern and a keeper's house. Local +z faces the sea. */
function lighthouseGeometry() {
  const b = new GeoBuilder(), I = new THREE.Matrix4();
  const red = 0xc63a32, white = 0xf1eee6, dark = new THREE.Color(0x3a3d42);
  const H = 19, R0 = 3.0, R1 = 2.0, bands = 6;
  for (let k = 0; k < bands; k++) {
    const y0 = (k * H) / bands, y1 = ((k + 1) * H) / bands;
    const r0 = R0 + ((R1 - R0) * k) / bands, r1 = R0 + ((R1 - R0) * (k + 1)) / bands;
    b.addGeometry(paint(new THREE.CylinderGeometry(r1, r0, y1 - y0, 18, 1, true).translate(0, (y0 + y1) / 2, 0), k % 2 ? red : white, k ? 0.92 : 0.7), I);
  }
  b.addGeometry(new THREE.CylinderGeometry(3.6, 3.4, 1.2, 18).translate(0, 0.3, 0), I, new THREE.Color(0x9a958c)); // plinth
  b.addGeometry(new THREE.CylinderGeometry(2.9, 2.7, 0.4, 18).translate(0, H + 0.2, 0), I, dark);                 // gallery floor
  b.addGeometry(new THREE.CylinderGeometry(2.8, 2.8, 0.9, 18, 1, true).translate(0, H + 0.85, 0), I, dark);      // railing
  b.addGeometry(new THREE.CylinderGeometry(1.75, 1.75, 0.3, 14).translate(0, H + 3.0, 0), I, dark);              // lantern top ring
  b.addGeometry(paint(new THREE.ConeGeometry(1.95, 1.9, 14).translate(0, H + 4.1, 0), red, 0.8), I);           // roof
  b.addGeometry(new THREE.SphereGeometry(0.3, 8, 6).translate(0, H + 5.1, 0), I, dark);
  // keeper's house on the landward side, with a pitched roof
  b.box(I, 0, 1.6, -7.5, 7, 3.2, 5.5, new THREE.Color(white));
  const slope = 0.5, half = 3.3; // roof pitch (rad) and slab width; the slabs meet at the ridge, eaves at the wall tops
  for (const s of [1, -1]) {
    const m = new THREE.Matrix4().makeTranslation(0, 3.2 + half * Math.sin(slope), -7.5)
      .multiply(new THREE.Matrix4().makeRotationX(s * slope)).multiply(new THREE.Matrix4().makeTranslation(0, 0, (s * half) / 2));
    b.box(m, 0, 0, 0, 7.6, 0.25, half, new THREE.Color(red));
  }
  const lamp = new THREE.CylinderGeometry(1.45, 1.45, 2.3, 14).translate(0, H + 1.75, 0);
  return { body: b.build(), lamp };
}

/** A small sailing boat: tapered hull, cabin, mast and two flat sails. */
function boatGeometry() {
  const b = new GeoBuilder(), I = new THREE.Matrix4();
  const hull = new THREE.BoxGeometry(2.4, 1.1, 7.5, 1, 1, 2);
  const pos = hull.attributes.position;
  for (let v = 0; v < pos.count; v++) {
    const z = pos.getZ(v), y = pos.getY(v);
    let k = z > 0.1 ? 0.12 : 1;      // pointed bow
    if (y < 0) k *= 0.6;              // narrower keel
    pos.setX(v, pos.getX(v) * k);
    if (z > 0.1 && y > 0) pos.setY(v, y + 0.25); // raised bow
  }
  hull.computeVertexNormals();
  b.addGeometry(paint(hull.translate(0, 0.45, 0), 0xf3f4f6, 0.55, -0.1, 1.2), I);
  b.box(I, 0, 1.25, -1.2, 1.5, 0.6, 2.4, new THREE.Color(0x2f6fb4));
  b.addGeometry(new THREE.CylinderGeometry(0.06, 0.08, 8, 5).translate(0, 4.8, 0.4), I, new THREE.Color(0xd8d8d8));
  const sail = (h, w, z, dir) => new THREE.ConeGeometry(w, h, 3).scale(1, 1, 0.04).rotateY(Math.PI / 2).translate(0, 1.5 + h / 2, z + dir * w * 0.4);
  b.addGeometry(sail(7, 1.9, -0.6, -1), I, new THREE.Color(0xf6f3ea));
  b.addGeometry(sail(5.5, 1.3, 1.9, 1), I, new THREE.Color(0xf6f3ea));
  return b.build();
}

/**
 * Night city blocks: a dark facade with a grid of windows in world space
 * (so every block size gets the same window size), about 40 % of them lit.
 * Blocks are instanced boxes, never rotated (walls face x or z).
 */
function skylineMaterial() {
  const mat = new THREE.MeshStandardMaterial({ color: 0x1b2130, roughness: 0.8, metalness: 0.1 });
  mat.onBeforeCompile = (sh) => {
    sh.vertexShader = sh.vertexShader
      .replace('#include <common>', '#include <common>\nvarying vec3 vWinW;\nvarying vec3 vWinN;')
      .replace('#include <project_vertex>', `#include <project_vertex>
        vec4 winW = vec4(transformed, 1.0);
        #ifdef USE_INSTANCING
          winW = instanceMatrix * winW;
        #endif
        vWinW = (modelMatrix * winW).xyz;
        vWinN = objectNormal;`);
    sh.fragmentShader = sh.fragmentShader
      .replace('#include <common>', '#include <common>\nvarying vec3 vWinW;\nvarying vec3 vWinN;')
      .replace('#include <emissivemap_fragment>', `#include <emissivemap_fragment>
        {
          vec3 an = abs(vWinN);
          if (an.y < 0.5) {
            float u = an.x > an.z ? vWinW.z : vWinW.x;
            vec2 g = vec2(u / 3.4, (vWinW.y + 0.6) / 3.8), cell = floor(g), f = fract(g);
            float win = step(0.2, f.x) * step(f.x, 0.8) * step(0.28, f.y) * step(f.y, 0.78);
            float r = fract(sin(dot(cell, vec2(12.9898, 78.233)) + dot(floor(vWinW.xz / 9.0), vec2(3.17, 7.31))) * 43758.5453);
            vec3 tint = mix(vec3(1.0, 0.72, 0.38), vec3(0.75, 0.88, 1.0), step(0.85, r));
            totalEmissiveRadiance += tint * win * step(0.6, r) * (0.6 + 0.9 * fract(r * 13.7));
          }
        }`);
  };
  mat.customProgramCacheKey = () => 'skylineWindows';
  return mat;
}

/** Scenery species: procedural low-poly meshes with vertex colours. */
const SPECIES = {
  broadleaf: { scale: [0.8, 1.35], minFlat: 0.82, tilt: 0.06, sink: 0.2, hue: 0.06, light: 0.18, build: (s) => broadleafTree(s) },
  pine: { scale: [0.75, 1.4], minFlat: 0.8, tilt: 0.05, sink: 0.2, hue: 0.04, light: 0.16, build: (s) => pineTree(s, false) },
  pineSnow: { scale: [0.75, 1.45], minFlat: 0.8, tilt: 0.05, sink: 0.2, hue: 0.02, light: 0.1, maxHeight: 160, build: (s) => pineTree(s, true) },
  bush: { scale: [0.7, 1.6], minFlat: 0.75, tilt: 0.1, sink: 0.25, hue: 0.06, light: 0.18, build: (s) => bush(s, 0x4d8a36) },
  rock: { scale: [0.6, 2.6], minFlat: 0.5, tilt: 0.4, sink: 0.35, hue: 0.02, light: 0.15, receive: true, build: (s) => rock(s, 0x8a877f) },
  rockGrey: { scale: [0.7, 3.0], minFlat: 0.45, tilt: 0.4, sink: 0.35, hue: 0.02, light: 0.12, receive: true, build: (s) => rock(s, 0x7f838b) },
  rockRed: { scale: [0.6, 2.8], minFlat: 0.45, tilt: 0.4, sink: 0.35, hue: 0.03, light: 0.15, receive: true, build: (s) => rock(s, 0xa65d3c) },
  saguaro: { scale: [0.75, 1.3], minFlat: 0.85, tilt: 0.04, sink: 0.1, hue: 0.03, light: 0.12, build: (s) => saguaro(s) },
  barrel: { weight: 0.7, scale: [0.7, 1.5], minFlat: 0.8, tilt: 0.1, sink: 0.1, hue: 0.04, light: 0.12, build: (s) => barrelCactus(s) },
  shrubDry: { scale: [0.6, 1.6], minFlat: 0.7, tilt: 0.15, sink: 0.15, hue: 0.05, light: 0.15, build: (s) => bush(s, 0x8f7f4b, true) },
  hoodoo: { weight: 0.22, scale: [0.6, 1.4], minFlat: 0.6, tilt: 0.05, sink: 0.5, hue: 0.02, light: 0.1, receive: true, build: (s) => hoodoo(s) },
  juniper: { weight: 1.3, scale: [0.8, 1.5], minFlat: 0.75, tilt: 0.08, sink: 0.15, hue: 0.04, light: 0.12, build: (s) => juniper(s) },
  palm: { weight: 1.6, scale: [0.8, 1.3], minFlat: 0.8, tilt: 0.04, sink: 0.15, hue: 0.05, light: 0.14, build: (s) => palmTree(s) },
  bushCoast: { scale: [0.6, 1.4], minFlat: 0.7, tilt: 0.12, sink: 0.2, hue: 0.06, light: 0.16, build: (s) => bush(s, 0x6f8f3e, true) },
};

function broadleafTree(seed) {
  const b = new GeoBuilder();
  const I = new THREE.Matrix4();
  b.addGeometry(paint(new THREE.CylinderGeometry(0.2, 0.34, 4.4, 6).translate(0, 2.2, 0), 0x6b4a32, 0.7), I);
  const rnd = mulberry32(seed);
  const blobs = [[0, 5.7, 0, 2.3], [1.2, 5.0, 0.5, 1.7], [-1.0, 5.1, -0.6, 1.8], [0.2, 6.9, -0.2, 1.6]];
  for (const [x, y, z, r] of blobs) {
    const g = new THREE.IcosahedronGeometry(r, r > 2 ? 1 : 0);
    displace(g, 0.28 * r, seed + Math.floor(rnd() * 100));
    g.translate(x, y, z);
    b.addGeometry(paint(g, 0x4f8a3a, 0.55, 3.6, 8.5), I);
  }
  return b.build();
}

function pineTree(seed, snow) {
  const b = new GeoBuilder();
  const I = new THREE.Matrix4();
  b.addGeometry(paint(new THREE.CylinderGeometry(0.14, 0.26, 3.2, 5).translate(0, 1.6, 0), 0x5e4330, 0.7), I);
  const layers = [[2.7, 4.2, 3.9], [2.1, 3.6, 6.1], [1.4, 3.0, 8.2], [0.8, 2.2, 9.9]];
  layers.forEach(([r, h, y], k) => {
    const g = new THREE.ConeGeometry(r, h, 8, 1, true).translate(0, y, 0);
    displace(g, 0.18, seed + k * 7);
    paint(g, 0x2d5e34, 0.5, y - h / 2, y + h / 2);
    if (snow) {
      const c = g.attributes.color, pos = g.attributes.position;
      const white = new THREE.Color(0xf2f6fa), tmp = new THREE.Color();
      for (let v = 0; v < pos.count; v++) {
        const t = (pos.getY(v) - (y - h / 2)) / h;
        tmp.fromBufferAttribute(c, v).lerp(white, t > 0.15 ? 0.85 : 0.35);
        c.setXYZ(v, tmp.r, tmp.g, tmp.b);
      }
    }
    b.addGeometry(g, I);
  });
  return b.build();
}

function bush(seed, color, dry = false) {
  const b = new GeoBuilder();
  const g = new THREE.IcosahedronGeometry(1.1, 0);
  displace(g, dry ? 0.5 : 0.3, seed);
  g.scale(1.2, dry ? 0.65 : 0.8, 1.1).translate(0, 0.65, 0);
  b.addGeometry(paint(g, color, 0.55, 0, 1.4), new THREE.Matrix4());
  return b.build();
}

function rock(seed, color) {
  const b = new GeoBuilder();
  const g = new THREE.DodecahedronGeometry(1.2, 0);
  displace(g, 0.42, seed);
  g.scale(1.25, 0.75, 1.0).translate(0, 0.45, 0);
  b.addGeometry(paint(g, color, 0.75, -0.4, 1.4), new THREE.Matrix4());
  return b.build();
}

function saguaro(seed) {
  const b = new GeoBuilder();
  const I = new THREE.Matrix4();
  const green = 0x4f7d3c;
  const col = (r, h, x, y, z) => {
    b.addGeometry(paint(new THREE.CylinderGeometry(r, r * 1.08, h, 8, 1, y === 0).translate(x, y + h / 2, z), green, 0.7, 0, 8), I);
    b.addGeometry(paint(new THREE.SphereGeometry(r, 8, 3, 0, Math.PI * 2, 0, Math.PI / 2).translate(x, y + h, z), green, 0.7, 0, 8), I);
  };
  col(0.45, 6.4, 0, 0, 0);
  const rnd = mulberry32(seed);
  const arm = (side, y0, len, up) => {
    const g = new THREE.CylinderGeometry(0.3, 0.3, len, 7).rotateZ(Math.PI / 2).translate(side * len / 2, y0, 0);
    b.addGeometry(paint(g, green, 0.7, 0, 8), I);
    col(0.3, up, side * len, y0, 0);
  };
  arm(1, 2.6 + rnd() * 0.8, 1.3, 2.0 + rnd());
  arm(-1, 3.4 + rnd() * 0.8, 1.1, 1.6 + rnd());
  return b.build();
}

function barrelCactus(seed) {
  const b = new GeoBuilder();
  const g = new THREE.CylinderGeometry(0.42, 0.5, 0.9, 12, 1, true);
  const pos = g.attributes.position;
  for (let v = 0; v < pos.count; v++) {
    const x = pos.getX(v), z = pos.getZ(v);
    const a = Math.atan2(z, x), r = Math.hypot(x, z);
    if (r < 1e-3) continue;
    const k = 1 + 0.08 * Math.cos(a * 12);
    pos.setX(v, x * k); pos.setZ(v, z * k);
  }
  g.computeVertexNormals();
  g.translate(0, 0.45, 0);
  b.addGeometry(paint(g, 0x5f8a3e, 0.7, 0, 1), new THREE.Matrix4());
  const top = new THREE.SphereGeometry(0.47, 12, 2, 0, Math.PI * 2, 0, Math.PI / 2).scale(1, 0.5, 1).translate(0, 0.9, 0);
  b.addGeometry(paint(top, 0x6b9444, 0.9, 0, 1), new THREE.Matrix4());
  const rnd = mulberry32(seed);
  for (let k = 0; k < 2; k++) {
    const f = new THREE.IcosahedronGeometry(0.1, 0).translate((rnd() - 0.5) * 0.4, 1.1, (rnd() - 0.5) * 0.4);
    b.addGeometry(paint(f, k % 2 ? 0xf2c94c : 0xe0603a, 1), new THREE.Matrix4());
  }
  return b.build();
}

function hoodoo(seed) {
  const b = new GeoBuilder();
  const I = new THREE.Matrix4();
  const strata = [0xa95b36, 0xc07648, 0x9c4f30, 0xb86c42, 0xc98a5c];
  let y = 0, r = 2.6;
  const rnd = mulberry32(seed);
  for (let k = 0; k < 4; k++) {
    const h = 2.5 + rnd() * 2;
    const g = new THREE.CylinderGeometry(r * 0.82, r, h, 9, 2).translate(0, y + h / 2, 0);
    displace(g, 0.3, seed + k);
    b.addGeometry(paint(g, strata[k % strata.length], 0.85, 0, 16), I);
    y += h; r *= 0.78;
  }
  const cap = new THREE.CylinderGeometry(r * 1.8, r * 1.5, 1.4, 9).translate(0, y + 0.6, 0);
  displace(cap, 0.3, seed + 9);
  b.addGeometry(paint(cap, 0x8f4a2c, 0.9), I);
  return b.build();
}

function juniper(seed) {
  const b = new GeoBuilder();
  const I = new THREE.Matrix4();
  b.addGeometry(paint(new THREE.CylinderGeometry(0.15, 0.28, 2.2, 5).rotateZ(0.15).translate(0.1, 1.1, 0), 0x6e5a44, 0.7), I);
  for (const [x, y, z, r] of [[0.2, 2.6, 0, 1.4], [-0.7, 2.0, 0.4, 1.0], [0.8, 2.2, -0.5, 0.9]]) {
    const g = new THREE.IcosahedronGeometry(r, 1);
    displace(g, 0.3 * r, seed + Math.round(x * 10));
    g.scale(1, 0.7, 1).translate(x, y, z);
    b.addGeometry(paint(g, 0x4f5f37, 0.6, 1, 3.6), I);
  }
  return b.build();
}

/** A palm: a curved, ringed trunk and a crown of drooping fronds (each two flat blades). */
function palmTree(seed) {
  const b = new GeoBuilder();
  const rnd = mulberry32(seed);
  const segs = 7, H = 8.6;
  let x = 0, y = 0;
  for (let k = 0; k < segs; k++) {
    const h = H / segs, lean = 0.04 + k * 0.05; // leans further out towards the top
    const g = new THREE.CylinderGeometry(0.3 - (k + 1) * 0.022, 0.3 - k * 0.022, h * 1.06, 7, 1, true);
    paint(g, k % 2 ? 0x8d6c49 : 0x76583a, 0.8);
    const m = new THREE.Matrix4().makeRotationZ(-lean).setPosition(x + Math.sin(lean) * h / 2, y + Math.cos(lean) * h / 2, 0);
    b.addGeometry(g, m);
    x += Math.sin(lean) * h; y += Math.cos(lean) * h;
  }
  const blade = (len, wid) => {
    const g = new THREE.ConeGeometry(wid, len, 4, 1).rotateZ(-Math.PI / 2).scale(1, 0.14, 1).translate(len / 2, 0, 0);
    return paint(g, 0x4c8a35, 0.55, -0.2, 0.2);
  };
  const n = 8;
  for (let f = 0; f < n; f++) {
    const az = (f / n) * Math.PI * 2 + rnd() * 0.35;
    const inner = blade(2.4, 0.5), outer = blade(2.6, 0.45);
    const up = 0.2 + rnd() * 0.15, droop = -0.55 - rnd() * 0.25;
    const rot = (pitch) => new THREE.Matrix4().makeRotationY(az).multiply(new THREE.Matrix4().makeRotationZ(pitch));
    const m1 = rot(up).setPosition(x, y + 0.1, 0);
    b.addGeometry(inner, m1);
    const tip = new THREE.Vector3(2.3, 0, 0).applyMatrix4(m1);
    b.addGeometry(outer, rot(droop).setPosition(tip.x, tip.y, tip.z));
  }
  for (let k = 0; k < 3; k++) {
    const a = k * 2.1 + rnd();
    b.addGeometry(paint(new THREE.IcosahedronGeometry(0.17, 0).translate(x + Math.cos(a) * 0.32, y - 0.25, Math.sin(a) * 0.32), 0x5a4128, 0.9), new THREE.Matrix4());
  }
  return b.build();
}

function tuftGeometry(spec) {
  const pos = [], col = [];
  const base = new THREE.Color(spec.color), tip = new THREE.Color(spec.tip);
  for (let k = 0; k < 6; k++) {
    const a = (k / 6) * Math.PI * 2 + k * 0.4;
    const lean = 0.25 + (k % 3) * 0.1;
    const h = 0.45 + (k % 2) * 0.2;
    const w = 0.07;
    const cx = Math.cos(a), cz = Math.sin(a);
    pos.push(-cz * w, 0, cx * w, cz * w, 0, -cx * w, cx * lean, h, cz * lean);
    col.push(base.r, base.g, base.b, base.r, base.g, base.b, tip.r, tip.g, tip.b);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
  g.computeVertexNormals();
  // grass looks better lit from above
  const n = g.attributes.normal;
  for (let v = 0; v < n.count; v++) { n.setXYZ(v, n.getX(v) * 0.3, 1, n.getZ(v) * 0.3); }
  g.normalizeNormals();
  return g;
}

/** Give a geometry a vertex colour with a darker base (fake ambient occlusion). */
function paint(geo, hex, ao = 0.6, y0 = null, y1 = null) {
  const pos = geo.attributes.position;
  let lo = y0, hi = y1;
  if (lo == null || hi == null) {
    geo.computeBoundingBox();
    lo = geo.boundingBox.min.y; hi = geo.boundingBox.max.y;
  }
  const base = new THREE.Color(hex);
  const arr = new Float32Array(pos.count * 3);
  for (let v = 0; v < pos.count; v++) {
    const t = clamp((pos.getY(v) - lo) / Math.max(1e-3, hi - lo), 0, 1);
    const k = ao + (1 - ao) * t;
    arr[v * 3] = base.r * k; arr[v * 3 + 1] = base.g * k; arr[v * 3 + 2] = base.b * k;
  }
  geo.setAttribute('color', new THREE.BufferAttribute(arr, 3));
  return geo;
}

/** Push vertices along their direction from the centre by position-based noise (crack-free). */
function displace(geo, amount, seed) {
  const pos = geo.attributes.position;
  for (let v = 0; v < pos.count; v++) {
    const x = pos.getX(v), y = pos.getY(v), z = pos.getZ(v);
    const n = vnoise(x * 1.7 + y * 0.9, z * 1.7 - y * 1.1, seed) - 0.5;
    const l = Math.hypot(x, y, z) || 1;
    const k = 1 + (n * 2 * amount) / l;
    pos.setXYZ(v, x * k, y * k, z * k);
  }
  geo.computeVertexNormals();
}

// =============================================================================
// Geometry builder
// =============================================================================

const WHITE = new THREE.Color(1, 1, 1);
const UP = [0, 1, 0];
const _v = new THREE.Vector3(), _n = new THREE.Vector3(), _c3 = new THREE.Color();
const _m3 = new THREE.Matrix3();
let _unitBox = null;

/** Accumulates positions, normals, uvs and colours, then builds one BufferGeometry. */
class GeoBuilder {
  constructor(capacity = 4096) {
    this.cap = capacity;
    this.P = new Float32Array(capacity * 3); this.N = new Float32Array(capacity * 3);
    this.U = new Float32Array(capacity * 2); this.C = new Float32Array(capacity * 3);
    this.I = new Uint32Array(capacity * 2);
    this.n = 0; this.ni = 0;
  }
  get count() { return this.n; }
  _growV() {
    const cap = this.cap * 2;
    const g = (a, k) => { const b = new Float32Array(cap * k); b.set(a); return b; };
    this.P = g(this.P, 3); this.N = g(this.N, 3); this.U = g(this.U, 2); this.C = g(this.C, 3);
    this.cap = cap;
  }
  _idx(a, b, c) {
    if (this.ni + 3 > this.I.length) { const x = new Uint32Array(this.I.length * 2); x.set(this.I); this.I = x; }
    const I = this.I, k = this.ni;
    I[k] = a; I[k + 1] = b; I[k + 2] = c;
    this.ni = k + 3;
  }
  vert(x, y, z, nx, ny, nz, u, v, c) {
    if (this.n >= this.cap) this._growV();
    const k = this.n, k3 = k * 3, k2 = k * 2;
    this.P[k3] = x; this.P[k3 + 1] = y; this.P[k3 + 2] = z;
    this.N[k3] = nx; this.N[k3 + 1] = ny; this.N[k3 + 2] = nz;
    this.U[k2] = u; this.U[k2 + 1] = v;
    this.C[k3] = c.r; this.C[k3 + 1] = c.g; this.C[k3 + 2] = c.b;
    this.n = k + 1;
    return k;
  }
  quad(a, b, c, d) { this._idx(a, b, c); this._idx(a, c, d); }
  /** Flat-shaded quad lying on the road, facing up. */
  flatQuad(a, b, c, d, color) {
    this.quadUV(a, b, c, d, [0, 0], [1, 0], [1, 1], [0, 1], color, UP);
  }
  /**
   * Flat-shaded quad a-b-c-d. The normal comes from the corner order, or is
   * flipped to agree with `ref` if given; the winding always matches it.
   */
  quadUV(a, b, c, d, ua, ub, uc, ud, color, ref = null) {
    const ux = b[0] - a[0], uy = b[1] - a[1], uz = b[2] - a[2];
    const vx = d[0] - a[0], vy = d[1] - a[1], vz = d[2] - a[2];
    let nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
    const l = Math.hypot(nx, ny, nz) || 1;
    nx /= l; ny /= l; nz /= l;
    let flip = false;
    if (ref && nx * ref[0] + ny * ref[1] + nz * ref[2] < 0) { nx = -nx; ny = -ny; nz = -nz; flip = true; }
    const s = this.count;
    this.vert(a[0], a[1], a[2], nx, ny, nz, ua[0], ua[1], color);
    this.vert(b[0], b[1], b[2], nx, ny, nz, ub[0], ub[1], color);
    this.vert(c[0], c[1], c[2], nx, ny, nz, uc[0], uc[1], color);
    this.vert(d[0], d[1], d[2], nx, ny, nz, ud[0], ud[1], color);
    // (a,b,c) is counter-clockwise around (b-a)x(d-a)
    if (!flip) { this._idx(s, s + 1, s + 2); this._idx(s, s + 2, s + 3); }
    else { this._idx(s, s + 3, s + 2); this._idx(s, s + 2, s + 1); }
  }
  /** Quad with given per-edge normals (smooth along a sweep); winding follows the normal. */
  sweepQuad(a, b, c, d, ni, nj, color, ua, ub, uc, ud) {
    const s = this.count;
    this.vert(a[0], a[1], a[2], ni[0], ni[1], ni[2], ua[0], ua[1], color);
    this.vert(b[0], b[1], b[2], nj[0], nj[1], nj[2], ub[0], ub[1], color);
    this.vert(c[0], c[1], c[2], nj[0], nj[1], nj[2], uc[0], uc[1], color);
    this.vert(d[0], d[1], d[2], ni[0], ni[1], ni[2], ud[0], ud[1], color);
    const ux = b[0] - a[0], uy = b[1] - a[1], uz = b[2] - a[2];
    const vx = d[0] - a[0], vy = d[1] - a[1], vz = d[2] - a[2];
    const fx = uy * vz - uz * vy, fy = uz * vx - ux * vz, fz = ux * vy - uy * vx;
    if (fx * ni[0] + fy * ni[1] + fz * ni[2] >= 0) { this._idx(s, s + 1, s + 2); this._idx(s, s + 2, s + 3); }
    else { this._idx(s, s + 3, s + 2); this._idx(s, s + 2, s + 1); }
  }
  /** Append a geometry transformed by m; color overrides (or multiplies) its vertex colours. */
  addGeometry(geo, m, color = null) {
    const p = geo.attributes.position, n = geo.attributes.normal, uv = geo.attributes.uv, c = geo.attributes.color;
    _m3.getNormalMatrix(m);
    const s = this.count;
    for (let k = 0; k < p.count; k++) {
      _v.fromBufferAttribute(p, k).applyMatrix4(m);
      if (n) _n.fromBufferAttribute(n, k).applyMatrix3(_m3).normalize(); else _n.set(0, 1, 0);
      if (c) { _c3.fromBufferAttribute(c, k); if (color) _c3.multiply(color); } else _c3.copy(color ?? WHITE);
      this.vert(_v.x, _v.y, _v.z, _n.x, _n.y, _n.z, uv ? uv.getX(k) : 0, uv ? uv.getY(k) : 0, _c3);
    }
    if (geo.index) { const a = geo.index.array; for (let k = 0; k < a.length; k += 3) this._idx(s + a[k], s + a[k + 1], s + a[k + 2]); }
    else for (let k = 0; k < p.count; k += 3) this._idx(s + k, s + k + 1, s + k + 2);
  }
  /** Axis-aligned box in the frame m: centre (x,y,z), size (sx,sy,sz). */
  box(m, x, y, z, sx, sy, sz, color) {
    _unitBox = _unitBox ?? new THREE.BoxGeometry(1, 1, 1);
    const t = new THREE.Matrix4().makeTranslation(x, y, z).multiply(new THREE.Matrix4().makeScale(sx, sy, sz));
    this.addGeometry(_unitBox, new THREE.Matrix4().multiplyMatrices(m, t), color);
  }
  build() {
    const g = new THREE.BufferGeometry();
    const n = this.n;
    g.setAttribute('position', new THREE.BufferAttribute(this.P.slice(0, n * 3), 3));
    g.setAttribute('normal', new THREE.BufferAttribute(this.N.slice(0, n * 3), 3));
    g.setAttribute('uv', new THREE.BufferAttribute(this.U.slice(0, n * 2), 2));
    g.setAttribute('color', new THREE.BufferAttribute(this.C.slice(0, n * 3), 3));
    const idx = n > 65535 ? this.I.slice(0, this.ni) : Uint16Array.from(this.I.subarray(0, this.ni));
    g.setIndex(new THREE.BufferAttribute(idx, 1));
    g.computeBoundingSphere();
    return g;
  }
}

// =============================================================================
// Procedural textures (shared by every track, created once)
// =============================================================================

const TEX = {};

function makeCanvas(w, h) {
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  return c;
}

function asphaltTextures() {
  if (TEX.asphalt) return TEX.asphalt;
  const S = 512;
  const rnd = mulberry32(77);
  const hgt = new Float32Array(S * S);
  const cc = makeCanvas(S, S), rc = makeCanvas(S, S), nc = makeCanvas(S, S);
  const cg = cc.getContext('2d'), rg = rc.getContext('2d'), ng = nc.getContext('2d');
  const ci = cg.createImageData(S, S), ri = rg.createImageData(S, S), ni = ng.createImageData(S, S);
  for (let y = 0; y < S; y++) {
    for (let x = 0; x < S; x++) {
      const k = y * S + x;
      const blot = fbmP((x / S) * 6, (y / S) * 6, 6, 4, 11);
      const grain = rnd();
      const speck = rnd() < 0.02 ? 1 : 0;
      hgt[k] = grain * 0.7 + speck * 0.9 + blot * 0.4;
      const g = 54 + (blot - 0.5) * 30 + (grain - 0.5) * 26 + speck * 36;
      ci.data[k * 4] = g - 1; ci.data[k * 4 + 1] = g; ci.data[k * 4 + 2] = g + 4; ci.data[k * 4 + 3] = 255;
      const r = clamp(215 + (blot - 0.5) * 70 + (grain - 0.5) * 34 - speck * 40, 0, 255);
      ri.data[k * 4] = r; ri.data[k * 4 + 1] = r; ri.data[k * 4 + 2] = r; ri.data[k * 4 + 3] = 255;
    }
  }
  for (let y = 0; y < S; y++) {
    for (let x = 0; x < S; x++) {
      const k = y * S + x;
      const dx = hgt[y * S + ((x + 1) % S)] - hgt[y * S + ((x + S - 1) % S)];
      const dy = hgt[((y + 1) % S) * S + x] - hgt[((y + S - 1) % S) * S + x];
      let nx = -dx * 1.2, ny = -dy * 1.2, nz = 1;
      const l = Math.hypot(nx, ny, nz);
      nx /= l; ny /= l; nz /= l;
      ni.data[k * 4] = (nx * 0.5 + 0.5) * 255; ni.data[k * 4 + 1] = (ny * 0.5 + 0.5) * 255;
      ni.data[k * 4 + 2] = (nz * 0.5 + 0.5) * 255; ni.data[k * 4 + 3] = 255;
    }
  }
  cg.putImageData(ci, 0, 0); rg.putImageData(ri, 0, 0); ng.putImageData(ni, 0, 0);
  const tex = (c, srgb) => {
    const t = new THREE.CanvasTexture(c);
    t.wrapS = t.wrapT = THREE.RepeatWrapping;
    t.anisotropy = 8;
    t.colorSpace = srgb ? THREE.SRGBColorSpace : THREE.NoColorSpace;
    return t;
  };
  TEX.asphalt = { map: tex(cc, true), rough: tex(rc, false), normal: tex(nc, false) };
  return TEX.asphalt;
}

/** Grey detail noise (multiplies vertex colours of terrain and concrete). */
function detailTexture() {
  if (TEX.detail) return TEX.detail;
  const S = 256;
  const c = makeCanvas(S, S), g = c.getContext('2d');
  const img = g.createImageData(S, S);
  const rnd = mulberry32(5);
  for (let y = 0; y < S; y++) {
    for (let x = 0; x < S; x++) {
      const k = (y * S + x) * 4;
      const n = fbmP((x / S) * 8, (y / S) * 8, 8, 4, 3);
      const v = clamp(0.86 + (n - 0.5) * 0.36 + (rnd() - 0.5) * 0.08, 0, 1) * 255;
      img.data[k] = v; img.data[k + 1] = v; img.data[k + 2] = v; img.data[k + 3] = 255;
    }
  }
  g.putImageData(img, 0, 0);
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.anisotropy = 8;
  t.colorSpace = THREE.NoColorSpace;
  TEX.detail = t;
  return t;
}

function checkerTexture() {
  if (TEX.checker) return TEX.checker;
  const c = makeCanvas(64, 64), g = c.getContext('2d');
  for (let x = 0; x < 2; x++) for (let y = 0; y < 2; y++) {
    g.fillStyle = (x + y) % 2 ? '#141414' : '#f2f2f2';
    g.fillRect(x * 32, y * 32, 32, 32);
  }
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 8;
  TEX.checker = t;
  return t;
}

function chevronTexture() {
  if (TEX.chevron) return TEX.chevron;
  const c = makeCanvas(256, 128), g = c.getContext('2d');
  g.fillStyle = '#d4232b';
  g.fillRect(0, 0, 256, 128);
  g.fillStyle = '#ffffff';
  for (const x0 of [40, 140]) {
    g.beginPath();
    g.moveTo(x0, 16); g.lineTo(x0 + 40, 16); g.lineTo(x0 + 84, 64); g.lineTo(x0 + 40, 112); g.lineTo(x0, 112); g.lineTo(x0 + 44, 64);
    g.closePath();
    g.fill();
  }
  g.strokeStyle = '#ffffff'; g.lineWidth = 6; g.strokeRect(3, 3, 250, 122);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 8;
  TEX.chevron = t;
  return t;
}

/** Four fictional sponsor banners in one atlas (rows from the top). */
function bannerTexture() {
  if (TEX.banner) return TEX.banner;
  const c = makeCanvas(1024, 512), g = c.getContext('2d');
  const rows = [
    { bg: ['#123a8f', '#1d5fd6'], fg: '#ffffff', accent: '#ffc83d', text: 'TRACK RUSH' },
    { bg: ['#f5c400', '#ffd84a'], fg: '#111111', accent: '#111111', text: 'NEURO RACING' },
    { bg: ['#b3121b', '#e3262f'], fg: '#ffffff', accent: '#ffffff', text: 'GRIP+ TYRES' },
    { bg: ['#16181d', '#2a2f39'], fg: '#ffffff', accent: '#2ed15a', text: 'FULL THROTTLE' },
  ];
  rows.forEach((r, k) => {
    const y = k * 128;
    const grad = g.createLinearGradient(0, y, 0, y + 128);
    grad.addColorStop(0, r.bg[1]); grad.addColorStop(1, r.bg[0]);
    g.fillStyle = grad;
    g.fillRect(0, y, 1024, 128);
    g.fillStyle = r.accent;
    g.fillRect(0, y + 112, 1024, 8);
    g.beginPath(); g.moveTo(40, y + 100); g.lineTo(90, y + 28); g.lineTo(120, y + 28); g.lineTo(70, y + 100); g.fill();
    g.beginPath(); g.moveTo(904, y + 100); g.lineTo(954, y + 28); g.lineTo(984, y + 28); g.lineTo(934, y + 100); g.fill();
    g.fillStyle = r.fg;
    g.font = 'italic 900 78px system-ui, "Segoe UI", Arial, sans-serif';
    g.textAlign = 'center';
    g.textBaseline = 'middle';
    g.fillText(r.text, 512, y + 62);
  });
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 8;
  TEX.banner = t;
  return t;
}

function glowTexture() {
  if (TEX.glow) return TEX.glow;
  const c = makeCanvas(128, 128), g = c.getContext('2d');
  const grad = g.createRadialGradient(64, 64, 0, 64, 64, 64);
  grad.addColorStop(0, 'rgba(255,255,255,1)');
  grad.addColorStop(0.35, 'rgba(255,255,255,0.55)');
  grad.addColorStop(1, 'rgba(0,0,0,0)');
  g.fillStyle = '#000';
  g.fillRect(0, 0, 128, 128);
  g.fillStyle = grad;
  g.fillRect(0, 0, 128, 128);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  TEX.glow = t;
  return t;
}

/** Tileable ripple normals for the sea (repeats every 24 m on the 32 km water disc). */
function waterNormalTexture() {
  if (TEX.water) return TEX.water;
  const S = 256;
  const c = makeCanvas(S, S), g = c.getContext('2d');
  const img = g.createImageData(S, S);
  const hgt = new Float32Array(S * S);
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    hgt[y * S + x] = fbmP((x / S) * 5, (y / S) * 5, 5, 4, 91) + 0.4 * fbmP((x / S) * 12, (y / S) * 12, 12, 3, 92);
  }
  for (let y = 0; y < S; y++) {
    for (let x = 0; x < S; x++) {
      const k = (y * S + x) * 4;
      const dx = hgt[y * S + ((x + 1) % S)] - hgt[y * S + ((x + S - 1) % S)];
      const dy = hgt[((y + 1) % S) * S + x] - hgt[((y + S - 1) % S) * S + x];
      let nx = -dx * 6, ny = -dy * 6, nz = 1;
      const l = Math.hypot(nx, ny, nz);
      nx /= l; ny /= l; nz /= l;
      img.data[k] = (nx * 0.5 + 0.5) * 255; img.data[k + 1] = (ny * 0.5 + 0.5) * 255; img.data[k + 2] = (nz * 0.5 + 0.5) * 255; img.data[k + 3] = 255;
    }
  }
  g.putImageData(img, 0, 0);
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.repeat.set(32000 / 24, 32000 / 24);
  t.anisotropy = 8;
  t.colorSpace = THREE.NoColorSpace;
  TEX.water = t;
  return t;
}

/** Gate banners for one track: one row per gate. */
function gateAtlas(defs, theme) {
  const RH = 128;
  const c = makeCanvas(1024, RH * defs.length), g = c.getContext('2d');
  defs.forEach((d, k) => {
    const y = k * RH;
    const grad = g.createLinearGradient(0, y, 0, y + RH);
    grad.addColorStop(0, '#2a2f3a'); grad.addColorStop(1, '#10131a');
    g.fillStyle = grad;
    g.fillRect(0, y, 1024, RH);
    if (d.kind === 'start') {
      for (let x = 0; x < 6; x++) for (let r = 0; r < 4; r++) {
        g.fillStyle = (x + r) % 2 ? '#111' : '#f4f4f4';
        g.fillRect(x * 21, y + r * 32, 21, 32);
        g.fillRect(1024 - 126 + x * 21, y + r * 32, 21, 32);
      }
    } else {
      g.fillStyle = '#19d3ff';
      g.fillRect(0, y, 24, RH); g.fillRect(1000, y, 24, RH);
      g.fillRect(36, y + 20, 8, RH - 40); g.fillRect(980, y + 20, 8, RH - 40);
    }
    g.fillStyle = '#ffffff';
    g.font = `italic 900 ${d.kind === 'start' ? 76 : 70}px system-ui, "Segoe UI", Arial, sans-serif`;
    g.textAlign = 'center';
    g.textBaseline = 'middle';
    g.fillText(d.label, 512, y + RH / 2 + 3);
  });
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 8;
  return t;
}

// =============================================================================
// Small maths helpers: noise, smoothing
// =============================================================================

function clamp(v, a, b) { return v < a ? a : v > b ? b : v; }
function smoothstep(a, b, x) { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); }

function mulberry32(a) {
  return function () {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function hash2(ix, iz, seed) {
  let h = Math.imul(ix, 0x27d4eb2d) ^ Math.imul(iz, 0x165667b1) ^ Math.imul(seed, 0x9e3779b1);
  h = Math.imul(h ^ (h >>> 15), 0x85ebca6b);
  h = Math.imul(h ^ (h >>> 13), 0xc2b2ae35);
  h ^= h >>> 16;
  return (h >>> 0) / 4294967296;
}

/** 2D value noise in 0..1. */
function vnoise(x, z, seed) {
  const ix = Math.floor(x), iz = Math.floor(z);
  const fx = x - ix, fz = z - iz;
  const ux = fx * fx * (3 - 2 * fx), uz = fz * fz * (3 - 2 * fz);
  const a = hash2(ix, iz, seed), b = hash2(ix + 1, iz, seed), c = hash2(ix, iz + 1, seed), d = hash2(ix + 1, iz + 1, seed);
  return a + (b - a) * ux + (c - a) * uz + (a - b - c + d) * ux * uz;
}

function fbm(x, z, oct, seed) {
  let v = 0, a = 0.5, f = 1, norm = 0;
  for (let k = 0; k < oct; k++) {
    v += a * vnoise(x * f, z * f, seed + k * 101);
    norm += a; a *= 0.5; f *= 2.03;
  }
  return v / norm;
}

/** Tileable value noise / fbm (period in lattice cells) for textures. */
function vnoiseP(x, y, P, seed) {
  const ix = Math.floor(x), iy = Math.floor(y);
  const fx = x - ix, fy = y - iy;
  const ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy);
  const w = (i) => ((i % P) + P) % P;
  const a = hash2(w(ix), w(iy), seed), b = hash2(w(ix + 1), w(iy), seed);
  const c = hash2(w(ix), w(iy + 1), seed), d = hash2(w(ix + 1), w(iy + 1), seed);
  return a + (b - a) * ux + (c - a) * uy + (a - b - c + d) * ux * uy;
}

function fbmP(x, y, P, oct, seed) {
  let v = 0, a = 0.5, f = 1, norm = 0;
  for (let k = 0; k < oct; k++) {
    v += a * vnoiseP(x * f, y * f, P * f, seed + k * 13);
    norm += a; a *= 0.5; f *= 2;
  }
  return v / norm;
}

function erode(a, r, closed) {
  const n = a.length, out = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    let m = Infinity;
    for (let k = -r; k <= r; k++) {
      let j = i + k;
      if (closed) j = ((j % n) + n) % n;
      else if (j < 0 || j >= n) continue;
      if (a[j] < m) m = a[j];
    }
    out[i] = m;
  }
  return out;
}

function blur(a, r, closed) {
  const n = a.length, out = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    let s = 0, c = 0;
    for (let k = -r; k <= r; k++) {
      let j = i + k;
      if (closed) j = ((j % n) + n) % n;
      else if (j < 0 || j >= n) continue;
      s += a[j]; c++;
    }
    out[i] = s / c;
  }
  return out;
}

function dilateMask(m, r, closed) {
  const n = m.length, src = Uint8Array.from(m);
  for (let i = 0; i < n; i++) {
    if (src[i]) continue;
    for (let k = -r; k <= r; k++) {
      let j = i + k;
      if (closed) j = ((j % n) + n) % n;
      else if (j < 0 || j >= n) continue;
      if (src[j]) { m[i] = 1; break; }
    }
  }
}

function removeShortRuns(m, minLen) {
  const n = m.length;
  let i = 0;
  while (i < n) {
    if (!m[i]) { i++; continue; }
    let j = i;
    while (j < n && m[j]) j++;
    if (j - i < minLen && !(i === 0 || j === n)) for (let k = i; k < j; k++) m[k] = 0;
    i = j;
  }
}
