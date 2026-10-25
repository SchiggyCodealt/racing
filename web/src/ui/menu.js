/**
 * menu.js
 * ------------------------------------------------------------------
 * The main menu, in the order you use it: 1 pick a track, 2 pick a car,
 * 3 drive (v5 layout).
 *
 * - Track cards: the track's number, a small map of its centre line (an SVG
 *   drawn here from the built track, no image files), its name, difficulty
 *   and the medal and best time you hold with the picked car.
 * - One detail panel for the selected track: description, type and length,
 *   your best time, best score and ghost with the picked car, the AI's best
 *   from training and the four medal times (#menu-medals).
 * - The car picker: the four cars of src/physics/cars.js (side view drawn
 *   from the 3D model's shape, carProfile in carMesh.js, five stat bars and
 *   the picked car's one-line description). The pick is the 'car' setting
 *   (storage.js), which Drive and Race the AI ghost use (playMode.js).
 * - Mode buttons, the best-run ghost option and the AI network status
 *   (load / save).
 * - A Controls screen (#controls) listing every key and gamepad button; the
 *   menu itself keeps one short hint line (#menu-hint).
 *
 * Keyboard: arrows / 1-9, 0, -, = (tracks 1-12), C / Shift+C (next /
 * previous car), Enter drives, H or ? opens Controls (Esc closes it).
 * Gamepad: a highlight moved with the d-pad / stick over the track cards
 * (moving onto one selects it), the car cards under them (moving onto one
 * picks it) and the buttons; A drives or presses, B goes back to the
 * tracks, LB / RB pick the car, View opens Controls.
 */
import { formatTime } from '../game/race.js';
import { padTargets, nearestTo, padActivate, PadMark } from '../game/input.js';
import { getRecord, loadGhost, getSetting, setSetting, getBestScore } from '../game/storage.js';
import { formatPoints, SCORE } from '../game/score.js';
import { CARS, CAR_IDS, getCar } from '../physics/cars.js';
import { carProfile } from '../game/carMesh.js';
import { ghostFits } from '../game/replay.js';
import { savedWallRule } from '../ai/trainer.js';
import { medalTimes, medalFor, MEDAL_ORDER, MEDAL_NAMES } from '../tracks/medals.js';

const $ = (id) => document.getElementById(id);

/** Number-row keys that pick track 1-12 on the menu: 1-9, then 0, - and = (numpad: 0-9, -, +). */
const TRACK_KEYS = [
  ...[1, 2, 3, 4, 5, 6, 7, 8, 9].map((k) => ({ label: String(k), codes: [`Digit${k}`, `Numpad${k}`] })),
  { label: '0', codes: ['Digit0', 'Numpad0'] },
  { label: '-', codes: ['Minus', 'NumpadSubtract'] },
  { label: '=', codes: ['Equal', 'NumpadAdd'] },
];

/** The stat bars of a car card, in order: [key in def.bars, label]. */
const STATS = [['speed', 'Speed'], ['acceleration', 'Accel'], ['grip', 'Grip'], ['drift', 'Drift'], ['nitro', 'Nitro']];

/** The one hint line beside the title: [keys, what] for the keyboard, or the gamepad while it is the last input used. */
const HINTS = {
  keys: [['Arrows, 1–9 0 - =', 'track'], ['C', 'car'], ['Enter', 'drive']],
  pad: [['D-pad', 'move'], ['LB RB', 'car'], ['A', 'drive'], ['View', 'controls']],
};

