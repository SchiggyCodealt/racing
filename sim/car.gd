class_name Car
extends RefCounted
## car.gd: car physics v3 (PHYSICS_VERSION) with nitro (v4), a port of
## web/src/physics/car.js. Shared by the player, the AI cars and the ghost.
## ------------------------------------------------------------------
## No Nodes and no rendering: a car is a plain object so many AI cars can be
## simulated cheaply. Read the JS file header for the whole model; in short,
## per fixed 60 Hz step (split into spec.substeps sub-steps):
##
##  1. Driver inputs: the steering command is rate limited, then turned into a
##     speed-sensitive front wheel angle (+ a countersteer assist in slides).
##  2. Drivetrain: torque curve -> automatic 6-speed gearbox -> AWD with a
##     rear-biased split; brakes with a front bias; handbrake lever; ESC gating.
##  3. Two-axle "bicycle" model (u, v, yaw rate) with normal loads (weight
##     transfer, downforce, banking, crests), magic-formula tyres with a
##     friction circle, solved semi-implicitly; aero drag, rolling resistance,
##     gravity along the road; stability control (ESC).
##  4. Walls: capsule against the wall segments every sub-step (collision.gd):
##     push-out, almost no rebound, friction that grows with the hit, rubbing,
##     yaw stop and alignment; flying cars only stay inside the barrier line.
##  5. Vertical: glued to the road unless it really drops away (kicker ramps);
##     ballistic in the air; damped landings that cost a little speed.
##  6. Smoothed visual attitude (pitch / roll) through a damped spring.
##  6b. Road surfaces (v6.3, sim/surfaces.gd): on a track with dirt or snow each
##     axle reads the surface blend under it once a step: the car's grip share
##     scales that axle's grip, the surface's stiffness how fast its tyre force
##     builds with slip (and the steering lock that matches it), the rolling
##     resistance grows and the ESC can do less. Pure asphalt under both axles
##     skips all of it, so all-asphalt tracks run the v6.2 physics bit for bit.
##  7. Nitro: ctrl.nitro (0..1) burns the tank on the ground in a forward gear,
##     not braking, no handbrake; opens the throttle at least that far and adds
##     min(nitro_force, nitro_power / speed) of push, fading out below nitro_top.
##
## Use:
##   var car := Car.new(track)                      # at track.start_idx, the racer, full tank
##   var car := Car.new(track, idx, Cars.spec("kestrel"))
##   var ctrl := Car.Controls.new()                 # steer -1..1 (+ = left), throttle -1..1
##   car.step(track, ctrl, 1.0 / 60.0)              #   (- = brake/reverse), handbrake, nitro 0..1
##   car.place(track, idx, car.snapshot())           # respawn (keeps the nitro tank)
##   car.add_nitro(0.25)
##
## Fields: the JS car's fields in snake_case (x, y, z, vx, vy, vz, yaw, speed,
## forward_speed, side_speed, grounded, air_time, drifting, idx, lat, bank,
## ground_y, prog, laps, hit_wall, wall_hits, steer, throttle, yaw_rate,
## steer_angle, pitch, roll, rpm, gear, braking, slip, wheel_rot, wall_impact,
## wall_scrape, wall_x/y/z, wall_nx/nz, nitro, boost, boosting); `spec` is the
## CarSpec. Fields starting with "_" are internal. to_state() / from_state()
## give and take the whole state with the JS names (tests, parity tools).
##
## Thread safety: each car has its own scratch objects (the JS shares one per
## module), and a built track is only read, so different cars may be stepped
## on different threads. track_phys() data is filled when Tracks builds a track.
##
## Numbers: every expression keeps the JS order of operations, so a step gives
## the JS doubles bit for bit except where sin/cos/tan/atan/exp/asin round
## differently (glibc vs V8's fdlibm, 1 ulp on some arguments).

## Tags saved data that depends on the exact physics (ghosts, best times, medal times).
const PHYSICS_VERSION: int = 3
const G: float = 9.81
## m, contact skin around the capsule
const SKIN: float = 0.03
## m above the car's base where wall_y puts a contact (bumper height)
const WALL_Y: float = 0.45
const U_MIN: float = 1.5

## The JS names of the car state, in createCar's order (to_state / from_state).
const STATE_KEYS: PackedStringArray = [
	"x", "y", "z", "vx", "vy", "vz", "yaw", "speed", "forwardSpeed", "sideSpeed",
	"grounded", "airTime", "drifting", "idx", "lat", "bank", "groundY", "prog", "laps",
	"hitWall", "wallHits", "steer", "throttle",
	"yawRate", "steerAngle", "pitch", "roll", "rpm", "gear", "braking", "slip", "wheelRot",
	"wallImpact", "wallScrape", "wallX", "wallY", "wallZ", "wallNx", "wallNz",
	"nitro", "boost", "boosting",
	"_sc", "_ax", "_ay", "_fyr", "_shift", "_gear", "_pitchV", "_rollV",
	"_t", "_nx", "_nz", "_hw", "_ground", "_slipF", "_slipR", "_tcCut", "_hb", "_escOff", "_airRs", "_wallT",
	"_wallNow", "_rubT",
]


## Driver inputs for one step (the JS ctrl object).
class Controls:
	## -1..1, + = left
	var steer: float = 0.0
	## -1..1, - = brake / reverse
	var throttle: float = 0.0
	var handbrake: bool = false
	## 0..1 (the JS true = 1)
	var nitro: float = 0.0

	func _init(s: float = 0.0, t: float = 0.0, hb: bool = false, n: float = 0.0) -> void:
		steer = s
		throttle = t
		handbrake = hb
		nitro = n

	func set_to(s: float, t: float, hb: bool = false, n: float = 0.0) -> Controls:
		steer = s
		throttle = t
		handbrake = hb
		nitro = n
		return self


var spec: CarSpec

var x: float = 0.0
var y: float = 0.0
var z: float = 0.0
var vx: float = 0.0
var vy: float = 0.0
var vz: float = 0.0
var yaw: float = 0.0
var speed: float = 0.0
var forward_speed: float = 0.0
var side_speed: float = 0.0
var grounded: bool = true
var air_time: float = 0.0
var drifting: bool = false
var idx: int = 0
var lat: float = 0.0
var bank: float = 0.0
var ground_y: float = 0.0
## unwrapped progress (sample units) and wrap counter
var prog: float = 0.0
var laps: int = 0
var hit_wall: bool = false
var wall_hits: int = 0
var steer: float = 0.0
var throttle: float = 0.0
# v2
var yaw_rate: float = 0.0
var steer_angle: float = 0.0
var pitch: float = 0.0
var roll: float = 0.0
var rpm: float = 1000.0
var gear: int = 0
var braking: bool = false
var slip: float = 0.0
var wheel_rot: float = 0.0
# v3: wall contact
var wall_impact: float = 0.0
var wall_scrape: float = 0.0
var wall_x: float = 0.0
var wall_y: float = 0.0
var wall_z: float = 0.0
var wall_nx: float = 0.0
var wall_nz: float = 0.0
# v4: nitro
var nitro: float = 1.0
var boost: float = 0.0
var boosting: bool = false
# internal state
var _sc: float = 0.0
var _ax: float = 0.0
var _ay: float = 0.0
var _fyr: float = 0.0
var _shift: float = 0.0
var _gear: int = 1
var _pitch_v: float = 0.0
var _roll_v: float = 0.0
var _t: float = 0.0
var _nx: float = 1.0
var _nz: float = 0.0
var _hw: float = 7.0
var _ground: float = 0.0
var _slip_f: float = 0.0
var _slip_r: float = 0.0
var _tc_cut: float = 0.0
var _hb: float = 0.0
var _esc_off: float = 0.0
var _air_rs: float = 0.0
var _wall_t: int = 1000000
var _wall_now: bool = false
var _rub_t: float = 0.0

