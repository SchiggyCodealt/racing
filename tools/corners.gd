extends SceneTree
## corners.gd: the tight corners of the tracks and how the medal autopilot takes them (v6.6.0:
## made to rework the tightest corners of the old tracks and to measure the result).
## ------------------------------------------------------------------
##   godot --headless --path . --script res://tools/corners.gd [-- options]
##     --tracks=a,b          only these tracks (default: all)
##     --cars=a,b            only these cars (default: all six)
##     --max-r=40            list the corners whose tightest radius is under this (m)
##     --tracks-json=/path   read the track definitions from that file instead of data/tracks.json
##                           (e.g. an older one: git show <commit>:data/tracks.json > /tmp/old.json)
##     --medals=/path        the author runs' settings from that file (default data/medals.json)
##     --setting=20,0.75     drive every car with this aLat, lookK instead of its author run
##     --sweep               also drive all 50 settings of the medal sweep with every car and
##                           report each corner's wall contacts averaged over them
##     --jobs=3              threads (default 3)
##     --json=/path          also write every number as JSON
##
## A corner is a stretch of road that keeps turning one way with a radius under 150 m (the
## curvature over ±2 samples, as tools/gen_tracks.gd measures it). For each corner tighter
## than --max-r: where it is, how far it turns, its tightest radius, the road width and
## banking there, and for each car its author run (the medal autopilot with the setting
## stored in medals.json, nitro and all: the run that set the author time) through it: the
## lowest speed (the mean of each lap's lowest, km/h) and the wall contacts per lap (steps
## touching a wall / hits, contacts that start) from 10 m before the corner to 30 m after it.
## With --sweep, the last columns are the same contacts per lap averaged over the sweep's
## 50 settings × the cars (runs that finish), and the share of those laps that hit a wall there.

const BEND_R: float = 150.0 # m: tighter than this counts as turning
const BEFORE: float = 10.0 # m before a corner that count as its own
const AFTER: float = 30.0 # m after it (cars run wide on the exit)
const DT: float = 1.0 / 60.0

var _opt: Dictionary = {}
var _jobs: Array[Dictionary] = []
var _next: int = 0
var _mutex: Mutex = Mutex.new()


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			_opt[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
		elif a.begins_with("--"):
			_opt[a.substr(2)] = true
	var max_r: float = float(_opt.get("max-r", "40"))
	var defs: Array[Dictionary] = []
	if _opt.has("tracks-json"):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(_opt["tracks-json"])))
		if not (data is Array):
			print("cannot read %s" % _opt["tracks-json"])
			quit(1)
			return
		for d: Variant in data:
			defs.append(d)
	else:
		defs = Tracks.defs()
	var only: PackedStringArray = String(_opt.get("tracks", "")).split(",", false)
	var cars: PackedStringArray = String(_opt.get("cars", "")).split(",", false)
	if cars.is_empty():
		cars = Cars.ids()
	var medals: Dictionary = {}
	var md: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(_opt.get("medals", "res://data/medals.json"))))
	if md is Dictionary:
		medals = (md as Dictionary).get("tracks", {})
	var setting: PackedStringArray = String(_opt.get("setting", "")).split(",", false)
	# the tracks (built here, read-only in the threads) and the runs to drive
	var tracks: Array[Dictionary] = []
	for d in defs:
		if not only.is_empty() and not only.has(String(d.id)):
			continue
		var t: BuiltTrack = Tracks.build_def(d)
		var cs: Array[Dictionary] = corners(t, max_r)
		var tk: Dictionary = {t = t, corners = cs, zone = zones(t, cs), runs = {}, sweep = []}
		tracks.append(tk)
		for car_id in cars:
			var run: Dictionary = (((medals.get(t.id, {}) as Dictionary).get("cars", {}) as Dictionary).get(car_id, {}) as Dictionary).get("run", {})
			var a_lat: float = 20.0
			var look_k: float = 0.75
			if setting.size() == 2:
				a_lat = float(setting[0])
				look_k = float(setting[1])
			elif not run.is_empty():
				a_lat = float(run.aLat)
				look_k = float(run.lookK)
			_jobs.append({tk = tk, car = car_id, a_lat = a_lat, look_k = look_k, sweep = false})
			if _opt.has("sweep"):
				for k: float in Autopilot.GRID_LOOK_K:
					for a: float in Autopilot.GRID_A_LAT:
						_jobs.append({tk = tk, car = car_id, a_lat = a, look_k = k, sweep = true})
	var threads: int = clampi(int(_opt.get("jobs", "3")), 1, 16)
	var pool: Array[Thread] = []
	for k in threads:
		var th := Thread.new()
		th.start(_work)
		pool.append(th)
	for th in pool:
		th.wait_to_finish()
	var out: Dictionary = {}
	for tk in tracks:
		var r: Dictionary = report(tk, cars)
		out[(tk.t as BuiltTrack).id] = r
		_print(tk.t, r, cars)
	if _opt.has("json"):
		var f := FileAccess.open(String(_opt["json"]), FileAccess.WRITE)
		f.store_string(JSON.stringify(out, "  ", false))
		f.close()
		print("wrote ", _opt["json"])
	quit(0)


