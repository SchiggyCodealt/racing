extends SceneTree
## car_stats.gd: measures every car's stats with the real physics (a port of
## web/tools/carStats.mjs; the numbers are the `stats` of sim/cars.gd).
## ------------------------------------------------------------------
##   godot --headless --path <copy> --script res://tools/car_stats.gd [-- options]
##     (no option)   measure, print a table and the `stats = {...}` line of every car
##     --check       measure and compare with the stats stored in sim/cars.gd;
##                   exits 1 when one is off by more than its tolerance
##     --jobs=N      measure on N threads (default: one per car, at most 4); same numbers
## tests/test_sim.gd runs the same check (measure_car + stats_mismatch), so the numbers on
## the car picker can't go stale: after changing a spec, run this and paste the printed
## stats lines into sim/cars.gd. About 15 s per car on one core, no scene.
##
## What is measured (all on flat synthetic roads, 60 Hz like the game):
##   accel100 / accel200   s from a standstill, full throttle, a light hand keeping the car straight
##   top                   km/h, the highest speed in 150 s of full throttle on a 25 km straight
##   accel200n             s, 0-200 km/h with nitro held from a full tank (as at the start of a race)
##   topNitro              km/h, top speed with nitro held and the tank kept full
##   tankTime              s a full tank lasts with nitro held from a standstill
##   tankDist              m covered in that time
##   brake100              m, 100-0 km/h, full brakes, wheels straight
##   grip / gripFast       g, the fastest steady lap of a 30 / 120 m circle (speed² / radius) that
##                         a look-ahead driver holds within 4 m of the line, without touching a wall
##   drift                 s, how long a keyboard driver holds a drift: on an open pad at 60-130 km/h, a
##                         handbrake pull with a steer key held (0.2-0.8 s), then throttle and digital
##                         countersteer (a key towards the slide above a target body slip angle of 15-35°,
##                         the turn key below it). The longest stretch above 12° of body slip in each of
##                         192 runs (a spin counts as 0); the median of those
##
## From other scripts: const CarStats = preload("res://tools/car_stats.gd"), then
## CarStats.prepare() once on the main thread, CarStats.measure_car(spec) -> stats Dictionary
## (JS key names), CarStats.stats_mismatch(stored, measured) -> [{key, stored, measured}].

const DT: float = 1.0 / 60.0
const KMH: float = 3.6

## How far a stored stat may be from a fresh measurement (absolute, in its unit).
const TOLERANCE: Dictionary = {
	mass = 0.0, accel100 = 0.03, accel200 = 0.05, top = 0.5, accel200n = 0.05, topNitro = 0.5,
	tankTime = 0.05, tankDist = 3.0, brake100 = 0.3, grip = 0.02, gripFast = 0.02, drift = 0.05,
}
const STAT_KEYS: Array[String] = ["mass", "accel100", "accel200", "top", "accel200n", "topNitro",
	"tankTime", "tankDist", "brake100", "grip", "gripFast", "drift"]
## The keyboard steering ramp of the game's input (web/src/game/input.js).
const KEYS: Dictionary = {rateSlow = 7.0, rateFast = 3.2, fastSpeed = 50.0, ret = 10.0}

static var _straight: BuiltTrack = null
static var _circles: Dictionary = {}
static var _pad: BuiltTrack = null


## Builds the synthetic roads (call once on the main thread before measuring on threads).
static func prepare() -> void:
	road()
	circle(30.0)
	circle(120.0)
	pad()


static func road() -> BuiltTrack:
	if _straight == null:
		var pts: Array = []
		for k in 126:
			pts.append([0, k * 200, 0])
		_straight = Tracks.build_def({id = "stats-straight", name = "Stats straight", type = "sprint", laps = 1, width = 30,
			checkpoints = [], points = pts})
	return _straight


