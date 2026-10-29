class_name ChaseCamera
extends Camera3D
## chase_camera.gd (port of web/src/game/camera.js)
## ------------------------------------------------------------------
## Chase camera and the overview / menu cameras.
##
## The chase camera sits behind the car along a *smoothed* heading:
##   - the heading follows a blend of the car's nose and its velocity with a
##     critically damped spring, and cannot swing faster than max_swing, so
##     hairpins and drifts do not whip the view around;
##   - height follows the car with its own spring (absorbs bumps and jumps);
##   - position is otherwise rigidly attached to the car, so there is no
##     lag-induced jitter at high speed;
##   - it stays above the road and no further out than just over the
##     barriers (uses `track` when given, else the one set with set_track);
##   - the field of view widens with speed;
##   - a wall hit shakes it briefly (scaled by the speed into the wall) and
##     scraping fast along a wall makes it rumble lightly. The shake is added
##     on top of the smoothed pose each frame and never fed back into it, and
##     is off with reduce_motion;
##   - nitro: while the car boosts (car.boost) the view widens a little more
##     and drops back a little, eased in and out (also off with reduce_motion).
##
## Usage: add it to the scene (it is top_level, so its transform is global),
## call snap(car) after a restart and update(car, dt) every drawn frame, with
## the drawn (interpolated) car: a car object or Dictionary with x, y, z, yaw,
## vx, vz, speed, forward_speed, boost / boosting, idx and the wall fields
## (see CarEffects.Pose for the names; camelCase works too).

# Shake: a hit adds its speed into the wall / SHAKE_HIT to the "trauma" (0..1),
# which fades by SHAKE_FADE per second; the shake is trauma² (soft for light
# knocks) times these largest offsets. A scrape faster than RUMBLE_MIN m/s adds
# a light rumble, full at RUMBLE_FULL m/s. Loose ground (v6.3) rumbles too: the
# surface's "rumble" (sim/surfaces.gd) × GROUND_RUMBLE, full from GROUND_FULL m/s.
const SHAKE_HIT := 22.0
const SHAKE_FADE := 1.5
const SHAKE_MOVE := 0.16   # m, sideways (the up/down offset is 3/4 of it)
const SHAKE_ROLL := 0.022  # rad (1.3°); pitch and yaw get half and a third of it
const RUMBLE_MIN := 8.0
const RUMBLE_FULL := 48.0
const RUMBLE := 0.22
const GROUND_RUMBLE := 0.3
const GROUND_FULL := 30.0
# Nitro kick: at full boost the field of view gains KICK_FOV degrees and the camera drops
# KICK_BACK m further back; it eases in at KICK_IN and out at KICK_OUT per second.
const KICK_FOV := 5.0
const KICK_BACK := 0.6
const KICK_IN := 5.0
const KICK_OUT := 1.6

static var _RUMBLE_COL: PackedFloat64Array = Surfaces.column("rumble")

## Off switch for the shake and the nitro kick (the browser's prefers-reduced-motion).
static var reduce_motion := false

var distance := 9.0
var height := 3.4
var max_swing := 2.8     # rad/s, fastest the view may rotate around the car
var heading_time := 0.26 # s, smoothing of the heading
var track: BuiltTrack = null

var heading := 0.0
var heading_vel := 0.0
var y := 0.0
var y_vel := 0.0
var dist := 9.0
var dist_vel := 0.0
var look := Vector3.ZERO
## wall shake (see the header): trauma 0..1, rumble 0..1, its clock, and the
## size of the shake applied this frame (0 = the camera is at its normal pose)
var wall := CarEffects.WallState.new()
var trauma := 0.0
var rumble := 0.0
## the rumble of the ground under the car (0..1, smoothed)
var ground_rumble := 0.0
var shake_time := 0.0
var shake := 0.0
var kick := 0.0  # nitro kick 0..1

var _loc := Collision.Loc.new()
var _pose := CarEffects.Pose.new()


func _init() -> void:
	top_level = true
	fov = 70.0
	near = 0.3
	far = 6000.0


## The track the camera keeps inside of (stays above the road, inside the barriers).
func set_track(t: BuiltTrack) -> void:
	track = t


## Jump straight to the ideal spot (after restart / respawn).
func snap(car: Variant, p_track: BuiltTrack = null) -> void:
	var c := _pose.read(car)
	heading = c.yaw
	heading_vel = 0.0
	y = c.y
	y_vel = 0.0
	dist = distance
	dist_vel = 0.0
	wall.ready = false
	trauma = 0.0
	rumble = 0.0
	ground_rumble = 0.0
	kick = 0.0
	_place(c, p_track if p_track != null else track)
	shake = 0.0