/** Side view of a car (SVG markup), facing right; the same scale for every car so their sizes compare. */
function silhouette(def) {
  const { parts, wheels } = carProfile(def.id);
  const z0 = -2.75, z1 = 2.85, top = 1.62; // metres shown
  const fill = { paint: def.look.color, accent: def.look.accent, glass: '#2a3b52', carbon: '#121418', head: '#fff3d6' };
  const X = (z) => (z - z0).toFixed(3), Y = (y) => (top - y).toFixed(3);
  const body = parts.map((p) => `<path d="M${p.pts.map(([z, y]) => `${X(z)} ${Y(y)}`).join('L')}Z" fill="${fill[p.mat] ?? fill.carbon}"/>`).join('');
  const tyres = wheels.map(([z, r]) => `<circle cx="${X(z)}" cy="${Y(r)}" r="${r}" fill="#0c0d10"/><circle cx="${X(z)}" cy="${Y(r)}" r="0.23" fill="#a7adb8"/>`).join('');
  return `<svg class="sil" viewBox="0 0 ${(z1 - z0).toFixed(2)} ${top}" aria-hidden="true">${body}${tyres}</svg>`;
}

/**
 * Map of a track's centre line seen from above (SVG markup): about 160 points of the road, turned a
 * quarter when the track is taller than wide so it fills a wide card, with a dot on the start line
 * (and, for a sprint, one on the finish line). x / z go to SVG x / y and the quarter turn is a
 * rotation, never a mirror, so corners turn the way they do from the car. The line keeps its width
 * in pixels (non-scaling stroke) whatever the track's size; the dots are zero-length strokes.
 */
function trackMap(t) {
  const n = t.closed ? t.N : t.count;
  const step = Math.max(1, Math.round(n / 160));
  let x0 = Infinity, x1 = -Infinity, z0 = Infinity, z1 = -Infinity;
  for (let i = 0; i < n; i++) {
    x0 = Math.min(x0, t.px[i]); x1 = Math.max(x1, t.px[i]);
    z0 = Math.min(z0, t.pz[i]); z1 = Math.max(z1, t.pz[i]);
  }
  const turn = z1 - z0 > x1 - x0;
  const w = turn ? z1 - z0 : x1 - x0, h = turn ? x1 - x0 : z1 - z0;
  const pad = Math.max(w, h) * 0.04;
  const P = (i) => {
    const [u, v] = turn ? [z1 - t.pz[i], t.px[i] - x0] : [t.px[i] - x0, t.pz[i] - z0];
    return `${(u + pad).toFixed(1)} ${(v + pad).toFixed(1)}`;
  };
  const idx = [];
  for (let i = 0; i < n; i += step) idx.push(i);
  if (!t.closed && idx[idx.length - 1] !== n - 1) idx.push(n - 1);
  const dot = (cls, i) => `<path class="${cls}" d="M${P(i)}h0.01"/>`;
  return `<svg class="map" viewBox="0 0 ${(w + 2 * pad).toFixed(1)} ${(h + 2 * pad).toFixed(1)}" aria-hidden="true">` +
    `<path d="M${idx.map(P).join('L')}${t.closed ? 'Z' : ''}"/>${dot('start', t.closed ? 0 : t.startLine)}${t.closed ? '' : dot('fin', t.finishIdx)}</svg>`;
}

/** Difficulty 1-5 as five bars (the fonts have no star glyphs). */
function difficulty(n) {
  return `<span class="diff" title="Difficulty ${n} of 5">${[1, 2, 3, 4, 5].map((k) => `<i${k <= n ? ' class="on"' : ''}></i>`).join('')}</span>`;
}

const pad2 = (i) => String(i + 1).padStart(2, '0');

export class Menu {
  /**
   * @param app      shared app context
   * @param actions  {drive, ghost, watch, train, loadNet, saveNet}
   */
  constructor(app, actions) {
    this.app = app;
    this.actions = actions;
    $('btn-drive').onclick = actions.drive;
    $('btn-ghost').onclick = actions.ghost;
    $('btn-watch').onclick = actions.watch;
    $('btn-train').onclick = actions.train;
    $('btn-load-net').onclick = actions.loadNet;
    $('btn-save-net').onclick = actions.saveNet;
    $('btn-controls').onclick = () => this.showControls(true);
    $('btn-controls-close').onclick = () => this.showControls(false);
    $('controls').onclick = (e) => { if (e.target === $('controls')) this.showControls(false); }; // a click beside the panel
    $('opt-ghost').onchange = (e) => {
      setSetting('ghost', e.target.checked);
      e.target.blur(); // keep the arrow / Enter keys for the menu
    };
    window.addEventListener('resize', () => this.fitCheck());
    this.padMark = new PadMark();
    this.padAt = null; // the button or car the gamepad highlight is on (null: the selected track card)
    this.hint = null;
    this.maps = app.tracks.map(trackMap); // drawn once: the tracks don't change
    this.buildCars();
  }

