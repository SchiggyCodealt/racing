/**
 * score.js
 * ------------------------------------------------------------------
 * Style points for clean driving (v4). No DOM and no Three.js: the same
 * scorer runs in the browser (PlayMode, for the player's car only) and in
 * Node (npm test, tools). It reads nothing but the car's plain state and the
 * race's gates, once per fixed 60 Hz physics step, so a run always scores
 * exactly the same.
 *
 * Use:
 *   const score = new ScoreState(track);    // {nitro: false}: score only, no refills
 *   ... each step, after stepCar and race.update:
 *   const events = score.update(car, race, dt); // null, or [{kind, points, text, ...}]
 *   ... when the player respawns:      score.respawn()
 *   score.total, score.multiplier, score.live (the drift / jump / wall contact in progress), score.breakdown()
 *
 * Rules (the numbers are in SCORE below):
 *  - Clean checkpoint: a gate (checkpoint, lap line or finish) reached
 *    without touching a wall or respawning since the gate before scores
 *    cpPoints × the combo multiplier. The multiplier starts at x1 and grows
 *    by one with every clean gate in a row, up to x comboMax. A wall contact
 *    or a respawn drops it back to x1 and spoils the section being driven
 *    (its gate scores nothing).
 *  - Drift: while the car slides on the ground at driftOn or more between
 *    heading and travel (body slip angle) above driftSpeed, points build up:
 *    driftRate a second at 30° and 90 km/h, in proportion to the angle (up
 *    to driftMaxAngle) and the speed, and growing to twice that over the
 *    first driftHold seconds of one drift. The drift ends once the slip stays
 *    under driftOff for driftGrace s; it is banked if it lasted driftMin s.
 *    A wall contact loses it, and so does a spin (slip over driftSpin).
 *    In the air the drift just waits for the landing.
 *  - Air: airRate points per second of flight (flights of airMin s and
 *    more), banked once the car has landed cleanly: not crooked (slip under
 *    airCrooked at touchdown) and no wall contact for airSettle s after.
 *  - Close call: passing within closeGap m of a wall above closeSpeed
 *    without touching it: closePoints once the car is clear of it again
 *    (closeSettle s with no contact); then nothing for closeWait s.
 *  - Wall: every new contact (car.hitWall, a glancing touch too) costs
 *    wallPoints + wallImpact × the speed it took into the wall (m/s, the
 *    sum of car.wallImpact over the contact), plus scrapeRate a second of
 *    contact past scrapeAfter s, at most wallMax. Touches less than
 *    wallMerge s apart are one contact (penalty and count), but each touch
 *    spoils the section it happens in: a gate passed between two of them
 *    does not carry the first one over into the next section.
 *    It is shown live while it lasts and taken when it ends.
 *  - Respawn: respawnPoints.
 *  - New road only: drifts, jumps and close calls score only where the car
 *    is no more than replayGap m behind the furthest it has got in this
 *    run (car.prog, the high-water mark). After a respawn to the last
 *    checkpoint, or after turning round to drive back, the road already
 *    driven scores none of them again until the car is past that mark, so
 *    a kicker can't be jumped twice for points (or nitro).
 *  - Clean lap: a lap of a circuit without a wall contact or a respawn:
 *    cleanLap. Clean run: the whole race without one: cleanRun at the finish.
 *  Penalties never take the score below zero (they take what there is).
 *
 * Nitro: every point banked (penalties aside) refills the car's tank by
 * 1 / pointsPerTank of a full tank (addNitro, car.js), so a clean, flowing
 * lap of 2-3 km refills about one tank and drifts and jumps fill it faster.
 * Respawns refill nothing, and neither do the points banked at the finish.
 *
 * SCORE_RULES tags stored best scores (storage.js): bump it when the rules
 * or the numbers change, so old best scores aren't compared with new ones.
 */
import { addNitro, CAR } from '../physics/car.js';

export const SCORE_RULES = 1;

const DEG = Math.PI / 180;

