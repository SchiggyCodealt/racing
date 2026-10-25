/**
 * playMode.js
 * ------------------------------------------------------------------
 * A race on one track. Three flavours:
 *   driver 'human'                 you drive
 *   driver 'human' + ghost network you race a see-through AI car
 *   driver 'ai'                    watch the AI drive (with its live network)
 * The player drives with the keyboard or a gamepad (input.js; the pad's
 * buttons sit next to the keys: Back (View) restart, B respawn, Y ghost,
 * Start (Menu) menu; the HUD names them View and Menu, as printed on the pad).
 *
 * v4: the player drives the car picked on the menu (cars.js, remembered as
 * the 'car' setting; Shift / X / RB burns its nitro tank, full at every
 * start, kept on respawn). The watched AI and the AI ghost are always the
 * racer they were trained with, and never use nitro.
 *
 * Best times, ghosts and medals are per track and car (v4): the player's
 * runs are recorded (replay.js); a new personal best with the car is saved
 * as that track and car's ghost. In plain Drive the best run's ghost of the
 * car you drive races along (G shows / hides it, remembered), drawn as that
 * car with its nitro flames. It is only drawn: it never collides and counts
 * for nothing. It runs on the race clock: physics steps since GO, the same
 * count the recording was made with. (Watch the AI compares with your best
 * with the racer, the AI's car.)
 *
 * Medal times (src/tracks/medals.js, made by tools/medals.mjs for exactly
 * this race with each car): the HUD shows the next medal above your best
 * time with the car, the finish panel the medal the run earned and whether
 * it is new. The medal you hold always comes from the stored best time;
 * nothing else is saved for it.
 *
 * Style score (v4, score.js): the player's runs (Drive and Race the AI
 * ghost, not Watch the AI) score points for clean checkpoints (with a combo
 * multiplier), drifts, jumps and close calls, and lose some for wall
 * contacts and respawns. Banked points refill the car's nitro tank. The HUD
 * shows the score, the combo, what is building up and a popup per event;
 * the finish panel the breakdown and the best score for this track and car
 * (storage.js).
 *
 * Physics runs at a fixed 60 Hz (the same step the AI trains with);
 * rendering interpolates between steps so high refresh screens stay smooth.
 *
 * AI cars (watched or ghost) are not eliminated by walls here. If one makes
 * no progress for STUCK_TIME seconds (e.g. nose against a wall: v2 walls
 * don't bounce cars back), it is put back at its last checkpoint, like a
 * player pressing Enter.
 */
import { createCar, placeCar, stepCar } from '../physics/car.js';
import { getCar, DEFAULT_CAR } from '../physics/cars.js';
import { RaceState, formatTime, formatDelta } from './race.js';
import { CarModel, SensorRays } from './carMesh.js';
import { ChaseCamera } from './camera.js';
import { AIDriver, SENSOR_RANGE } from '../ai/sensors.js';
import { getRecord, submitRecord, loadGhost, saveGhost, getSetting, setSetting, getBestScore, submitScore } from './storage.js';
import { ScoreState, formatPoints } from './score.js';
import { GhostRecorder, GhostPlayer, packGhost, unpackGhost } from './replay.js';
import { medalTimes, medalFor, nextMedal, MEDAL_ORDER, MEDAL_NAMES } from '../tracks/medals.js';
import { NetworkView } from '../ui/networkView.js';

const STEP = 1 / 60;
const COUNTDOWN = 3;
const STUCK_TIME = 3; // s without progress before an AI car is respawned
const COAST = { steer: 0, throttle: 0, handbrake: false };
const PB_COLOR = 0x8fd6ff;  // the best-run ghost (the AI ghost is purple)
const NOTE_TIME = 2.5;      // s a HUD note (ghost on / off) stays up
const POPS_KEPT = 8;        // score events kept for the HUD between two frames

/** A time difference for the finish panel, green when it is ahead (negative) and red when behind. */
const delta = (d) => `<span class="delta ${d <= 0 ? 'faster' : 'slower'}">${formatDelta(d)}</span>`;

