extends SceneTree
## bench.gd: how fast the car physics runs in GDScript (the speed parts of the web
## game's web/tools/physicsBench.mjs; compare with `node web/tools/physicsBench.mjs`).
## ------------------------------------------------------------------
##   godot --headless --path <copy> --script res://tools/bench.gd [-- cars=80 seconds=10 threads=4 parts=123]
##
## 1. One car, every track: an autopilot drives one lap and its controls are recorded,
##    then the same lap is replayed and only Car.step() is timed: µs per step.
## 1b. Every car (sim/cars.gd): the same over all the tracks.
## 2. `cars` cars on each track, every step each car does what a training run's physics
##    does (autopilot controls, Car.step, RaceState.update), on ONE core: car-steps per
##    second and "× real time" (simulated seconds per wall-clock second for all of them).
##    (The AI's sensors and network are not included: they belong to the AI code.)
## 3. The same on `threads` threads (each thread owns a slice of the cars; the sim is
##    deterministic and thread-safe as long as each car stays on one thread).
## Times are wall-clock on whatever else the machine is doing: run it twice.

const DT: float = 1.0 / 60.0


## physicsBench's autopilot: aims at a point ahead (offset from the centre line by `line_offset`
## of the half width), speed targets for `a_lat` m/s² of grip, braking at 9 m/s². O(1) per call.
class BenchPilot:
	var track: BuiltTrack
	var plan: Autopilot
	var line_offset: float

	func _init(t: BuiltTrack, offset: float = 0.0, a_lat: float = 12.5) -> void:
		track = t
		line_offset = offset
		plan = Autopilot.new()
		plan.track = t
		plan._plan(3, 6.0, 100.0, 1e4, a_lat, 9.0, true)

	func drive(car: Car, c: Car.Controls) -> void:
		var look: int = maxi(4, mini(14, JsMath.roundi((6.0 + car.speed * 0.35) / track.seg_len)))
		var i: int = plan._at(car.idx + look)
		var off: float = line_offset * maxf(0.0, track.hw[i] - 2.5)
		var gx: float = track.px[i] + track.nx[i] * off - car.x
		var gz: float = track.pz[i] + track.nz[i] * off - car.z
		var fx: float = sin(car.yaw)
		var fz: float = cos(car.yaw)
		c.steer = maxf(-1.0, minf(1.0, 3.0 * atan2(gx * fz - gz * fx, gx * fx + gz * fz)))
		var target: float = plan.vt[plan._at(car.idx + 1)]
		c.throttle = 1.0 if car.speed < target - 1.0 else (-1.0 if car.speed > target + 1.5 else 0.3)
		c.handbrake = false


## One training-like agent: a car, its race and its autopilot.
class Agent:
	var car: Car
	var race: RaceState
	var pilot: BenchPilot
	var c: Car.Controls = Car.Controls.new()


var n_cars: int = 80
var seconds: float = 10.0
var n_threads: int = 4
var parts: String = "123"
var bad: int = 0
var outside: int = 0


func _initialize() -> void:
	n_threads = mini(4, OS.get_processor_count())
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("cars="):
			n_cars = maxi(1, a.substr(5).to_int())
		elif a.begins_with("seconds="):
			seconds = maxf(0.5, a.substr(8).to_float())
		elif a.begins_with("threads="):
			n_threads = clampi(a.substr(8).to_int(), 1, 32)
		elif a.begins_with("parts="):
			parts = a.substr(6)
	var tracks: Array[BuiltTrack] = []
	for id: String in Tracks.ids():
		tracks.append(Tracks.build(id))
	print("Track Rush physics bench (GDScript) - %d tracks, substeps %d, Godot %s, %d CPU cores" % [
		tracks.size(), Cars.default_spec().substeps, Engine.get_version_info().string, OS.get_processor_count()])

	if parts.contains("1"):
		part1(tracks)
	if parts.contains("2"):
		part2(tracks)
	if parts.contains("3") and n_threads > 1:
		part3(tracks)
	print("\n4) sanity: non-finite car states %d, cars outside the walls %d" % [bad, outside])
	quit(1 if bad or outside else 0)


