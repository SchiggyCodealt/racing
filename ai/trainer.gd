class_name Trainer
extends RefCounted
## trainer.gd: a port of web/src/ai/trainer.js (and the parts of trainWorker.js the
## Godot training screen needs).
## ------------------------------------------------------------------
## Runs a generation of AI cars on the track(s) and scores them. Pure
## simulation (no rendering): the training mode calls step() / step_many() as
## often as it likes, from the main thread or from a background thread (Max).
##
## One generation = every selected track driven in turn by the whole
## population ("track rotation"). A car's fitness is its average score over
## those tracks.
##
## Score for one track run (0 .. ~1950):
##   1000 × fraction of the race distance covered
## +  200 × fraction of checkpoints reached
## +  finished ? 500 × (reference time / your time, capped at 1.5)
##             : 50 × average speed / 50 m/s (small tie-breaker)
##
## Walls (setting `walls`):
##   "ride"  (default) a car may hit and scrape the walls and keeps driving,
##           so it can learn where a wall beats braking (a hit costs speed by
##           how hard it is, scraping slows the car further).
##   "crash" touching a wall puts the car out, so it learns clean lines.
##
## A car is out of the run when it
##   - touches a wall, with walls "crash",
##   - stalls (less than 3 m of progress in RULES.stall_time seconds),
##   - drives backwards (RULES.backwards metres behind its best progress),
##   - is too slow between two checkpoints: it must reach the next gate
##     within (gate distance / RULES.min_pace) + RULES.gate_slack seconds,
##   - is still driving well after the first car finished
##     (RULES.finish_cutoff × the winner's time + RULES.finish_slack), or
##   - runs out of time (race distance / RULES.min_pace + RULES.time_slack).
## Cars that drop out keep the score they had reached.
##
## Two ways to simulate a track run, with the same results:
##   - native: the C++ FleetSim (native/, a GDExtension) steps every car in one call
##     (sensors + network + car physics + the rules above), optionally on several
##     threads. Used whenever the extension is loaded (Trainer.native_available()).
##   - GDScript: the agents below with sim/car.gd, sim/race.gd and ai/sensors.gd,
##     exactly the JS step() loop. The fallback when the extension is missing, and
##     the reference the native path is tested against (tests/test_ai.gd).
## Either way `agents` holds one Agent per car for the view: with the native path
## its car / prev / fitness are filled by sync_agents() (call it before drawing).
##
## Use:
##   var tr := Trainer.new({tracks = [Tracks.build("rookie-oval")]})   # see DEFAULT_TRAINING
##   tr.on_generation = func(entry): ...        # {gen, best, avg}, after each generation
##   tr.step_many(6)                            # fixed 1/60 s steps
##   tr.export_best()                           # the network file (web format, with its car)
## The car: opts.car_id (default "racer", like the web game; any id of sim/cars.gd) picks the
## spec every car drives, on both simulation paths (FleetSim gets the spec as data). The
## sensors scale the speed by that car's top speed (ai/sensors.gd). Network files record the
## car they were trained with ("car"; a file without one is a Racer network: network_car()).

const STEP: float = 1.0 / 60.0

const DEFAULT_TRAINING: Dictionary = {
	population_size = 80,
	mutation_rate = 0.1,
	hidden = [12],
	laps = 1,
	walls = "ride", # "ride" = cars keep going after a wall hit, "crash" = a wall hit puts the car out
	car_id = "racer",
}

## Training wall rules (see the header): value -> label in the training form's Walls menu.
const WALL_RULES: Dictionary = {ride = "Ride them (car keeps going)", crash = "Crash out (car is out)"}

## Elimination rules (see the header). Times in seconds, distances in metres, speeds in m/s.
const RULES: Dictionary = {
	stall_time = 3.0,
	backwards = 20.0,
	min_pace = 8.0,
	gate_slack = 10.0,
	time_slack = 20.0,
	finish_cutoff = 1.25,
	finish_slack = 5.0,
	ref_speed = 50.0, # m/s: finishing at this average speed earns the full 500 bonus
}