func _work() -> void:
	while true:
		_mutex.lock()
		var j: int = _next
		_next += 1
		_mutex.unlock()
		if j >= _jobs.size():
			return
		var job: Dictionary = _jobs[j]
		var tk: Dictionary = job.tk
		var r: Dictionary = drive(tk.t, tk.zone, (tk.corners as Array).size(), job.car, job.a_lat, job.look_k)
		_mutex.lock()
		if job.sweep:
			(tk.sweep as Array).append(r)
		else:
			tk.runs[job.car] = r
		_mutex.unlock()


## The corners of `t` tighter than `max_r`: [{from, to, apex (samples), at (m), turn (°), r (m),
## width (m at the apex), min_width, bank (° at the apex)}], in driving order.
static func corners(t: BuiltTrack, max_r: float) -> Array[Dictionary]:
	var n: int = t.N if t.closed else t.count
	var kappa := PackedFloat64Array()
	kappa.resize(n)
	for i in n:
		var a: int = i - 2 if t.closed else maxi(0, i - 2)
		var b: int = i + 2 if t.closed else mini(t.count - 1, i + 2)
		var dh: float = t.heading(t.wrap(b)) - t.heading(t.wrap(a))
		kappa[i] = atan2(sin(dh), cos(dh)) / ((b - a) * t.seg_len)
	var sgn := PackedInt32Array()
	sgn.resize(n)
	for i in n:
		sgn[i] = 0 if absf(kappa[i]) < 1.0 / BEND_R else (1 if kappa[i] > 0.0 else -1)
	# on a circuit, start the scan where the road is straight so no corner is cut in two
	var s0: int = 0
	if t.closed:
		while s0 < n and sgn[s0] != 0:
			s0 += 1
	var out: Array[Dictionary] = []
	var k: int = 0
	while k < n:
		var i: int = (s0 + k) % n if t.closed else k
		if sgn[i] == 0:
			k += 1
			continue
		var j: int = k
		while j + 1 < n and sgn[((s0 + j + 1) % n) if t.closed else j + 1] == sgn[i]:
			j += 1
		var best: int = i
		var turn: float = 0.0
		var min_w: float = INF
		for q in range(k, j + 1):
			var p: int = (s0 + q) % n if t.closed else q
			if absf(kappa[p]) > absf(kappa[best]):
				best = p
			min_w = minf(min_w, 2.0 * t.hw[p])
			var p1: int = t.wrap(p + 1) if t.closed else mini(p + 1, t.count - 1)
			var dh: float = t.heading(p1) - t.heading(p)
			turn += atan2(sin(dh), cos(dh))
		var r: float = 1.0 / absf(kappa[best])
		if r < max_r:
			out.append({from = i, to = (s0 + j) % n if t.closed else j, apex = best, at = JsMath.roundi(i * t.seg_len),
				turn = turn / (PI / 180.0), r = r, width = 2.0 * t.hw[best], min_width = min_w,
				bank = absf(t.bank[best]) / (PI / 180.0)})
		k = j + 1
	return out