# per-step environment shared by the sub-steps (the JS module's `env`)
var _env_gx: float = 0.0
var _env_gz: float = 0.0
var _env_gn: float = G
var _env_drive: float = 0.0
var _env_brake: float = 0.0
var _env_hb: float = 0.0
var _env_esc: float = 1.0
# the road surface under the axles (v6.3, _surface_mix), once per step: off (false) on pure asphalt
var _env_loose: bool = false
var _env_gf: float = 1.0     # grip share, front / rear axle
var _env_gr: float = 1.0
var _env_kf: float = 1.0     # tyre stiffness, front / rear
var _env_kr: float = 1.0
var _env_rf: float = 1.0     # rolling resistance factor, front / rear
var _env_rr: float = 1.0
var _env_sesc: float = 1.0   # share of the ESC moment left
var _env_pk: float = 0.0     # front slip angle at the tyre's peak on this surface (the lock's allowance)
var _mx_g: float = 1.0       # _axle_mix results
var _mx_k: float = 1.0
var _mx_r: float = 1.0
var _mx_e: float = 1.0
var _mx_pure: bool = true
# scratch (the JS module's `scratch`, `contact`, `attTmp`), one per car
var _loc: Collision.Loc = Collision.Loc.new()
var _contact: Collision.Contact = Collision.Contact.new()
var _att_pitch: float = 0.0
var _att_roll: float = 0.0


## A car standing on sample `sample_idx` (default: the start) of `track`, with a full
## nitro tank. `car_spec`: the car (default: the racer; see Cars.spec(id)).
## Car.new() without a track gives an unplaced car (e.g. to hold a copied state).
func _init(track: BuiltTrack = null, sample_idx: int = -1, car_spec: CarSpec = null) -> void:
	spec = car_spec if car_spec != null else Cars.default_spec()
	rpm = spec.idle_rpm
	if track != null:
		place(track, track.start_idx if sample_idx == -1 else sample_idx)


## Add `amount` (a share of a full tank, may be negative) to the nitro tank, clamped to 0..1.
func add_nitro(amount: float) -> float:
	var n: float = nitro + (0.0 if is_nan(amount) else amount)
	nitro = 0.0 if n < 0.0 else (1.0 if n > 1.0 else n)
	return nitro


## Teleport onto a sample, facing along the track, or onto a snapshot() `state`
## (position, heading, velocity). Keeps the nitro tank.
func place(track: BuiltTrack, sample_idx: int, state: Dictionary = {}) -> void:
	var P: CarSpec = spec
	var has: bool = not state.is_empty()
	var i: int = maxi(0, mini(track.count - 1, sample_idx))
	x = float(state.x) if has else track.px[i]
	z = float(state.z) if has else track.pz[i]
	yaw = float(state.yaw) if has else atan2(track.tx[i], track.tz[i])
	vx = float(state.vx) if has else 0.0
	vz = float(state.vz) if has else 0.0
	vy = 0.0
	idx = int(state.idx) if has else mini(i, track.seg_count - 1)
	laps = int(state.laps) if has else 0
	var loc: Collision.Loc = Collision.locate(track, x, z, idx, _loc)
	idx = loc.idx
	y = loc.ground_y
	ground_y = loc.ground_y
	prog = laps * track.N + loc.prog
	lat = loc.lat
	bank = loc.bank
	_t = loc.t
	_nx = loc.nx
	_nz = loc.nz
	_hw = loc.hw
	grounded = true
	air_time = 0.0
	drifting = false
	hit_wall = false
	steer = 0.0
	throttle = 0.0
	yaw_rate = 0.0
	steer_angle = 0.0
	braking = false
	slip = 0.0
	wall_impact = 0.0
	wall_scrape = 0.0
	wall_x = 0.0
	wall_y = 0.0
	wall_z = 0.0
	wall_nx = 0.0
	wall_nz = 0.0
	_sc = 0.0
	_ax = 0.0
	_ay = 0.0
	_fyr = 0.0
	_shift = 0.0
	_ground = 1.0
	_slip_f = 0.0
	_slip_r = 0.0
	_tc_cut = 0.0
	_hb = 0.0
	_esc_off = 0.0
	_air_rs = 0.0
	_wall_t = 1000000
	_wall_now = false
	_rub_t = 0.0
	boost = 0.0
	boosting = false
	var fx: float = sin(yaw)
	var fz: float = cos(yaw)
	speed = JsMath.hypot2(vx, vz)
	forward_speed = vx * fx + vz * fz
	side_speed = vx * fz - vz * fx
	# pick the gear that suits the speed
	_gear = 1
	var gears: PackedFloat64Array = P.gears
	var wheel_rpm: float = (absf(forward_speed) / P.wheel_radius) * (30.0 / PI)
	while _gear < gears.size() and wheel_rpm * gears[_gear - 1] * P.final_drive > P.upshift_rpm - 600.0:
		_gear += 1
	gear = 0 if speed < 0.3 else _gear
	rpm = maxf(P.idle_rpm, wheel_rpm * gears[_gear - 1] * P.final_drive)
	# body attitude straight from the road, no spring transient
	track_phys(track)
	_road_attitude(track, loc)
	pitch = _att_pitch
	roll = _att_roll
	_pitch_v = 0.0
	_roll_v = 0.0


## Snapshot of the state needed to respawn the car here later (place()'s `state`).
func snapshot() -> Dictionary:
	return {x = x, z = z, yaw = yaw, vx = vx, vz = vz, idx = idx, laps = laps}