## Format identifier and version of saved network files.
const NETWORK_FORMAT: String = "trackmania-lite-network"
const NETWORK_FILE_VERSION: int = 2

## Why a car left the run (FleetSim reports these codes; 0 = still driving).
const REASONS: PackedStringArray = ["", "finished", "wall", "backwards", "stalled", "too slow", "cut off", "time"]


## One car of the run in progress.
class Agent:
	var index: int = 0
	var net: NeuralNetwork
	var car: Car
	## pose before the last step {x, y, z, yaw} (for smooth rendering)
	var prev: Dictionary = {}
	var race: RaceState
	var alive: bool = true
	var finished: bool = false
	var fitness: float = 0.0
	var start_prog: float = 0.0
	var max_prog: float = 0.0
	var last_improve: float = 0.0
	var gate_deadline: float = 0.0
	var inputs := PackedFloat32Array()
	var rays := PackedFloat32Array()
	var death_reason: String = ""
	var touched_wall: bool = false


var cfg: Dictionary = {}
var tracks: Array[BuiltTrack] = []
var population: Population
var sizes: PackedInt32Array = PackedInt32Array()
var generation: int = 0
## [{gen, best, avg}]
var history: Array[Dictionary] = []
## track id -> {lap, finish} (null when none yet)
var best_times: Dictionary = {}
## reason -> count, for the run in progress
var deaths: Dictionary = {}
## cars that touched a wall in the run in progress
var wall_cars: int = 0
## (track) -> void, when a track run starts
var on_track_change: Callable
## (entry {gen, best, avg}) -> void, after each generation
var on_generation: Callable
## (track, deaths {reason: count}) -> void, after each track run
var on_run_end: Callable

var track: BuiltTrack
var track_pos: int = 0
var race_len: float = 0.0
var ref_time: float = 0.0
var time_limit: float = 0.0
var sim_time: float = 0.0
## time of the first finish of this run, INF until then (the JS null)
var first_finish: float = INF
var gen_scores := PackedFloat32Array()
var agents: Array[Agent] = []
var spec: CarSpec

## the FleetSim (native path) or null (GDScript path)
var fleet: Object = null
## why the native path is not used ("" when it is)
var native_note: String = ""
var _fleet_track: BuiltTrack = null
var _fleet_nets_gen: int = -1
var _synced_step: int = -1
var _steps: int = 0
var _gd_car_steps: int = 0

var _ctrl := Car.Controls.new()
var _mirrored := PackedFloat32Array()


