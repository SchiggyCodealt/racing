extends SceneTree
## opponents.gd: makes the AI opponents of Race the AI (v6.5.0) and writes
## data/opponents/<car>.json (read by sim/opponents.gd).
## ------------------------------------------------------------------
##   godot --headless --path . --script res://tools/opponents.gd -- --train [options]
##       train a network for every track with every car: FleetSim, 80 cars, walls ride, one lap
##       a run, a fixed seed per track and car. From --gens on, every --every generations the
##       best network so far drives a whole race the way the game runs the opponent
##       (ai/opponent_race.gd); training stops once that race beats the gold medal (and at
##       --max-gens in any case), and the fastest race's network is kept. A retrained track
##       loses its levels: run the second step again.
##   godot --headless --path . --script res://tools/opponents.gd -- [options]
##       the levels: from Elite down to Rookie, a speed cap is searched so the race takes
##       Opponents.LEVELS pace × the car's author time, and at least Opponents.MIN_GAP × the level
##       above (within TOLERANCE); a level the network flat out doesn't beat has no cap. Each
##       level's cap and measured finish time are stored.
##   ... -- --check     re-run every stored level's race and compare the times (writes nothing;
##                      exits 1 on a difference)
## Options: --cars=a,b  --tracks=a,b (only these), --threads=N (FleetSim threads when training,
##          race threads otherwise; default 3), --gens=80 --every=20 --max-gens=300, --retrain
##          (train tracks that already have a network for the current version of the track).
## Re-run after changing the physics, a car, the sensors, the network or a track (a track whose
## signature changed has no opponents until it is trained again: --train --tracks=<id>, then
## the levels with --tracks=<id>), and after changing Opponents.LEVELS (the levels only).

const FORMAT: String = Opponents.FORMAT
const METHOD: String = "one network per track and car, trained on that track with that car (FleetSim, 80 cars, mutation 0.1, " + \
	"hidden 12, one lap a run, walls ride, seed 1000 × (car index + 1) + track index) until the best network's whole race " + \
	"beats the gold medal (checked from generation 80, every 20); each level drives it with a speed cap set so the race takes the level's pace × the author time " + \
	"(at least 1.04 × the level above; no cap where the network is not faster); times measured with ai/opponent_race.gd " + \
	"(the game's AI ghost race)"
## A level's race is accepted within this share of its target time.
const TOLERANCE: float = 0.012

var _opt: Dictionary = {}
var _jobs: Array[Dictionary] = []
var _next: int = 0
var _results: Dictionary = {}
var _mutex: Mutex = Mutex.new()


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		_opt[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var cars: PackedStringArray = String(_opt.cars).split(",") if _opt.has("cars") else Cars.ids()
	var tracks: PackedStringArray = String(_opt.tracks).split(",") if _opt.has("tracks") else Tracks.ids()
	for c: String in cars:
		if not Cars.has_car(c):
			printerr("unknown car ", c)
			quit(1)
			return
	for id: String in tracks:
		if Tracks.build(id) == null:
			printerr("unknown track ", id)
			quit(1)
			return
	var code: int = 0
	if _opt.has("train"):
		code = _train(cars, tracks)
	else:
		code = _levels(cars, tracks, _opt.has("check"))
	quit(code)


# ---------------------------------------------------------------- the files

static func file_path(car_id: String) -> String:
	return "%s/%s.json" % [Opponents.DATA_DIR, car_id]


static func read_file(car_id: String) -> Dictionary:
	var p: String = file_path(car_id)
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(p)) if FileAccess.file_exists(p) else null
	if v is Dictionary and (v as Dictionary).get("format") == FORMAT and (v as Dictionary).get("tracks") is Dictionary:
		return v
	return {format = FORMAT, car = car_id, tracks = {}}