## Advance one fixed physics step.
func step(track: BuiltTrack, ctrl: Controls, dt: float) -> void:
	var P: CarSpec = spec
	var steer_in: float = _clamp(0.0 if is_nan(ctrl.steer) else ctrl.steer, -1.0, 1.0)
	var thr: float = _clamp(0.0 if is_nan(ctrl.throttle) else ctrl.throttle, -1.0, 1.0)
	var hb: bool = ctrl.handbrake
	# nitro: on the ground, in a forward gear, not braking, no handbrake, with something in the
	# tank; holding it opens the throttle at least as far (nitro alone drives the car)
	var boost_now: float = 0.0
	var n_in: float = ctrl.nitro
	if n_in != 0.0 and not is_nan(n_in) and not hb and nitro > 0.0 and grounded and _gear >= 1 and thr > -0.02:
		boost_now = _clamp(n_in, 0.0, 1.0)
		if thr < boost_now:
			thr = boost_now
	steer = steer_in
	throttle = thr
	hit_wall = false
	wall_impact = 0.0
	_wall_now = false
	track_phys(track)
	var prev_idx: int = idx

	# --- 1. steering command (rate limited) -------------------------------
	var d: float = steer_in - _sc
	var m: float = P.steer_rate * dt
	_sc += m if d > m else (-m if d < -m else d)

	# --- 2. surface under the car, drivetrain, nitro -------------------------
	_surface_env(track)
	_drivetrain(P, thr, hb, dt)
	if boost_now > 0.0:
		# extra push through the tyres (on top of the engine's drive, also during shifts),
		# fading out just below the top speed with nitro
		var u: float = vx * sin(yaw) + vz * cos(yaw)
		var fade: float = _clamp((P.nitro_top - u) / P.nitro_fade, 0.0, 1.0)
		_env_drive += boost_now * fade * minf(P.nitro_force, P.nitro_power / (u if u > 1.0 else 1.0))
		var left: float = nitro - (boost_now * dt) / P.nitro_time
		nitro = left if left > 1e-9 else 0.0 # (a full tank lasts exactly nitro_time, no rounding crumb left)
	boost = boost_now
	boosting = boost_now > 0.0

	# --- 3 + 4. planar dynamics and walls, in sub-steps ---------------------
	var n: int = P.substeps
	var h: float = dt / n
	var loc: Collision.Loc = null
	for s in n:
		_planar_step(P, h)
		loc = _walls(P, track, h)

	# --- 5. locate, vertical ------------------------------------------------
	if loc == null:
		loc = Collision.locate_near(track, x, z, idx, _loc)
	_vertical(P, track, loc, dt)

	# --- bookkeeping ------------------------------------------------------
	if track.closed:
		if loc.idx - prev_idx < -track.N / 2.0:
			laps += 1
		elif loc.idx - prev_idx > track.N / 2.0:
			laps -= 1
	if hit_wall:
		wall_hits += 1
	if _wall_t < 1000000:
		_wall_t += 1
	# wall contact for effects; the rub memory fades while off the wall
	if _wall_now:
		wall_y = y + WALL_Y
	if hit_wall:
		var vn: float = vx * wall_nx + vz * wall_nz
		wall_scrape = sqrt(maxf(0.0, vx * vx + vz * vz - vn * vn))
	else:
		wall_scrape = 0.0
		if _rub_t > 0.0:
			_rub_t = maxf(0.0, _rub_t - dt)
	idx = loc.idx
	prog = laps * track.N + loc.prog
	lat = loc.lat
	bank = loc.bank
	_t = loc.t
	_nx = loc.nx
	_nz = loc.nz
	_hw = loc.hw
	var fx: float = sin(yaw)
	var fz: float = cos(yaw)
	forward_speed = vx * fx + vz * fz
	side_speed = vx * fz - vz * fx
	speed = sqrt(vx * vx + vz * vz)
	wheel_rot = fmod(wheel_rot + (forward_speed / P.wheel_radius) * dt, 2.0 * PI)
	if wheel_rot < 0.0:
		wheel_rot += 2.0 * PI

	# derived "drifting" flag and slip amount (for effects)
	var a_r: float = absf(_slip_r)
	var a_f: float = absf(_slip_f)
	var fast: bool = speed > 8.0
	var hb_on: bool = _hb > 0.5 and speed > 12.0
	if drifting:
		drifting = grounded and fast and (a_r > 0.1 or hb_on)
	else:
		drifting = grounded and fast and (a_r > 0.16 or hb_on)
	var sl: float = 0.0
	if grounded and speed > 3.0:
		var lateral: float = (maxf(a_r, a_f) - 0.8 * P.peak_slip) / (2.2 * P.peak_slip)
		sl = maxf(maxf(lateral, _tc_cut), _hb * 0.9)
		sl *= minf(1.0, (speed - 3.0) / 6.0)
	slip = _clamp(sl, 0.0, 1.0)

	_attitude(track, loc, dt)


# ===========================================================================
# Surface: gravity along the road, normal load, cached track data
# ===========================================================================

## Per-sample data cached on the track (once): slope (dy/ds along the centre line) and
## vertical curvature (d²y/ds², smoothed) for crest/dip detection and normal load.
static func track_phys(track: BuiltTrack) -> void:
	var n: int = track.count
	if track.phys_kv.size() == n:
		return
	var closed: bool = track.closed
	var seg_len: float = track.seg_len
	var py: PackedFloat32Array = track.py
	var slope := PackedFloat32Array()
	var kv_raw := PackedFloat32Array()
	var kv := PackedFloat32Array()
	var tmp := PackedFloat32Array()
	slope.resize(n)
	kv_raw.resize(n)
	kv.resize(n)
	tmp.resize(n)
	for i in n:
		var a: float = py[posmod(i - 1, n)] if closed else py[maxi(0, mini(n - 1, i - 1))]
		var b: float = py[i]
		var c: float = py[posmod(i + 1, n)] if closed else py[maxi(0, mini(n - 1, i + 1))]
		slope[i] = (c - a) / (2.0 * seg_len)
		kv_raw[i] = (c - 2.0 * b + a) / (seg_len * seg_len)
	# smooth the curvature over ±3 samples (±6 m), twice (triangle-ish kernel)
	_box(kv_raw, tmp, 3, closed)
	_box(tmp, kv, 3, closed)
	track.phys_slope = slope
	track.phys_kv = kv


static func _box(src: PackedFloat32Array, dst: PackedFloat32Array, r: int, closed: bool) -> void:
	var n: int = src.size()
	for i in n:
		var s: float = 0.0
		var c: int = 0
		for k in range(-r, r + 1):
			var j: int = i + k
			if closed:
				j = posmod(j, n)
			elif j < 0 or j >= n:
				continue
			s += src[j]
			c += 1
		dst[i] = s / c


## The surface table's columns, for the physics (sim/surfaces.gd).
static var _S_ROLL: PackedFloat64Array = Surfaces.column("roll")
static var _S_STIFF: PackedFloat64Array = Surfaces.column("stiffness")
static var _S_ESC: PackedFloat64Array = Surfaces.column("esc")


## The surface blend under both axles (v6.3): front axle cg_to_front ahead of the car's
## position along the road, rear axle cg_to_rear behind (projected on the centre line).
func _surface_mix(P: CarSpec, track: BuiltTrack) -> void:
	_env_loose = false
	if track.surf_w.is_empty():
		return
	var cos_t: float = sin(yaw) * -_nz + cos(yaw) * _nx # heading against the road's tangent
	var p0: float = idx + _t
	_axle_mix(P, track, p0 + (P.cg_to_front * cos_t) / track.seg_len)
	var pure_f: bool = _mx_pure
	_env_gf = _mx_g
	_env_kf = _mx_k
	_env_rf = _mx_r
	var esc_f: float = _mx_e
	_axle_mix(P, track, p0 - (P.cg_to_rear * cos_t) / track.seg_len)
	if pure_f and _mx_pure:
		return
	_env_loose = true
	_env_gr = _mx_g
	_env_kr = _mx_k
	_env_rr = _mx_r
	_env_sesc = (esc_f + _mx_e) * 0.5
	_env_pk = atan((P.peak_slip / _env_kf) * P.steer_slip_gain)


## Blend of the surfaces at fractional sample p (into _mx_*): the car's grip share, stiffness,
## rolling resistance and ESC share, each the weights × the surface's number.
func _axle_mix(P: CarSpec, track: BuiltTrack, p: float) -> void:
	var n: int = track.count
	var k: int
	var f: float
	if track.closed:
		var kf: float = floorf(p)
		f = p - kf
		k = posmod(int(kf), track.N)
	elif p <= 0.0:
		k = 0
		f = 0.0
	elif p >= n - 1:
		k = n - 2
		f = 1.0
	else:
		var kf2: float = floorf(p)
		k = int(kf2)
		f = p - kf2
	var j: int = (k + 1) % track.N if track.closed else k + 1
	var S: int = track.surf_n
	var W: PackedFloat32Array = track.surf_w
	var G: PackedFloat64Array = P.surface_grip
	var g: float = 0.0
	var st: float = 0.0
	var r: float = 0.0
	var e: float = 0.0
	var a0: float = 0.0
	for s in S:
		var wa: float = W[k * S + s]
		var w: float = wa + (W[j * S + s] - wa) * f
		if s == 0:
			a0 = w
		g += w * G[s]
		st += w * _S_STIFF[s]
		r += w * _S_ROLL[s]
		e += w * _S_ESC[s]
	_mx_pure = a0 == 1.0
	_mx_g = g
	_mx_k = st
	_mx_r = r
	_mx_e = e