export class PlayMode {
  /**
   * @param app   shared app context (see main.js)
   * @param opts  {track, driver: 'human'|'ai', net?: NeuralNetwork, ghost?: bool, returnTo?: () => void}
   */
  constructor(app, opts) {
    this.app = app;
    this.track = opts.track;
    this.driver = opts.driver;
    this.net = opts.net ?? null;
    this.withGhost = !!opts.ghost && !!this.net && this.driver === 'human';
    // the player's car (opts.car or the one picked on the menu); the AI always drives the racer
    this.carDef = getCar(this.driver === 'human' ? opts.car ?? getSetting('car') : DEFAULT_CAR);
    this.rec = this.driver === 'human' ? new GhostRecorder() : null;
    this.pbShown = getSetting('ghost');
    this.medals = medalTimes(this.track, this.carDef.id); // null if none were made for this track's race, car, physics and scoring
    this.returnTo = opts.returnTo ?? (() => app.showMenu());
    this.ctrl = { steer: 0, throttle: 0, handbrake: false };
    this.prev = {};
    this.view = {};
  }

  enter() {
    const { app, track } = this;
    this.meshes = app.showTrack(track);
    // the player's car in its own colours; the watched AI is the racer in yellow
    this.model = new CarModel({ car: this.carDef.id, color: this.driver === 'ai' ? 0xffc83d : undefined });
    app.world.scene.add(this.model.root);
    if (this.withGhost) {
      this.ghostModel = new CarModel({ color: 0xb36bff, ghost: true });
      app.world.scene.add(this.ghostModel.root);
    } else if (this.driver === 'human') {
      // your best run on this track with this car (if there is one yet), drawn as that car
      this.pb = this.loadPB();
      this.pbModel = new CarModel({ color: PB_COLOR, ghost: true, car: this.carDef.id });
      this.pbModel.root.visible = false;
      app.world.scene.add(this.pbModel.root);
    }
    if (this.driver === 'ai') {
      this.ai = new AIDriver(this.net);
      this.rays = new SensorRays();
      app.world.scene.add(this.rays.group);
      this.netView = new NetworkView(document.getElementById('watch-net'));
      document.getElementById('watch-panel').classList.remove('hidden');
    }
    this.camera = new ChaseCamera(app.world.camera);
    app.hud.show(true);
    const car = this.carDef.name;
    app.hud.setMode(
      this.driver === 'ai' ? `WATCHING AI · ${track.name}` : this.withGhost ? `VS AI GHOST · ${track.name} · ${car}` : `${track.name} · ${car}`,
    );
    app.hud.setKeys([ // [key, what, gamepad button] (input.js)
      ...(this.driver === 'human' ? [['Shift', 'nitro', 'X / RB']] : []),
      ['R', 'restart', 'View'], ...(this.driver === 'human' ? [['Enter', 'respawn', 'B']] : []), ...(this.pbModel ? [['G', 'ghost', 'Y']] : []), ['Esc', 'menu', 'Menu'],
    ], app.input.padActive);
    this.restart();
  }

  exit() {
    const { app } = this;
    app.world.scene.remove(this.model.root);
    this.model.dispose();
    if (this.ghostModel) { app.world.scene.remove(this.ghostModel.root); this.ghostModel.dispose(); }
    if (this.pbModel) { app.world.scene.remove(this.pbModel.root); this.pbModel.dispose(); }
    if (this.rays) { app.world.scene.remove(this.rays.group); this.rays.dispose(); }
    document.getElementById('watch-panel').classList.add('hidden');
    app.hud.show(false);
  }