  /** The car cards (built once; renderCars marks the picked one). */
  buildCars() {
    const box = $('car-picker');
    box.replaceChildren(...CAR_IDS.map((id) => {
      const def = CARS[id], st = def.stats;
      const card = document.createElement('button');
      card.className = 'car-card';
      card.dataset.car = id;
      card.setAttribute('role', 'radio');
      card.title = `${def.name}: ${def.description} (C changes the car)`;
      card.innerHTML = `${silhouette(def)}
        <span class="head"><span class="cname">${def.name}</span><span class="cspec">${Math.round(st.top)} km/h · ${(st.mass / 1000).toFixed(2)} t</span></span>
        <span class="bars">${STATS.map(([k, label]) =>
          `<span class="stat ${k}" title="${label}: ${Math.round(def.bars[k] * 10)} / 10"><i>${label}</i><b><span style="width:${(def.bars[k] * 100).toFixed(0)}%"></span></b></span>`).join('')}</span>`;
      card.onclick = () => { this.selectCar(id); card.blur(); };
      card.ondblclick = () => this.actions.drive();
      return card;
    }));
    this.renderCars();
  }

  /** Mark the picked car and show its description. */
  renderCars() {
    const def = getCar(getSetting('car'));
    for (const card of $('car-picker').children) {
      const on = card.dataset.car === def.id;
      card.classList.toggle('selected', on);
      card.setAttribute('aria-checked', String(on));
    }
    $('car-desc').innerHTML = `<b>${def.name}</b> ${def.description}`;
    $('car-desc').title = `${def.name}: ${def.description}`;
  }

  /** Pick car `id` (remembered: Drive and Race the AI ghost use it); the track cards and the detail panel follow it. */
  selectCar(id) {
    setSetting('car', getCar(id).id);
    this.render();
  }

  /** The next (step 1) or previous (step -1) car. */
  cycleCar(step) {
    const n = CAR_IDS.length, i = CAR_IDS.indexOf(getCar(getSetting('car')).id);
    this.selectCar(CAR_IDS[(i + step + n) % n]);
  }

  /** The picked car's card. */
  carCard() {
    const id = getCar(getSetting('car')).id;
    return [...$('car-picker').children].find((c) => c.dataset.car === id) ?? null;
  }

  show(on) {
    $('menu').classList.toggle('hidden', !on);
    if (on) this.render();
    else {
      this.padMark.set(null);
      this.showControls(false);
    }
  }

  /** Open or close the Controls screen. */
  showControls(on) {
    const el = $('controls');
    if (on === this.controlsOpen) return;
    el.classList.toggle('hidden', !on);
    if (on) this.padMark.set(null);
    if (document.activeElement instanceof HTMLElement) document.activeElement.blur(); // keep Enter / Space for the menu
  }

  get controlsOpen() {
    return !$('controls').classList.contains('hidden');
  }

  /**
   * Mark the menu when it is taller than the window, and keep a card chosen with the keys clear of the
   * action bar that sticks to the bottom of narrow windows (its height becomes the menu's scroll padding).
   */
  fitCheck() {
    const m = $('menu');
    if (m.classList.contains('hidden')) return;
    m.classList.toggle('scrolls', m.scrollHeight > m.clientHeight + 1);
    const bar = m.querySelector('.menu-actions');
    const sticky = !!bar && getComputedStyle(bar).position === 'sticky';
    m.style.scrollPaddingBottom = sticky ? `${bar.offsetHeight + 12}px` : '';
  }

