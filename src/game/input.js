/**
 * input.js
 * ------------------------------------------------------------------
 * Keyboard and gamepad state (the class keeps its v1 name, Keyboard).
 * Steering keys are smoothed so a digital key press feels like an
 * analogue stick instead of jerking the wheel.
 *
 * v2: the car physics already rate-limits the steering rack and scales the
 * full lock with speed (full steer ≈ the grip limit), so the keyboard only
 * shapes how a key press builds up: quick at parking speeds, gentler at
 * high speed (a short tap at 200 km/h is a small correction, holding the
 * key still reaches full steer in ~0.3 s), and a fast return to centre.
 *
 *   Arrows / WASD  drive          Space      handbrake (drift)
 *   R              restart run    Enter/Backspace  respawn at checkpoint
 *   G              ghost on / off Esc        back to menu
 *   Shift (either) nitro (v4)     C / Shift+C  next / previous car (menu)
 *   H or ?         Controls screen (menu, v5)
 *
 * v3: gamepads (Gamepad API, standard mapping, Xbox names). They are polled
 * once per frame, just before the frame's update, and hot-plugged
 * (gamepadconnected / gamepaddisconnected; a short notice shows).
 *
 *   left stick     steer (analogue)   RT / LT    accelerate / brake-reverse (analogue)
 *   A              handbrake          B          respawn at checkpoint
 *   Back (View)    restart run        Y          ghost on / off
 *   Start (Menu)   back to menu       d-pad ← →  steer like the arrow keys
 *   X or RB        nitro (v4)         LB / RB    previous / next car (menu)
 *   menus: d-pad / left stick move a highlight, A chooses, B goes back;
 *   View opens the Controls screen on the menu (v5)
 *
 * Pad buttons are codes next to the key codes ('PadA' … 'PadStart', d-pad
 * 'PadUp' …), so a screen asks for both: consume('KeyR', 'PadBack'). Menus
 * use 'NavUp' … (d-pad or stick, repeating while held). The stick and the
 * triggers go straight to the physics, which rate-limits the steering
 * itself; with keyboard and pad both in use each control takes the stronger.
 */
/** Steering build-up rates (steer units per second) and the return rate. */
export const STEER_KEYS = { rateSlow: 7, rateFast: 3.2, fastSpeed: 50, ret: 10 };

/**
 * Gamepad tuning. Steer = ((|x| - dead) / (full - dead)) ^ curve: no drift
 * from a worn stick, full lock a little before the rim, and finer control
 * near the centre (half travel ≈ 0.30 steer; full steer is already the grip
 * limit at speed). Triggers ignore their rest noise below trigDead.
 */
export const PAD = {
  dead: 0.12, full: 0.96, curve: 1.5,
  trigDead: 0.04,
  navOn: 0.55, navOff: 0.35,           // stick as a d-pad in menus (with hysteresis)
  repeatDelay: 0.4, repeatEvery: 0.13, // s, a held menu direction repeats
};

/** Standard-mapping button order (index → code). */
const PAD_BUTTONS = ['PadA', 'PadB', 'PadX', 'PadY', 'PadLB', 'PadRB', 'PadLT', 'PadRT', 'PadBack', 'PadStart',
  'PadL3', 'PadR3', 'PadUp', 'PadDown', 'PadLeft', 'PadRight', 'PadHome'];
const NAV = { up: 'NavUp', down: 'NavDown', left: 'NavLeft', right: 'NavRight' };
const DPAD = { up: 'PadUp', down: 'PadDown', left: 'PadLeft', right: 'PadRight' };
const NOTE_MS = 4500; // how long the connect notice stays

/** Stick axis → steer amount (same sign), with the dead zone and response curve. */
export function stickCurve(v) {
  const a = Math.abs(v);
  if (!(a > PAD.dead)) return 0;
  return Math.sign(v) * Math.min(1, (a - PAD.dead) / (PAD.full - PAD.dead)) ** PAD.curve;
}

/** Trigger value 0..1 without its rest noise. */
export function triggerValue(v) {
  return v > PAD.trigDead ? Math.min(1, (v - PAD.trigDead) / (1 - PAD.trigDead)) : 0;
}