  restart() {
    const { track } = this;
    this.car = createCar(track, track.startIdx, this.carDef.spec); // a full nitro tank
    this.race = new RaceState(track);
    this.record = getRecord(track.id, this.carDef.id); // your best with this car
    this.medalTarget = this.aimFor(); // fixed for the run: the HUD ticks it at the finish if won
    // a best run saved during the last race is raced from now on
    if (this.nextPB) { this.pb = this.nextPB; this.nextPB = null; }
    this.raceStep = 0; // physics steps since GO: the race clock the ghost replays on
    if (this.rec) { this.rec.reset(); this.rec.add(0, this.car, true); }
    // the player's style score (its points refill the nitro tank); the AI scores nothing
    this.score = this.driver === 'human' ? new ScoreState(track) : null;
    this.scoreEvents = [];
    this.bestScore = this.score ? getBestScore(track.id, this.carDef.id) : null;
    this.note = null;
    if (this.withGhost) {
      this.ghost = { car: createCar(track), race: new RaceState(track), ai: new AIDriver(this.net) };
      this.ghost.watch = newWatch(this.ghost.car, 0);
    }
    this.watch = newWatch(this.car, 0);
    this.aiNote = 0;
    this.phase = 'countdown';
    this.clock = COUNTDOWN;
    this.goTimer = 0;
    this.acc = 0;
    this.lastGateDelta = null;
    this.ghostText = '';
    this.app.hud.hidePanel();
    this.app.hud.resetScore();
    this.app.input.steer = 0;
    this.savePrev();
    this.camera.snap(this.car);
    this.updateGates(true);
  }

  /** Back to the last checkpoint. The player keeps the speed they had there; a stuck AI restarts standing. */
  respawn(standing = false) {
    const { car, race, track } = this;
    this.addScoreEvents(this.score?.respawn()); // (the player only: the AI scores nothing)
    this.rec?.beforeJump(this.raceStep, car);
    respawnCar(car, race, track, !standing);
    this.rec?.afterJump(this.raceStep, car);
    this.app.input.steer = 0;
    this.watch = newWatch(car, race.time);
    this.savePrev();
    this.camera.snap(car);
  }

  update(dt) {
    const { app } = this;
    const input = app.input;
    if (input.consume('Escape', 'PadStart')) return this.returnTo();
    if (input.consume('KeyR', 'PadBack')) this.restart();
    if (this.driver === 'human' && this.phase === 'race' && input.consume('Enter', 'Backspace', 'NumpadEnter', 'PadB')) this.respawn();
    if (this.pbModel && input.consume('KeyG', 'PadY')) this.toggleGhost();
    input.clearPressed();
    if (this.note && (this.note.t -= dt) <= 0) this.note = null;

    this.acc += Math.min(dt, 0.1);
    while (this.acc >= STEP) {
      this.acc -= STEP;
      this.savePrev();
      this.fixedStep(STEP);
    }
    this.render(dt, this.acc / STEP);
  }

  fixedStep(dt) {
    const { track, car, race } = this;
    if (this.phase === 'countdown') {
      this.clock -= dt;
      if (this.clock <= 0) {
        this.phase = 'race';
        this.goTimer = 0.8;
      }
      return;
    }
    if (this.goTimer > 0) this.goTimer -= dt;
    this.raceStep++;

    // --- the main car ---
    let ctrl;
    if (this.phase === 'finished') ctrl = rollOut(car, track);
    else if (this.driver === 'ai') ctrl = this.ai.drive(track, car, race);
    else ctrl = this.app.input.controls(dt, this.ctrl, car.speed);
    stepCar(car, track, ctrl, dt);
    if (this.phase === 'race') {
      const events = race.update(car, dt);
      if (this.score) this.addScoreEvents(this.score.update(car, race, dt)); // before onFinish, which shows the score
      this.rec?.add(this.raceStep, car, race.finished); // before onFinish, which saves the run
      if (events) events.forEach((ev) => this.onGate(ev));
      if (this.driver === 'ai' && isStuck(this.watch, car, race)) {
        this.respawn(true);
        this.aiNote = 2.5;
      }
    }
    if (this.aiNote > 0) this.aiNote -= dt;

    // --- the ghost ---
    const g = this.ghost;
    if (g) {
      const gc = g.race.finished ? rollOut(g.car, track) : g.ai.drive(track, g.car, g.race);
      stepCar(g.car, track, gc, dt);
      g.race.update(g.car, dt);
      if (!g.race.finished && isStuck(g.watch, g.car, g.race)) {
        respawnCar(g.car, g.race, track, false);
        g.watch = newWatch(g.car, g.race.time);
        Object.assign(this.prev.ghost, { x: g.car.x, y: g.car.y, z: g.car.z, yaw: g.car.yaw });
      }
    }
  }

