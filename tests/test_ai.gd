extends RefCounted
## test_ai.gd: checks of the AI (ai/, native/, modes/train_mode.gd), run by tests/run_tests.gd:
##   godot --headless --path <copy> --script res://tests/run_tests.gd -- ai
## - the network: shapes, forward pass, clone / mutate / crossover, flat parameters, the JSON
##   format (round trips, a network saved by the browser version, refused old / wrong files)
## - the sensors and the driver: the browser version's numbers for the saved network driving
##   from the start of two tracks (inputs, controls, the car after 2 s), the mirror symmetry
## - the rules: crash / ride walls, stalled, backwards, the score of a finished car
## - FleetSim (the native GDExtension) against the GDScript simulation: every car's state,
##   inputs, fitness and reason, the generation and the best times; 1 thread = 4 threads;
##   the fallback to GDScript (with its note) when the extension is missing
## - a short training run improves the best fitness (native and GDScript)
## - the training screen with a stand-in game: setup, 1×, Fast, Max on its thread, pause,
##   Save best network, Stop
## About 30 s with the extension (most of it the GDScript simulation), longer without.

const FIXTURE := "res://tests/fixtures/ai_web_network.json"
const TrainModeScript := preload("res://modes/train_mode.gd")

## The browser version (web/, node) driving the fixture network from each track's start:
## inputs and controls at steps 0 and 120 as 32-bit float bits, then the car's x, z, yaw and
## speed after 120 steps as 64-bit float bits (node tools/parity/ai_ref.mjs prints them).
const JS_REF := {
	"rookie-oval": {
		"s0": {"inputs": [1038174126, 1040322755, 1044668865, 1054448273, 1065353216, 1054448273, 1044668865, 1040322755, 1038174126, 0, 0, 0, 0, 0, 0, 1065353216, 1065353216, 1065353216], "steer": 0, "throttle": 1065342566},
		"s120": {"inputs": [1038174126, 1040322755, 1044668865, 1054448273, 1065353216, 1054448273, 1044668865, 1040322755, 1038174126, 1050095063, 0, 0, 0, 0, 0, 1065353216, 1065353216, 1065353216], "steer": 0, "throttle": 1065340933},
		"x": "0000000000000000", "z": "4041f021c85aa5ab", "yaw": "0000000000000000", "speed": "4036babdb4257e06",
	},
	"hairpin-valley": {
		"s0": {"inputs": [1032134328, 1033483959, 1038620271, 1048614276, 1065353216, 1048614276, 1038620271, 1033483959, 1032134328, 0, 0, 0, 607372669, 598984061, 0, 1065353216, 1065353216, 1065353216], "steer": 0, "throttle": 1065343867},
		"s120": {"inputs": [1032134328, 1033483959, 1038620271, 1048614276, 1065353216, 1048614276, 1038620271, 1033483959, 1032134328, 1050095844, 184549376, 2332803447, 615725020, 603667625, 0, 1065353216, 1065353216, 1065353216], "steer": 0, "throttle": 1065342487},
		"x": "4041efaadc7d6d13", "z": "3cda5621057cab91", "yaw": "3ff921fb54442d18", "speed": "4036bb331d46e1cc",
	},
}

var t: Variant
var fixture_text := ""


func run(checker: Variant) -> bool:
	t = checker
	NeuralNetwork.rng.seed = 2024
	fixture_text = FileAccess.get_file_as_string(FIXTURE)
	_network()
	_network_files()
	_sensors()
	_rules()
	_fleet_parity()
	_training()
	_train_screen()
	return true


# ================================================================= helpers

static func f32(bits: int) -> float:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_u32(0, bits)
	return b.decode_float(0)


static func f64(hex: String) -> float:
	var b := PackedByteArray()
	b.resize(8)
	b.encode_u64(0, hex.hex_to_int())
	return b.decode_double(0)


func fixture_net() -> NeuralNetwork:
	return Trainer.parse_network_file(fixture_text).net


## A network with no hidden layer whose outputs are tanh(steer_b), tanh(thr_b) whatever it sees.
static func const_net(steer_b: float, thr_b: float) -> NeuralNetwork:
	var n := NeuralNetwork.new(PackedInt32Array([18, 2]))
	n.weights[0].fill(0.0)
	n.biases[0][0] = steer_b
	n.biases[0][1] = thr_b
	return n


