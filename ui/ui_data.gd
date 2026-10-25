class_name UiData
extends RefCounted
## ui_data.gd
## ------------------------------------------------------------------
## The one adapter between the interface and the game's data. Every screen in ui/ reads
## (and the few settings it changes, writes) through these static functions, so the
## interface holds no game logic and the integration phase wires them in one place.
##
## Where the data comes from today:
##   tracks       the real tracks: handed over with use_tracks (BuiltTrack from sim/), else
##                built here through sim/ Tracks (data/tracks.json); the fixture
##                ui/fixtures/web_v5.json (exported from the web game v5) only when sim/ is missing.
##   cars         sim/ Cars (names, descriptions, colours, measured stats, stat bars, CarSpec rev
##                limits); the fixture only when sim/ is missing.
##   silhouettes  CarModel.profile(id) (world/) when it exists, else the fixture (the web's carProfile).
##   medals       the fixture's medal times (web medals.js).        WIRE: sim medals.
##   records, best scores, ghosts, settings, the AI network: an in-memory store (`store`),
##                which previews and tests fill.        WIRE: sim save data / ai.
##
## Shapes returned (plain Dictionaries, so nothing here depends on sim/ types):
##   track_info(i)   {id, name, difficulty, description, closed, laps, length, sprint_length, theme}
##   track_map(i)    see TrackMapView.make_map: {points, size, start, finish (or null), closed}
##   car_info(id)    {id, name, description, color, accent, top, mass, bars {speed, acceleration,
##                   grip, drift, nitro}, rev {idle_rpm, redline, upshift_rpm}}
##   car_profile(id) {parts: [{mat, pts: PackedVector2Array of (z, y) m}], wheels: [[z, r]]}
##   record(t, c)    {time, splits} or null;  best_score(t, c) int or -1;  has_ghost(t, c) bool
##   medal_times(t, c) {author, gold, silver, bronze} (s) or {} (none for this track and car)
##   ai_status()     {ready, generation, fitness, sizes, trained_on [track ids], walls, best_times {id: {lap, finish}}}

const FIXTURE_PATH := "res://ui/fixtures/web_v5.json"
const TRACKS_JSON := "res://data/tracks.json"
const TrackMapView := preload("res://ui/track_map_view.gd")

## Settings and their defaults (the web's trackrush.settings plus the Godot port's display settings).
const SETTING_DEFAULTS := {"car": "racer", "ghost": true, "quality": "high", "fullscreen": false, "vsync": true}
## Score rules the menu's tooltips quote (score.js SCORE.comboMax).
const COMBO_MAX := 5

## In-memory save data (WIRE: replace the reads and writes below with sim's save data):
##   records  {"track_id|car_id": {time, splits}},  scores {"track_id|car_id": int},
##   ghosts   {"track_id|car_id": true},  settings {key: value},
##   network  null or {generation, fitness, sizes, trained_on, walls, best_times}
static var store := {"records": {}, "scores": {}, "ghosts": {}, "settings": {}, "network": null}

## Emitted-style hook: called with (key, value) after set_setting (the game applies quality etc.).
static var on_setting_changed: Callable = Callable()

static var _fixture: Dictionary = {}
static var _tracks: Array = []       # BuiltTrack-like objects (px, pz, closed, ...) or [] for the fixture
static var _maps: Dictionary = {}    # track index -> map dictionary
static var _world_profiles: Variant = null   # CarModel.profile works: null not asked yet
static var _tried_tracks := false            # sim/ Tracks asked already
static var _cars_class: Variant = null       # sim/ Cars script, false when missing, null not asked yet


# ---------------------------------------------------------------- tracks

## Hand over the built tracks (BuiltTrack from sim/, in menu order). The minimaps are then
## drawn from their centre lines.
static func use_tracks(tracks: Array) -> void:
	_tracks = tracks
	_maps.clear()


static func track_count() -> int:
	_ensure_tracks()
	return _tracks.size() if not _tracks.is_empty() else fixture().tracks.size()


static func track_info(i: int) -> Dictionary:
	_ensure_tracks()
	if not _tracks.is_empty():
		var t: Object = _tracks[i]
		var d: Dictionary = t.get("def") if t.get("def") is Dictionary else {}
		return {
			"id": t.get("id"), "name": t.get("name"), "difficulty": int(d.get("difficulty", 1)),
			"description": str(d.get("description", "")), "closed": t.get("closed"), "laps": t.get("laps"),
			"length": t.get("length"), "theme": t.get("theme"),
			"sprint_length": (int(t.get("finish_idx")) - int(t.get("start_idx"))) * float(t.get("seg_len")),
		}
	var f: Dictionary = fixture().tracks[i]
	return {
		"id": f.id, "name": f.name, "difficulty": int(f.difficulty), "description": f.description,
		"closed": f.closed, "laps": int(f.laps), "length": float(f.length), "theme": f.theme,
		"sprint_length": float(f.sprint_length),
	}