## opts: tracks (Array of BuiltTrack, at least one), population_size, mutation_rate,
## hidden (Array of hidden layer sizes), laps, walls ("ride" | "crash"), car_id,
## seed (NeuralNetwork to continue from), seed_meta (the saved file's data),
## population (a Population to train as it is, instead of a new one),
## native (true = use FleetSim when it is available (default), false = GDScript),
## threads (FleetSim threads, default 1; 0 = one per core, at most 8),
## native_class (tests: the class to use instead of "FleetSim"; a missing one = the fallback).
func _init(opts: Dictionary) -> void:
	for k: String in DEFAULT_TRAINING:
		cfg[k] = opts.get(k, DEFAULT_TRAINING[k])
	if not WALL_RULES.has(String(cfg.walls)):
		cfg.walls = DEFAULT_TRAINING.walls
	cfg.walls = String(cfg.walls)
	cfg.laps = int(cfg.laps)
	cfg.population_size = int(cfg.population_size)
	cfg.mutation_rate = float(cfg.mutation_rate)
	cfg.car_id = String(cfg.car_id)
	if not Cars.has_car(cfg.car_id):
		cfg.car_id = Cars.DEFAULT_CAR
	for t: Variant in opts.tracks:
		tracks.append(t as BuiltTrack)
	spec = Cars.spec(cfg.car_id)
	_mirrored.resize(Sensors.INPUT_COUNT)
	var seed: NeuralNetwork = opts.get("seed")
	var meta: Variant = opts.get("seed_meta")
	var hidden: Array = cfg.hidden
	if seed != null:
		sizes = seed.sizes.duplicate()
	else:
		sizes = PackedInt32Array([Sensors.INPUT_COUNT])
		for h: Variant in hidden:
			sizes.append(int(h))
		sizes.append(Sensors.OUTPUT_COUNT)
	# A saved fitness only counts as "best ever" when it was scored with the same car, on the same
	# tracks, laps and wall rule. A network trained with another car starts a new history (the
	# chart, the generation count) for this car; with the same car it carries on.
	var same_car: bool = network_car(meta) == cfg.car_id
	var same_task: bool = false
	if meta is Dictionary and (meta as Dictionary).get("trainedOn") is Array:
		var ids: PackedStringArray = []
		for t in tracks:
			ids.append(t.id)
		var on: PackedStringArray = []
		for v: Variant in meta.trainedOn:
			on.append(str(v))
		var settings: Variant = meta.get("settings")
		var laps: Variant = settings.get("laps", 1) if settings is Dictionary else 1
		same_task = same_car and ",".join(on) == ",".join(ids) and JsMath.same(laps, cfg.laps) and saved_wall_rule(meta) == cfg.walls
	var seed_fitness: Variant = null
	if same_task and _is_num(meta.get("fitness")):
		seed_fitness = float(meta.fitness)
	if opts.get("population") is Population:
		# continue with this population (tests: the same networks on both simulation paths)
		population = opts.population
		sizes = population.sizes.duplicate()
		cfg.population_size = population.size()
	else:
		population = Population.new({size = cfg.population_size, sizes = sizes, mutation_rate = cfg.mutation_rate,
			seed = seed, seed_fitness = seed_fitness})
	if meta is Dictionary and same_car:
		generation = int(meta.get("generation", 0)) if _is_num(meta.get("generation")) else 0
		if meta.get("history") is Array:
			for h: Variant in meta.history:
				if h is Dictionary and _is_num(h.get("gen")) and _is_num(h.get("best")) and _is_num(h.get("avg")):
					history.append({gen = int(h.gen), best = float(h.best), avg = float(h.avg)})
	if bool(opts.get("native", true)):
		_start_native(int(opts.get("threads", 1)), String(opts.get("native_class", "FleetSim")))
	_prepare_tracks()
	begin_generation()


static func _is_num(v: Variant) -> bool:
	return (v is float or v is int) and is_finite(float(v))


# ---- the native fast path (FleetSim) --------------------------------------------------

## True when the FleetSim GDExtension (native/) is loaded.
static func native_available(cls: String = "FleetSim") -> bool:
	return ClassDB.class_exists(cls) and ClassDB.can_instantiate(cls)


## `cls`: the native class (tests name a missing one to check the fallback).
func _start_native(threads: int, cls: String = "FleetSim") -> void:
	if not native_available(cls):
		native_note = "The fast training extension (native/, bin/) is not loaded: training runs in GDScript, which is much slower."
		return
	fleet = ClassDB.instantiate(cls)
	if fleet == null:
		native_note = "The fast training extension could not start: training runs in GDScript, which is much slower."
		return
	fleet.call("set_spec", Trainer.spec_data(spec))
	fleet.call("set_rules", rules_data())
	set_threads(threads)


## Number of native threads (0 = one per core, at most 8). No effect on the GDScript path.
func set_threads(n: int) -> void:
	if fleet != null:
		if n <= 0:
			n = clampi(OS.get_processor_count(), 1, 8)
		fleet.call("set_threads", n)


func is_native() -> bool:
	return fleet != null


## Physics steps simulated so far (the whole population advances one step per step).
func steps_done() -> int:
	return _steps


## Car steps simulated so far (one car through one step: sensors, network, physics, rules).
func car_steps() -> int:
	return int(fleet.call("get_car_steps")) if fleet != null else _gd_car_steps


## The numbers FleetSim needs from the rules and settings (the sensors' speed scale is the
## car's own top speed, part of its spec).
func rules_data() -> Dictionary:
	var d: Dictionary = RULES.duplicate()
	d.walls_crash = cfg.walls == "crash"
	d.laps = cfg.laps
	return d