static func population_of(nets: Array) -> Population:
	var pop := Population.new({sizes = (nets[0] as NeuralNetwork).sizes, mutation_rate = 0.1})
	for n: NeuralNetwork in nets:
		pop.genomes.append(Population.Genome.new(n))
	return pop


## The fixture network and n - 1 mutated copies (seeded: the same every run).
func mutated_fixture(n: int, seed: int) -> Array:
	NeuralNetwork.rng.seed = seed
	var base := fixture_net()
	var out: Array = [base]
	for k in n - 1:
		out.append(base.clone().mutate(0.1))
	return out


static func same_floats(a: PackedFloat32Array, b: PackedFloat32Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i] != b[i]:
			return false
	return true


# ================================================================= the network

func _network() -> void:
	t.section("network")
	var n := NeuralNetwork.new(PackedInt32Array([18, 12, 2]))
	t.check(n.weights.size() == 2 and n.weights[0].size() == 12 * 18 and n.weights[1].size() == 2 * 12
		and n.biases[0].size() == 12 and n.biases[1].size() == 2, "a [18, 12, 2] network has weights o * n_in + i per layer and a bias per neuron")
	t.check(n.param_count() == 254 and NeuralNetwork.params_for(PackedInt32Array([18, 12, 2])) == 254, "254 parameters")
	var inputs := PackedFloat32Array()
	for i in 18:
		inputs.append(sin(i * 1.7))
	var out := n.forward(inputs).duplicate()
	t.check(out.size() == 2 and absf(out[0]) <= 1.0 and absf(out[1]) <= 1.0, "forward gives 2 outputs in -1..1 (tanh)")
	t.check(same_floats(n.acts[0], inputs) and same_floats(n.acts[2], out), "acts keeps every layer's activations (the network view draws them)")
	# by hand: one neuron of the hidden layer
	var sum := float(n.biases[0][3])
	for i in 18:
		sum += float(n.weights[0][3 * 18 + i]) * float(inputs[i])
	var h3 := PackedFloat32Array([tanh(sum)])
	t.check(n.acts[1][3] == h3[0], "a hidden neuron is tanh(bias + sum of weight × input), summed in doubles, kept as a 32-bit float")

	var c := n.clone()
	c.weights[0][0] += 1.0
	t.check(n.weights[0][0] != c.weights[0][0] and same_floats(c.forward(inputs), c.outputs()), "a clone is independent of its original")
	var m := n.clone().mutate(1.0, 0.5)
	var changed := 0
	var inside := true
	for l in m.weights.size():
		for i in m.weights[l].size():
			if m.weights[l][i] != n.weights[l][i]:
				changed += 1
			inside = inside and absf(m.weights[l][i]) <= 5.0
	t.check(changed > 200 and inside, "mutate(rate 1) changes the weights, kept within ±5 (%d changed)" % changed)
	var x := NeuralNetwork.crossover(n, m)
	var from_a := 0
	var from_b := 0
	for o in 12:
		var row_a := true
		var row_b := true
		for i in 18:
			row_a = row_a and x.weights[0][o * 18 + i] == n.weights[0][o * 18 + i]
			row_b = row_b and x.weights[0][o * 18 + i] == m.weights[0][o * 18 + i]
		from_a += 1 if row_a else 0
		from_b += 1 if row_b and not row_a else 0
	t.check(x.same_shape(n) and from_a + from_b == 12, "crossover takes each neuron's weights from one parent (%d / %d)" % [from_a, from_b])
	var p := n.params()
	var back := NeuralNetwork.from_params(n.sizes, p)
	t.check(p.size() == 254 and same_floats(back.forward(inputs), out), "params() / from_params() round trip")

	# JSON
	var j := n.to_json()
	var text := JSON.stringify(j)
	var n2 := NeuralNetwork.from_json(JSON.parse_string(text))
	var same := n2 != null and n2.sizes == n.sizes
	if same:
		for l in n.weights.size():
			same = same and same_floats(n.weights[l], n2.weights[l]) and same_floats(n.biases[l], n2.biases[l])
	t.check(same, "to_json (9 significant digits) -> JSON text -> from_json gives the same 32-bit weights")
	t.check(Array(j.sizes) == [18, 12, 2] and j.weights is Array and (j.weights[0] as Array).size() == 216, "the JSON is {sizes, weights, biases} with plain number arrays (web network.js)")
	t.check(NeuralNetwork.from_json({sizes = [18, 2], weights = [[1, 2]], biases = [[0, 0]]}) == null
		and NeuralNetwork.from_json("nope") == null, "from_json refuses a malformed network")

	t.section("population")
	NeuralNetwork.rng.seed = 11
	var pop := Population.new({size = 20, sizes = PackedInt32Array([18, 6, 2]), mutation_rate = 0.1})
	for k in 20:
		pop.genomes[k].fitness = float(k * 7 % 20)
	var best_params := pop.genomes[17].net.params() # fitness 19
	var st := pop.evolve()
	t.check(pop.size() == 20 and float(st.best) == 19.0 and is_equal_approx(float(st.avg), 9.5), "evolve keeps the size and reports best / average")
	t.check(same_floats(pop.genomes[0].net.params(), best_params) and pop.best_ever.fitness == 19.0, "the best genome is kept unchanged (elite) and is the best ever")
	var copy := pop.copy()
	copy.genomes[0].net.weights[0][0] += 1.0
	t.check(pop.genomes[0].net.weights[0][0] != copy.genomes[0].net.weights[0][0], "copy() is a deep copy")