  onGate(ev) {
    const { race, hud } = { race: this.race, hud: this.app.hud };
    const gate = race.gates[ev.gateIndex];
    const best = this.record?.splits?.[ev.gateIndex];
    const delta = best != null ? ev.time - best : null;
    let label;
    if (ev.kind === 'cp') label = `CP ${gate.cp + 1}`;
    else if (ev.kind === 'lap') label = `LAP ${gate.lap + 1}`;
    else label = 'FINISH';
    hud.split(label, ev.time, delta);

    if (this.ghost) {
      const gt = this.ghost.race.splits[ev.gateIndex];
      this.ghostText = gt != null ? `AI ghost ${formatDelta(ev.time - gt)}` : 'AI ghost behind you';
    }
    this.updateGates(ev.kind !== 'cp');
    if (ev.kind === 'finish') this.onFinish();
  }

  onFinish() {
    this.phase = 'finished';
    const { race, track, app } = this;
    const t = race.finishTime;
    let html = `<h2 class="tag">${this.driver === 'ai' ? 'AI finished' : 'Finish'}</h2><div class="big">${formatTime(t)}</div>`;
    if (this.driver === 'human') {
      const isRecord = submitRecord(track.id, this.carDef.id, t, race.splits);
      const prev = this.record?.time;
      html += this.medalLine(t, prev);
      if (isRecord) {
        html += `<div class="record">New personal best${prev != null ? ` ${delta(t - prev)}` : ''}</div>`;
        html += `<div class="ghost-note">${this.saveRun(t)}</div>`;
      } else html += `<div class="cmp">Best with the ${this.carDef.name}: ${formatTime(prev)} ${delta(t - prev)}</div>`;
      html += this.nextMedalLine(t, isRecord ? t : prev);
      if (this.ghost) {
        const gt = this.ghost.race.finishTime;
        html += gt != null
          ? `<div class="cmp">AI ghost: ${formatTime(gt)}, ${t <= gt ? 'you win!' : 'the AI wins'}</div>`
          : `<div class="cmp">AI ghost hasn't finished: you win!</div>`;
      }
      html += this.scoreLines();
      this.record = getRecord(track.id, this.carDef.id);
    } else {
      html += this.medalLine(t);
      if (this.record) html += `<div class="cmp">Your best with the ${this.carDef.name}: ${formatTime(this.record.time)} (AI ${formatDelta(t - this.record.time)})</div>`;
    }
    if (race.lapTimes.length > 1) html += `<div class="laps">${race.lapTimes.map((l, i) => `<span>Lap ${i + 1} <b>${formatTime(l)}</b></span>`).join('')}</div>`;
    const pad = app.input.padConnected; // name the gamepad buttons too
    html += `<div class="keys"><span><kbd>R</kbd>${pad ? '<kbd>View</kbd>' : ''} race again</span><span><kbd>Esc</kbd>${pad ? '<kbd>Menu</kbd>' : ''} back</span></div>`;
    app.hud.showPanel(html);
  }

  /** Queue score events for the HUD's popups (only the last few are kept between frames). */
  addScoreEvents(events) {
    if (!events) return;
    const q = this.scoreEvents;
    q.push(...events);
    if (q.length > POPS_KEPT) q.splice(0, q.length - POPS_KEPT);
  }

  /** Finish panel: the score, its breakdown, the nitro it refilled and the best score for this track and car (saved if beaten). */
  scoreLines() {
    const sc = this.score;
    if (!sc) return '';
    const car = this.carDef, prev = this.bestScore;
    const isBest = submitScore(this.track.id, car.id, sc.total);
    this.bestScore = getBestScore(this.track.id, car.id) ?? prev;
    const best = isBest
      ? `<span class="new">New best score</span>${prev ? `<span class="prev">was ${formatPoints(prev.score)}</span>` : ''}`
      : prev ? `<span class="prev">Best with the ${car.name}: ${formatPoints(prev.score)}</span>` : '';
    const rows = sc.breakdown().map((r) =>
      `<div class="row ${r.points < 0 ? 'neg' : ''}"><span>${r.label}${r.note ? `<small>${r.note}</small>` : ''}</span>` +
      `<b>${r.points > 0 ? '+' : ''}${formatPoints(r.points)}</b></div>`).join('');
    // the nitro the points earned during the race, and how much of it a full tank had no room for
    const tanks = (n) => `${n.toFixed(1)} ${n.toFixed(1) === '1.0' ? 'tank' : 'tanks'}`;
    const lost = sc.nitroEarned - sc.nitro;
    const nitro = sc.nitroEarned < 0.05 ? 'Nitro earned: none' :
      `Nitro earned: ${tanks(sc.nitroEarned)}${lost >= 0.05 ? ` (${lost.toFixed(1)} lost: the tank was full)` : ''}`;
    return `<div class="score"><div class="score-head"><span class="lbl">Score</span><b>${formatPoints(sc.total)}</b>${best}</div>` +
      `<div class="breakdown">${rows}</div><div class="nitro-note">${nitro}</div></div>`;
  }