func update(car: Variant, dt: float, p_track: BuiltTrack = null) -> void:
	var c := _pose.read(car)
	dt = clampf(dt, 1e-4, 0.1)
	# Target heading: mostly the nose, partly the direction of travel.
	var target := c.yaw
	var speed := c.speed
	var fs: Variant = CarEffects.Pose._v(car, "forward_speed", "forwardSpeed")
	var fwd: float = float(fs) if fs != null else speed
	if speed > 6.0 and fwd > 0.0:
		var d := atan2(c.vx, c.vz) - c.yaw
		d = atan2(sin(d), cos(d))
		target = c.yaw + clampf(d * 0.35, -0.5, 0.5)
	var h := smooth_damp_angle(heading, target, heading_vel, heading_time, max_swing, dt)
	heading = h.x
	heading_vel = h.y

	var yy := smooth_damp(y, c.y, y_vel, 0.16, INF, dt)
	y = yy.x
	y_vel = yy.y
	# nitro kick (eased; none with reduced motion)
	var boost := 0.0
	if not reduce_motion:
		boost = clampf(c.boost if c.has_boost else (1.0 if c.boosting else 0.0), 0.0, 1.0)
	kick += (boost - kick) * (1.0 - exp(-dt * (KICK_IN if boost > kick else KICK_OUT)))
	if boost == 0.0 and kick < 1e-3:
		kick = 0.0
	# the camera drops back a little at speed (and with nitro)
	var dd := smooth_damp(dist, distance + minf(2.2, speed * 0.028) + KICK_BACK * kick, dist_vel, 0.5, INF, dt)
	dist = dd.x
	dist_vel = dd.y

	_place(c, p_track if p_track != null else track)
	_shake(c, dt, p_track if p_track != null else track)

	# Widen the field of view with speed: cheap but effective sense of speed.
	var f := 68.0 + 16.0 * minf(1.0, maxf(0.0, speed - 10.0) / 60.0) + KICK_FOV * kick
	if absf(fov - f) > 0.05:
		fov += (f - fov) * (1.0 - exp(-dt * 3.0))


## Wall shake on top of the pose _place() just set (which is rebuilt from scratch every frame).
func _shake(c: CarEffects.Pose, dt: float, tr: BuiltTrack = null) -> void:
	var w := wall
	if CarEffects.wall_events(w, c) > 0 and w.impact > 2.0:
		trauma = minf(1.0, trauma + w.impact / SHAKE_HIT)
	trauma = maxf(0.0, trauma - SHAKE_FADE * dt)
	var r := clampf((w.scrape - RUMBLE_MIN) / (RUMBLE_FULL - RUMBLE_MIN), 0.0, 1.0)
	rumble += (r - rumble) * (1.0 - exp(-dt * 6.0))
	var g := 0.0
	if tr != null and c.grounded and c.idx >= 0 and tr.has_surfaces():
		g = Surfaces.mix_at(tr, c.idx, _RUMBLE_COL) * minf(1.0, c.speed / GROUND_FULL)
	ground_rumble += (g - ground_rumble) * (1.0 - exp(-dt * 5.0))
	var amp := trauma * trauma + rumble * RUMBLE + ground_rumble * GROUND_RUMBLE
	if amp < 1e-3 or reduce_motion:
		shake = 0.0
		return
	shake = amp
	# smooth noise (two sines per axis, 10-22 Hz) instead of a random jolt per frame
	shake_time = fmod(shake_time + dt, 1000.0)
	var t := shake_time
	var b := transform.basis
	position += b.x * (amp * SHAKE_MOVE * wobble(t, 71.0, 113.0, 0.3))
	position += b.y * (amp * SHAKE_MOVE * 0.75 * wobble(t, 83.0, 127.0, 1.1))
	rotate_object_local(Vector3(0, 0, 1), amp * SHAKE_ROLL * wobble(t, 67.0, 97.0, 2.3))
	rotate_object_local(Vector3(1, 0, 0), amp * SHAKE_ROLL * 0.5 * wobble(t, 79.0, 131.0, 4.1))
	rotate_object_local(Vector3(0, 1, 0), amp * SHAKE_ROLL * 0.33 * wobble(t, 89.0, 109.0, 5.7))