## Which corner every sample belongs to (-1: none): from BEFORE m ahead of it to AFTER m past it
## (an exit running into the next corner's approach is the next corner's).
static func zones(t: BuiltTrack, cs: Array[Dictionary]) -> PackedInt32Array:
	var n: int = t.N if t.closed else t.count
	var zone := PackedInt32Array()
	zone.resize(n)
	zone.fill(-1)
	var before: int = JsMath.roundi(BEFORE / t.seg_len)
	var after: int = JsMath.roundi(AFTER / t.seg_len)
	for c in cs.size():
		var a: int = int(cs[c].from) - before
		var len_: int = posmod(int(cs[c].to) - int(cs[c].from), n) + before + after
		for q in len_ + 1:
			var p: int = posmod(a + q, n) if t.closed else clampi(a + q, 0, n - 1)
			if zone[p] == -1 or q <= before:
				zone[p] = c
	return zone


## One race with the medal autopilot (as Autopilot.drive_race: nitro, the score's refills) with
## the corners' speeds and wall contacts: {finished, time, setting, wall_steps, wall_hits (per lap,
## whole track), min_kmh [per corner], steps [per corner, per lap], hits [per corner, per lap],
## hit_laps [per corner: laps with a hit there]}.
static func drive(t: BuiltTrack, zone: PackedInt32Array, nc: int, car_id: String, a_lat: float, look_k: float) -> Dictionary:
	var n: int = zone.size()
	var laps: int = t.laps if t.closed else 1
	var car := Car.new(t, -1, Cars.spec(car_id))
	var race := RaceState.new(t)
	var pilot := Autopilot.medal(t, a_lat, look_k, true, Autopilot.DECEL, car.spec)
	var score := ScoreState.new(t, true)
	var lap_min := PackedFloat64Array() # [lap * nc + corner] lowest speed
	lap_min.resize(laps * nc)
	lap_min.fill(INF)
	var lap_hit := PackedInt32Array() # [lap * nc + corner] hits
	lap_hit.resize(laps * nc)
	var steps := PackedInt32Array()
	steps.resize(nc)
	var all_steps: int = 0
	var all_hits: int = 0
	var was: bool = false
	var step: int = 0
	var best: float = car.prog
	var gained: int = 0
	while not race.finished and step < Autopilot.MAX_STEPS and step - gained <= Autopilot.STUCK_STEPS:
		car.step(t, pilot.drive(car), DT)
		race.update(car, DT)
		score.update(car, race, DT)
		step += 1
		if car.prog > best + 3.0:
			best = car.prog
			gained = step
		var z: int = zone[clampi(car.idx, 0, n - 1)] if race.time > 0.0 else -1
		var l: int = clampi(race.lap() - 1, 0, laps - 1)
		if z >= 0:
			lap_min[l * nc + z] = minf(lap_min[l * nc + z], car.speed)
		if car.hit_wall:
			all_steps += 1
			if z >= 0:
				steps[z] += 1
			if not was:
				all_hits += 1
				if z >= 0:
					lap_hit[l * nc + z] += 1
		was = car.hit_wall
	var mins: Array[float] = []
	var st: Array[float] = []
	var ht: Array[float] = []
	var hl: Array[int] = []
	for c in nc:
		var sum: float = 0.0
		var cnt: int = 0
		var h: int = 0
		var hlaps: int = 0
		for l in laps:
			var v: float = lap_min[l * nc + c]
			if is_finite(v):
				sum += v
				cnt += 1
			h += lap_hit[l * nc + c]
			hlaps += 1 if lap_hit[l * nc + c] > 0 else 0
		mins.append(sum / maxi(1, cnt) * 3.6)
		st.append(float(steps[c]) / laps)
		ht.append(float(h) / laps)
		hl.append(hlaps)
	return {finished = race.finished, time = race.finish_time if race.finished else -1.0, setting = [a_lat, look_k],
		wall_steps = float(all_steps) / laps, wall_hits = float(all_hits) / laps, min_kmh = mins, steps = st, hits = ht, hit_laps = hl}