## A car spec as plain data for FleetSim: the spec fields with their JS names plus the
## derived constants (the same numbers sim/car.gd uses).
static func spec_data(s: CarSpec) -> Dictionary:
	var d: Dictionary = s.to_dict()
	d.erase("torque")
	d.erase("id")
	d.gears = PackedFloat64Array(s.gears)
	d.wheelbase = s.wheelbase
	d.core = s.core
	d.peakSlip = s.peak_slip
	d.pacSlope0 = s.pac_slope0
	d.peakSteer = s.peak_steer
	d.torqueRpm = s.torque_rpm
	d.torqueNm = s.torque_nm
	return d


## A built track as plain data for FleetSim: geometry, the physics tables, the wall grid,
## the gates for `laps` laps and the sensors' heading tables (all computed by the GDScript).
static func track_data(t: BuiltTrack, laps: int) -> Dictionary:
	Car.track_phys(t)
	var h: Sensors.Headings = Sensors.track_headings(t)
	var g: Collision.WallGrid = t.grid
	var gates: Array[Dictionary] = TrackBuilder.get_gates(t, laps if t.closed else 1)
	var gate_prog := PackedFloat64Array()
	var gate_kind := PackedInt32Array()
	for gt in gates:
		gate_prog.append(float(gt.prog))
		gate_kind.append(0 if gt.kind == "cp" else (1 if gt.kind == "lap" else 2))
	return {
		id = t.id, closed = t.closed, N = t.N, count = t.count, seg_count = t.seg_count, seg_len = t.seg_len,
		length = t.length, start_idx = t.start_idx, finish_idx = t.finish_idx,
		px = t.px, py = t.py, pz = t.pz, tx = t.tx, tz = t.tz, nx = t.nx, nz = t.nz, hw = t.hw, bank = t.bank,
		phys_slope = t.phys_slope, phys_kv = t.phys_kv,
		grid_cell = g.cell, grid_min_x = g.min_x, grid_min_z = g.min_z, grid_cols = g.cols, grid_rows = g.rows,
		grid_seg_d = g.seg_d, grid_inward = g.inward, grid_cell_start = g.cell_start, grid_cell_segs = g.cell_segs,
		grid_seg_cell = g.seg_cell,
		gate_prog = gate_prog, gate_kind = gate_kind, race_len = TrackBuilder.race_length(t, laps if t.closed else 1),
		head_theta = h.theta, head_total = h.total, head_n = h.n, head_len = h.len, head_sparse = h.sparse,
	}


## Fill the lazily cached per-track data now (gates for the training laps, physics
## tables, heading tables), so a background thread only ever reads the tracks.
func _prepare_tracks() -> void:
	for t in tracks:
		Car.track_phys(t)
		Sensors.track_headings(t)
		TrackBuilder.get_gates(t, cfg.laps if t.closed else 1)


# ---- generations and track runs --------------------------------------------------------

var best_fitness: float:
	get:
		return population.best_ever.fitness if population.best_ever != null else 0.0

var best_net: NeuralNetwork:
	get:
		return population.best_ever.net if population.best_ever != null else null


func alive_count() -> int:
	if fleet != null:
		return int(fleet.call("alive_count"))
	var n: int = 0
	for a in agents:
		if a.alive:
			n += 1
	return n


func begin_generation() -> void:
	track_pos = 0
	gen_scores = PackedFloat32Array()
	gen_scores.resize(population.size())
	begin_track_run()


func begin_track_run() -> void:
	var t: BuiltTrack = use_track(tracks[track_pos])
	sim_time = 0.0
	first_finish = INF
	deaths = {}
	wall_cars = 0
	agents = []
	for i in population.size():
		agents.append(new_agent(population.genomes[i], i))
	if fleet != null:
		if _fleet_track != t:
			fleet.call("set_track", Trainer.track_data(t, cfg.laps))
			_fleet_track = t
		if _fleet_nets_gen != generation:
			fleet.call("set_networks", sizes, population.all_params(), population.size())
			_fleet_nets_gen = generation
		fleet.call("begin_run")
		_synced_step = -1
	else:
		for a in agents:
			a.gate_deadline = gate_deadline(a, a.start_prog, 0.0)
	if on_track_change.is_valid():
		on_track_change.call(t)


