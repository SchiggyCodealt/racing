/**
 * trainMode.js
 * ------------------------------------------------------------------
 * AI training screen: the 3D view of the whole population on the left,
 * the dashboard (settings, live network, fitness chart, stats) on the right.
 *
 * Speeds:
 *   1×    real time
 *   Fast  several physics steps per rendered frame
 *   Max   no 3D rendering: the session runs in a Web Worker
 *         (src/ai/trainWorker.js), so the page stays smooth; where no worker
 *         can run, the page simulates for most of each frame instead
 *
 * The training session survives switching to Watch / Race and back.
 * Gamepad: the d-pad / stick move a highlight over the dashboard's buttons,
 * ticks and selects, A presses it, B or Start goes back to the menu.
 */
import * as THREE from '../../vendor/three.module.min.js';
import { Trainer, parseNetworkFile, networkFile, DEFAULT_TRAINING, WALL_RULES, savedWallRule } from '../ai/trainer.js';
import { netFromParams } from '../ai/genetic.js';
import { AIFleet, SensorRays } from './carMesh.js';
import { ChaseCamera, overviewPose } from './camera.js';
import { SENSOR_RANGE } from '../ai/sensors.js';
import { NetworkView } from '../ui/networkView.js';
import { FitnessChart } from '../ui/fitnessChart.js';
import { formatTime } from './race.js';
import { downloadJSON, pickJSONFile, saveNetwork } from './storage.js';
import { PlayMode } from './playMode.js';
import { PadFocus } from './input.js';

const STEP = 1 / 60;
const FAST_STEPS = 6;
const RETURN_TIMEOUT = 5000; // ms the worker gets to hand a session back before it is given up
const $ = (id) => document.getElementById(id);

export class TrainMode {
  constructor(app) {
    this.app = app;
    this.speed = 1;
    this.paused = false;
    this.cam = 'chase';
    this.selected = -1;
    this.statsTimer = 0;
    this.netView = new NetworkView($('tr-net'));
    this.chart = new FitnessChart($('tr-chart'));
    // Max speed in a Web Worker (see "Max speed on a background thread" below)
    this.worker = null;
    this.workerBroken = false; // no worker here (or it failed): Max simulates on this page
    this.remote = null; // the session the worker is training, while it has it
    this.runSeq = 0;
    // gamepad highlight on the dashboard (the number fields need a keyboard; the file dialogs a mouse or keys);
    // it starts on Start training, or on the run's first button (the header's Menu button comes last)
    this.padFocus = new PadFocus(() => [...$('dashboard').querySelectorAll('button, select, label.check')]
      .filter((el) => el.id !== 'tr-load' && el.id !== 'tr-load2')
      .sort((p, q) => (p.id === 'tr-menu') - (q.id === 'tr-menu')));
    this.bindUI();
  }

  // ---- lifecycle ------------------------------------------------------------

  enter() {
    document.body.classList.add('training');
    $('dashboard').classList.remove('hidden');
    this.app.world.resize();
    this.chase = new ChaseCamera(this.app.world.camera);
    // further back and a bit higher than in a race, to see the cars around; low
    // enough to pass under the gate beams (start gate beam 6.2 m up, checkpoints 5.6 m):
    // at a run start the camera is 3 m behind the start gate, with the beam above the view
    this.chase.distance = 15;
    this.chase.height = 4.4;
    this.rays = new SensorRays();
    this.app.world.scene.add(this.rays.group);
    this.onPointer = (e) => this.pick(e);
    this.app.world.renderer.domElement.addEventListener('pointerdown', this.onPointer);

    if (this.trainer) {
      this.showRun();
      this.attachTrack(this.remote?.track ?? this.trainer.track);
    } else {
      this.showSetup();
    }
  }