static func circle(R: float) -> BuiltTrack:
	if not _circles.has(R):
		var pts: Array = []
		for k in 96:
			var a: float = (k / 96.0) * PI * 2.0
			pts.append([R * sin(a), R * cos(a) - R, 0])
		_circles[R] = Tracks.build_def({id = "stats-circle-%d" % R, name = "Stats circle", type = "circuit", laps = 1,
			width = minf(30.0, 2.0 * (R - 4.0)), checkpoints = [], points = pts})
	return _circles[R]


static func pad() -> BuiltTrack:
	if _pad == null:
		var pts: Array = []
		for k in 400:
			var a: float = (k / 400.0) * PI * 2.0
			pts.append([3000.0 * sin(a), 3000.0 * cos(a) - 3000.0, 0])
		_pad = Tracks.build_def({id = "stats-pad", name = "Stats pad", type = "circuit", laps = 1, width = 1200,
			checkpoints = [], points = pts})
	return _pad


## Keep a car going straight down the stats road.
static func keep_straight(car: Car, ctrl: Car.Controls) -> Car.Controls:
	ctrl.steer = maxf(-1.0, minf(1.0, -car.lat * 0.05 - car.yaw * 2.0))
	return ctrl


## Full throttle from a standstill, with or without nitro; `refill` keeps the tank full.
static func run(spec: CarSpec, nitro: bool = false, refill: bool = false, seconds: float = 150.0) -> Dictionary:
	var tr: BuiltTrack = road()
	var car := Car.new(tr, 3, spec)
	var ctrl := Car.Controls.new(0.0, 1.0, false, 1.0 if nitro else 0.0)
	var out: Dictionary = {t100 = NAN, t200 = NAN, top = 0.0, tankTime = NAN, tankDist = NAN}
	var z0: float = car.z
	for s in range(1, int(seconds * 60) + 1):
		if refill:
			car.add_nitro(1.0)
		car.step(tr, keep_straight(car, ctrl), DT)
		var t: float = s * DT
		var kmh: float = car.speed * KMH
		if is_nan(out.t100) and kmh >= 100.0:
			out.t100 = t
		if is_nan(out.t200) and kmh >= 200.0:
			out.t200 = t
		if nitro and not refill and is_nan(out.tankTime) and car.nitro <= 0.0:
			out.tankTime = t
			out.tankDist = car.z - z0
		if kmh > out.top:
			out.top = kmh
		if car.idx > tr.count - 30:
			break
	return out


static func brake100(spec: CarSpec) -> float:
	var tr: BuiltTrack = road()
	var car := Car.new(tr, 10, spec)
	car.place(tr, 10, {x = tr.px[10], z = tr.pz[10], yaw = 0.0, vx = 0.0, vz = 100.0 / KMH, idx = 10, laps = 0})
	var z0: float = car.z
	var ctrl := Car.Controls.new(0.0, -1.0, false)
	var s: int = 0
	while s < 60 * 20 and car.forward_speed > 0.05:
		car.step(tr, ctrl, DT)
		s += 1
	return car.z - z0


## Fastest steady speed round a circle of radius R (m/s), as lateral g.
static func skidpad(spec: CarSpec, R: float) -> float:
	var tr: BuiltTrack = circle(R)
	var best: float = 0.0
	var vT: float = sqrt(6.0 * R)
	while vT < minf(95.0, sqrt(30.0 * R)):
		var car := Car.new(tr, 0, spec)
		car.place(tr, 0, {x = tr.px[0], z = tr.pz[0], yaw = atan2(tr.tx[0], tr.tz[0]), vx = tr.tx[0] * vT * 0.7, vz = tr.tz[0] * vT * 0.7, idx = 0, laps = 0})
		var ctrl := Car.Controls.new()
		var lat_max: float = 0.0
		var us: float = 0.0
		var n: int = 0
		var wall: bool = false
		var s: int = 0
		while s < 60 * 10 and not wall:
			var look: int = maxi(2, JsMath.roundi((4.0 + car.speed * 0.3) / tr.seg_len))
			var i: int = (car.idx + look) % tr.N
			var gx: float = tr.px[i] - car.x
			var gz: float = tr.pz[i] - car.z
			var fx: float = sin(car.yaw)
			var fz: float = cos(car.yaw)
			ctrl.steer = maxf(-1.0, minf(1.0, 3.0 * atan2(gx * fz - gz * fx, gx * fx + gz * fz)))
			ctrl.throttle = maxf(-1.0, minf(1.0, (minf(vT, 0.7 * vT + s * DT * 2.0) - car.forward_speed) * 0.8))
			car.step(tr, ctrl, DT)
			wall = car.hit_wall
			if s > 60 * 6:
				lat_max = maxf(lat_max, absf(car.lat))
				us += car.speed
				n += 1
			s += 1
		var v: float = us / n if n > 0 else NAN
		if not wall and lat_max < 4.0 and v > vT - 1.0:
			best = maxf(best, v)
		vT *= 1.01
	return (best * best) / R / 9.81