## Make `t` the one driven, with its race length and limits.
func use_track(t: BuiltTrack) -> BuiltTrack:
	track = t
	race_len = TrackBuilder.race_length(t, cfg.laps if t.closed else 1)
	ref_time = race_len / RULES.ref_speed
	time_limit = race_len / RULES.min_pace + RULES.time_slack
	return t


## A car on the start line, driven by genome g.
func new_agent(g: Population.Genome, i: int) -> Agent:
	var a := Agent.new()
	var car := Car.new(track, -1, spec)
	a.index = i
	a.net = g.net
	a.car = car
	a.prev = {x = car.x, y = car.y, z = car.z, yaw = car.yaw}
	a.race = RaceState.new(track, cfg.laps)
	a.start_prog = car.prog
	a.max_prog = car.prog
	a.inputs.resize(Sensors.INPUT_COUNT)
	a.rays.resize(Sensors.NR)
	return a


## Time by which a car that passed a gate at `from_prog` at time `now` must reach the next one.
func gate_deadline(a: Agent, from_prog: float, now: float) -> float:
	var g: Dictionary = a.race.gates[mini(a.race.next_gate, a.race.gates.size() - 1)]
	var metres: float = maxf(0.0, (float(g.prog) - from_prog) * track.seg_len)
	return now + metres / RULES.min_pace + RULES.gate_slack


## Advance `n` fixed steps (1/60 s), crossing run and generation ends as needed.
func step_many(n: int) -> void:
	if fleet == null:
		for k in n:
			step(STEP)
		return
	while n > 0:
		var done: int = int(fleet.call("step", n, STEP))
		n -= done
		_steps += done
		if bool(fleet.call("is_run_over")):
			_merge_native_times()
			_end_native_run()
		elif done == 0:
			break


## Advance the whole population by one fixed step (JS Trainer.step).
func step(dt: float) -> void:
	if fleet != null:
		var done: int = int(fleet.call("step", 1, dt))
		_steps += done
		if bool(fleet.call("is_run_over")):
			_merge_native_times()
			_end_native_run()
		return
	var t: BuiltTrack = track
	sim_time += dt
	var now: float = sim_time
	var cutoff: float = first_finish * RULES.finish_cutoff + RULES.finish_slack if first_finish != INF else INF
	var any_alive: bool = false
	var seg_len: float = t.seg_len
	var crash: bool = cfg.walls == "crash"
	for a in agents:
		if not a.alive:
			continue
		var car: Car = a.car
		var p: Dictionary = a.prev
		p.x = car.x
		p.y = car.y
		p.z = car.z
		p.yaw = car.yaw
		_gd_car_steps += 1
		Sensors.sense(t, car, a.inputs, a.rays)
		Sensors.drive_network(a.net, a.inputs, _mirrored, _ctrl)
		car.step(t, _ctrl, dt)
		var events: Array[Dictionary] = a.race.update(car, dt)
		if not events.is_empty():
			for ev in events:
				record_time(t, ev)
			if not a.race.finished:
				a.gate_deadline = gate_deadline(a, float(a.race.gates[a.race.next_gate - 1].prog), now)

		if car.prog > a.max_prog + 3.0:
			a.max_prog = car.prog
			a.last_improve = now
		a.fitness = score(a)
		if car.hit_wall and not a.touched_wall:
			a.touched_wall = true
			wall_cars += 1

		var reason: String = ""
		if a.race.finished:
			reason = "finished"
			a.finished = true
			if first_finish == INF:
				first_finish = a.race.finish_time
		elif car.hit_wall and crash:
			reason = "wall"
		elif (a.max_prog - car.prog) * seg_len > RULES.backwards:
			reason = "backwards"
		elif now - a.last_improve > RULES.stall_time:
			reason = "stalled"
		elif now > a.gate_deadline:
			reason = "too slow"
		elif now > cutoff:
			reason = "cut off"
		elif now > time_limit:
			reason = "time"
		if reason != "":
			a.alive = false
			a.death_reason = reason
			deaths[reason] = int(deaths.get(reason, 0)) + 1
			p.x = car.x # parked: no interpolation wobble
			p.y = car.y
			p.z = car.z
			p.yaw = car.yaw
		else:
			any_alive = true
	_steps += 1
	if not any_alive:
		end_track_run()


