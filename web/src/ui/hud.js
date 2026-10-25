/**
 * hud.js
 * ------------------------------------------------------------------
 * The in-race heads-up display (plain DOM, see #hud in index.html):
 * timer, laps, checkpoints, speed, gear + rev bar (built here; v4: for the
 * driven car's spec), the nitro tank gauge (v4, built here), best time,
 * the next medal to aim for, ghost notes, countdown, split popups, the
 * finish panel and the key hints (keyboard or gamepad names).
 * v4: the style score (src/game/score.js) under the lap and checkpoint
 * counters: the total and the combo multiplier, a live counter for the
 * drift, jump or wall contact in progress, and short popups for what was
 * scored or lost (#hud-score, #hud-live, #hud-pops).
 * v5: the read-outs are a small label and a value (lap, checkpoint, best),
 * the key hints are key caps; the look is all in css/style.css.
 */
import { formatTime, formatDelta } from '../game/race.js';
import { CAR } from '../physics/car.js';
import { formatPoints } from '../game/score.js';
import { MEDAL_NAMES } from '../tracks/medals.js';

const POP_TIME = 2.2;  // s a score popup stays up (it fades out over the last POP_FADE s)
const POP_FADE = 0.4;
const POP_MAX = 4;     // popups shown at once; the oldest goes first
/** Live counter names (score.live.kind; a wall contact reads WALL). */
const LIVE_NAMES = { drift: 'DRIFT', air: 'AIR' };

const $ = (id) => document.getElementById(id);

/** A read-out with a small label (`<span class="lbl">Lap</span><b>2/3</b>`) in `el`; returns its two parts. */
function labelled(el) {
  const lbl = document.createElement('span');
  lbl.className = 'lbl';
  const val = document.createElement('b');
  el.replaceChildren(lbl, val);
  return { lbl, val, text: null };
}

/** Set a labelled read-out (only when it changed). */
function setLabelled(r, label, value) {
  const text = `${label}|${value}`;
  if (text === r.text) return;
  r.text = text;
  r.lbl.textContent = label;
  r.val.textContent = value;
}

/** Gear + rev counter under the speed read-out (styles: #hud-rev in css/style.css). */
function buildRevMeter(root) {
  const box = document.createElement('div');
  box.id = 'hud-rev';
  const gear = document.createElement('div');
  gear.id = 'hud-gear';
  const bar = document.createElement('div');
  bar.className = 'bar';
  const fill = document.createElement('div');
  fill.id = 'hud-rpm';
  // redline zone marker (placed for the car's spec by updateRev)
  const red = document.createElement('div');
  red.className = 'red';
  bar.append(red, fill);
  box.append(gear, bar);
  root.appendChild(box);
  return { box, gear, fill, red };
}

/**
 * Nitro tank gauge above the speed read-out (styles: #hud-nitro in
 * css/style.css): a ten-segment bar that glows while boosting and reads
 * EMPTY when the tank is out.
 */
function buildNitroGauge(root) {
  const box = document.createElement('div');
  box.id = 'hud-nitro';
  const label = document.createElement('span');
  label.className = 'lbl';
  label.textContent = 'NITRO';
  const tank = document.createElement('div');
  tank.className = 'tank';
  const fill = document.createElement('div');
  fill.className = 'fill';
  tank.append(fill);
  box.append(label, tank);
  root.appendChild(box);
  return { box, label, fill };
}

