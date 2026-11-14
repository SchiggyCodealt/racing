class_name Sectors
extends RefCounted
## sectors.gd (v6.26.0): every track's lap in three sectors, timed as the car crosses them, as in the
## F1 games. Pure logic (no nodes), used by the play modes (modes/play_mode.gd, field_mode.gd), the
## HUD's minimap (ui/race_minimap.gd) and the records page (ui/records_screen.gd).
## ------------------------------------------------------------------
## The sectors split a lap into thirds by distance: on a circuit from the start line (sample 0) to a
## third of the lap, to two thirds and back to the line; on a sprint from the start spot to the finish
## line the same way. A sector ends when the car's unwrapped progress (car.prog, as RaceState's gates
## use it) passes its end mark, so the last sector of a lap ends exactly on the lap's time. The first
## sector of a race starts at GO (a standing start); later laps' first sectors start at the line
## (flying). A respawn puts the car back behind a mark; the sector simply goes on until it is passed.
## The best sector times per track are kept by SaveData (get_sectors / submit_sectors) with the car
## and upgrades they were set with.
##
##   Sectors.COUNT -> 3
##   Sectors.marks(track) -> PackedInt32Array of the three end samples of a lap (the last: the line,
##       N on a circuit, finish_idx on a sprint)
##   Sectors.of_sample(track, i) -> the sector (0..2) sample i is in (samples outside a sprint's race: -1)
##   Sectors.name(k) -> "S1" .. "S3"
##   var clock := Sectors.Clock.new(track, laps)       (laps as RaceState takes it: -1 = the track's)
##   clock.update(car.prog, race.time) -> [] or [{sector (0..2), lap (0-based), time (s, the sector's),
##       at (race time)}] after race.update, every step
##   clock.sector() -> the sector being driven (0..2; COUNT when done);  clock.lap() -> its lap (0-based)
##   clock.times -> one PackedFloat64Array per lap begun (the sector times so far)
##   clock.best -> PackedFloat64Array of the best time of each sector in this run (INF: none yet)

const COUNT: int = 3
const NAMES: PackedStringArray = ["S1", "S2", "S3"]


## The end samples of the three sectors of a lap.
static func marks(t: BuiltTrack) -> PackedInt32Array:
	if t.closed:
		return PackedInt32Array([roundi(t.N / 3.0), roundi(t.N * 2.0 / 3.0), t.N])
	var s0: int = t.start_idx
	var span: float = float(t.finish_idx - s0)
	return PackedInt32Array([s0 + roundi(span / 3.0), s0 + roundi(span * 2.0 / 3.0), t.finish_idx])


## The sector sample `i` lies in (0..2), or -1 for a sprint's samples before the start or past the finish.
static func of_sample(t: BuiltTrack, i: int) -> int:
	var m: PackedInt32Array = marks(t)
	if t.closed:
		var j: int = posmod(i, t.N)
		return 0 if j < m[0] else 1 if j < m[1] else 2
	if i < t.start_idx or i > t.finish_idx:
		return -1
	return 0 if i < m[0] else 1 if i < m[1] else 2


static func name(k: int) -> String:
	return NAMES[k] if k >= 0 and k < COUNT else ""


## One car's sector times in one race.
class Clock:
	extends RefCounted
	var bounds: PackedFloat64Array = PackedFloat64Array() # the progress of every sector end, in race order
	var next: int = 0
	var last_at: float = 0.0
	var times: Array[PackedFloat64Array] = []
	var best: PackedFloat64Array = PackedFloat64Array()

	func _init(t: BuiltTrack, n_laps: int = -1) -> void:
		var laps: int = (t.laps if n_laps < 0 else n_laps) if t.closed else 1
		var m: PackedInt32Array = Sectors.marks(t)
		for lap in laps:
			for k in COUNT:
				bounds.append(float(lap * t.N + m[k]) if t.closed else float(m[k]))
		best.resize(COUNT)
		best.fill(INF)
		times.append(PackedFloat64Array())

	## The sector being driven (COUNT once the race's last one is done).
	func sector() -> int:
		return next % COUNT if next < bounds.size() else COUNT

	## The lap of the sector being driven (0-based).
	@warning_ignore("integer_division")
	func lap() -> int:
		return mini(next, bounds.size() - 1) / COUNT

	@warning_ignore("integer_division")
	func update(prog: float, at: float) -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		while next < bounds.size() and prog >= bounds[next]:
			var k: int = next % COUNT
			var lp: int = next / COUNT
			var dt: float = at - last_at
			times[lp].append(dt)
			if dt < best[k]:
				best[k] = dt
			out.append({sector = k, lap = lp, time = dt, at = at})
			last_at = at
			next += 1
			if next < bounds.size() and next % COUNT == 0:
				times.append(PackedFloat64Array())
		return out