  render() {
    const { app } = this;
    const car = getCar(getSetting('car')); // best times, ghosts and medals are the picked car's
    $('track-grid').replaceChildren(...app.tracks.map((t, i) => {
      const rec = getRecord(t.id, car.id);
      const medal = medalFor(medalTimes(t, car.id), rec?.time); // earned by the stored best time
      const card = document.createElement('button');
      card.className = 'track-card' + (i === app.selectedTrack ? ' selected' : '');
      card.setAttribute('role', 'radio');
      card.setAttribute('aria-checked', String(i === app.selectedTrack));
      card.title = `${t.name} (key ${TRACK_KEYS[i]?.label ?? i + 1})`;
      // the medal in the top corner, opposite the number; the best time under the name
      card.innerHTML = `<span class="num">${pad2(i)}</span>${medal ? `<i class="medal ${medal}" title="${MEDAL_NAMES[medal]} medal with the ${car.name}"></i>` : ''}` +
        `${this.maps[i]}<span class="name">${t.name}</span><span class="foot">${difficulty(t.def.difficulty)}` +
        `${rec ? `<span class="best" title="Your best with the ${car.name}">${formatTime(rec.time)}</span>` : ''}</span>`;
      card.onclick = () => this.select(i);
      card.ondblclick = () => this.actions.drive();
      return card;
    }));
    this.renderDetail(app.tracks[app.selectedTrack]);

    const net = app.network;
    // the AI status: two lines at most (the whole text is in the tooltip)
    $('ai-status').innerHTML = net
      ? `<b>Ready</b>: generation ${net.meta.generation ?? '?'}, fitness ${Math.round(net.meta.fitness ?? 0)}, network ${net.net.sizes.join('-')}` +
        (net.meta.trainedOn ? `, trained on ${net.meta.trainedOn.map((id) => app.tracks.find((t) => t.id === id)?.name ?? id).join(', ')}` : '') +
        (savedWallRule(net.meta) ? ` (walls: ${savedWallRule(net.meta)})` : '')
      : '<b>None yet</b>: train one or load a saved network file.';
    $('ai-status').title = $('ai-status').textContent;
    $('opt-ghost').checked = getSetting('ghost');
    this.renderCars();
    $('btn-ghost').disabled = !net;
    $('btn-watch').disabled = !net;
    $('btn-save-net').disabled = !net;
    this.fitCheck();
  }

  /** The detail panel: the selected track, and your records and its medal times with the picked car. */
  renderDetail(t) {
    const car = getCar(getSetting('car'));
    const box = $('track-detail');
    const rec = getRecord(t.id, car.id);
    const ghost = rec && ghostFits(loadGhost(t.id, car.id), t, t.closed ? t.laps : 1, car.id);
    const score = getBestScore(t.id, car.id);
    const ai = this.app.network?.meta?.bestTimes?.[t.id];
    const aiTime = ai && (t.closed ? ai.lap : ai.finish);
    const medal = medalFor(medalTimes(t, car.id), rec?.time);
    const km = (m) => (m / 1000).toFixed(2);
    box.querySelector('.td-num').textContent = pad2(this.app.tracks.indexOf(t));
    box.querySelector('.td-name').textContent = t.name;
    box.querySelector('.td-meta').innerHTML = `${difficulty(t.def.difficulty)}<span>${t.closed
      ? `Circuit · ${t.laps} laps · ${km(t.length)} km a lap` : `Sprint · ${km((t.finishIdx - t.startIdx) * t.segLen)} km`}</span>`;
    box.querySelector('.td-desc').textContent = t.def.description ?? '';
    box.querySelector('.td-map').innerHTML = this.maps[this.app.tracks.indexOf(t)]; // shown when the panel has room
    box.querySelector('.td-car').innerHTML = `With the <b>${car.name}</b>`;
    const cell = (label, value, title, has) => `<div title="${title}"><dt>${label}</dt><dd${has ? '' : ' class="none"'}>${has ? value : '—'}</dd></div>`;
    box.querySelector('.td-stats').innerHTML =
      cell(`Your best${medal ? `<i class="medal ${medal}"></i>` : ''}`, rec && formatTime(rec.time),
        `Your best time on ${t.name} with the ${car.name}${medal ? ` (${MEDAL_NAMES[medal]} medal)` : ''}`, !!rec) +
      cell('Best score', score && formatPoints(score.score), `Your best score on ${t.name} with the ${car.name}. Points for clean checkpoints ` +
        `(a combo up to x${SCORE.comboMax}), drifts, jumps and close calls; walls and respawns cost points. Points refill the nitro.`, !!score) +
      cell('Ghost', 'Saved', ghost ? `Your best run with the ${car.name} is saved as a ghost` : 'No ghost yet: set a best time', !!ghost) +
      cell(t.closed ? 'AI best lap' : 'AI best', aiTime && formatTime(aiTime),
        `The AI's best ${t.closed ? 'lap' : 'time'} here, from training (the AI always drives the Racer)`, !!aiTime);
    this.renderMedals(t);
  }