export const SCORE = {
  cpPoints: 500,       // a clean checkpoint, × the combo multiplier
  comboMax: 5,         // highest multiplier
  driftOn: 12 * DEG,   // body slip angle that starts a drift ...
  driftOff: 8 * DEG,   // ... and keeps it going
  driftSpeed: 12,      // m/s to start a drift (43 km/h) ...
  driftKeep: 9,        // ... and to keep it going
  driftRate: 600,      // points a second at 30° and 25 m/s (90 km/h), in proportion to both
  driftMaxAngle: 45 * DEG, // more angle than this scores no more
  driftMaxSpeed: 50,   // m/s, nor does more speed
  driftHold: 3,        // s: the rate grows to twice this over the first driftHold s of a drift
  driftGrace: 0.3,     // s under driftOff before a drift ends
  driftMin: 0.6,       // s a drift must last to count
  driftSpin: 100 * DEG, // slip angle that counts as a spin (the drift is lost)
  airRate: 500,        // points a second of flight
  airMin: 0.5,         // s of flight that count (crest hops don't)
  airCrooked: 25 * DEG, // slip angle at touchdown above which the landing is crooked (no points)
  airSettle: 0.5,      // s after touchdown without a wall contact before the jump is banked
  closePoints: 250,    // a close call
  closeGap: 0.5,       // m between the car's capsule and the wall
  closeSpeed: 30,      // m/s (108 km/h)
  closeSettle: 0.3,    // s clear of the wall (no contact) before it counts
  closeWait: 2,        // s after a close call before the next can count
  wallPoints: 150,     // a wall contact ...
  wallImpact: 25,      // ... + this per m/s of speed into the wall ...
  scrapeRate: 200,     // ... + this a second of contact ...
  scrapeAfter: 0.5,    // ... past the first scrapeAfter s ...
  wallMax: 1500,       // ... at most
  wallMerge: 0.4,      // s: touches closer together than this are one contact
  respawnPoints: 500,
  replayGap: 15,       // m behind the furthest point reached that still count as new road (a spin, a slide back)
  cleanLap: 2000,      // a circuit lap without a wall contact or respawn
  cleanRun: 5000,      // the whole race without one
  pointsPerTank: 16000, // points that refill one full nitro tank
};

/** Category keys of the breakdown, in the order the finish panel lists them. */
export const CATEGORIES = ['checkpoints', 'drift', 'air', 'close', 'laps', 'run', 'walls', 'respawns'];

/** 12345 -> '12,345' (whole points; a minus sign for negatives). */
export function formatPoints(n) {
  const v = Math.round(n);
  return `${v < 0 ? '−' : ''}${String(Math.abs(v)).replace(/\B(?=(\d{3})+(?!\d))/g, ',')}`;
}

const round10 = (x) => Math.round(x / 10) * 10;

/** Body slip angle (rad): between the car's heading and where it is going; over 90° it moves backwards. */
function slipAngle(car) {
  return Math.atan2(Math.abs(car.sideSpeed), car.forwardSpeed);
}

/** The flight label for `t` s of air. */
const airText = (t) => (t >= 2.5 ? 'Huge air' : t >= 1.5 ? 'Big air' : 'Air');

export class ScoreState {
  /**
   * @param track  the built track
   * @param opts   {nitro: true}: banked points refill the car's nitro tank (false: score only)
   */
  constructor(track, { nitro = true } = {}) {
    this.track = track;
    this.refill = nitro;
    this.reset();
  }

  reset() {
    this.total = 0;
    this.combo = 0;                  // clean gates in a row
    this.points = Object.fromEntries(CATEGORIES.map((k) => [k, 0])); // per category (penalties negative)
    this.counts = {
      gates: 0, cleanGates: 0, bestMult: 1, laps: 0, cleanLaps: 0, drifts: 0, bestDrift: 0,
      airs: 0, bestAir: 0, closeCalls: 0, wallHits: 0, respawns: 0,
    };
    this.nitro = 0;                  // tanks the banked points refilled (what actually went in: the tank holds 1)
    this.nitroEarned = 0;            // tanks the points banked before the finish were worth
    this.gate = 0;                   // the race's next gate as of the last update
    this.section = true;             // no wall contact or respawn since the last gate ...
    this.lap = true;                 // ... this lap ...
    this.run = true;                 // ... this race
    this.finished = false;
    this.reach = -Infinity;          // the furthest car.prog of this run (samples): new road starts replayGap m behind it
    this.drift = null;               // {t, points, grace} while drifting
    this.flight = null;              // {t, lost} while in the air (lost from take-off on road already driven)
    this.landing = null;             // {t, points, settle} after a touchdown, until it is banked
    this.wall = null;                // {t, impact, off} during a wall contact
    this.near = null;                // {settle} after passing close to a wall
    this.closeCool = 0;
    this.wallComboLost = false;      // the current wall contact broke a combo
    this.out = null;                 // this step's events
  }