  exit() {
    // training waits while Watch / Race / the menu is shown: take the session back from the worker
    if (this.remote && !this.remote.returning) this.requestReturn();
    document.body.classList.remove('training');
    $('dashboard').classList.add('hidden');
    $('max-overlay').classList.add('hidden');
    this.app.world.renderer.domElement.removeEventListener('pointerdown', this.onPointer);
    this.app.world.scene.remove(this.rays.group);
    this.rays.dispose();
    this.removeFleet();
    this.padFocus.clear();
    this.app.world.resize();
  }

  // ---- setup form --------------------------------------------------------------

  showSetup() {
    $('tr-setup').classList.remove('hidden');
    $('tr-run').classList.add('hidden');
    $('dashboard').scrollTop = 0;
    const list = $('tr-tracks');
    if (!list.children.length) {
      this.app.tracks.forEach((t, i) => {
        const label = document.createElement('label');
        label.className = 'check';
        label.innerHTML = `<input type="checkbox" value="${i}"> ${i + 1}. ${t.name}`;
        list.appendChild(label);
      });
    }
    // A track picked on the menu since the last visit replaces the ticks (the
    // player's own multi-track choice is kept while the menu pick is unchanged).
    if (this.listFor !== this.app.selectedTrack) {
      this.listFor = this.app.selectedTrack;
      for (const c of list.querySelectorAll('input')) c.checked = +c.value === this.app.selectedTrack;
    }
    const saved = this.app.network;
    $('tr-seed').disabled = !saved;
    $('tr-seed').checked = !!saved;
    this.showSeedInfo();
    this.previewTrack();
  }

  /** What "Continue from saved network" continues from, including the wall rule it was trained with. */
  showSeedInfo() {
    const saved = this.app.network;
    if (!saved) { $('tr-seed-info').textContent = '(none yet)'; return; }
    const rule = savedWallRule(saved.meta);
    const chosen = $('tr-walls').value;
    $('tr-seed-info').textContent =
      `(gen ${saved.meta.generation ?? '?'}, fitness ${Math.round(saved.meta.fitness ?? 0)}, ${saved.net.sizes.join('-')}` +
      `${rule ? `, walls: ${rule}` : ''})${rule && rule !== chosen ? ` – would continue with walls: ${chosen}` : ''}`;
  }

  previewTrack() {
    const checked = [...$('tr-tracks').querySelectorAll('input:checked')].map((c) => +c.value);
    const t = this.app.tracks[checked[0] ?? this.app.selectedTrack];
    this.app.showTrack(t);
    this.previewing = t;
  }

  readSettings() {
    const tracks = [...$('tr-tracks').querySelectorAll('input:checked')].map((c) => this.app.tracks[+c.value]);
    const hidden = $('tr-hidden').value.split(',').map((s) => parseInt(s.trim(), 10)).filter((n) => n > 0 && n <= 64);
    return {
      tracks: tracks.length ? tracks : [this.app.tracks[this.app.selectedTrack]],
      populationSize: clampInt($('tr-pop').value, 4, 400, DEFAULT_TRAINING.populationSize),
      mutationRate: Math.min(1, Math.max(0.005, parseFloat($('tr-mut').value) || DEFAULT_TRAINING.mutationRate)),
      hidden: hidden.length ? hidden : DEFAULT_TRAINING.hidden,
      laps: clampInt($('tr-laps').value, 1, 3, 1),
      walls: Object.hasOwn(WALL_RULES, $('tr-walls').value) ? $('tr-walls').value : DEFAULT_TRAINING.walls,
    };
  }