## The track's id (records, scores and medals are keyed by it).
static func track_id(i: int) -> String:
	return str(track_info(i).id)


## The minimap of track `i` (cached: tracks don't change while the game runs).
static func track_map(i: int) -> Dictionary:
	_ensure_tracks()
	if _maps.has(i):
		return _maps[i]
	var m: Dictionary
	if not _tracks.is_empty():
		var t: Object = _tracks[i]
		var closed: bool = t.get("closed")
		var n: int = int(t.get("N")) if closed else int(t.get("count"))
		m = TrackMapView.make_map(t.get("px"), t.get("pz"), n, closed,
			0 if closed else int(t.get("start_line")), -1 if closed else int(t.get("finish_idx")))
	else:
		var mp: Dictionary = fixture().tracks[i].map
		var px := PackedFloat64Array(mp.px)
		m = TrackMapView.make_map(px, PackedFloat64Array(mp.pz), px.size(), fixture().tracks[i].closed,
			int(mp.start), int(mp.finish))
	_maps[i] = m
	return m


## Build the real tracks here (sim/ Tracks: data/tracks.json through TrackBuilder) when nobody
## handed them over. Without sim/ the fixture stands in.
static func _ensure_tracks() -> void:
	if not _tracks.is_empty() or _tried_tracks:
		return
	_tried_tracks = true
	var tracks := _global_script("Tracks")
	if tracks == null or not tracks.can_instantiate() or not FileAccess.file_exists(TRACKS_JSON):
		return
	var built: Array = []
	for id in tracks.call("ids"):
		var t: Variant = tracks.call("build", id)
		if t == null:
			return
		built.append(t)
	_tracks = built


# ---------------------------------------------------------------- cars

## Car ids in picker order: sim/ Cars when it is there, else the fixture.
static func car_ids() -> Array[String]:
	var out: Array[String] = []
	var cars := _cars_script()
	if cars != null:
		for id in cars.call("ids"):
			out.append(str(id))
		return out
	for c in fixture().cars:
		out.append(str(c.id))
	return out


## A car's menu data (unknown ids give the racer, like getCar): name, description, paint,
## top speed (km/h), mass (kg), the five 0..1 bars and the rev limits for the rev bar.
static func car_info(id: String) -> Dictionary:
	var cars := _cars_script()
	if cars != null:
		var d: Dictionary = cars.call("get_car", id)
		var sp: Object = d.spec
		return {
			"id": d.id, "name": d.name, "description": d.description,
			"color": Color(d.look.color), "accent": Color(d.look.accent),
			"top": float(d.stats.top), "mass": float(d.stats.mass), "bars": d.bars,
			"rev": {"idle_rpm": sp.get("idle_rpm"), "redline": sp.get("redline"), "upshift_rpm": sp.get("upshift_rpm")},
		}
	var c: Dictionary = _fixture_car(id)
	return {
		"id": c.id, "name": c.name, "description": c.description,
		"color": Color(c.color), "accent": Color(c.accent),
		"top": float(c.stats.top), "mass": float(c.stats.mass),
		"bars": c.bars, "rev": c.rev,
	}


## sim/ Cars, or null when it isn't in the project.
static func _cars_script() -> Script:
	if _cars_class == null:
		var c := _global_script("Cars")
		_cars_class = c if c != null and c.can_instantiate() else false
	return _cars_class if _cars_class is Script else null


## The car's side view for the car cards: CarModel.profile (world/) when it exists, else the
## fixture (the web's carProfile).
static func car_profile(id: String) -> Dictionary:
	if _world_profiles != false:
		var model := _global_script("CarModel")
		var p: Variant = null
		if model != null and model.can_instantiate() and _has_static(model, "profile"):
			p = model.call("profile", id)
		_world_profiles = p is Dictionary and (p as Dictionary).has("parts") # (asked once: false keeps the fixture)
		if _world_profiles:
			return p
	var src: Dictionary = _fixture_car(id).profile
	var parts: Array = []
	for part in src.parts:
		var pts := PackedVector2Array()
		for q in part.pts:
			pts.append(Vector2(q[0], q[1]))
		parts.append({"mat": part.mat, "pts": pts})
	return {"parts": parts, "wheels": src.wheels}