func _surface_env(track: BuiltTrack) -> void:
	_surface_mix(spec, track)
	var i: int = idx
	var j: int = (i + 1) % track.N if track.closed else mini(i + 1, track.count - 1)
	var t: float = _t
	var ps: PackedFloat32Array = track.phys_slope
	var slope_t: float = ps[i] + (ps[j] - ps[i]) * t
	var tb: float = tan(bank)
	# gradient of the road height on the x/z plane: along the tangent + across (bank)
	var nx: float = _nx # left normal
	var nz: float = _nz
	var tx: float = -nz # tangent
	var tz: float = nx
	var gx: float = slope_t * tx - tb * nx
	var gz: float = slope_t * tz - tb * nz
	var g2: float = gx * gx + gz * gz
	var inv_s: float = 1.0 / sqrt(1.0 + g2) # cos of the surface tilt
	# gravity's component in the road surface (≈ horizontal): -g sinθ along the gradient
	_env_gx = -G * gx * inv_s
	_env_gz = -G * gz * inv_s
	if not grounded:
		_env_gn = 0.0
		return
	# normal acceleration: g cosθ + (lateral acceleration into the slope) sinθ + vertical curvature
	var fx: float = sin(yaw)
	var fz: float = cos(yaw)
	var u: float = vx * fx + vz * fz
	var a_lat: float = u * yaw_rate # centripetal, towards the car's left
	var lx: float = fz
	var lz: float = -fx
	var gl: float = sqrt(g2)
	var into: float = 0.0
	if gl > 1e-4:
		into = -a_lat * (lx * gx + lz * gz) / gl # acceleration towards down-slope
	var sin_s: float = gl * inv_s
	var pk: PackedFloat32Array = track.phys_kv
	var kv_t: float = pk[i] + (pk[j] - pk[i]) * t
	var vt: float = vx * tx + vz * tz
	var gn: float = G * inv_s + into * sin_s + kv_t * vt * vt
	_env_gn = 0.0 if gn < 0.0 else (2.2 * G if gn > 2.2 * G else gn)


# ===========================================================================
# Drivetrain: gearbox, engine, brakes (once per 60 Hz step)
# ===========================================================================

func _drivetrain(P: CarSpec, thr: float, hb: bool, dt: float) -> void:
	var fx: float = sin(yaw)
	var fz: float = cos(yaw)
	var u: float = vx * fx + vz * fz
	var wheel_rpm: float = (absf(u) / P.wheel_radius) * (30.0 / PI)

	# Direction logic: brake to a stop first, then reverse (and the other way round).
	var drive: float = 0.0
	var brake: float = 0.0
	if _gear == -1:
		if thr > 0.02 and u > -1.0:
			_gear = 1
	elif thr < -0.02 and u < 1.0:
		_gear = -1
	if _gear >= 1 and thr < -0.02:
		brake = -thr
	elif _gear == -1 and thr > 0.02:
		brake = thr

	if _gear >= 1:
		# automatic gearbox
		if _shift > 0.0:
			_shift -= dt
		var fd: float = P.final_drive
		var gears: PackedFloat64Array = P.gears
		var rpm_w: float = wheel_rpm * gears[_gear - 1] * fd
		if _shift <= 0.0 and grounded:
			if rpm_w > P.upshift_rpm and _gear < gears.size() and thr > 0.02:
				_gear += 1
				_shift = P.shift_time
			elif _gear > 1 and rpm_w < P.downshift_rpm and wheel_rpm * gears[_gear - 2] * fd < P.upshift_rpm - 700.0:
				_gear -= 1
				_shift = P.shift_time * 0.5
			rpm_w = wheel_rpm * gears[_gear - 1] * fd
		var ratio: float = gears[_gear - 1] * fd
		# clutch slip when pulling away in first gear
		var rpm_eng: float = rpm_w
		if _gear == 1 and thr > 0.02:
			rpm_eng = maxf(rpm_w, P.idle_rpm + (P.launch_rpm - P.idle_rpm) * thr)
		rpm_eng = maxf(P.idle_rpm, rpm_eng)
		if thr > 0.02:
			if _shift <= 0.0 and rpm_w < P.redline:
				drive = (P.engine_torque(rpm_eng) * thr * ratio * P.efficiency) / P.wheel_radius
		elif grounded and rpm_w > P.idle_rpm * 1.2:
			# engine braking (friction + pumping torque grows with rpm)
			drive = -((25.0 + 0.009 * rpm_w) * ratio) / P.wheel_radius * signf(u)
		gear = 0 if speed < 0.3 and thr <= 0.02 else _gear
		var rpm_target: float = rpm_eng if grounded else maxf(rpm_eng, P.idle_rpm + (P.redline - P.idle_rpm) * maxf(0.0, thr))
		rpm += (minf(P.redline, rpm_target) - rpm) * minf(1.0, dt * 18.0)
	else:
		# reverse gear
		var ratio: float = P.reverse_ratio * P.final_drive
		var rpm_w: float = wheel_rpm * ratio
		var rpm_eng: float = maxf(rpm_w, P.idle_rpm + 2500.0 * maxf(0.0, -thr))
		if thr < -0.02 and u > -P.max_reverse:
			drive = -(P.engine_torque(rpm_eng) * -thr * ratio * P.efficiency * 0.6) / P.wheel_radius
		gear = -1
		rpm += (minf(P.redline, rpm_eng) - rpm) * minf(1.0, dt * 18.0)
	_env_drive = drive
	_env_brake = brake * P.brake_force
	# handbrake lever: ramps in (a keyboard tap gives a short, partial pull)
	if hb:
		_hb = minf(1.0, _hb + P.handbrake_rate * dt)
	else:
		_hb = maxf(0.0, _hb - 2.0 * P.handbrake_rate * dt)
	_env_hb = _hb
	# stability control: off while the handbrake is used and for a moment after, then fades back in
	if _hb > 0.02:
		_esc_off = P.esc_handbrake_hold
	elif _esc_off > 0.0:
		_esc_off = maxf(0.0, _esc_off - dt)
	_env_esc = P.esc * (1.0 if _esc_off <= 0.0 else (0.0 if _esc_off >= 0.5 else 1.0 - _esc_off / 0.5))
	# ... and while scraping a wall (the wall, not the tyres, sets the rotation then)
	var wt: int = _wall_t
	if wt < 45:
		_env_esc *= 0.0 if wt < 15 else (wt - 15) / 30.0
	braking = brake > 0.02 or (_hb > 0.1 and speed > 1.0)


# ===========================================================================
# Planar dynamics: bicycle model, one sub-step
# ===========================================================================

static func _mu_at(P: CarSpec, load: float, load0: float) -> float:
	var r: float = load / load0
	var k: float = 1.0 - P.load_sensitivity * (r - 1.0)
	return P.mu * (0.6 if k < 0.6 else (1.2 if k > 1.2 else k))