## The file's text: the header, then one line per track in menu order (so a retrained track is a
## one-line change).
static func file_text(d: Dictionary) -> String:
	var lines: PackedStringArray = []
	lines.append("{")
	lines.append('"format": %s, "car": %s, "physics": %d,' % [JSON.stringify(FORMAT), JSON.stringify(d.car), Car.PHYSICS_VERSION])
	lines.append('"generated": "by tools/opponents.gd: don\'t edit by hand; re-run it after changing the physics, a car, the sensors, the network or a track",')
	lines.append('"method": %s,' % JSON.stringify(METHOD))
	lines.append('"tracks": {')
	var ids: PackedStringArray = []
	for id: String in Tracks.ids():
		if (d.tracks as Dictionary).has(id):
			ids.append(id)
	for id: Variant in d.tracks:
		if not ids.has(str(id)):
			ids.append(str(id))
	for k in ids.size():
		lines.append("  %s: %s%s" % [JSON.stringify(ids[k]), JSON.stringify(d.tracks[ids[k]], "", true, false), "," if k < ids.size() - 1 else ""])
	lines.append("}}")
	return "\n".join(lines) + "\n"


static func write_file(d: Dictionary) -> void:
	var f := FileAccess.open(file_path(d.car), FileAccess.WRITE)
	f.store_string(file_text(d))
	f.close()
	Opponents.reload()


static func _ms(t: float) -> float:
	return JsMath.round(t * 1000.0) / 1000.0


## A cap to 0.01 m/s as the number the file's text reads back as (k / 100.0 is the double nearest
## to k/100, as parsing "25.9" is; snappedf's 25.900000000000002 would not survive the file and
## the race would drive another line).
static func _cap(v: float) -> float:
	return roundi(v * 100.0) / 100.0


static func _fmt(t: float) -> String:
	return RaceState.format_time(t)


# ---------------------------------------------------------------- training

func _train(cars: PackedStringArray, track_ids: PackedStringArray) -> int:
	var threads: int = int(_opt.get("threads", 3))
	var gens: int = int(_opt.get("gens", 80))
	var every: int = int(_opt.get("every", 20))
	var max_gens: int = int(_opt.get("max-gens", 300))
	var t_all: int = Time.get_ticks_msec()
	for car_id: String in cars:
		var d: Dictionary = read_file(car_id)
		for id: String in track_ids:
			var t: BuiltTrack = Tracks.build(id)
			var old: Variant = (d.tracks as Dictionary).get(id)
			if old is Dictionary and JsMath.same(old.get("sig"), t.signature()) and not _opt.has("retrain"):
				print("%s %s: trained already (generation %s), skipped" % [car_id, id, str(old.get("generation"))])
				continue
			var e: Dictionary = train_one(t, car_id, gens, every, max_gens, threads)
			if e.is_empty():
				print("%s %s: NO network finished a race" % [car_id, id])
				continue
			d.tracks[id] = e
			write_file(d)
	print("training done in %.0f s" % ((Time.get_ticks_msec() - t_all) / 1000.0))
	return 0


## The seed of a track and car's training (the same run every time).
static func seed_of(car_id: String, track_id: String) -> int:
	return 1000 * (Cars.ids().find(car_id) + 1) + Tracks.ids().find(track_id)


## Train track `t`'s network with car `car_id`; the entry for the file, or {} when no network
## finished a race.
static func train_one(t: BuiltTrack, car_id: String, gens: int, every: int, max_gens: int, threads: int) -> Dictionary:
	var seed: int = seed_of(car_id, t.id)
	NeuralNetwork.rng.seed = seed
	var trainer := Trainer.new({tracks = [t], population_size = 80, mutation_rate = 0.1, hidden = [12], laps = 1, walls = "ride",
		car_id = car_id, native = true, threads = threads})
	var medals: Dictionary = Medals.medal_times(t, car_id)
	var gold: float = float(medals.get("gold", INF))
	var t0: int = Time.get_ticks_msec()
	var best: Dictionary = {}
	var evaluated: float = -INF
	var next_check: int = gens
	var line: PackedStringArray = []
	while true:
		while trainer.generation < next_check:
			trainer.step_many(1200)
		if trainer.best_fitness > evaluated:
			evaluated = trainer.best_fitness
			var file: Dictionary = trainer.export_best()
			var r: Dictionary = OpponentRace.run(Trainer.parse_network_file(file).net, t, car_id)
			line.append("gen %d %s" % [trainer.generation, _fmt(r.time) if r.finished else "dnf"])
			if r.finished and (best.is_empty() or r.time < best.time):
				best = {time = r.time, file = file, gen = trainer.generation, respawns = r.respawns}
		if trainer.generation >= max_gens or (not best.is_empty() and best.time <= gold):
			break
		next_check += every
	var secs: float = (Time.get_ticks_msec() - t0) / 1000.0
	print("%-8s %-16s %s | kept %s (gold %s, author %s) in %.0f s, %s" % [car_id, t.id, ", ".join(line),
		_fmt(best.time) if not best.is_empty() else "none", _fmt(gold), _fmt(float(medals.get("author", INF))), secs,
		"native" if trainer.is_native() else "GDSCRIPT"])
	if best.is_empty():
		return {}
	var f: Dictionary = best.file
	var net_file: Dictionary = {}
	for k: String in ["format", "version", "sensorVersion", "inputs", "car", "generation", "fitness", "trainedOn", "settings", "bestTimes", "network"]:
		if f.has(k):
			net_file[k] = f[k]
	return {sig = t.signature(), laps = t.laps if t.closed else 1, seed = seed, generation = best.gen, trainSeconds = roundi(secs),
		network = net_file, levels = {}}