func score(a: Agent) -> float:
	var metres: float = maxf(0.0, (maxf(a.car.prog, a.max_prog - 3.0) - a.start_prog) * track.seg_len)
	var frac: float = minf(1.0, metres / race_len)
	var f: float = 1000.0 * frac + (200.0 * a.race.next_gate) / a.race.total_gates()
	if a.race.finished:
		f += 500.0 * minf(1.5, ref_time / a.race.finish_time)
	elif sim_time > 1.0:
		f += 50.0 * minf(1.0, metres / sim_time / RULES.ref_speed)
	return f


func record_time(t: BuiltTrack, ev: Dictionary) -> void:
	if not best_times.has(t.id):
		best_times[t.id] = {lap = null, finish = null}
	var rec: Dictionary = best_times[t.id]
	if ev.has("lap_time") and (rec.lap == null or float(ev.lap_time) < float(rec.lap)):
		rec.lap = float(ev.lap_time)
	if ev.kind == "finish" and (rec.finish == null or float(ev.time) < float(rec.finish)):
		rec.finish = float(ev.time)


func end_track_run() -> void:
	for a in agents:
		gen_scores[a.index] += a.fitness
	if on_run_end.is_valid():
		on_run_end.call(track, deaths)
	track_pos += 1
	if track_pos < tracks.size():
		begin_track_run()
	else:
		end_generation()


func end_generation() -> void:
	var genomes: Array[Population.Genome] = population.genomes
	for i in genomes.size():
		genomes[i].fitness = gen_scores[i] / tracks.size()
	var stats: Dictionary = population.evolve()
	var entry: Dictionary = {gen = generation, best = float(stats.best), avg = float(stats.avg)}
	history.append(entry)
	generation += 1
	if on_generation.is_valid():
		on_generation.call(entry)
	begin_generation()


# ---- native run bookkeeping ---------------------------------------------------------------

## The native run ended: take its scores, deaths and wall count, then go on like end_track_run().
func _end_native_run() -> void:
	sync_agents(false)
	end_track_run()


## Best lap / finish times of the native run so far into best_times (like record_time, the
## track's entry exists once a car passed any gate, even without a lap or finish yet).
func _merge_native_times() -> void:
	if fleet == null:
		return
	var lap: float = float(fleet.call("get_best_lap"))
	var fin: float = float(fleet.call("get_best_finish"))
	if lap == INF and fin == INF:
		if not best_times.has(track.id) and bool(fleet.call("get_any_gate")):
			best_times[track.id] = {lap = null, finish = null}
		return
	if not best_times.has(track.id):
		best_times[track.id] = {lap = null, finish = null}
	var rec: Dictionary = best_times[track.id]
	if lap != INF and (rec.lap == null or lap < float(rec.lap)):
		rec.lap = lap
	if fin != INF and (rec.finish == null or fin < float(rec.finish)):
		rec.finish = fin