  start(seedOverride = null) {
    const cfg = this.readSettings();
    let seed = null, seedMeta = null;
    if (seedOverride) ({ net: seed, meta: seedMeta } = seedOverride);
    else if ($('tr-seed').checked && this.app.network) ({ net: seed, meta: seedMeta } = this.app.network);
    this.removeFleet();
    this.dropRemote();
    this.adopt(new Trainer({ ...cfg, seed, seedMeta }));
    // only a seed scored on the same tracks counts as already saved (see Trainer)
    this.lastSavedFitness = this.trainer.population.bestEver?.fitness ?? -Infinity;
    this.fleet = new AIFleet(cfg.populationSize);
    this.app.world.scene.add(this.fleet.group);
    this.selected = -1;
    this.paused = false;
    this.attachTrack(this.trainer.track);
    this.showRun();
    // the dashboard shows the new session at once (at Max the worker's first numbers take a moment)
    const a = this.shownAgent();
    this.netView.draw(a.net);
    this.renderStats(this.trainer.liveStats(), this.shownInfo(a));
    this.simRate = 0;
    $('max-rate').textContent = '';
    this.note(seed ? `Continuing from a saved network (${seed.sizes.join('-')}).${this.ruleChange(seedMeta)}` : `New population of ${cfg.populationSize} random drivers.`);
  }

  /** Make `tr` the session trained on this screen. */
  adopt(tr) {
    tr.onTrackChange = (t) => this.attachTrack(t);
    tr.onGeneration = () => this.onGeneration();
    this.trainer = tr;
  }

  /** A note for when a network trained with one wall rule continues with the other. */
  ruleChange(meta) {
    const was = savedWallRule(meta), now = this.trainer.cfg.walls;
    return was && was !== now ? ` It was trained with walls: ${was}; this run uses walls: ${now}, so its old best fitness doesn't carry over.` : '';
  }

  showRun() {
    $('tr-setup').classList.add('hidden');
    $('tr-run').classList.remove('hidden');
    // on small screens the dashboard scrolls: show the run controls from the top
    $('dashboard').scrollTop = 0;
    if (!this.fleet && this.trainer) {
      this.fleet = new AIFleet(this.trainer.population.size);
      this.app.world.scene.add(this.fleet.group);
    }
    this.syncButtons();
    this.chartDirty = true;
    this.drawChart();
  }

  stop() {
    this.dropRemote();
    this.trainer = null;
    this.pendingTrack = null;
    this.removeFleet();
    $('max-overlay').classList.add('hidden');
    this.showSetup();
  }

  removeFleet() {
    if (this.fleet) {
      this.app.world.scene.remove(this.fleet.group);
      this.fleet.dispose();
      this.fleet = null;
    }
  }

  attachTrack(track) {
    this.selected = -1;
    // Max speed draws nothing, so building the next track's 3D scene would only stall
    // the simulation (multi-track training switches track every run): it is built
    // when the view comes back (another speed, or pause). The same while another
    // screen is shown (a worker message can still arrive then).
    if ((this.speed === 'max' && !this.paused) || this.app.mode !== this) {
      this.pendingTrack = track;
      return;
    }
    this.pendingTrack = null;
    this.app.showTrack(track);
    const a = this.trainer.agents[this.trainer.leaderIndex()];
    if (a) this.chase.snap(a.car);
  }

  onGeneration() {
    const tr = this.trainer;
    this.selected = -1;
    this.chartDirty = true; // drawn once per frame (Max can end several generations in one)
    // Autosave the best network in the browser whenever it improves.
    if (tr.bestFitness > this.lastSavedFitness) {
      this.lastSavedFitness = tr.bestFitness;
      const data = tr.exportBest();
      saveNetwork(data);
      this.app.network = parseNetworkFile(data);
      this.note(`Gen ${tr.generation - 1}: new best (${Math.round(tr.bestFitness)}), autosaved in this browser.`);
    }
  }

  // ---- per frame -----------------------------------------------------------------

