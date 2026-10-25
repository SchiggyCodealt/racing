/**
 * camera.js
 * ------------------------------------------------------------------
 * Chase camera and the overview camera for training.
 *
 * The chase camera sits behind the car along a *smoothed* heading:
 *   - the heading follows a blend of the car's nose and its velocity with a
 *     critically damped spring, and cannot swing faster than maxSwing, so
 *     hairpins and drifts do not whip the view around;
 *   - height follows the car with its own spring (absorbs bumps and jumps);
 *   - position is otherwise rigidly attached to the car, so there is no
 *     lag-induced jitter at high speed;
 *   - it stays above the road and no further out than just over the
 *     barriers (uses the track last shown, or the optional track argument);
 *   - the field of view widens with speed;
 *   - a wall hit shakes it briefly (scaled by the speed into the wall) and
 *     scraping fast along a wall makes it rumble lightly. The shake is added
 *     on top of the smoothed pose each frame and never fed back into it, and
 *     is off when the browser asks for reduced motion;
 *   - v4 nitro: while the car boosts (car.boost) the view widens a little
 *     more and drops back a little, eased in and out (also off with reduced
 *     motion).
 */
import * as THREE from '../../vendor/three.module.min.js';
import { locate } from '../physics/collision.js';
import { newWallState, wallEvents } from './carMesh.js';

// Shake: a hit adds its speed into the wall / SHAKE_HIT to the "trauma" (0..1),
// which fades by SHAKE_FADE per second; the shake is trauma² (soft for light
// knocks) times these largest offsets. A scrape faster than RUMBLE_MIN m/s adds
// a light rumble, full at RUMBLE_FULL m/s.
const SHAKE_HIT = 22, SHAKE_FADE = 1.5;
const SHAKE_MOVE = 0.16;  // m, sideways (the up/down offset is 3/4 of it)
const SHAKE_ROLL = 0.022; // rad (1.3°); pitch and yaw get half and a third of it
const RUMBLE_MIN = 8, RUMBLE_FULL = 48, RUMBLE = 0.22;
// Nitro kick: at full boost the field of view gains KICK_FOV degrees and the camera drops
// KICK_BACK m further back; it eases in at KICK_IN and out at KICK_OUT per second.
const KICK_FOV = 5, KICK_BACK = 0.6, KICK_IN = 5, KICK_OUT = 1.6;

let reduceMotion = null;
function motionReduced() {
  if (reduceMotion === null) {
    try { reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)'); } catch (e) { reduceMotion = false; }
  }
  return !!(reduceMotion && reduceMotion.matches);
}

export class ChaseCamera {
  constructor(camera) {
    this.camera = camera;
    this.distance = 9;
    this.height = 3.4;
    this.maxSwing = 2.8;   // rad/s, fastest the view may rotate around the car
    this.headingTime = 0.26; // s, smoothing of the heading
    this.pos = new THREE.Vector3();
    this.look = new THREE.Vector3();
    this.heading = 0;
    this.headingVel = 0;
    this.y = 0;
    this.yVel = 0;
    this.dist = this.distance;
    this.distVel = 0;
    this._loc = {};
    // wall shake (see the header): trauma 0..1, rumble 0..1, its clock, and the
    // size of the shake applied this frame (0 = the camera is at its normal pose)
    this.wall = newWallState();
    this.trauma = 0;
    this.rumble = 0;
    this.shakeTime = 0;
    this.shake = 0;
    this.kick = 0; // nitro kick 0..1
  }

  /** Jump straight to the ideal spot (after restart / respawn). */
  snap(car, track = this.camera.userData.track) {
    this.heading = car.yaw;
    this.headingVel = 0;
    this.y = car.y;
    this.yVel = 0;
    this.dist = this.distance;
    this.distVel = 0;
    this.wall.ready = false;
    this.trauma = 0;
    this.rumble = 0;
    this.kick = 0;
    this._place(car, track);
    this.shake = 0;
  }

  update(car, dt, track = this.camera.userData.track) {
    dt = Math.min(Math.max(dt, 1e-4), 0.1);
    // Target heading: mostly the nose, partly the direction of travel.
    let target = car.yaw;
    const speed = car.speed ?? Math.hypot(car.vx, car.vz);
    if (speed > 6 && (car.forwardSpeed ?? speed) > 0) {
      let d = Math.atan2(car.vx, car.vz) - car.yaw;
      d = Math.atan2(Math.sin(d), Math.cos(d));
      target = car.yaw + Math.max(-0.5, Math.min(0.5, d * 0.35));
    }
    const h = smoothDampAngle(this.heading, target, this.headingVel, this.headingTime, this.maxSwing, dt);
    this.heading = h.value;
    this.headingVel = h.vel;

    const y = smoothDamp(this.y, car.y, this.yVel, 0.16, Infinity, dt);
    this.y = y.value;
    this.yVel = y.vel;
    // nitro kick (eased; none with reduced motion)
    const boost = motionReduced() ? 0 : Math.max(0, Math.min(1, car.boost ?? (car.boosting ? 1 : 0)));
    this.kick += (boost - this.kick) * (1 - Math.exp(-dt * (boost > this.kick ? KICK_IN : KICK_OUT)));
    if (boost === 0 && this.kick < 1e-3) this.kick = 0;
    // the camera drops back a little at speed (and with nitro)
    const d = smoothDamp(this.dist, this.distance + Math.min(2.2, speed * 0.028) + KICK_BACK * this.kick, this.distVel, 0.5, Infinity, dt);
    this.dist = d.value;
    this.distVel = d.vel;

    this._place(car, track);
    this._shake(car, dt);

    // Widen the field of view with speed: cheap but effective sense of speed.
    const fov = 68 + 16 * Math.min(1, Math.max(0, speed - 10) / 60) + KICK_FOV * this.kick;
    if (Math.abs(this.camera.fov - fov) > 0.05) {
      this.camera.fov += (fov - this.camera.fov) * (1 - Math.exp(-dt * 3));
      this.camera.updateProjectionMatrix();
    }
  }