# ================================================================= network files

func _network_files() -> void:
	t.section("network files")
	var parsed := Trainer.parse_network_file(fixture_text)
	t.check(not parsed.has("error"), "the browser version's saved network loads (tests/fixtures/ai_web_network.json)")
	if parsed.has("error"):
		return
	var net: NeuralNetwork = parsed.net
	var meta: Dictionary = parsed.meta
	t.check(Array(net.sizes) == [18, 12, 2] and int(meta.generation) == 6 and absf(float(meta.fitness) - 1512.46) < 0.01,
		"its network is 18-12-2, generation 6, fitness 1512.46")
	t.check(Trainer.saved_wall_rule(meta) == "ride" and Array(meta.trainedOn) == ["rookie-oval", "hairpin-valley"], "trained with walls: ride on rookie-oval + hairpin-valley")
	var raw: Dictionary = JSON.parse_string(fixture_text)
	var w_ok := true
	for l in 2:
		var src: Array = raw.network.weights[l]
		for i in src.size():
			w_ok = w_ok and net.weights[l][i] == PackedFloat32Array([float(src[i])])[0]
	t.check(w_ok, "every weight is the file's number as a 32-bit float")
	# saved again (the file format of Save best network) and loaded back
	var again := Trainer.parse_network_file(JSON.stringify(Trainer.network_file(net, meta)))
	var same := not again.has("error")
	if same:
		for l in 2:
			same = same and same_floats(net.weights[l], again.net.weights[l]) and same_floats(net.biases[l], again.net.biases[l])
	t.check(same and int(again.meta.generation) == 6 and again.meta.format == Trainer.NETWORK_FORMAT, "saved again and loaded back: the same network and training info")
	var tr := Trainer.new({tracks = [Tracks.build("rookie-oval")], population_size = 4, native = false})
	var ex := tr.export_best()
	t.check(ex.format == "trackmania-lite-network" and int(ex.version) == 2 and int(ex.sensorVersion) == 2 and (ex.inputs as Array).size() == 18
		and ex.settings.walls == "ride" and ex.network.sizes == [18, 12, 2], "export_best writes the web file format (format, version 2, sensorVersion 2, inputs, settings, network)")
	t.check(not Trainer.parse_network_file(JSON.stringify(ex)).has("error"), "an exported file loads")
	var bare := Trainer.parse_network_file(JSON.stringify(net.to_json()))
	t.check(not bare.has("error") and Trainer.saved_wall_rule(bare.meta) == "", "a bare {sizes, weights, biases} network loads (no training info)")

	var v1 := NeuralNetwork.new(PackedInt32Array([11, 8, 2]))
	var e1: Dictionary = Trainer.parse_network_file(JSON.stringify({format = Trainer.NETWORK_FORMAT, version = 1, network = v1.to_json()}))
	t.check(e1.has("error") and String(e1.error).contains("v1"), "a v1 network (11 inputs) is refused with the v1 message")
	var e2: Dictionary = Trainer.parse_network_file(JSON.stringify(NeuralNetwork.new(PackedInt32Array([18, 4, 3])).to_json()))
	t.check(e2.has("error") and String(e2.error).contains("3 outputs"), "a network with the wrong outputs is refused")
	var e3: Dictionary = Trainer.parse_network_file(JSON.stringify({sensorVersion = 1, network = net.to_json()}))
	t.check(e3.has("error"), "another sensor version is refused")
	t.check(Trainer.parse_network_file("{oops").has("error") and Trainer.parse_network_file("[1, 2]").has("error"), "not JSON / not a network: an error, no crash")
	var crash_meta := {trainedOn = ["rookie-oval"], settings = {laps = 1}}
	t.check(Trainer.saved_wall_rule(crash_meta) == "crash", "files from before the walls setting were trained with walls: crash")


