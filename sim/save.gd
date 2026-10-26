class_name SaveData
extends RefCounted
## save.gd: everything the game keeps between sessions, in one JSON file in user://
## (the web game's web/src/game/storage.js kept the same things in localStorage):
## best times + splits and the ghost of the best run per track and car, the best
## score per track and car, settings, and the latest trained AI network.
## ------------------------------------------------------------------
## Bad, missing or foreign data is ignored, never fatal: an unreadable file is
## kept next to the save as "<file>.bad" and the game starts from defaults. Writes
## go to "<file>.tmp" first and then replace the file, so a crash mid-write can't
## leave half a save. When the file can't be written (disk full, read-only), what
## was saved is still kept for this session. Browser (localStorage) saves cannot
## be carried over.
##
##   SaveData.get_record(track_id, car_id)            -> {time, splits, date} or {}
##   SaveData.submit_record(track_id, car_id, time, splits) -> true when it is a new best (unknown car: false;
##                                                    splits: Array or race.splits)
##   SaveData.load_ghost(track_id, car_id)            -> the saved ghost (Replay.pack_ghost) or null, unchecked
##   SaveData.save_ghost(track_id, car_id, ghost)     -> false when the file can't be written
##   SaveData.get_best_score(track_id, car_id)        -> {score, date} or {}
##   SaveData.submit_score(track_id, car_id, score)   -> true when it is a new best
##   SaveData.get_setting(name) / set_setting(name, value)   (SETTINGS: names, defaults and types)
##   SaveData.load_network() / save_network(data)     the trained AI network (a JSON-safe Dictionary)
##   SaveData.use_file(path)                          another file (tests); SaveData.path is the current one
##
## File layout: {version, records: {track: {car: {time, splits, date, physics}}},
## ghosts: {track: {car: ghost}}, scores: {track: {car: {score, date, rules, physics}}},
## settings: {...}, network: {...} or null}. Records and ghosts made under another
## Car.PHYSICS_VERSION, and scores under other ScoreState.SCORE_RULES, are not read.
## Times are written with 17 significant digits; Godot's JSON reader may return a
## stored time one unit in the last place (~1e-14 s) off, which no screen shows.

const VERSION: int = 1
const DEFAULT_PATH: String = "user://trackrush_save.json"
## Settings, their defaults and (by the default's type) the type a stored value must have.
## car: the car picked on the menu (Cars.get_car() turns an unknown id into the racer);
## quality: the graphics quality ("auto" | "high" | "medium" | "low").
const SETTINGS: Dictionary = {ghost = true, car = "racer", quality = "auto"}

static var path: String = DEFAULT_PATH
static var _data: Dictionary = {}
static var _loaded: bool = false
static var _mutex: Mutex = Mutex.new()


## Use another save file (tests, tools); it is read on next use.
static func use_file(p: String) -> void:
	_mutex.lock()
	path = p
	_loaded = false
	_data = {}
	_mutex.unlock()


static func _all() -> Dictionary:
	if not _loaded:
		_loaded = true
		_data = {}
		if FileAccess.file_exists(path):
			var text: String = FileAccess.get_file_as_string(path)
			var json := JSON.new()
			if json.parse(text) == OK and json.data is Dictionary:
				_data = json.data
			else:
				# keep what we couldn't read, then start over
				DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(path + ".bad"))
		for k: String in ["records", "ghosts", "scores", "settings"]:
			if not (_data.get(k) is Dictionary):
				_data[k] = {}
		_data.version = VERSION
	return _data


static func _write() -> bool:
	var tmp: String = path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(_json_safe(_data), "", false, true))
	var ok: bool = f.get_error() == OK
	f.close()
	if not ok:
		return false
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path)) == OK


## A copy of `v` that JSON can hold: inf and nan become null (Godot would write them as
## "inf" / "nan" and make the whole file unreadable), packed arrays plain arrays.
static func _json_safe(v: Variant) -> Variant:
	if v is float:
		return v if is_finite(v) else null
	if v is Dictionary:
		var out: Dictionary = {}
		for k: Variant in v:
			out[str(k)] = _json_safe(v[k])
		return out
	if v is Array or v is PackedFloat64Array or v is PackedFloat32Array or v is PackedInt32Array or v is PackedInt64Array:
		var out: Array = []
		for x: Variant in v:
			out.append(_json_safe(x))
		return out
	return v


## data[section][a][b] when every level is a Dictionary, else null.
static func _entry(section: String, a: String, b: String) -> Variant:
	var s: Variant = _all()[section]
	if not (s is Dictionary) or not (s as Dictionary).has(a):
		return null
	var t: Variant = s[a]
	if not (t is Dictionary) or not (t as Dictionary).has(b):
		return null
	return t[b]


static func _set_entry(section: String, a: String, b: String, value: Variant) -> bool:
	var s: Dictionary = _all()[section]
	if not (s.get(a) is Dictionary):
		s[a] = {}
	s[a][b] = value
	return _write()