  /** Wall shake on top of the pose _place() just set (which is rebuilt from scratch every frame). */
  _shake(car, dt) {
    const w = this.wall;
    if (wallEvents(w, car) > 0 && w.impact > 2) this.trauma = Math.min(1, this.trauma + w.impact / SHAKE_HIT);
    this.trauma = Math.max(0, this.trauma - SHAKE_FADE * dt);
    const rumble = Math.min(1, Math.max(0, (w.scrape - RUMBLE_MIN) / (RUMBLE_FULL - RUMBLE_MIN)));
    this.rumble += (rumble - this.rumble) * (1 - Math.exp(-dt * 6));
    const amp = this.trauma * this.trauma + this.rumble * RUMBLE;
    if (amp < 1e-3 || motionReduced()) { this.shake = 0; return; }
    this.shake = amp;
    // smooth noise (two sines per axis, 10-22 Hz) instead of a random jolt per frame
    const t = (this.shakeTime = (this.shakeTime + dt) % 1000);
    const cam = this.camera;
    cam.translateX(amp * SHAKE_MOVE * wobble(t, 71, 113, 0.3));
    cam.translateY(amp * SHAKE_MOVE * 0.75 * wobble(t, 83, 127, 1.1));
    cam.rotateZ(amp * SHAKE_ROLL * wobble(t, 67, 97, 2.3));
    cam.rotateX(amp * SHAKE_ROLL * 0.5 * wobble(t, 79, 131, 4.1));
    cam.rotateY(amp * SHAKE_ROLL * 0.33 * wobble(t, 89, 109, 5.7));
  }

  _place(car, track) {
    const hx = Math.sin(this.heading), hz = Math.cos(this.heading);
    const p = this.pos.set(car.x - hx * this.dist, this.y + this.height, car.z - hz * this.dist);
    if (track && car.idx !== undefined) {
      const loc = locate(track, p.x, p.z, car.idx, this._loc);
      const lim = loc.hw + 1.0;
      if (Math.abs(loc.lat) > lim) {
        const push = Math.abs(loc.lat) - lim, s = Math.sign(loc.lat);
        p.x -= loc.nx * s * push;
        p.z -= loc.nz * s * push;
      }
      // road height under the camera (clamped to the road, i.e. barrier height beyond it)
      const lat = Math.max(-loc.hw, Math.min(loc.hw, loc.lat));
      const ground = loc.groundY + (loc.lat - lat) * Math.tan(loc.bank) + (Math.abs(loc.lat) > loc.hw ? 1.1 : 0);
      p.y = Math.max(p.y, ground + 1.6);
    }
    this.look.set(car.x + hx * 4.5, this.y + 1.3, car.z + hz * 4.5);
    this.camera.position.copy(p);
    this.camera.lookAt(this.look);
  }
}

/** Smooth -1..1 noise for the shake: two sines (rad/s a and b) with a phase. */
function wobble(t, a, b, ph) {
  return 0.5 * (Math.sin(t * a + ph) + Math.sin(t * b + 1.7 * ph));
}

/** Critically damped spring towards target (Unity-style SmoothDamp). */
function smoothDamp(current, target, vel, smoothTime, maxSpeed, dt) {
  const omega = 2 / smoothTime;
  const x = omega * dt;
  const exp = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x);
  let change = current - target;
  const maxChange = maxSpeed * smoothTime;
  change = Math.max(-maxChange, Math.min(maxChange, change));
  const t = current - change;
  const temp = (vel + omega * change) * dt;
  let v = (vel - omega * temp) * exp;
  let out = t + (change + temp) * exp;
  if ((target - current > 0) === (out > target)) {
    out = target;
    v = 0;
  }
  return { value: out, vel: v };
}

function smoothDampAngle(current, target, vel, smoothTime, maxSpeed, dt) {
  let d = target - current;
  d = Math.atan2(Math.sin(d), Math.cos(d));
  const r = smoothDamp(current, current + d, vel, smoothTime, maxSpeed, dt);
  return r;
}

/** Looks down at the whole track from above (training overview). */
export function overviewPose(camera, track) {
  let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
  for (let i = 0; i < track.count; i++) {
    minX = Math.min(minX, track.px[i]); maxX = Math.max(maxX, track.px[i]);
    minZ = Math.min(minZ, track.pz[i]); maxZ = Math.max(maxZ, track.pz[i]);
  }
  const cx = (minX + maxX) / 2, cz = (minZ + maxZ) / 2;
  const size = Math.max(maxX - minX, (maxZ - minZ) * camera.aspect);
  const h = (size / 2 / Math.tan((camera.fov * Math.PI) / 360)) * 1.05 + 30;
  camera.position.set(cx, h, cz + h * 0.25);
  camera.lookAt(cx, 0, cz);
}