  update(dt) {
    const { app } = this;
    if (app.input.consume('Escape', 'PadB', 'PadStart')) return app.showMenu();
    this.padFocus.update(app.input);
    app.input.clearPressed();
    if (app.mode !== this) return; // the pad pressed Menu, Watch best or Race best

    if (!this.trainer) {
      // Setup screen: slowly orbit the preview track.
      app.orbit(dt);
      app.world.render();
      return;
    }

    this.syncWorker();
    if (this.remote) return this.updateRemote(dt);

    const tr = this.trainer;
    let steps = 0;
    let alpha = 1; // interpolation between the last two physics steps (1× only)
    const t0 = performance.now();
    if (!this.paused) {
      if (this.speed === 'max') {
        // no worker: simulate on this page for most of the frame
        while (performance.now() - t0 < 28) {
          for (let k = 0; k < 20; k++) tr.step(STEP);
          steps += 20;
        }
      } else if (this.speed === 1) {
        // Fixed 60 Hz steps; the trainer stores each car's pose before a step in
        // agent.prev, so the fleet can be drawn in between for smooth motion.
        this.acc = (this.acc ?? 0) + Math.min(dt, 0.1);
        while (this.acc >= STEP) { this.acc -= STEP; tr.step(STEP); steps++; }
        alpha = this.acc / STEP;
      } else {
        for (let k = 0; k < FAST_STEPS; k++) tr.step(STEP);
        steps = FAST_STEPS;
      }
    } else if (this.speed === 1) {
      alpha = (this.acc ?? 0) / STEP;
    }
    this.simRate = (this.simRate ?? 0) * 0.9 + (steps / Math.max(dt, 1e-3) / 60) * 0.1;

    const shown = this.shownAgent();
    $('max-overlay').classList.toggle('hidden', this.speed !== 'max' || this.paused);
    if (this.speed !== 'max' || this.paused) {
      if (this.pendingTrack) this.attachTrack(this.pendingTrack);
      this.fleet.update(tr.agents, tr.track, shown?.index ?? -1, performance.now() / 1000, alpha);
      if (shown) {
        const view = this.fleet.selectedView ?? shown.car; // interpolated copy of the shown car
        this.rays.group.visible = true;
        this.rays.update(view, shown.rays, SENSOR_RANGE);
        // view is one copy reused for whichever car is shown: when that changes (a new
        // leader, a click), the new car's earlier wall contacts are no news (no shake)
        if (shown.car !== this.chaseCar) { this.chaseCar = shown.car; this.chase.wall.ready = false; }
        if (this.cam === 'chase') this.chase.update(view, dt);
        app.world.focusShadows(view.x, view.y, view.z);
      }
      if (this.cam === 'overview') overviewPose(app.world.camera, tr.track);
      app.world.render();
    } else {
      $('max-rate').textContent = `${Math.round(this.simRate)}× real time`;
    }

    // Dashboard: network every frame (cheap), text a few times a second.
    if (shown) this.netView.draw(shown.net);
    this.drawChart();
    this.statsTimer -= dt;
    if (this.statsTimer <= 0) {
      this.statsTimer = 0.2;
      this.renderStats(tr.liveStats(), shown && this.shownInfo(shown));
    }
  }

  /** A frame while the worker trains: nothing to simulate or draw here but the dashboard. */
  updateRemote(dt) {
    const r = this.remote;
    $('max-overlay').classList.remove('hidden');
    if (r.netDirty) {
      r.netDirty = false;
      this.netView.draw(r.net);
    }
    this.drawChart();
    this.statsTimer -= dt;
    if (this.statsTimer <= 0) {
      this.statsTimer = 0.2;
      if (r.live) {
        $('max-rate').textContent = `${Math.round(this.simRate)}× real time`;
        this.renderStats(r.live.stats, r.live.shown);
      }
    }
  }

  /** The fitness chart, redrawn when a generation ended since the last frame. */
  drawChart() {
    if (!this.chartDirty) return;
    this.chartDirty = false;
    this.chart.draw(this.trainer.history);
  }

  shownAgent() {
    const tr = this.trainer;
    if (this.selected >= 0 && tr.agents[this.selected]) return tr.agents[this.selected];
    return tr.agents[tr.leaderIndex()];
  }

  /** What the dashboard says about the shown car (the worker sends the same). */
  shownInfo(a) {
    return { index: a.index, clicked: a.index === this.selected, alive: a.alive, deathReason: a.deathReason, fitness: a.fitness, speed: a.car.speed };
  }