  /** The HUD's medal target for this run: the next medal above your best time ({medal, time}; all: every medal won), or null. */
  aimFor() {
    if (!this.medals || this.driver !== 'human') return null;
    return nextMedal(this.medals, this.record?.time) ?? { medal: 'author', time: this.medals.author, all: true };
  }

  /** Finish panel: the medal time `t` earns, NEW when it beats the medal of the best time before (`prev`; never for the AI). */
  medalLine(t, prev) {
    const m = this.medals;
    if (!m) return '';
    const got = medalFor(m, t);
    if (!got) return `<div class="medal-line none">No medal: bronze is ${formatTime(m.bronze)} ${delta(t - m.bronze)}</div>`;
    const had = medalFor(m, prev);
    const isNew = this.driver === 'human' && (!had || MEDAL_ORDER.indexOf(got) < MEDAL_ORDER.indexOf(had));
    return `<div class="medal-line"><i class="medal ${got}"></i>${MEDAL_NAMES[got]} medal${isNew ? '<span class="new">New</span>' : ''}</div>`;
  }

  /** Finish panel: the next medal above the best time `best` and how far time `t` was from it (none before the first medal). */
  nextMedalLine(t, best) {
    const next = medalFor(this.medals, best) && nextMedal(this.medals, best);
    return next ? `<div class="medal-next">Next <i class="medal ${next.medal}"></i>${MEDAL_NAMES[next.medal]} ${formatTime(next.time)} ${delta(t - next.time)}</div>` : '';
  }

  /** The best-run ghost saved for this track and the player's car, ready to play, or null. */
  loadPB() {
    const car = this.carDef.id;
    const g = unpackGhost(loadGhost(this.track.id, car), this.track, this.race?.laps ?? (this.track.closed ? this.track.laps : 1), car);
    return g ? new GhostPlayer(g) : null;
  }

  /** Save the run that just set a personal best as the ghost of this track and car. Returns the line for the finish panel. */
  saveRun(time) {
    const { rec, track, race } = this, car = this.carDef.id;
    if (!rec || rec.full) return 'Run too long to keep as a ghost';
    const data = packGhost(rec, { track, laps: race.laps, time, car });
    if (!saveGhost(track.id, car, data)) return 'Ghost not saved: browser storage is full or off';
    const g = unpackGhost(data, track, race.laps, car);
    // the ghost that is still racing keeps going; the new one starts with the next race
    if (g) this.nextPB = new GhostPlayer(g);
    if (!this.pbShown) return `Ghost saved (ghosts are off: ${this.withGhost ? 'tick "Race my best-run ghost" on the menu' : `${this.app.input.padActive ? 'Y' : 'G'} shows it`})`;
    return this.withGhost ? 'Ghost saved: race it in Drive' : 'Ghost saved: race it with R';
  }

  toggleGhost() {
    const k = this.app.input.padActive ? 'Y' : 'G';
    // nothing to show yet: the remembered setting stays as it is (a best time can lack a ghost when
    // its run was too long to keep or storage was full)
    if (!this.pb && !this.nextPB) {
      this.note = { t: NOTE_TIME, text: this.record ? 'No ghost: beat your best to save one' : `No ${this.carDef.name} ghost yet: set a best time first` };
      return;
    }
    this.pbShown = !this.pbShown;
    setSetting('ghost', this.pbShown);
    this.note = { t: NOTE_TIME, text: this.pbShown ? `Ghost on (${k})` : `Ghost off (${k})` };
  }