# ---------------------------------------------------------------- the levels

func _levels(cars: PackedStringArray, track_ids: PackedStringArray, check: bool) -> int:
	var threads: int = int(_opt.get("threads", 3))
	var t_all: int = Time.get_ticks_msec()
	var files: Dictionary = {}
	for car_id: String in cars:
		files[car_id] = read_file(car_id)
		for id: String in track_ids:
			var t: BuiltTrack = Tracks.build(id)
			var e: Variant = (files[car_id].tracks as Dictionary).get(id)
			if not (e is Dictionary) or not JsMath.same(e.get("sig"), t.signature()):
				print("%s %s: no network for this version of the track (run --train)" % [car_id, id])
				continue
			# (the caches the race threads read, filled here)
			Car.track_phys(t)
			Sensors.track_headings(t)
			TrackBuilder.get_gates(t, t.laps if t.closed else 1)
			_jobs.append({car = car_id, track = id, entry = e, km = t.race_length(), check = check})
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
	var code: int = 0
	for car_id: String in cars:
		print("\n%s  %-16s %-9s %-9s %s" % [car_id, "track", "author", "gold", "  ".join(PackedStringArray(Array(Opponents.ids()).map(
			func(l: String) -> String: return "%-22s" % Opponents.level_name(l))))])
		for id: String in track_ids:
			var key: String = car_id + " " + id
			if not _results.has(key):
				continue
			var r: Dictionary = _results[key]
			var t: BuiltTrack = Tracks.build(id)
			var m: Dictionary = Medals.medal_times(t, car_id)
			var cells: PackedStringArray = []
			for l: String in Opponents.ids():
				var lv: Variant = (r.levels as Dictionary).get(l)
				if lv is Dictionary:
					cells.append("%-22s" % ("%s %.3f%s" % [_fmt(float(lv.time)), float(lv.time) / float(m.author),
						(" @%.1f" % float(lv.cap)) if lv.cap != null else ""]))
				else:
					cells.append("%-22s" % "none")
			print("%s  %-16s %-9s %-9s %s%s" % ["        ", id, _fmt(float(m.author)), _fmt(float(m.gold)), "  ".join(cells),
				("  " + r.note) if str(r.get("note", "")) != "" else ""])
			if not r.ok:
				code = 1
			if not check:
				files[car_id].tracks[id].levels = r.levels
		if not check:
			write_file(files[car_id])
	print("\n%s in %.0f s" % ["checked" if check else "levels written", (Time.get_ticks_msec() - t_all) / 1000.0])
	if check:
		print("every stored time is reproduced" if code == 0 else "SOME STORED TIMES DIFFER: run tools/opponents.gd")
	return code


func _work() -> void:
	while true:
		_mutex.lock()
		var j: int = _next
		_next += 1
		_mutex.unlock()
		if j >= _jobs.size():
			return
		var job: Dictionary = _jobs[j]
		var t: BuiltTrack = Tracks.build(job.track)
		var r: Dictionary = check_levels(t, job.car, job.entry) if job.check else make_levels(t, job.car, job.entry)
		_mutex.lock()
		_results[job.car + " " + job.track] = r
		_mutex.unlock()