  /** s: Trainer.liveStats() (here or from the worker), shown: shownInfo() or null. */
  renderStats(s, shown) {
    const tr = this.trainer;
    let deaths = Object.entries(s.deaths).map(([k, v]) => `${k} ${v}`).join(' · ');
    if (tr.cfg.walls === 'ride' && s.wallCars) deaths = `${deaths || 'all cars still driving'} · ${s.wallCars} used a wall`;
    const times = tr.tracks.map((t) => {
      const r = s.bestTimes[t.id];
      const lap = r?.lap != null ? formatTime(r.lap) : '—';
      const fin = r?.finish != null ? formatTime(r.finish) : '—';
      return `<tr><td>${t.name}</td><td>${t.closed ? lap : '—'}</td><td>${fin}</td></tr>`;
    }).join('');
    $('tr-stats').innerHTML = `
      <div class="grid">
        <div><span>Generation</span><b>${s.generation}</b></div>
        <div><span>Cars alive</span><b>${s.alive} / ${s.size}</b></div>
        <div><span>Best fitness ever</span><b>${s.bestFitness != null ? Math.round(s.bestFitness) : '—'}</b></div>
        <div><span>Leader this run</span><b>${Math.round(s.leaderFitness)}</b></div>
        <div><span>Track</span><b>${tr.tracks[s.trackPos].name}${tr.tracks.length > 1 ? ` (${s.trackPos + 1}/${tr.tracks.length})` : ''}</b></div>
        <div><span>Run time</span><b>${s.simTime.toFixed(1)} s</b></div>
      </div>
      <div class="viewing">This run: ${deaths || "all cars still driving"}</div>
      <table class="times"><tr><th>AI best</th><th>lap</th><th>finish</th></tr>${times}</table>`;
    if (shown) {
      const state = shown.alive ? 'driving' : shown.deathReason === 'finished' ? 'finished' : `out (${shown.deathReason})`;
      $('tr-viewing').innerHTML = `Viewing <b>car #${shown.index + 1}</b> ${shown.clicked ? '(clicked)' : '(leader)'} · ` +
        `${state} · fitness ${Math.round(shown.fitness)} · ${Math.round(shown.speed * 3.6)} km/h`;
    }
  }

  // ---- Max speed on a background thread ---------------------------------------------
  //
  // At Max (and not paused) the session is handed to a Web Worker with exportState(): the
  // worker trains it and sends live numbers and the shown network a few times a second.
  // this.trainer stays here as a copy that follows the worker generation by generation
  // (population, best network, chart history, best times: what autosave, Save, Watch and
  // Race use). Another speed, Pause or leaving the screen asks for the session back; it
  // returns exactly as the worker left it (mid-run), and only then is it stepped here again.
  // Every hand-over has its own run id, so messages from a dropped run are ignored.

  /** Start or end the worker's run so it matches the speed and pause buttons. */
  syncWorker() {
    const r = this.remote;
    const want = this.speed === 'max' && !this.paused;
    if (!r) {
      if (want) this.startRemote();
    } else if (!r.returning) {
      if (!want) this.requestReturn();
    } else if (performance.now() - r.returning > RETURN_TIMEOUT) {
      this.workerFailed(); // no answer: carry on here from the last generation it reported
    }
  }

  startRemote() {
    const worker = this.getWorker();
    if (!worker) return;
    const tr = this.trainer;
    const runId = ++this.runSeq;
    this.remote = { runId, returning: 0, followed: false, track: tr.track, live: null, net: null, netDirty: false, steps: 0, rateAt: performance.now() };
    try {
      const state = tr.exportState();
      worker.postMessage({ type: 'start', runId, state, defs: tr.tracks.map((t) => t.def), selected: this.selected }, [state.population.params.buffer]);
    } catch {
      this.workerFailed();
    }
  }

  requestReturn() {
    this.remote.returning = performance.now();
    this.worker.postMessage({ type: 'return', runId: this.remote.runId });
  }