# ================================================================= sensors

func _sensors() -> void:
	t.section("sensors and the driver (the browser version's numbers)")
	var net := fixture_net()
	for id: String in JS_REF:
		var ref: Dictionary = JS_REF[id]
		var track := Tracks.build(id)
		var drv := Sensors.AIDriver.new(net.clone())
		var car := Car.new(track)
		var worst := 0.0
		var exact := true
		for s in 121:
			var ctrl := drv.drive(track, car)
			if s == 0 or s == 120:
				var r: Dictionary = ref["s%d" % s]
				for i in 18:
					var d := absf(drv.inputs[i] - f32(int(r.inputs[i])))
					worst = maxf(worst, d)
					exact = exact and d == 0.0
				for v: Array in [[ctrl.steer, r.steer], [ctrl.throttle, r.throttle]]:
					var d := absf(float(v[0]) - f32(int(v[1])))
					worst = maxf(worst, d)
					exact = exact and d == 0.0
			car.step(track, ctrl, 1.0 / 60.0)
		t.check(worst <= 1e-6, "%s: the 18 inputs and the 2 controls at steps 0 and 120 are the browser's (%s)" % [id, "bit for bit" if exact else "largest difference %s" % worst])
		var dx := maxf(absf(car.x - f64(ref.x)), absf(car.z - f64(ref.z)))
		var dyaw := absf(car.yaw - f64(ref.yaw))
		var dv := absf(car.speed - f64(ref.speed))
		t.check(dx < 1e-6 and dyaw < 1e-9 and dv < 1e-6, "%s: after 2 s the car is where the browser's is (%s)" % [id,
			"bit for bit" if dx == 0.0 and dyaw == 0.0 and dv == 0.0 else "%.2g m" % dx])

	t.section("sensors: ranges and symmetry")
	var tracks: Array = [Tracks.build("hairpin-valley"), Tracks.build("canyon-run")]
	var inputs := PackedFloat32Array()
	inputs.resize(18)
	var rays := PackedFloat32Array()
	rays.resize(9)
	var mirrored := PackedFloat32Array()
	mirrored.resize(18)
	var m2 := PackedFloat32Array()
	m2.resize(18)
	var in_range := true
	var symmetric := true
	var involution := true
	var ctrl := Car.Controls.new()
	var ctrl_m := Car.Controls.new()
	var tmp := PackedFloat32Array()
	tmp.resize(18)
	NeuralNetwork.rng.seed = 5
	var rnd_net := NeuralNetwork.new(PackedInt32Array([18, 12, 2]))
	for tr: BuiltTrack in tracks:
		for k in 40:
			var car := Car.new(tr, (k * 97) % tr.count)
			car.yaw += sin(k * 1.3) * 0.6
			car.vx = sin(car.yaw) * 30.0
			car.vz = cos(car.yaw) * 30.0
			car.forward_speed = 30.0
			car.side_speed = sin(k * 0.7) * 3.0
			car.yaw_rate = cos(k * 0.9) * 0.8
			Sensors.sense(tr, car, inputs, rays)
			for i in 18:
				in_range = in_range and absf(inputs[i]) <= 1.0
			for i in 9:
				in_range = in_range and rays[i] >= 0.0 and rays[i] <= Sensors.SENSOR_RANGE
			Sensors.mirror_inputs(inputs, mirrored)
			Sensors.mirror_inputs(mirrored, m2)
			involution = involution and same_floats(m2, inputs)
			Sensors.drive_network(rnd_net, inputs, tmp, ctrl)
			Sensors.drive_network(rnd_net, mirrored, tmp, ctrl_m)
			symmetric = symmetric and ctrl_m.steer == -ctrl.steer and ctrl_m.throttle == ctrl.throttle
	t.check(in_range, "every input is within -1..1 and every ray within 0..100 m (80 poses on two tracks)")
	t.check(involution, "mirroring the inputs twice gives them back")
	t.check(symmetric, "the driver is exactly left / right symmetric: the mirrored situation steers the other way, same throttle")