  /** The selected track's four medal times with the picked car; the medals its best time has won are lit. */
  renderMedals(t) {
    const car = getCar(getSetting('car'));
    const m = medalTimes(t, car.id);
    if (!m) { $('menu-medals').innerHTML = ''; return; }
    const got = medalFor(m, getRecord(t.id, car.id)?.time);
    const from = got ? MEDAL_ORDER.indexOf(got) : MEDAL_ORDER.length; // won: this medal and the ones below it
    $('menu-medals').innerHTML = `<div class="lbl">Medal times</div><div class="row">${MEDAL_ORDER.map((k, i) =>
      `<span class="${i >= from ? 'won' : ''}" title="${MEDAL_NAMES[k]} medal${i >= from ? ': won' : ''}">` +
      `<em><i class="medal ${k}${i >= from ? '' : ' off'}"></i>${MEDAL_NAMES[k]}</em><b>${formatTime(m[k])}</b></span>`).join('')}</div>`;
  }

  select(i) {
    this.app.selectedTrack = i;
    this.app.showTrack(this.app.tracks[i]);
    this.render();
    // keep the chosen card visible when the menu is taller than the window
    // (the menu's scroll padding keeps it clear of the sticky action bar)
    document.querySelector('#track-grid .track-card.selected')?.scrollIntoView?.({ block: 'nearest' });
  }

  /** Arrow keys / Enter on the menu (and the gamepad: handlePad). */
  handleKeys(input) {
    this.updateHint(input.padActive);
    if (this.controlsOpen) {
      // the Controls screen: Esc, H, ?, Backspace, Enter or Space close it (pad: B, A, View or Menu); nothing else
      if (input.consume('Escape', 'KeyH', 'Slash', 'Backspace', 'Enter', 'Space', 'PadB', 'PadA', 'PadBack', 'PadStart')) this.showControls(false);
      input.clearPressed();
      return;
    }
    if (input.consume('KeyH', 'Slash', 'PadBack')) {
      this.showControls(true);
      input.clearPressed();
      return;
    }
    const n = this.app.tracks.length;
    if (input.consume('ArrowRight', 'ArrowDown', 'KeyD', 'KeyS')) this.select((this.app.selectedTrack + 1) % n);
    if (input.consume('ArrowLeft', 'ArrowUp', 'KeyA', 'KeyW')) this.select((this.app.selectedTrack + n - 1) % n);
    TRACK_KEYS.forEach((key, k) => { if (k < n && input.consume(...key.codes)) this.select(k); });
    if (input.consume('KeyC')) this.cycleCar(input.consume('Shift+KeyC') ? -1 : 1);
    if (input.consume('Enter', 'Space')) this.actions.drive();
    else this.handlePad(input);
    input.clearPressed();
  }

