class_name SaveData
extends RefCounted
## save.gd: everything the game keeps between sessions, in one JSON file in user://
## (the web game's web/src/game/storage.js kept the same things in localStorage):
## best times + splits and the ghost of the best run per track and car, the best
## score per track and car, settings, and the trained AI network of every car.
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
##   SaveData.load_network(car_id) / save_network(data, car_id)   a car's trained AI network (the network
##                                                    file, a JSON-safe Dictionary; default the racer's)
##   SaveData.network_cars()                          -> the cars that have a trained network
##   SaveData.get_archived(section, track_id, car_id) -> {signature: entry} kept from older versions of a
##                                                    track (section: "records", "scores" or "ghosts")
##   SaveData.use_file(path)                          another file (tests); SaveData.path is the current one
##
## File layout: {version, records: {track: {car: {time, splits, date, physics, sig}}},
## ghosts: {track: {car: ghost}}, scores: {track: {car: {score, date, rules, physics, sig}}},
## settings: {...}, networks: {car: {slot: network file}},
## archive: {records | scores | ghosts: {track: {car: {sig: entry}}}}}. Records and ghosts made under
## another Car.PHYSICS_VERSION, and scores under other ScoreState.SCORE_RULES, are not read.
## Track versions: records, scores and ghosts carry the signature of the track they were made on
## (BuiltTrack.signature(): its layout and road surfaces). When a track changes (v6.3 put dirt and
## snow on four tracks), what was made on the old version stops counting: on loading, such
## entries move to "archive" (by section, track, car and old signature), so new runs are never
## compared with them and nothing is lost.
## Networks: one slot per car today, "best" (the network the player trains: autosaved by
## training, Save best network, Load network…); more slots per car can sit beside it later
## (AI opponents of several skill levels).
## Versions: 1 (v6.0-6.1) kept one network, {network: {...}}: it was the Racer's (the AI only
## drove the Racer), so loading a version 1 file moves it to networks.racer.best (_migrate).
## 2 (v6.2) had no track signatures on records and scores: they get the signature the track had
## then (Tracks.LEGACY_SIGS), so those of the tracks v6.3 changed move to the archive.
## Times are written with 17 significant digits; Godot's JSON reader may return a
## stored time one unit in the last place (~1e-14 s) off, which no screen shows.

const VERSION: int = 3
## The sections whose entries belong to one version of a track (moved to "archive" when it changes).
const TRACK_SECTIONS: PackedStringArray = ["records", "scores", "ghosts"]
## The network slot the player's training fills (see the header).
const BEST_SLOT: String = "best"
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
		for k: String in ["records", "ghosts", "scores", "settings", "networks", "archive"]:
			if not (_data.get(k) is Dictionary):
				_data[k] = {}
		_migrate(_data)
		_archive_stale(_data)
		_data.version = VERSION
	return _data


## Bring older layouts up to date (in memory; the next write stores them). Version 1's single
## network was the Racer's: it becomes networks.racer.best (unless that slot is already filled,
## e.g. by a newer version before an older one wrote the file again).
static func _migrate(d: Dictionary) -> void:
	# version 2 and older: records and scores were made on the tracks of v6.2
	var v: Variant = d.get("version")
	if not _is_num(v) or float(v) < 3.0:
		for section: String in ["records", "scores"]:
			var sec: Dictionary = d[section]
			for track: Variant in sec:
				var legacy: String = Tracks.legacy_signature(str(track))
				if legacy == "" or not (sec[track] is Dictionary):
					continue
				for car: Variant in sec[track]:
					var e: Variant = sec[track][car]
					if e is Dictionary and not (e as Dictionary).has("sig"):
						e.sig = legacy
	var old: Variant = d.get("network")
	if d.has("network"):
		d.erase("network")
	if old is Dictionary:
		var nets: Dictionary = d.networks
		if not (nets.get(Cars.DEFAULT_CAR) is Dictionary):
			nets[Cars.DEFAULT_CAR] = {}
		if not ((nets[Cars.DEFAULT_CAR] as Dictionary).get(BEST_SLOT) is Dictionary):
			nets[Cars.DEFAULT_CAR][BEST_SLOT] = old


