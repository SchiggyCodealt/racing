/**
 * carMesh.js
 * ------------------------------------------------------------------
 * Car visuals:
 *   - CarModel:   a detailed procedural race car (player, watched AI, ghost)
 *                 with steering/spinning wheels, brake lights, body attitude,
 *                 tyre smoke, skid marks, wall sparks and nitro flames; v4:
 *                 in the shape of one of the four cars of cars.js (SHAPES,
 *                 one model with different proportions and parts)
 *   - AIFleet:    up to hundreds of cars drawn with a few InstancedMeshes
 *                 (plus one shared spark pool with a fixed budget)
 *   - SensorRays: the AI's distance rays drawn as lines
 *
 * Car frame: x = left, y = up, z = forward; the origin is on the road
 * surface between the axles.
 *
 * v2 car fields are used when present, each with a v1 fallback:
 *   steerAngle (front wheel angle, + left), wheelRot (wheel spin angle),
 *   pitch (+ nose up) and roll (+ left side up) as the body attitude
 *   relative to the horizontal (road slope and banking included),
 *   braking (brake lights), slip 0..1 (smoke and skid marks).
 * v3 wall fields (wallImpact, wallScrape, wallX/Z, wallNx/Nz, with wallHits
 * to count new contact steps) drive the sparks, see wallEvents(); a ghost
 * model never makes sparks. v4 nitro fields (boost 0..1, boosting) light the
 * flames at the tail pipes, see NitroFlame.
 */
import * as THREE from '../../vendor/three.module.min.js';
import { SENSOR_ANGLES } from '../ai/sensors.js';
import { CAR } from '../physics/car.js';
import { getCar, DEFAULT_CAR } from '../physics/cars.js';

const WHEELS = [
  // x, z, radius, width, front
  [0.86, 1.45, 0.37, 0.3, true], [-0.86, 1.45, 0.37, 0.3, true],
  [0.86, -1.42, 0.4, 0.36, false], [-0.86, -1.42, 0.4, 0.36, false],
];

/** Visual pitch/roll from the road under the car (v1 behaviour, fallback). */
function carTilt(car, track, out) {
  const i = car.idx, j = track.closed ? (i + 1) % track.N : Math.min(i + 1, track.count - 1);
  const slope = (track.py[j] - track.py[i]) / track.segLen;
  const rel = Math.cos(car.yaw - Math.atan2(track.tx[i], track.tz[i]));
  out.pitch = Math.atan(slope * rel); // + = nose up
  out.roll = -car.bank * rel;          // + = left side up
  return out;
}

/** Body attitude (pitch + nose up, roll + left up) from v2 fields or the road. */
function attitude(car, track, out) {
  if (car.pitch !== undefined && car.roll !== undefined) {
    out.pitch = car.pitch;
    out.roll = car.roll;
    return out;
  }
  return carTilt(car, track, out);
}

// =============================================================================
// Procedural geometry
// =============================================================================

/**
 * Loft a smooth body through cross-sections (superellipses) along z.
 * stations: [{z, x, y, w, h, n}] with z ascending; w/h are half sizes.
 */
