class_name OpponentRace
extends RefCounted
## opponent_race.gd: one AI opponent's whole race, run without the game (v6.5.0).
## ------------------------------------------------------------------
## Exactly what the game does with the AI car next to you in Race the AI (modes/play_mode.gd,
## its AI ghost): a standing start at GO, 60 Hz steps of the network driver (ai/sensors.gd
## AIDriver, with the level's speed cap), car.step, race.update; walls are ridden (the
## opponent never collides with you and is never put out by a wall), and when it makes no
## progress for PlayMode.STUCK_TIME seconds it is put back at its last checkpoint, standing.
## The opponent's race does not depend on yours, and the physics is deterministic, so its finish
## time is known before the race: tools/opponents.gd measures every level on every track with
## every car this way and stores the times in data/opponents/<car>.json (sim/opponents.gd), and
## tests/test_ai.gd re-runs some of them.
##
##   OpponentRace.run(net, track, car_id, cap = INF, max_time = MAX_TIME, trace = false)
##     -> {finished, time (INF when not finished), steps, respawns, wall_steps, top (m/s),
##         speeds (PackedFloat32Array, one per step, only with trace)}
## (`net` is driven as it is: give each thread its own copy, NeuralNetwork.clone().)

const PlayMode := preload("res://modes/play_mode.gd")
const STEP: float = 1.0 / 60.0
## A race that has not finished after this long (s) is given up.
const MAX_TIME: float = 1500.0


static func run(net: NeuralNetwork, track: BuiltTrack, car_id: String, cap: float = INF, max_time: float = MAX_TIME,
		trace: bool = false) -> Dictionary:
	var car := Car.new(track, track.start_idx, Cars.spec(car_id))
	var race := RaceState.new(track)
	var driver := Sensors.AIDriver.new(net, cap)
	var watch: Dictionary = PlayMode._new_watch(car, 0.0)
	var respawns: int = 0
	var wall_steps: int = 0
	var top: float = 0.0
	var speeds := PackedFloat32Array()
	var limit: int = int(max_time / STEP)
	var steps: int = 0
	while not race.finished and steps < limit:
		var c: Car.Controls = driver.drive(track, car, race)
		car.step(track, c, STEP)
		race.update(car, STEP)
		steps += 1
		if car.hit_wall:
			wall_steps += 1
		if car.speed > top:
			top = car.speed
		if trace:
			speeds.append(car.speed)
		if not race.finished and PlayMode.is_stuck(watch, car, race):
			PlayMode.respawn_car(car, race, track, false)
			watch = PlayMode._new_watch(car, race.time)
			respawns += 1
	var out: Dictionary = {finished = race.finished, time = race.finish_time, steps = steps, respawns = respawns,
		wall_steps = wall_steps, top = top}
	if trace:
		out.speeds = speeds
	return out


## The finish time a speed cap of `cap` would give, estimated from an uncapped run's speed trace
## (`speeds`, one per step): every step covers its distance at min(speed, cap) instead. It
## ignores the time to get back up to speed, so it is a little optimistic; tools/opponents.gd
## starts its search for a level's cap from it.
static func estimate(speeds: PackedFloat32Array, cap: float) -> float:
	var t: float = 0.0
	for v: float in speeds:
		t += STEP * (v / cap if v > cap else 1.0)
	return t