## Magic formula force ratio divided by slip (secant stiffness), finite at 0.
static func _secant(P: CarSpec, xs: float) -> float:
	var ax: float = -xs if xs < 0.0 else xs
	if ax < 1e-4:
		return P.pac_slope0
	return P.pacejka(ax) / ax


func _planar_step(P: CarSpec, h: float) -> void:
	var L: float = P.wheelbase
	var m: float = P.mass
	var iz: float = P.inertia
	var a: float = P.cg_to_front
	var b: float = P.cg_to_rear
	var yaw0: float = yaw
	var fx: float = sin(yaw0)
	var fz: float = cos(yaw0)
	var lx: float = fz
	var lz: float = -fx
	var u: float = vx * fx + vz * fz
	var v: float = vx * lx + vz * lz
	var r: float = yaw_rate
	var spd: float = sqrt(u * u + v * v)

	# External forces in the car frame: aero drag, gravity along the road.
	var drag_k: float = P.drag * spd
	var fx_e: float = -drag_k * u + m * (_env_gx * fx + _env_gz * fz)
	var fy_e: float = -drag_k * v + m * (_env_gx * lx + _env_gz * lz)

	if not grounded:
		# In the air: no tyre forces. The car keeps the yaw rate it took off with
		# (slowly damped); steering only adds a small, quickly fading correction.
		var r0: float = (r - _air_rs) * exp(-P.air_yaw_damp * h) # take-off rotation (+ any wall knock)
		_air_rs += (_sc * P.air_steer - _air_rs) * (1.0 - exp(-h / P.air_steer_tau))
		yaw_rate = r0 + _air_rs
		vx += ((fx_e * fx + fy_e * lx) / m) * h
		vz += ((fx_e * fz + fy_e * lz) / m) * h
		yaw = yaw0 + yaw_rate * h
		x += vx * h
		z += vz * h
		steer_angle = _sc * P.steer_lock * 0.5
		_slip_f = 0.0
		_slip_r = 0.0
		_tc_cut = 0.0
		_ax += (0.0 - _ax) * minf(1.0, h * 10.0)
		_ay = 0.0
		return

	# --- normal loads ------------------------------------------------------
	var down: float = P.downforce * spd * spd
	var w: float = m * _env_gn
	var tr: float = (m * _ax * P.cg_height) / L # longitudinal weight transfer
	var load_f: float = (w * b) / L + down * P.aero_front - tr
	var load_r: float = (w * a) / L + down * (1.0 - P.aero_front) + tr
	var min_load: float = 0.03 * w
	if load_f < min_load:
		load_f = min_load
	if load_r < min_load:
		load_r = min_load
	var load_f0: float = (m * G * b) / L
	var load_r0: float = (m * G * a) / L
	var cap_f: float = _mu_at(P, load_f, load_f0) * load_f
	var cap_r: float = _mu_at(P, load_r, load_r0) * load_r
	var loose: bool = _env_loose # dirt / snow under an axle (v6.3)
	if loose:
		cap_f *= _env_gf
		cap_r *= _env_gr

	# rolling resistance (opposes u, never reverses it)
	var sgn_u: float = 1.0 if u > 0.0 else (-1.0 if u < 0.0 else 0.0)
	var stop_f: float = (m * absf(u)) / h # force that would stop the car this sub-step
	var roll_f: float = P.roll_resist * (load_f + load_r)
	if loose:
		roll_f = P.roll_resist * (load_f * _env_rf + load_r * _env_rr)
	if roll_f > stop_f * 0.5:
		roll_f = stop_f * 0.5
	fx_e -= roll_f * sgn_u

	# --- longitudinal tyre forces --------------------------------------------
	var brake: float = _env_brake
	if brake > stop_f * 0.9:
		brake = stop_f * 0.9
	var hb: float = _env_hb # handbrake lever 0..1
	var drive_f: float = _env_drive * P.drive_front
	var drive_r: float = _env_drive - drive_f
	# Rear: cornering has priority (EBD / traction control), unless the handbrake is on.
	var fx_r: float = 0.0
	var fy_cap_r: float = cap_r
	var tc_cut: float = 0.0
	if hb > 0.0:
		# Handbrake: a strong rear brake that bypasses the electronics; the drive the
		# rear can't take goes to the front.
		drive_f += drive_r * hb
		drive_r *= 1.0 - hb
		var hbk: float = P.handbrake if u < 25.0 else (P.handbrake_fast if u > 55.0 else P.handbrake + ((P.handbrake_fast - P.handbrake) * (u - 25.0)) / 30.0)
		var fb: float = hb * hbk * cap_r
		if fb > stop_f * 0.5:
			fb = stop_f * 0.5
		fx_r = drive_r - fb * sgn_u - brake * (1.0 - P.brake_front) * sgn_u
		if fx_r > 0.97 * cap_r:
			fx_r = 0.97 * cap_r
		elif fx_r < -0.97 * cap_r:
			fx_r = -0.97 * cap_r
		fy_cap_r = sqrt(maxf(0.0, cap_r * cap_r - fx_r * fx_r))
	else:
		var fy_prev: float = absf(_fyr) if absf(_fyr) < cap_r else cap_r
		var long_cap: float = 0.97 * sqrt(cap_r * cap_r - fy_prev * fy_prev)
		var want: float = drive_r - brake * (1.0 - P.brake_front) * sgn_u
		var sliding: bool = absf(_slip_r) > P.peak_slip * P.slide_drive
		if sliding and want > 0.0:
			# rear already sliding: the driven wheels spin up and keep it loose (power slide)
			if want > 0.97 * cap_r:
				want = 0.97 * cap_r
			fy_cap_r = sqrt(maxf(0.0, cap_r * cap_r - want * want))
		elif want > long_cap:
			# traction control: cut what the rear can't use without losing cornering grip
			if drive_r > 0.0:
				tc_cut = maxf(tc_cut, (want - long_cap) / (absf(_env_drive) + 1.0))
			want = long_cap
		elif want < -long_cap:
			want = -long_cap
		fx_r = want
	# Front: driving/braking has priority, cornering gets what is left.
	var fx_f: float = drive_f - brake * P.brake_front * sgn_u
	var fx_cap_f: float = 0.97 * cap_f
	if fx_f > fx_cap_f:
		tc_cut = maxf(tc_cut, (fx_f - fx_cap_f) / (absf(_env_drive) + 1.0))
		fx_f = fx_cap_f
	elif fx_f < -fx_cap_f:
		fx_f = -fx_cap_f
	var fy_cap_f: float = sqrt(maxf(0.0, cap_f * cap_f - fx_f * fx_f))
	_tc_cut = tc_cut

	# --- steering angle --------------------------------------------------------
	# Speed-sensitive lock (about the grip limit at this speed, never more than the
	# mechanical lock) + countersteer assist when the rear slides.
	var sc: float = _sc
	var delta: float = 0.0
	var delta_cmd: float = 0.0
	if u > 0.5:
		var wf: float = (u - P.steer_slow_speed) / (P.steer_fast_speed - P.steer_slow_speed)
		wf = 0.0 if wf <= 0.0 else (1.0 if wf >= 1.0 else wf * wf * (3.0 - 2.0 * wf))
		var lock: float
		if loose:
			# the same lock for the grip and the tyre this surface leaves
			lock = atan((L * P.steer_ref_accel * _env_gf) / (u * u)) + _env_pk + (P.steer_extra_fast / _env_kf - _env_pk) * wf
		else:
			lock = atan((L * P.steer_ref_accel) / (u * u)) + P.peak_steer + (P.steer_extra_fast - P.peak_steer) * wf
		delta = sc * (lock if lock < P.steer_lock else P.steer_lock)
		delta_cmd = delta
		if u > 3.0:
			var slide_r: float = atan((v - b * r) / u) # rear slip angle
			var ab: float = -slide_r if slide_r < 0.0 else slide_r
			if ab > P.assist_from:
				var aw: float = (ab - P.assist_from) / (P.assist_full - P.assist_from)
				aw = 1.0 if aw > 1.0 else aw * aw * (3.0 - 2.0 * aw)
				var fade: float = (u - 3.0) / 5.0 if u < 8.0 else 1.0
				delta += slide_r * aw * fade * P.steer_assist
	else:
		var rev: float = minf(1.0, 6.0 / -u) if u < -0.5 else 1.0
		delta = sc * P.steer_lock * rev
	if delta > P.steer_lock:
		delta = P.steer_lock
	elif delta < -P.steer_lock:
		delta = -P.steer_lock
	steer_angle = delta
	var c: float = cos(delta)
	var s: float = sin(delta)

	# --- lateral tyre stiffness (secant of the magic formula) -------------------
	# front wheel frame velocities
	var vfa: float = v + a * r
	var uw: float = u * c + vfa * s
	var vw: float = -u * s + vfa * c
	var uf: float = absf(uw) if absf(uw) > U_MIN else U_MIN
	var x_f: float = vw / uf
	var k_f: float = (fy_cap_f * _secant(P, x_f)) / uf # N per (m/s) of lateral wheel velocity
	var vr: float = v - b * r
	var ur: float = absf(u) if absf(u) > U_MIN else U_MIN
	var x_r: float = vr / ur
	var k_r: float = (fy_cap_r * _secant(P, x_r)) / ur
	if loose:
		# a softer tyre: the force at slip x is the asphalt force at x × stiffness
		k_f = (fy_cap_f * (_env_kf * _secant(P, x_f * _env_kf))) / uf
		k_r = (fy_cap_r * (_env_kr * _secant(P, x_r * _env_kr))) / ur
	_slip_f = x_f
	_slip_r = x_r

	# --- semi-implicit solve for the new sideways speed v' and yaw rate r' ------
	var kfc2: float = k_f * c * c
	var hm: float = h / m
	var hi: float = h / iz
	var a11: float = 1.0 + hm * (kfc2 + k_r)
	var a12: float = hm * (kfc2 * a - k_r * b) + h * u
	var b1: float = v + hm * (fx_f * s + k_f * c * u * s + fy_e)
	var a21: float = hi * (a * kfc2 - b * k_r)
	var a22: float = 1.0 + hi * (a * a * kfc2 + b * b * k_r)
	var b2: float = r + hi * (a * (fx_f * s + k_f * c * u * s))
	var det: float = a11 * a22 - a12 * a21
	var v1: float = (b1 * a22 - a12 * b2) / det
	var r1: float = (a11 * b2 - a21 * b1) / det

	# tyre forces at the solved state, clamped to their grip
	var fy_f: float = k_f * (u * s - c * (v1 + a * r1))
	if fy_f > fy_cap_f:
		fy_f = fy_cap_f
	elif fy_f < -fy_cap_f:
		fy_f = -fy_cap_f
	var fy_r: float = -k_r * (v1 - b * r1)
	if fy_r > fy_cap_r:
		fy_r = fy_cap_r
	elif fy_r < -fy_cap_r:
		fy_r = -fy_cap_r
	_fyr = fy_r

	# body-frame totals
	var f_x: float = fx_f * c - fy_f * s + fx_r + fx_e
	var f_y: float = fx_f * s + fy_f * c + fy_r + fy_e
	var mz: float = a * (fx_f * s + fy_f * c) - b * fy_r

	# integrate (world frame for velocity, so turning never creates speed)
	var r_n: float = r + (mz / iz) * h
	var vx_n: float = vx + ((f_x * fx + f_y * lx) / m) * h
	var vz_n: float = vz + ((f_x * fz + f_y * lz) / m) * h

	# --- stability control (ESC) ---------------------------------------------
	# Compares the yaw rate with what the steering asks for (never more than the
	# tyres can hold at this speed) and brakes single wheels to pull the car back.
	if _env_esc > 0.0 and u > P.esc_from:
		var r_lim: float = (fy_cap_f + fy_cap_r) / (m * u) # yaw rate of a grip-limited steady turn
		var r_ref: float = (u * tan(delta_cmd)) / L
		if r_ref > r_lim:
			r_ref = r_lim
		elif r_ref < -r_lim:
			r_ref = -r_lim
		var e: float = r_n - r_ref
		var ae: float = (-e if e < 0.0 else e) - P.esc_deadband
		if ae > 0.0:
			var under: bool = e * r_ref < 0.0 and r_n * r_ref > 0.0
			var fade_in: float = (u - P.esc_from) / 4.0 if u < P.esc_from + 4.0 else 1.0
			var mom: float = iz * P.esc_gain * ae
			var m_max: float = P.esc_moment * (P.esc_under if under else 1.0)
			if loose:
				m_max *= _env_sesc
			if mom > m_max:
				mom = m_max
			mom *= _env_esc * fade_in
			r_n -= (mom if e > 0.0 else -mom) * (h / iz)
			# the single-wheel braking that makes the moment also slows the car a little
			var sp: float = sqrt(vx_n * vx_n + vz_n * vz_n)
			if sp > 1.0:
				var dv: float = ((mom / 0.8) * P.esc_slow * h) / m
				if dv > sp * 0.5:
					dv = sp * 0.5
				vx_n -= (vx_n / sp) * dv
				vz_n -= (vz_n / sp) * dv
	yaw_rate = r_n
	vx = vx_n
	vz = vz_n
	yaw = yaw0 + yaw_rate * h
	x += vx * h
	z += vz * h
	# filtered accelerations for weight transfer and body attitude (suspension lag)
	var kf: float = minf(1.0, h * 12.0)
	_ax += ((f_x - fx_e + (-drag_k * u)) / m - _ax) * kf
	_ay += (f_y / m + 0.0 - _ay) * kf


