extends SceneTree
## headless_train.gd: train without the game window (port of web/tools/headlessTrain.mjs).
## ------------------------------------------------------------------
##   godot --headless --path . --script res://tools/headless_train.gd -- [tracks,comma,separated] [generations] [out.json] [seed.json] [options]
##   godot --headless --path . --script res://tools/headless_train.gd -- rookie-oval,hairpin-valley 100 /tmp/my-driver.json
##
## Options:
##   --pop N          population size (default 80)
##   --hidden 12      hidden layer size(s), e.g. 16,8
##   --mutation 0.1   mutation rate
##   --laps 1         laps per circuit run
##   --walls ride     "ride" (cars keep going after a wall hit) or "crash" (a wall hit puts the car out)
##   --stop-after N   stop N generations after every track has been finished
##   --quiet          only print every 10th generation
##   --threads N      native threads (default: one per core, at most 8)
##   --gdscript       simulate in GDScript instead of the native FleetSim (much slower)
##   --seed N         seed the AI's random numbers (repeatable runs with the same options)
##   --car ID         the car the AI drives (default racer, like the web game)
##
## The output file is the same format as "Save best network" in the game and in the browser
## version, so it loads in either to watch it drive or keep training. It is written whenever
## the best network improves, so the run can be stopped at any time. Relative file paths are
## taken from the current directory. Every line ends with the speed: simulated seconds per real
## second ("x real time") and car steps per second.

var _opt: Dictionary = {}


func _initialize() -> void:
	var pos: PackedStringArray = []
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var k: int = 0
	while k < args.size():
		var a: String = args[k]
		if a.begins_with("--"):
			var key: String = a.substr(2)
			if key == "quiet" or key == "gdscript":
				_opt[key] = true
			elif k + 1 < args.size():
				k += 1
				_opt[key] = args[k]
		else:
			pos.append(a)
		k += 1
	var code: int = _run(pos)
	quit(code)


func _path(p: String) -> String:
	if p.begins_with("res://") or p.begins_with("user://") or p.is_absolute_path():
		return p
	var cwd: String = OS.get_environment("PWD")
	return cwd.path_join(p) if cwd != "" else p