  /** The multiplier the next clean checkpoint gets (x1 .. x comboMax). */
  get multiplier() {
    return Math.min(SCORE.comboMax, this.combo + 1);
  }

  /**
   * What is building up right now, for the HUD (null: nothing): a wall
   * contact {kind: 'wall', points (negative)}, a jump {kind: 'air', points,
   * time} (from airMin s of flight until it is banked) or a drift
   * {kind: 'drift', points, time} (from a quarter second).
   */
  get live() {
    if (this.wall) return { kind: 'wall', points: -Math.min(this.total, this.wallPenalty()) || 0, time: this.wall.t };
    if (this.landing) return { kind: 'air', points: this.landing.points, time: this.landing.t };
    if (this.flight && !this.flight.lost && this.flight.t >= SCORE.airMin) return { kind: 'air', points: round10(this.flight.t * SCORE.airRate), time: this.flight.t };
    if (this.drift && this.drift.t >= 0.25) return { kind: 'drift', points: round10(this.drift.points), time: this.drift.t };
    return null;
  }

  /**
   * One physics step, after stepCar and race.update. Returns this step's
   * events (in order) or null. Event: {kind, points, text} plus
   * kind 'cp': mult; 'drift' / 'air': time; 'wall': impact; and
   * comboLost (the multiplier was above x1) on wall and respawn events.
   * Kinds: cp, drift, air, close, lap, run (points > 0); wall, respawn
   * (points ≤ 0); driftLost, airLost (0).
   */
  update(car, race, dt) {
    if (this.finished) return null;
    this.out = null;
    this.car = car;
    const P = SCORE;
    const slip = slipAngle(car);
    // new road: not more than replayGap m behind the furthest point of this run
    if (car.prog > this.reach) this.reach = car.prog;
    const fresh = car.prog >= this.reach - P.replayGap / this.track.segLen;

    // --- walls: a contact spoils the section, the lap, the run and anything building up
    if (car.hitWall) {
      if (!this.wall) {
        this.wall = { t: 0, impact: 0, off: 0 };
        this.counts.wallHits++;
        this.wallComboLost = this.spoil();
      } else if (this.section && this.spoil()) {
        // a touch merged into a contact from before the last gate spoils this section too
        this.wallComboLost = true;
      }
      const w = this.wall;
      w.t += dt;
      w.off = 0;
      w.impact += car.wallImpact;
    } else if (this.wall && (this.wall.off += dt) >= P.wallMerge) this.endWall();

    // --- air: banked after a clean landing (a take-off from road already driven scores nothing)
    if (!car.grounded) {
      this.flight ??= { t: 0, lost: !fresh };
      this.flight.t += dt;
    } else if (this.flight) {
      const f = this.flight;
      this.flight = null;
      if (!f.lost && f.t >= P.airMin) {
        if (slip > P.airCrooked) this.emit({ kind: 'airLost', points: 0, text: 'Crooked landing' });
        else this.landing = { t: f.t, points: round10(f.t * P.airRate), settle: 0 };
      }
    }
    if (this.landing && (this.landing.settle += dt) >= P.airSettle) this.bankAir();

    // --- drift: builds up while sliding on the ground, banked when it ends cleanly
    const d = this.drift;
    if (!d) {
      if (fresh && car.grounded && !this.wall && car.speed >= P.driftSpeed && slip >= P.driftOn && slip < P.driftSpin) {
        this.drift = { t: 0, points: 0, grace: 0 };
        this.driftStep(car, slip, dt);
      }
    } else if (slip >= P.driftSpin) {
      this.drift = null;
      if (d.t >= P.driftMin) this.emit({ kind: 'driftLost', points: 0, text: 'Spin: drift lost' });
    } else if (car.grounded) {
      if (slip >= P.driftOff && car.speed >= P.driftKeep) {
        d.grace = 0;
        this.driftStep(car, slip, dt);
      } else if ((d.grace += dt) >= P.driftGrace) this.endDrift();
    }

    // --- close calls: near a wall at speed without touching it
    if (this.closeCool > 0) this.closeCool -= dt;
    if (fresh && car.grounded && !this.wall && car.speed >= P.closeSpeed && this.closeCool <= 0 && this.clearance(car) < P.closeGap) {
      this.near = { settle: 0 };
    } else if (this.near && (this.near.settle += dt) >= P.closeSettle) {
      this.near = null;
      this.closeCool = P.closeWait;
      this.counts.closeCalls++;
      this.bank('close', P.closePoints, { kind: 'close', text: 'Close call' });
    }

    // --- gates
    while (this.gate < race.nextGate) this.onGate(race.gates[this.gate++]);
    const out = this.out;
    this.out = null;
    return out;
  }

