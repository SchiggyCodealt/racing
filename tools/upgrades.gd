extends SceneTree
## upgrades.gd (v6.11.0; v6.16.0: ten levels; v6.21.0: the weight part): measures what the car
## upgrades (sim/upgrades.gd) do, with the real physics.
## ------------------------------------------------------------------
##   godot --headless --path <copy> --script res://tools/upgrades.gd [-- options]
##     (no option)   stats: every car stock and with each part's levels (tools/car_stats.gd's
##                   measurements of the upgraded specs), the grip on dirt and snow with the loose
##                   grip part; prints tables and the MEASURED lines for sim/upgrades.gd
##     --check       measure the engine, tyre and weight levels and compare with Upgrades.MEASURED
##                   (exits 1 when one is off by more than car_stats.gd's tolerance)
##     --parts=a,b   stats and --check for these parts only (engine, tyres, weight): the others'
##                   MEASURED lines are printed as they are stored (a new part, a new car's --cars=)
##     --laps        lap times: the medal autopilot's best race (the author time's sweep, 50
##                   settings) on --tracks=a,b (default rookie-oval, technical-trial, ramp-rally,
##                   hairpin-valley) with every car (--cars=a,b), stock, everything at level 3,
##                   each part at level 10 and everything at level 10 (--sets=stock,W10 picks
##                   some), with the wall contact and
##                   the largest body slip of the level 3 and 10 runs
##     --quick       --laps on a 10-setting grid (lookK 0.75 only) instead of 50
##     --jobs=N      threads (default: one per core, at most 4); the same numbers whatever N is
## About 15 s per measured spec on one core (stats: 35 specs a car); --laps about 1-3 s per race.

const CarStats = preload("res://tools/car_stats.gd")

## The parts with a MEASURED table: [id, the sets' letter, the index in a levels list, the stats kept].
const MEASURED_PARTS: Array = [
	["engine", "E", 0, ["top", "accel100", "accel200"]],
	["tyres", "T", 1, ["grip", "gripFast"]],
	["weight", "W", 4, ["top", "accel100", "accel200", "brake100", "grip", "gripFast"]],
]
const LOOSE_SETS: Array = [["stock", [0, 0, 0, 0, 0]], ["L3", [0, 0, 0, 3, 0]], ["L10", [0, 0, 0, 10, 0]], ["T10", [0, 10, 0, 0, 0]],
	["all3", [3, 3, 3, 3, 3]], ["all10", [10, 10, 10, 10, 10]]]
const LAP_SETS: Array = [
	["stock", [0, 0, 0, 0, 0]], ["all3", [3, 3, 3, 3, 3]], ["E10", [10, 0, 0, 0, 0]], ["T10", [0, 10, 0, 0, 0]], ["N10", [0, 0, 10, 0, 0]],
	["L10", [0, 0, 0, 10, 0]], ["W10", [0, 0, 0, 0, 10]], ["all10", [10, 10, 10, 10, 10]],
]
const SLIP_SETS: Array = ["all3", "all10"]

## The parts measured (--parts=; all of MEASURED_PARTS by default).
var _parts: PackedStringArray = ["engine", "tyres", "weight"]
var _lap_sets: PackedStringArray = []


## The level sets the stats measure: stock, then levels 1-10 of each measured part, then (all the
## parts measured) nitro 3 and 10 and everything at 3 and 10.
func _stat_sets() -> Array:
	var out: Array = [["stock", [0, 0, 0, 0, 0]]]
	for mp: Array in MEASURED_PARTS:
		if not _parts.has(mp[0]):
			continue
		for k in range(1, Upgrades.MAX_LEVEL + 1):
			var lv: Array = [0, 0, 0, 0, 0]
			lv[int(mp[2])] = k
			out.append(["%s%d" % [mp[1], k], lv])
	if _parts.size() == MEASURED_PARTS.size():
		out.append_array([["N3", [0, 0, 3, 0, 0]], ["N10", [0, 0, 10, 0, 0]], ["all3", [3, 3, 3, 3, 3]], ["all10", [10, 10, 10, 10, 10]]])
	return out

