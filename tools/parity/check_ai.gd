extends SceneTree
## check_ai.gd: AI parity, Godot side (tools/parity/ai_runs.mjs writes the JS side).
## ------------------------------------------------------------------
##   node tools/parity/ai_runs.mjs /tmp/ai_runs tests/fixtures/ai_web_network.json
##   godot --headless --path <copy> --script res://tools/parity/check_ai.gd -- /tmp/ai_runs [native-only]
## 1. Lockstep sensors + network: every JS sample's car state (before the step) goes into a
##    GDScript Car; ai/sensors.gd senses it and drives the same network; the 18 inputs and the
##    2 controls must equal the JS ones (32-bit floats).
## 2. Free runs: one generation of each scenario with the GDScript Trainer (unless
##    "native-only") and with FleetSim: every car's fitness, why it stopped, the deaths, the
##    wall count, the run's step count, the generation's best / average and the best times,
##    compared with the JS run.

const HexJson = preload("res://tools/parity/hex_json.gd")


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var prefix: String = args[0] if args.size() > 0 else "/tmp/ai_runs"
	var native_only: bool = args.has("native-only")
	var data: Dictionary = HexJson.decode(JSON.parse_string(FileAccess.get_file_as_string(prefix + ".json")))
	var bin: PackedFloat64Array = FileAccess.get_file_as_bytes(prefix + ".bin").to_float64_array()
	var keys: Array = data.keys
	var per: int = int(data.per)
	var scenarios: Array = data.scenarios
	var ok_all: bool = true

	# --- 1. lockstep sensors + network --------------------------------------------------------
	var nets: Array = []
	var built: Array = []
	for sc: Dictionary in scenarios:
		nets.append(_population(sc).genomes)
		var ts: Array = []
		for id: Variant in sc.tracks:
			ts.append(Tracks.build_asphalt(String(id)))
		built.append(ts)
	var n_samples: int = bin.size() / per
	# where each sample is: "scenario:run:step:car" -> offset in bin
	var sample_at: Dictionary = {}
	for s in n_samples:
		var o: int = s * per
		sample_at["%d:%d:%d:%d" % [int(bin[o]), int(bin[o + 1]), int(bin[o + 2]), int(bin[o + 3])]] = o
	var in_bad: int = 0
	var out_bad: int = 0
	var in_max: float = 0.0
	var out_max: float = 0.0
	var first: String = ""
	var car := Car.new()
	var inputs := PackedFloat32Array()
	inputs.resize(Sensors.INPUT_COUNT)
	var mirrored := PackedFloat32Array()
	mirrored.resize(Sensors.INPUT_COUNT)
	var ctrl := Car.Controls.new()
	for s in n_samples:
		var o: int = s * per
		var si: int = int(bin[o])
		var run: int = int(bin[o + 1])
		var k: int = int(bin[o + 3])
		var st: Dictionary = {}
		for i in keys.size():
			st[keys[i]] = bin[o + 4 + i]
		car.from_state(st)
		var t: BuiltTrack = built[si][run]
		Sensors.sense(t, car, inputs, null)
		var net: NeuralNetwork = (nets[si][k] as Population.Genome).net
		Sensors.drive_network(net, inputs, mirrored, ctrl)
		var io: int = o + 4 + keys.size()
		for i in Sensors.INPUT_COUNT:
			var d: float = absf(inputs[i] - bin[io + i])
			if d != 0.0:
				in_bad += 1
				in_max = maxf(in_max, d)
				if first == "":
					first = "sample %d (scenario %d run %d step %d car %d) input %d: gd %s js %s" % [s, si, run, int(bin[o + 2]), k, i, inputs[i], bin[io + i]]
		for i in 2:
			var v: float = ctrl.steer if i == 0 else ctrl.throttle
			var d: float = absf(v - bin[io + 18 + i])
			if d != 0.0:
				out_bad += 1
				out_max = maxf(out_max, d)
	print("lockstep: %d samples (car states from the JS run): %d of %d inputs differ (largest %s), %d of %d controls differ (largest %s)" % [
		n_samples, in_bad, n_samples * 18, str(in_max), out_bad, n_samples * 2, str(out_max)])
	if first != "":
		print("  first: ", first)
	ok_all = ok_all and in_bad == 0 and out_bad == 0

	# --- 2. free runs ---------------------------------------------------------------------------
	for si in scenarios.size():
		var sc: Dictionary = scenarios[si]
		for native: bool in [false, true]:
			if not native and native_only:
				continue
			if native and not Trainer.native_available():
				print("FleetSim not loaded: native free runs skipped")
				continue
			var t0: int = Time.get_ticks_msec()
			var res: Dictionary = _free_run(sc, built[si], native, si, sample_at, bin, keys)
			var report: Array = []
			var same_runs: bool = true
			for r in sc.runs.size():
				var js: Dictionary = sc.runs[r]
				var gd: Dictionary = res.runs[r] if r < res.runs.size() else {}
				if gd.is_empty():
					same_runs = false
					report.append("run %d missing" % r)
					continue
				var fit_same: int = 0
				var fit_max: float = 0.0
				for k in js.fitness.size():
					var d: float = absf(float(js.fitness[k]) - float(gd.fitness[k]))
					if d == 0.0:
						fit_same += 1
					fit_max = maxf(fit_max, d)
				var reasons_same: bool = str(js.reasons) == str(gd.reasons)
				var deaths_same: bool = _same_counts(js.deaths, gd.deaths)
				var steps_same: bool = int(js.steps) == int(gd.steps)
				var walls_same: bool = int(js.wallCars) == int(gd.wall_cars)
				same_runs = same_runs and fit_same == js.fitness.size() and reasons_same and deaths_same and steps_same and walls_same
				report.append("%s: fitness %d/%d equal (largest diff %s), reasons %s, deaths %s, steps %s (%d/%d), wall cars %s" % [
					js.track, fit_same, js.fitness.size(), str(fit_max), _yn(reasons_same), _yn(deaths_same), _yn(steps_same),
					int(gd.steps), int(js.steps), _yn(walls_same)])
			var entry_same: bool = float(sc.entry.best) == float(res.entry.best) and float(sc.entry.avg) == float(res.entry.avg)
			var times_same: bool = _same_times(sc.bestTimes, res.best_times)
			if res.first_diff != "":
				print("  first state difference from the JS run: %s; first over 1 mm: %s" % [res.first_diff, res.first_mm])
			print("scenario %d %s (%s, walls %s, laps %d, %d cars) %s: %s; generation best/avg %s; best times %s (%.1f s)" % [
				si, "+".join(PackedStringArray(sc.tracks)), "FleetSim" if native else "GDScript", sc.walls, int(sc.laps), int(sc.n),
				"OK" if same_runs and entry_same and times_same else "DIFFERS", "; ".join(PackedStringArray(report)),
				_yn(entry_same), _yn(times_same), (Time.get_ticks_msec() - t0) / 1000.0])
			if not entry_same:
				print("  entry js %s gd %s" % [sc.entry, res.entry])
			if not times_same:
				print("  times js %s gd %s" % [sc.bestTimes, res.best_times])
			ok_all = ok_all and same_runs and entry_same and times_same
	print("AI parity: ", "all identical" if ok_all else "differences (see above)")
	quit(0 if ok_all else 1)