  /** The player went back to the last checkpoint: a penalty, and the combo, the section and anything building up are lost. */
  respawn() {
    if (this.finished) return null;
    this.out = null;
    if (this.wall) this.endWall();
    this.counts.respawns++;
    const comboLost = this.spoil();
    this.flight = null; // the car is back on the road
    this.penalty('respawns', SCORE.respawnPoints, { kind: 'respawn', text: 'Respawn', comboLost });
    const out = this.out;
    this.out = null;
    return out;
  }

  /**
   * The finish panel's lines: [{key, label, points, note}] for every category
   * that scored something, plus the checkpoints always and walls and respawns
   * whenever there were any (even when the score had nothing left to take).
   */
  breakdown() {
    const c = this.counts, p = this.points;
    const rows = [
      ['checkpoints', 'Clean checkpoints', `${c.cleanGates} of ${c.gates} · best x${c.bestMult}`],
      ['drift', 'Drifts', c.drifts ? `${c.drifts} · best ${formatPoints(c.bestDrift)}` : ''],
      ['air', 'Air', c.airs ? `${c.airs} · longest ${c.bestAir.toFixed(1)} s` : ''],
      ['close', 'Close calls', c.closeCalls ? String(c.closeCalls) : ''],
      ['laps', 'Clean laps', c.laps ? `${c.cleanLaps} of ${c.laps}` : ''],
      ['run', 'Clean run', ''],
      ['walls', 'Walls', `${c.wallHits} ${c.wallHits === 1 ? 'contact' : 'contacts'}`],
      ['respawns', 'Respawns', String(c.respawns)],
    ];
    return rows
      .filter(([k]) => p[k] !== 0 || k === 'checkpoints' || (k === 'walls' && c.wallHits > 0) || (k === 'respawns' && c.respawns > 0))
      .map(([key, label, note]) => ({ key, label, points: p[key], note }));
  }

  // ---------------------------------------------------------------- internals

  emit(ev) {
    (this.out ??= []).push(ev);
  }

  /** Add points to a category and the total; they refill the car's nitro tank (not at the finish: the race is over). */
  bank(cat, pts, ev) {
    if (pts <= 0) return;
    this.total += pts;
    this.points[cat] += pts;
    if (!this.finished) {
      const tanks = pts / SCORE.pointsPerTank, car = this.car;
      this.nitroEarned += tanks;
      if (this.refill && car) {
        const before = car.nitro;
        addNitro(car, tanks);
        this.nitro += car.nitro - before;
      }
    }
    this.emit({ ...ev, points: pts });
  }

  /** Take up to `pts` points (never below zero). */
  penalty(cat, pts, ev) {
    const took = Math.min(this.total, Math.max(0, pts));
    this.total -= took;
    this.points[cat] -= took;
    this.emit({ ...ev, points: took ? -took : 0 });
  }

