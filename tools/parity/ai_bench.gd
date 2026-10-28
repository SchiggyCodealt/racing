extends SceneTree
## ai_bench.gd: AI training speed in Godot on the population tools/parity/ai_bench.mjs wrote
## (the JS side prints its own numbers):
##   godot --headless --path <copy> --script res://tools/parity/ai_bench.gd -- <bench.json> [threads=1,4] [gdscript]
## One generation of the same networks on the same tracks, timed, with FleetSim on each
## thread count given (and with the GDScript path when "gdscript" is given: slow).
## Prints car steps per second and the real-time factor (simulated seconds per second).

const HexJson = preload("res://tools/parity/hex_json.gd")


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var data: Dictionary = HexJson.decode(JSON.parse_string(FileAccess.get_file_as_string(args[0])))
	var thread_list: PackedStringArray = (args[1] if args.size() > 1 else "1").split(",")
	var tracks: Array = []
	for id: Variant in data.tracks:
		tracks.append(Tracks.build(String(id)))
	var runs: Array = []
	if args.has("gdscript"):
		runs.append(0)
	for t in thread_list:
		runs.append(int(t))
	for threads: int in runs:
		var sizes := PackedInt32Array(data.sizes)
		var params := PackedFloat32Array(data.params)
		var pop := Population.new({sizes = sizes, mutation_rate = 0.1})
		var per: int = NeuralNetwork.params_for(sizes)
		for k in int(data.n):
			pop.genomes.append(Population.Genome.new(NeuralNetwork.from_params(sizes, params, k * per)))
		var tr := Trainer.new({tracks = tracks, population = pop, native = threads > 0, threads = maxi(1, threads), walls = data.walls})
		var t0: int = Time.get_ticks_usec()
		while tr.generation == 0:
			tr.step_many(60)
		var secs: float = (Time.get_ticks_usec() - t0) / 1e6
		print("%s: %d cars: %d steps, %d car steps in %.2f s = %.0f car steps/s, %.1fx real time; generation best %.1f avg %.1f" % [
			"FleetSim %d thread(s)" % threads if threads > 0 else "GDScript", int(data.n), tr.steps_done(), tr.car_steps(), secs,
			tr.car_steps() / secs, tr.steps_done() / 60.0 / secs, tr.history[0].best, tr.history[0].avg])
	quit()