# ================================================================= the rules

## One run of a single constant-output car; returns {reason, time, fitness, walls, finished}.
func _one_car(tid: String, walls: String, steer_b: float, thr_b: float, native: bool) -> Dictionary:
	var tr := Trainer.new({tracks = [Tracks.build(tid)], population = population_of([const_net(steer_b, thr_b)]),
		walls = walls, native = native, threads = 1})
	var res := {}
	tr.on_run_end = func(_t: BuiltTrack, _d: Dictionary) -> void:
		var a: Trainer.Agent = tr.agents[0]
		res.merge({reason = a.death_reason, time = tr.sim_time, fitness = a.fitness, walls = tr.wall_cars, first = tr.first_finish,
			ref = tr.ref_time, race_len = tr.race_len, finish = tr.best_times.get(tid, {}).get("finish"),
			metres = maxf(0.0, (maxf(a.car.prog, a.max_prog - 3.0) - a.start_prog) * tr.track.seg_len)}) # (merge: a lambda can't reassign `res`)
	var guard := 0
	while res.is_empty() and guard < 20000:
		tr.step(Trainer.STEP)
		guard += 1
	tr.on_run_end = Callable()
	return res


func _rules() -> void:
	t.section("rules (GDScript simulation)")
	var crash := _one_car("rookie-oval", "crash", 0.0, 5.0, false)
	t.check(crash.reason == "wall" and int(crash.walls) == 1 and float(crash.fitness) > 100.0,
		"walls: crash — straight on at full throttle, the first wall puts the car out (%.1f s, fitness %.0f)" % [crash.time, crash.fitness])
	var ride := _one_car("rookie-oval", "ride", 0.0, 5.0, false)
	t.check(ride.reason == "finished" and int(ride.walls) == 1, "walls: ride — the same car rides the walls round to the finish (%.1f s)" % ride.time)
	if ride.reason == "finished":
		var fin: float = float(ride.finish)
		var expect := 1000.0 * minf(1.0, float(ride.metres) / float(ride.race_len)) + 200.0 + 500.0 * minf(1.5, float(ride.ref) / fin)
		t.check(absf(float(ride.fitness) - expect) < 1e-9 and fin == float(ride.first) and float(ride.fitness) > 1450.0,
			"a finished car scores 1000 × share of the distance + 200 (every gate) + 500 × reference time / its time (%.2f)" % ride.fitness)
	var stall := _one_car("rookie-oval", "ride", 0.0, 0.0, false)
	t.check(stall.reason == "stalled" and absf(float(stall.time) - 3.0) < 0.05 and float(stall.fitness) == 0.0, "no throttle: out as stalled after 3 s with fitness 0")
	var back := _one_car("rookie-oval", "ride", 0.0, -5.0, false)
	t.check(back.reason == "backwards", "reversing: out as backwards (20 m behind its best) after %.1f s" % back.time)

	# the score of a car in progress
	var tr := Trainer.new({tracks = [Tracks.build("hairpin-valley")], population_size = 2, native = false})
	var a: Trainer.Agent = tr.agents[0]
	t.check(tr.score(a) == 0.0, "a car on the grid scores 0")
	a.max_prog = a.start_prog + 103.0 / tr.track.seg_len
	a.car.prog = a.start_prog + 50.0 / tr.track.seg_len
	tr.sim_time = 10.0
	var metres := (a.max_prog - 3.0 - a.start_prog) * tr.track.seg_len
	var expect := 1000.0 * minf(1.0, metres / tr.race_len) + 50.0 * minf(1.0, metres / 10.0 / 50.0)
	t.check(absf(tr.score(a) - expect) < 1e-6, "in progress: 1000 × share of the distance (best progress - 3 samples) + 50 × average speed / 50 m/s")

	if Trainer.native_available():
		t.section("rules (FleetSim)")
		var same := true
		for c: Array in [["rookie-oval", "crash", 5.0], ["rookie-oval", "ride", 5.0], ["rookie-oval", "ride", 0.0], ["rookie-oval", "ride", -5.0], ["hairpin-valley", "crash", 5.0]]:
			var g := _one_car(c[0], c[1], 0.0, c[2], false)
			var n := _one_car(c[0], c[1], 0.0, c[2], true)
			same = same and g.reason == n.reason and g.time == n.time and g.fitness == n.fitness and g.walls == n.walls
		t.check(same, "the same five cars in FleetSim: the same reason, time, fitness and wall count")