  /** Colour checkpoint gates: passed this lap = green, next = cyan. */
  updateGates(force) {
    const n = this.track.cpSamples.length;
    const done = this.race.finished ? n : this.race.cpInLap;
    if (!force && done === this._gatesDone) return;
    this._gatesDone = done;
    for (let k = 0; k < n; k++) this.meshes.setCheckpointState(k, k < done ? 'passed' : k === done ? 'next' : 'idle');
  }

  savePrev() {
    for (const [key, c] of [['car', this.car], ['ghost', this.ghost?.car]]) {
      if (!c) continue;
      const p = (this.prev[key] ??= {});
      p.x = c.x; p.y = c.y; p.z = c.z; p.yaw = c.yaw;
    }
  }

  /** Interpolated copy of a car for smooth rendering. */
  lerpCar(key, car, a) {
    const p = this.prev[key];
    const v = (this.view[key] ??= {});
    Object.assign(v, car);
    if (!p) return v;
    v.x = p.x + (car.x - p.x) * a;
    v.y = p.y + (car.y - p.y) * a;
    v.z = p.z + (car.z - p.z) * a;
    let dy = car.yaw - p.yaw;
    dy = Math.atan2(Math.sin(dy), Math.cos(dy));
    v.yaw = p.yaw + dy * a;
    return v;
  }

  render(dt, alpha) {
    const { app, track, race } = this;
    const car = this.lerpCar('car', this.car, alpha);
    this.model.update(car, track, dt);
    this.camera.update(car, dt);
    const cam = app.world.camera.position;
    if (this.ghost) {
      const g = this.lerpCar('ghost', this.ghost.car, alpha);
      this.ghostModel.update(g, track, dt);
      fadeGhost(this.ghostModel, g, car, cam, true);
    }
    if (this.pbModel) {
      // the render shows the car between the last two steps: race time (raceStep - 1 + alpha) steps;
      // after its finish the ghost is gone
      const on = !!this.pb && this.pbShown && this.pb.pose(Math.max(0, this.raceStep - 1 + alpha));
      if (on) this.pbModel.update(this.pb.car, track, dt);
      fadeGhost(this.pbModel, this.pb?.car, car, cam, on);
    }
    app.world.focusShadows(car.x, car.y, car.z);

    if (this.ai) {
      this.rays.group.visible = this.phase !== 'countdown';
      this.rays.update(car, this.ai.rays, SENSOR_RANGE);
      this.netView.draw(this.net);
    }

    // HUD
    if (this.phase === 'countdown') app.hud.countdown(String(Math.ceil(this.clock)));
    else if (this.goTimer > 0) app.hud.countdown('GO!');
    else app.hud.countdown(null);
    this.updateGates(false);
    app.hud.update({
      time: race.finished ? race.finishTime : race.time,
      lap: race.lap,
      laps: race.laps,
      cp: race.finished ? race.cpPerLap - 1 : Math.min(race.cpInLap, race.cpPerLap - 1),
      cps: race.cpPerLap - 1,
      sprint: !track.closed,
      speed: this.car.speed,
      gear: this.car.gear,
      rpm: this.car.rpm,
      spec: this.car.spec, // the rev bar's scale
      nitro: this.driver === 'human' ? this.car.nitro : null, // the AI never uses nitro: no gauge
      boosting: this.car.boosting,
      score: this.score ? { total: this.score.total, mult: this.score.multiplier, live: this.score.live } : null, // none when watching the AI
      best: this.record?.time,
      medal: this.medalTarget,
      finished: race.finished,
      ghostText: this.aiNote > 0 ? 'AI was stuck: back to its last checkpoint' : this.note ? this.note.text : this.ghostText,
      pad: app.input.padActive, // key hints name the gamepad buttons
    }, dt);
    if (this.scoreEvents.length) {
      app.hud.scorePops(this.scoreEvents);
      this.scoreEvents.length = 0;
    }
    app.world.render();
  }
}

const smooth = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t); };

