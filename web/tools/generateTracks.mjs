/**
 * generateTracks.mjs — regenerates src/tracks/trackData.js from the turtle
 * programs below, validates every track against the design rules and
 * writes a map of all tracks to docs/tracks-overview.svg.
 *
 *   node tools/generateTracks.mjs            validate, then write both files
 *   node tools/generateTracks.mjs --check    validate only, write nothing
 *   node tools/generateTracks.mjs --preview  write the SVG even if a rule fails
 *
 * Any rule violation is printed and the script exits with code 1 without
 * writing trackData.js. You don't need this to add a track: you can also
 * write control points straight into trackData.js (see README.md), but then
 * run this script's checks by adding the track here.
 *
 * Design rules (RULES below):
 *   - no part of the track comes within hwA + hwB + 6 m of another part
 *     (no crossings or bridges: physics is 2.5D)
 *   - centre-line radius >= half width + 4 m everywhere (walls never fold)
 *   - grades <= 12 %; only kicker ramps may be steeper (<= 25 %), and every
 *     kicker lip is followed by >= 120 m of straight landing zone whose
 *     downslope is <= 15 %
 *   - crests (outside kickers) have a vertical radius >= 300 m, so cars stay
 *     on the road over hills instead of hopping
 *   - heights between 0 and 18 m, banking <= 30°, width changes <= 1:10
 *   - checkpoints every 250-500 m and never on a jump
 *   - the start is on a straight with >= 80 m to the first corner; circuits
 *     close within 1 m with the start/finish line on a straight; sprints
 *     finish on a straight
 *   - sprints have 36 m of straight road before the cars' start position
 *     (the START line is 12 m behind the cars, like on circuits, so the
 *     chase camera has road behind it) and 250 m of flat, straight run-off
 *     after the FINISH line (a car crossing it at 270 km/h stops in ~240 m)
 */