# ================================================================= FleetSim

func _fleet_parity() -> void:
	t.section("FleetSim against the GDScript simulation")
	if not Trainer.native_available():
		t.check(true, "FleetSim not loaded (no native library for this platform): only the GDScript simulation is checked")
	else:
		for c: Array in [["rookie-oval", "ride", 6, 31], ["hairpin-valley", "crash", 6, 32]]:
			_lockstep(c[0], c[1], c[2], c[3])
		# 1 thread = 4 threads (the cars are split over the threads; every result the same)
		var hist := []
		var bests := []
		var params := []
		for threads in [1, 4]:
			var tr := Trainer.new({tracks = [Tracks.build("rookie-oval"), Tracks.build("hairpin-valley")], population = population_of(mutated_fixture(60, 77)),
				walls = "ride", native = true, threads = threads})
			NeuralNetwork.rng.seed = 99
			while tr.generation < 2:
				tr.step_many(600)
			hist.append(var_to_bytes(tr.history))
			bests.append(var_to_bytes(tr.best_times))
			params.append(tr.population.all_params())
		t.check(hist[0] == hist[1] and bests[0] == bests[1] and params[0] == params[1],
			"60 cars, 2 tracks, 2 generations: 1 and 4 threads give the same fitness, best times and next population")

	t.section("fallback without the extension")
	var tr := Trainer.new({tracks = [Tracks.build("rookie-oval")], population_size = 6, walls = "crash", native_class = "NoSuchFleetSim"})
	t.check(not tr.is_native() and tr.native_note.contains("GDScript"), "a missing native class: training runs in GDScript, with a note for the screen (\"%s\")" % tr.native_note)
	var guard := 0
	while tr.generation < 1 and guard < 20000:
		tr.step(Trainer.STEP)
		guard += 1
	t.check(tr.generation == 1 and tr.history.size() == 1, "and a generation completes")


## Both simulations side by side, step by step: every car's state and inputs compared every
## 15 steps, then each car's fitness and reason, the generation and the best times.
func _lockstep(tid: String, walls: String, n: int, seed: int) -> void:
	var nets := mutated_fixture(n, seed)
	var gd := Trainer.new({tracks = [Tracks.build(tid)], population = population_of(nets), walls = walls, native = false})
	var nets2: Array = []
	for x: NeuralNetwork in nets:
		nets2.append(x.clone())
	var nat := Trainer.new({tracks = [Tracks.build(tid)], population = population_of(nets2), walls = walls, native = true, threads = 1})
	var runs: Array = [[], []]
	gd.on_run_end = func(_t: BuiltTrack, d: Dictionary) -> void:
		runs[0].append(_run_record(gd, d))
	nat.on_run_end = func(_t: BuiltTrack, d: Dictionary) -> void:
		runs[1].append(_run_record(nat, d))
	var steps := 0
	var states_same := true
	var inputs_same := true
	var compared := 0
	var first := ""
	while gd.generation == 0 and steps < 20000:
		gd.step(Trainer.STEP)
		nat.step(Trainer.STEP)
		steps += 1
		if steps % 15 == 0 and gd.generation == 0:
			nat.sync_agents()
			for k in n:
				var a: Trainer.Agent = gd.agents[k]
				var b: Trainer.Agent = nat.agents[k]
				if not a.alive:
					continue
				compared += 1
				var ok := a.car.x == b.car.x and a.car.y == b.car.y and a.car.z == b.car.z and a.car.yaw == b.car.yaw \
					and a.car.speed == b.car.speed and a.car.prog == b.car.prog and a.alive == b.alive and a.fitness == b.fitness
				if not ok and first == "":
					first = "step %d car %d: x %s / %s" % [steps, k, a.car.x, b.car.x]
				states_same = states_same and ok
				var ins: PackedFloat32Array = nat.fleet.call("get_inputs", k)
				inputs_same = inputs_same and same_floats(ins, a.inputs)
	gd.on_run_end = Callable()
	nat.on_run_end = Callable()
	t.check(states_same and compared > 100, "%s (%d cars, walls %s): every car's state the same at every 15th step (%d compared)%s" % [tid, n, walls, compared, "" if first == "" else ", first difference " + first])
	t.check(inputs_same, "%s: FleetSim's sensor inputs are the GDScript sensors' (bit for bit)" % tid)
	var runs_same: bool = runs[0].size() == 1 and runs[1].size() == 1
	if runs_same:
		var a: Dictionary = runs[0][0]
		var b: Dictionary = runs[1][0]
		runs_same = a.fitness == b.fitness and a.reasons == b.reasons and a.walls == b.walls and a.deaths.size() == b.deaths.size()
		for k: String in a.deaths:
			runs_same = runs_same and int(b.deaths.get(k, -1)) == int(a.deaths[k])
	t.check(runs_same, "%s: each car's fitness (bit for bit) and reason, the outs and the wall count are the same" % tid)
	t.check(var_to_bytes(gd.history) == var_to_bytes(nat.history) and var_to_bytes(gd.best_times) == var_to_bytes(nat.best_times),
		"%s: the same generation best / average and best times (%s)" % [tid, str(gd.history)])


