/**
 * race.js
 * ------------------------------------------------------------------
 * Race rules: checkpoints in order, laps, timing and splits.
 * Pure logic (no rendering), used by the player, the AI trainer and the
 * ghost car alike.
 *
 * The car's "unwrapped progress" (car.prog, in sample units, counting up
 * across laps) is compared against an ordered list of gates. Only the next
 * gate can be taken, so a lap only counts when every checkpoint was
 * passed in order.
 */
import { getGates } from '../tracks/trackBuilder.js';
import { snapshotCar } from '../physics/car.js';

export class RaceState {
  constructor(track, laps = track.laps) {
    this.track = track;
    this.laps = track.closed ? laps : 1;
    this.gates = getGates(track, this.laps);
    this.cpPerLap = track.cpSamples.length + 1; // checkpoints + the line
    this.reset();
  }

  reset() {
    this.nextGate = 0;
    this.time = 0;           // seconds since GO
    this.finished = false;
    this.finishTime = null;
    this.splits = [];        // time at each gate
    this.lapTimes = [];
    this.lapStart = 0;
    this.respawn = null;     // car snapshot at the last gate
  }

  get lap() {
    return Math.min(this.laps, this.gates[Math.min(this.nextGate, this.gates.length - 1)].lap + 1);
  }

  /** Checkpoints passed in the current lap (for the HUD). */
  get cpInLap() {
    if (this.finished) return this.cpPerLap;
    return this.gates[this.nextGate].cp;
  }

  get totalGates() {
    return this.gates.length;
  }

  /**
   * Advance the timer and test gates. Returns the gate events that happened
   * this step: {kind: 'cp'|'lap'|'finish', gateIndex, time, lapTime?}
   */
  update(car, dt) {
    if (this.finished) return null;
    this.time += dt;
    let events = null;
    while (this.nextGate < this.gates.length && car.prog >= this.gates[this.nextGate].prog) {
      const g = this.gates[this.nextGate];
      const ev = { kind: g.kind, gateIndex: this.nextGate, time: this.time };
      this.splits.push(this.time);
      this.respawn = snapshotCar(car);
      if (g.kind === 'lap' || g.kind === 'finish') {
        ev.lapTime = this.time - this.lapStart;
        this.lapTimes.push(ev.lapTime);
        this.lapStart = this.time;
      }
      if (g.kind === 'finish') {
        this.finished = true;
        this.finishTime = this.time;
      }
      this.nextGate++;
      (events ??= []).push(ev);
    }
    return events;
  }
}

/** Format seconds as m:ss.mmm */
export function formatTime(t) {
  if (t == null || !isFinite(t)) return '--:--.---';
  const neg = t < 0;
  const ms = Math.round(Math.abs(t) * 1000); // round once, so 119.9996 s shows as 2:00.000, not 1:60.000
  const m = Math.floor(ms / 60000);
  const s = (ms - m * 60000) / 1000;
  return `${neg ? '-' : ''}${m}:${s < 10 ? '0' : ''}${s.toFixed(3)}`;
}

/** Format a split difference: "+0.123" / "-0.456" */
export function formatDelta(d) {
  return `${d >= 0 ? '+' : '-'}${Math.abs(d).toFixed(3)}`;
}