  /** Forget the worker's session (Stop, or a new run): what it still sends is ignored. */
  dropRemote() {
    if (!this.remote) return;
    this.worker?.postMessage({ type: 'stop' });
    this.remote = null;
  }

  /** The worker, started on first use; null where none can run (Max then simulates on this page). */
  getWorker() {
    if (this.workerBroken) return null;
    if (!this.worker) {
      try {
        this.worker = new Worker(new URL('../ai/trainWorker.js', import.meta.url), { type: 'module' });
      } catch {
        this.workerBroken = true;
        this.note('Max speed simulates on this page (no background thread available here).');
        return null;
      }
      this.worker.onmessage = (e) => this.onWorkerMessage(e.data);
      this.worker.onerror = (e) => { e.preventDefault(); this.workerFailed(); };
      this.worker.onmessageerror = () => this.workerFailed();
    }
    return this.worker;
  }

  onWorkerMessage(msg) {
    this.workerSeen = true; // it started (for the note if it fails later)
    const r = this.remote;
    if (!r || msg.runId !== r.runId) return; // from a run that was stopped, replaced or handed back
    const tr = this.trainer;
    try {
      if (msg.type === 'live') {
        r.live = msg;
        tr.bestTimes = msg.stats.bestTimes; // for Save best network
        const track = tr.tracks[msg.stats.trackPos];
        if (track !== r.track) {
          // multi-track: the worker moved on; that track's 3D scene is built when the view is back
          r.track = track;
          this.selected = -1;
          this.pendingTrack = track;
        }
        if (msg.params) r.net = netFromParams(msg.sizes, msg.params);
        if (r.net && msg.acts) {
          let o = 0;
          for (const layer of r.net.acts) { layer.set(msg.acts.subarray(o, o + layer.length)); o += layer.length; }
          r.netDirty = true;
        }
        const now = performance.now();
        const rate = (msg.steps - r.steps) / 60 / Math.max(1e-3, (now - r.rateAt) / 1000);
        r.steps = msg.steps;
        r.rateAt = now;
        this.simRate = (this.simRate ?? 0) * 0.6 + rate * 0.4;
      } else if (msg.type === 'generation') {
        tr.followGeneration(msg);
        r.followed = true;
        this.onGeneration();
      } else if (msg.type === 'state') {
        const back = Trainer.fromState(msg.state, tr.tracks); // first: if this fails, workerFailed still knows the run
        this.remote = null;
        this.adopt(back);
        this.pendingTrack = back.track; // shown, and the camera put behind the leader, when the view is back
        this.acc = 0;
      } else if (msg.type === 'error') {
        this.workerError = msg.message; // kept for debugging (app.mode.workerError)
        this.workerFailed();
      }
    } catch (err) {
      this.workerError = String(err?.stack ?? err);
      this.workerFailed();
    }
  }

  /** The worker failed (or never started): from now on Max simulates on this page. */
  workerFailed() {
    this.workerBroken = true;
    if (this.worker) {
      this.worker.terminate();
      this.worker = null;
    }
    const r = this.remote;
    this.remote = null;
    if (!r) return;
    // The run here stopped where the worker took over. After a generation update it no
    // longer matches the population, so that generation starts again.
    if (r.followed) this.trainer.beginGeneration();
    this.pendingTrack = this.trainer.track; // not the worker's (multi-track: it may have moved on)
    this.note(`Max speed now simulates on this page (the background thread ${this.workerSeen ? 'stopped' : 'could not start'}).`);
  }

  // ---- interaction ----------------------------------------------------------------

  pick(e) {
    if (!this.fleet || !this.trainer || this.remote) return;
    const rect = e.target.getBoundingClientRect();
    const ndc = new THREE.Vector2(((e.clientX - rect.left) / rect.width) * 2 - 1, -((e.clientY - rect.top) / rect.height) * 2 + 1);
    const ray = new THREE.Raycaster();
    ray.setFromCamera(ndc, this.app.world.camera);
    const idx = this.fleet.pick(ray);
    if (idx >= 0) {
      this.selected = idx;
      this.note(`Viewing car #${idx + 1}. Click "Follow leader" to go back to the best car.`);
    }
  }

