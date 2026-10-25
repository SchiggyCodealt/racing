class_name RaceState
extends RefCounted
## race.gd: race rules, a port of web/src/game/race.js: checkpoints in order,
## laps, timing and splits. Pure logic, used by the player, the AI trainer and
## the ghost car alike.
## ------------------------------------------------------------------
## The car's "unwrapped progress" (car.prog, in sample units, counting up
## across laps) is compared against an ordered list of gates
## (TrackBuilder.get_gates). Only the next gate can be taken, so a lap only
## counts when every checkpoint was passed in order.
##
##   var race := RaceState.new(track)          # all the track's laps (sprints: 1)
##   var race := RaceState.new(track, 1)       # one lap
##   var events := race.update(car, dt)        # after car.step(), every step
##       -> [] or [{kind = "cp"|"lap"|"finish", gate_index, time, lap_time (lap/finish)}]
##   race.time, race.finished, race.finish_time (INF until finished), race.splits,
##   race.lap_times, race.respawn (car.snapshot() at the last gate, {} before),
##   race.lap(), race.cp_in_lap(), race.total_gates(), race.cp_per_lap
##   RaceState.format_time(t) -> "m:ss.mmm";  RaceState.format_delta(d) -> "+0.123"

var track: BuiltTrack
var laps: int = 1
var gates: Array[Dictionary] = []
## checkpoints + the line
var cp_per_lap: int = 1
var next_gate: int = 0
## seconds since GO
var time: float = 0.0
var finished: bool = false
## INF until finished (the JS null)
var finish_time: float = INF
## time at each gate
var splits: PackedFloat64Array = PackedFloat64Array()
var lap_times: PackedFloat64Array = PackedFloat64Array()
var lap_start: float = 0.0
## car snapshot at the last gate ({} before the first)
var respawn: Dictionary = {}


func _init(t: BuiltTrack, n_laps: int = -1) -> void:
	track = t
	laps = (t.laps if n_laps < 0 else n_laps) if t.closed else 1
	gates = TrackBuilder.get_gates(t, laps)
	cp_per_lap = t.cp_samples.size() + 1
	reset()


func reset() -> void:
	next_gate = 0
	time = 0.0
	finished = false
	finish_time = INF
	splits = PackedFloat64Array()
	lap_times = PackedFloat64Array()
	lap_start = 0.0
	respawn = {}


## The lap being driven (1-based, at most laps).
func lap() -> int:
	return mini(laps, int(gates[mini(next_gate, gates.size() - 1)].lap) + 1)


## Checkpoints passed in the current lap (for the HUD).
func cp_in_lap() -> int:
	if finished:
		return cp_per_lap
	return int(gates[next_gate].cp)


func total_gates() -> int:
	return gates.size()


## Advance the timer and test gates. Returns the gate events of this step
## (empty when none): {kind: "cp"|"lap"|"finish", gate_index, time, lap_time (lap and finish)}.
func update(car: Car, dt: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if finished:
		return events
	time += dt
	while next_gate < gates.size() and car.prog >= float(gates[next_gate].prog):
		var g: Dictionary = gates[next_gate]
		var ev: Dictionary = {kind = g.kind, gate_index = next_gate, time = time}
		splits.append(time)
		respawn = car.snapshot()
		if g.kind == "lap" or g.kind == "finish":
			ev.lap_time = time - lap_start
			lap_times.append(ev.lap_time)
			lap_start = time
		if g.kind == "finish":
			finished = true
			finish_time = time
		next_gate += 1
		events.append(ev)
	return events


## Format seconds as m:ss.mmm ("--:--.---" for INF / NaN).
@warning_ignore("integer_division")
static func format_time(t: float) -> String:
	if not is_finite(t):
		return "--:--.---"
	var neg: bool = t < 0.0
	var ms: int = JsMath.roundi(absf(t) * 1000.0) # round once, so 119.9996 s shows as 2:00.000, not 1:60.000
	var m: int = ms / 60000
	var rest: int = ms - m * 60000
	return "%s%d:%02d.%03d" % ["-" if neg else "", m, rest / 1000, rest % 1000]


## Format a split difference: "+0.123" / "-0.456".
static func format_delta(d: float) -> String:
	return ("+" if d >= 0.0 else "-") + JsMath.to_fixed(absf(d), 3)