var _jobs: Array[Dictionary] = []
var _next: int = 0
var _results: Dictionary = {}
var _mutex: Mutex = Mutex.new()
var _threads: int = 4


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_threads = mini(4, OS.get_processor_count())
	var tracks: PackedStringArray = ["rookie-oval", "technical-trial", "ramp-rally", "hairpin-valley"]
	var cars: PackedStringArray = Cars.ids()
	for a: String in args:
		if a.begins_with("--jobs="):
			_threads = clampi(a.substr(7).to_int(), 1, 16)
		elif a.begins_with("--tracks="):
			tracks = a.substr(9).split(",")
		elif a.begins_with("--cars="):
			cars = a.substr(7).split(",")
		elif a.begins_with("--parts="):
			_parts = a.substr(8).split(",")
		elif a.begins_with("--sets="):
			_lap_sets = a.substr(7).split(",")
	var t0: int = Time.get_ticks_msec()
	var code: int = 0
	if args.has("--laps") or args.has("--quick"):
		_laps(tracks, cars, args.has("--quick"))
	elif args.has("--check"):
		code = _check(cars)
	else:
		_stats(cars)
	print("\n%.1f s on %d threads" % [(Time.get_ticks_msec() - t0) / 1000.0, _threads])
	quit(code)


# ---------------------------------------------------------------- jobs on threads

func _run_jobs(jobs: Array[Dictionary]) -> void:
	_jobs = jobs
	_next = 0
	_results = {}
	var pool: Array[Thread] = []
	for k in mini(_threads, jobs.size()):
		var th := Thread.new()
		th.start(_work)
		pool.append(th)
	for th in pool:
		th.wait_to_finish()


func _work() -> void:
	while true:
		_mutex.lock()
		var j: int = _next
		_next += 1
		_mutex.unlock()
		if j >= _jobs.size():
			return
		var job: Dictionary = _jobs[j]
		var r: Variant = (job.fn as Callable).call()
		_mutex.lock()
		_results[job.key] = r
		_mutex.unlock()


static func _lv(a: Array) -> PackedInt32Array:
	return PackedInt32Array(a)


# ---------------------------------------------------------------- stats

func _stats(cars: PackedStringArray) -> void:
	CarStats.surface = "asphalt"
	CarStats.prepare()
	var sets: Array = _stat_sets()
	var full: bool = _parts.size() == MEASURED_PARTS.size()
	var jobs: Array[Dictionary] = []
	for id: String in cars:
		for set: Array in sets:
			var spec: CarSpec = Upgrades.spec(id, _lv(set[1]))
			jobs.append({key = "%s|%s" % [id, set[0]], fn = CarStats.measure_car.bind(spec)})
	_run_jobs(jobs)
	var asphalt: Dictionary = _results.duplicate()
	print("on asphalt: every car stock, %s at levels 1-10%s" % [", ".join(_parts), ", nitro 3 and 10, everything 3 and 10" if full else ""])
	print("car/set     kg    0-100  0-200   top    0-200N  topN    tank       100-0   grip  fast  drift")
	for id: String in cars:
		for set: Array in sets:
			print(CarStats.table_row("%s %s" % [id.left(4), set[0]], asphalt["%s|%s" % [id, set[0]]]))
		print("")
	# the share each level adds over stock (the "3-5 % a level" check)
	print("gain over stock (%): top / 0-100 / 0-200 (time, - = quicker) for E1-E10; grip / fast for T1-T10; 0-100 / 0-200 / 100-0 (m) / grip / fast for W1-W10; tank for N3, N10; all3, all10")
	for id: String in cars:
		var s: Dictionary = asphalt["%s|stock" % id]
		var parts: PackedStringArray = []
		for k in range(1, Upgrades.MAX_LEVEL + 1):
			if not _parts.has("engine"):
				break
			var m: Dictionary = asphalt["%s|E%d" % [id, k]]
			parts.append("E%d %+.1f/%+.1f/%+.1f" % [k, _pc(m.top, s.top), _pc(m.accel100, s.accel100), _pc(m.accel200, s.accel200)])
		for k in range(1, Upgrades.MAX_LEVEL + 1):
			if not _parts.has("tyres"):
				break
			var m: Dictionary = asphalt["%s|T%d" % [id, k]]
			parts.append("T%d %+.1f/%+.1f" % [k, _pc(m.grip, s.grip), _pc(m.gripFast, s.gripFast)])
		for k in range(1, Upgrades.MAX_LEVEL + 1):
			if not _parts.has("weight"):
				break
			var m: Dictionary = asphalt["%s|W%d" % [id, k]]
			parts.append("W%d %+.1f/%+.1f/%+.1f/%+.1f/%+.1f" % [k, _pc(m.accel100, s.accel100), _pc(m.accel200, s.accel200), _pc(m.brake100, s.brake100), _pc(m.grip, s.grip), _pc(m.gripFast, s.gripFast)])
		if full:
			for n: String in ["N3", "N10"]:
				parts.append("%s tank %+.1f" % [n, _pc(asphalt["%s|%s" % [id, n]].tankTime, s.tankTime)])
			for a: String in ["all3", "all10"]:
				var a3: Dictionary = asphalt["%s|%s" % [id, a]]
				parts.append("%s top %+.1f 0-200 %+.1f grip %+.1f/%+.1f brake %+.1f drift %.2f->%.2f s" % [a, _pc(a3.top, s.top), _pc(a3.accel200, s.accel200),
					_pc(a3.grip, s.grip), _pc(a3.gripFast, s.gripFast), _pc(a3.brake100, s.brake100), float(s.drift), float(a3.drift)])
		print("%-8s %s" % [id, ", ".join(parts)])
	# dirt and snow: the skidpads with the loose grip part (and the tyres, which must not change them)
	for surface: String in (["dirt", "snow"] if full else []):
		CarStats.surface = surface
		CarStats.prepare()
		var sj: Array[Dictionary] = []
		for id: String in cars:
			for set: Array in LOOSE_SETS:
				var spec: CarSpec = Upgrades.spec(id, _lv(set[1]))
				sj.append({key = "%s|%s" % [id, set[0]], fn = func() -> Dictionary:
					return {grip = CarStats.r2(CarStats.skidpad(spec, 30.0)), gripFast = CarStats.r2(CarStats.skidpad(spec, 120.0)),
						brake100 = CarStats.r1(CarStats.brake100(spec))}})
		_run_jobs(sj)
		print("\non %s: skidpad grip 30 m / 120 m (g) and 100-0 (m): stock, loose 3 and 10, tyres 10, everything 3 and 10" % surface)
		for id: String in cars:
			var row: PackedStringArray = []
			var st: Dictionary = _results["%s|stock" % id]
			for set: Array in LOOSE_SETS:
				var m: Dictionary = _results["%s|%s" % [id, set[0]]]
				row.append("%s %.2f / %.2f / %.1f m (%+.1f %%)" % [set[0], float(m.grip), float(m.gripFast), float(m.brake100),
					_pc((float(m.grip) + float(m.gripFast)), (float(st.grip) + float(st.gripFast)))])
			print("%-8s %s" % [id, ",  ".join(row)])
	CarStats.surface = "asphalt"
	print("\nMEASURED for sim/upgrades.gd:")
	print(_measured_text(cars, asphalt))