export class HUD {
  constructor() {
    this.root = $('hud');
    this.el = {
      time: $('hud-time'),
      lap: $('hud-lap'),
      cp: $('hud-cp'),
      speed: $('hud-speed'),
      best: $('hud-best'),
      medal: $('hud-medal'),
      ghost: $('hud-ghost'),
      countdown: $('hud-countdown'),
      split: $('hud-split'),
      splitTime: $('hud-split-time'),
      splitDelta: $('hud-split-delta'),
      panel: $('hud-panel'),
      mode: $('hud-mode'),
      keys: $('hud-keys'),
      score: $('hud-score'),
      points: $('hud-points'),
      combo: $('hud-combo'),
      live: $('hud-live'),
      pops: $('hud-pops'),
    };
    this.lap = labelled(this.el.lap);
    this.cp = labelled(this.el.cp);
    this.best = labelled(this.el.best);
    this.rev = buildRevMeter(this.root);
    this.nitro = buildNitroGauge(this.root);
    this.splitTimer = 0;
    this._gear = null;
    this._rpm = -1;
    this._spec = null;
    this._medal = null;
    this._nitro = null;
    this.pops = []; // [{el, t}] score popups, oldest first
    this._score = null;
    this._live = null;
    this._flash = 0;
  }

  show(on) {
    this.root.classList.toggle('hidden', !on);
    // clear anything left over from the previous race
    this.hidePanel();
    this.countdown(null);
    this.el.split.classList.remove('show');
    this.splitTimer = 0;
    this.resetScore();
  }

  setMode(text) {
    this.el.mode.textContent = text;
  }

  /**
   * Key hints at the bottom left: [[key, what it does, gamepad button?], ...].
   * They name the gamepad buttons while the pad is the last input used (update's s.pad).
   */
  setKeys(keys, pad = this._pad) {
    this._keys = keys;
    this._pad = !!pad;
    this.el.keys.replaceChildren(...keys.flatMap(([k, what, btn]) => {
      const cap = document.createElement('kbd');
      cap.textContent = this._pad && btn ? btn : k;
      const span = document.createElement('span');
      span.append(cap, ` ${what}`);
      return [span, ' '];
    }));
  }

  update(s, dt) {
    this.el.time.textContent = formatTime(s.time);
    setLabelled(this.lap, s.sprint ? 'Sprint' : 'Lap', s.sprint ? '' : `${s.lap}/${s.laps}`);
    setLabelled(this.cp, 'CP', `${s.cp}/${s.cps}`);
    const kmh = Math.round(s.speed * 3.6);
    if (kmh !== this._kmh) {
      this._kmh = kmh;
      this.el.speed.innerHTML = `${kmh}<small>km/h</small>`;
    }
    setLabelled(this.best, 'Best', s.best == null ? '—' : formatTime(s.best)); // (a dash until there is a best time)
    this.el.ghost.textContent = s.ghostText ?? '';
    this.updateMedal(s.medal, s.time, s.finished);
    this.updateRev(s.gear, s.rpm, s.spec);
    this.updateNitro(s.nitro, s.boosting);
    this.updateScore(s.score, dt);
    if (!!s.pad !== this._pad && this._keys) this.setKeys(this._keys, s.pad);
    if (this.splitTimer > 0) {
      this.splitTimer -= dt;
      if (this.splitTimer <= 0) this.el.split.classList.remove('show');
    }
  }

  /**
   * The medal to aim for under the best time: {medal, time, all?} (all: every
   * medal is already won, the author time is shown) or null for none. Struck
   * through once this run's `time` is past it, ticked when won.
   */
  updateMedal(target, time, finished) {
    const over = !!target && Math.round(time * 1000) > Math.round(target.time * 1000); // to the ms, as shown
    const cls = !target ? '' : target.all || (finished && !over) ? 'won' : over ? 'missed' : '';
    const state = target ? `${target.medal} ${target.time} ${cls}` : 'none';
    if (state === this._medal) return;
    this._medal = state;
    const el = this.el.medal;
    el.className = cls;
    if (!target) { el.replaceChildren(); return; }
    const disc = document.createElement('i');
    disc.className = `medal ${target.medal}`;
    const name = document.createElement('span');
    name.className = 'lbl';
    name.textContent = MEDAL_NAMES[target.medal];
    const t = document.createElement('b');
    t.textContent = formatTime(target.time);
    el.replaceChildren(name, disc, t);
  }

