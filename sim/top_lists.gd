class_name TopLists
extends RefCounted
## top_lists.gd (v6.32.0): every track's ten fastest laps and ten fastest runs through each of its
## three sectors (sim/sectors.gd), by any car, from every race you drive yourself (time trial, Race
## the AI, the field, cups; Watch the AI and training don't count). A time that makes a list earns
## career points by the place it takes: 25, 18, 15, 12, 10, 8, 6, 4, 2, 1 (the F1 points). Pure
## logic (no nodes): SaveData keeps the lists (get_tops / submit_tops), the play modes submit a run's
## laps and sectors, the finish panel shows what they earned and the Records screen shows the lists.
## ------------------------------------------------------------------
## Every lap counts, the first one (a standing start) as much as the others, and a run can put more
## than one lap (or sector) in a list. A sprint's one lap is its run from the start to the finish.
## The run's times go in fastest first, so each is paid by the place it holds once the run is in (a
## run with two laps under the list's best takes 1st and 2nd: 25 + 18). A time equal to one already
## listed goes below it. Times pushed off the list keep the points they earned.
##
##   TopLists.SIZE -> 10;  TopLists.POINTS -> [25, 18, 15, 12, 10, 8, 6, 4, 2, 1]
##   TopLists.points_for(place) -> the points for a place (1-based; 0 outside the list)
##   TopLists.merge(list, times, car, up, date) -> {list (the new list, fastest first, at most SIZE),
##       places (PackedInt32Array: the places, 1-based, this run's times took, best first)}
##   TopLists.record_laps(splits, laps, gates_per_lap) -> the lap times a saved best run's splits
##       hold (the seed of a track's lap list from the records set before v6.32)
##   TopLists.LISTS -> ["laps", "s1", "s2", "s3"];  TopLists.list_name(i) -> "Laps", "S1" ...

const SIZE: int = 10
const POINTS: PackedInt32Array = [25, 18, 15, 12, 10, 8, 6, 4, 2, 1]
const LISTS: PackedStringArray = ["laps", "s1", "s2", "s3"]
const NAMES: PackedStringArray = ["Laps", "S1", "S2", "S3"]


static func points_for(place: int) -> int:
	return POINTS[place - 1] if place >= 1 and place <= POINTS.size() else 0


static func list_name(i: int) -> String:
	return NAMES[i] if i >= 0 and i < NAMES.size() else ""


## A list with a run's `times` (seconds; INF, NaN and <= 0 are left out) set with `car` and its
## upgrade levels `up` on `date`. `list`: [{time, car, up, date}] fastest first (left unchanged).
static func merge(list: Array, times: Variant, car: String, up: Variant, date: String) -> Dictionary:
	var fresh: Array = []
	if times is Array or times is PackedFloat64Array or times is PackedFloat32Array:
		for t: Variant in times:
			if (t is float or t is int) and is_finite(float(t)) and float(t) > 0.0:
				fresh.append(float(t))
	fresh.sort()
	var out: Array = []
	for e: Variant in list:
		if e is Dictionary:
			out.append(e)
	var places := PackedInt32Array()
	var mine: Array = [] # the new entries, to find their places once all are in
	for t: float in fresh:
		var at: int = out.size()
		for i in out.size():
			if t < float(out[i].time):
				at = i
				break
		if at >= SIZE:
			break # (the rest are slower still)
		var e: Dictionary = {time = t, car = car, up = up, date = date}
		out.insert(at, e)
		mine.append(e)
		if out.size() > SIZE:
			out.resize(SIZE)
	for i in out.size():
		for e: Dictionary in mine:
			if is_same(out[i], e):
				places.append(i + 1)
	return {list = out, places = places}


## The lap times in the splits of a saved run (`splits`: the time at every gate, `gates_per_lap`
## gates a lap, the last of them the line): the time from one line to the next, the first from GO.
## Empty when the splits don't add up to `laps` laps.
static func record_laps(splits: Array, laps: int, gates_per_lap: int) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	if laps < 1 or gates_per_lap < 1 or splits.size() != laps * gates_per_lap:
		return out
	var prev: float = 0.0
	for k in laps:
		var s: Variant = splits[(k + 1) * gates_per_lap - 1]
		if not ((s is float or s is int) and is_finite(float(s))) or float(s) <= prev:
			return PackedFloat64Array()
		out.append(float(s) - prev)
		prev = float(s)
	return out