static func _is_num(v: Variant) -> bool:
	return (v is float or v is int) and is_finite(float(v))


# ---- best times -------------------------------------------------------------------

## {time, splits[], date} on a track with a car (default: the racer), or {} (also for a
## record set under other physics). A split that isn't a number reads as null.
static func get_record(track_id: String, car_id: String = Cars.DEFAULT_CAR) -> Dictionary:
	_mutex.lock()
	var r: Variant = _entry("records", track_id, car_id)
	var out: Dictionary = {}
	if r is Dictionary and JsMath.same(r.get("physics"), Car.PHYSICS_VERSION) and _is_num(r.get("time")) and float(r.time) > 0.0:
		var splits: Array = []
		if r.get("splits") is Array:
			for s: Variant in r.splits:
				splits.append(float(s) if _is_num(s) else null)
		out = {time = float(r.time), splits = splits, date = str(r.get("date", ""))}
	_mutex.unlock()
	return out


## Save a time on a track with a car if it beats the best. Returns true when it is a new record.
static func submit_record(track_id: String, car_id: String, time: float, splits: Variant = []) -> bool:
	if not Cars.has_car(car_id) or not (time > 0.0) or not is_finite(time):
		return false
	var prev: Dictionary = get_record(track_id, car_id)
	if not prev.is_empty() and prev.time <= time:
		return false
	_mutex.lock()
	_set_entry("records", track_id, car_id, {time = time, splits = _json_safe(splits) if splits is Array or splits is PackedFloat64Array else [],
		physics = Car.PHYSICS_VERSION, date = _now()})
	_mutex.unlock()
	return true


# ---- ghosts ------------------------------------------------------------------------

## The saved ghost of the best run on a track with a car, unchecked (Replay.unpack_ghost
## checks and decodes it), or null.
static func load_ghost(track_id: String, car_id: String = Cars.DEFAULT_CAR) -> Variant:
	_mutex.lock()
	var g: Variant = _entry("ghosts", track_id, car_id)
	_mutex.unlock()
	return g


## Save the ghost of a track and car (Replay.pack_ghost output). False when the file can't be written.
static func save_ghost(track_id: String, car_id: String, ghost: Dictionary) -> bool:
	_mutex.lock()
	var ok: bool = _set_entry("ghosts", track_id, car_id, ghost)
	_mutex.unlock()
	return ok


# ---- settings -----------------------------------------------------------------------

## A remembered setting (see SETTINGS for the names and defaults; a stored value of another
## type reads as the default). Names not in SETTINGS return what was stored, or `fallback`.
static func get_setting(name: String, fallback: Variant = null) -> Variant:
	_mutex.lock()
	var v: Variant = (_all().settings as Dictionary).get(name)
	_mutex.unlock()
	if SETTINGS.has(name):
		var d: Variant = SETTINGS[name]
		return v if typeof(v) == typeof(d) else d
	return fallback if v == null else v


static func set_setting(name: String, value: Variant) -> bool:
	_mutex.lock()
	(_all().settings as Dictionary)[name] = value
	var ok: bool = _write()
	_mutex.unlock()
	return ok


# ---- best scores -----------------------------------------------------------------------

## The best score on a track with a car: {score, date}, or {} (also for one made under other rules or physics).
static func get_best_score(track_id: String, car_id: String) -> Dictionary:
	_mutex.lock()
	var e: Variant = _entry("scores", track_id, car_id)
	var out: Dictionary = {}
	if e is Dictionary and JsMath.same(e.get("rules"), ScoreState.SCORE_RULES) and JsMath.same(e.get("physics"), Car.PHYSICS_VERSION) and \
			_is_num(e.get("score")) and float(e.score) > 0.0:
		out = {score = float(e.score), date = str(e.get("date", ""))}
	_mutex.unlock()
	return out


## Save a race's score on a track with a car if it beats the best. True when it is a new best (0 never is).
static func submit_score(track_id: String, car_id: String, score: float) -> bool:
	if not is_finite(score) or not (score > 0.0):
		return false
	var prev: Dictionary = get_best_score(track_id, car_id)
	if not prev.is_empty() and prev.score >= score:
		return false
	_mutex.lock()
	_set_entry("scores", track_id, car_id, {score = score, date = _now(), rules = ScoreState.SCORE_RULES, physics = Car.PHYSICS_VERSION})
	_mutex.unlock()
	return true


# ---- AI network ---------------------------------------------------------------------------

## The saved network data, or null.
static func load_network() -> Variant:
	_mutex.lock()
	var n: Variant = _all().get("network")
	_mutex.unlock()
	return n if n is Dictionary else null


static func save_network(data: Dictionary) -> bool:
	_mutex.lock()
	_all().network = data
	var ok: bool = _write()
	_mutex.unlock()
	return ok


static func _now() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"