static func _pc(a: Variant, b: Variant) -> float:
	return (float(a) / float(b) - 1.0) * 100.0


## The MEASURED table as GDScript: the parts measured now from `m`, the others as they are stored.
func _measured_text(cars: PackedStringArray, m: Dictionary) -> String:
	var lines: PackedStringArray = []
	for id: String in cars:
		var rows: PackedStringArray = []
		for mp: Array in MEASURED_PARTS:
			var cells: PackedStringArray = []
			for k in range(1, Upgrades.MAX_LEVEL + 1):
				var src: Dictionary = {}
				if _parts.has(mp[0]):
					src = m["%s|%s%d" % [id, mp[1], k]]
				else:
					var have: Array = (Upgrades.MEASURED.get(id, {}) as Dictionary).get(mp[0], [])
					src = have[k - 1] if have.size() >= k else {}
				var kv: PackedStringArray = []
				for key: String in mp[3]:
					if src.has(key):
						kv.append("%s = %s" % [key, JsMath.num_to_js(float(src[key]))])
				cells.append("{%s}" % ", ".join(kv))
			rows.append("\t\t%s = [%s]," % [mp[0], ", ".join(cells)])
		lines.append("\t%s = {\n%s\n\t}," % [id, "\n".join(rows)])
	return "const MEASURED: Dictionary = {\n%s\n}" % "\n".join(lines)


func _check(cars: PackedStringArray) -> int:
	CarStats.surface = "asphalt"
	CarStats.prepare()
	var jobs: Array[Dictionary] = []
	for id: String in cars:
		for set: Array in _stat_sets():
			if ["stock", "N3", "N10", "all3", "all10"].has(set[0]):
				continue
			var spec: CarSpec = Upgrades.spec(id, _lv(set[1]))
			jobs.append({key = "%s|%s" % [id, set[0]], fn = CarStats.measure_car.bind(spec)})
	_run_jobs(jobs)
	var off: PackedStringArray = []
	for id: String in cars:
		var stored: Dictionary = Upgrades.MEASURED.get(id, {})
		for k in range(1, Upgrades.MAX_LEVEL + 1):
			for mp: Array in MEASURED_PARTS:
				if not _parts.has(mp[0]):
					continue
				var tag: String = "%s%d" % [mp[1], k]
				var m: Dictionary = _results["%s|%s" % [id, tag]]
				var have: Dictionary = (stored.get(mp[0], [])[k - 1] if (stored.get(mp[0], []) as Array).size() >= k else {})
				for key: String in mp[3]:
					if not (absf(float(have.get(key, NAN)) - float(m[key])) <= float(CarStats.TOLERANCE[key]) + 1e-9):
						off.append("%s %s %s %s -> %s" % [id, tag, key, have.get(key), m[key]])
	print("Upgrades.MEASURED is up to date" if off.is_empty() else "OUT OF DATE (run tools/upgrades.gd and paste MEASURED):\n  " + "\n  ".join(off))
	return 0 if off.is_empty() else 1