export class Keyboard {
  constructor() {
    this.down = new Set();
    this.pressed = new Set(); // keys (and pad buttons) pressed since last consume
    this.steer = 0;           // the keyboard's smoothed steering
    // gamepads: analogue state, buttons held, menu directions held (code → next repeat time)
    this.pad = { steer: 0, throttle: 0, brake: 0 };
    this.padDown = new Set();
    this.navHeld = new Map();
    this.pads = new Map();    // connected pads: index → id
    this.padActive = false;   // the pad was used last (hints and menu highlights follow it)
    window.addEventListener('keydown', (e) => {
      this.padActive = false;
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLSelectElement) return;
      if (['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Space', 'Backspace', 'Slash'].includes(e.code)) e.preventDefault(); // (Slash: Firefox's quick find; ? opens Controls on the menu)
      if (!this.down.has(e.code)) {
        this.pressed.add(e.code);
        // a shifted press is also kept as 'Shift+<code>' (the menu's Shift+C), so a quick tap
        // that lets go of Shift before the next frame still counts
        if (e.shiftKey) this.pressed.add(`Shift+${e.code}`);
      }
      this.down.add(e.code);
    });
    window.addEventListener('keyup', (e) => this.down.delete(e.code));
    window.addEventListener('blur', () => this.down.clear());
    window.addEventListener('pointerdown', () => { this.padActive = false; });