import { writeFileSync, realpathSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { turtle, closeLoop } from './turtle.mjs';
import { buildTrack, KICKER_GRADE } from '../src/tracks/trackBuilder.js';

const args = new Set(process.argv.slice(2));
const CHECK_ONLY = args.has('--check');
const PREVIEW = args.has('--preview');

const RULES = {
  clearance: 6,          // m between the road edges of two separate parts of the track
  radiusMargin: 4,       // centre-line radius >= hw + 4 m
  maxGrade: KICKER_GRADE, // 12 %
  maxKickerGrade: 0.25,
  maxLandingGrade: 0.15,
  landingZone: 120,      // m of straight road after a kicker lip
  minCrestRadius: 300,   // m, vertical radius of crests outside kickers
  minHeight: 0,
  maxHeight: 18,
  maxBank: 30,           // degrees
  maxTaper: 0.1,         // |d(half width)/ds|: walls angle in at most 1:10
  cpGap: [250, 500],     // m between consecutive gates (start, checkpoints, finish)
  startStraight: 80,     // m of straight after the start
  finishStraight: 40,    // m of straight before a sprint finish / around a start line
  closure: 1,            // m
  straightTol: 1,        // degrees of heading change still counted as "straight"
  sprintRunIn: 36,       // m of road before a sprint's start position
  sprintRunOff: 250,     // m of straight, flat road after a sprint's finish line
};
const { sprintRunIn: RUN_IN, sprintRunOff: RUN_OFF } = RULES;

const THEMES = ['meadow', 'desert', 'alpine', 'canyon', 'dusk', 'night', 'seaside'];


/** The designs, in menu order (see below). */
export const DESIGNS = [];
/** A circuit: make(a, b) is a turtle program with two free straights that closeLoop solves. */
const circuit = (meta, make, close, req = {}) => DESIGNS.push({ kind: 'circuit', meta, make, close, req });
/** A sprint: make() returns the turtle, point to point. */
const sprint = (meta, make, req = {}) => DESIGNS.push({ kind: 'sprint', meta, make, req });

function realise(d) {
  const { meta, req } = d;
  let t, solved = null;
  if (d.kind === 'circuit') {
    solved = closeLoop(d.make, d.close);
    t = solved.t;
  } else t = d.make();
  const sprintEnds = d.kind === 'sprint' ? { startAt: RUN_IN, runOff: RUN_OFF } : {};
  const f = t.finish({ closed: d.kind === 'circuit', cpSpacing: req.cpSpacing ?? 400, ...sprintEnds });
  const def = { ...meta, type: d.kind, ...(d.kind === 'circuit' ? { laps: 3 } : sprintEnds), width: meta.width, theme: meta.theme, checkpoints: f.checkpoints, points: f.points };
  return { def, f, req, solved };
}

// =============================================================================
// The tracks. Lengths in metres, angles in degrees; L/R = left/right turn
// (deg, radius, {bank, y}); y = height at the end of a piece.
// =============================================================================

// 1 — Rookie Oval: a wide, flowing beginner circuit with gentle slopes.
circuit(
  { id: 'rookie-oval', name: 'Rookie Oval', difficulty: 1, width: 22, theme: 'meadow',
    description: 'A wide, flowing loop with gentle slopes: learn the car and carry speed through the sweepers.' },
  (a, b) => turtle({ width: 22, y: 2 })
    .S(a, { y: 2 }).width(20, 60)
    .L(110, 100, { bank: 6 })
    .S(b, { y: 3 })
    .L(70, 70, { bank: 6, y: 4 })
    .S(160, { y: 5 }).R(40, 150).L(40, 150).S(100, { y: 3.5 })
    .L(90, 90, { bank: 6 })
    .S(160).width(22, 60)
    .L(90, 120, { bank: 5, y: 2.5 })
    .S(100, { y: 2 }),
  { a0: 300, b0: 200, minA: 150, minB: 60 },
  { minLength: 1600, width: [18, 22], maxGrade: 0.06, kickers: 0 },
);

// 2 — Hairpin Valley: switchbacks up one side of the valley, a ridge road, switchbacks down the other.
// (A wide hairpin: L(90) + short straight + L(90) gives the legs more room.)
circuit(
  { id: 'hairpin-valley', name: 'Hairpin Valley', difficulty: 2, width: 13, theme: 'alpine',
    description: 'Climb three switchbacks, cross the ridge and drop down two more: brake early, power out.' },
  (a, b) => turtle({ width: 13, y: 1, yaw: Math.PI / 2 })
    .S(a, { y: 1 })
    .S(60)
    // up: three switchbacks, each leg climbs 5 m at up to 7 %
    .L(90, 16).S(64).L(90, 16).S(20).climb(110, 6).S(20)
    .R(90, 16).S(64).R(90, 16).S(20).climb(110, 11).S(20)
    .L(90, 16).S(64).L(90, 16).S(20).climb(110, 16)
    // the ridge
    .S(100).hill(200, 1.5)
    .L(90, 40)
    // down: two hairpins
    .climb(b, 12.5)
    .hairpin('R', 17).climb(b - 40, 8)
    .hairpin('L', 17).climb(b + 20, 3)
    .L(90, 40, { y: 1.5 })
    .S(120, { y: 1 }),
  { a0: 100, b0: 160, minA: 60, minB: 100 },
  { minLength: 2200, hairpins: 5, minClimb: 10, kickers: 0 },
);

// 3 — Ramp Rally: four kicker jumps on long straights, chicanes and dunes in between.
circuit(
  { id: 'ramp-rally', name: 'Ramp Rally', difficulty: 3, width: 15, theme: 'desert',
    description: 'Four kicker jumps from 4 to 7 m: hit each ramp straight and land on the long run-outs.' },
  (a, b) => turtle({ width: 15, y: 2 })
    .S(a, { y: 2 })
    .kicker({ h: 4.2, ramp: 22, land: 32, run: 130, lead: 30 })
    .L(90, 40, { bank: 6 })
    .S(b).SL(30, 70, {}, 20)
    .kicker({ h: 5.5, ramp: 28, land: 42, run: 130 })
    .hill(180, 3)
    .L(90, 35, { bank: 8 })
    .S(60).kicker({ h: 7, ramp: 34, land: 55, run: 130 })
    .L(90, 45, { bank: 6 })
    .S(60).hill(160, 2.5).SR(35, 60, {}, 30)
    .kicker({ h: 5, ramp: 26, land: 45, run: 130, drop: 1.5 }).y(0.5)
    .L(90, 40, { y: 2 })
    .S(80, { y: 2 }),
  { a0: 120, b0: 100, minA: 90, minB: 40 },
  { minLength: 2000, kickers: 4, kickerHeight: [4, 7] },
);

// 4 — Banked Speedway: huge banked bowls, banked esses and long straights.
circuit(
  { id: 'banked-speedway', name: 'Banked Speedway', difficulty: 3, width: 18, theme: 'dusk',
    description: 'Steep banked bowls hold the car at full speed: trust the banking and stay flat out.' },
  (a, b) => turtle({ width: 18, y: 6 })
    .S(a, { y: 6 })
    .L(95, 170, { bank: 24 })
    .S(b)
    .L(85, 160, { bank: 26 })
    .S(20, { y: 6 }).hill(320, 3)
    .L(45, 180, { bank: 12 }).R(45, 180, { bank: 12 })
    .S(120)
    .L(180, 150, { bank: 28 })
    .S(120, { y: 6 }),
  { a0: 400, b0: 120, minA: 200, minB: 60 },
  { minLength: 2500, bank: [20, 30], kickers: 0 },
);

// 5 — Technical Trial: everything mixed, the road narrows and widens.
circuit(
  { id: 'technical-trial', name: 'Technical Trial', difficulty: 4, width: 14, theme: 'canyon',
    description: 'Narrow chicanes, a jump, banked sweepers and a switchback climb: rhythm beats top speed.' },
  (a, b) => turtle({ width: 16, y: 3 })
    .S(a, { y: 3 }).width(12, 40)
    .L(90, 30, { bank: 5 })
    .S(40).kicker({ h: 5, ramp: 26, land: 40, run: 120, lead: 10 })
    .width(10, 40).SL(55, 24, {}, 12).S(40).width(14, 40).hill(200, -2)
    .L(90, 30, { y: 4 })
    .S(220, { y: 9 })
    .hairpin('R', 15, { y: 10 }).S(170, { y: 12 })
    .hairpin('L', 15, { y: 13 }).width(14, 40).S(230, { y: 13 })
    .L(90, 40, { bank: 8 })
    .S(b)
    .R(40, 60, { bank: 12 }).L(80, 60, { bank: 14 }).R(40, 60, { bank: 12 })
    .S(60, { y: 8 }).width(10, 40)
    .L(35, 30).R(35, 30).S(40, { y: 4 }).width(16, 60)
    .L(90, 45, { bank: 10, y: 3 })
    .S(100, { y: 3 }),
  { a0: 150, b0: 150, minA: 100, minB: 40 },
  { minLength: 2500, width: [10, 16], widthSpread: 5.5 },
);

// 6 — Grand Marathon: the long point-to-point run with every element.
// Four long rows joined by U-turns (a banked bowl, a switchback, a wide banked turn).
sprint(
  { id: 'grand-marathon', name: 'Grand Marathon', difficulty: 5, width: 15, theme: 'meadow',
    description: 'Over 6 km point to point: jumps, switchbacks, banked bowls and narrow chicanes in one run.' },
  () => turtle({ width: 16, y: 2, yaw: Math.PI / 2 })
    .S(RUN_IN, { y: 2 }) // road behind the start position
    // row 1 (east): start, fast sweepers, first jump
    .S(260, { y: 2 }).width(15, 60)
    .L(30, 220, { bank: 6 }).R(30, 220, { bank: 6 })
    .S(60).kicker({ h: 5, ramp: 26, land: 40, run: 140 })
    .S(100).R(25, 180).L(25, 180).S(140, { y: 5 })
    .R(30, 150, { bank: 6 }).L(30, 150, { bank: 6 }).S(100, { y: 5 })
    // U-turn 1: banked bowl
    .L(180, 115, { bank: 24 }).S(80, { y: 5 })
    // row 2 (west): climb, switchback tongue, narrow chicanes
    .S(220, { y: 9 })
    .R(90, 20).S(110, { y: 12 }).hairpin('L', 16, { y: 13 }).S(110, { y: 15 }).R(90, 20, { y: 15 })
    .S(80).width(11, 40).S(60).SR(45, 28, {}, 12).S(60).width(15, 40)
    .S(260, { y: 12 }).R(20, 200).L(20, 200)
    .S(120, { y: 11 })
    // U-turn 2: a slow double-right
    .R(90, 35, { bank: 6 }).S(170).R(90, 35, { bank: 6, y: 10 })
    // row 3 (east): descent, banked esses, second jump
    .S(240, { y: 7 })
    .L(50, 100, { bank: 15 }).R(50, 100, { bank: 15 })
    .S(120, { y: 6 })
    .kicker({ h: 6, ramp: 30, land: 50, run: 150, drop: 2 })
    .S(120, { y: 4 }).R(30, 120).L(30, 120)
    .S(160, { y: 4 })
    // U-turn 3: wide banked turn
    .L(180, 110, { bank: 20 })
    // row 4 (west): technical run home
    .S(180, { y: 3 }).width(12, 40)
    .R(60, 35).L(120, 40, { bank: 8 }).R(60, 35).width(16, 40)
    .S(300, { y: 2 }).L(25, 250).R(25, 250)
    .S(250, { y: 2 })
    .S(RUN_OFF, { y: 2 }), // run-off after the finish line
  { minLength: 6000 },
);

// 7 — Coastal GP: a fast, flowing grand-prix circuit; wide main straight, narrower twisty sector.
circuit(
  { id: 'coastal-gp', name: 'Coastal GP', difficulty: 3, width: 14, theme: 'dusk',
    description: 'A fast grand-prix circuit at sunset: big braking zones, quick esses and a narrow final sector.' },
  (a, b) => turtle({ width: 18, y: 2 })
    .S(a, { y: 2 }).width(14, 80)
    .R(90, 30, { bank: 4 })
    .L(30, 60)
    .S(150, { y: 3 })
    .R(60, 110, { bank: 8 }).L(40, 150, { bank: 6 })
    .S(b, { y: 4 })
    .R(120, 70, { bank: 10 })
    .S(330, { y: 8 })
    .L(50, 60, { bank: 6 }).R(50, 60, { bank: 6 })
    .S(160, { y: 7 })
    .R(90, 45, { bank: 6 })
    .S(330, { y: 5 }).width(12, 40)
    .L(35, 30).R(35, 30)
    .S(150, { y: 3 }).width(18, 60)
    .R(70, 90, { bank: 8, y: 2 })
    .S(120, { y: 2 }),
  { a0: 400, b0: 200, minA: 250, minB: 100 },
  { minLength: 2800, width: [12, 18], widthSpread: 5.5, kickers: 0 },
);

// 8 — Mountain Pass: a point-to-point climb over banked switchbacks to 18 m and down the other side.
sprint(
  { id: 'mountain-pass', name: 'Mountain Pass', difficulty: 4, width: 13, theme: 'alpine',
    description: 'A 4.5 km sprint over the pass: banked switchbacks up to the summit and a fast, twisting descent.' },
  () => turtle({ width: 14, y: 1, yaw: Math.PI })
    .S(RUN_IN, { y: 1 }) // road behind the start position
    // valley run north, then a steep pull up the first slope
    .S(240, { y: 1 })
    .L(35, 160, { bank: 6 }).R(35, 160, { bank: 6 })
    .S(40).climb(150, 8).S(40).width(13, 40)
    // the climb: three banked switchbacks
    .L(90, 40, { bank: 8 })
    .S(40).climb(150, 11.5).S(30).hairpin('R', 18, { bank: 12 })
    .S(40).climb(150, 14.5).S(30).hairpin('L', 18, { bank: 12 })
    .S(40).climb(150, 17).S(30).hairpin('R', 18, { bank: 12 })
    .climb(240, 17.5)
    // summit ridge
    .S(60).L(30, 90, { bank: 10 }).R(30, 90, { bank: 10 })
    .S(60).hill(240, 0.5).S(200)
    // the descent: three banked switchbacks, steep legs
    .hairpin('R', 19, { bank: 12 })
    .S(30).climb(140, 12.5).S(30).hairpin('L', 19, { bank: 12 })
    .S(30).climb(140, 8).S(30).hairpin('R', 19, { bank: 12 })
    .S(30).climb(140, 4.5).S(30)
    // fast run to the finish
    .L(90, 60, { bank: 8 })
    .climb(200, 3).L(30, 180, { bank: 6 }).R(30, 180, { bank: 6 })
    .S(320, { y: 3 })
    .S(RUN_OFF, { y: 3 }), // run-off after the finish line
  { minLength: 4300, minClimb: 14 },
);

// 9 — Canyon Run: out along one narrow canyon, back along the next; twisty, narrow and jumpy.
circuit(
  { id: 'canyon-run', name: 'Canyon Run', difficulty: 5, width: 11, theme: 'canyon',
    description: 'Out and back through narrow red-rock badlands with jumps, blind crests and tight S-bends: the hardest circuit.' },
  (a, b) => turtle({ width: 13, y: 4, yaw: Math.PI / 2 })
    // out along the south canyon
    .S(a, { y: 4 }).width(11, 40)
    .SR(40, 40, { bank: 6 }, 10)
    .S(40).kicker({ h: 4.5, lead: 15 })
    .SL(55, 26, { bank: 8 }, 10).width(10, 40)
    .S(60, { y: 6 }).hill(170, 2.5, { y: 7 })
    .SR(65, 24, { bank: 8 }, 12)
    .S(80, { y: 9 })
    // far end: a tight double-left onto the north canyon
    .L(90, 22, { bank: 8 }).S(140, { y: 10 }).L(90, 22, { bank: 8 }).width(12, 40)
    // back along the north canyon
    .S(80, { y: 11 }).hill(160, 2, { y: 11 }).S(60)
    .SL(45, 30, { bank: 8 }, 10)
    .kicker({ h: 5, drop: 3 })
    .SR(60, 26, { bank: 10 }, 8).width(10, 40)
    .S(60, { y: 7 })
    .R(90, 20, { bank: 6 }).S(60, { y: 8 }).hairpin('L', 13, { y: 8 }).S(60, { y: 6 }).R(90, 20, { bank: 6 })
    .S(100, { y: 5 }).SL(40, 40, { bank: 6 }, 20).width(13, 40)
    // home: back down to the start straight
    .L(90, 30, { bank: 6 }).S(b, { y: 4 }).L(90, 30, { bank: 6 })
    .S(80, { y: 4 }),
  { a0: 150, b0: 60, minA: 100, minB: 20 },
  { minLength: 2600, width: [10, 13], kickers: 2 },
);

// 10 — Night Highway: long straights joined by slow, heavy-braking corners; the fastest circuit, built for nitro.
circuit(
  { id: 'night-highway', name: 'Night Highway', difficulty: 2, width: 18, theme: 'night',
    description: 'Kilometre-long straights under the lights: brake hard for the slow corners and fire the nitro out of them.' },
  (a, b) => turtle({ width: 18, y: 3 })
    .S(a, { y: 3 })
    .R(90, 28, { bank: 4 }).S(70).R(90, 28, { bank: 4 })
    .S(300, { y: 3 }).hill(400, 3).L(12, 500).R(12, 500).S(200, { y: 4 })
    .R(90, 30, { bank: 4 })
    .S(b, { y: 4 })
    .R(90, 120, { bank: 12 })
    .S(250, { y: 3 })
    .R(90, 45, { bank: 6 })
    .S(60)
    .L(90, 30, { bank: 4 })
    .S(100, { y: 3 }),
  { a0: 650, b0: 160, minA: 450, minB: 100 },
  { minLength: 2800, kickers: 0 },
);

// 11 — Lighthouse Bay: long, constant-radius sweepers round the bay; made for holding drifts.
circuit(
  { id: 'lighthouse-bay', name: 'Lighthouse Bay', difficulty: 3, width: 17, theme: 'seaside',
    description: 'Long sweeping bends round the bay, past the lighthouse: throw the car sideways and hold the drift.' },
  (a, b) => turtle({ width: 18, y: 2 })
    .S(a, { y: 2 }).width(17, 60)
    .L(110, 104, { bank: 4 })
    .S(70, { y: 3 })
    .R(50, 80, { bank: 4 })
    .S(92, { y: 4 })
    .L(40, 92)
    .S(b, { y: 5 })
    .L(140, 63, { bank: 5 })
    .S(126, { y: 6 })
    .L(80, 80, { bank: 4 })
    .R(170, 109, { bank: 5, y: 5 })
    .L(70, 75, { bank: 4, y: 4 })
    .S(92, { y: 3 })
    .L(140, 69, { bank: 5 }).width(18, 60)
    .S(115, { y: 2 }),
  { a0: 185, b0: 80, minA: 120, minB: 40 },
  { minLength: 2200, kickers: 0 },
);

// 12 — Seaside Stunts: a point-to-point run down the coast over six kickers.
sprint(
  { id: 'seaside-stunts', name: 'Seaside Stunts', difficulty: 4, width: 16, theme: 'seaside',
    description: 'Six kickers down the coast road, with step-downs and a 7.5 m launch: line up straight and fly far.' },
  () => turtle({ width: 16, y: 13, yaw: Math.PI / 2 })
    .S(RUN_IN, { y: 13 })
    .S(100, { y: 13 })
    .kicker({ h: 4.5, drop: 2 })
    .L(90, 55, { bank: 8 }).S(30).cp().S(30)
    .kicker({ h: 5.5, drop: 2 })
    .R(100, 50, { bank: 8 }).S(30).cp().S(30)
    .kicker({ h: 7, drop: 1 })
    .R(70, 70, { bank: 6 }).S(30).cp().S(30)
    .kicker({ h: 4, drop: 3 })
    .L(110, 50, { bank: 8 }).S(30).cp().S(30)
    .kicker({ h: 6, drop: 2 })
    .R(70, 80, { bank: 6 }).S(30).cp().S(30)
    .kicker({ h: 7.5, drop: 2 })
    .R(60, 70, { bank: 6 })
    .S(60, { y: 1 }).cp().S(300)
    .S(RUN_OFF, { y: 1 }),
  { minLength: 3000, kickers: 6 },
);

// =============================================================================
// Validation
// =============================================================================
const DEGR = Math.PI / 180;
const angDiff = (a, b) => Math.atan2(Math.sin(a - b), Math.cos(a - b));

function validate(e) {
  const { def, f, req } = e;
  const tr = buildTrack(def);
  const issues = [];
  const fail = (msg) => issues.push(msg);
  const { count, N, closed, segLen, px, pz, py, hw, bank, tx, tz } = tr;
  const n = closed ? N : count;
  const wrap = (i) => (closed ? ((i % N) + N) % N : Math.max(0, Math.min(count - 1, i)));
  const heading = (i) => Math.atan2(tx[wrap(i)], tz[wrap(i)]);
  const L = tr.length;

  // curvature over +-2 samples
  const kappa = new Float64Array(count);
  for (let i = 0; i < count; i++) {
    const a = closed ? i - 2 : Math.max(0, i - 2), b = closed ? i + 2 : Math.min(count - 1, i + 2);
    kappa[i] = angDiff(heading(b), heading(a)) / ((b - a) * segLen);
  }

  // meta
  if (!THEMES.includes(def.theme)) fail(`unknown theme '${def.theme}'`);
  if (!(def.difficulty >= 1 && def.difficulty <= 5)) fail('difficulty must be 1-5');
  if (!def.description || def.description.length > 110) fail('description missing or longer than 110 characters');

  // closure (turtle end vs start) and spline agreement
  const closure = closed ? f.closure : 0;
  if (closed && closure > RULES.closure) fail(`does not close: end is ${closure.toFixed(2)} m from the start`);
  const lenErr = Math.abs(L - f.length);
  if (lenErr > 0.002 * L) fail(`spline length ${L.toFixed(1)} m differs from the design ${f.length.toFixed(1)} m`);
  if (req.minLength && L < req.minLength) fail(`too short: ${L.toFixed(0)} m < ${req.minLength} m`);
  if (req.maxLength && L > req.maxLength) fail(`too long: ${L.toFixed(0)} m > ${req.maxLength} m`);

  // corner radius
  let minR = Infinity, minMargin = Infinity, minRAt = 0;
  for (let i = 0; i < count; i++) {
    if (!closed && (i < 2 || i > count - 3)) continue;
    const r = 1 / Math.max(1e-9, Math.abs(kappa[i]));
    if (r < minR) minR = r;
    if (r - hw[i] < minMargin) { minMargin = r - hw[i]; minRAt = i; }
  }
  if (minMargin < RULES.radiusMargin) fail(`corner too tight at ${(minRAt * segLen).toFixed(0)} m: radius ${(minMargin + hw[minRAt]).toFixed(1)} m < half width ${hw[minRAt].toFixed(1)} + ${RULES.radiusMargin} m`);

  // separation between different parts of the track
  let minClear = Infinity, clearAt = null;
  {
    const cell = 40, grid = new Map();
    const keyOf = (cx, cz) => cx * 100003 + cz;
    for (let i = 0; i < count; i++) {
      const k = keyOf(Math.floor(px[i] / cell), Math.floor(pz[i] / cell));
      if (!grid.has(k)) grid.set(k, []);
      grid.get(k).push(i);
    }
    for (let i = 0; i < count; i++) {
      const cx = Math.floor(px[i] / cell), cz = Math.floor(pz[i] / cell);
      for (let dx = -1; dx <= 1; dx++) for (let dz = -1; dz <= 1; dz++) {
        const list = grid.get(keyOf(cx + dx, cz + dz));
        if (!list) continue;
        for (const j of list) {
          if (j <= i) continue;
          let d = j - i;
          if (closed) d = Math.min(d, N - d);
          const C = hw[i] + hw[j] + RULES.clearance;
          if (d * segLen < Math.max(40, 1.6 * C)) continue;
          const dist = Math.hypot(px[i] - px[j], pz[i] - pz[j]);
          if (dist - C < minClear) { minClear = dist - C; clearAt = [i, j, dist, C]; }
        }
      }
    }
    if (minClear < 0) fail(`parts of the track too close: ${(clearAt[0] * segLen).toFixed(0)} m and ${(clearAt[1] * segLen).toFixed(0)} m are ${clearAt[2].toFixed(1)} m apart (need ${clearAt[3].toFixed(1)} m)`);
  }

  // grades, kickers, crests
  const grade = (i) => (py[wrap(i + 1)] - py[wrap(i - 1)]) / ((closed ? 2 : Math.min(count - 1, i + 1) - Math.max(0, i - 1)) * segLen);
  const zone = new Int8Array(count); // 1 = kicker ramp, 2 = landing slope
  const kick = [];
  for (const k of tr.kickers) {
    const span = (a, b) => { const out = []; for (let i = a; ; i = wrap(i + 1)) { out.push(i); if (i === b || out.length > count) break; } return out; };
    for (const i of span(k.foot, k.lip)) zone[i] = 1;
    for (const i of span(k.lip, k.land)) if (i !== k.lip) zone[i] = 2;
    const rampMax = Math.max(...span(k.foot, k.lip).map(grade));
    const landMin = Math.min(...span(k.lip, k.land).map(grade));
    const landLen = span(k.lip, k.land).length * segLen;
    // straight landing zone: no heading change from the ramp foot to lip + 120 m
    const zoneEnd = k.lip + Math.ceil(RULES.landingZone / segLen);
    let maxTurn = 0;
    for (let i = k.foot; i <= zoneEnd; i++) maxTurn = Math.max(maxTurn, Math.abs(angDiff(heading(i), heading(k.lip))));
    if (!closed && zoneEnd > count - 1) fail(`kicker at ${(k.lip * segLen).toFixed(0)} m: the track ends inside the landing zone`);
    const at = `kicker at ${(k.lip * segLen).toFixed(0)} m`;
    if (rampMax > RULES.maxKickerGrade + 1e-3) fail(`${at}: ramp grade ${(rampMax * 100).toFixed(1)} % > ${RULES.maxKickerGrade * 100} %`);
    if (-landMin > RULES.maxLandingGrade + 1e-3) fail(`${at}: landing slope ${(-landMin * 100).toFixed(1)} % > ${RULES.maxLandingGrade * 100} %`);
    if (landLen > RULES.landingZone) fail(`${at}: landing slope (${landLen.toFixed(0)} m) longer than the landing zone`);
    if (maxTurn > RULES.straightTol * DEGR) fail(`${at}: ramp/landing zone not straight (${(maxTurn / DEGR).toFixed(1)}° heading change within ${RULES.landingZone} m)`);
    const hr = req.kickerHeight ?? [2, 7.5];
    if (k.height < hr[0] - 0.05 || k.height > hr[1] + 0.05) fail(`${at}: height ${k.height.toFixed(1)} m outside ${hr[0]}-${hr[1]} m`);
    kick.push({ ...k, rampMax, landMin, s: k.lip * segLen });
  }
  if (req.kickers && kick.length < req.kickers) fail(`needs at least ${req.kickers} kickers, has ${kick.length}`);
  if (req.kickers === 0 && kick.length) fail('should have no kickers');

  let maxGrade = 0, maxGradeAt = 0, minCrest = Infinity, crestAt = 0;
  const nearKick = (i) => kick.some((k) => {
    const a = k.foot - 8, b = k.land + 8;
    if (closed) { const d = ((i - a) % N + N) % N; return d <= ((b - a) % N + N) % N; }
    return i >= a && i <= b;
  });
  for (let i = 0; i < n; i++) {
    if (!closed && (i < 1 || i > count - 2)) continue;
    const g = grade(i);
    if (zone[i] === 0 && Math.abs(g) > maxGrade) { maxGrade = Math.abs(g); maxGradeAt = i; }
    if (zone[i] === 2 && g > RULES.maxGrade + 1e-3) fail(`climb of ${(g * 100).toFixed(1)} % inside the landing at ${(i * segLen).toFixed(0)} m`);
    if (!closed && (i < 4 || i > count - 5)) continue;
    if (nearKick(i)) continue;
    const ypp = (py[wrap(i + 4)] - 2 * py[i] + py[wrap(i - 4)]) / (4 * segLen) ** 2;
    if (ypp < 0 && -1 / ypp < minCrest) { minCrest = -1 / ypp; crestAt = i; }
  }
  const gradeLimit = req.maxGrade ?? RULES.maxGrade;
  if (maxGrade > gradeLimit + 1e-3) fail(`grade ${(maxGrade * 100).toFixed(1)} % at ${(maxGradeAt * segLen).toFixed(0)} m > ${(gradeLimit * 100).toFixed(0)} %`);
  if (minCrest < RULES.minCrestRadius) fail(`crest at ${(crestAt * segLen).toFixed(0)} m too sharp: vertical radius ${minCrest.toFixed(0)} m < ${RULES.minCrestRadius} m`);

  // heights (and how well the spline reproduced the designed profile)
  let minY = Infinity, maxY = -Infinity, prof = 0;
  for (let i = 0; i < count; i++) {
    minY = Math.min(minY, py[i]); maxY = Math.max(maxY, py[i]);
    prof = Math.max(prof, Math.abs(py[i] - f.profile((i * segLen * f.length) / L)));
  }
  if (minY < RULES.minHeight - 0.01 || maxY > RULES.maxHeight + 0.01) fail(`heights ${minY.toFixed(1)}-${maxY.toFixed(1)} m outside ${RULES.minHeight}-${RULES.maxHeight} m`);
  if (prof > 0.15) fail(`built heights differ from the design by up to ${prof.toFixed(2)} m (banking lift or too few points)`);
  if (req.minClimb && maxY - minY < req.minClimb) fail(`elevation range ${(maxY - minY).toFixed(1)} m < ${req.minClimb} m`);

  // width
  let wMin = Infinity, wMax = 0, taper = 0;
  for (let i = 0; i < count; i++) {
    wMin = Math.min(wMin, 2 * hw[i]); wMax = Math.max(wMax, 2 * hw[i]);
    if (closed || i < count - 1) taper = Math.max(taper, Math.abs(hw[wrap(i + 1)] - hw[i]) / segLen);
  }
  if (req.width && (wMin < req.width[0] - 0.05 || wMax > req.width[1] + 0.05)) fail(`width ${wMin.toFixed(1)}-${wMax.toFixed(1)} m outside ${req.width[0]}-${req.width[1]} m`);
  if (req.widthSpread && wMax - wMin < req.widthSpread - 0.05) fail(`width should vary by >= ${req.widthSpread} m (is ${wMin.toFixed(1)}-${wMax.toFixed(1)} m)`);
  if (taper > RULES.maxTaper) fail(`road width changes too abruptly (${taper.toFixed(2)} m per m)`);

  // banking
  let maxBank = 0;
  for (let i = 0; i < count; i++) maxBank = Math.max(maxBank, Math.abs(bank[i]) / DEGR);
  if (maxBank > RULES.maxBank + 0.5) fail(`banking ${maxBank.toFixed(1)}° > ${RULES.maxBank}°`);
  if (req.bank && (maxBank < req.bank[0] - 0.5 || maxBank > req.bank[1] + 0.5)) fail(`max banking ${maxBank.toFixed(1)}° outside ${req.bank[0]}-${req.bank[1]}°`);

  // hairpins: >= 150° of heading change within 150 m
  let hairpins = 0;
  {
    const W = Math.round(150 / segLen);
    for (let i = 0; i < n - (closed ? 0 : W); i++) {
      let turn = 0;
      for (let k = 0; k < W; k++) turn += angDiff(heading(i + k + 1), heading(i + k));
      if (Math.abs(turn) >= 150 * DEGR) { hairpins++; i += W; }
    }
  }
  if (req.hairpins && hairpins < req.hairpins) fail(`needs >= ${req.hairpins} hairpins, has ${hairpins}`);

  // checkpoints
  const cps = tr.cpSamples;
  const gates = closed ? [0, ...cps.map((c) => c * segLen), L] : [tr.startIdx * segLen, ...cps.map((c) => c * segLen), tr.finishIdx * segLen];
  const gaps = gates.slice(1).map((g, k) => g - gates[k]);
  gaps.forEach((g, k) => {
    if (g < RULES.cpGap[0] || g > RULES.cpGap[1]) fail(`gap ${k + 1} between gates is ${g.toFixed(0)} m (allowed ${RULES.cpGap[0]}-${RULES.cpGap[1]} m)`);
  });
  for (const c of cps) {
    for (const k of kick) {
      let d = c - k.foot;
      if (closed) d = ((d % N) + N + N / 2) % N - N / 2;
      if (d * segLen >= -20 && d * segLen <= (((k.lip - k.foot) % N + N) % N) * segLen + RULES.landingZone) fail(`checkpoint at ${(c * segLen).toFixed(0)} m is on the jump at ${k.s.toFixed(0)} m`);
    }
  }

  // start / finish on straights
  const straightRun = (from, dir, max) => {
    const h0 = heading(from);
    let m = 0;
    for (let k = 1; k * segLen <= max; k++) {
      const i = from + dir * k;
      if (!closed && (i < 0 || i > count - 1)) break;
      if (Math.abs(angDiff(heading(i), h0)) > RULES.straightTol * DEGR) break;
      m = k * segLen;
    }
    return m;
  };
  const startRun = straightRun(tr.startIdx, 1, 400);
  if (startRun < RULES.startStraight) fail(`only ${startRun.toFixed(0)} m of straight after the start (need ${RULES.startStraight})`);
  let startFlat = 0;
  for (let i = tr.startIdx - 6; i <= tr.startIdx + RULES.startStraight / segLen; i++) startFlat = Math.max(startFlat, Math.abs(grade(wrap(i))));
  if (startFlat > 0.04) fail(`start area not flat (grade ${(startFlat * 100).toFixed(1)} %)`);
  if (closed) {
    const back = straightRun(0, -1, RULES.finishStraight);
    if (back < RULES.finishStraight - segLen) fail(`start/finish line not on a straight (${back.toFixed(0)} m straight before it)`);
  } else {
    const back = straightRun(tr.finishIdx, -1, RULES.finishStraight);
    if (back < RULES.finishStraight - segLen) fail(`finish not on a straight (${back.toFixed(0)} m straight before it)`);
    if (def.startAt !== RUN_IN || def.runOff !== RUN_OFF) fail(`sprint needs startAt ${RUN_IN} and runOff ${RUN_OFF} (has ${def.startAt} / ${def.runOff})`);
    const runIn = straightRun(tr.startIdx, -1, RUN_IN);
    if (runIn < tr.startIdx * segLen - segLen) fail(`road before the start is not straight (${runIn.toFixed(0)} m)`);
    const runOut = straightRun(tr.finishIdx, 1, RUN_OFF);
    let runFlat = 0;
    for (let i = tr.finishIdx; i < count - 1; i++) runFlat = Math.max(runFlat, Math.abs(grade(i)));
    if ((count - 1 - tr.finishIdx) * segLen < RUN_OFF - segLen) fail(`only ${((count - 1 - tr.finishIdx) * segLen).toFixed(0)} m of road after the finish (need ${RUN_OFF})`);
    if (runOut < RUN_OFF - 2 * segLen) fail(`run-off after the finish not straight (${runOut.toFixed(0)} m)`);
    if (runFlat > 0.04) fail(`run-off after the finish not flat (grade ${(runFlat * 100).toFixed(1)} %)`);
  }

  return {
    tr, issues, kick, gaps,
    stats: {
      length: L, race: closed ? L : (tr.finishIdx - tr.startIdx) * segLen, laps: closed ? def.laps : 1, minR, minMargin, minY, maxY, maxGrade, minClear, closure,
      wMin, wMax, maxBank, hairpins, cps: cps.length, minCrest, startRun, prof,
      kickGrade: kick.length ? Math.max(...kick.map((k) => k.rampMax)) : 0,
      landGrade: kick.length ? Math.max(...kick.map((k) => -k.landMin)) : 0,
      points: def.points.length,
    },
  };
}

// =============================================================================
// Run
// =============================================================================
// run main() only when executed directly (not when imported); realpath so a
// symlinked project folder still matches import.meta.url
const invokedAs = (() => { try { return pathToFileURL(realpathSync(process.argv[1] ?? '')).href; } catch { return ''; } })();
if (import.meta.url === invokedAs) main();

function main() {
  let failed = 0;
  const results = [];
  for (const d of DESIGNS) {
    let e;
    try {
      e = realise(d);
    } catch (err) {
      console.log(`${d.meta.id.padEnd(16)} ! ${err.message}`);
      failed++;
      continue;
    }
    const r = validate(e);
    results.push({ ...e, ...r });
    const s = r.stats;
    console.log(
      `${e.def.id.padEnd(16)} ${(s.race / 1000).toFixed(2)} km ${e.def.type === 'sprint' ? 'sprint ' : `${s.laps} laps`}  ` +
      `minR ${s.minR.toFixed(1)} (R-hw ${s.minMargin.toFixed(1)})  h ${s.minY.toFixed(1)}-${s.maxY.toFixed(1)} m  grade ${(s.maxGrade * 100).toFixed(1)}%  ` +
      `kick ${r.kick.length}${r.kick.length ? ` (${r.kick.map((k) => k.height.toFixed(1)).join('/')} m, ramp ${(s.kickGrade * 100).toFixed(0)}%, land ${(s.landGrade * 100).toFixed(0)}%)` : ''}  ` +
      `cp ${s.cps} (gaps ${Math.round(Math.min(...r.gaps))}-${Math.round(Math.max(...r.gaps))})  clear +${s.minClear.toFixed(1)}  crestR ${isFinite(s.minCrest) ? s.minCrest.toFixed(0) : '-'}  ` +
      `w ${s.wMin.toFixed(0)}-${s.wMax.toFixed(0)}  bank ${s.maxBank.toFixed(0)}°  hairpins ${s.hairpins}  start ${s.startRun.toFixed(0)} m  ` +
      `${e.def.type === 'circuit' ? `closure ${s.closure.toFixed(3)} m  ` : ''}pts ${s.points}`);
    for (const msg of r.issues) console.log(`   ! ${msg}`);
    if (r.issues.length) failed++;
  }
  const marathon = results.find((r) => r.def.id === 'grand-marathon');
  if (marathon && marathon.stats.race < Math.max(...results.map((r) => r.stats.race))) { console.log('   ! grand-marathon must be the longest track'); failed++; }
  if (new Set(results.map((r) => r.def.id)).size !== results.length) { console.log('   ! duplicate track ids'); failed++; }

  if (!CHECK_ONLY && (!failed || PREVIEW) && results.length) {
    writeFileSync(new URL('../docs/tracks-overview.svg', import.meta.url), overviewSVG(results));
    console.log('wrote docs/tracks-overview.svg');
  }
  if (failed) {
    console.log(`\n${failed} track(s) break the design rules: trackData.js NOT written`);
    process.exit(1);
  }
  if (!CHECK_ONLY) {
    writeFileSync(new URL('../src/tracks/trackData.js', import.meta.url), trackDataJS(results.map((r) => r.def)));
    console.log(`wrote src/tracks/trackData.js (${results.length} tracks, all design rules pass)`);
  } else console.log(`all ${results.length} tracks pass the design rules`);
}

// =============================================================================
// Output: trackData.js
// =============================================================================
function trackDataJS(defs) {
  const fmt = (p, w) => {
    const v = [p[0], p[1], p[2]];
    if (p[3] || p[4] !== w) v.push(p[3]);
    if (p[4] !== w) v.push(p[4]);
    return `[${v.join(', ')}]`;
  };
  let out = `/**
 * trackData.js
 * ------------------------------------------------------------------
 * Track definitions. Each track is plain data:
 *
 *   id          unique id (used for saved best times)
 *   name        display name
 *   difficulty  1-5 stars on the menu
 *   description one sentence shown on the menu
 *   type        'circuit' (closed loop, laps) or 'sprint' (point to point)
 *   laps        laps for circuits
 *   width       default road width in metres
 *   theme       scenery/sky: 'meadow' | 'desert' | 'alpine' | 'canyon' | 'dusk' |
 *               'night' | 'seaside'
 *   startAt     sprints only: metres of road before the cars' start
 *               position (the START line is 12 m behind it; default 6)
 *   runOff      sprints only: metres of road after the FINISH line, so a
 *               car can stop before the road ends (default 10)
 *   checkpoints indices into \`points\` where checkpoint gates stand.
 *               A circuit's start/finish line is at points[0]; a sprint
 *               runs from points[0] to the last point (see startAt/runOff).
 *   points      control points [x, z, height, bankDeg?, widthM?] that the
 *               centre line passes through:
 *                 x, z     metres on the ground plane
 *                 height   metres up (0-18 for the built-in tracks)
 *                 bankDeg  banking angle in degrees; give a positive number,
 *                          it leans into the corner automatically (default 0)
 *                 widthM   road width in metres at this point (default:
 *                          the track's width); changes are smoothed
 *               The plan is a Catmull-Rom spline through x/z, the height a
 *               smooth monotone curve through the heights (see trackBuilder.js).
 *
 * The built-in tracks are generated (and checked against the design rules)
 * by tools/generateTracks.mjs with the turtle helper in tools/turtle.mjs:
 * edit them there and run \`npm run tracks\`. Hand-written points work too.
 */
export const TRACKS = [
`;
  for (const def of defs) {
    const { points, ...meta } = def;
    out += `  {\n`;
    for (const [k, v] of Object.entries(meta)) if (v !== undefined) out += `    ${k}: ${JSON.stringify(v)},\n`;
    out += `    points: [\n`;
    for (let i = 0; i < points.length; i += 4) out += '      ' + points.slice(i, i + 4).map((p) => fmt(p, def.width)).join(', ') + ',\n';
    out += `    ],\n  },\n`;
  }
  out += `];\n`;
  return out;
}

// =============================================================================
// Output: docs/tracks-overview.svg
// =============================================================================
function overviewSVG(results) {
  // sequential blue ramp (light = low, dark = high), 2 m bands from 0 to 18 m
  const RAMP = ['#86b6ef', '#6da7ec', '#5598e7', '#3987e5', '#2a78d6', '#256abf', '#1c5cab', '#184f95', '#0d366b'];
  const band = (y) => Math.max(0, Math.min(RAMP.length - 1, Math.floor(y / 2)));
  const INK = '#0b0b0b', INK2 = '#52514e', MUTED = '#8a8984', SURF = '#fcfcfb', CASING = '#3b3a37', KICK = '#eb6834', START = '#008300';
  const cols = 3, PW = 440, MAPH = 360, PH = MAPH + 112, PAD = 18, TOP = 64;
  const rows = Math.ceil(results.length / cols);
  const W = cols * PW + (cols + 1) * PAD, H = TOP + rows * PH + (rows + 1) * PAD + 70;
  const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');
  const f1 = (v) => v.toFixed(1);
  // greedy word wrap for the panel captions (at most two lines)
  const wrap = (text, max) => {
    const lines = [''];
    for (const word of text.split(' ')) {
      const cur = lines[lines.length - 1];
      if (cur && (cur + ' ' + word).length > max) lines.push(word);
      else lines[lines.length - 1] = cur ? cur + ' ' + word : word;
    }
    return lines.slice(0, 2);
  };
  let s = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" font-family="system-ui, -apple-system, Segoe UI, Roboto, sans-serif">\n`;
  s += `<title>Track Rush: all ${results.length} tracks</title>\n<rect width="${W}" height="${H}" fill="${SURF}"/>\n`;
  s += `<text x="${PAD}" y="34" font-size="22" font-weight="700" fill="${INK}">Track Rush: track overview</text>\n`;
  s += `<text x="${PAD}" y="54" font-size="13" fill="${INK2}">Top view of every track (each panel has its own scale bar). Road colour shows height; generated by tools/generateTracks.mjs.</text>\n`;

  results.forEach((r, idx) => {
    const { tr, def } = r;
    const ox = PAD + (idx % cols) * (PW + PAD), oy = TOP + PAD + Math.floor(idx / cols) * (PH + PAD);
    let minX = Infinity, minZ = Infinity, maxX = -Infinity, maxZ = -Infinity;
    for (let i = 0; i < tr.count; i++) {
      minX = Math.min(minX, tr.px[i] - tr.hw[i]); maxX = Math.max(maxX, tr.px[i] + tr.hw[i]);
      minZ = Math.min(minZ, tr.pz[i] - tr.hw[i]); maxZ = Math.max(maxZ, tr.pz[i] + tr.hw[i]);
    }
    const sc = Math.min((PW - 40) / (maxX - minX), (MAPH - 40) / (maxZ - minZ));
    const cx = ox + PW / 2 - ((minX + maxX) / 2) * sc, cz = oy + MAPH / 2 - ((minZ + maxZ) / 2) * sc;
    const X = (i) => f1(cx + tr.px[i] * sc), Z = (i) => f1(cz + tr.pz[i] * sc);
    s += `<g>\n<rect x="${ox}" y="${oy}" width="${PW}" height="${PH}" rx="8" fill="#ffffff" stroke="#e1e0dc"/>\n`;
    // road casing, then elevation bands
    const last = tr.closed ? tr.count : tr.count - 1;
    // polyline through samples a..b, skipping samples closer than 2 px to the last one drawn
    const poly = (a, b) => {
      let d = `M${X(a % tr.count)},${Z(a % tr.count)}`, lx = tr.px[a % tr.count], lz = tr.pz[a % tr.count];
      for (let i = a + 1; i <= b; i++) {
        const k = i % tr.count;
        if (i < b && Math.hypot(tr.px[k] - lx, tr.pz[k] - lz) * sc < 2) continue;
        d += `L${X(k)},${Z(k)}`; lx = tr.px[k]; lz = tr.pz[k];
      }
      return d;
    };
    const d = poly(0, last);
    const roadW = (i) => Math.max(2.5, 2 * tr.hw[i] * sc);
    const wAvg = tr.hw.reduce((a, b) => a + b, 0) / tr.count;
    s += `<path d="${d}" fill="none" stroke="${CASING}" stroke-width="${f1(Math.max(4, 2 * wAvg * sc + 2.5))}" stroke-linejoin="round" stroke-linecap="round"/>\n`;
    let i = 0;
    while (i < last) {
      const b = band(tr.py[i]), w = roadW(i);
      let j = i;
      while (j < last && band(tr.py[j % tr.count]) === b && Math.abs(roadW(j % tr.count) - w) < 0.6) j++;
      s += `<path d="${poly(i, j)}" fill="none" stroke="${RAMP[b]}" stroke-width="${f1(w)}" stroke-linejoin="round"/>\n`;
      i = j;
    }
    // kickers
    for (const k of r.kick) {
      const a = Math.atan2(tr.tz[k.lip], tr.tx[k.lip]) * 180 / Math.PI;
      s += `<g transform="translate(${X(k.lip)},${Z(k.lip)}) rotate(${f1(a)})"><title>Kicker ${k.height.toFixed(1)} m</title><path d="M7,0 L-5,-6 L-5,6 Z" fill="${KICK}" stroke="#ffffff" stroke-width="1.5"/></g>\n`;
    }
    // checkpoints
    tr.cpSamples.forEach((c, k) => {
      s += `<g><title>Checkpoint ${k + 1}</title><circle cx="${X(c)}" cy="${Z(c)}" r="7.5" fill="#ffffff" stroke="${INK}" stroke-width="1.5"/>` +
        `<text x="${X(c)}" y="${f1(cz + tr.pz[c] * sc + 3.5)}" font-size="9.5" font-weight="700" text-anchor="middle" fill="${INK}">${k + 1}</text></g>\n`;
    });
    // finish (sprint) and start arrow
    if (!tr.closed) {
      const fi = tr.finishIdx;
      s += `<g transform="translate(${X(fi)},${Z(fi)})"><title>Finish</title><rect x="-7" y="-7" width="14" height="14" fill="#ffffff" stroke="${INK}" stroke-width="1.5"/>` +
        `<rect x="-7" y="-7" width="7" height="7" fill="${INK}"/><rect x="0" y="0" width="7" height="7" fill="${INK}"/></g>\n`;
    }
    {
      const si = tr.startIdx;
      const a = Math.atan2(tr.tz[si], tr.tx[si]) * 180 / Math.PI;
      s += `<g transform="translate(${X(si)},${Z(si)}) rotate(${f1(a)})"><title>Start</title><path d="M11,0 L-6,-8 L-2,0 L-6,8 Z" fill="${START}" stroke="#ffffff" stroke-width="1.8" stroke-linejoin="round"/></g>\n`;
    }
    // scale bar
    const bar = [50, 100, 200, 250, 500].reduce((best, m) => (m * sc <= 110 ? m : best), 50);
    const bx = ox + PW - 20 - bar * sc, by = oy + MAPH - 8;
    s += `<path d="M${f1(bx)},${by - 4}V${by}H${f1(bx + bar * sc)}V${by - 4}" fill="none" stroke="${INK2}" stroke-width="1.5"/>` +
      `<text x="${f1(bx + (bar * sc) / 2)}" y="${by - 7}" font-size="10.5" text-anchor="middle" fill="${INK2}">${bar} m</text>\n`;
    // caption
    const st = r.stats;
    const stars = '★'.repeat(def.difficulty) + '☆'.repeat(5 - def.difficulty);
    const kind = def.type === 'sprint' ? `sprint · ${(st.race / 1000).toFixed(2)} km` : `${def.laps} laps · ${(st.length / 1000).toFixed(2)} km per lap`;
    s += `<text x="${ox + 14}" y="${oy + MAPH + 24}" font-size="16" font-weight="700" fill="${INK}">${idx + 1}  ${esc(def.name)}</text>` +
      `<text x="${ox + PW - 14}" y="${oy + MAPH + 24}" font-size="14" text-anchor="end" fill="${INK2}">${stars}</text>\n`;
    s += `<text x="${ox + 14}" y="${oy + MAPH + 44}" font-size="12.5" fill="${INK2}">${kind} · ${def.theme} · width ${st.wMin.toFixed(0)}${st.wMax - st.wMin > 0.5 ? '-' + st.wMax.toFixed(0) : ''} m</text>\n`;
    s += `<text x="${ox + 14}" y="${oy + MAPH + 62}" font-size="12.5" fill="${INK2}">height ${st.minY.toFixed(0)}-${st.maxY.toFixed(0)} m · ${st.cps} checkpoints · ${r.kick.length} jump${r.kick.length === 1 ? '' : 's'} · tightest radius ${st.minR.toFixed(0)} m</text>\n`;
    wrap(def.description, 64).forEach((line, k) => {
      s += `<text x="${ox + 14}" y="${oy + MAPH + 81 + k * 16}" font-size="12" fill="${MUTED}">${esc(line)}</text>\n`;
    });
    s += `</g>\n`;
  });

  // legend
  const ly = H - 52;
  s += `<text x="${PAD}" y="${ly}" font-size="13" font-weight="700" fill="${INK}">Height (m)</text>\n`;
  const lx0 = PAD + 86;
  RAMP.forEach((c, k) => {
    s += `<rect x="${lx0 + k * 30 + 1}" y="${ly - 12}" width="28" height="14" fill="${c}"/>\n`;
  });
  for (let k = 0; k <= RAMP.length; k++) {
    s += `<text x="${lx0 + k * 30}" y="${ly + 16}" font-size="10.5" text-anchor="middle" fill="${INK2}">${k * 2}</text>\n`;
  }
  const lx = lx0 + RAMP.length * 30 + 44;
  s += `<g transform="translate(${lx},${ly - 5})"><path d="M11,0 L-6,-8 L-2,0 L-6,8 Z" fill="${START}" stroke="#ffffff" stroke-width="1.8"/></g><text x="${lx + 16}" y="${ly}" font-size="12.5" fill="${INK2}">start, pointing the way to drive</text>\n`;
  s += `<g transform="translate(${lx + 230},${ly - 5})"><circle r="7.5" fill="#ffffff" stroke="${INK}" stroke-width="1.5"/><text y="3.5" font-size="9.5" font-weight="700" text-anchor="middle" fill="${INK}">1</text></g><text x="${lx + 244}" y="${ly}" font-size="12.5" fill="${INK2}">checkpoint, in order</text>\n`;
  s += `<g transform="translate(${lx + 400},${ly - 5})"><path d="M7,0 L-5,-6 L-5,6 Z" fill="${KICK}" stroke="#ffffff" stroke-width="1.5"/></g><text x="${lx + 414}" y="${ly}" font-size="12.5" fill="${INK2}">kicker jump (lip)</text>\n`;
  s += `<g transform="translate(${lx + 560},${ly - 5})"><rect x="-7" y="-7" width="14" height="14" fill="#ffffff" stroke="${INK}" stroke-width="1.5"/><rect x="-7" y="-7" width="7" height="7" fill="${INK}"/><rect x="0" y="0" width="7" height="7" fill="${INK}"/></g><text x="${lx + 574}" y="${ly}" font-size="12.5" fill="${INK2}">sprint finish (circuits finish at the start)</text>\n`;
  s += `</svg>\n`;
  return s;
}