  /** The hint line beside the title names the gamepad's buttons while the pad is the last input used. */
  updateHint(pad) {
    const h = pad ? 'pad' : 'keys';
    if (h === this.hint) return;
    this.hint = h;
    $('menu-hint').innerHTML = HINTS[h].map(([k, what]) => `<span><b>${k}</b> ${what}</span>`).join('');
  }

  /**
   * Gamepad on the menu. The highlight is on the selected track card (padAt null), a car card or a
   * button. On the track cards the d-pad moves like the arrow keys (left / right along the cards,
   * wrapping; up / down a row; moving onto a card selects it); down from the bottom row goes to the
   * cars, up from the top row to the Controls button. On the cars, moving onto one picks it; up from
   * the top row goes back to the tracks, right from the last car or down from the bottom row to Drive.
   * Between the buttons it moves to the nearest one (left / right only along a row); left from the
   * first button of a row goes back to the picked car or the tracks, whichever is beside. A drives (on
   * a track card) or presses the button; on a car it goes back to the tracks. B goes back to the
   * tracks, LB / RB pick the previous / next car from anywhere. The highlight shows while the pad is
   * the last input used; a press while it is hidden only shows it. "Load network…" is left out: its
   * file dialog needs a mouse or keyboard anyway.
   */
  handlePad(input) {
    const dir = input.navDir(), a = input.consume('PadA'), b = input.consume('PadB');
    const ctrls = padTargets([...['btn-controls', 'btn-drive', 'btn-ghost', 'btn-watch', 'btn-train'].map($), $('opt-ghost').closest('label'), $('btn-save-net')]);
    const cars = padTargets($('car-picker').children);
    const shown = !!this.padMark.el;
    let at = ctrls.includes(this.padAt) || cars.includes(this.padAt) ? this.padAt : null;
    const onCar = cars.includes(at);
    const step = (input.consume('PadRB') ? 1 : 0) - (input.consume('PadLB') ? 1 : 0);
    if (step) {
      this.cycleCar(step);
      if (onCar) at = this.carCard();
    }
    const drive = ctrls.includes($('btn-drive')) ? $('btn-drive') : null;
    if (dir && shown) {
      const cards = [...$('track-grid').children], card = cards[this.app.selectedTrack];
      if (onCar) {
        const next = nearestTo(at, dir, cars);
        if (next) { this.selectCar(next.dataset.car); at = next; }
        else if (dir === 'up') at = null;
        else if (dir === 'right' || dir === 'down') at = drive ?? at;
      } else if (at === $('btn-controls') && dir === 'down') {
        at = null; // under the Controls button: the track cards
      } else if (at) {
        const next = nearestTo(at, dir, ctrls);
        if (next && (dir === 'up' || dir === 'down' || sameRow(at, next))) at = next; // (left / right: only along a row)
        else if (dir === 'left') {
          const back = nearestTo(at, 'left', [this.carCard(), card].filter(Boolean));
          at = back && back !== card ? back : null;
        }
      } else if (dir === 'left' || dir === 'right') {
        const n = cards.length;
        this.select((this.app.selectedTrack + (dir === 'right' ? 1 : n - 1)) % n);
      } else {
        const next = nearestTo(card, dir, cards);
        if (next) this.select(cards.indexOf(next));
        else if (dir === 'down') at = this.carCard(); // below the last row: the cars
        else at = ctrls.includes($('btn-controls')) ? $('btn-controls') : null; // above the top row: Controls
      }
    } else if (a && shown) {
      if (onCar) at = null; // the car is picked: back to the tracks
      else if (at) { padActivate(at); return; } else { this.actions.drive(); return; }
    }
    if (b) at = null;
    this.padAt = at;
    this.padMark.set(input.padActive ? at ?? document.querySelector('#track-grid .track-card.selected') : null);
  }
}

/** True when two elements sit on the same row (their boxes overlap vertically). */
function sameRow(p, q) {
  const r = p.getBoundingClientRect(), s = q.getBoundingClientRect();
  return s.top < r.bottom && s.bottom > r.top;
}