## A track run's results (exact numbers) for comparing two simulations.
static func _run_record(tr: Trainer, deaths: Dictionary) -> Dictionary:
	var fit := PackedFloat64Array()
	var reasons := PackedStringArray()
	for a in tr.agents:
		fit.append(a.fitness)
		reasons.append(a.death_reason)
	return {fitness = fit, reasons = reasons, deaths = deaths.duplicate(), walls = tr.wall_cars}


# ================================================================= training

func _training() -> void:
	t.section("training improves")
	if Trainer.native_available():
		NeuralNetwork.rng.seed = 4
		var tr := Trainer.new({tracks = [Tracks.build("rookie-oval")], population_size = 40, walls = "crash", native = true, threads = 0})
		var t0 := Time.get_ticks_msec()
		while tr.generation < 12:
			tr.step_many(600)
		var h := tr.history
		var fin: Variant = tr.best_times.get("rookie-oval", {}).get("finish")
		t.check(tr.best_fitness > float(h[0].best) + 300.0 and fin != null,
			"FleetSim: 40 random drivers on rookie-oval (walls: crash), 12 generations: best %.0f -> %.0f, first finish %s (%.1f s)" % [
				h[0].best, tr.best_fitness, UiFormat.time(fin), (Time.get_ticks_msec() - t0) / 1000.0])
		var non_decreasing := true
		for k in range(1, h.size()):
			non_decreasing = non_decreasing and float(h[k].best) >= float(h[k - 1].best)
		t.check(non_decreasing, "the generation best never drops (the elite is kept and the simulation is deterministic)")
		var parsed := Trainer.parse_network_file(JSON.stringify(tr.export_best()))
		t.check(not parsed.has("error") and absf(float(parsed.meta.fitness) - tr.best_fitness) < 1e-6 and int(parsed.meta.generation) == 12,
			"the exported best network loads back with its fitness and generation")
	NeuralNetwork.rng.seed = 6
	var gd := Trainer.new({tracks = [Tracks.build("rookie-oval")], population_size = 10, walls = "crash", native = false})
	var t1 := Time.get_ticks_msec()
	while gd.generation < 4:
		gd.step(Trainer.STEP)
	t.check(gd.history.size() == 4 and gd.best_fitness >= float(gd.history[0].best),
		"GDScript: 10 drivers, 4 generations: best %.0f -> %.0f (%.1f s)" % [gd.history[0].best, gd.best_fitness, (Time.get_ticks_msec() - t1) / 1000.0])


# ================================================================= the training screen

## The parts of the game the training screen uses (game/app.gd provides the real ones).
class FakeApp:
	extends Node
	var world: World
	var ui: UiRoot
	var input: MenuInput
	var tracks_shown := 0

	func _init() -> void:
		world = World.new()
		add_child(world)
		ui = UiRoot.new()
		add_child(ui)
		input = ui.input

	func show_track(tr: BuiltTrack) -> void:
		tracks_shown += 1
		world.show_track(tr)


