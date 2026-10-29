class_name Opponents
extends RefCounted
## opponents.gd: the AI opponents of Race the AI (v6.5.0), five skill levels from Rookie to
## Elite on every track with every car, shipped in data/opponents/<car>.json.
## ------------------------------------------------------------------
## Each track and car has one network of its own, trained on that track with that car by
## tools/opponents.gd --train (FleetSim, walls ride) until its race beats the gold medal. Every
## level drives that network; a level whose network would be faster than its pace drives it with
## a speed cap (ai/sensors.gd AIDriver.speed_cap): it settles just under the cap on the
## straights and takes the corners as the network does. Each level's cap is set by
## tools/opponents.gd so that the opponent's race takes about `pace` × the car's author time
## (data/medals.json), and at least MIN_GAP × the next level up; Elite drives flat out where the
## network is no faster than the author time, and is held to about the author time where it is
## (on Hairpin Valley's snow the networks ride the walls to 0.83-0.92 × the author time). The opponent never
## collides with you and its race does not depend on yours, so its finish time is known: the
## file stores it, the menu shows it and tests check it (ai/opponent_race.gd runs it).
## Data-driven: a new level is one more LEVELS entry (and its rewards in sim/economy.gd).
## The player's own trained network (SaveData's "best" slot) is separate: it is raced as "My AI"
## and earns no AI rewards.
##
##   Opponents.ids() -> ["rookie", "amateur", "pro", "expert", "elite"]   (slowest first)
##   Opponents.level(id) -> {id, name, pace, blurb} or {}
##   Opponents.rank(id) -> 0 (rookie) .. 4 (elite), -1 unknown
##   Opponents.entry(track_id, car_id) -> {network (a network file), levels {id: {cap, time}},
##       generation, ...} or {} (none for this car, or made for another version of the track)
##   Opponents.time_of(track_id, car_id, level) -> the level's finish time (s), or -1
##   Opponents.cap_of(track_id, car_id, level) -> its speed cap (m/s; INF for none), or -1
##   Opponents.has_track(track_id, car_id) -> true when all the levels are there
##
## File (data/opponents/<car>.json, written by tools/opponents.gd; don't edit by hand):
##   {format, car, physics, generated, method, tracks: {id: {sig, laps, seed, generation,
##    network: {network file}, levels: {level: {cap (m/s, null = none), time (s)}}}}}

const DATA_DIR: String = "res://data/opponents"
const FORMAT: String = "track-rush-opponents"
## The levels, slowest first. pace: the target finish time as a share of the car's author time
## (a network slower than that drives flat out). blurb: the menu's tooltip.
const LEVELS: Array[Dictionary] = [
	{id = "rookie", name = "Rookie", pace = 1.6, blurb = "takes it easy: slower than the bronze medal"},
	{id = "amateur", name = "Amateur", pace = 1.4, blurb = "a steady driver, between silver and bronze pace"},
	{id = "pro", name = "Pro", pace = 1.25, blurb = "quick: about silver medal pace"},
	{id = "expert", name = "Expert", pace = 1.13, blurb = "fast: between gold and silver pace"},
	{id = "elite", name = "Elite", pace = 1.0, blurb = "the fastest: about the author time"},
]
## Each level's finish time is at least this × the next level up's (tools/opponents.gd).
const MIN_GAP: float = 1.04

static var _files: Dictionary = {}
static var _mutex: Mutex = Mutex.new()


static func ids() -> PackedStringArray:
	var out: PackedStringArray = []
	for l: Dictionary in LEVELS:
		out.append(String(l.id))
	return out


## A level's definition, or {} for an unknown id.
static func level(id: String) -> Dictionary:
	for l: Dictionary in LEVELS:
		if l.id == id:
			return l
	return {}


## 0 for the slowest level up to LEVELS.size() - 1 for the fastest, -1 for an unknown id.
static func rank(id: String) -> int:
	for k in LEVELS.size():
		if LEVELS[k].id == id:
			return k
	return -1


static func level_name(id: String) -> String:
	var l: Dictionary = level(id)
	return String(l.name) if not l.is_empty() else id


## The whole data/opponents/<car>.json ({} when there is none or it can't be read), read once.
static func file_data(car_id: String) -> Dictionary:
	_mutex.lock()
	if not _files.has(car_id):
		var p: String = "%s/%s.json" % [DATA_DIR, car_id]
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(p)) if FileAccess.file_exists(p) else null
		_files[car_id] = v if v is Dictionary and (v as Dictionary).get("format") == FORMAT else {}
	var d: Dictionary = _files[car_id]
	_mutex.unlock()
	return d


## Forget the files read (tools/opponents.gd after writing one; tests).
static func reload() -> void:
	_mutex.lock()
	_files.clear()
	_mutex.unlock()


## The opponents of a track with a car: {sig, laps, network, levels {id: {cap, time}}, ...}, or {}
## when there are none, or they were made for other physics or another version of the track.
static func entry(track_id: String, car_id: String) -> Dictionary:
	var d: Dictionary = file_data(car_id)
	if d.is_empty() or not JsMath.same(d.get("physics"), Car.PHYSICS_VERSION) or not (d.get("tracks") is Dictionary):
		return {}
	var e: Variant = (d.tracks as Dictionary).get(track_id)
	if not (e is Dictionary) or not (e as Dictionary).get("network") is Dictionary or not (e as Dictionary).get("levels") is Dictionary:
		return {}
	var sig: String = Tracks.signature(track_id)
	if sig == "" or not JsMath.same(e.get("sig"), sig):
		return {}
	return e


## True when the track has every level with the car.
static func has_track(track_id: String, car_id: String) -> bool:
	var e: Dictionary = entry(track_id, car_id)
	if e.is_empty():
		return false
	for id: String in ids():
		if not ((e.levels as Dictionary).get(id) is Dictionary):
			return false
	return true


## A level's measured finish time on the track with the car (s), or -1.
static func time_of(track_id: String, car_id: String, level_id: String) -> float:
	var l: Variant = _level_entry(track_id, car_id, level_id)
	return float(l.time) if l is Dictionary and (l.get("time") is float or l.get("time") is int) else -1.0


## A level's speed cap (m/s; INF when it drives flat out), or -1 when there is no such opponent.
static func cap_of(track_id: String, car_id: String, level_id: String) -> float:
	var l: Variant = _level_entry(track_id, car_id, level_id)
	if not (l is Dictionary):
		return -1.0
	var c: Variant = l.get("cap")
	return float(c) if (c is float or c is int) and float(c) > 0.0 else INF


static func _level_entry(track_id: String, car_id: String, level_id: String) -> Variant:
	var e: Dictionary = entry(track_id, car_id)
	return (e.levels as Dictionary).get(level_id) if not e.is_empty() else null