## Native path: copy the run's state from FleetSim into `agents` (fitness, alive, death
## reasons, run time, deaths, best times; with `cars` also every car's pose and effect fields and the
## pose before the last step, for drawing). No-op on the GDScript path.
func sync_agents(cars: bool = true) -> void:
	if fleet == null:
		return
	_merge_native_times() # (the best lap / finish so far, live like the JS record_time)
	sim_time = float(fleet.call("get_sim_time"))
	first_finish = float(fleet.call("get_first_finish"))
	wall_cars = int(fleet.call("get_wall_cars"))
	deaths = fleet.call("get_deaths")
	var fit: PackedFloat64Array = fleet.call("get_fitness")
	var reasons: PackedInt32Array = fleet.call("get_reasons")
	for a in agents:
		a.fitness = fit[a.index]
		var r: int = reasons[a.index]
		a.alive = r == 0
		a.death_reason = REASONS[r]
		a.finished = r == 1
	if not cars or _synced_step == _steps:
		return
	_synced_step = _steps
	var st: PackedFloat64Array = fleet.call("get_view_states")
	var nf: int = int(fleet.call("view_stride"))
	for a in agents:
		var o: int = a.index * nf
		var c: Car = a.car
		c.x = st[o]
		c.y = st[o + 1]
		c.z = st[o + 2]
		c.yaw = st[o + 3]
		c.pitch = st[o + 4]
		c.roll = st[o + 5]
		c.steer_angle = st[o + 6]
		c.wheel_rot = st[o + 7]
		c.vx = st[o + 8]
		c.vz = st[o + 9]
		c.speed = st[o + 10]
		c.forward_speed = st[o + 11]
		c.side_speed = st[o + 12]
		c.steer = st[o + 13]
		c.throttle = st[o + 14]
		c.slip = st[o + 15]
		c.grounded = st[o + 16] != 0.0
		c.drifting = st[o + 17] != 0.0
		c.braking = st[o + 18] != 0.0
		c.hit_wall = st[o + 19] != 0.0
		c.wall_hits = int(st[o + 20])
		c.wall_impact = st[o + 21]
		c.wall_scrape = st[o + 22]
		c.wall_x = st[o + 23]
		c.wall_y = st[o + 24]
		c.wall_z = st[o + 25]
		c.wall_nx = st[o + 26]
		c.wall_nz = st[o + 27]
		c.idx = int(st[o + 28])
		c.prog = st[o + 29]
		c.yaw_rate = st[o + 30]
		var p: Dictionary = a.prev
		p.x = st[o + 31]
		p.y = st[o + 32]
		p.z = st[o + 33]
		p.yaw = st[o + 34]


## The shown car's sensor rays (m) and its network's activations of the last step, into
## agent.rays and agent.net.acts (native path; the GDScript path has them already).
func sync_shown(a: Agent) -> void:
	if fleet == null or a == null:
		return
	var rays: PackedFloat32Array = fleet.call("get_rays", a.index)
	for k in mini(rays.size(), a.rays.size()):
		a.rays[k] = rays[k]
	var acts: PackedFloat32Array = fleet.call("get_acts", a.index)
	var o: int = 0
	for l in a.net.acts.size():
		var layer: PackedFloat32Array = a.net.acts[l]
		for i in layer.size():
			if o < acts.size():
				layer[i] = acts[o]
			o += 1


# ---- what the dashboard shows -----------------------------------------------------------------

## Index of the alive car with the highest live fitness (or the best overall).
func leader_index() -> int:
	var best: int = -1
	var bf: float = -INF
	var best_any: int = 0
	var bfa: float = -INF
	for a in agents:
		if a.fitness > bfa:
			bfa = a.fitness
			best_any = a.index
		if a.alive and a.fitness > bf:
			bf = a.fitness
			best = a.index
	return best if best >= 0 else best_any


## The numbers the training dashboard shows for the run in progress (plain data;
## the native path: call sync_agents() first).
func live_stats() -> Dictionary:
	var leader: float = 0.0
	var alive: int = 0
	for a in agents:
		leader = maxf(leader, a.fitness)
		if a.alive:
			alive += 1
	return {
		generation = generation,
		alive = alive,
		size = population.size(),
		best_fitness = best_fitness if population.best_ever != null else null,
		leader_fitness = leader,
		track_pos = track_pos,
		sim_time = sim_time,
		deaths = deaths.duplicate(),
		wall_cars = wall_cars,
		best_times = best_times.duplicate(true),
	}


# ---- network files --------------------------------------------------------------------------

## Everything needed to continue later, as JSON-safe data (the web game's file format, with
## the car it was trained with).
func export_best() -> Dictionary:
	return export_network(best_net if best_net != null else population.genomes[0].net, best_fitness)