## Move every record, score and ghost made on another version of its track (another signature)
## to archive[section][track][car][old signature]. Tracks the game doesn't know are left alone.
static func _archive_stale(d: Dictionary) -> void:
	var arch: Dictionary = d.archive
	for section: String in TRACK_SECTIONS:
		var sec: Dictionary = d[section]
		for track: Variant in sec.keys():
			var cur: String = Tracks.signature(str(track))
			if cur == "" or not (sec[track] is Dictionary):
				continue
			var cars: Dictionary = sec[track]
			for car: Variant in cars.keys():
				var e: Variant = cars[car]
				var sig: Variant = (e as Dictionary).get("sig") if e is Dictionary else null
				if not (sig is String) or sig == cur:
					continue
				if not (arch.get(section) is Dictionary):
					arch[section] = {}
				if not (arch[section].get(track) is Dictionary):
					arch[section][track] = {}
				if not (arch[section][track].get(car) is Dictionary):
					arch[section][track][car] = {}
				arch[section][track][car][sig] = e
				cars.erase(car)


## Entries kept from older versions of a track: {signature: entry} (section: "records",
## "scores" or "ghosts"; {} when none).
static func get_archived(section: String, track_id: String, car_id: String) -> Dictionary:
	_mutex.lock()
	var out: Dictionary = {}
	var a: Variant = (_all().archive as Dictionary).get(section)
	if a is Dictionary and a.get(track_id) is Dictionary and a[track_id].get(car_id) is Dictionary:
		out = (a[track_id][car_id] as Dictionary).duplicate(true)
	_mutex.unlock()
	return out


## True when entry `e` was made on the current version of track `track_id` (tracks the game
## doesn't know: always).
static func _same_track(e: Dictionary, track_id: String) -> bool:
	var cur: String = Tracks.signature(track_id)
	return cur == "" or JsMath.same(e.get("sig"), cur)


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
## record set under other physics or on another version of the track). A split that isn't a
## number reads as null.
static func get_record(track_id: String, car_id: String = Cars.DEFAULT_CAR) -> Dictionary:
	_mutex.lock()
	var r: Variant = _entry("records", track_id, car_id)
	var out: Dictionary = {}
	if r is Dictionary and JsMath.same(r.get("physics"), Car.PHYSICS_VERSION) and _same_track(r, track_id) and \
			_is_num(r.get("time")) and float(r.time) > 0.0:
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
		physics = Car.PHYSICS_VERSION, sig = Tracks.signature(track_id), date = _now()})
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

## The best score on a track with a car: {score, date}, or {} (also for one made under other rules or
## physics, or on another version of the track).
static func get_best_score(track_id: String, car_id: String) -> Dictionary:
	_mutex.lock()
	var e: Variant = _entry("scores", track_id, car_id)
	var out: Dictionary = {}
	if e is Dictionary and JsMath.same(e.get("rules"), ScoreState.SCORE_RULES) and JsMath.same(e.get("physics"), Car.PHYSICS_VERSION) and \
			_same_track(e, track_id) and _is_num(e.get("score")) and float(e.score) > 0.0:
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
	_set_entry("scores", track_id, car_id, {score = score, date = _now(), rules = ScoreState.SCORE_RULES, physics = Car.PHYSICS_VERSION,
		sig = Tracks.signature(track_id)})
	_mutex.unlock()
	return true


# ---- AI networks ---------------------------------------------------------------------------

## A car's saved network file (slot: BEST_SLOT, the one training fills), or null.
static func load_network(car_id: String = Cars.DEFAULT_CAR, slot: String = BEST_SLOT) -> Variant:
	_mutex.lock()
	var n: Variant = _entry("networks", car_id, slot)
	_mutex.unlock()
	return n if n is Dictionary else null


## Keep `data` (a network file) as car `car_id`'s network (slot: BEST_SLOT). False when the file
## can't be written (it is kept for this session all the same) or the car is unknown.
static func save_network(data: Dictionary, car_id: String = Cars.DEFAULT_CAR, slot: String = BEST_SLOT) -> bool:
	if not Cars.has_car(car_id):
		return false
	_mutex.lock()
	var ok: bool = _set_entry("networks", car_id, slot, data)
	_mutex.unlock()
	return ok


## The cars (picker order) that have a saved network in `slot`.
static func network_cars(slot: String = BEST_SLOT) -> PackedStringArray:
	var out: PackedStringArray = []
	for id: String in Cars.ids():
		if load_network(id, slot) != null:
			out.append(id)
	return out


static func _now() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"
