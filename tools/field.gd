extends SceneTree
## field.gd (v6.13.0): measures Race the field without the game: whole field races (sim/field_race.gd)
## with every car driven by its AI, to see how the AI drivers behave in traffic.
## ------------------------------------------------------------------
##   godot --headless --path . --script res://tools/field.gd -- [--tracks=a,b] [--levels=a,b] [--car=racer]
##       [--threads=3] [--solo]
## The "player" (last on the grid) is driven by its car's AI opponent network at the level's own cap
## with the same traffic layer as the AI (a player who drives at the level's pace and avoids cars).
## For each race it prints: whether every AI finished, the new contacts between two AI cars and with
## the player's car, the stuck / wrong-way respawns, how many AI pairs finished in the order of their
## paces (sim/field.gd: the expected finish times alone) and whether the whole order matched, the
## player's place, and the script time per race step of the six cars. --solo also runs each AI alone
## with its cap (its real pace) and compares the finishing order with those times. Default: five tracks (a short
## oval, a twisty snowy one, a dirt circuit, a long one, a sprint) at the five levels with the Racer.

## A contact closing faster than this (m/s) counts as a hard one.
const HARD: float = 3.0

var _opt: Dictionary = {}
var _jobs: Array[Dictionary] = []
var _next: int = 0
var _results: Array[Dictionary] = []
var _mutex: Mutex = Mutex.new()


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		_opt[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var tracks: PackedStringArray = String(_opt.tracks).split(",") if _opt.has("tracks") else \
		PackedStringArray(["rookie-oval", "hairpin-valley", "forest-rally", "coastal-gp", "summit-rush"])
	var levels: PackedStringArray = String(_opt.levels).split(",") if _opt.has("levels") else Opponents.ids()
	var car: String = String(_opt.get("car", "racer"))
	for id: String in tracks:
		for lv: String in levels:
			var j := make_job(id, lv, car, _opt.has("solo"))
			if j.is_empty():
				print("%s %s: no field" % [id, lv])
				continue
			_jobs.append(j)
	var threads: int = int(_opt.get("threads", 3))
	var t0: int = Time.get_ticks_msec()
	var pool: Array[Thread] = []
	for k in threads:
		var th := Thread.new()
		th.start(_work)
		pool.append(th)
	for th in pool:
		th.wait_to_finish()
	_results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.order < b.order)
	print("\n%-16s %-8s %4s %6s %5s %6s %5s %8s %5s %5s %7s %s" % ["track", "level", "fin", "ai-ai", "hard", "you", "resp", "pairs", "exact", "you", "us/step", "AI order (finish time, pace)"])
	var tot := {races = 0, finished = 0, ai = 0, hard = 0, player = 0, resp = 0, pairs = 0, ok_pairs = 0, exact = 0, usec = 0.0,
		solo_pairs = 0, solo_ok = 0, drift = 0.0}
	for r: Dictionary in _results:
		print("%-16s %-8s %2d/5 %6d %5d %6d %5d %4d/%-3d %5s %5s %7.0f %s" % [r.track, r.level, r.finished, r.ai_contacts, r.hard, r.player_contacts, r.respawns,
			r.ok_pairs, r.pairs, "yes" if r.exact else "no", Field.place_name(r.place), r.usec, r.order_text])
		tot.races += 1
		tot.finished += r.finished
		tot.ai += r.ai_contacts
		tot.hard += r.hard
		tot.player += r.player_contacts
		tot.resp += r.respawns
		tot.pairs += r.pairs
		tot.ok_pairs += r.ok_pairs
		tot.exact += 1 if r.exact else 0
		tot.usec += r.usec
		tot.solo_pairs += r.solo_pairs
		tot.solo_ok += r.solo_ok
		tot.drift += r.drift
	if tot.races > 0:
		print("\n%d races: every AI finished in %d (%d of %d cars); %.1f AI-AI contacts a race (%.1f hard, over 3 m/s), %.1f with the player's car, %.2f respawns a race; pace order kept in %.0f %% of AI pairs, the whole order in %d of %d races; %.0f us a step (6 cars)" % [
			tot.races, _all_finished(), tot.finished, tot.races * 5, float(tot.ai) / tot.races, float(tot.hard) / tot.races, float(tot.player) / tot.races, float(tot.resp) / tot.races,
			100.0 * tot.ok_pairs / maxf(1.0, tot.pairs), tot.exact, tot.races, tot.usec / tot.races])
	if tot.solo_pairs > 0:
		print("against each AI's own race alone: the order kept in %.0f %% of AI pairs; a field race's time off its solo time by %.1f %% on average" % [
			100.0 * tot.solo_ok / tot.solo_pairs, 100.0 * tot.drift / tot.races])
	print("in %.0f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0)


func _all_finished() -> int:
	var n := 0
	for r: Dictionary in _results:
		if r.finished == 5:
			n += 1
	return n


func _work() -> void:
	while true:
		_mutex.lock()
		var k: int = _next
		_next += 1
		_mutex.unlock()
		if k >= _jobs.size():
			return
		var r := run_race(_jobs[k])
		r.order = k
		_mutex.lock()
		_results.append(r)
		_mutex.unlock()


## One field race to run (run_race): track `id`, field level `lv`, the player's car `car` ({} when
## there is no field). Readies the track for the threads (its physics tables, headings and gates).
static func make_job(id: String, lv: String, car: String, solo: bool = false) -> Dictionary:
	var t: BuiltTrack = Tracks.build(id)
	Car.track_phys(t)
	Sensors.track_headings(t)
	TrackBuilder.get_gates(t, t.laps if t.closed else 1)
	var lineup := Field.lineup(id, lv, car)
	if lineup.is_empty():
		return {}
	# the networks' files (one per car; each driver parses its own copy in its thread)
	var nets: Array = []
	for e: Dictionary in lineup:
		nets.append(Opponents.entry(id, String(e.car)).network)
	return {track = id, level = lv, car = car, lineup = lineup, nets = nets,
		player_net = Opponents.entry(id, car).network, player_cap = Opponents.cap_of(id, car, lv), solo = solo}


## A whole field race of `job` (make_job()), every car driven by its AI: the numbers the report prints.
static func run_race(job: Dictionary) -> Dictionary:
	var t: BuiltTrack = Tracks.build(String(job.track))
	var lineup: Array = job.lineup
	var drivers: Array = []
	for k in lineup.size():
		var net: NeuralNetwork = Trainer.parse_network_file(job.nets[k]).net
		drivers.append(Sensors.AIDriver.new(net, float(lineup[k].cap)))
	var pnet: NeuralNetwork = Trainer.parse_network_file(job.player_net).net
	var pdriver := Sensors.AIDriver.new(pnet, float(job.player_cap))
	var pcar := Car.new(t, t.start_idx, Cars.spec(String(job.car)))
	var prace := RaceState.new(t)
	var f := FieldRace.new(t, lineup, drivers, pcar, prace)
	var me: FieldRace.Racer = f.racers[f.player_index]
	var limit: int = int(1800.0 * 60.0)
	var usec := 0
	var coast := Car.Controls.new()
	var hard := 0
	while not (prace.finished and f.all_done()) and f.steps < limit:
		var t0 := Time.get_ticks_usec()
		var c: Car.Controls
		if prace.finished:
			c = FieldRace.PlayMode.roll_out(pcar, t, coast)
		else:
			c = pdriver.drive(t, pcar, prace)
			f.traffic(me, c)
		f.step(1.0 / 60.0, c)
		usec += Time.get_ticks_usec() - t0
		for h: CarContact.Hit in f.hits:
			if h.speed > HARD and h.a != f.player_index and h.b != f.player_index:
				hard += 1
		var bad := -1
		for k in f.racers.size():
			var cc: Car = f.racers[k].car
			if is_nan(cc.x) or is_nan(cc.z) or is_nan(cc.vx) or is_nan(cc.yaw_rate):
				bad = k
		if bad >= 0:
			var cc: Car = f.racers[bad].car
			printerr("NaN: %s %s step %d car %d (%s) x %f vx %f yaw_rate %f hits %d" % [job.track, job.level, f.steps, bad, f.code_of(bad), cc.x, cc.vx, cc.yaw_rate, f.hits.size()])
			for h: CarContact.Hit in f.hits:
				printerr("  hit %d-%d depth %.3f speed %.2f impulse %.0f" % [h.a, h.b, h.depth, h.speed, h.impulse])
			break
		if f.steps % 60 == 0:
			for k in f.racers.size():
				var cc: Car = f.racers[k].car
				if absf(cc.yaw_rate) > 8.0 or cc.speed > 120.0:
					printerr("wild: %s %s step %d car %d yaw_rate %.1f speed %.1f" % [job.track, job.level, f.steps, k, cc.yaw_rate, cc.speed])
		# (the player is an AI here too: put it back when it is stuck, as the AI are)
		if not prace.finished and FieldRace.PlayMode.is_stuck(me.watch, pcar, prace):
			FieldRace.PlayMode.respawn_car(pcar, prace, t, false)
			f.respawned(f.player_index)
			me.respawns += 1
	var fin := 0
	var resp := 0
	for k in lineup.size():
		var r: FieldRace.Racer = f.racers[k]
		if r.race.finished:
			fin += 1
		resp += r.respawns
	# pace order: AI pairs that finished in the order of their expected times
	var pairs := 0
	var ok := 0
	for i in lineup.size():
		for j in range(i + 1, lineup.size()):
			var a: FieldRace.Racer = f.racers[i]
			var b: FieldRace.Racer = f.racers[j]
			if is_equal_approx(float(a.info.pace), float(b.info.pace)):
				continue
			pairs += 1
			var a_first: bool = a.race.finish_time < b.race.finish_time
			if a_first == (float(a.info.pace) < float(b.info.pace)):
				ok += 1
	# (--solo) each AI alone with its cap: its real pace (ai/opponent_race.gd, as the menu's AI times)
	var solo_pairs := 0
	var solo_ok := 0
	var drift := 0.0
	if bool(job.solo):
		var solo: Array = []
		for k in lineup.size():
			var net2: NeuralNetwork = Trainer.parse_network_file(job.nets[k]).net
			solo.append(float(OpponentRace.run(net2, t, String(lineup[k].car), float(lineup[k].cap)).time))
		for i in lineup.size():
			drift += absf(f.racers[i].race.finish_time - float(solo[i])) / float(solo[i]) / lineup.size()
			(f.racers[i].info as Dictionary).solo = solo[i]
			for j in range(i + 1, lineup.size()):
				if is_equal_approx(float(solo[i]), float(solo[j])):
					continue
				solo_pairs += 1
				if (f.racers[i].race.finish_time < f.racers[j].race.finish_time) == (float(solo[i]) < float(solo[j])):
					solo_ok += 1
	var order := f.standings()
	var text: PackedStringArray = []
	for i: int in order:
		var r: FieldRace.Racer = f.racers[i]
		text.append("%s %s%s" % [f.code_of(i), RaceState.format_time(r.race.finish_time),
			(" (%s%s)" % [RaceState.format_time(float(r.info.pace)), (" solo %s" % RaceState.format_time(float(r.info.solo))) if r.info.has("solo") else ""]) if not r.player else ""])
	var times: PackedFloat64Array = []
	for r: FieldRace.Racer in f.racers:
		times.append(r.race.finish_time)
	return {track = job.track, level = job.level, finished = fin, times = times, steps = f.steps, ai_contacts = f.ai_contacts, player_contacts = f.player_contacts,
		hard = hard, respawns = resp, pairs = pairs, ok_pairs = ok, exact = ok == pairs, place = f.position(f.player_index),
		usec = float(usec) / maxf(1.0, f.steps), order_text = ", ".join(text), solo_pairs = solo_pairs, solo_ok = solo_ok, drift = drift}