func _place(c: CarEffects.Pose, t: BuiltTrack) -> void:
	var hx := sin(heading)
	var hz := cos(heading)
	var p := Vector3(c.x - hx * dist, y + height, c.z - hz * dist)
	if t != null and c.idx >= 0:
		var loc := Collision.locate(t, p.x, p.z, c.idx, _loc)
		var lim := loc.hw + 1.0
		if absf(loc.lat) > lim:
			var push := absf(loc.lat) - lim
			var s := signf(loc.lat)
			p.x -= loc.nx * s * push
			p.z -= loc.nz * s * push
		# road height under the camera (clamped to the road, i.e. barrier height beyond it)
		var lat := clampf(loc.lat, -loc.hw, loc.hw)
		var ground := loc.ground_y + (loc.lat - lat) * tan(loc.bank) + (1.1 if absf(loc.lat) > loc.hw else 0.0)
		p.y = maxf(p.y, ground + 1.6)
	look = Vector3(c.x + hx * 4.5, y + 1.3, c.z + hz * 4.5)
	transform = Transform3D(Basis.looking_at(look - p, Vector3.UP), p)


## Smooth -1..1 noise for the shake: two sines (rad/s a and b) with a phase.
static func wobble(t: float, a: float, b: float, ph: float) -> float:
	return 0.5 * (sin(t * a + ph) + sin(t * b + 1.7 * ph))


## Critically damped spring towards target (Unity-style SmoothDamp). Returns (value, velocity).
static func smooth_damp(current: float, target: float, vel: float, smooth_time: float, max_speed: float, dt: float) -> Vector2:
	var omega := 2.0 / smooth_time
	var x := omega * dt
	var e := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := current - target
	var max_change := max_speed * smooth_time
	change = clampf(change, -max_change, max_change)
	var t := current - change
	var temp := (vel + omega * change) * dt
	var v := (vel - omega * temp) * e
	var out := t + (change + temp) * e
	if (target - current > 0.0) == (out > target):
		out = target
		v = 0.0
	return Vector2(out, v)


static func smooth_damp_angle(current: float, target: float, vel: float, smooth_time: float, max_speed: float, dt: float) -> Vector2:
	var d := target - current
	d = atan2(sin(d), cos(d))
	return smooth_damp(current, current + d, vel, smooth_time, max_speed, dt)


## Looks down at the whole track from above (training overview).
static func overview_pose(cam: Camera3D, t: BuiltTrack) -> void:
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for i in t.count:
		min_x = minf(min_x, t.px[i])
		max_x = maxf(max_x, t.px[i])
		min_z = minf(min_z, t.pz[i])
		max_z = maxf(max_z, t.pz[i])
	var cx := (min_x + max_x) / 2.0
	var cz := (min_z + max_z) / 2.0
	var aspect := 16.0 / 9.0
	if cam.is_inside_tree():
		var vs := cam.get_viewport().get_visible_rect().size
		if vs.y > 0.0:
			aspect = vs.x / vs.y
	var size := maxf(max_x - min_x, (max_z - min_z) * aspect)
	var h := (size / 2.0 / tan(deg_to_rad(cam.fov) / 2.0)) * 1.05 + 30.0
	var p := Vector3(cx, h, cz + h * 0.25)
	var xf := Transform3D(Basis.looking_at(Vector3(cx, 0.0, cz) - p, Vector3.UP), p)
	if cam.is_inside_tree():
		cam.global_transform = xf
	else:
		cam.transform = xf
	if cam is ChaseCamera:
		(cam as ChaseCamera).shake = 0.0


## Slow orbit around the track (menu background, main.js orbit()): `angle` grows by dt * 0.08.
## Returns the orbit centre (for World.focus_shadows).
static func orbit_pose(cam: Camera3D, t: BuiltTrack, angle: float) -> Vector3:
	var cx := 0.0
	var cy := 0.0
	var cz := 0.0
	var r := 0.0
	var i := 0
	while i < t.count:
		cx += t.px[i]
		cy += t.py[i]
		cz += t.pz[i]
		i += 8
	var n := ceili(t.count / 8.0)
	cx /= n
	cy /= n
	cz /= n
	i = 0
	while i < t.count:
		r = maxf(r, Vector2(t.px[i] - cx, t.pz[i] - cz).length())
		i += 8
	var d := r * 1.25 + 60.0
	var p := Vector3(cx + cos(angle) * d, d * 0.55, cz + sin(angle) * d)
	var xf := Transform3D(Basis.looking_at(Vector3(cx, 0.0, cz) - p, Vector3.UP), p)
	if cam.is_inside_tree():
		cam.global_transform = xf
	else:
		cam.transform = xf
	cam.fov = 60.0
	return Vector3(cx, cy, cz)