## 1 + 1b: µs per Car.step, one car.
func part1(tracks: Array[BuiltTrack]) -> void:
	print("\n1) one car, one lap with an autopilot, µs per Car.step() (controls replayed, only Car.step timed)")
	var single: Array[float] = []
	for track: BuiltTrack in tracks:
		var r: Dictionary = lap_bench(track, Cars.default_spec(), 12.5)
		single.append(r.us)
		print("   %-22s %6.2f µs/step   lap %.1f s, wall contact %.1f %% of steps" % [track.id, r.us, r.steps * DT, 100.0 * r.wall / r.steps])
	var avg: float = 0.0
	for u: float in single:
		avg += u
	avg /= single.size()
	print("   average %.2f µs/step  (= %d car-steps per second on one core)" % [avg, int(1e6 / avg)])

	# --- 1b. every car ---
	print("\n1b) every car: one lap of every track with its own autopilot (corner speeds scaled by its skidpad grip), µs per Car.step()")
	for id: String in Cars.ids():
		var a_lat: float = 12.5 * float(Cars.get_car(id).stats.grip) / float(Cars.get_car("racer").stats.grip)
		var us: float = 0.0
		var steps: int = 0
		var wall: int = 0
		for track: BuiltTrack in tracks:
			var r: Dictionary = lap_bench(track, Cars.spec(id), a_lat)
			us += r.us * r.steps
			steps += r.steps
			wall += r.wall
		print("   %-8s %6.2f µs/step   %d laps in %.1f s (autopilot grip %.1f m/s²), wall contact %.1f %% of steps" % [id, us / steps, tracks.size(), steps * DT, a_lat, 100.0 * wall / steps])


## 2: n_cars cars on one core.
func part2(tracks: Array[BuiltTrack]) -> void:
	print("\n2) %d cars per track, each step per car: autopilot + Car.step() + RaceState.update(); %s s simulated per track, one core" % [n_cars, JsMath.num_to_js(seconds)])
	var results: Array[float] = []
	var cs_total: float = 0.0
	for track: BuiltTrack in tracks:
		var agents: Array[Agent] = make_agents(track)
		var steps: int = JsMath.roundi(seconds / DT)
		var t0: int = Time.get_ticks_usec()
		run_agents(track, agents, steps)
		var us: float = Time.get_ticks_usec() - t0
		for a: Agent in agents:
			check_car(a.car)
		var x: float = steps * DT * 1e6 / us
		results.append(x)
		cs_total += steps * n_cars / (us / 1e6)
		print("   %-22s %6.2f× real time  (%.2f µs per car-step, %d car-steps/s)" % [track.id, x, us / (steps * n_cars), int(steps * n_cars / (us / 1e6))])
	var min_x: float = results.min()
	var avg_x: float = 0.0
	for x: float in results:
		avg_x += x
	avg_x /= results.size()
	print("   slowest track %.2f× real time, average %.2f×, %d car-steps/s on one core (the web game: >= 40× with 80 cars, sensors and network included)" % [
		min_x, avg_x, int(cs_total / results.size())])


## 3: the same on n_threads threads.
func part3(tracks: Array[BuiltTrack]) -> void:
	print("\n3) the same with the cars split over %d threads (the sim is thread-safe as long as each car stays on one thread)" % n_threads)
	for track: BuiltTrack in [tracks[0], tracks[tracks.size() - 1]]:
		for own: bool in [false, true]:
			var x: float = threaded(track, own)
			print("   %-22s %6.2f× real time  (%d car-steps/s)  %s" % [track.id, x, int(x * 60.0 * n_cars),
				"each thread with its own copy of the track and the car spec" if own else "all threads sharing one track and one car spec"])


