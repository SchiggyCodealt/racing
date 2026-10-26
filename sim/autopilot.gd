class_name Autopilot
extends RefCounted
## autopilot.gd: the look-ahead autopilots of the web game's tools, used for medal
## times (tools/medals.gd), tests and tools (car stats, bench).
## ------------------------------------------------------------------
## It plans a speed for every sample of road from the curvature (corner speed for
## a lateral grip, braking towards every corner at a fixed rate), steers at a point
## on the centre line ahead and, optionally, burns nitro on the straights.
##
##   Autopilot.medal(track, a_lat, look_k, nitro)  web/tools/medals.mjs makeAutopilot:
##       corner speed from the heading change over ±3 samples, braking at DECEL, aims
##       6 m + look_k × speed ahead (at most LOOK_MAX), nitro at full throttle with
##       |steer| < NITRO_STEER
##   Autopilot.basic(track, grip, brake, top)       web/tools/selfTest.mjs makeAutopilot:
##       ±4 samples, aims 6 m + 0.35 × speed ahead (4..14 samples), no nitro
##   var ctrl: Car.Controls = pilot.drive(car)      every step (the same Controls object)
##
## Both are deterministic: the same car state gives the same controls.

const DECEL: float = 11.0 # m/s², the braking the medal autopilot plans with
const NITRO_STEER: float = 0.25 # nitro at full throttle with |steer| below this
const LOOK_MAX: float = 80.0 # m, the furthest the medal autopilot aims
## The medal sweep's two cornering settings (tools/medals.gd).
const GRID_A_LAT: Array[float] = [14.0, 16.0, 18.0, 20.0, 22.0, 24.0, 26.0, 28.0, 32.0, 40.0]
const GRID_LOOK_K: Array[float] = [0.35, 0.55, 0.75, 1.0, 1.3]

var track: BuiltTrack
## speed target per sample (m/s)
var vt: PackedFloat64Array = PackedFloat64Array()
var look_k: float = 0.35
var look_min: int = 4
var look_max: int = 14
var use_nitro: bool = false
var ctrl: Car.Controls = Car.Controls.new()


## The medal sweep's autopilot for one setting (aLat m/s² of planned grip, aim lookK).
static func medal(t: BuiltTrack, a_lat: float, k: float, nitro: bool = false, decel: float = DECEL) -> Autopilot:
	var p := Autopilot.new()
	p.track = t
	p._plan(3, 6.0, 100.0, 1e4, a_lat, decel, false)
	p.look_k = k
	p.look_min = 3
	p.look_max = JsMath.roundi(LOOK_MAX / t.seg_len)
	p.use_nitro = nitro
	return p


## The test autopilot (corner speed for `grip` m/s², braking at `brake` m/s², at most `top` m/s).
static func basic(t: BuiltTrack, grip: float = 11.0, brake: float = 7.5, top: float = 77.0) -> Autopilot:
	var p := Autopilot.new()
	p.track = t
	p._plan(4, 8.0, top, 1e5, grip, brake, true)
	p.look_k = 0.35
	p.look_min = 4
	p.look_max = 14
	return p


func _at(i: int) -> int:
	var n: int = track.count
	return posmod(i, n) if track.closed else maxi(0, mini(n - 1, i))


static func _wrap(a: float) -> float:
	return atan2(sin(a), cos(a))


## Speed targets: corner speed from the heading change over ±window samples, then
## lowered backwards from every corner so the car can brake down to it.
## (f32: kept in float32 like the test autopilot's Float32Array.)
func _plan(window: int, span: float, cap: float, straight: float, grip: float, decel: float, f32: bool) -> void:
	var n: int = track.count
	var closed: bool = track.closed
	var seg: float = track.seg_len
	var f := PackedFloat32Array()
	f.resize(1)
	vt.resize(n)
	for i in n:
		var a: int = _at(i - window)
		var b: int = _at(i + window)
		var turn: float = absf(_wrap(atan2(track.tx[b], track.tz[b]) - atan2(track.tx[a], track.tz[a])))
		var v: float = minf(cap, sqrt(grip * ((span * seg) / turn if turn > 1e-4 else straight)))
		if f32:
			f[0] = v
			v = f[0]
		vt[i] = v
	for _pass in (2 if closed else 1):
		for i in range(n - 1, -1, -1):
			var j: int = (i + 1) % n if closed else i + 1
			if j < n:
				var v: float = minf(vt[i], sqrt(vt[j] * vt[j] + 2.0 * decel * seg))
				if f32:
					f[0] = v
					v = f[0]
				vt[i] = v


## The controls for this step (the same Controls object every call).
func drive(car: Car) -> Car.Controls:
	var seg: float = track.seg_len
	var look: int = maxi(look_min, mini(look_max, JsMath.roundi((6.0 + car.speed * look_k) / seg)))
	var i: int = _at(car.idx + look)
	var gx: float = track.px[i] - car.x
	var gz: float = track.pz[i] - car.z
	var fx: float = sin(car.yaw)
	var fz: float = cos(car.yaw)
	ctrl.steer = maxf(-1.0, minf(1.0, 3.0 * atan2(gx * fz - gz * fx, gx * fx + gz * fz)))
	var target: float = vt[_at(car.idx + 1)]
	ctrl.throttle = 1.0 if car.speed < target - 1.0 else (-1.0 if car.speed > target + 1.5 else 0.3)
	ctrl.handbrake = false
	ctrl.nitro = 1.0 if use_nitro and ctrl.throttle == 1.0 and absf(ctrl.steer) < NITRO_STEER else 0.0
	return ctrl


const MAX_STEPS: int = 60 * 60 * 15 # 15 min: a medal run that takes longer doesn't count
const STUCK_STEPS: int = 180 # 3 s without gaining 3 samples (~6 m): stuck, the run doesn't count


## One Drive race with the medal autopilot (web/tools/medals.mjs driveRace): car `car_id`
## from a standing start at GO with a full tank, burning nitro on the straights with the
## style score's refills (nitro false: no nitro, no score). Returns {finished, time, steps,
## wall (steps touching a wall), laps, score (points), burned, refilled (nitro, in tanks)}.
static func drive_race(t: BuiltTrack, a_lat: float, k: float, car_id: String = Cars.DEFAULT_CAR, nitro: bool = true) -> Dictionary:
	var dt: float = 1.0 / 60.0
	var car := Car.new(t, -1, Cars.spec(car_id))
	var race := RaceState.new(t)
	var pilot := Autopilot.medal(t, a_lat, k, nitro)
	var score: ScoreState = ScoreState.new(t, true) if nitro else null
	var steps: int = 0
	var wall: int = 0
	var best: float = car.prog
	var gained: int = 0
	var burned: float = 0.0
	while not race.finished and steps < MAX_STEPS and steps - gained <= STUCK_STEPS:
		var tank: float = car.nitro
		car.step(t, pilot.drive(car), dt)
		if car.nitro < tank:
			burned += tank - car.nitro
		race.update(car, dt)
		if score != null:
			score.update(car, race, dt) # after race.update, as in Drive: banked points refill the tank
		steps += 1
		if car.hit_wall:
			wall += 1
		if car.prog > best + 3.0:
			best = car.prog
			gained = steps
	return {
		finished = race.finished, time = race.finish_time, steps = steps, wall = wall, laps = race.laps,
		score = score.total if score != null else 0.0, burned = burned, refilled = score.nitro if score != null else 0.0,
	}