func _train_screen() -> void:
	t.section("training screen (modes/train_mode.gd) with a stand-in game")
	var prev_save := SaveData.path
	SaveData.use_file("user://test_ai_save.json")
	var app := FakeApp.new()
	t.tree.root.add_child(app)
	var saved: Array = []
	var asked: Array = []
	var make := func() -> Node:
		var m: Node = TrainModeScript.new()
		m.setup(app, {track_index = 0, network = {}})
		m.file_dir = "user://test_ai_networks"
		m.network_saved.connect(func(n: Dictionary) -> void: saved.append(n))
		m.watch_requested.connect(func(tr: BuiltTrack, net: NeuralNetwork) -> void: asked.append(["watch", tr.id, net.sizes]))
		app.add_child(m)
		m.enter()
		return m
	TrainModeScript.session = null
	var mode: Node = make.call()
	var d: Control = mode.get("dash")
	t.check(d.setup_box.visible and d.ticked_tracks() == [0], "it opens on the setup form with the menu's track ticked")
	d.pop.value = 12
	d.press(d.start_btn)
	var s: Object = TrainModeScript.session
	var tr: Trainer = s.get("trainer")
	t.check(tr != null and tr.population.size() == 12 and d.run_box.visible, "Start training: a population of 12 and the run's dashboard")
	t.check(String(s.get("note")).begins_with("New population of 12") and (tr.is_native() or String(s.get("note")).contains("GDScript")),
		"the note says what started (and that it runs in GDScript when the extension is missing)")
	for k in 30:
		mode.update(1.0 / 60.0)
	t.check(tr.steps_done() == 30, "1×: one physics step per 1/60 s frame")
	d.press(d.speed_segs["6"])
	for k in 10:
		mode.update(1.0 / 60.0)
	t.check(tr.steps_done() == 90 or not tr.is_native(), "Fast: six steps per frame (%d steps)" % tr.steps_done())
	d.press(d.speed_segs["max"])
	mode.update(1.0 / 60.0)
	t.check(mode.get("_max") != null, "Max: the session trains on a background thread")
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1500:
		OS.delay_msec(50)
		mode.update(0.05)
	d.press(d.pause_btn)
	t.check(mode.get("_max") == null and bool(s.get("paused")), "Pause takes the session back from the thread")
	var hist: Array = s.get("history")
	t.check(tr.steps_done() > 400 and hist.size() == tr.history.size(), "it trained meanwhile (%d steps, generation %d) and the chart has every generation" % [tr.steps_done(), tr.generation])
	mode.update(1.0 / 60.0)
	t.check(d.stat_values.generation.text == str(tr.generation) and d.run_line.text.begins_with("This run:"), "the stats show the session (generation %s)" % d.stat_values.generation.text)
	d.press(d.save_btn)
	t.check(SaveData.load_network() is Dictionary and saved.size() >= 1 and not Trainer.parse_network_file(SaveData.load_network()).has("error"),
		"Save best network: in the save file, and the game is told (network_saved)")
	d.press(d.watch_btn)
	t.check(asked.size() == 1 and asked[0][0] == "watch", "Watch best asks the game to show the best network driving")
	mode.exit()
	mode.queue_free()
	# a new screen resumes the session
	var mode2: Node = make.call()
	var d2: Control = mode2.get("dash")
	t.check(TrainModeScript.session.trainer == tr and d2.run_box.visible, "a new training screen resumes the session (after Watch / Race / the menu)")
	d2.press(d2.stop_btn)
	t.check(TrainModeScript.session.trainer == null and d2.setup_box.visible, "Stop ends the session: back to the setup form")
	mode2.load_network_text("{not a network")
	t.check(String(TrainModeScript.session.note).begins_with("Could not load") and TrainModeScript.session.trainer == null, "loading a bad file: a note, nothing else changes")
	var before := saved.size()
	mode2.load_network_text(fixture_text)
	var tr2: Trainer = TrainModeScript.session.trainer
	t.check(tr2 != null and Array(tr2.sizes) == [18, 12, 2] and saved.size() == before + 1
		and String(TrainModeScript.session.note).begins_with("Loaded network (18-12-2)"), "loading a network file: kept as the saved network, training continues from it")
	d2.press(d2.stop_btn)
	# the gamepad: the highlight starts on Start training, A presses it
	app.input.pad_active = true
	app.input.press("PadA")
	mode2.update(1.0 / 60.0)
	t.check(TrainModeScript.session.trainer != null and d2.run_box.visible, "gamepad: A on the highlighted Start training starts a session")
	app.input.press("PadB")
	var left: Array = []
	mode2.exit_requested.connect(func() -> void: left.append(true))
	mode2.update(1.0 / 60.0)
	t.check(left.size() == 1, "gamepad: B asks to go back to the menu")
	mode2.exit()
	mode2.queue_free()
	app.queue_free()
	TrainModeScript.session = null
	# clean up the test files
	SaveData.use_file(prev_save)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_ai_save.json"))
	var dir := DirAccess.open("user://test_ai_networks")
	if dir != null:
		for f in dir.get_files():
			dir.remove(f)
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_ai_networks"))