## `seconds` of `n_cars` cars on `track` split over n_threads threads; `own`: every thread builds its
## own copy of the track and of the car spec (no shared objects). Returns × real time.
func threaded(track: BuiltTrack, own: bool) -> float:
	var steps: int = JsMath.roundi(seconds / DT)
	var per: int = ceili(float(n_cars) / n_threads)
	var slices: Array = []
	var tracks_of: Array[BuiltTrack] = []
	for k in n_threads:
		var tr: BuiltTrack = Tracks.build_def(Tracks.def(track.id)) if own else track
		var spec: CarSpec = CarSpec.make({}, Cars.default_spec()) if own else Cars.default_spec()
		var all: Array[Agent] = make_agents(tr, spec)
		slices.append(all.slice(k * per, mini(n_cars, (k + 1) * per)))
		tracks_of.append(tr)
	var t0: int = Time.get_ticks_usec()
	var pool: Array[Thread] = []
	for k in n_threads:
		var slice: Array[Agent] = slices[k]
		if slice.is_empty():
			continue
		var th := Thread.new()
		th.start(run_agents.bind(tracks_of[k], slice, steps))
		pool.append(th)
	for th in pool:
		th.wait_to_finish()
	var us: float = Time.get_ticks_usec() - t0
	for sl: Array[Agent] in slices:
		for a: Agent in sl:
			check_car(a.car)
	return steps * DT * 1e6 / us


## One lap of a track: the autopilot's controls recorded, then replayed with only Car.step timed.
func lap_bench(track: BuiltTrack, spec: CarSpec, a_lat: float) -> Dictionary:
	var pilot := BenchPilot.new(track, 0.0, a_lat)
	var c := Car.Controls.new()
	var car := Car.new(track, track.start_idx, spec)
	var rec := PackedFloat64Array()
	var goal: float = car.prog + (track.N if track.closed else track.count - 12 - car.prog)
	var s: int = 0
	while s < 60 * 400 and car.prog < goal:
		pilot.drive(car, c)
		rec.append(c.steer)
		rec.append(c.throttle)
		car.step(track, c, DT)
		s += 1
	var steps: int = rec.size() >> 1
	car = Car.new(track, track.start_idx, spec)
	var wall: int = 0
	var t0: int = Time.get_ticks_usec()
	for k in steps:
		c.steer = rec[2 * k]
		c.throttle = rec[2 * k + 1]
		car.step(track, c, DT)
		if car.hit_wall:
			wall += 1
	var us: float = float(Time.get_ticks_usec() - t0) / steps
	check_car(car)
	return {us = us, steps = steps, wall = wall}


func make_agents(track: BuiltTrack, spec: CarSpec = null) -> Array[Agent]:
	var agents: Array[Agent] = []
	for k in n_cars:
		var a := Agent.new()
		a.car = Car.new(track, -1, spec)
		a.race = RaceState.new(track, 1)
		a.pilot = BenchPilot.new(track, ((k % 9) - 4) / 5.0, 11.0 + (k % 5))
		agents.append(a)
	# stagger the cars along the first stretch so they don't all sit on one spot
	for s in 120:
		for k in agents.size():
			if s >= k * 1.5:
				continue
			var a: Agent = agents[k]
			a.pilot.drive(a.car, a.c)
			a.car.step(track, a.c, DT)
	return agents


## `steps` physics steps of every agent (one thread).
static func run_agents(track: BuiltTrack, agents: Array[Agent], steps: int) -> void:
	for s in steps:
		for a: Agent in agents:
			var car: Car = a.car
			a.pilot.drive(car, a.c)
			car.step(track, a.c, DT)
			a.race.update(car, DT)
			if a.race.finished:
				a.race.reset()
			if not track.closed and car.idx > track.count - 12:
				car.place(track, track.start_idx)
				a.race.reset()


func check_car(car: Car) -> void:
	if not is_finite(car.x + car.y + car.z + car.vx + car.vy + car.vz + car.yaw + car.yaw_rate):
		bad += 1
	if absf(car.lat) > car._hw + 0.01:
		outside += 1