function loft(stations, ring = 18, steps = 3) {
  const rows = [];
  const keys = ['z', 'x', 'y', 'w', 'h', 'n'];
  const S = stations.length;
  for (let s = 0; s < S - 1; s++) {
    const p0 = stations[Math.max(0, s - 1)], p1 = stations[s], p2 = stations[s + 1], p3 = stations[Math.min(S - 1, s + 2)];
    for (let t = 0; t < steps; t++) {
      const u = t / steps, u2 = u * u, u3 = u2 * u;
      const r = {};
      for (const k of keys) {
        r[k] = 0.5 * (2 * p1[k] + (-p0[k] + p2[k]) * u + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * u2 + (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * u3);
      }
      rows.push(r);
    }
  }
  rows.push(stations[S - 1]);
  const pos = [], idx = [];
  const ringPts = (r) => {
    const pts = [];
    for (let k = 0; k < ring; k++) {
      const a = (k / ring) * Math.PI * 2;
      const c = Math.cos(a), s = Math.sin(a), e = 2 / r.n;
      pts.push([r.x + r.w * Math.sign(c) * Math.abs(c) ** e, r.y + r.h * Math.sign(s) * Math.abs(s) ** e, r.z]);
    }
    return pts;
  };
  rows.forEach((r) => ringPts(r).forEach((p) => pos.push(...p)));
  for (let r = 0; r < rows.length - 1; r++) {
    for (let k = 0; k < ring; k++) {
      const a = r * ring + k, b = r * ring + ((k + 1) % ring), c = b + ring, d = a + ring;
      idx.push(a, b, c, a, c, d);
    }
  }
  // end caps with their own vertices (hard edge)
  for (const [r, front] of [[rows[0], false], [rows[rows.length - 1], true]]) {
    const base = pos.length / 3;
    pos.push(r.x, r.y, r.z);
    ringPts(r).forEach((p) => pos.push(...p));
    for (let k = 0; k < ring; k++) {
      const a = base + 1 + k, b = base + 1 + ((k + 1) % ring);
      if (front) idx.push(base, a, b); else idx.push(base, b, a);
    }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setIndex(idx);
  g.computeVertexNormals();
  return g;
}

/** Mirror stations to the other side (x -> -x). */
const mirrorX = (st) => st.map((s) => ({ ...s, x: -s.x }));

/** Merge geometries (position + normal only) into one indexed geometry. */
function merge(geos) {
  let nv = 0, ni = 0;
  for (const g of geos) {
    nv += g.attributes.position.count;
    ni += g.index ? g.index.count : g.attributes.position.count;
  }
  const pos = new Float32Array(nv * 3), nor = new Float32Array(nv * 3);
  const idx = nv > 65535 ? new Uint32Array(ni) : new Uint16Array(ni);
  let ov = 0, oi = 0;
  for (const g of geos) {
    if (!g.attributes.normal) g.computeVertexNormals();
    pos.set(g.attributes.position.array, ov * 3);
    nor.set(g.attributes.normal.array, ov * 3);
    const n = g.attributes.position.count;
    if (g.index) for (let k = 0; k < g.index.count; k++) idx[oi++] = g.index.getX(k) + ov;
    else for (let k = 0; k < n; k++) idx[oi++] = ov + k;
    ov += n;
    g.dispose();
  }
  const out = new THREE.BufferGeometry();
  out.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  out.setAttribute('normal', new THREE.BufferAttribute(nor, 3));
  out.setIndex(new THREE.BufferAttribute(idx, 1));
  out.computeBoundingSphere();
  return out;
}

const box = (sx, sy, sz, x, y, z) => new THREE.BoxGeometry(sx, sy, sz).translate(x, y, z);
const ST = (z, x, y, w, h, n = 5) => ({ z, x, y, w, h, n }); // a loft station

// =============================================================================
// Car shapes (v4)
// =============================================================================

/** The racer's glass canopy (also drawn by the AI fleet). */
function canopyStations() {
  const S = (z, w, h, y, n = 3) => ({ z, x: 0, y, w, h, n });
  return [S(-1.25, 0.22, 0.06, 0.74), S(-0.95, 0.36, 0.16, 0.8), S(-0.5, 0.42, 0.24, 0.84), S(0.1, 0.42, 0.24, 0.84), S(0.6, 0.36, 0.16, 0.78), S(0.95, 0.18, 0.04, 0.7)];
}

/**
 * The four cars of src/physics/cars.js are one detailed model with different
 * proportions and parts (each car's look.shape). Every part is laid out in the
 * racer's frame and then stretched by warp(): x × width, y × height + lift,
 * z × front (z > 0) or rear (z < 0), so the parts stay in place on each body.
 * Only the drawing changes: every car has the racer's collision capsule
 * (CAR.radius, CAR.halfLength), and the bodies stay within ~0.2 m of the racer's.
 *
 *   front, rear, width, height  stretch factors; lift (m) raises the body off the wheels
 *   track     wheel x as a share of the stretched racer's (narrow or wide track)
 *   wheels    [front radius, front width, rear radius, rear width] (m)
 *   haunch    rear fender width factor (fat rear tyres)
 *   glass     the glass (loft stations {z, x, y, w, h, n}); mirror: where the door mirrors sit [x, y, z]
 *   stripes   x of each livery stripe on the tub (stripeW: half width; stripeAccent: in the
 *             accent colour, else white on dark paint and dark on light paint, as in v3)
 *   exhausts  tail pipes [x, y, z of the pipe end, radius]: the nitro flames come out of them
 *   rain      the rain light [x, y, z]
 *   parts     extra parts, one material each (paint, accent, carbon, glass or head):
 *             {loft: stations} | {box: [sx, sy, sz]} | {wing: [span, chord, thickness]} |
 *             {hoop: [radius, tube]} (upright half ring) | {lamp: [radius, depth]} (facing
 *             forwards) | {fin: true} (the racer's engine-cover fin); placed at `at` [x, y, z]
 *             after a tilt of rx (rad, about x); sym: also mirrored to -x; flat: left out of
 *             the side view (carProfile)
 */
const SHAPES = {
  // the v3 sports car exactly as it was: low wedge, bubble canopy, rear wing on swan necks, fin
  racer: {
    front: 1, rear: 1, width: 1, height: 1, lift: 0, track: 1, haunch: 1,
    wheels: [0.37, 0.3, 0.4, 0.36],
    glass: canopyStations(), mirror: [0.64, 0.85, 0.46],
    stripes: [0], stripeW: 0.15, stripeAccent: false,
    exhausts: [[0.22, 0.38, -2.42, 0.05], [-0.22, 0.38, -2.42, 0.05]],
    rain: [0, 0.98, -2.24],
    parts: [
      { mat: 'carbon', wing: [1.9, 0.5, 0.09], at: [0, 1.06, -1.88] },
      { mat: 'carbon', wing: [1.86, 0.22, 0.05], at: [0, 1.2, -2.26] },
      { mat: 'carbon', box: [0.04, 0.42, 0.14], at: [0.3, 0.88, -1.95], sym: true }, // wing pylons
      { mat: 'paint', fin: true },
      { mat: 'paint', box: [0.035, 0.42, 0.62], at: [0.97, 1.08, -2.12], sym: true }, // wing end plates
    ],
  },
  // small, short, low roadster: open cockpit with a wraparound screen, roll hoops, ducktail lip, narrow track
  kestrel: {
    front: 0.88, rear: 0.86, width: 0.94, height: 0.94, lift: -0.01, track: 0.97, haunch: 1,
    wheels: [0.34, 0.26, 0.355, 0.29],
    glass: [ST(0.26, 0, 0.8, 0.44, 0.08, 3), ST(0.32, 0, 0.8, 0.5, 0.11, 3), ST(0.45, 0, 0.77, 0.5, 0.09, 3), ST(0.56, 0, 0.73, 0.48, 0.05, 3), ST(0.66, 0, 0.69, 0.42, 0.015, 3)],
    mirror: [0.6, 0.78, 0.5],
    stripes: [0], stripeW: 0.13, stripeAccent: true,
    exhausts: [[0.1, 0.34, -2.42, 0.045], [-0.1, 0.34, -2.42, 0.045]],
    rain: [0, 0.74, -2.37],
    parts: [
      // open cockpit (a dark well in the deck), two headrest fairings and roll hoops behind the seats
      { mat: 'carbon', flat: true, loft: [ST(-0.85, 0, 0.79, 0.3, 0.03, 4), ST(-0.6, 0, 0.8, 0.42, 0.035, 4), ST(-0.1, 0, 0.765, 0.43, 0.035, 4), ST(0.22, 0, 0.73, 0.36, 0.03, 4)] },
      { mat: 'paint', sym: true, loft: [ST(-1.85, 0.22, 0.76, 0.04, 0.02, 3), ST(-1.35, 0.22, 0.78, 0.1, 0.07, 3), ST(-0.85, 0.22, 0.8, 0.13, 0.13, 3), ST(-0.66, 0.22, 0.8, 0.12, 0.14, 3)] },
      { mat: 'accent', hoop: [0.13, 0.022], at: [0.22, 0.86, -0.6], sym: true },
      { mat: 'accent', wing: [1.36, 0.2, 0.045], at: [0, 0.77, -2.12], rx: 0.3 }, // ducktail lip
    ],
  },
  // long, wide grand tourer: cabin set back (long bonnet), fat rear tyres, big wing, splitter, four pipes
  thunder: {
    front: 1.06, rear: 1.02, width: 1.03, height: 0.97, lift: 0, track: 1, haunch: 1.08,
    wheels: [0.38, 0.32, 0.42, 0.46],
    glass: [ST(-1.85, 0, 0.75, 0.2, 0.05, 3), ST(-1.5, 0, 0.79, 0.34, 0.12, 3), ST(-0.95, 0, 0.83, 0.42, 0.2, 3), ST(-0.3, 0, 0.84, 0.43, 0.22, 3), ST(0.2, 0, 0.78, 0.38, 0.16, 3), ST(0.55, 0, 0.7, 0.2, 0.04, 3)],
    mirror: [0.62, 0.84, 0.12],
    stripes: [0.14, -0.14], stripeW: 0.055, stripeAccent: true,
    exhausts: [[0.16, 0.42, -2.42, 0.048], [0.3, 0.42, -2.42, 0.048], [-0.16, 0.42, -2.42, 0.048], [-0.3, 0.42, -2.42, 0.048]],
    rain: [0, 0.74, -2.37],
    parts: [
      { mat: 'carbon', wing: [2.0, 0.6, 0.1], at: [0, 1.2, -1.84] },
      { mat: 'carbon', wing: [1.96, 0.26, 0.05], at: [0, 1.36, -2.26], rx: 0.2 },
      { mat: 'carbon', box: [0.045, 0.56, 0.18], at: [0.42, 0.95, -1.98], sym: true },
      { mat: 'accent', box: [0.04, 0.38, 0.6], at: [1.02, 1.24, -2.08], sym: true }, // wing end plates
      { mat: 'carbon', box: [1.95, 0.035, 0.3], at: [0, 0.13, 2.35] },           // splitter
      { mat: 'carbon', box: [0.04, 0.12, 0.3], at: [0.94, 0.3, 2.16], sym: true }, // dive planes
    ],
  },
  // tall rally hatchback: raised ride, boxy greenhouse with a roof, scoop, roof spoiler, light pod, mud flaps
  drifter: {
    front: 0.9, rear: 0.88, width: 0.97, height: 1, lift: 0.09, track: 1, haunch: 1,
    wheels: [0.37, 0.27, 0.37, 0.27],
    glass: [ST(-2.14, 0, 0.8, 0.48, 0.04, 4), ST(-1.95, 0, 1.02, 0.56, 0.24, 4), ST(-1.4, 0, 1.02, 0.6, 0.3, 4), ST(-0.4, 0, 1.02, 0.6, 0.3, 4), ST(0.2, 0, 1.0, 0.58, 0.28, 4), ST(0.85, 0, 0.74, 0.46, 0.04, 4)],
    mirror: [0.68, 0.98, 0.5],
    stripes: [0], stripeW: 0.12, stripeAccent: true,
    exhausts: [[-0.55, 0.3, -2.42, 0.065]],
    rain: [0, 0.74, -2.37],
    parts: [
      { mat: 'paint', loft: [ST(-1.95, 0, 1.27, 0.52, 0.02, 4), ST(-1.8, 0, 1.31, 0.6, 0.035, 4), ST(-0.4, 0, 1.33, 0.61, 0.035, 4), ST(0.1, 0, 1.3, 0.59, 0.03, 4), ST(0.22, 0, 1.28, 0.5, 0.01, 4)] }, // roof
      { mat: 'accent', loft: [ST(-0.55, 0, 1.36, 0.12, 0.02, 4), ST(-0.3, 0, 1.38, 0.16, 0.05, 4), ST(0.0, 0, 1.39, 0.17, 0.06, 4), ST(0.08, 0, 1.385, 0.16, 0.055, 4)] }, // roof scoop
      { mat: 'paint', box: [0.05, 0.56, 0.3], at: [0.6, 1.02, -1.62], sym: true },  // C-pillars ...
      { mat: 'paint', box: [0.05, 0.56, 0.1], at: [0.6, 1.02, -0.62], sym: true },  // ... and B-pillars
      { mat: 'accent', wing: [1.24, 0.34, 0.05], at: [0, 1.33, -1.72], rx: 0.15 }, // roof spoiler
      { mat: 'paint', box: [0.03, 0.14, 0.36], at: [0.62, 1.31, -1.9], sym: true },
      { mat: 'carbon', box: [1.12, 0.12, 0.07], at: [0, 0.56, 1.72] },              // light pod on the bonnet
      { mat: 'head', lamp: [0.075, 0.05], at: [0.17, 0.56, 1.765], sym: true },
      { mat: 'head', lamp: [0.075, 0.05], at: [0.43, 0.56, 1.765], sym: true },
      { mat: 'accent', box: [0.3, 0.26, 0.025], at: [0.85, 0.2, 0.92], sym: true },  // mud flaps
      { mat: 'accent', box: [0.3, 0.26, 0.025], at: [0.85, 0.2, -1.95], sym: true },
    ],
  },
};

/** The shape of car `id` (unknown ids: the racer's). */
function shapeOf(id) {
  return Object.hasOwn(SHAPES, id) ? SHAPES[id] : SHAPES.racer;
}

const isRacerFrame = (s) => s.front === 1 && s.rear === 1 && s.width === 1 && s.height === 1 && !s.lift;

/** Stretch a geometry laid out in the racer's frame onto shape `s` (in place; the racer's is left as it is). */
function warp(geo, s) {
  if (isRacerFrame(s)) return geo;
  const p = geo.attributes.position.array;
  for (let i = 0; i < p.length; i += 3) {
    p[i] *= s.width;
    p[i + 1] = s.lift + p[i + 1] * s.height;
    p[i + 2] *= p[i + 2] > 0 ? s.front : s.rear;
  }
  geo.attributes.position.needsUpdate = true;
  geo.computeVertexNormals();
  geo.computeBoundingSphere();
  return geo;
}

/** A point of the racer's frame on shape `s` (as warp). */
const warpPoint = (s, x, y, z) => [x * s.width, s.lift + y * s.height, z * (z > 0 ? s.front : s.rear)];

/** Wheels of shape `s`: [x, z, radius, width, front] like WHEELS. */
function wheelLayout(s) {
  const [fr, fw, rr, rw] = s.wheels;
  return WHEELS.map(([x, z, , , front]) => [x * s.width * s.track, z * (z > 0 ? s.front : s.rear), front ? fr : rr, front ? fw : rw, front]);
}

/** Tail pipe ends of shape `s` in the body frame: [x, y, z, radius]. */
function nozzles(s) {
  return s.exhausts.map(([x, y, z, r]) => [...warpPoint(s, x, y, z), r]);
}

/** Painted body panels: tub, fenders, side pods (superellipse sections), and the livery stripes. */
function bodyStations(shape = SHAPES.racer) {
  const S = ST;
  const tub = [
    S(-2.36, 0, 0.47, 0.5, 0.2), S(-2.2, 0, 0.5, 0.58, 0.26), S(-1.6, 0, 0.52, 0.62, 0.28), S(-0.9, 0, 0.5, 0.64, 0.3),
    S(0.0, 0, 0.46, 0.64, 0.28), S(0.7, 0, 0.42, 0.62, 0.24), S(1.3, 0, 0.37, 0.6, 0.19), S(1.9, 0, 0.32, 0.58, 0.14, 4.5),
    S(2.3, 0, 0.29, 0.5, 0.1, 4), S(2.47, 0, 0.27, 0.36, 0.06, 3),
  ];
  const frontFender = [
    S(0.5, 0.79, 0.47, 0.05, 0.04, 3), S(0.68, 0.8, 0.5, 0.16, 0.11, 4), S(1.0, 0.8, 0.57, 0.24, 0.2), S(1.45, 0.81, 0.6, 0.26, 0.21), S(1.9, 0.8, 0.55, 0.25, 0.19),
    S(2.25, 0.78, 0.45, 0.2, 0.13, 4), S(2.42, 0.74, 0.37, 0.12, 0.07, 3),
  ];
  const sidePod = [
    S(-1.05, 0.76, 0.52, 0.26, 0.26), S(-0.6, 0.75, 0.44, 0.26, 0.24), S(0.1, 0.74, 0.42, 0.26, 0.22), S(0.6, 0.74, 0.43, 0.22, 0.2),
    S(0.85, 0.74, 0.45, 0.12, 0.12, 4),
  ];
  let rearFender = [
    S(-2.36, 0.78, 0.53, 0.18, 0.14, 4), S(-2.15, 0.8, 0.58, 0.25, 0.22), S(-1.75, 0.81, 0.63, 0.28, 0.24), S(-1.42, 0.82, 0.64, 0.29, 0.25),
    S(-1.0, 0.8, 0.6, 0.28, 0.24), S(-0.62, 0.78, 0.52, 0.2, 0.16, 4), S(-0.38, 0.77, 0.47, 0.06, 0.05, 3),
  ];
  // fat rear tyres: wider haunches, grown outwards
  if (shape.haunch !== 1) rearFender = rearFender.map((s) => ({ ...s, x: s.x + (shape.haunch - 1) * s.w, w: s.w * shape.haunch }));
  // livery stripes: thin bands just proud of the tub's top surface
  const stripes = shape.stripes.map((x) => tub.slice(1, -1).map((t) => S(t.z, x, t.y + t.h - 0.025, shape.stripeW, 0.035, 4)));
  return { tub, frontFender, sidePod, rearFender, stripes };
}

/** Airfoil wing extruded across the car. */
function wingGeometry(span, chord, thick) {
  const sh = new THREE.Shape();
  sh.moveTo(0, 0);
  sh.bezierCurveTo(chord * 0.25, thick * 1.2, chord * 0.7, thick * 0.9, chord, thick * 0.2);
  sh.lineTo(chord, 0);
  sh.bezierCurveTo(chord * 0.7, -thick * 0.15, chord * 0.25, -thick * 0.25, 0, 0);
  const g = new THREE.ExtrudeGeometry(sh, { depth: span, bevelEnabled: false, curveSegments: 6 });
  // shape is in x(chord)/y; extrusion along z -> rotate so chord runs backwards (-z) and span along x
  g.translate(0, 0, -span / 2);
  g.rotateY(Math.PI / 2);
  return g;
}

/** The racer's engine-cover fin, outline in (z, y). */
const FIN = [[-0.9, 0.95], [-2.05, 1.12], [-2.15, 0.7], [-0.9, 0.7]];

function finGeometry() {
  const fin = new THREE.Shape();
  FIN.forEach(([z, y], k) => (k ? fin.lineTo(z, y) : fin.moveTo(z, y)));
  // shape x is the car's z; rotating -90 degrees about y maps shape x to z and the extrusion to -x
  return new THREE.ExtrudeGeometry(fin, { depth: 0.04, bevelEnabled: false }).rotateY(-Math.PI / 2).translate(0.02, 0, 0);
}

/** The extra parts of `shape` made of material `mat` (racer frame, not warped yet). */
function partGeometries(shape, mat, detail = 1) {
  const out = [];
  for (const p of shape.parts) {
    if (p.mat !== mat) continue;
    for (const s of p.sym ? [1, -1] : [1]) {
      let g;
      if (p.loft) g = loft(s > 0 ? p.loft : mirrorX(p.loft), detail ? 18 : 10, detail ? 3 : 1);
      else if (p.box) g = new THREE.BoxGeometry(...p.box);
      else if (p.wing) g = wingGeometry(...p.wing);
      else if (p.hoop) g = new THREE.TorusGeometry(p.hoop[0], p.hoop[1], 6, detail ? 14 : 8, Math.PI);
      else if (p.lamp) g = new THREE.CylinderGeometry(p.lamp[0], p.lamp[0], p.lamp[1], detail ? 14 : 8).rotateX(Math.PI / 2);
      else if (p.fin) g = finGeometry();
      else continue;
      if (p.rx) g.rotateX(p.rx);
      if (p.at) g.translate(s * p.at[0], p.at[1], p.at[2]);
      out.push(g);
    }
  }
  return out;
}

function paintGeometry(detail = 1, shape = SHAPES.racer) {
  const st = bodyStations(shape);
  const ring = detail ? 18 : 10, steps = detail ? 3 : 1;
  const parts = [
    loft(st.tub, ring, steps),
    loft(st.frontFender, ring, steps), loft(mirrorX(st.frontFender), ring, steps),
    loft(st.sidePod, ring, steps), loft(mirrorX(st.sidePod), ring, steps),
    loft(st.rearFender, ring, steps), loft(mirrorX(st.rearFender), ring, steps),
    // the racer: engine-cover fin and wing end plates
    ...partGeometries(shape, 'paint', detail),
  ];
  return warp(merge(parts), shape);
}

function stripeGeometry(shape = SHAPES.racer) {
  return warp(merge(bodyStations(shape).stripes.map((st) => loft(st, 12, 3))), shape);
}

function carbonGeometry(detail = 1, shape = SHAPES.racer) {
  const parts = [];
  // floor with a front splitter
  const fl = new THREE.Shape();
  fl.moveTo(-0.9, -2.25); fl.lineTo(0.9, -2.25); fl.lineTo(0.9, 2.2); fl.quadraticCurveTo(0.86, 2.5, 0.4, 2.52);
  fl.lineTo(-0.4, 2.52); fl.quadraticCurveTo(-0.86, 2.5, -0.9, 2.2); fl.lineTo(-0.9, -2.25);
  const floor = new THREE.ExtrudeGeometry(fl, { depth: 0.05, bevelEnabled: false });
  floor.rotateX(Math.PI / 2).translate(0, 0.16, 0);
  parts.push(floor);
  // the racer: rear wing on swan-neck pylons
  parts.push(...partGeometries(shape, 'carbon', detail));
  // diffuser fins
  for (const x of [-0.6, -0.2, 0.2, 0.6]) parts.push(box(0.03, 0.22, 0.4, x, 0.25, -2.12));
  // side intakes and mirror stalks
  const [mx, my, mz] = shape.mirror;
  for (const s of [1, -1]) {
    parts.push(box(0.04, 0.2, 0.06, s * 0.72, 0.42, 0.83));
    parts.push(box(0.03, 0.03, 0.14, s * (mx - 0.09), my - 0.02, mz + 0.04));
  }
  if (detail) {
    // exhausts
    for (const [x, y, z, r] of shape.exhausts) parts.push(new THREE.CylinderGeometry(r, r, 0.2, 10).rotateX(Math.PI / 2).translate(x, y, z + 0.1));
  }
  return warp(merge(parts), shape);
}

function glassGeometry(shape = SHAPES.racer) {
  return warp(merge([loft(shape.glass, 20, 3), ...partGeometries(shape, 'glass')]), shape);
}

/** Parts in the car's accent colour, or null when it has none. */
function accentGeometry(shape = SHAPES.racer) {
  const parts = partGeometries(shape, 'accent');
  return parts.length ? warp(merge(parts), shape) : null;
}

function mirrorGeometry(shape = SHAPES.racer) {
  const parts = [];
  const [mx, my, mz] = shape.mirror;
  for (const s of [1, -1]) parts.push(new THREE.SphereGeometry(0.07, 10, 6).scale(1.4, 0.7, 1.1).translate(s * mx, my, mz));
  return warp(merge(parts), shape);
}

/** Tyre (lathe), rim with spokes, and brake disc + caliper. Rim face towards +x. */
function wheelGeometries(R, W) {
  const tp = [
    [0.25, -W / 2], [R - 0.05, -W / 2], [R - 0.012, -W / 2 + 0.03], [R, -W / 2 + 0.08],
    [R, W / 2 - 0.08], [R - 0.012, W / 2 - 0.03], [R - 0.05, W / 2], [0.25, W / 2],
  ].map(([r, a]) => new THREE.Vector2(r, a));
  const tyre = new THREE.LatheGeometry(tp, 28).rotateZ(-Math.PI / 2);
  const rp = [
    [0.0, W / 2 - 0.05], [0.07, W / 2 - 0.05], [0.08, W / 2 - 0.1], [0.23, W / 2 - 0.12], [0.25, W / 2 - 0.03], [0.25, -W / 2 + 0.03], [0.22, -W / 2 + 0.03],
  ].map(([r, a]) => new THREE.Vector2(r, a));
  const rimParts = [new THREE.LatheGeometry(rp, 28).rotateZ(-Math.PI / 2)];
  for (let k = 0; k < 6; k++) {
    const sp = new THREE.BoxGeometry(0.035, 0.16, 0.045).translate(W / 2 - 0.085, 0.15, 0);
    sp.rotateX((k / 6) * Math.PI * 2);
    rimParts.push(sp);
  }
  rimParts.push(new THREE.CylinderGeometry(0.035, 0.035, 0.03, 10).rotateZ(Math.PI / 2).translate(W / 2 - 0.035, 0, 0));
  const rim = merge(rimParts);
  const disc = new THREE.CylinderGeometry(0.21, 0.21, 0.028, 24).rotateZ(Math.PI / 2).translate(-W / 2 + 0.11, 0, 0);
  const caliper = new THREE.BoxGeometry(0.07, 0.15, 0.12).translate(-W / 2 + 0.11, 0.17, -0.1);
  // vertex colours: grey disc, red caliper
  const tint = (g, c) => {
    const col = new THREE.Color(c), n = g.attributes.position.count, a = new Float32Array(n * 3);
    for (let k = 0; k < n; k++) { a[k * 3] = col.r; a[k * 3 + 1] = col.g; a[k * 3 + 2] = col.b; }
    g.setAttribute('color', new THREE.BufferAttribute(a, 3));
    return g;
  };
  tint(disc, 0x8a8d93); tint(caliper, 0xd8322b);
  const brakeCol = new Float32Array([...disc.attributes.color.array, ...caliper.attributes.color.array]);
  const brake = merge([disc, caliper]);
  brake.setAttribute('color', new THREE.BufferAttribute(brakeCol, 3));
  return { tyre, rim, brake };
}

function lightGeometries(shape = SHAPES.racer) {
  const head = [], tail = [];
  for (const s of [1, -1]) {
    head.push(new THREE.SphereGeometry(0.1, 12, 6).scale(1.5, 0.42, 0.85).rotateX(-0.55).translate(s * 0.79, 0.485, 2.31));
    head.push(box(0.2, 0.018, 0.05, s * 0.79, 0.555, 2.2).rotateX(0)); // daytime running light
  }
  head.push(...partGeometries(shape, 'head')); // the rally car's light pod
  tail.push(box(1.9, 0.045, 0.03, 0, 0.6, -2.375)); // full-width light blade
  for (const s of [1, -1]) tail.push(box(0.05, 0.16, 0.03, s * 0.86, 0.55, -2.37));
  tail.push(box(0.12, 0.06, 0.04, ...shape.rain)); // rain light (the racer: on the wing pylons)
  return { head: warp(merge(head), shape), tail: warp(merge(tail), shape) };
}

/**
 * Side view of car `id` for the menu's car picker (plain numbers, no Three.js
 * objects), from the same shape data as the 3D model: {parts: [{mat, pts}],
 * wheels: [[z, radius], ...]} in metres (z forward, y up). Each part is a
 * polygon of [z, y] points; mat is 'glass', 'paint', 'accent', 'carbon' or
 * 'head'. Draw the parts in order, then the wheels on top.
 */
export function carProfile(id) {
  const s = shapeOf(id);
  const P = (z, y) => { const p = warpPoint(s, 0, y, z); return [+p[2].toFixed(3), +p[1].toFixed(3)]; };
  const side = (st) => [...st.map((t) => P(t.z, t.y + t.h)), ...st.slice().reverse().map((t) => P(t.z, t.y - t.h))];
  const rect = (z, y, dz, dy) => [P(z - dz, y - dy), P(z + dz, y - dy), P(z + dz, y + dy), P(z - dz, y + dy)];
  const b = bodyStations(s);
  const parts = [{ mat: 'glass', pts: side(s.glass) }];
  for (const st of [b.sidePod, b.rearFender, b.frontFender, b.tub]) parts.push({ mat: 'paint', pts: side(st) });
  parts.push({ mat: 'carbon', pts: rect(0.13, 0.135, 2.38, 0.025) }); // floor
  for (const p of s.parts) {
    if (p.flat) continue;
    const [, y, z] = p.at ?? [0, 0, 0];
    let pts;
    if (p.loft) pts = side(p.loft);
    else if (p.box) pts = rect(z, y, p.box[2] / 2, p.box[1] / 2);
    else if (p.hoop) pts = rect(z, y + (p.hoop[0] + p.hoop[1]) / 2, p.hoop[1], (p.hoop[0] + p.hoop[1]) / 2);
    else if (p.lamp) pts = rect(z, y, p.lamp[1] / 2, p.lamp[0]);
    else if (p.fin) pts = FIN.map(([fz, fy]) => P(fz, fy));
    else if (p.wing) {
      const [, chord, thick] = p.wing, a = p.rx ?? 0;
      const tz = z - chord * Math.cos(a), ty = y + chord * Math.sin(a);
      pts = [P(z, y), P(z - chord * 0.3, y + thick), P(tz, ty + thick * 0.25), P(tz, ty), P(z - chord * 0.3, y - thick * 0.2)];
    }
    if (pts) parts.push({ mat: p.mat, pts });
  }
  const wheels = wheelLayout(s).filter((w) => w[0] > 0).map(([, z, R]) => [+z.toFixed(3), R]);
  return { parts, wheels };
}

let _glowTex = null;
function blobTexture() {
  if (_glowTex) return _glowTex;
  const c = document.createElement('canvas');
  c.width = c.height = 64;
  const g = c.getContext('2d');
  const grad = g.createRadialGradient(32, 32, 0, 32, 32, 32);
  grad.addColorStop(0, 'rgba(0,0,0,0.75)');
  grad.addColorStop(0.6, 'rgba(0,0,0,0.35)');
  grad.addColorStop(1, 'rgba(0,0,0,0)');
  g.fillStyle = grad;
  g.fillRect(0, 0, 64, 64);
  _glowTex = new THREE.CanvasTexture(c);
  return _glowTex;
}

// =============================================================================
// Tyre smoke and skid marks (world space, pooled)
// =============================================================================

const SMOKE_VERT = /* glsl */`
  attribute vec3 iPos;
  attribute vec2 iData; // size, alpha
  varying vec2 vUv;
  varying float vAlpha;
  void main() {
    vUv = position.xy;
    vAlpha = iData.y;
    vec4 mv = viewMatrix * vec4(iPos, 1.0);
    mv.xy += position.xy * iData.x;
    gl_Position = projectionMatrix * mv;
  }`;
const SMOKE_FRAG = /* glsl */`
  uniform vec3 color;
  varying vec2 vUv;
  varying float vAlpha;
  void main() {
    float d = length(vUv) * 2.0;
    float a = smoothstep(1.0, 0.15, d) * vAlpha;
    if (a < 0.004) discard;
    gl_FragColor = vec4(color, a);
    #include <colorspace_fragment>
  }`;

/** Keep an effect mesh in world space even though it hangs under the car root. */
function worldSpace(obj) {
  obj.matrixAutoUpdate = false;
  obj.matrix.identity();
  obj.matrixWorld.identity();
  obj.updateMatrixWorld = () => {};
  obj.updateWorldMatrix = () => {};
  obj.frustumCulled = false;
  return obj;
}

class TyreSmoke {
  constructor(max = 48) {
    this.max = max;
    const g = new THREE.InstancedBufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute([-0.5, -0.5, 0, 0.5, -0.5, 0, 0.5, 0.5, 0, -0.5, 0.5, 0], 3));
    g.setIndex([0, 1, 2, 0, 2, 3]);
    this.pos = new Float32Array(max * 3);
    this.data = new Float32Array(max * 2);
    g.setAttribute('iPos', new THREE.InstancedBufferAttribute(this.pos, 3).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('iData', new THREE.InstancedBufferAttribute(this.data, 2).setUsage(THREE.DynamicDrawUsage));
    g.instanceCount = max;
    this.mat = new THREE.ShaderMaterial({
      uniforms: { color: { value: new THREE.Color(0xd9dadc) } },
      vertexShader: SMOKE_VERT, fragmentShader: SMOKE_FRAG,
      transparent: true, depthWrite: false,
    });
    this.mesh = worldSpace(new THREE.Mesh(g, this.mat));
    this.mesh.renderOrder = 3;
    this.geo = g;
    this.p = Array.from({ length: max }, () => ({ life: 0, max: 1, x: 0, y: 0, z: 0, vx: 0, vy: 0, vz: 0, s0: 0.5, a: 0 }));
    this.next = 0;
    this.acc = 0;
  }

  emit(x, y, z, vx, vz, strength) {
    const p = this.p[this.next];
    this.next = (this.next + 1) % this.max;
    p.life = p.max = 0.9 + Math.random() * 0.6;
    p.x = x + (Math.random() - 0.5) * 0.3; p.y = y + 0.25; p.z = z + (Math.random() - 0.5) * 0.3;
    p.vx = vx * 0.25 + (Math.random() - 0.5) * 1.2; p.vy = 0.6 + Math.random() * 0.6; p.vz = vz * 0.25 + (Math.random() - 0.5) * 1.2;
    p.s0 = 0.6 + Math.random() * 0.4;
    p.a = 0.16 + 0.24 * strength;
  }

  update(dt) {
    let alive = 0;
    for (let k = 0; k < this.max; k++) {
      const p = this.p[k];
      if (p.life > 0) {
        p.life -= dt;
        const drag = Math.exp(-dt * 1.8);
        p.vx *= drag; p.vz *= drag; p.vy *= Math.exp(-dt * 0.8);
        p.x += p.vx * dt; p.y += p.vy * dt; p.z += p.vz * dt;
      }
      const t = p.life > 0 ? 1 - p.life / p.max : 1;
      this.pos[k * 3] = p.x; this.pos[k * 3 + 1] = p.y; this.pos[k * 3 + 2] = p.z;
      this.data[k * 2] = p.s0 + t * 2.2;
      this.data[k * 2 + 1] = p.life > 0 ? p.a * (1 - t) * Math.min(1, t * 8) : 0;
      if (p.life > 0) alive++;
    }
    this.mesh.visible = alive > 0;
    this.geo.attributes.iPos.needsUpdate = true;
    this.geo.attributes.iData.needsUpdate = true;
  }

  dispose() { this.geo.dispose(); this.mat.dispose(); }
}

class SkidMarks {
  constructor(segments = 220) {
    this.max = segments;
    const g = new THREE.BufferGeometry();
    this.pos = new Float32Array(segments * 4 * 3);
    this.col = new Float32Array(segments * 4 * 4);
    const idx = new Uint16Array(segments * 6);
    for (let k = 0; k < segments; k++) {
      const v = k * 4;
      idx.set([v, v + 1, v + 2, v, v + 2, v + 3], k * 6);
    }
    g.setAttribute('position', new THREE.BufferAttribute(this.pos, 3).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('color', new THREE.BufferAttribute(this.col, 4).setUsage(THREE.DynamicDrawUsage));
    g.setIndex(new THREE.BufferAttribute(idx, 1));
    this.mat = new THREE.MeshBasicMaterial({
      color: 0x0d0d0d, vertexColors: true, transparent: true, depthWrite: false,
      polygonOffset: true, polygonOffsetFactor: -6, polygonOffsetUnits: -6,
    });
    this.mesh = worldSpace(new THREE.Mesh(g, this.mat));
    this.mesh.renderOrder = 1;
    this.geo = g;
    this.next = 0;
    this.last = [null, null];
  }

  /** Add a strip piece for wheel w from its last point to (x,y,z); side vector (sx,sz). */
  add(w, x, y, z, sx, sz, alpha) {
    const l = this.last[w];
    if (l && (x - l[0]) ** 2 + (z - l[2]) ** 2 < 0.25) return;
    if (l && (x - l[0]) ** 2 + (z - l[2]) ** 2 < 9) {
      const k = this.next;
      this.next = (this.next + 1) % this.max;
      const hw = 0.13;
      const P = this.pos, C = this.col, v = k * 12;
      P[v] = l[0] + l[3] * hw; P[v + 1] = l[1]; P[v + 2] = l[2] + l[4] * hw;
      P[v + 3] = l[0] - l[3] * hw; P[v + 4] = l[1]; P[v + 5] = l[2] - l[4] * hw;
      P[v + 6] = x - sx * hw; P[v + 7] = y; P[v + 8] = z - sz * hw;
      P[v + 9] = x + sx * hw; P[v + 10] = y; P[v + 11] = z + sz * hw;
      const c = k * 16;
      for (let q = 0; q < 4; q++) { C[c + q * 4] = 1; C[c + q * 4 + 1] = 1; C[c + q * 4 + 2] = 1; C[c + q * 4 + 3] = q < 2 ? l[5] : alpha; }
      this.geo.attributes.position.needsUpdate = true;
      this.geo.attributes.color.needsUpdate = true;
      this.mesh.visible = true;
    }
    this.last[w] = [x, y, z, sx, sz, alpha];
  }

  lift(w) { this.last[w] = null; }

  clear() {
    this.col.fill(0);
    this.geo.attributes.color.needsUpdate = true;
    this.last = [null, null];
  }

  dispose() { this.geo.dispose(); this.mat.dispose(); }
}

// =============================================================================
// Wall sparks (world space, pooled)
// =============================================================================

const STEP = 1 / 60;                     // the physics step (wallHits counts steps)
const CORE = CAR.halfLength - CAR.radius; // half length of the physics capsule's core segment
const SPARK_Y = 0.45;                    // m above the car's base: bumper height, as car.wallY
const BURST_MIN = 3;    // m/s into the wall for a burst (grinding into a wall gives at most ~2.4 per step)
const SCRAPE_MIN = 3;   // m/s along the wall for a stream
let sparkShare = 1;     // emission share for the graphics quality (setSparkQuality)

/** Share of the full spark emission to use (1 high, less on lower graphics quality). */
export function setSparkQuality(share) {
  sparkShare = Math.max(0, Math.min(1, +share || 0));
}

/** Per-car bookkeeping for wallEvents(). */
export function newWallState() {
  return { ready: false, hits: 0, vx: 0, vz: 0, x: 0, z: 0, touching: false, impact: 0, scrape: 0, acc: 0 };
}

/**
 * What a car's wall contact did since the last frame, from the v3 car fields.
 * car.wallImpact covers only the latest physics step, and a frame can run
 * several steps (slow screens, Fast training) or none (fast screens, which
 * draw the same step twice), so new contact steps are counted with
 * car.wallHits; a hit in a step that wasn't drawn is estimated from the speed
 * into the wall seen on the frame before (within ~0.5 m/s of wallImpact).
 * Returns the number of new contact steps (0: nothing new), and leaves the
 * hit's speed into the wall (m/s) in st.impact and the scrape speed (m/s) in
 * st.scrape. A new car, a jump of 20+ m (restart, respawn, another car in
 * the same view object) or st.ready = false starts over without an event.
 */
export function wallEvents(st, car) {
  const hits = car.wallHits ?? 0;
  const jump = (car.x - st.x) ** 2 + (car.z - st.z) ** 2 > 400;
  let steps = st.ready && !jump ? hits - st.hits : 0;
  if (steps < 0 || steps > 60) steps = 0;
  st.impact = 0;
  st.scrape = car.hitWall ? car.wallScrape ?? 0 : 0;
  if (steps > 0) {
    let imp = car.wallImpact ?? 0;
    if (!st.touching) imp = Math.max(imp, -(st.vx * (car.wallNx ?? 0) + st.vz * (car.wallNz ?? 0)));
    st.impact = imp;
  } else if (!st.ready || jump) {
    st.acc = 0;
  }
  st.ready = true;
  st.hits = hits;
  st.vx = car.vx; st.vz = car.vz;
  st.x = car.x; st.z = car.z;
  st.touching = !!car.hitWall;
  return steps;
}

/**
 * Where the drawn car touches the wall. car.wallX/Z is from the latest physics
 * step, up to a step ahead of the interpolated car that is drawn, so it is slid
 * along the wall into the span of the drawn car's capsule (exact for a corner
 * hit, within a step's travel for a car scraping side-on). Writes out.x/y/z,
 * a few cm off the wall so the barrier doesn't hide the spark.
 */
function contactPoint(x, y, z, yaw, car, out) {
  const nx = car.wallNx, nz = car.wallNz, tx = -nz, tz = nx;
  const fx = Math.sin(yaw) * CORE, fz = Math.cos(yaw) * CORE;
  const s0 = (x - fx - car.wallX) * tx + (z - fz - car.wallZ) * tz;
  const s1 = (x + fx - car.wallX) * tx + (z + fz - car.wallZ) * tz;
  const s = Math.max(Math.min(s0, s1), Math.min(Math.max(s0, s1), 0));
  out.x = car.wallX + tx * s + nx * 0.06;
  out.y = y + SPARK_Y;
  out.z = car.wallZ + tz * s + nz * 0.06;
  return out;
}

const _cp = { x: 0, y: 0, z: 0 };

/**
 * Sparks for one car's wall contact this frame (after wallEvents returned
 * `steps` > 0): a burst for a hit, scaled by its speed into the wall, and a
 * stream while scraping, scaled by the sliding speed (and by `rate`).
 * (x, y, z, yaw) is the drawn car. Spawns at most `cap`; returns how many it
 * spawned. Both shrink with the graphics quality (setSparkQuality).
 */
function emitSparks(sparks, st, steps, car, x, y, z, yaw, cap, rate = 1) {
  if (!(cap > 0) || (car.wallNx === 0 && car.wallNz === 0)) return 0;
  const q = sparkShare;
  let burst = 0, stream = 0;
  if (st.impact >= BURST_MIN) burst = Math.round(Math.min(64, 8 + st.impact * 3) * q);
  if (st.scrape > SCRAPE_MIN) {
    st.acc += steps * STEP * Math.min(200, (st.scrape - SCRAPE_MIN) * 4.5) * q * rate;
    stream = Math.floor(st.acc);
    st.acc -= stream;
  } else {
    st.acc = 0;
  }
  burst = Math.min(burst, cap);
  stream = Math.min(stream, cap - burst);
  if (burst + stream <= 0) return 0;
  const c = contactPoint(x, y, z, yaw, car, _cp);
  const nx = car.wallNx, nz = car.wallNz, tx = -nz, tz = nx;
  const cvx = car.vx, cvz = car.vz;
  const floor = y + 0.03;
  const R = Math.random;
  for (let k = 0; k < burst; k++) {
    // a fan off the wall and upwards, carried along a little by the car
    const sp = 3.5 + R() * Math.min(11, 3 + st.impact * 0.5);
    const a = 0.2 + R() * 0.8, u = 0.4 + R() * 1.1, t = (R() - 0.5) * 1.8;
    const l = Math.hypot(a, u, t);
    const m = 0.25 + R() * 0.35;
    sparks.spawn(c.x, c.y + (R() - 0.5) * 0.2, c.z,
      cvx * m + ((nx * a + tx * t) / l) * sp, (u / l) * sp, cvz * m + ((nz * a + tz * t) / l) * sp,
      0.3 + R() * 0.35, 0.85 + R() * 0.15, floor);
  }
  const span = steps * STEP;
  for (let k = 0; k < stream; k++) {
    // shaved off along the wall: most of the car's speed, a little off the wall and up;
    // spread over the frame's steps so a stream doesn't come out in clumps
    const m = 0.45 + R() * 0.4;
    const vx = cvx * m + nx * (0.3 + R() * 1.9) + (R() - 0.5) * 1.6;
    const vy = 0.6 + R() * 2.6;
    const vz = cvz * m + nz * (0.3 + R() * 1.9) + (R() - 0.5) * 1.6;
    const age = R() * span;
    sparks.spawn(c.x + (vx - cvx) * age, c.y + (R() - 0.5) * 0.25 + vy * age, c.z + (vz - cvz) * age,
      vx, vy, vz, 0.2 + R() * 0.3 - age, 0.7 + R() * 0.3, floor);
  }
  return burst + stream;
}

const SPARK_VERT = /* glsl */`
  attribute vec3 iHead;
  attribute vec3 iTail;
  attribute vec3 iData; // half width (m), heat 0..1, brightness 0..1
  varying vec2 vUv;
  varying float vHeat;
  varying float vBright;
  void main() {
    // a streak from tail to head, turned to face the camera
    vec4 h = viewMatrix * vec4(iHead, 1.0);
    vec4 t = viewMatrix * vec4(iTail, 1.0);
    vec2 d = h.xy - t.xy;
    float len = length(d);
    vec2 dir = len > 1e-5 ? d / len : vec2(1.0, 0.0);
    // half width; at least about a pixel wide in the distance, so far sparks don't shimmer
    float w = max(iData.x, -h.z * 0.0012);
    vec4 p = mix(t, h, position.x);
    p.xy += dir * (position.x * 2.0 - 1.0) * w + vec2(-dir.y, dir.x) * position.y * w;
    vUv = position.xy;
    vHeat = iData.y;
    vBright = iData.z;
    gl_Position = projectionMatrix * p;
  }`;
const SPARK_FRAG = /* glsl */`
  varying vec2 vUv;
  varying float vHeat;
  varying float vBright;
  void main() {
    float across = abs(vUv.y);
    float a = (1.0 - across * across) * mix(0.3, 1.0, vUv.x) * vBright;
    if (a < 0.004) discard;
    // orange when fresh, cooling to dull red, with a yellow-white hot core line (that blooms)
    vec3 col = vHeat > 0.5 ? mix(vec3(1.0, 0.3, 0.04), vec3(1.0, 0.5, 0.1), vHeat * 2.0 - 1.0)
                           : mix(vec3(0.6, 0.08, 0.02), vec3(1.0, 0.3, 0.04), vHeat * 2.0);
    col = col * (0.8 + 1.2 * vHeat) + vec3(1.0, 0.85, 0.55) * smoothstep(0.6, 0.0, across) * vHeat * 1.4;
    // premultiplied: the colour adds light, alpha dims what is behind a little,
    // so sparks still read as orange in front of snow or a bright sky
    gl_FragColor = vec4(col * a, a * 0.5);
    #include <tonemapping_fragment>
    #include <colorspace_fragment>
  }`;

/**
 * A fixed pool of sparks drawn as glowing streaks in one draw call. Live
 * sparks are packed at the front of the arrays (only those are drawn); a full
 * pool reuses slots in turn, so the budget never grows. Sparks fall with
 * gravity, slow down in the air, bounce low off the road and cool down over
 * their 0.2-0.65 s life. They move in render time (frame dt), so they are
 * smooth whatever the physics step.
 */
class Sparks {
  constructor(max) {
    this.max = max;
    this.n = 0;
    this.cursor = 0;
    const g = new THREE.InstancedBufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute([0, -1, 0, 1, -1, 0, 1, 1, 0, 0, 1, 0], 3));
    g.setIndex([0, 1, 2, 0, 2, 3]);
    this.head = new Float32Array(max * 3);
    this.tail = new Float32Array(max * 3);
    this.data = new Float32Array(max * 3);
    g.setAttribute('iHead', new THREE.InstancedBufferAttribute(this.head, 3).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('iTail', new THREE.InstancedBufferAttribute(this.tail, 3).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('iData', new THREE.InstancedBufferAttribute(this.data, 3).setUsage(THREE.DynamicDrawUsage));
    g.instanceCount = 0;
    this.geo = g;
    this.mat = new THREE.ShaderMaterial({
      vertexShader: SPARK_VERT, fragmentShader: SPARK_FRAG,
      transparent: true, depthWrite: false,
      blending: THREE.CustomBlending, blendSrc: THREE.OneFactor, blendDst: THREE.OneMinusSrcAlphaFactor,
    });
    this.mesh = worldSpace(new THREE.Mesh(g, this.mat));
    this.mesh.renderOrder = 4;
    this.mesh.visible = false;
    // state: position, velocity, life left, full life, heat, road height
    this.p = new Float32Array(max * 3);
    this.v = new Float32Array(max * 3);
    this.life = new Float32Array(max);
    this.full = new Float32Array(max);
    this.heat = new Float32Array(max);
    this.floor = new Float32Array(max);
  }

  spawn(x, y, z, vx, vy, vz, life, heat, floor) {
    if (!(life > 0)) return;
    let k = this.n;
    if (k < this.max) this.n++;
    else { k = this.cursor; this.cursor = (this.cursor + 1) % this.max; }
    const i = k * 3;
    this.p[i] = x; this.p[i + 1] = y; this.p[i + 2] = z;
    this.v[i] = vx; this.v[i + 1] = vy; this.v[i + 2] = vz;
    this.life[k] = this.full[k] = life;
    this.heat[k] = heat;
    this.floor[k] = floor;
  }

  update(dt) {
    if (this.n === 0 && !this.mesh.visible) return;
    const { p, v, life, full, heat, floor, head, tail, data } = this;
    const drag = Math.exp(-dt * 2.2), grav = 13 * dt;
    let n = this.n;
    for (let k = 0; k < n;) {
      life[k] -= dt;
      if (life[k] <= 0) {
        // dead: move the last live spark into this slot
        n--;
        if (k !== n) {
          const i = k * 3, j = n * 3;
          p[i] = p[j]; p[i + 1] = p[j + 1]; p[i + 2] = p[j + 2];
          v[i] = v[j]; v[i + 1] = v[j + 1]; v[i + 2] = v[j + 2];
          life[k] = life[n]; full[k] = full[n]; heat[k] = heat[n]; floor[k] = floor[n];
        }
        continue;
      }
      const i = k * 3;
      v[i] *= drag; v[i + 1] = v[i + 1] * drag - grav; v[i + 2] *= drag;
      p[i] += v[i] * dt; p[i + 1] += v[i + 1] * dt; p[i + 2] += v[i + 2] * dt;
      if (p[i + 1] < floor[k] && v[i + 1] < 0) {
        p[i + 1] = floor[k];
        v[i + 1] *= -0.3; v[i] *= 0.55; v[i + 2] *= 0.55;
      }
      // streak: the last ~40 ms of flight, at most 0.9 m
      const sp = Math.hypot(v[i], v[i + 1], v[i + 2]);
      const tl = Math.min(0.04, 0.9 / Math.max(sp, 1e-3));
      head[i] = p[i]; head[i + 1] = p[i + 1]; head[i + 2] = p[i + 2];
      tail[i] = p[i] - v[i] * tl; tail[i + 1] = p[i + 1] - v[i + 1] * tl; tail[i + 2] = p[i + 2] - v[i + 2] * tl;
      const t = 1 - life[k] / full[k];
      data[i] = 0.025;
      data[i + 1] = heat[k] * (1 - 0.8 * t);
      data[i + 2] = Math.min(1, 4 * (1 - t));
      k++;
    }
    this.n = n;
    if (this.cursor >= n) this.cursor = 0;
    this.geo.instanceCount = n;
    this.mesh.visible = n > 0;
    if (n > 0) {
      this.geo.attributes.iHead.needsUpdate = true;
      this.geo.attributes.iTail.needsUpdate = true;
      this.geo.attributes.iData.needsUpdate = true;
    }
  }

  clear() {
    this.n = 0;
    this.geo.instanceCount = 0;
    this.mesh.visible = false;
  }

  dispose() { this.geo.dispose(); this.mat.dispose(); }
}

// =============================================================================
// Nitro flames (v4): a blue jet from each tail pipe and a trail of glow
// =============================================================================

const JET_VERT = /* glsl */`
  attribute vec3 iHead;  // the pipe end
  attribute vec3 iTail;  // the tip of the jet
  attribute vec3 iData;  // half width (m), brightness, 1 for the white core layer
  varying float vS;      // along the streak in half widths: 0 at the tip ... vL at the pipe
  varying float vT;      // across, -1 .. 1
  varying float vL;
  varying float vBright;
  varying float vCore;
  void main() {
    // a streak from the tip to the pipe turned to face the camera, with round ends;
    // seen end-on (from the chase camera) it is a glowing disc at the pipe
    vec4 h = viewMatrix * vec4(iHead, 1.0);
    vec4 t = viewMatrix * vec4(iTail, 1.0);
    vec2 d = h.xy - t.xy;
    float len = length(d);
    vec2 dir = len > 1e-5 ? d / len : vec2(1.0, 0.0);
    float w = iData.x;
    vec4 p = mix(t, h, position.x);
    p.xy += dir * (position.x * 2.0 - 1.0) * w + vec2(-dir.y, dir.x) * position.y * w;
    vL = len / w;
    vS = position.x * (vL + 2.0) - 1.0;
    vT = position.y;
    vBright = iData.y;
    vCore = iData.z;
    gl_Position = projectionMatrix * p;
  }`;
const JET_FRAG = /* glsl */`
  uniform vec3 edge;
  uniform vec3 core;
  uniform float opacity;
  uniform float time;
  varying float vS;
  varying float vT;
  varying float vL;
  varying float vBright;
  varying float vCore;
  void main() {
    float dx = max(0.0, max(-vS, vS - vL));
    float d = sqrt(dx * dx + vT * vT);              // from the streak's centre line (half widths)
    float dh = sqrt((vL - vS) * (vL - vS) + vT * vT); // from the pipe
    float f = clamp(1.0 - dh / (vL + 1.0), 0.0, 1.0); // fades towards the tip (radially when seen end-on)
    float a = smoothstep(1.0, 0.0, d) * pow(f, 1.3) * vBright * opacity;
    a *= 0.84 + 0.16 * sin(dh * 2.2 - time * 50.0);  // bands running down the jet
    if (a < 0.003) discard;
    vec3 col = vCore > 0.5 ? core : mix(edge, core, f * f * f * (1.0 - d));
    gl_FragColor = vec4(col * a, a); // added to what is behind (one/one blending)
    #include <tonemapping_fragment>
    #include <colorspace_fragment>
  }`;
const GLOW_FRAG = /* glsl */`
  uniform vec3 color;
  uniform float opacity;
  varying vec2 vUv;
  varying float vAlpha;
  void main() {
    float a = smoothstep(1.0, 0.0, length(vUv) * 2.0) * vAlpha * opacity;
    if (a < 0.004) discard;
    gl_FragColor = vec4(color * a, a);
    #include <tonemapping_fragment>
    #include <colorspace_fragment>
  }`;

const FLAME_POOL = 64;   // glow particles per car
const FLAME_RATE = 150;  // glow particles per second at full nitro (high graphics quality), over all tail pipes

const additive = (o) => ({ transparent: true, depthWrite: false, blending: THREE.CustomBlending, blendSrc: THREE.OneFactor, blendDst: THREE.OneFactor, ...o });

/**
 * Nitro flames for one car, shown while car.boosting (strength car.boost):
 * from each tail pipe a blue jet with a white core (camera-facing streaks in
 * one draw call, a bright disc when seen from behind), flickering, easing in
 * within ~0.1 s and out within ~0.25 s; and, if `glow`, a pooled trail of
 * glowing blobs left in the world behind the pipes (FLAME_POOL slots, nothing
 * allocated per frame; fewer on lower graphics quality, like the sparks). A
 * ghost gets the jets only, faded with the ghost (their materials sit in the
 * model's list, and fadeGhost sets their opacity).
 */
class NitroFlame {
  /**
   * @param pipes     [[x, y, z, radius], ...] pipe ends in the car's frame
   * @param glow      also leave a trail of glow
   * @param register  keeps a geometry or material for the model's dispose()
   */
  constructor(pipes, glow, register) {
    this.pipes = pipes;
    this.power = 0;
    this.time = 0;
    const n = pipes.length * 2; // a blue layer and a white core per pipe
    const g = new THREE.InstancedBufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute([0, -1, 0, 1, -1, 0, 1, 1, 0, 0, 1, 0], 3));
    g.setIndex([0, 1, 2, 0, 2, 3]);
    this.head = new Float32Array(n * 3);
    this.tail = new Float32Array(n * 3);
    this.jd = new Float32Array(n * 3);
    g.setAttribute('iHead', new THREE.InstancedBufferAttribute(this.head, 3).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('iTail', new THREE.InstancedBufferAttribute(this.tail, 3).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('iData', new THREE.InstancedBufferAttribute(this.jd, 3).setUsage(THREE.DynamicDrawUsage));
    g.instanceCount = n;
    this.jetGeo = register(g);
    this.jetMat = register(new THREE.ShaderMaterial(additive({
      uniforms: { edge: { value: new THREE.Vector3(0.1, 0.34, 1.7) }, core: { value: new THREE.Vector3(1.0, 1.45, 2.3) }, opacity: { value: 1 }, time: { value: 0 } },
      vertexShader: JET_VERT, fragmentShader: JET_FRAG,
    })));
    this.jets = worldSpace(new THREE.Mesh(g, this.jetMat));
    this.jets.renderOrder = 5;
    this.jets.visible = false;
    this._p = new THREE.Vector3();
    if (glow) {
      const q = new THREE.InstancedBufferGeometry();
      q.setAttribute('position', new THREE.Float32BufferAttribute([-0.5, -0.5, 0, 0.5, -0.5, 0, 0.5, 0.5, 0, -0.5, 0.5, 0], 3));
      q.setIndex([0, 1, 2, 0, 2, 3]);
      this.pos = new Float32Array(FLAME_POOL * 3);
      this.data = new Float32Array(FLAME_POOL * 2);
      q.setAttribute('iPos', new THREE.InstancedBufferAttribute(this.pos, 3).setUsage(THREE.DynamicDrawUsage));
      q.setAttribute('iData', new THREE.InstancedBufferAttribute(this.data, 2).setUsage(THREE.DynamicDrawUsage));
      q.instanceCount = FLAME_POOL;
      this.glowGeo = register(q);
      this.glowMat = register(new THREE.ShaderMaterial(additive({
        uniforms: { color: { value: new THREE.Vector3(0.35, 0.75, 2.4) }, opacity: { value: 1 } }, vertexShader: SMOKE_VERT, fragmentShader: GLOW_FRAG,
      })));
      this.glow = worldSpace(new THREE.Mesh(q, this.glowMat));
      this.glow.renderOrder = 5;
      this.glow.visible = false;
      // particle state: position, velocity, life left, full life, size
      this.p = new Float32Array(FLAME_POOL * 3);
      this.v = new Float32Array(FLAME_POOL * 3);
      this.life = new Float32Array(FLAME_POOL);
      this.full = new Float32Array(FLAME_POOL).fill(1);
      this.size = new Float32Array(FLAME_POOL);
      this.next = 0;
      this.acc = 0;
      this.pipe = 0;
      this.alive = 0;
    }
  }

  /** car: the drawn car (boost / boosting, velocity, yaw); root: the car's root, its matrix current. */
  update(car, dt, root) {
    const want = Math.max(0, Math.min(1, car.boost ?? (car.boosting ? 1 : 0)));
    this.power += (want - this.power) * (1 - Math.exp(-dt * (want > this.power ? 30 : 12)));
    if (want === 0 && this.power < 0.01) this.power = 0;
    this.time = (this.time + dt) % 600;
    const on = this.power > 0;
    this.jets.visible = on;
    if (on) {
      this.jetMat.uniforms.opacity.value = this.jetMat.opacity; // a ghost's fade
      this.jetMat.uniforms.time.value = this.time;
      const e = root.matrix.elements, bx = -e[8], by = -e[9], bz = -e[10]; // backwards along the car
      const t = this.time, P = this.power;
      for (let k = 0; k < this.pipes.length; k++) { // (no closures or arrays per frame)
        const pipe = this.pipes[k], r = pipe[3];
        const w = this._p.set(pipe[0], pipe[1], pipe[2]).applyMatrix4(root.matrix);
        // length grows with the boost and flickers; thicker pipes give bigger jets
        const f = 0.86 + 0.14 * Math.sin(t * 47 + k * 1.7) * Math.sin(t * 29 + k * 3.1);
        const len = (0.6 + 1.4 * P) * f * (r / 0.05);
        for (let layer = 0; layer < 2; layer++) {
          const i = (k * 2 + layer) * 3, l = layer ? len * 0.45 : len;
          this.head[i] = w.x; this.head[i + 1] = w.y; this.head[i + 2] = w.z;
          this.tail[i] = w.x + bx * l; this.tail[i + 1] = w.y + by * l; this.tail[i + 2] = w.z + bz * l;
          this.jd[i] = r * (layer ? 1.25 : 3) * (0.75 + 0.25 * P);
          this.jd[i + 1] = P * (layer ? 0.9 : 1);
          this.jd[i + 2] = layer;
        }
      }
      const at = this.jetGeo.attributes;
      at.iHead.needsUpdate = true; at.iTail.needsUpdate = true; at.iData.needsUpdate = true;
    }
    if (this.glow) this.updateGlow(car, dt, root);
  }

  updateGlow(car, dt, root) {
    const { p, v, life, full, size, pos, data } = this;
    // new blobs at the pipes, spread over the frame so a slow frame doesn't leave clumps
    this.acc += dt * FLAME_RATE * this.power * sparkShare;
    if (this.power === 0) this.acc = 0;
    const fx = Math.sin(car.yaw), fz = Math.cos(car.yaw), R = Math.random;
    while (this.acc >= 1) {
      this.acc -= 1;
      const pipe = this.pipes[this.pipe], r = pipe[3];
      this.pipe = (this.pipe + 1) % this.pipes.length;
      const w = this._p.set(pipe[0], pipe[1], pipe[2]).applyMatrix4(root.matrix);
      const k = this.next;
      this.next = (this.next + 1) % FLAME_POOL;
      const i = k * 3, out = 6 + R() * 4; // m/s out of the pipe
      v[i] = car.vx * 0.7 - fx * out + (R() - 0.5) * 1.2;
      v[i + 1] = 0.3 + R() * 0.6;
      v[i + 2] = car.vz * 0.7 - fz * out + (R() - 0.5) * 1.2;
      const age = R() * dt;
      p[i] = w.x + (v[i] - car.vx) * age - fx * 0.3; p[i + 1] = w.y; p[i + 2] = w.z + (v[i + 2] - car.vz) * age - fz * 0.3;
      life[k] = full[k] = 0.14 + R() * 0.14;
      size[k] = (0.4 + R() * 0.25) * (r / 0.05) * (0.6 + 0.4 * this.power);
    }
    if (this.alive === 0 && this.power === 0) return;
    let alive = 0;
    const drag = Math.exp(-dt * 3);
    for (let k = 0; k < FLAME_POOL; k++) {
      const i = k * 3;
      if (life[k] > 0) {
        life[k] -= dt;
        v[i] *= drag; v[i + 1] *= drag; v[i + 2] *= drag;
        p[i] += v[i] * dt; p[i + 1] += v[i + 1] * dt; p[i + 2] += v[i + 2] * dt;
      }
      const a = life[k] > 0 ? life[k] / full[k] : 0; // 1 fresh .. 0 gone
      pos[i] = p[i]; pos[i + 1] = p[i + 1]; pos[i + 2] = p[i + 2];
      data[k * 2] = size[k] * (0.45 + 0.55 * a);
      data[k * 2 + 1] = a * a;
      if (a > 0) alive++;
    }
    this.alive = alive;
    this.glow.visible = alive > 0;
    this.glowGeo.attributes.iPos.needsUpdate = true;
    this.glowGeo.attributes.iData.needsUpdate = true;
  }

  /** Put out at once (restart / respawn). */
  clear() {
    this.power = 0;
    this.acc = 0;
    this.jets.visible = false;
    if (this.glow) { this.life.fill(0); this.alive = 0; this.glow.visible = false; }
  }
}

// =============================================================================
// CarModel
// =============================================================================

export class CarModel {
  /**
   * @param color  body colour (default: the car's look.color); a ghost is see-through in this colour
   * @param ghost  a see-through ghost (no smoke, skid marks, sparks or flame trail; nitro jets only)
   * @param car    which car's shape (a car id from cars.js; unknown ids: the racer)
   */
  constructor({ color, ghost = false, car = DEFAULT_CAR } = {}) {
    const def = getCar(car);
    const shape = shapeOf(def.id);
    this.carId = def.id;
    color ??= def.look.color;
    this.ghost = ghost;
    this.root = new THREE.Group();
    this.root.rotation.order = 'YXZ';
    this.root.name = ghost ? 'ghost-car' : 'car';
    this.geometries = [];
    this.materials = [];
    const g = (x) => (this.geometries.push(x), x);
    const m = (x) => (this.materials.push(x), x);

    let paint, carbon, glass, tyreM, rimM, brakeM, headM, tailM, stripeM, accentM;
    if (ghost) {
      const gm = m(new THREE.MeshStandardMaterial({
        color, emissive: color, emissiveIntensity: 0.45, roughness: 0.35, metalness: 0.1,
        transparent: true, opacity: 0.4, depthWrite: false,
      }));
      paint = carbon = glass = tyreM = rimM = brakeM = stripeM = accentM = gm;
      headM = tailM = gm;
    } else {
      paint = m(new THREE.MeshPhysicalMaterial({ color, metalness: 0.3, roughness: 0.36, clearcoat: 1, clearcoatRoughness: 0.06 }));
      accentM = m(new THREE.MeshPhysicalMaterial({ color: def.look.accent, metalness: 0.25, roughness: 0.4, clearcoat: 1, clearcoatRoughness: 0.08 }));
      // stripe: the accent colour, or (the racer, as in v3) white on dark paint, near-black on light paint
      const lum = new THREE.Color(color).getHSL({}).l;
      stripeM = shape.stripeAccent ? accentM
        : m(new THREE.MeshPhysicalMaterial({ color: lum > 0.62 ? 0x1b1d22 : 0xf4f4f2, metalness: 0.1, roughness: 0.4, clearcoat: 1, clearcoatRoughness: 0.08 }));
      carbon = m(new THREE.MeshStandardMaterial({ color: 0x17191e, roughness: 0.38, metalness: 0.4 }));
      glass = m(new THREE.MeshStandardMaterial({ color: 0x0d1621, roughness: 0.04, metalness: 0.75 }));
      tyreM = m(new THREE.MeshStandardMaterial({ color: 0x1c1c1e, roughness: 0.82, metalness: 0, side: THREE.DoubleSide }));
      rimM = m(new THREE.MeshStandardMaterial({ color: 0xc3c7cf, roughness: 0.22, metalness: 1 }));
      brakeM = m(new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.45, metalness: 0.6 }));
      headM = m(new THREE.MeshStandardMaterial({ color: 0xffffff, emissive: 0xfff1d6, emissiveIntensity: 2.2, roughness: 0.2 }));
      tailM = m(new THREE.MeshStandardMaterial({ color: 0x3a0505, emissive: 0xff0000, emissiveIntensity: 0.9, roughness: 0.3 }));
      // ACES (applied to the whole frame) bleeds bright red into green, so brake
      // lights would turn orange; pre-compensate with a little negative green/blue.
      tailM.emissive.setRGB(1, -0.084, -0.034);
    }
    this.tailMat = ghost ? null : tailM;

    // body (sprung part: pitches and rolls with the attitude)
    this.body = new THREE.Group();
    const add = (geo, mat, parent = this.body) => {
      const mesh = new THREE.Mesh(g(geo), mat);
      mesh.castShadow = !ghost;
      mesh.receiveShadow = !ghost;
      parent.add(mesh);
      return mesh;
    };
    add(paintGeometry(1, shape), paint);
    add(stripeGeometry(shape), stripeM);
    add(carbonGeometry(1, shape), carbon);
    add(glassGeometry(shape), glass);
    add(mirrorGeometry(shape), paint);
    const accent = accentGeometry(shape);
    if (accent) add(accent, accentM);
    const lights = lightGeometries(shape);
    add(lights.head, headM).castShadow = false;
    add(lights.tail, tailM).castShadow = false;
    this.root.add(this.body);

    // wheels: pivot (steers) > spin group (rolls) > tyre + rim; brake on the pivot
    this.wheels = [];
    const wheelGeo = {};
    for (const [x, z, R, W, front] of wheelLayout(shape)) {
      const key = `${R}:${W}:${x > 0 ? 'L' : 'R'}`;
      if (!wheelGeo[key]) {
        const w = wheelGeometries(R, W);
        if (x < 0) for (const k of ['tyre', 'rim', 'brake']) w[k].rotateY(Math.PI);
        wheelGeo[key] = w;
        for (const k of ['tyre', 'rim', 'brake']) g(w[k]);
      }
      const w = wheelGeo[key];
      const pivot = new THREE.Group();
      pivot.position.set(x, R, z);
      const spin = new THREE.Group();
      pivot.add(spin);
      const ty = new THREE.Mesh(w.tyre, tyreM), rim = new THREE.Mesh(w.rim, rimM), br = new THREE.Mesh(w.brake, brakeM);
      for (const mesh of [ty, rim, br]) { mesh.castShadow = !ghost; mesh.receiveShadow = !ghost; }
      spin.add(ty, rim);
      pivot.add(br);
      this.root.add(pivot);
      this.wheels.push({ pivot, spin, front, R });
    }

    // soft contact shadow under the car
    if (!ghost) {
      const blob = new THREE.Mesh(
        g(new THREE.PlaneGeometry(2.6 * shape.width, 5.4 * (shape.front + shape.rear) / 2).rotateX(-Math.PI / 2)),
        m(new THREE.MeshBasicMaterial({ map: blobTexture(), transparent: true, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -4, polygonOffsetUnits: -4 })),
      );
      blob.position.y = 0.02;
      blob.renderOrder = 1;
      this.root.add(blob);
      this.smoke = new TyreSmoke(64);
      this.skids = new SkidMarks(240);
      this.sparks = new Sparks(160);
      this.wall = newWallState();
      this.root.add(this.smoke.mesh, this.skids.mesh, this.sparks.mesh);
    }

    if (ghost) {
      // Depth pre-pass: every ghost part first writes depth only, then the see-through
      // paint is drawn where it is the front-most surface. Without it the wheels, brakes
      // and the cockpit tub show through the body like an X-ray. The pre-pass is in the
      // transparent queue (after all opaque objects), so the ghost never hides the road.
      const depthOnly = m(new THREE.MeshBasicMaterial({ colorWrite: false, depthWrite: true, transparent: true }));
      const parts = [];
      this.root.traverse((o) => { if (o.isMesh) parts.push(o); });
      for (const mesh of parts) {
        const pre = new THREE.Mesh(mesh.geometry, depthOnly);
        pre.renderOrder = 10;
        mesh.renderOrder = 11;
        mesh.add(pre);
      }
    }

    // nitro flames from the tail pipes (made after the ghost's depth pre-pass: light has no depth);
    // their materials sit in this.materials, so a ghost's fade (playMode.js) fades them too
    this.flame = new NitroFlame(nozzles(shape), !ghost, (x) => (x.isMaterial ? m(x) : g(x)));
    this.root.add(this.flame.jets);
    if (this.flame.glow) this.root.add(this.flame.glow);

    this.att = { pitch: 0, roll: 0 };
    this.tilt = { pitch: 0, roll: 0 };
    this.spinAngle = 0;
    this.steerVis = 0;
    this.brakeGlow = 1;
    this._v = new THREE.Vector3();
    this._first = true;
  }

  update(car, track, dt) {
    dt = Math.min(dt, 0.1);
    const root = this.root;
    // a jump of several metres means restart / respawn: snap, start new skid strips
    if (!this._first && (car.x - root.position.x) ** 2 + (car.z - root.position.z) ** 2 > 64) {
      this._first = true;
      if (this.skids) { this.skids.lift(0); this.skids.lift(1); }
    }
    root.position.set(car.x, car.y, car.z);
    root.rotation.y = car.yaw;

    // attitude: v2 pitch/roll when present, else follow the road (v1)
    const hasAtt = car.pitch !== undefined && car.roll !== undefined;
    if (hasAtt || car.grounded) attitude(car, track, this.tilt);
    const k = this._first ? 1 : 1 - Math.exp(-dt * (hasAtt ? 30 : car.grounded ? 14 : 2));
    this.att.pitch += (this.tilt.pitch - this.att.pitch) * k;
    this.att.roll += (this.tilt.roll - this.att.roll) * k;
    root.rotation.x = -this.att.pitch;
    root.rotation.z = this.att.roll;
    if (!hasAtt) {
      // v1: the body leans out of corners a little
      const lean = Math.max(-0.06, Math.min(0.06, -(car.steer ?? 0) * car.speed * 0.0016));
      this.body.rotation.z += (lean - this.body.rotation.z) * (1 - Math.exp(-dt * 8));
    } else {
      this.body.rotation.z = 0;
    }

    // wheels
    const steer = car.steerAngle ?? (car.steer ?? 0) * 0.42;
    this.steerVis += (steer - this.steerVis) * (this._first ? 1 : 1 - Math.exp(-dt * 20));
    if (car.wheelRot !== undefined) this.spinAngle = car.wheelRot;
    else this.spinAngle += ((car.forwardSpeed ?? 0) / 0.39) * dt;
    for (const w of this.wheels) {
      w.spin.rotation.x = this.spinAngle;
      w.pivot.rotation.y = w.front ? this.steerVis : 0;
    }

    // brake lights
    if (this.tailMat) {
      const braking = car.braking ?? ((car.throttle ?? 0) < -0.05 && (car.forwardSpeed ?? 0) > 0.5);
      const target = braking ? 3.4 : 0.75;
      this.brakeGlow += (target - this.brakeGlow) * (1 - Math.exp(-dt * 25));
      this.tailMat.emissiveIntensity = this.brakeGlow;
    }

    // tyre smoke and skid marks from the rear wheels
    if (this.smoke) {
      const slip = car.slip ?? (car.drifting ? 0.75 : Math.max(0, Math.min(1, (Math.abs(car.sideSpeed ?? 0) - 4) / 6)));
      const sliding = car.grounded && slip > 0.3 && car.speed > 4;
      root.updateMatrix();
      const sx = Math.cos(car.yaw), sz = -Math.sin(car.yaw); // left vector
      for (let wi = 0; wi < 2; wi++) {
        const w = this.wheels[2 + wi];
        const p = this._v.set(w.pivot.position.x, 0.03, w.pivot.position.z).applyMatrix4(root.matrix);
        if (sliding) {
          this.skids.add(wi, p.x, p.y, p.z, sx, sz, Math.min(0.75, 0.25 + slip * 0.6));
          this.smokeAcc = (this.smokeAcc ?? 0) + dt * 18 * slip;
          while (this.smokeAcc >= 1) { this.smokeAcc -= 1; this.smoke.emit(p.x, p.y, p.z, car.vx, car.vz, slip); }
        } else {
          this.skids.lift(wi);
        }
      }
      this.smoke.update(dt);
    }

    // sparks where the car hits or scrapes a wall (ghosts have none)
    if (this.sparks) {
      if (this._first) this.wall.ready = false;
      const steps = wallEvents(this.wall, car);
      if (steps > 0) emitSparks(this.sparks, this.wall, steps, car, car.x, car.y, car.z, car.yaw, this.sparks.max);
      this.sparks.update(dt);
    }

    // nitro flames while boosting (a ghost shows them when its car has boost / boosting)
    root.updateMatrix();
    this.flame.update(car, dt, root);
    this._first = false;
  }

  /** Forget smoke, skid marks, sparks and flames (after a restart / respawn). */
  resetEffects() {
    if (this.skids) this.skids.clear();
    if (this.smoke) for (const p of this.smoke.p) p.life = 0;
    if (this.sparks) { this.sparks.clear(); this.wall.ready = false; }
    this.flame.clear();
    this._first = true;
  }

  dispose() {
    this.geometries.forEach((x) => x.dispose());
    this.materials.forEach((x) => x.dispose());
    if (this.smoke) this.smoke.dispose();
    if (this.skids) this.skids.dispose();
    if (this.sparks) this.sparks.dispose();
  }
}

// =============================================================================
// AIFleet: many cars with a few instanced meshes
// =============================================================================

const FLEET_SPARKS = 240;     // spark pool shared by every car of the fleet
const FLEET_SPARK_FRAME = 40; // most new sparks per frame for the whole fleet (high quality)

export class AIFleet {
  constructor(maxCount) {
    this.count = maxCount;
    const paint = paintGeometry(0);
    const dark = merge([
      carbonGeometry(0),
      loft(canopyStations(), 10, 1),
      ...WHEELS.map(([x, z, R, W]) => new THREE.CylinderGeometry(R, R, W, 10).rotateZ(Math.PI / 2).translate(x, R, z)),
    ]);
    this.body = new THREE.InstancedMesh(paint, new THREE.MeshStandardMaterial({ roughness: 0.38, metalness: 0.35 }), maxCount);
    this.dark = new THREE.InstancedMesh(dark, new THREE.MeshStandardMaterial({ color: 0x16181d, roughness: 0.45, metalness: 0.3 }), maxCount);
    this.body.castShadow = true;
    this.body.receiveShadow = true;
    for (const m of [this.body, this.dark]) m.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    this.group = new THREE.Group();
    this.group.name = 'ai-fleet';
    this.group.add(this.body, this.dark);

    // Selected car: a floating marker and a glowing ring on the road.
    this.marker = new THREE.Mesh(
      new THREE.OctahedronGeometry(0.55, 0).scale(1, 1.6, 1),
      new THREE.MeshStandardMaterial({ color: 0xffd23f, emissive: 0xffb300, emissiveIntensity: 2.2, roughness: 0.3 }),
    );
    this.ring = new THREE.Mesh(
      new THREE.RingGeometry(2.7, 3.2, 40).rotateX(-Math.PI / 2),
      new THREE.MeshBasicMaterial({ color: 0xffc83d, transparent: true, opacity: 0.85, depthWrite: false, side: THREE.DoubleSide,
        polygonOffset: true, polygonOffsetFactor: -4, polygonOffsetUnits: -4 }),
    );
    this.ring.rotation.order = 'YXZ';
    this.ring.renderOrder = 2;
    this.group.add(this.marker, this.ring);

    // Wall sparks for the whole fleet: one pool, at most FLEET_SPARK_FRAME new sparks a frame.
    this.sparks = new Sparks(FLEET_SPARKS);
    this.group.add(this.sparks.mesh);
    this._wall = Array.from({ length: maxCount }, newWallState);
    this._sparkFrom = 0;

    this._o = new THREE.Object3D();
    this._o.rotation.order = 'YXZ';
    this._c = new THREE.Color();
    this._tilt = { pitch: 0, roll: 0 };
    /** Interpolated copy of the selected agent's car (for a smooth chase camera). */
    this.selectedView = null;
    this._view = {};
  }

  /**
   * agents: trainer agents; selected: index of the viewed car; time: seconds;
   * alpha: interpolation between agent.prev and agent.car (0..1).
   */
  update(agents, track, selected, time, alpha = 1) {
    const o = this._o;
    this.selectedView = null;
    // A car inside the body of a car already drawn is not drawn: at every run start the
    // whole population sits on the grid, identical clones (elites) drive identical lines
    // (their bodies would z-fight as flickering stripes), and with the 'ride' wall rule a
    // trained pack presses into the same wall line a metre or two apart (a column of
    // bodies drawn through each other). Spots are claimed in a stable order, so the same
    // car stays the one drawn (no colour flicker as the pack leaves the grid): the viewed
    // car first, then the cars drawn last frame (they stay until they sit half inside one
    // already drawn), then the rest, which only appear once their body is clear of every
    // car drawn (hysteresis: no on/off flicker).
    const n = this.count;
    const P = (this._poses ??= new Float32Array(n * 4));
    const show = (this._show ??= new Uint8Array(n));
    const was = (this._was ??= new Uint8Array(n));
    const spots = (this._drawn ??= new Float32Array(n * 5)); // x, z, yaw, sin(yaw), cos(yaw)
    let nSpots = 0;
    const pose = this._pose ??= { x: 0, y: 0, z: 0, yaw: 0 };
    for (let k = 0; k < n; k++) {
      const a = agents[k];
      show[k] = 0;
      if (!a || (!a.alive && k !== selected)) continue;
      this.posed(a, alpha, pose);
      P[k * 4] = pose.x; P[k * 4 + 1] = pose.y; P[k * 4 + 2] = pose.z; P[k * 4 + 3] = pose.yaw;
      show[k] = 2; // candidate
    }
    // k is merged into a car already drawn when its centre lies within ±along × ±across
    // of that car (in its frame: 4.4 × 2 m body) at a heading within yawLim.
    const claim = (k, along, across, yawLim) => {
      const x = P[k * 4], z = P[k * 4 + 2], yaw = P[k * 4 + 3];
      const r2 = along * along + across * across;
      for (let j = 0; j < nSpots * 5; j += 5) {
        const dx = x - spots[j], dz = z - spots[j + 1];
        if (dx * dx + dz * dz >= r2) continue;
        const s = spots[j + 3], c = spots[j + 4];
        if (Math.abs(dx * s + dz * c) >= along || Math.abs(dx * c - dz * s) >= across) continue;
        const dy = Math.abs(Math.atan2(Math.sin(yaw - spots[j + 2]), Math.cos(yaw - spots[j + 2])));
        if (dy < yawLim) return 0;
      }
      const j = nSpots++ * 5;
      spots[j] = x; spots[j + 1] = z; spots[j + 2] = yaw; spots[j + 3] = Math.sin(yaw); spots[j + 4] = Math.cos(yaw);
      return 1;
    };
    if (selected >= 0 && selected < n && show[selected] === 2) show[selected] = claim(selected, 0, 0, 0);
    for (let k = 0; k < n; k++) if (show[k] === 2 && was[k]) show[k] = claim(k, 2.2, 0.8, 0.35);
    for (let k = 0; k < n; k++) if (show[k] === 2) show[k] = claim(k, 4.4, 1.9, 0.5);
    was.set(show);
    for (let k = 0; k < n; k++) {
      const a = agents[k];
      const hide = !show[k];
      if (!hide) { pose.x = P[k * 4]; pose.y = P[k * 4 + 1]; pose.z = P[k * 4 + 2]; pose.yaw = P[k * 4 + 3]; }
      if (hide) {
        // hidden: zero scale, parked at the start so the bounds stay tight
        o.position.set(track.px[0], track.py[0], track.pz[0]);
        o.scale.setScalar(0);
      } else {
        const car = a.car;
        const { x, y, z, yaw } = pose;
        attitude(car, track, this._tilt);
        o.position.set(x, y, z);
        o.rotation.set(-this._tilt.pitch, yaw, this._tilt.roll);
        o.scale.setScalar(1);
        if (k === selected) this._c.setHex(0xffc83d);
        else if (!a.alive) this._c.setHex(0x6a6d73);
        else this._c.setHSL((k * 0.137) % 1, 0.7, 0.5);
        this.body.setColorAt(k, this._c);
        if (k === selected) {
          const v = Object.assign(this._view, car);
          v.x = x; v.y = y; v.z = z; v.yaw = yaw;
          this.selectedView = v;
          this.ring.position.set(x, y + 0.05, z);
          this.ring.rotation.set(-this._tilt.pitch, yaw, this._tilt.roll);
        }
      }
      o.updateMatrix();
      this.body.setMatrixAt(k, o.matrix);
      this.dark.setMatrixAt(k, o.matrix);
    }
    this.body.instanceMatrix.needsUpdate = true;
    this.dark.instanceMatrix.needsUpdate = true;
    if (this.body.instanceColor) this.body.instanceColor.needsUpdate = true;
    this.body.computeBoundingSphere();
    this.dark.boundingSphere = this.body.boundingSphere;

    const s = this.selectedView;
    this.marker.visible = this.ring.visible = !!s;
    if (s) {
      this.marker.position.set(s.x, s.y + 4.4 + Math.sin(time * 4) * 0.3, s.z);
      this.marker.rotation.y = time * 2;
      this.ring.material.opacity = 0.55 + 0.3 * Math.sin(time * 6);
    }

    // Sparks from the cars drawn: the viewed car first, then the others from a
    // starting point that moves on every frame, so a full budget is shared out.
    const dt = Math.min(0.1, Math.max(0, time - (this._time ?? time)));
    this._time = time;
    let budget = Math.round(FLEET_SPARK_FRAME * sparkShare);
    this._sparkFrom = (this._sparkFrom + 7) % Math.max(1, n);
    for (let q = -1; q < n; q++) {
      const k = q < 0 ? selected : (this._sparkFrom + q) % n;
      if (k < 0 || k >= n || (q >= 0 && k === selected)) continue;
      const st = this._wall[k];
      if (!show[k]) { st.ready = false; continue; }
      const car = agents[k].car;
      const steps = wallEvents(st, car);
      if (steps > 0 && budget > 0) {
        budget -= emitSparks(this.sparks, st, steps, car, P[k * 4], P[k * 4 + 1], P[k * 4 + 2], P[k * 4 + 3], Math.min(budget, 24), 0.5);
      }
    }
    this.sparks.update(dt);
  }

  /** Interpolated pose of an agent's car between agent.prev and agent.car (into out). */
  posed(a, alpha, out) {
    const car = a.car, p = a.prev;
    out.x = car.x; out.y = car.y; out.z = car.z; out.yaw = car.yaw;
    if (p && alpha < 1) {
      out.x = p.x + (car.x - p.x) * alpha;
      out.y = p.y + (car.y - p.y) * alpha;
      out.z = p.z + (car.z - p.z) * alpha;
      const dy = Math.atan2(Math.sin(car.yaw - p.yaw), Math.cos(car.yaw - p.yaw));
      out.yaw = p.yaw + dy * alpha;
    }
    return out;
  }

  /** Returns the agent index under the pointer, or -1. */
  pick(raycaster) {
    const hits = raycaster.intersectObject(this.body, false);
    return hits.length ? hits[0].instanceId : -1;
  }

  dispose() {
    for (const m of [this.body, this.dark, this.marker, this.ring]) {
      m.geometry.dispose();
      m.material.dispose();
    }
    this.sparks.dispose();
    this.body.dispose?.();
    this.dark.dispose?.();
  }
}

// =============================================================================
// SensorRays
// =============================================================================

/** The AI's sensor rays, drawn from the car's nose, red when close. */
export class SensorRays {
  constructor() {
    const n = SENSOR_ANGLES.length;
    this.geo = new THREE.BufferGeometry();
    this.pos = new Float32Array(n * 6);
    this.col = new Float32Array(n * 6);
    this.geo.setAttribute('position', new THREE.BufferAttribute(this.pos, 3));
    this.geo.setAttribute('color', new THREE.BufferAttribute(this.col, 3));
    this.lines = new THREE.LineSegments(this.geo, new THREE.LineBasicMaterial({ vertexColors: true, transparent: true, opacity: 0.9, depthTest: false, toneMapped: false }));
    this.lines.frustumCulled = false;
    this.lines.renderOrder = 10;
    this.hits = new THREE.Points(
      new THREE.BufferGeometry().setAttribute('position', new THREE.BufferAttribute(new Float32Array(n * 3), 3)),
      new THREE.PointsMaterial({ color: 0xffffff, size: 0.45, depthTest: false, toneMapped: false }),
    );
    this.hits.frustumCulled = false;
    this.hits.renderOrder = 11;
    this.group = new THREE.Group();
    this.group.add(this.lines, this.hits);
    this._c = new THREE.Color();
  }

  update(car, rays, range) {
    const fx = Math.sin(car.yaw), fz = Math.cos(car.yaw);
    const lx = fz, lz = -fx;
    const ox = car.x + fx * 1.5, oz = car.z + fz * 1.5, oy = car.y + 0.8;
    const hp = this.hits.geometry.attributes.position.array;
    SENSOR_ANGLES.forEach((deg, k) => {
      const a = (deg * Math.PI) / 180;
      const dx = fx * Math.cos(a) + lx * Math.sin(a), dz = fz * Math.cos(a) + lz * Math.sin(a);
      const d = rays[k];
      const ex = ox + dx * d, ez = oz + dz * d;
      this.pos.set([ox, oy, oz, ex, oy, ez], k * 6);
      hp.set([ex, oy, ez], k * 3);
      this._c.setHSL(0.33 * Math.min(1, d / range), 0.9, 0.55);
      this.col.set([this._c.r, this._c.g, this._c.b, this._c.r, this._c.g, this._c.b], k * 6);
    });
    this.geo.attributes.position.needsUpdate = true;
    this.geo.attributes.color.needsUpdate = true;
    this.hits.geometry.attributes.position.needsUpdate = true;
  }

  dispose() {
    this.geo.dispose();
    this.lines.material.dispose();
    this.hits.geometry.dispose();
    this.hits.material.dispose();
  }
}
