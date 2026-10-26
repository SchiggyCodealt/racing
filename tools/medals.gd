extends SceneTree
## medals.gd: computes the medal times of every track for every car and writes
## data/medals.json (a port of web/tools/medals.mjs; read by sim/medals.gd).
## ------------------------------------------------------------------
##   godot --headless --path <copy> --script res://tools/medals.gd [-- options]
##     (no option)      run the sweep, print a table, write data/medals.json
##     --check          run the sweep and compare with data/medals.json; writes nothing,
##                      exits 1 when it is out of date
##     --jobs=N         sweep on N threads (default: one per CPU core, at most 4);
##                      the result is the same whatever N is
##     --out=/abs/path  write there instead of res://data/medals.json
##     --js=/abs/path   also compare with the web game's medal times (a JSON dump of
##                      web/src/tracks/medals.js MEDALS, see tools/parity/dump_medals.mjs)
##     --tracks=a,b     --cars=a,b   only these (for quick checks; nothing is written)
## Re-run it after changing the car physics (and Car.PHYSICS_VERSION), a car's spec
## (sim/cars.gd), the scoring rules (sim/score.gd; bump SCORE_RULES), a track or its laps.
##
## The race is the one the player drives in Drive, with each car: all the laps of a
## circuit, a sprint start to finish, standing start at GO with a full tank, 60 Hz:
## car.step, race.update, then the style score whose banked points refill the tank.
## Author time: the best finish of the medal autopilot (Autopilot.medal) over
## Autopilot.GRID_A_LAT × GRID_LOOK_K (the first in grid order on a tie, lookK outer),
## to the millisecond the HUD shows; gold / silver / bronze = author × Medals.FACTORS,
## rounded up to a whole second. A run that is stuck for 3 s or takes over 15 min
## doesn't count.

const METHOD: String = "author: fastest finish of the look-ahead autopilot in tools/medals.gd over aLat " + \
	"14/16/18/20/22/24/26/28/32/40 m/s² × lookK 0.35/0.55/0.75/1/1.3 (braking 11 m/s², aim at most 80 m ahead), " + \
	"nitro at full throttle with |steer| < 0.25, refilled by the style score; wall touches allowed; " + \
	"gold/silver/bronze = author × 1.06/1.2/1.5, rounded up to a whole second"