  note(text) {
    $('tr-note').textContent = text;
  }

  syncButtons() {
    $('tr-pause').textContent = this.paused ? 'Resume' : 'Pause';
    for (const b of $('tr-speed').querySelectorAll('button')) {
      b.classList.toggle('active', String(this.speed) === b.dataset.speed);
    }
    $('tr-cam').textContent = this.cam === 'chase' ? 'Overview camera' : 'Chase camera';
  }

  async loadFile() {
    try {
      const parsed = parseNetworkFile(await pickJSONFile());
      this.app.network = parsed;
      saveNetwork(parsed.meta.network ? parsed.meta : networkFile(parsed.net));
      this.start(parsed);
      this.note(`Loaded network (${parsed.net.sizes.join('-')}), training continues from it.${this.ruleChange(parsed.meta)}`);
    } catch (err) {
      this.note(`Could not load: ${err.message}`);
    }
  }

  playBest(ghost) {
    const tr = this.trainer;
    const net = tr.bestNet ?? tr.population.genomes[0].net;
    const app = this.app;
    app.setMode(new PlayMode(app, {
      track: this.remote?.track ?? tr.track,
      driver: ghost ? 'human' : 'ai',
      ghost,
      net: net.clone(),
      returnTo: () => app.setMode(this),
    }));
  }

  bindUI() {
    const walls = $('tr-walls');
    for (const [value, label] of Object.entries(WALL_RULES)) {
      const def = value === DEFAULT_TRAINING.walls;
      walls.add(new Option(label, value, def, def));
    }
    walls.addEventListener('change', () => this.showSeedInfo());
    $('tr-tracks').addEventListener('change', () => this.previewTrack());
    $('tr-start').onclick = () => this.start();
    $('tr-load').onclick = () => this.loadFile();
    $('tr-load2').onclick = () => this.loadFile();
    // the worker is asked for the session (or given it) on the click, not a frame later
    $('tr-pause').onclick = () => { this.paused = !this.paused; this.syncButtons(); if (this.trainer) this.syncWorker(); };
    for (const b of $('tr-speed').querySelectorAll('button')) {
      b.onclick = () => {
        this.speed = b.dataset.speed === 'max' ? 'max' : +b.dataset.speed;
        this.acc = 0;
        this.syncButtons();
        if (this.trainer) this.syncWorker();
      };
    }
    $('tr-follow').onclick = () => {
      this.selected = -1;
      if (this.remote) this.worker.postMessage({ type: 'select', runId: this.remote.runId, index: -1 });
      this.note('Following the leading car.');
    };
    $('tr-cam').onclick = () => {
      this.cam = this.cam === 'chase' ? 'overview' : 'chase';
      const a = this.trainer && !this.remote && this.shownAgent();
      if (this.cam === 'chase' && a) this.chase.snap(a.car);
      this.syncButtons();
    };
    $('tr-save').onclick = () => {
      if (!this.trainer) return;
      const data = this.trainer.exportBest();
      downloadJSON(data, `ai-driver-gen${data.generation}.json`);
      saveNetwork(data);
      this.app.network = parseNetworkFile(data);
      this.note('Best network downloaded (and kept in this browser).');
    };
    $('tr-watch').onclick = () => this.trainer && this.playBest(false);
    $('tr-race').onclick = () => this.trainer && this.playBest(true);
    $('tr-stop').onclick = () => this.stop();
    $('tr-menu').onclick = () => this.app.showMenu();
  }
}

function clampInt(v, lo, hi, fallback) {
  const n = parseInt(v, 10);
  return Number.isFinite(n) ? Math.min(hi, Math.max(lo, n)) : fallback;
}
