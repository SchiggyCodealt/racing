class_name Medals
extends RefCounted
## medals.gd: medal times (author, gold, silver, bronze, like Trackmania), a port of
## web/src/tracks/medals.js. The times live in data/medals.json, written by
## tools/medals.gd (the medal autopilot sweep, the same as web/tools/medals.mjs).
## ------------------------------------------------------------------
## Data-driven: the medal list (ORDER / NAMES) and the ratios (FACTORS: gold,
## silver and bronze = author × factor, rounded up to a whole second) are data;
## medals.json stores the factors it was made with next to the times.
##
##   Medals.medal_times(track, car_id = "racer", laps = -1) -> {author, gold, silver, bronze, run} or {}
##       ({} when none were made for this car, layout, laps, physics or scoring rules)
##   Medals.medal_for(medals, time) -> "author" | "gold" | "silver" | "bronze" | "" (none)
##   Medals.next_medal(medals, time) -> {medal, time} to aim for, or {} (author already won / no medals)
##   Medals.medal_set(author[, factors]) -> {author, gold, silver, bronze}
## A time earns a medal when it is no slower, to the millisecond the HUD shows.

const DATA_PATH: String = "res://data/medals.json"
const ORDER: PackedStringArray = ["author", "gold", "silver", "bronze"]
const NAMES: Dictionary = {author = "Author", gold = "Gold", silver = "Silver", bronze = "Bronze"}
## gold / silver / bronze = author × these, rounded up to a whole second
const FACTORS: Dictionary = {gold = 1.06, silver = 1.2, bronze = 1.5}

static var _data: Dictionary = {}
static var _loaded: bool = false
static var _mutex: Mutex = Mutex.new()


## The whole medals.json ({physics, scoreRules, method, factors, tracks: {id: {laps, sig, cars: {car: {...}}}}}).
static func data() -> Dictionary:
	_mutex.lock()
	if not _loaded:
		_loaded = true
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)) if FileAccess.file_exists(DATA_PATH) else null
		_data = v if v is Dictionary else {}
	_mutex.unlock()
	return _data


## A track's medal times with car `car_id` for a race of `laps` laps (-1: the track's laps),
## or {} (none made for this car, layout, laps, physics or scoring rules).
static func medal_times(track: BuiltTrack, car_id: String = Cars.DEFAULT_CAR, laps: int = -1) -> Dictionary:
	var d: Dictionary = data()
	var tracks: Variant = d.get("tracks")
	if not (tracks is Dictionary) or not (tracks as Dictionary).has(track.id):
		return {}
	var m: Variant = tracks[track.id]
	if not (m is Dictionary):
		return {}
	var n_laps: int = (track.laps if laps < 0 else laps) if track.closed else 1
	var fits: bool = JsMath.same(d.get("physics"), Car.PHYSICS_VERSION) and JsMath.same(d.get("scoreRules"), ScoreState.SCORE_RULES) and \
		JsMath.same(m.get("sig"), track.signature()) and JsMath.same(m.get("laps"), n_laps)
	var cars: Variant = m.get("cars")
	if not fits or not (cars is Dictionary) or not ((cars as Dictionary).get(car_id) is Dictionary):
		return {}
	return cars[car_id]


static func _ms(t: float) -> int:
	return JsMath.roundi(t * 1000.0)


## The medal a time earns ("author" | "gold" | "silver" | "bronze"), or "" (none, or no time / medal times).
static func medal_for(medals: Dictionary, time: float) -> String:
	if medals.is_empty() or not (time > 0.0) or not is_finite(time): # (no time yet: INF)
		return ""
	for m: String in ORDER:
		if medals.has(m) and _ms(time) <= _ms(float(medals[m])):
			return m
	return ""


## The next medal to aim for with a best time of `time` (no best yet: INF or 0):
## {medal, time}, or {} when the author medal is already won (or no medals).
static func next_medal(medals: Dictionary, time: float) -> Dictionary:
	if medals.is_empty():
		return {}
	var got: String = medal_for(medals, time)
	var k: int = ORDER.find(got) - 1 if got != "" else ORDER.size() - 1
	return {medal = ORDER[k], time = float(medals[ORDER[k]])} if k >= 0 else {}


## The medal times from an author time (s, to the ms): the others rounded up to a whole second
## (rounded to the ms first, so 132.0000001 stays 132).
static func medal_set(author: float, factors: Dictionary = FACTORS) -> Dictionary:
	var out: Dictionary = {author = author}
	for m: String in ORDER:
		if m != "author":
			out[m] = ceilf(JsMath.round(author * float(factors[m]) * 1000.0) / 1000.0)
	return out