  /**
   * Gear letter (R / N / 1-6) and the rev bar (green, amber near the shift
   * point, red at the limiter) for the car's spec (car.spec; default CAR).
   */
  updateRev(gear, rpm, spec = CAR) {
    if (gear == null || rpm == null) {
      this.rev.box.style.visibility = 'hidden';
      return;
    }
    this.rev.box.style.visibility = ''; // (shown, unless the stylesheet hides it: the finish panel is open)
    const P = spec ?? CAR;
    if (P !== this._spec) {
      this._spec = P;
      this._rpm = -1;
      this.rev.red.style.left = `${((P.upshiftRpm / P.redline) * 100).toFixed(1)}%`;
    }
    const g = gear < 0 ? 'R' : gear === 0 ? 'N' : String(gear);
    if (g !== this._gear) {
      this._gear = g;
      this.rev.gear.textContent = g;
    }
    const r = Math.round(rpm / 25) * 25;
    if (r !== this._rpm) {
      this._rpm = r;
      const f = Math.max(0, Math.min(1, (r - P.idleRpm * 0.8) / (P.redline - P.idleRpm * 0.8)));
      this.rev.fill.style.width = `${(f * 100).toFixed(1)}%`;
      // white, the accent near the shift point, red at the limiter (the colours are css/style.css tokens)
      this.rev.fill.className = r >= P.redline - 150 ? 'limit' : r >= P.upshiftRpm - 600 ? 'shift' : '';
    }
  }

  /** Nitro tank 0..1 (null: no gauge, e.g. watching the AI); boosting makes it glow. */
  updateNitro(level, boosting) {
    const n = this.nitro;
    if (level == null) {
      if (this._nitro !== 'off') { this._nitro = 'off'; n.box.style.display = 'none'; }
      return;
    }
    const pct = Math.round(Math.max(0, Math.min(1, level)) * 200) / 2; // half-percent steps
    const empty = pct <= 0;
    const cls = empty ? 'empty' : boosting ? 'boost' : pct < 25 ? 'low' : '';
    const state = `${pct} ${cls}`;
    if (state === this._nitro) return;
    if (this._nitro === 'off' || this._nitro === null) n.box.style.display = '';
    this._nitro = state;
    n.box.className = cls;
    n.fill.style.width = `${pct}%`;
    n.label.textContent = empty ? 'EMPTY' : 'NITRO';
  }

  /**
   * The score block: s = {total, mult, live} (score.js: total, multiplier,
   * live) or null (no score: watching the AI). The total briefly turns gold
   * or red when it changes; the combo badge is gold from x2, dim at x1 and
   * red-rimmed at x1 after a wall contact or respawn broke a combo.
   */
  updateScore(s, dt) {
    const el = this.el;
    if (!s) {
      if (this._score !== 'off') {
        this._score = 'off';
        el.score.style.display = 'none';
        el.live.style.display = 'none';
        this.root.classList.remove('scoring');
        this.resetScore();
      }
      return;
    }
    if (this._score === 'off' || this._score === null) {
      el.score.style.display = '';
      el.live.style.display = '';
      this.root.classList.add('scoring'); // (phones held upright move the split popup out of the score column's way)
    }
    const state = `${s.total} ${s.mult}`;
    if (state !== this._score) {
      // (no previous race state: a new race starts without a flash)
      const [total, mult] = this._score && this._score !== 'off' ? this._score.split(' ').map(Number) : [s.total, s.mult];
      this._score = state;
      el.points.textContent = formatPoints(s.total);
      el.combo.textContent = `x${s.mult}`;
      el.combo.className = s.mult > 1 ? 'on' : mult > 1 ? 'reset' : '';
      if (s.total !== total) {
        el.score.className = s.total > total ? 'gain' : 'loss';
        this._flash = 0.45;
      }
    }
    if (this._flash > 0 && (this._flash -= dt) <= 0) el.score.className = '';
    // the drift / jump / wall contact in progress
    const l = s.live;
    // "DRIFT 1.2 s +640", "AIR 1.8 s +900", "WALL −350" (just "WALL" when there is nothing left to take); the points in their own <b>
    const [what, pts] = !l ? ['', ''] : l.kind === 'wall' ? ['WALL', l.points < 0 ? formatPoints(l.points) : '']
      : [`${LIVE_NAMES[l.kind] ?? ''} ${l.time.toFixed(1)} s`, `+${formatPoints(l.points)}`];
    const live = `${what}|${pts}`;
    if (live !== this._live) {
      this._live = live;
      if (!l) el.live.replaceChildren();
      else {
        const w = document.createElement('span');
        w.textContent = what;
        const b = document.createElement('b');
        b.textContent = pts;
        el.live.replaceChildren(w, ...(pts ? [' ', b] : []));
      }
      el.live.className = l ? `on ${l.kind}` : '';
    }
    // popups age and fade
    for (let i = this.pops.length - 1; i >= 0; i--) {
      const p = this.pops[i];
      p.t -= dt;
      if (p.t <= POP_FADE) p.el.classList.add('out');
      if (p.t <= 0) { p.el.remove(); this.pops.splice(i, 1); }
    }
  }