func _run(pos: PackedStringArray) -> int:
	var ids: PackedStringArray = (pos[0] if pos.size() > 0 else "rookie-oval").split(",")
	var gens: int = int(pos[1]) if pos.size() > 1 else 30
	var out_file: String = _path(pos[2] if pos.size() > 2 else "best-network.json")
	var seed_file: String = _path(pos[3]) if pos.size() > 3 else ""

	var tracks: Array = []
	for id in ids:
		var t: BuiltTrack = Tracks.build(id)
		if t == null:
			printerr('Unknown track "%s". Known: %s' % [id, ", ".join(Tracks.ids())])
			return 1
		tracks.append(t)
	if _opt.has("walls") and not Trainer.WALL_RULES.has(String(_opt.walls)):
		printerr('--walls must be one of: %s (got "%s")' % [", ".join(PackedStringArray(Trainer.WALL_RULES.keys())), _opt.walls])
		return 1
	if _opt.has("seed"):
		NeuralNetwork.rng.seed = int(_opt.seed)

	var seed: NeuralNetwork = null
	var seed_meta: Variant = null
	if seed_file != "":
		var parsed: Dictionary = Trainer.parse_network_file(FileAccess.get_file_as_string(seed_file))
		if parsed.has("error"):
			printerr("%s: %s" % [seed_file, parsed.error])
			return 1
		seed = parsed.net
		seed_meta = parsed.meta

	var hidden: Array = Trainer.DEFAULT_TRAINING.hidden
	if _opt.has("hidden"):
		hidden = []
		for h in String(_opt.hidden).split(","):
			hidden.append(int(h))
	var native: bool = not _opt.has("gdscript")
	var cfg: Dictionary = {
		tracks = tracks,
		population_size = int(_opt.get("pop", Trainer.DEFAULT_TRAINING.population_size)),
		mutation_rate = float(_opt.get("mutation", Trainer.DEFAULT_TRAINING.mutation_rate)),
		hidden = hidden,
		laps = int(_opt.get("laps", Trainer.DEFAULT_TRAINING.laps)),
		walls = String(_opt.get("walls", Trainer.DEFAULT_TRAINING.walls)),
		car_id = String(_opt.get("car", Trainer.DEFAULT_TRAINING.car_id)),
		seed = seed,
		seed_meta = seed_meta,
		native = native,
		threads = int(_opt.get("threads", 0)),
	}
	var trainer := Trainer.new(cfg)
	var lens: PackedStringArray = []
	for t: BuiltTrack in tracks:
		lens.append("%s (%.2f km%s)" % [t.id, TrackBuilder.race_length(t, 1) / 1000.0, "/lap" if t.closed else ""])
	var sim: String = "native FleetSim, %d thread(s)" % int(trainer.fleet.call("get_threads")) if trainer.is_native() else "GDScript"
	print("training a %s network, population %d, mutation %s, %d lap(s) per circuit, walls: %s, car: %s, on %s [%s]" % [
		"-".join(Array(trainer.sizes).map(func(v: int) -> String: return str(v))), cfg.population_size, str(cfg.mutation_rate),
		cfg.laps, trainer.cfg.walls, trainer.cfg.car_id, ", ".join(lens), sim])
	if trainer.native_note != "" and native:
		print("note: ", trainer.native_note)
	var seed_rule: String = Trainer.saved_wall_rule(seed_meta)
	if seed_rule != "" and seed_rule != trainer.cfg.walls:
		print("note: %s was trained with walls: %s; this run uses walls: %s, so its old best fitness doesn't carry over (pass --walls %s to keep its rule)" % [
			seed_file, seed_rule, trainer.cfg.walls, seed_rule])

	var t0: int = Time.get_ticks_usec()
	var first_finish: Dictionary = {}
	var state: Dictionary = {all_finished_at = -1, saved = -INF, deaths = {}, wall_cars = 0}
	trainer.on_run_end = func(_t: BuiltTrack, d: Dictionary) -> void:
		for key: String in d:
			state.deaths[key] = int(state.deaths.get(key, 0)) + int(d[key])
		state.wall_cars += trainer.wall_cars
	trainer.on_generation = func(s: Dictionary) -> void:
		var gen: int = int(s.gen)
		for t: BuiltTrack in tracks:
			var r: Variant = trainer.best_times.get(t.id)
			if not first_finish.has(t.id) and r is Dictionary and r.finish != null:
				first_finish[t.id] = gen
		if state.all_finished_at < 0 and first_finish.size() == tracks.size():
			state.all_finished_at = gen
		if trainer.best_fitness > state.saved:
			state.saved = trainer.best_fitness
			_write(out_file, trainer.export_best())
		if not _opt.has("quiet") or gen % 10 == 0 or gen == state.all_finished_at:
			var times: PackedStringArray = []
			for t: BuiltTrack in tracks:
				var r: Variant = trainer.best_times.get(t.id)
				var lap: Variant = r.lap if r is Dictionary else null
				var fin: Variant = r.finish if r is Dictionary else null
				times.append("%s: %sfinish %s" % [t.id, ("lap %s " % _fmt(lap)) if t.closed else "", _fmt(fin)])
			var outs: PackedStringArray = []
			for key: String in state.deaths:
				outs.append("%s %d" % [key, state.deaths[key]])
			var walls: String = ", %d touched a wall" % state.wall_cars if trainer.cfg.walls == "ride" else ""
			var secs: float = (Time.get_ticks_usec() - t0) / 1e6
			print("gen %d  best %.0f  avg %.0f  %s  [cars: %s%s]  (%.1f s, %.1fx real time, %.0f car steps/s)" % [
				gen, s.best, s.avg, "  ".join(times), ", ".join(outs), walls, secs,
				trainer.steps_done() * Trainer.STEP / maxf(secs, 1e-6), trainer.car_steps() / maxf(secs, 1e-6)])
		state.deaths = {}
		state.wall_cars = 0

	var target: int = trainer.generation + gens
	var stop_after: int = int(_opt["stop-after"]) if _opt.has("stop-after") else -1
	while trainer.generation < target and not (state.all_finished_at >= 0 and stop_after >= 0 and trainer.generation > state.all_finished_at + stop_after):
		trainer.step_many(60)
	_write(out_file, trainer.export_best())
	trainer.on_run_end = Callable() # (the callbacks hold the trainer: let it go)
	trainer.on_generation = Callable()
	var secs: float = (Time.get_ticks_usec() - t0) / 1e6
	for t: BuiltTrack in tracks:
		var r: Variant = trainer.best_times.get(t.id)
		print("%s: first finish in generation %s, best %sfinish %s" % [t.id, str(first_finish.get(t.id, "none")),
			("lap %s, " % _fmt(r.lap if r is Dictionary else null)) if t.closed else "", _fmt(r.finish if r is Dictionary else null)])
	print("saved %s (generation %d, best fitness %.0f, %.0f s, %.1fx real time, %.0f car steps/s)" % [out_file, trainer.generation,
		trainer.best_fitness, secs, trainer.steps_done() * Trainer.STEP / maxf(secs, 1e-6), trainer.car_steps() / maxf(secs, 1e-6)])
	return 0


func _fmt(t: Variant) -> String:
	return RaceState.format_time(float(t) if t != null else INF)


func _write(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("could not write ", path)
		return
	f.store_string(JSON.stringify(data))
	f.close()