# ---------------------------------------------------------------- lap times

## The medal autopilot's best race over the sweep grid with `spec`: {time, a_lat, look_k, wall, slip}.
static func best_race(track: BuiltTrack, car_id: String, spec: CarSpec, quick: bool) -> Dictionary:
	var best: Dictionary = {}
	for look_k: float in ([0.75] if quick else Autopilot.GRID_LOOK_K):
		for a_lat: float in Autopilot.GRID_A_LAT:
			var r: Dictionary = Autopilot.drive_race(track, a_lat, look_k, car_id, true, spec)
			if r.finished and (best.is_empty() or int(r.steps) < int(best.steps)):
				best = r
				best.a_lat = a_lat
				best.look_k = look_k
	if best.is_empty():
		return {time = NAN}
	best.slip = max_slip(track, car_id, spec, float(best.a_lat), float(best.look_k))
	return best


## The largest body slip angle (degrees, on the ground above 10 m/s) of that race: a spin shows
## as 90 or more.
static func max_slip(t: BuiltTrack, car_id: String, spec: CarSpec, a_lat: float, k: float) -> float:
	var car := Car.new(t, -1, spec)
	var race := RaceState.new(t)
	var pilot := Autopilot.medal(t, a_lat, k, true, Autopilot.DECEL, spec)
	var score := ScoreState.new(t, true)
	var worst: float = 0.0
	var steps: int = 0
	while not race.finished and steps < Autopilot.MAX_STEPS:
		car.step(t, pilot.drive(car), 1.0 / 60.0)
		race.update(car, 1.0 / 60.0)
		score.update(car, race, 1.0 / 60.0)
		steps += 1
		if car.grounded and car.speed > 10.0:
			worst = maxf(worst, absf(atan2(car.side_speed, maxf(0.5, absf(car.forward_speed)))) * 180.0 / PI)
	return worst


func _laps(tracks: PackedStringArray, cars: PackedStringArray, quick: bool) -> void:
	var built: Dictionary = {}
	for tid: String in tracks:
		built[tid] = Tracks.build(tid)
	var jobs: Array[Dictionary] = []
	var lap_sets: Array = LAP_SETS.filter(func(x: Array) -> bool: return _lap_sets.is_empty() or x[0] == "stock" or _lap_sets.has(x[0]))
	for tid: String in tracks:
		for id: String in cars:
			for set: Array in lap_sets:
				var spec: CarSpec = Upgrades.spec(id, _lv(set[1]))
				jobs.append({key = "%s|%s|%s" % [tid, id, set[0]], fn = best_race.bind(built[tid], id, spec, quick)})
	_run_jobs(jobs)
	print("the medal autopilot's best race (%s), with nitro and the style score's refills: stock, level 3 and level 10" % ("10 settings" if quick else "50 settings, as the author time"))
	for tid: String in tracks:
		var t: BuiltTrack = built[tid]
		print("\n%s (%s, %s)" % [t.name, "%d laps" % t.laps if t.closed else "sprint", Surfaces.summary(t)])
		for id: String in cars:
			var st: Dictionary = _results["%s|%s|stock" % [tid, id]]
			var row: PackedStringArray = []
			for set: Array in lap_sets:
				var r: Dictionary = _results["%s|%s|%s" % [tid, id, set[0]]]
				if set[0] == "stock":
					row.append("stock %s (wall %d, slip %.0f°)" % [RaceState.format_time(float(r.time)), int(r.get("wall", 0)), float(r.get("slip", 0.0))])
				else:
					row.append("%s %+.2f%%" % [set[0], _pc(r.time, st.time)] + (" %s (wall %d, slip %.0f°)" % [RaceState.format_time(float(r.time)), int(r.get("wall", 0)), float(r.get("slip", 0.0))] if SLIP_SETS.has(set[0]) else ""))
			var author: Dictionary = Medals.medal_times(t, id)
			print("  %-8s %s%s" % [id, ", ".join(row), "  [author %s]" % RaceState.format_time(float(author.author)) if author.has("author") else ""])