/**
 * Fade a see-through ghost car where it would wash out the view: on top of
 * the player's car (every race starts that way) or right in front of the
 * camera. Hidden when (nearly) faded out or `on` is false.
 */
function fadeGhost(model, g, car, cam, on) {
  const f = on ? Math.min(
    smooth(1, 4.5, Math.hypot(g.x - car.x, g.y - car.y, g.z - car.z)),
    smooth(2.5, 6.5, Math.hypot(g.x - cam.x, g.y - cam.y, g.z - cam.z)),
  ) : 0;
  model.root.visible = f > 0.02;
  if (f === model._fade) return;
  model._fade = f;
  for (const m of model.materials ?? []) {
    if (!m.transparent || m.colorWrite === false) continue; // the depth pre-pass stays as it is
    m.userData.opacity ??= m.opacity;
    m.opacity = m.userData.opacity * f;
  }
}

/** Progress watchdog for an AI car (`time`: the race time now). */
function newWatch(car, time) {
  return { best: car.prog, at: time };
}

/** True when the car has made no real progress for STUCK_TIME seconds of race time. */
function isStuck(w, car, race) {
  if (car.prog > w.best + 2) {
    w.best = car.prog;
    w.at = race.time;
    return false;
  }
  return race.time - w.at > STUCK_TIME;
}

/** Samples a respawned car is moved past its checkpoint (12 m), so the chase camera isn't under the gate. */
const RESPAWN_AHEAD = 6;

/**
 * Put a car back at its last checkpoint (or the start), with the speed it had
 * there or standing. It reappears RESPAWN_AHEAD samples past the gate with the
 * same offset and angle to the road it had when it crossed it.
 */
function respawnCar(car, race, track, keepSpeed) {
  const r = race.respawn;
  if (!r) { placeCar(car, track, track.startIdx); return; }
  const i = r.idx;
  let j = i + RESPAWN_AHEAD, laps = r.laps;
  if (track.closed && j >= track.N) { j -= track.N; laps++; }
  if (!track.closed) j = Math.min(j, track.finishIdx - 1, track.count - 2);
  const lat = (r.x - track.px[i]) * track.nx[i] + (r.z - track.pz[i]) * track.nz[i];
  let turn = Math.atan2(track.tx[j], track.tz[j]) - Math.atan2(track.tx[i], track.tz[i]);
  turn = Math.atan2(Math.sin(turn), Math.cos(turn));
  const c = Math.cos(turn), s = Math.sin(turn); // rotate the velocity with the road (+ = left)
  const vx = keepSpeed ? r.vx * c + r.vz * s : 0;
  const vz = keepSpeed ? -r.vx * s + r.vz * c : 0;
  placeCar(car, track, j, { x: track.px[j] + track.nx[j] * lat, z: track.pz[j] + track.nz[j] * lat, yaw: r.yaw + turn, vx, vz, idx: j, laps });
}

/**
 * After the finish: follow the road and brake to a stop (never into reverse),
 * then coast. Sprints brake hard: the road ends 250 m after the finish line.
 * The car keeps its own lane (at least 2.5 m inside the barrier) instead of
 * aiming at the centre line: a hard swerve to the centre at speed, braking,
 * sent a car that finished next to a barrier across into the opposite one.
 */
function rollOut(car, track) {
  const look = Math.max(3, Math.round((6 + car.speed * 0.3) / track.segLen));
  const i = track.closed ? (car.idx + look) % track.N : Math.min(track.count - 1, car.idx + look);
  const room = Math.max(0, track.hw[i] - 2.5);
  const lat = Math.max(-room, Math.min(room, car.lat));
  const gx = track.px[i] + track.nx[i] * lat - car.x, gz = track.pz[i] + track.nz[i] * lat - car.z;
  const fx = Math.sin(car.yaw), fz = Math.cos(car.yaw);
  const ang = Math.atan2(gx * fz - gz * fx, gx * fx + gz * fz);
  COAST.steer = car.forwardSpeed > 1 ? Math.max(-1, Math.min(1, 2.5 * ang)) : 0;
  COAST.throttle = car.speed > 2 && car.forwardSpeed > 0 ? (track.closed ? -0.5 : -1) : 0;
  return COAST;
}