func _yn(b: bool) -> String:
	return "same" if b else "DIFFERENT"


func _population(sc: Dictionary) -> Population:
	var sizes := PackedInt32Array(sc.sizes)
	var params := PackedFloat32Array(sc.params)
	var pop := Population.new({sizes = sizes, mutation_rate = 0.1})
	var per: int = NeuralNetwork.params_for(sizes)
	for k in int(sc.n):
		pop.genomes.append(Population.Genome.new(NeuralNetwork.from_params(sizes, params, k * per)))
	return pop


## One generation of the scenario: each track run's fitness, reasons, deaths, wall count, steps.
## The car states are compared with the JS samples as they go (first difference, first over 1 mm).
func _free_run(sc: Dictionary, ts: Array, native: bool, si: int, sample_at: Dictionary, bin: PackedFloat64Array, keys: Array) -> Dictionary:
	var tr := Trainer.new({tracks = ts, population = _population(sc), native = native, threads = 1,
		walls = sc.walls, laps = int(sc.laps)})
	var res: Dictionary = {runs = [], entry = {}, best_times = {}, first_diff = "", first_mm = "none"}
	var steps: Array[int] = [0]
	tr.on_run_end = func(t: BuiltTrack, deaths: Dictionary) -> void:
		var fit: Array = []
		var reasons: Array = []
		for a in tr.agents:
			fit.append(a.fitness)
			reasons.append(a.death_reason)
		res.runs.append({track = t.id, fitness = fit, reasons = reasons, deaths = deaths.duplicate(), wall_cars = tr.wall_cars, steps = steps[0]})
		steps[0] = 0
	tr.on_generation = func(entry: Dictionary) -> void:
		res.entry = entry.duplicate()
	while tr.generation == 0:
		if steps[0] % 10 == 0 and (res.first_diff == "" or res.first_mm == "none"):
			for a in tr.agents:
				var key: String = "%d:%d:%d:%d" % [si, tr.track_pos, steps[0], a.index]
				if not a.alive or not sample_at.has(key):
					continue
				var o: int = sample_at[key]
				var st: Dictionary = tr.fleet.call("get_car_state", a.index) if native else a.car.to_state()
				for i in keys.size():
					var d: float = absf(float(st[keys[i]]) - bin[o + 4 + i])
					if d != 0.0 and res.first_diff == "":
						res.first_diff = "run %d step %d car %d %s by %s" % [tr.track_pos, steps[0], a.index, keys[i], String.num_scientific(d)]
					if d > 1e-3 and (keys[i] == "x" or keys[i] == "z") and res.first_mm == "none":
						res.first_mm = "run %d step %d car %d %s by %s" % [tr.track_pos, steps[0], a.index, keys[i], str(d)]
		tr.step(Trainer.STEP)
		steps[0] += 1
	res.best_times = tr.best_times.duplicate(true)
	tr.on_run_end = Callable() # (the callbacks hold the trainer: let it go)
	tr.on_generation = Callable()
	return res


func _same_counts(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k: Variant in a:
		if not b.has(k) or int(a[k]) != int(b[k]):
			return false
	return true


func _same_times(a: Dictionary, b: Dictionary) -> bool:
	for id: Variant in a:
		if not b.has(id):
			return false
		for f: String in ["lap", "finish"]:
			var x: Variant = a[id].get(f)
			var y: Variant = b[id].get(f)
			if (x == null) != (y == null) or (x != null and float(x) != float(y)):
				return false
	for id: Variant in b:
		if not a.has(id):
			return false
	return true