    // The Gamepad API only exists in secure contexts (https, localhost).
    if (typeof navigator.getGamepads !== 'function' || window.isSecureContext === false) return;
    window.addEventListener('gamepadconnected', (e) => this.padSeen(e.gamepad));
    window.addEventListener('gamepaddisconnected', (e) => this.padGone(e.gamepad.index));
    // Requested before main.js starts its loop, so each frame polls first, then updates.
    const tick = () => { requestAnimationFrame(tick); this.poll(); };
    requestAnimationFrame(tick);
  }

  /** True while at least one gamepad is connected. */
  get padConnected() {
    return this.pads.size > 0;
  }

  /** True once per key press. */
  consume(...codes) {
    for (const c of codes) {
      if (this.pressed.has(c)) {
        this.pressed.delete(c);
        return true;
      }
    }
    return false;
  }

  clearPressed() {
    this.pressed.clear();
  }

  is(...codes) {
    return codes.some((c) => this.down.has(c) || this.padDown.has(c));
  }

  /** The menu direction pressed this frame ('up' | 'down' | 'left' | 'right'), or null. */
  navDir() {
    for (const dir in NAV) if (this.consume(NAV[dir])) return dir;
    return null;
  }

  /**
   * Car controls for this physics step.
   * @param speed  the car's current speed in m/s (shapes the steering build-up)
   */
  controls(dt, out, speed = 0) {
    const left = this.is('ArrowLeft', 'KeyA', 'PadLeft');
    const right = this.is('ArrowRight', 'KeyD', 'PadRight');
    const target = (left ? 1 : 0) - (right ? 1 : 0);
    const K = STEER_KEYS;
    let rate;
    if (target === 0 || target * this.steer < 0) rate = K.ret; // centring or reversing: quick
    else {
      const f = Math.min(1, Math.max(0, speed / K.fastSpeed));
      rate = K.rateSlow + (K.rateFast - K.rateSlow) * f;
    }
    const d = target - this.steer;
    this.steer += Math.sign(d) * Math.min(Math.abs(d), rate * dt);
    // keyboard and pad together: each control takes the stronger input
    const pad = this.pad;
    out.steer = Math.abs(pad.steer) > Math.abs(this.steer) ? pad.steer : this.steer;
    out.throttle = Math.max(this.is('ArrowUp', 'KeyW') ? 1 : 0, pad.throttle) - Math.max(this.is('ArrowDown', 'KeyS') ? 1 : 0, pad.brake);
    out.handbrake = this.is('Space', 'PadA');
    out.nitro = this.is('ShiftLeft', 'ShiftRight', 'PadX', 'PadRB'); // held: burns the tank (car.js)
    return out;
  }

  // ---- gamepads ---------------------------------------------------------------

  /**
   * Read every connected pad (call once per frame; done automatically). New
   * button presses go to `pressed` like key presses; several pads add up
   * (strongest stick and trigger, any button).
   */
  poll(now = performance.now()) {
    let list;
    try { list = navigator.getGamepads?.() ?? []; } catch (e) { list = []; }
    const t = now / 1000;
    const held = new Set();
    let steer = 0, throttle = 0, brake = 0, x = 0, y = 0;
    const seen = new Set();
    for (const gp of list) {
      if (!gp || gp.connected === false) continue;
      seen.add(gp.index);
      if (!this.pads.has(gp.index)) this.padSeen(gp);
      const b = gp.buttons ?? [], ax = gp.axes ?? [];
      for (let i = 0; i < PAD_BUTTONS.length && i < b.length; i++) if (b[i]?.pressed) held.add(PAD_BUTTONS[i]);
      const s = stickCurve(-(ax[0] ?? 0)); // stick right = +x; steer + = left
      if (Math.abs(s) > Math.abs(steer)) steer = s;
      throttle = Math.max(throttle, triggerValue(b[7]?.value ?? 0));
      brake = Math.max(brake, triggerValue(b[6]?.value ?? 0));
      if (Math.abs(ax[0] ?? 0) > Math.abs(x)) x = ax[0];
      if (Math.abs(ax[1] ?? 0) > Math.abs(y)) y = ax[1];
    }
    for (const i of [...this.pads.keys()]) if (!seen.has(i)) this.padGone(i);

    // menu directions: the d-pad, or the stick pushed past navOn (held until it is back under navOff)
    const stickDir = (dir) => {
      const v = dir === 'left' ? -x : dir === 'right' ? x : dir === 'up' ? -y : y;
      const along = dir === 'left' || dir === 'right' ? Math.abs(x) >= Math.abs(y) : Math.abs(y) > Math.abs(x);
      return v > (this.navHeld.has(NAV[dir]) ? PAD.navOff : PAD.navOn) && along;
    };
    for (const dir in NAV) if (held.has(DPAD[dir]) || stickDir(dir)) held.add(NAV[dir]);

    let used = false;
    for (const c of held) {
      if (this.padDown.has(c)) continue;
      this.pressed.add(c);
      used = true;
      if (c.startsWith('Nav')) this.navHeld.set(c, t + PAD.repeatDelay);
    }
    for (const [c, next] of this.navHeld) {
      if (!held.has(c)) this.navHeld.delete(c);
      else if (t >= next) { this.pressed.add(c); this.navHeld.set(c, Math.max(next + PAD.repeatEvery, t)); }
    }
    const p = this.pad;
    if ((steer && !p.steer) || (throttle && !p.throttle) || (brake && !p.brake)) used = true;
    p.steer = steer; p.throttle = throttle; p.brake = brake;
    this.padDown = held;
    if (used) this.padActive = true;
  }

  padSeen(gp) {
    if (!gp || this.pads.has(gp.index)) return;
    this.pads.set(gp.index, gp.id);
    const name = String(gp.id ?? '').replace(/\s*\(.*$/, '').slice(0, 40);
    notify(`Gamepad connected${name ? `: ${name}` : ''} · RT accelerate · LT brake · A handbrake · X nitro · View on the menu lists every button` +
      (gp.mapping === 'standard' ? '' : ' (unknown layout: some buttons may differ)'));
  }

  padGone(index) {
    if (!this.pads.delete(index)) return;
    if (!this.pads.size) {
      this.padDown = new Set();
      this.navHeld.clear();
      Object.assign(this.pad, { steer: 0, throttle: 0, brake: 0 });
      this.padActive = false;
    }
    notify(this.pads.size ? 'A gamepad was disconnected' : 'Gamepad disconnected');
  }
}

/** A short notice at the bottom of the screen (#pad-note). */
let noteTimer = 0;
function notify(text) {
  const el = document.getElementById('pad-note');
  if (!el) return;
  el.textContent = text;
  el.classList.add('show');
  clearTimeout(noteTimer);
  noteTimer = setTimeout(() => el.classList.remove('show'), NOTE_MS);
}