  /**
   * Popups for score events (score.js update / respawn): "Clean checkpoint
   * +1,500 x3", "Drift +820", "Wall −200 · combo lost", "Drift lost", ...
   */
  scorePops(events) {
    for (const ev of events) {
      const div = document.createElement('div');
      div.className = `pop ${ev.points > 0 ? 'good' : ev.points < 0 || ev.kind === 'wall' || ev.kind === 'respawn' ? 'bad' : 'lost'} ${ev.kind}`;
      const label = document.createElement('span');
      label.textContent = ev.text;
      div.append(label);
      if (ev.points !== 0) {
        const pts = document.createElement('b');
        pts.textContent = `${ev.points > 0 ? '+' : ''}${formatPoints(ev.points)}`;
        div.append(' ', pts);
      }
      if (ev.mult > 1) {
        const m = document.createElement('i');
        m.textContent = `x${ev.mult}`;
        div.append(' ', m);
      }
      if (ev.comboLost) div.append(' · combo lost');
      this.el.pops.append(div);
      this.pops.push({ el: div, t: POP_TIME });
      while (this.pops.length > POP_MAX) this.pops.shift().el.remove();
    }
  }

  /** Clear the popups and the live counter and forget the last total (a new race). */
  resetScore() {
    for (const p of this.pops) p.el.remove();
    this.pops.length = 0;
    this._live = null;
    this._flash = 0;
    if (this._score !== 'off') this._score = null;
    if (this.el.live) { this.el.live.textContent = ''; this.el.live.className = ''; }
    if (this.el.score) this.el.score.className = '';
    if (this.el.combo) this.el.combo.className = '';
  }

  countdown(text) {
    const c = this.el.countdown;
    if (!text) {
      c.classList.remove('show', 'pop');
      c.textContent = '';
      return;
    }
    if (c.textContent !== text) {
      c.textContent = text;
      c.classList.remove('pop');
      void c.offsetWidth; // restart the CSS animation
      c.classList.add('pop');
    }
    c.classList.add('show');
  }

  /** Split popup at a checkpoint: time and delta vs the best run (or null). */
  split(label, time, delta) {
    this.el.splitTime.textContent = `${label}  ${formatTime(time)}`;
    if (delta == null) {
      this.el.splitDelta.textContent = '';
      this.el.splitDelta.className = '';
    } else {
      this.el.splitDelta.textContent = formatDelta(delta);
      this.el.splitDelta.className = delta <= 0 ? 'faster' : 'slower';
    }
    this.el.split.classList.add('show');
    this.splitTimer = 2.2;
  }

  showPanel(html) {
    this.el.panel.innerHTML = html;
    this.el.panel.classList.add('show');
    this.root.classList.add('panel-open'); // (hides the speed, gear, nitro and key hints; narrow and short windows also the rows the panel would cover)
  }

  hidePanel() {
    this.el.panel.classList.remove('show');
    this.root.classList.remove('panel-open');
  }
}