## A track's numbers: {sig, laps, length, corners, cars: {car: drive()}, sweep: {runs, finished,
## steps [per corner, per lap, mean], hits [...], hit_share [share of laps with a hit there],
## min_kmh [mean]} (sweep only with --sweep)}.
static func report(tk: Dictionary, cars: PackedStringArray) -> Dictionary:
	var t: BuiltTrack = tk.t
	var nc: int = (tk.corners as Array).size()
	var laps: int = t.laps if t.closed else 1
	var res: Dictionary = {sig = t.signature(), laps = laps, length = t.length, corners = tk.corners, cars = {}}
	for c: String in cars:
		res.cars[c] = tk.runs[c]
	var sw: Array = tk.sweep
	if not sw.is_empty():
		var fin: int = 0
		var steps := PackedFloat64Array()
		var hits := PackedFloat64Array()
		var hl := PackedFloat64Array()
		var mk := PackedFloat64Array()
		for a: PackedFloat64Array in [steps, hits, hl, mk]:
			a.resize(nc)
		var wall: float = 0.0
		for r: Dictionary in sw:
			if not r.finished:
				continue
			fin += 1
			wall += float(r.wall_steps)
			for c in nc:
				steps[c] += float(r.steps[c])
				hits[c] += float(r.hits[c])
				hl[c] += float(r.hit_laps[c]) / laps
				mk[c] += float(r.min_kmh[c])
		var f: float = maxf(1.0, fin)
		var s_out: Array[float] = []
		var h_out: Array[float] = []
		var hl_out: Array[float] = []
		var mk_out: Array[float] = []
		for c in nc:
			s_out.append(steps[c] / f)
			h_out.append(hits[c] / f)
			hl_out.append(hl[c] / f)
			mk_out.append(mk[c] / f)
		res.sweep = {runs = sw.size(), finished = fin, wall_steps = wall / f, steps = s_out, hits = h_out, hit_share = hl_out, min_kmh = mk_out}
	return res


func _print(t: BuiltTrack, r: Dictionary, cars: PackedStringArray) -> void:
	print("\n%s  %s, %s  (%s)" % [t.id, t.signature(), ("%d laps of %.0f m" % [t.laps, t.length]) if t.closed else "sprint",
		("every car at aLat %s, lookK %s" % Array(String(_opt.setting).split(","))) if _opt.has("setting") else "each car's author run"])
	var head: String = "   #   at m  turn   min r  width  bank |"
	for c: String in cars:
		head += " %8s" % c
	head += " | wall steps/hits per lap"
	if r.has("sweep"):
		head += " | sweep: steps, hits, laps hit"
	print(head + "   (lowest speed in km/h)")
	var cs: Array = r.corners
	for k in cs.size():
		var c: Dictionary = cs[k]
		var line: String = "  %2d %6d %+5.0f° %5.1f m %4.1f m %3.0f° |" % [k + 1, c.at, c.turn, c.r, c.width, c.bank]
		var walls: PackedStringArray = []
		for car: String in cars:
			var e: Dictionary = r.cars[car]
			line += " %8.1f" % float(e.min_kmh[k])
			walls.append("%s/%s" % [_n(e.steps[k]), _n(e.hits[k])])
		line += " | " + " ".join(walls)
		if r.has("sweep"):
			line += " | %.1f %.2f %.0f%%" % [r.sweep.steps[k], r.sweep.hits[k], 100.0 * float(r.sweep.hit_share[k])]
		print(line)
	var tot: String = "  whole track: finish"
	for car: String in cars:
		var e: Dictionary = r.cars[car]
		tot += "  %s %s (%s/%s)" % [car, RaceState.format_time(e.time) if float(e.time) > 0.0 else "DNF", _n(e.wall_steps), _n(e.wall_hits)]
	print(tot)
	if r.has("sweep"):
		print("  sweep: %d of %d runs finished, %.1f wall steps per lap" % [r.sweep.finished, r.sweep.runs, r.sweep.wall_steps])


static func _n(v: float) -> String:
	return ("%.0f" % v) if is_equal_approx(v, roundf(v)) else ("%.1f" % v)