# ===========================================================================
# Walls
# ===========================================================================

## Wall collisions for one sub-step. Returns the located position (the car's
## scratch Loc), or null when the safety net moved the car.
func _walls(P: CarSpec, track: BuiltTrack, h: float) -> Collision.Loc:
	var R: float = P.radius
	var core: float = P.core
	# Broad phase: far from both walls and from the ends of a sprint track -> nothing to do.
	var hint: int = idx
	var loc: Collision.Loc = Collision.locate_near(track, x, z, hint, _loc)
	idx = loc.idx
	_t = loc.t
	_nx = loc.nx
	_nz = loc.nz
	_hw = loc.hw
	var near_end: bool = not track.closed and (loc.idx < 4 or loc.idx > track.seg_count - 5)
	var reach: float = P.half_length + 1.5
	if not near_end and absf(loc.lat) < loc.hw - reach:
		return loc

	# Flying higher than the barriers: nothing to hit up there. The whole capsule is
	# only kept inside the barrier line, so the car comes down on the road.
	if not grounded and y - loc.ground_y > P.wall_height and not near_end:
		var ax: float = sin(yaw) * loc.nx + cos(yaw) * loc.nz # how far the capsule's axis points across the road
		var lim: float = loc.hw - R - core * (-ax if ax < 0.0 else ax)
		if absf(loc.lat) <= lim:
			return loc
		var sgn: float = 1.0 if loc.lat > 0.0 else -1.0
		var push: float = absf(loc.lat) - lim
		x -= loc.nx * push * sgn
		z -= loc.nz * push * sgn
		var vn: float = (vx * loc.nx + vz * loc.nz) * sgn
		if vn > 0.0:
			vx -= loc.nx * vn * sgn
			vz -= loc.nz * vn * sgn
		return Collision.locate_near(track, x, z, idx, _loc)

	var grid: Collision.WallGrid = track.grid
	var c: Collision.Contact = _contact
	var touched: bool = false
	for iter in 4:
		var fx: float = sin(yaw)
		var fz: float = cos(yaw)
		var p0x: float = x - fx * core
		var p0z: float = z - fz * core
		var p1x: float = x + fx * core
		var p1z: float = z + fz * core
		# a thin skin keeps the contact (and hit_wall) steady while scraping along a wall
		if not Collision.collide_capsule(grid, p0x, p0z, p1x, p1z, R + SKIN, c):
			# contact hysteresis: a car that touched in the last few steps still counts as
			# scraping while it stays within wall_latch of the wall, and a corner still
			# swinging towards the wall keeps losing that rotation
			if iter == 0 and _wall_t < P.wall_latch_steps and Collision.collide_capsule(grid, p0x, p0z, p1x, p1z, R + P.wall_latch, c):
				hit_wall = true
				touched = true
				_wall_contact(c.px, c.pz, c.nx, c.nz)
				_stop_rotation(P, c.px - x, c.pz - z, c.nx, c.nz)
			break
		touched = true
		hit_wall = true
		_wall_t = -1
		var nx: float = c.nx
		var nz: float = c.nz
		var depth: float = c.depth - SKIN
		c.px += nx * SKIN
		c.pz += nz * SKIN
		if depth <= 1e-5:
			# touching: only stop motion into the wall
			_wall_contact(c.px, c.pz, nx, nz)
			if vx * nx + vz * nz < 0.0:
				_impulse(P, c.px - x, c.pz - z, nx, nz, h)
			break
		# push out (no velocity change from the push)
		x += nx * depth
		z += nz * depth
		# contact point relative to the centre (after the push)
		var dx: float = c.px + nx * depth - x
		var dz: float = c.pz + nz * depth - z
		_wall_contact(x + dx, z + dz, nx, nz)
		_impulse(P, dx, dz, nx, nz, h)
	if touched:
		_rub(P, h)

	# Safety net: the centre must stay on the road whatever happens (a small,
	# bounded nudge per sub-step, so a badly shaped track can never fling the car).
	# (Untouched, the car hasn't moved: when the segment didn't change either, this is the
	# very same query as the one above, whose answer is still in _loc.)
	var l2: Collision.Loc = loc if not touched and idx == hint else Collision.locate_near(track, x, z, idx, _loc)
	var lim2: float = l2.hw - 0.3
	if absf(l2.lat) > lim2:
		var sgn: float = 1.0 if l2.lat > 0.0 else -1.0
		var push: float = absf(l2.lat) - lim2
		if not (push < 0.5):
			push = 0.5
		x -= l2.nx * push * sgn
		z -= l2.nz * push * sgn
		var vn: float = (vx * l2.nx + vz * l2.nz) * sgn
		if vn > 0.0:
			vx -= l2.nx * vn * sgn
			vz -= l2.nz * vn * sgn
			wall_impact += vn
		var gap: float = l2.hw - absf(l2.lat) + push # from the centre (after the nudge) out to the wall line
		_wall_contact(x + l2.nx * gap * sgn, z + l2.nz * gap * sgn, -l2.nx * sgn, -l2.nz * sgn)
		hit_wall = true
		_wall_t = -1
		return null
	return l2


