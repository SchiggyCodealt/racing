/**
 * trainWorker.js
 * ------------------------------------------------------------------
 * Max-speed training on a background thread, so the page stays smooth
 * while it simulates. src/game/trainMode.js starts this file as a module
 * Web Worker and hands it the whole training session when the speed goes
 * to Max (Trainer.exportState: settings, population, history and every car
 * of the run in progress). The worker simulates in short time slices, as
 * fast as the CPU allows, and hands the session back the same way when the
 * speed changes, training is paused or the training screen is left, so a
 * switch in either direction loses and repeats nothing.
 *
 * Messages. Each hand-over has a run id, and every message about it carries
 * that id: the page ignores messages from a run it has stopped or replaced.
 *   page -> worker
 *     {type: 'start', runId, state, defs, selected}
 *         take over: state from Trainer.exportState(), defs = the track
 *         definitions it names (built here), selected = clicked car or -1
 *     {type: 'select', runId, index}   show this car's network (-1 = leader)
 *     {type: 'return', runId}          stop and send the session back
 *     {type: 'stop'}                   stop and forget the session
 *   worker -> page
 *     {type: 'live', runId, steps, stats, shown, sizes, acts, params?}
 *         every LIVE_MS: Trainer.liveStats(), the shown car (clicked or
 *         leader), its network's activations and, when the shown network
 *         changed, its weights (flat Float32Arrays, see netParams)
 *     {type: 'generation', runId, ...Trainer.generationUpdate()}
 *         after every generation: chart entry, new population, best network
 *     {type: 'state', runId, state}    the answer to 'return'
 *     {type: 'error', runId, message}  something failed: the page trains itself again
 *
 * TrainerHost has no worker-specific code, so tools/selfTest.mjs drives it in Node.
 */
import { Trainer } from './trainer.js';
import { netParams } from './genetic.js';
import { buildTrack } from '../tracks/trackBuilder.js';

const STEP = 1 / 60;
const SLICE_MS = 25; // simulate this long, then let waiting messages in
const LIVE_MS = 125; // live dashboard updates: 8 per second

export class TrainerHost {
  /**
   * @param post      (message, transfer?) => void, to the page
   * @param schedule  (fn) => void: run fn after waiting messages; null = never
   *                  (the caller steps with advance(), as the self-test does)
   */
  constructor(post, schedule = null) {
    this.post = post;
    this.schedule = schedule;
    this.trainer = null;
    this.runId = 0;
    this.built = new Map(); // track definition JSON -> built track
    this.ticking = false;
  }

  handle(msg) {
    try {
      if (msg.type === 'start') this.start(msg);
      else if (msg.type === 'stop') this.trainer = null;
      else if (msg.runId !== this.runId) return; // about a run this worker has already let go
      else if (msg.type === 'select') this.selected = msg.index;
      else if (msg.type === 'return') this.handBack();
    } catch (err) {
      this.fail(err);
    }
  }

  start(msg) {
    this.runId = msg.runId;
    this.trainer = null;
    const tr = Trainer.fromState(msg.state, msg.defs.map((def) => this.build(def)));
    this.trainer = tr;
    this.selected = msg.selected ?? -1;
    this.steps = 0;
    this.lastLive = -Infinity;
    this.sentNet = null;
    tr.onTrackChange = () => { this.selected = -1; };
    tr.onGeneration = () => {
      this.selected = -1;
      const u = tr.generationUpdate();
      const buffers = [u.population.params.buffer];
      if (u.population.bestEver) buffers.push(u.population.bestEver.params.buffer);
      this.post({ type: 'generation', runId: this.runId, ...u }, buffers);
    };
    this.tick();
  }

  /** The built track for a definition (the same numbers as the page's: same code, same input). */
  build(def) {
    const key = JSON.stringify(def);
    if (!this.built.has(key)) this.built.set(key, buildTrack(def));
    return this.built.get(key);
  }

  /** Simulate `steps` physics steps, or until performance.now() reaches `until`. */
  advance(steps = Infinity, until = Infinity) {
    const tr = this.trainer;
    for (let n = 0; n < steps && performance.now() < until; n++) {
      tr.step(STEP);
      this.steps++;
    }
  }

  /** One time slice, then the next one after any waiting messages ('return' answers within a slice). */
  tick() {
    if (this.ticking || !this.schedule) return;
    this.ticking = true;
    this.schedule(() => {
      this.ticking = false;
      if (!this.trainer) return;
      try {
        this.advance(Infinity, performance.now() + SLICE_MS);
        if (performance.now() - this.lastLive >= LIVE_MS) this.sendLive();
      } catch (err) {
        return this.fail(err);
      }
      this.tick();
    });
  }

  sendLive() {
    const tr = this.trainer;
    this.lastLive = performance.now();
    const a = (this.selected >= 0 && tr.agents[this.selected]) || tr.agents[tr.leaderIndex()];
    const msg = { type: 'live', runId: this.runId, steps: this.steps, stats: tr.liveStats(), shown: null };
    const buffers = [];
    if (a) {
      msg.shown = { index: a.index, clicked: a.index === this.selected, alive: a.alive, deathReason: a.deathReason, fitness: a.fitness, speed: a.car.speed };
      msg.sizes = a.net.sizes;
      msg.acts = new Float32Array(a.net.acts.reduce((n, l) => n + l.length, 0));
      let o = 0;
      for (const l of a.net.acts) { msg.acts.set(l, o); o += l.length; }
      buffers.push(msg.acts.buffer);
      if (a.net !== this.sentNet) {
        this.sentNet = a.net;
        msg.params = netParams(a.net);
        buffers.push(msg.params.buffer);
      }
    }
    this.post(msg, buffers);
  }

  /** Answer 'return': the exact session, mid-run, then forget it. */
  handBack() {
    if (!this.trainer) return;
    const state = this.trainer.exportState();
    this.trainer = null;
    const buffers = [state.population.params.buffer];
    if (state.population.bestEver) buffers.push(state.population.bestEver.params.buffer);
    this.post({ type: 'state', runId: this.runId, state }, buffers);
  }

  fail(err) {
    this.trainer = null;
    this.post({ type: 'error', runId: this.runId, message: String(err?.stack ?? err) });
  }
}

// Started as a Web Worker (in Node, tools/selfTest.mjs only imports TrainerHost).
if (typeof WorkerGlobalScope !== 'undefined' && globalThis instanceof WorkerGlobalScope) {
  // Time slices are chained through a MessageChannel: it runs the next slice right after any
  // waiting page messages, without the ≥ 4 ms a chain of setTimeout(0) calls is held back by.
  const channel = new MessageChannel();
  let next = null;
  channel.port1.onmessage = () => { const fn = next; next = null; fn?.(); };
  const host = new TrainerHost(
    (msg, transfer) => postMessage(msg, transfer),
    (fn) => { next = fn; channel.port2.postMessage(null); },
  );
  globalThis.onmessage = (e) => host.handle(e.data);
}