## One keyboard drift: the longest stretch (s) above 12° of body slip, 0 after a spin.
static func drift_run(spec: CarSpec, kmh: float, hb_t: float, beta_t: float, band: float, lift: bool) -> float:
	var tr: BuiltTrack = pad()
	var v: float = kmh / KMH
	var y0: float = atan2(tr.tx[0], tr.tz[0])
	var car := Car.new(tr, 0, spec)
	car.place(tr, 0, {x = tr.px[0], z = tr.pz[0], yaw = y0, vx = sin(y0) * v, vz = cos(y0) * v, idx = 0, laps = 0})
	var ctrl := Car.Controls.new()
	var held: float = 0.0
	var longest: float = 0.0
	for s in 60 * 8:
		var t: float = s * DT
		var beta: float = (atan2(-car.side_speed, maxf(0.5, car.forward_speed)) * 180.0) / PI # + = nose left of travel
		var target: float
		if t < hb_t:
			target = 1.0
			ctrl.handbrake = true
			ctrl.throttle = 0.0
		else:
			target = -1.0 if beta > beta_t + band else (1.0 if beta < beta_t - band else 0.0)
			ctrl.handbrake = false
			ctrl.throttle = 0.0 if lift and beta > beta_t + 15.0 else 1.0
		var rate: float = KEYS.ret if target == 0.0 or target * ctrl.steer < 0.0 \
			else KEYS.rateSlow + (KEYS.rateFast - KEYS.rateSlow) * minf(1.0, car.speed / KEYS.fastSpeed)
		ctrl.steer += JsMath.sign(target - ctrl.steer) * minf(absf(target - ctrl.steer), rate * DT)
		car.step(tr, ctrl, DT)
		var ab: float = absf(beta)
		if ab > 90.0:
			return 0.0 # spun
		if ab > 12.0 and car.speed > 6.0:
			held += DT
			if held > longest:
				longest = held
		else:
			held = 0.0
	return longest


## Median keyboard drift (s) over the grid of speeds, handbrake pulls, target angles and throttle styles.
static func drift(spec: CarSpec) -> float:
	var all: Array[float] = []
	for kmh: float in [60.0, 80.0, 100.0, 130.0]:
		for hb_t: float in [0.2, 0.35, 0.5, 0.8]:
			for beta_t: float in [15.0, 25.0, 35.0]:
				for band: float in [3.0, 8.0]:
					for lift: bool in [false, true]:
						all.append(drift_run(spec, kmh, hb_t, beta_t, band, lift))
	all.sort()
	return all[all.size() >> 1]


static func r2(x: float) -> float:
	return JsMath.round(x * 100.0) / 100.0


static func r1(x: float) -> float:
	return JsMath.round(x * 10.0) / 10.0


## Measure one car spec: the stats Dictionary stored in sim/cars.gd (JS key names).
static func measure_car(spec: CarSpec) -> Dictionary:
	var plain: Dictionary = run(spec)
	var boost: Dictionary = run(spec, true, false, 30.0)
	var flat: Dictionary = run(spec, true, true, 150.0)
	return {
		mass = spec.mass,
		accel100 = r2(plain.t100), accel200 = r2(plain.t200), top = r1(plain.top),
		accel200n = r2(boost.t200), topNitro = r1(flat.top),
		tankTime = r2(boost.tankTime), tankDist = JsMath.round(boost.tankDist),
		brake100 = r1(brake100(spec)),
		grip = r2(skidpad(spec, 30.0)), gripFast = r2(skidpad(spec, 120.0)),
		drift = r2(drift(spec)),
	}