## Remember the latest wall contact (point and normal back to the road) for effects.
func _wall_contact(px: float, pz: float, nx: float, nz: float) -> void:
	wall_x = px
	wall_z = pz
	wall_nx = nx
	wall_nz = nz
	_wall_now = true


## Rubbing along a wall: the sliding speed along it fades by wall_rub per second,
## building up over wall_rub_build s of contact. Nothing pulls the car to the wall.
func _rub(P: CarSpec, h: float) -> void:
	var nx: float = wall_nx
	var nz: float = wall_nz
	var vn: float = vx * nx + vz * nz
	var tvx: float = vx - vn * nx
	var tvz: float = vz - vn * nz
	_rub_t = minf(P.wall_rub_build, _rub_t + h)
	var k: float = P.wall_rub * h * (_rub_t / P.wall_rub_build if P.wall_rub_build > 0.0 else 1.0)
	vx -= tvx * k
	vz -= tvz * k


## Remove part (wall_yaw_stop) of the rotation that swings the contact point (dx, dz from the centre) into the wall.
func _stop_rotation(P: CarSpec, dx: float, dz: float, nx: float, nz: float) -> void:
	var kn: float = dz * nx - dx * nz # normal velocity of the contact point per unit yaw rate
	var wn: float = yaw_rate * kn
	if wn < 0.0 and absf(kn) > 0.05:
		yaw_rate -= (P.wall_yaw_stop * wn) / kn


## Velocity response at a wall contact: the speed into the wall goes (almost no bounce),
## friction along the wall grows with the hit, rotation into the wall stops, and a
## gentle yaw aligns the car with the wall it scrapes. Acts on the car's centre.
func _impulse(P: CarSpec, dx: float, dz: float, nx: float, nz: float, h: float) -> void:
	var vn: float = vx * nx + vz * nz
	if vn < 0.0:
		wall_impact -= vn
		# almost no bounce, and never more than max_rebound m/s
		var reb: float = -vn * P.wall_restitution
		var jn: float = -vn + (reb if reb < P.max_rebound else P.max_rebound)
		vx += nx * jn
		vz += nz * jn
		var vn2: float = vx * nx + vz * nz
		var tvx: float = vx - vn2 * nx
		var tvz: float = vz - vn2 * nz
		var vt: float = sqrt(tvx * tvx + tvz * tvz)
		if vt > 1e-6:
			var dv: float = (P.wall_friction + P.wall_crush * jn) * jn
			# slow sliding: the friction fades out, so a car pressed nose-in slides off
			if vt < P.wall_slide:
				dv *= vt / P.wall_slide
			if dv > vt:
				dv = vt
			vx -= (tvx / vt) * dv
			vz -= (tvz / vt) * dv
	# rotation pushing the contact point into the wall: take it away (over a few sub-steps)
	_stop_rotation(P, dx, dz, nx, nz)
	# gentle alignment with the wall, in the direction the car is sliding
	var fx: float = sin(yaw)
	var fz: float = cos(yaw)
	var u: float = vx * fx + vz * fz
	if absf(u) > 2.0:
		var dir: float = 1.0 if u > 0.0 else -1.0 # the end of the car that leads
		var fn: float = (fx * nx + fz * nz) * dir # < 0: leading end points into the wall
		if fn < 0.0:
			var ln: float = (fz * nx - fx * nz) * dir # turning left lifts the nose off the wall if > 0
			var ang: float = asin(minf(1.0, -fn)) # angle between heading and wall
			var target: float = (1.0 if ln >= 0.0 else -1.0) * dir * minf(P.wall_align, ang * P.wall_align_gain)
			if yaw_rate * target < target * target:
				var m: float = P.wall_align_accel * h
				var d: float = target - yaw_rate
				yaw_rate += m if d > m else (-m if d < -m else d)