var _jobs: Array[Dictionary] = []
var _next: int = 0
var _results: Dictionary = {}
var _mutex: Mutex = Mutex.new()


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var check: bool = args.has("--check")
	var threads: int = mini(4, OS.get_processor_count())
	var out_path: String = "res://data/medals.json"
	var js_path: String = ""
	var only_tracks: PackedStringArray = []
	var only_cars: PackedStringArray = []
	for a: String in args:
		if a.begins_with("--jobs="):
			threads = clampi(a.substr(7).to_int(), 1, 16)
		elif a.begins_with("--out="):
			out_path = a.substr(6)
		elif a.begins_with("--js="):
			js_path = a.substr(5)
		elif a.begins_with("--tracks="):
			only_tracks = a.substr(9).split(",")
		elif a.begins_with("--cars="):
			only_cars = a.substr(7).split(",")
	var partial: bool = only_tracks.size() > 0 or only_cars.size() > 0
	var t0: int = Time.get_ticks_msec()
	var track_ids: PackedStringArray = only_tracks if only_tracks.size() else Tracks.ids()
	var car_ids: PackedStringArray = only_cars if only_cars.size() else Cars.ids()
	print("physics v%d, scoring rules v%d; %d cars × %d tracks × %d autopilot settings, nitro on the straights with the score's refills; %d thread%s\n" % [
		Car.PHYSICS_VERSION, ScoreState.SCORE_RULES, car_ids.size(), track_ids.size(),
		Autopilot.GRID_A_LAT.size() * Autopilot.GRID_LOOK_K.size(), threads, "s" if threads > 1 else ""])

	# every track × car, longest races first (so the threads finish together); tracks are built
	# here, on the main thread, so the sweep threads only read them
	for id: String in track_ids:
		var t: BuiltTrack = Tracks.build(id)
		for c: String in car_ids:
			_jobs.append({track = id, car = c, km = t.race_length()})
	_jobs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.km > b.km)
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

	print("%-16s %-7s %-8s finished  author     (setting, wall steps)       nitro burned / refilled   gold      silver    bronze" % ["track", "race", "car"])
	var tracks: Dictionary = {}
	var missing: bool = false
	for id: String in track_ids:
		var t: BuiltTrack = Tracks.build(id)
		var cars: Dictionary = {}
		var k: int = 0
		for c: String in car_ids:
			var r: Dictionary = _results[id + " " + c]
			var head: String = "%-16s %-7s %-8s" % ["" if k else id, "" if k else ("%d laps" % t.laps if t.closed else "sprint"), c]
			k += 1
			if r.entry.is_empty():
				print(head, " no run finished")
				missing = true
				continue
			var e: Dictionary = r.entry
			cars[c] = e
			print("%s %2d/%d    %-37s%5s / %4s tanks      %s  %s  %s" % [head, r.finished, r.runs,
				"%s  (aLat %s, lookK %s, %d)" % [RaceState.format_time(e.author), JsMath.num_to_js(e.run.aLat), JsMath.num_to_js(e.run.lookK), e.run.wallSteps],
				JsMath.to_fixed(r.best.burned, 2), JsMath.to_fixed(r.best.refilled, 2),
				RaceState.format_time(e.gold), RaceState.format_time(e.silver), RaceState.format_time(e.bronze)])
		tracks[id] = {name = t.name, laps = t.laps if t.closed else 1, sig = t.signature(), cars = cars}
	print("\n%.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))

	var code: int = 0
	if js_path != "":
		code = maxi(code, _compare_js(tracks, js_path))
	var text: String = medals_json(tracks)
	if partial:
		print("(--tracks / --cars: a partial sweep; nothing written)")
	elif missing:
		print("a track has no finishing run with some car: medals.json NOT written")
		code = 1
	elif check:
		var old: String = FileAccess.get_file_as_string(out_path)
		if old == text:
			print("data/medals.json is up to date")
		else:
			print("data/medals.json is OUT OF DATE: run tools/medals.gd")
			code = 1
	else:
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(text)
		f.close()
		print("wrote ", out_path)
	quit(code)


## A sweep thread (or the main thread): takes jobs until none are left.
func _work() -> void:
	while true:
		_mutex.lock()
		var j: int = _next
		_next += 1
		_mutex.unlock()
		if j >= _jobs.size():
			return
		var job: Dictionary = _jobs[j]
		var r: Dictionary = car_medals(Tracks.build(job.track), job.car)
		_mutex.lock()
		_results[job.track + " " + job.car] = r
		_mutex.unlock()


## Sweep one track with one car: {runs, finished, entry (for medals.json; {} when no run
## finished), best (the winning run)}.
static func car_medals(track: BuiltTrack, car_id: String) -> Dictionary:
	var best: Dictionary = {}
	var finished: int = 0
	var runs: int = 0
	for look_k: float in Autopilot.GRID_LOOK_K:
		for a_lat: float in Autopilot.GRID_A_LAT:
			var r: Dictionary = Autopilot.drive_race(track, a_lat, look_k, car_id)
			runs += 1
			if not r.finished:
				continue
			finished += 1
			if best.is_empty() or r.steps < best.steps:
				best = r
				best.a_lat = a_lat
				best.look_k = look_k
	if best.is_empty():
		return {runs = runs, finished = finished, entry = {}, best = best}
	var author: float = JsMath.round(best.time * 1000.0) / 1000.0 # what the HUD shows for that run
	var entry: Dictionary = Medals.medal_set(author)
	entry.run = {aLat = best.a_lat, lookK = best.look_k, steps = best.steps, wallSteps = best.wall}
	return {runs = runs, finished = finished, entry = entry, best = best}


## data/medals.json, one car per line (numbers written the shortest way, as JS would).
static func medals_json(tracks: Dictionary) -> String:
	var n := func(v: Variant) -> String: return JsMath.num_to_js(float(v))
	var lines: PackedStringArray = []
	lines.append("{")
	lines.append("\"generated\": \"by tools/medals.gd: don't edit by hand; re-run it after changing the physics, a car, the scoring rules, a track or its laps\",")
	lines.append("\"physics\": %d, \"scoreRules\": %d," % [Car.PHYSICS_VERSION, ScoreState.SCORE_RULES])
	lines.append("\"method\": %s," % JSON.stringify(METHOD))
	var factors: PackedStringArray = []
	for m: String in Medals.ORDER.slice(1):
		factors.append("\"%s\": %s" % [m, n.call(Medals.FACTORS[m])])
	lines.append("\"factors\": {%s}," % ", ".join(factors))
	lines.append("\"tracks\": {")
	var ids: Array = tracks.keys()
	for ti in ids.size():
		var id: String = ids[ti]
		var t: Dictionary = tracks[id]
		lines.append("  \"%s\": {\"name\": %s, \"laps\": %d, \"sig\": \"%s\", \"cars\": {" % [id, JSON.stringify(t.name), t.laps, t.sig])
		var cids: Array = (t.cars as Dictionary).keys()
		for ci in cids.size():
			var e: Dictionary = t.cars[cids[ci]]
			lines.append("    \"%s\": {\"author\": %s, \"gold\": %s, \"silver\": %s, \"bronze\": %s, \"run\": {\"aLat\": %s, \"lookK\": %s, \"steps\": %d, \"wallSteps\": %d}}%s" % [
				cids[ci], n.call(e.author), n.call(e.gold), n.call(e.silver), n.call(e.bronze),
				n.call(e.run.aLat), n.call(e.run.lookK), e.run.steps, e.run.wallSteps, "," if ci < cids.size() - 1 else ""])
		lines.append("  }}%s" % ("," if ti < ids.size() - 1 else ""))
	lines.append("}")
	lines.append("}")
	return "\n".join(lines) + "\n"


## Compares the sweep with the web game's medal times (JSON dump of MEDALS). Returns 1 when any differ.
static func _compare_js(tracks: Dictionary, path: String) -> int:
	var js: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (js is Dictionary):
		print("cannot read ", path)
		return 1
	var same: int = 0
	var total: int = 0
	for id: String in tracks:
		var jt: Dictionary = js.get(id, {})
		for c: String in tracks[id].cars:
			total += 1
			var e: Dictionary = tracks[id].cars[c]
			var je: Dictionary = (jt.get("cars", {}) as Dictionary).get(c, {})
			var keys: Array = ["author", "gold", "silver", "bronze"]
			var ok: bool = not je.is_empty() and jt.get("sig") == tracks[id].sig and jt.get("laps") == tracks[id].laps
			for k: String in keys:
				ok = ok and je.has(k) and float(je[k]) == float(e[k])
			ok = ok and je.has("run") and float(je.run.aLat) == float(e.run.aLat) and float(je.run.lookK) == float(e.run.lookK) and \
				int(je.run.steps) == int(e.run.steps) and int(je.run.wallSteps) == int(e.run.wallSteps)
			if ok:
				same += 1
			else:
				print("differs from the web game: %s %s: gd %s, js %s" % [id, c, e, je])
	print("compared with the web game's medals.js: %d of %d track × car entries identical (times, winning setting, steps, wall steps)" % [same, total])
	return 0 if same == total else 1