  /** A wall contact or respawn: the combo, the section, the lap and the run are no longer clean; drift and jump are lost. Returns whether a combo was lost. */
  spoil() {
    const comboLost = this.combo > 0;
    this.combo = 0;
    this.section = this.lap = this.run = false;
    if (this.drift) {
      if (this.drift.t >= SCORE.driftMin) this.emit({ kind: 'driftLost', points: 0, text: 'Drift lost' });
      this.drift = null;
    }
    if (this.landing || (this.flight && !this.flight.lost && this.flight.t >= SCORE.airMin)) {
      this.emit({ kind: 'airLost', points: 0, text: 'Air lost' });
    }
    this.landing = null;
    if (this.flight) this.flight.lost = true;
    this.near = null;
    return comboLost;
  }

  wallPenalty() {
    const w = this.wall, P = SCORE;
    return round10(Math.min(P.wallMax, P.wallPoints + P.wallImpact * w.impact + P.scrapeRate * Math.max(0, w.t - P.scrapeAfter)));
  }

  endWall() {
    const pts = this.wallPenalty(), impact = this.wall.impact;
    this.wall = null;
    this.penalty('walls', pts, { kind: 'wall', text: 'Wall', impact, comboLost: !!this.wallComboLost });
  }

  driftStep(car, slip, dt) {
    const d = this.drift, P = SCORE;
    d.t += dt;
    const angle = Math.min(slip, P.driftMaxAngle) / (30 * DEG);
    const speed = Math.min(car.speed, P.driftMaxSpeed) / 25;
    d.points += P.driftRate * angle * speed * (1 + Math.min(d.t, P.driftHold) / P.driftHold) * dt;
  }

  endDrift() {
    const d = this.drift;
    this.drift = null;
    const pts = round10(d.points);
    if (d.t < SCORE.driftMin || pts <= 0) return;
    this.counts.drifts++;
    this.counts.bestDrift = Math.max(this.counts.bestDrift, pts);
    this.bank('drift', pts, { kind: 'drift', text: 'Drift', time: d.t });
  }

  bankAir() {
    const l = this.landing;
    this.landing = null;
    this.counts.airs++;
    this.counts.bestAir = Math.max(this.counts.bestAir, l.t);
    this.bank('air', l.points, { kind: 'air', text: airText(l.t), time: l.t });
  }

  /** Gap (m) between the car's capsule and the nearer wall (walls run at ±hw from the centre line). */
  clearance(car) {
    const tr = this.track, i = car.idx, S = car.spec ?? CAR;
    const fn = Math.sin(car.yaw) * tr.nx[i] + Math.cos(car.yaw) * tr.nz[i]; // heading across the road
    const reach = Math.abs(car.lat) + Math.abs(fn) * (S.halfLength - S.radius) + S.radius;
    return tr.hw[i] - reach;
  }

  onGate(g) {
    const P = SCORE, c = this.counts;
    c.gates++;
    if (g.kind === 'finish') this.finished = true; // the race is over: its last points refill no nitro
    if (this.section) {
      const mult = this.multiplier;
      this.combo++;
      c.cleanGates++;
      c.bestMult = Math.max(c.bestMult, mult);
      this.bank('checkpoints', P.cpPoints * mult, { kind: 'cp', text: g.kind === 'finish' ? 'Clean finish' : 'Clean checkpoint', mult });
    }
    // a car touching the wall right at the gate spoils the next section too (a touch that has
    // already ended doesn't, though its penalty is still waiting out the merge window)
    const touching = !!this.wall && this.wall.off === 0;
    this.section = !touching;
    if (this.track.closed && (g.kind === 'lap' || g.kind === 'finish')) {
      c.laps++;
      if (this.lap) {
        c.cleanLaps++;
        this.bank('laps', P.cleanLap, { kind: 'lap', text: 'Clean lap' });
      }
      this.lap = !touching;
    }
    if (g.kind !== 'finish') return;
    // the finish: bank what was building up cleanly, then the clean run
    if (this.wall) this.endWall();
    if (this.drift) this.endDrift();
    if (this.landing) this.bankAir();
    this.flight = null;
    this.near = null;
    if (this.run) this.bank('run', P.cleanRun, { kind: 'run', text: 'Clean run' });
  }
}