## export_best() for another network of the session (`fitness`: what it scored), e.g. a car of
## the run in progress that already beats the best so far.
func export_network(net: NeuralNetwork, fitness: float) -> Dictionary:
	var ids: Array = []
	for t in tracks:
		ids.append(t.id)
	var hist: Array = []
	for h in history.slice(maxi(0, history.size() - 500)):
		hist.append(h.duplicate())
	return {
		format = NETWORK_FORMAT,
		version = NETWORK_FILE_VERSION,
		sensorVersion = Sensors.SENSOR_VERSION,
		inputs = Array(Sensors.INPUT_LABELS),
		car = cfg.car_id,
		savedAt = Time.get_datetime_string_from_system(true) + "Z",
		generation = generation,
		fitness = fitness,
		trainedOn = ids,
		settings = {populationSize = cfg.population_size, mutationRate = cfg.mutation_rate, laps = cfg.laps, walls = cfg.walls},
		bestTimes = best_times.duplicate(true),
		history = hist,
		network = net.to_json(),
	}


## The car a network file was trained with (its "car", a sim/cars.gd id). Files without one
## (older files, the browser version's, bare networks) and unknown cars are Racer networks.
static func network_car(meta: Variant) -> String:
	if meta is Dictionary:
		var c: Variant = (meta as Dictionary).get("car")
		if c is String and Cars.has_car(c):
			return c
	return Cars.DEFAULT_CAR


## The wall rule a saved network file was trained with: a WALL_RULES key, or "" for a bare
## network without training info (or an unknown rule). Files saved before the setting
## existed used "crash".
static func saved_wall_rule(meta: Variant) -> String:
	if not (meta is Dictionary) or not ((meta as Dictionary).get("trainedOn") is Array):
		return ""
	var settings: Variant = meta.get("settings")
	var rule: Variant = settings.get("walls", "crash") if settings is Dictionary else "crash"
	if rule == null:
		rule = "crash"
	return String(rule) if rule is String and WALL_RULES.has(rule) else ""


## Wrap a bare network in the current file format (JS networkFile).
static func network_file(net: NeuralNetwork, meta: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {
		format = NETWORK_FORMAT,
		version = NETWORK_FILE_VERSION,
		sensorVersion = Sensors.SENSOR_VERSION,
		inputs = Array(Sensors.INPUT_LABELS),
	}
	d.merge(meta, true)
	d.network = net.to_json()
	return d


## Parse a saved network file (as made by export_best(), or a bare {sizes, weights, biases}
## network): JSON text or parsed data. Returns {net, meta} or {error: message for the player}.
static func parse_network_file(json: Variant) -> Dictionary:
	var obj: Variant = json
	if json is String:
		var p := JSON.new()
		if p.parse(json) != OK:
			return {error = "Not a network file"}
		obj = p.data
	if not (obj is Dictionary):
		return {error = "Not a network file"}
	var d: Dictionary = obj
	var net: NeuralNetwork = NeuralNetwork.from_json(d.get("network") if d.get("network") != null else d)
	if net == null:
		return {error = "Not a network file"}
	var n_in: int = net.sizes[0]
	var n_out: int = net.sizes[net.sizes.size() - 1]
	var version: Variant = d.get("version")
	var sv: Variant = d.get("sensorVersion")
	var old_file: bool = (_is_num(version) and float(version) < NETWORK_FILE_VERSION) or \
		(_is_num(sv) and float(sv) != Sensors.SENSOR_VERSION)
	if n_in != Sensors.INPUT_COUNT or n_out != Sensors.OUTPUT_COUNT or old_file:
		if old_file or n_in == 11:
			return {error = "This network was trained for Track Rush v1 (%d inputs). v2 has new car physics and %d inputs, so v1 networks can't drive it. Train a new one on the training screen." % [n_in, Sensors.INPUT_COUNT]}
		return {error = "This network has %d inputs and %d outputs; Track Rush v2 needs %d inputs and %d outputs." % [n_in, n_out, Sensors.INPUT_COUNT, Sensors.OUTPUT_COUNT]}
	return {net = net, meta = d}