## Stats that differ from a fresh measurement by more than TOLERANCE: [{key, stored, measured}].
static func stats_mismatch(stored: Dictionary, measured: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for k: String in STAT_KEYS:
		var a: float = float(stored.get(k, NAN))
		if not (absf(a - float(measured[k])) <= float(TOLERANCE[k]) + 1e-9):
			out.append({key = k, stored = stored.get(k), measured = measured[k]})
	return out


## `stats = {mass = 1250, accel100 = 2.7, ...}` as written in sim/cars.gd.
static func stats_line(m: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k: String in STAT_KEYS:
		parts.append("%s = %s" % [k, JsMath.num_to_js(float(m[k]))])
	return "stats = {%s}," % ", ".join(parts)


static func table_row(id: String, m: Dictionary) -> String:
	return "%-9s %4d  %s s %5s s %s  %5s s %s  %s s %4d m  %s m  %s  %s  %s s" % [id, int(m.mass),
		JsMath.to_fixed(m.accel100, 2), JsMath.to_fixed(m.accel200, 2), JsMath.to_fixed(m.top, 1),
		JsMath.to_fixed(m.accel200n, 2), JsMath.to_fixed(m.topNitro, 1), JsMath.to_fixed(m.tankTime, 2), int(m.tankDist),
		JsMath.to_fixed(m.brake100, 1), JsMath.to_fixed(m.grip, 2), JsMath.to_fixed(m.gripFast, 2), JsMath.to_fixed(m.drift, 2)]


var _ids: PackedStringArray = []
var _measured: Dictionary = {}
var _next: int = 0
var _mutex: Mutex = Mutex.new()


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var check: bool = args.has("--check")
	var threads: int = mini(4, OS.get_processor_count())
	for a: String in args:
		if a.begins_with("--jobs="):
			threads = clampi(a.substr(7).to_int(), 1, 16)
	var t0: int = Time.get_ticks_msec()
	_ids = Cars.ids()
	prepare()
	threads = mini(threads, _ids.size())
	if threads <= 1:
		_work()
	else:
		var pool: Array[Thread] = []
		for k in threads:
			var th := Thread.new()
			th.start(_work)
			pool.append(th)
		for th in pool:
			th.wait_to_finish()
	var bad: int = 0
	var lines: PackedStringArray = []
	print("car       kg    0-100  0-200   top    0-200N  topN    tank       100-0   grip  fast  drift")
	for id: String in _ids:
		var m: Dictionary = _measured[id]
		print(table_row(id, m))
		lines.append("\t\t%s  # %s" % [stats_line(m), id])
		var off: Array[Dictionary] = stats_mismatch(Cars.get_car(id).stats, m)
		if off.size():
			bad += 1
			var what: PackedStringArray = []
			for o: Dictionary in off:
				what.append("%s %s -> %s" % [o.key, o.stored, JsMath.num_to_js(float(o.measured))])
			print("   sim/cars.gd differs: ", ", ".join(what))
	print("\n%.1f s on %d thread%s" % [(Time.get_ticks_msec() - t0) / 1000.0, threads, "s" if threads > 1 else ""])
	if not check:
		print("\nstats lines for sim/cars.gd:\n%s" % "\n".join(lines))
	else:
		print("%d car(s) OUT OF DATE in sim/cars.gd: run tools/car_stats.gd and paste the stats" % bad if bad else "sim/cars.gd stats are up to date")
	quit(1 if check and bad else 0)


func _work() -> void:
	while true:
		_mutex.lock()
		var j: int = _next
		_next += 1
		_mutex.unlock()
		if j >= _ids.size():
			return
		var m: Dictionary = measure_car(Cars.spec(_ids[j]))
		_mutex.lock()
		_measured[_ids[j]] = m
		_mutex.unlock()