static func _fixture_car(id: String) -> Dictionary:
	for c in fixture().cars:
		if c.id == id:
			return c
	return fixture().cars[0]


# ---------------------------------------------------------------- records, medals, the AI

static func _key(track: String, car: String) -> String:
	return "%s|%s" % [track, car]


## Your best time and splits on a track with a car, or null.       WIRE: sim save data.
static func record(track: String, car: String) -> Variant:
	return store.records.get(_key(track, car))


## Your best score on a track with a car, or -1 for none.       WIRE: sim save data.
static func best_score(track: String, car: String) -> int:
	return int(store.scores.get(_key(track, car), -1))


## True when a ghost of the best run is saved for the track and car.       WIRE: sim replay/save data.
static func has_ghost(track: String, car: String) -> bool:
	return record(track, car) != null and bool(store.ghosts.get(_key(track, car), false))


## The four medal times of a track for a car (s), or {} when none were made.       WIRE: sim medals.
static func medal_times(track: String, car: String) -> Dictionary:
	for t in fixture().tracks:
		if t.id == track:
			return t.medals.get(car, {})
	return {}


## The medal a time earns ("author" ... "bronze"), or "" (none, no time or no medal times).
## To the millisecond the HUD shows (medals.js medalFor).
static func medal_for(medals: Dictionary, time: Variant) -> String:
	if medals.is_empty() or time == null or float(time) <= 0.0:
		return ""
	var ms := int(roundf(float(time) * 1000.0))
	for m in UiStyle.MEDAL_ORDER:
		if ms <= int(roundf(float(medals[m]) * 1000.0)):
			return m
	return ""


## The next medal to aim for with best time `time` (null: none yet): {medal, time}, or {} when
## the author medal is won or there are no medals (medals.js nextMedal).
static func next_medal(medals: Dictionary, time: Variant) -> Dictionary:
	if medals.is_empty():
		return {}
	var got := medal_for(medals, time)
	var k := UiStyle.MEDAL_ORDER.find(got) - 1 if got != "" else UiStyle.MEDAL_ORDER.size() - 1
	return {"medal": UiStyle.MEDAL_ORDER[k], "time": float(medals[UiStyle.MEDAL_ORDER[k]])} if k >= 0 else {}


## The saved AI network's summary for the menu.       WIRE: ai/ (the loaded network's meta).
static func ai_status() -> Dictionary:
	var n: Variant = store.network
	if n == null:
		return {"ready": false}
	var out: Dictionary = (n as Dictionary).duplicate()
	out.ready = true
	return out


## The AI's best lap (circuits) or finish (sprints) on a track from training, or -1.
static func ai_best(track_index: int) -> float:
	var st := ai_status()
	if not st.ready:
		return -1.0
	var info := track_info(track_index)
	var b: Variant = st.get("best_times", {}).get(info.id)
	if not (b is Dictionary):
		return -1.0
	var v: Variant = b.get("lap" if info.closed else "finish")
	return float(v) if v != null else -1.0


## The AI network's input and output names (sensors.js INPUT_LABELS / OUTPUT_LABELS).       WIRE: ai/.
static func network_labels() -> Dictionary:
	return {"inputs": fixture().input_labels, "outputs": fixture().output_labels}


# ---------------------------------------------------------------- settings

## A remembered setting ("car", "ghost", "quality", "fullscreen", "vsync").       WIRE: sim save data.
static func get_setting(key: String) -> Variant:
	return store.settings.get(key, SETTING_DEFAULTS.get(key))


static func set_setting(key: String, value: Variant) -> void:
	store.settings[key] = value
	if on_setting_changed.is_valid():
		on_setting_changed.call(key, value)


## The picked car's id (unknown ids give the racer).
static func picked_car() -> String:
	var id := str(get_setting("car"))
	return id if car_ids().has(id) else car_ids()[0]


# ---------------------------------------------------------------- internals

static func fixture() -> Dictionary:
	if _fixture.is_empty():
		_fixture = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_PATH))
	return _fixture


## The script of global class `name_`, or null when that class isn't in the project (yet).
static func _global_script(name_: String) -> Script:
	for d in ProjectSettings.get_global_class_list():
		if d["class"] == name_:
			return load(d["path"])
	return null


## True when `script` declares function `fn` (static functions included).
static func _has_static(script: Script, fn: String) -> bool:
	for m in script.get_script_method_list():
		if m["name"] == fn:
			return true
	return false


## Forget everything stored and cached (tests and previews).
static func reset() -> void:
	store = {"records": {}, "scores": {}, "ghosts": {}, "settings": {}, "network": null}
	_maps.clear()