## Each level's cap and time for a track and car: {ok, levels {id: {cap, time}}, note}. From the
## fastest level down: the target is pace × author, at least MIN_GAP × the level above; a level
## the network flat out does not beat by more than TOLERANCE drives with no cap.
static func make_levels(t: BuiltTrack, car_id: String, e: Dictionary) -> Dictionary:
	var net: NeuralNetwork = Trainer.parse_network_file(e.network).net
	var author: float = float(Medals.medal_times(t, car_id).author)
	var top: Dictionary = OpponentRace.run(net, t, car_id, INF, OpponentRace.MAX_TIME, true)
	var levels: Dictionary = {}
	if not top.finished:
		return {ok = false, levels = levels, note = "the network does not finish"}
	var ids: PackedStringArray = Opponents.ids()
	var above: float = 0.0
	var notes: PackedStringArray = []
	var ok: bool = true
	for k in range(ids.size() - 1, -1, -1):
		var lv: Dictionary = Opponents.level(ids[k])
		var target: float = maxf(float(lv.pace) * author, above * Opponents.MIN_GAP)
		var best: Dictionary = {}
		if top.time >= target * (1.0 - TOLERANCE):
			best = {cap = null, time = top.time, err = absf(top.time - target)}
		else:
			var est_target: float = target
			for it in 8:
				var cap: float = _cap(_solve_cap(top.speeds, est_target, top.top))
				var r: Dictionary = OpponentRace.run(net, t, car_id, cap)
				if not r.finished:
					est_target *= 0.97 # (too slow to finish: aim a little faster)
					continue
				var err: float = absf(r.time - target)
				if best.is_empty() or err < best.err:
					best = {cap = cap, time = r.time, err = err}
				if err <= TOLERANCE * target:
					break
				est_target *= target / r.time
		if best.is_empty():
			notes.append("%s does not finish" % ids[k])
			ok = false
			break
		if best.err > TOLERANCE * target and best.cap != null:
			notes.append("%s %.1f %% off" % [ids[k], 100.0 * best.err / target])
		if above > 0.0 and best.time <= above:
			notes.append("%s NOT slower than the level above" % ids[k])
			ok = false
		levels[ids[k]] = {cap = best.cap, time = _ms(best.time)}
		above = best.time
	return {ok = ok, levels = levels, note = ", ".join(notes)}


## The cap whose estimated race time (OpponentRace.estimate) is `target`: bisection between
## 3 m/s and the run's top speed.
static func _solve_cap(speeds: PackedFloat32Array, target: float, top: float) -> float:
	var lo: float = 3.0
	var hi: float = top
	for it in 40:
		var mid: float = 0.5 * (lo + hi)
		if OpponentRace.estimate(speeds, mid) > target:
			lo = mid
		else:
			hi = mid
	return 0.5 * (lo + hi)


## Re-run every stored level: {ok, levels (as measured now), note}.
static func check_levels(t: BuiltTrack, car_id: String, e: Dictionary) -> Dictionary:
	var net: NeuralNetwork = Trainer.parse_network_file(e.network).net
	var levels: Dictionary = {}
	var notes: PackedStringArray = []
	for id: String in Opponents.ids():
		var lv: Variant = (e.levels as Dictionary).get(id)
		if not (lv is Dictionary):
			notes.append("%s missing" % id)
			continue
		var cap: float = float(lv.cap) if lv.cap != null else INF
		var r: Dictionary = OpponentRace.run(net, t, car_id, cap)
		var now: float = _ms(r.time) if r.finished else INF
		levels[id] = {cap = lv.cap, time = now}
		if not is_finite(now) or JsMath.roundi(now * 1000.0) != JsMath.roundi(float(lv.time) * 1000.0):
			notes.append("%s %s, stored %s" % [id, _fmt(now), _fmt(float(lv.time))])
	return {ok = notes.is_empty(), levels = levels, note = ", ".join(notes)}