// ---- gamepad focus on screens of buttons ----------------------------------------

/** The elements a pad highlight may go to: shown, and not disabled (a label counts with its input). */
export function padTargets(els) {
  return [...els].filter((el) => el && !el.disabled && !el.querySelector?.('input:disabled') && el.getClientRects().length > 0);
}

/**
 * The element of `list` next to `from` in direction `dir`: the nearest one in
 * the same row (left / right) or column (up / down), else the closest one
 * that way at all. null if there is none.
 */
export function nearestTo(from, dir, list) {
  const r = from.getBoundingClientRect();
  const horiz = dir === 'left' || dir === 'right', sgn = dir === 'left' || dir === 'up' ? -1 : 1;
  const ax = r.left + r.width / 2, ay = r.top + r.height / 2;
  const cands = [];
  for (const el of list) {
    if (el === from) continue;
    const b = el.getBoundingClientRect();
    const dx = b.left + b.width / 2 - ax, dy = b.top + b.height / 2 - ay;
    const main = sgn * (horiz ? dx : dy);
    if (main < 2) continue;
    cands.push({
      el, main,
      side: Math.abs(horiz ? dy : dx),
      gap: horiz ? (sgn > 0 ? b.left - r.right : r.left - b.right) : (sgn > 0 ? b.top - r.bottom : r.top - b.bottom),
      inLine: horiz ? b.top < r.bottom && b.bottom > r.top : b.left < r.right && b.right > r.left,
    });
  }
  const line = cands.filter((c) => c.inLine);
  if (line.length) {
    const g = Math.min(...line.map((c) => c.gap));
    return line.filter((c) => c.gap <= g + 8).sort((p, q) => p.side - q.side)[0].el;
  }
  cands.sort((p, q) => p.main + 2 * p.side - (q.main + 2 * q.side));
  return cands[0]?.el ?? null;
}

/** Press a highlighted element: a select steps to its next option, anything else is clicked. */
export function padActivate(el) {
  if (el instanceof HTMLSelectElement) {
    if (!el.options.length) return;
    el.selectedIndex = (el.selectedIndex + 1) % el.options.length;
    el.dispatchEvent(new Event('change', { bubbles: true }));
  } else el.click();
}

/** Draws the highlight (class pad-focus) on one element at a time. */
export class PadMark {
  constructor() { this.el = null; }
  /** Highlight `el` (null: none); scrolls it into view when it changes. */
  set(el) {
    if (el === this.el) return;
    this.el?.classList.remove('pad-focus');
    this.el = el;
    if (el) {
      el.classList.add('pad-focus');
      el.scrollIntoView?.({ block: 'nearest' });
    }
  }
}

/**
 * Gamepad focus for a screen of buttons (the training dashboard): the d-pad /
 * stick move a highlight between `targets()`, A presses it. It is not DOM
 * focus, so Enter and Space on the keyboard keep their own meaning. The
 * highlight shows while the pad is the last thing used; the first direction
 * press only shows it.
 */
export class PadFocus {
  /** @param targets  () => the candidate elements, in order (filtered with padTargets) */
  constructor(targets) {
    this.targets = targets;
    this.el = null;
    this.mark = new PadMark();
  }

  update(input) {
    const dir = input.navDir(), a = input.consume('PadA');
    const shown = !!this.mark.el;
    const list = padTargets(this.targets());
    if (!list.includes(this.el)) this.el = null;
    if (dir || a) {
      // the first press only shows where the highlight is (at first: the screen's primary button)
      if (!this.el || !shown) this.el ??= list.find((el) => el.classList.contains('primary')) ?? list[0] ?? null;
      else if (dir) this.el = nearestTo(this.el, dir, list) ?? this.el;
      else padActivate(this.el);
    }
    this.mark.set(input.padActive && this.el?.isConnected ? this.el : null);
  }

  /** Remove the highlight (the screen is left). */
  clear() {
    this.mark.set(null);
  }
}