# ===========================================================================
# Vertical: glued to the road, real jumps only, damped landings
# ===========================================================================

static func _road_height_at(track: BuiltTrack, p: float, lat_at: float) -> float:
	var kf: float = floorf(p)
	var t: float = p - kf
	var k: int = int(kf)
	var n: int = track.count
	if track.closed:
		k = ((k % track.N) + track.N) % track.N
	elif k >= n - 1:
		k = n - 2
		t = 1.0
	elif k < 0:
		k = 0
		t = 0.0
	var j: int = (k + 1) % track.N if track.closed else k + 1
	var py: float = track.py[k] + (track.py[j] - track.py[k]) * t
	var bk: float = track.bank[k] + (track.bank[j] - track.bank[k]) * t
	return py - lat_at * tan(bk)


func _vertical(P: CarSpec, track: BuiltTrack, loc: Collision.Loc, dt: float) -> void:
	var g_y: float = loc.ground_y
	var spd2: float = vx * vx + vz * vz
	var g_eff: float = P.gravity + (P.downforce * spd2) / P.mass
	if grounded:
		var v_ground: float = (g_y - y) / dt # vertical speed of the road under the car
		_ground += dt
		# Could the road be dropping away faster than the car can follow?
		var i: int = loc.idx
		var j: int = (i + 1) % track.N if track.closed else mini(i + 1, track.count - 1)
		var pk: PackedFloat32Array = track.phys_kv
		var kv: float = pk[i] + (pk[j] - pk[i]) * loc.t
		var tx: float = -loc.nz
		var tz: float = loc.nx
		var vt: float = vx * tx + vz * tz
		var take_off: bool = false
		if kv * vt * vt < -g_eff and _ground > 0.05 and absf(vt) > 5.0:
			# The smoothed road curves down faster than gravity can follow. Confirm by
			# flying the ballistic path forward against the actual road ahead: take off
			# only if the car would stay clear of the road from the very next step and
			# rise more than lift_separation, for at least min_flight seconds.
			var v0: float = v_ground
			var max_sep: float = 0.0
			var flight: float = 0.0
			for k in range(1, 37):
				var T: float = k * dt
				var road: float = _road_height_at(track, loc.prog + (vt * T) / track.seg_len, loc.lat)
				var sep: float = g_y + v0 * T - 0.5 * g_eff * T * T - road
				if sep < 0.0:
					break
				flight = T
				if sep > max_sep:
					max_sep = sep
			take_off = max_sep > P.lift_separation and flight >= P.min_flight
		if take_off:
			grounded = false
			air_time = 0.0
			_air_rs = 0.0
			vy = v_ground
			y = g_y
		else:
			y = g_y
			vy = v_ground
			air_time = 0.0
	else:
		air_time += dt
		y += vy * dt - 0.5 * g_eff * dt * dt # exact ballistic step (matches the take-off prediction)
		vy -= g_eff * dt
		# Just after take-off the path skims the road: don't let rounding end the jump.
		if air_time < 0.1 and y < g_y and y > g_y - 0.02:
			y = g_y
		elif y < g_y:
			# Landing: the vertical speed relative to the road under the car.
			var slope_along: float = (_road_height_at(track, loc.prog + 0.5, loc.lat) - _road_height_at(track, loc.prog - 0.5, loc.lat)) / track.seg_len
			var tx: float = -loc.nz
			var tz: float = loc.nx
			var vt: float = vx * tx + vz * tz
			var v_road: float = slope_along * vt
			var impact: float = v_road - vy # > 0 when hitting the road
			if impact > P.hard_landing:
				var loss: float = minf(0.15, P.landing_loss * (impact - P.hard_landing))
				vx *= 1.0 - loss
				vz *= 1.0 - loss
			_pitch_v -= minf(0.6, 0.03 * impact) # nose dips as the suspension compresses
			y = g_y
			vy = v_road
			grounded = true
			_ground = 0.0
	ground_y = g_y


# ===========================================================================
# Visual body attitude
# ===========================================================================

## Pitch/roll of the road surface under the car, in the car's frame (into _att_pitch / _att_roll).
func _road_attitude(track: BuiltTrack, loc: Collision.Loc) -> void:
	var i: int = loc.idx
	var j: int = (i + 1) % track.N if track.closed else mini(i + 1, track.count - 1)
	var ps: PackedFloat32Array = track.phys_slope
	var slope_t: float = ps[i] + (ps[j] - ps[i]) * loc.t
	var tb: float = tan(loc.bank)
	var nx: float = loc.nx
	var nz: float = loc.nz
	var tx: float = -nz
	var tz: float = nx
	var gx: float = slope_t * tx - tb * nx # height gradient
	var gz: float = slope_t * tz - tb * nz
	var fx: float = sin(yaw)
	var fz: float = cos(yaw)
	_att_pitch = atan(gx * fx + gz * fz) # uphill ahead -> nose up
	_att_roll = atan(gx * fz - gz * fx) # ground rising to the left -> left side up


func _attitude(track: BuiltTrack, loc: Collision.Loc, dt: float) -> void:
	var tp: float
	var tr: float
	var w: float
	if grounded:
		_road_attitude(track, loc)
		# squat under acceleration (nose up), dive under braking; roll out of corners
		var ax: float = _clamp(_ax, -20.0, 20.0)
		var ay: float = _clamp(forward_speed * yaw_rate, -25.0, 25.0)
		tp = _att_pitch + 0.0032 * ax
		tr = _att_roll + 0.0035 * ay
		w = 11.0
	else:
		var vh: float = maxf(4.0, speed)
		tp = _clamp(atan2(vy, vh) * 0.6, -0.4, 0.4)
		tr = roll * 0.98
		w = 3.0
	# critically-damped-ish spring (semi-implicit, stable at 60 Hz)
	var zeta: float = 0.8
	_pitch_v += (w * w * (tp - pitch) - 2.0 * zeta * w * _pitch_v) * dt
	_roll_v += (w * w * (tr - roll) - 2.0 * zeta * w * _roll_v) * dt
	pitch += _pitch_v * dt
	roll += _roll_v * dt


static func _clamp(v: float, a: float, b: float) -> float:
	return a if v < a else (b if v > b else v)


# ===========================================================================
# Whole-state access (tests, parity tools, ghosts of the future)
# ===========================================================================

## The whole car state with the JS names (the spec is not part of it, as in the JS).
func to_state() -> Dictionary:
	var d: Dictionary = {}
	for k: String in STATE_KEYS:
		d[k] = get(k.to_snake_case())
	return d


## Sets the car state from to_state()-style data (JS names; missing keys are kept).
func from_state(d: Dictionary) -> void:
	for k: String in STATE_KEYS:
		if not d.has(k):
			continue
		var key: String = k.to_snake_case()
		var v: Variant = d[k]
		match typeof(get(key)):
			TYPE_BOOL:
				set(key, bool(v))
			TYPE_INT:
				set(key, int(v))
			_:
				set(key, float(v))


## Copies another car's whole state (and its spec) into this one.
func copy_from(other: Car) -> void:
	spec = other.spec
	from_state(other.to_state())
