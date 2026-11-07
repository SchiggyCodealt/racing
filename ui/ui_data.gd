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
##   medals       sim/ Medals (data/medals.json, made by tools/medals.gd) once that file exists;
##                until then the fixture's medal times (the web's medals.json).
##   records, best scores, ghosts, settings: sim/ SaveData (the save file in user://) once the
##                game calls use_save_data(true) (game/app.gd does at start-up); until then (tests,
##                previews) an in-memory store (`store`), which they fill.
##   the AI network: the game hands the picked car's network summary over with set_ai_status
##                (game/app.gd, from that car's network file); the input / output names come from
##                ai/sensors.gd.
##
## Shapes returned (plain Dictionaries, so nothing here depends on sim/ types):
##   track_info(i)   {id, name, difficulty, description, closed, laps, length, sprint_length, theme,
##                   surfaces (the road surfaces for the menu: "Asphalt", "Asphalt + dirt", ...)}
##   track_map(i)    see TrackMapView.make_map: {points, size, start, finish (or null), closed}
##   car_info(id)    {id, name, description, color, accent, top, mass, bars {speed, acceleration,
##                   grip, drift, nitro}, rev {idle_rpm, redline, upshift_rpm}}
##   car_profile(id) {parts: [{mat, pts: PackedVector2Array of (z, y) m}], wheels: [[z, r]]}
##   record(t, c)    {time, splits} or null;  best_score(t, c) int or -1;  has_ghost(t, c) bool
##   medal_times(t, c) {author, gold, silver, bronze} (s) or {} (none for this track and car)
##   ai_status()     {ready, generation, fitness, sizes, trained_on [track ids], walls, best_times {id: {lap, finish}},
##                   car (whose network it is: the picked car), trained_car (the car it was trained with)}
##   the career (v6.5.0): money() and points() (int), owns_car(id), car_price(id), buy_car(id) ->
##                   {ok, error, price, short}: sim/ Economy and SaveData in the game; in tests the
##                   in-memory store's "career" {money, points, cars, paid}
##   opponents       opponent() (the picked opponent: an AI level id or "mine", the player's own
##                   network), opponent_levels(t, c) [{id, name, blurb, time (s or -1), pays {money,
##                   points} (what beating it would pay now; 0 when paid), paid (bool)}]
##   car upgrades (v6.11.0) upgrade_parts() [{id, name, what}], upgrade_levels(car) [4 ints 0..3],
##                   upgrade_price(car, part) (the next level's, 0 at the top), upgrade_cost(car, part,
##                   level), buy_upgrade(car, part) -> {ok, error, price, level, short}, car_bars(car)
##                   (the stat bars with the levels bought), car_stats(car) ({top, ...} with them);
##                   sim/ Upgrades + SaveData in the game, the store's career.upgrades {car: levels}
##                   in tests
##   locked tracks (v6.8.0) track_open(i) (bool), track_lock(i) {medal, index, name} (what opens track i:
##                   that medal on track `index`, called `name`; {} when open), open_track_count();
##                   sim/ Unlocks in the game, the store's career.tracks_open in tests (null: all open).
##                   mark_new_track(id) / is_new_track(id) / clear_new_tracks(): the menu's NEW mark on a
##                   track a finish just opened (this session only)
##   championships (v6.14.0) cup_list() [{id, name, blurb, number ("1"), open, missing (the locked tracks'
##                   names), difficulty (1-5), tracks [{id, name, number ("03"), open}], trophies {level: best
##                   place}}], cup_trophies() {cup: {level: place}}, cup_pays(cup, level, place) {money, points}
##                   (not paid yet), cup_view(run) (a CupRun for the standings: {cup, name, level, level_name,
##                   car_name, done, count, finished, place, rows [{pos, id, name, color, places, points, me}],
##                   races [{id, name, number}], next {id, name, number, slot}}; {} for null); sim/ Cups and
##                   SaveData in the game, the store's career.cups {trophies, paid} in tests

const FIXTURE_PATH := "res://ui/fixtures/web_v5.json"
const TRACKS_JSON := "res://data/tracks.json"
const MEDALS_JSON := "res://data/medals.json"
const TrackMapView := preload("res://ui/track_map_view.gd")

## Settings and their defaults (the web's trackrush.settings plus the Godot port's display settings).
const SETTING_DEFAULTS := {"car": "racer", "ghost": true, "quality": "high", "fullscreen": false, "vsync": true, "ui_scale": "auto",
	"opponent": "rookie", "grime": true, "vol_master": 1.0, "vol_music": 0.7, "vol_sfx": 0.8, "vol_engine": 0.8, "mute_unfocused": true}
## The menu's opponent choice for the player's own trained network (the others are AI level ids).
const MY_AI := "mine"
## Score rules the menu's tooltips quote (score.js SCORE.comboMax).
const COMBO_MAX := 5

## In-memory save data (tests and previews; the game reads and writes SaveData instead):
##   records  {"track_id|car_id": {time, splits}},  scores {"track_id|car_id": int},
##   ghosts   {"track_id|car_id": true},  settings {key: value},
##   network  null or {generation, fitness, sizes, trained_on, walls, best_times}
static var store := {"records": {}, "scores": {}, "ghosts": {}, "settings": {}, "network": null, "career": _new_career()}

## Emitted-style hook: called with (key, value) after set_setting (the game applies quality etc.).
static var on_setting_changed: Callable = Callable()
## True: records, scores, ghosts and settings are the save file's (SaveData), see use_save_data.
static var _save := false

static var _fixture: Dictionary = {}
static var _tracks: Array = []       # BuiltTrack-like objects (px, pz, closed, ...) or [] for the fixture
static var _maps: Dictionary = {}    # track index -> map dictionary
static var _world_profiles: Variant = null   # CarModel.profile works: null not asked yet
static var _tried_tracks := false            # sim/ Tracks asked already
static var _cars_class: Variant = null       # sim/ Cars script, false when missing, null not asked yet
static var _surfaces_script: Variant = null  # sim/ Surfaces script, false when missing, null not asked yet


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
			"surfaces": _surfaces_of(t),
		}
	var f: Dictionary = fixture().tracks[i]
	return {
		"id": f.id, "name": f.name, "difficulty": int(f.difficulty), "description": f.description,
		"closed": f.closed, "laps": int(f.laps), "length": float(f.length), "theme": f.theme,
		"sprint_length": float(f.sprint_length), "surfaces": "Asphalt",
	}


## The road surfaces of a built track for the menu (sim/ Surfaces.summary: "Asphalt + dirt"),
## "Asphalt" when sim/ can't tell.
static func _surfaces_of(t: Object) -> String:
	if _surfaces_script == null:
		var sc := _global_script("Surfaces")
		_surfaces_script = sc if sc != null else false
	if not (_surfaces_script is Script) or not t.has_method("surfaces_used"):
		return "Asphalt"
	return str((_surfaces_script as Script).call("summary", t))


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


## Read and write the game's save file (SaveData, sim/save.gd) instead of the in-memory store
## (the game turns it on at start-up; reset() turns it off again for tests).
static func use_save_data(on: bool = true) -> void:
	_save = on


## Your best time and splits on a track with a car, or null.
static func record(track: String, car: String) -> Variant:
	if _save:
		var r := SaveData.get_record(track, car)
		return {"time": r.time, "splits": r.splits} if not r.is_empty() else null
	return store.records.get(_key(track, car))


## Your best score on a track with a car, or -1 for none.
static func best_score(track: String, car: String) -> int:
	if _save:
		var b := SaveData.get_best_score(track, car)
		return int(b.score) if not b.is_empty() else -1
	return int(store.scores.get(_key(track, car), -1))


## True when a ghost of the best run is saved for the track and car (and fits this track's
## layout and laps, the car and the physics: Replay.ghost_fits, as the web menu's "Saved").
static func has_ghost(track: String, car: String) -> bool:
	if _save:
		if record(track, car) == null:
			return false
		_ensure_tracks()
		for t: Variant in _tracks:
			if t is BuiltTrack and (t as BuiltTrack).id == track:
				var bt: BuiltTrack = t
				return Replay.ghost_fits(SaveData.load_ghost(track, car), bt, bt.laps if bt.closed else 1, car)
		return false
	return record(track, car) != null and bool(store.ghosts.get(_key(track, car), false))


## The four medal times of a track for a car (s), or {} when none were made: sim/ Medals
## (data/medals.json) for the real tracks once that file is made, else the fixture's.
static func medal_times(track: String, car: String) -> Dictionary:
	var real: Variant = _sim_medals(track, car)
	if real != null:
		return real
	for t in fixture().tracks:
		if t.id == track:
			return t.medals.get(car, {})
	return {}


## sim/ Medals' times for a real track ({} when none fit this car, layout, laps and physics),
## or null when there is no such data (no sim/, no data/medals.json yet, a fixture track).
static func _sim_medals(track: String, car: String) -> Variant:
	_ensure_tracks()
	if _tracks.is_empty() or not FileAccess.file_exists(MEDALS_JSON):
		return null
	var medals := _global_script("Medals")
	if medals == null or not medals.can_instantiate():
		return null
	for t in _tracks:
		if str(t.get("id")) == track:
			var m: Dictionary = medals.call("medal_times", t, car)
			var out := {}
			for k in UiStyle.MEDAL_ORDER:
				if m.has(k):
					out[k] = float(m[k])
			return out if out.size() == UiStyle.MEDAL_ORDER.size() else {}
	return null


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


## The picked car's AI network summary for the menu (the game hands it over: set_ai_status);
## {ready: false} when that car has none.
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


## The game's AI network summary of the picked car for the menu ({generation, fitness, sizes,
## trained_on, walls, best_times, car, trained_car}), or null when that car has no network.
static func set_ai_status(info: Variant) -> void:
	store.network = info


## The AI network's input and output names (ai/sensors.gd INPUT_LABELS / OUTPUT_LABELS; the
## fixture's when the AI isn't in the project).
static func network_labels() -> Dictionary:
	var s := _global_script("Sensors")
	if s != null and s.can_instantiate():
		var ins: Variant = s.get("INPUT_LABELS")
		var outs: Variant = s.get("OUTPUT_LABELS")
		if ins != null and outs != null:
			return {"inputs": Array(ins), "outputs": Array(outs)}
	return {"inputs": fixture().input_labels, "outputs": fixture().output_labels}


# ---------------------------------------------------------------- the career (v6.5.0)

## (tracks_open: null = every track open, else the ids opened besides the first: Unlocks' rule)
static func _new_career() -> Dictionary:
	return {"money": 0, "points": 0, "cars": ["racer"], "paid": {}, "prices": {}, "tracks_open": null, "upgrades": {}}


## The career's money (the save file's in the game).
static func money() -> int:
	return SaveData.get_money() if _save else int(store.career.money)


## The career's points.
static func points() -> int:
	return SaveData.get_points() if _save else int(store.career.points)


## True when car `id` is owned (can be driven).
static func owns_car(id: String) -> bool:
	return SaveData.owns_car(id) if _save else (store.career.cars as Array).has(id)


## What car `id` costs in the shop (0 for a car owned from the start).
static func car_price(id: String) -> int:
	if _save or not (store.career.prices as Dictionary).has(id):
		var cars := _cars_script()
		return int((cars.call("get_car", id) as Dictionary).get("price", 0)) if cars != null else 0
	return int(store.career.prices[id])


## Buy car `id` (Economy.buy in the game): {ok, error ("" | "owned" | "money" | "unknown"), price, short}.
static func buy_car(id: String) -> Dictionary:
	if _save:
		return Economy.buy(id)
	var c: Dictionary = store.career
	var p := car_price(id)
	if (c.cars as Array).has(id):
		return {"ok": false, "error": "owned", "price": p, "short": 0}
	if int(c.money) < p:
		return {"ok": false, "error": "money", "price": p, "short": p - int(c.money)}
	c.money = int(c.money) - p
	(c.cars as Array).append(id)
	return {"ok": true, "error": "", "price": p, "short": 0}


# ---------------------------------------------------------------- car upgrades (v6.11.0)

## The parts, in the picker's order: [{id, name, what, max}].
static func upgrade_parts() -> Array:
	var out: Array = []
	for p: Dictionary in Upgrades.PARTS:
		out.append({"id": p.id, "name": p.name, "what": p.what, "max": Upgrades.MAX_LEVEL})
	return out


## Car `id`'s upgrade levels [engine, tyres, nitro, loose] (all 0 for a car not owned).
static func upgrade_levels(id: String) -> PackedInt32Array:
	if _save:
		return SaveData.get_upgrades(id)
	if not owns_car(id):
		return Upgrades.stock()
	return Upgrades.clean((store.career.get("upgrades", {}) as Dictionary).get(id))


## The price of level `level` of part `part` on car `id`.
static func upgrade_cost(id: String, part: String, level: int) -> int:
	return Upgrades.price(id, part, level)


## The price of the next level of part `part` on car `id` (0 when every level is bought).
static func upgrade_price(id: String, part: String) -> int:
	var i := Upgrades.index_of(part)
	return Upgrades.price(id, part, upgrade_levels(id)[i] + 1) if i >= 0 else 0


## Buy the next level of part `part` for car `id` (Economy.buy_upgrade in the game):
## {ok, error ("" | "locked" | "max" | "money" | "unknown"), price, level, short}.
static func buy_upgrade(id: String, part: String) -> Dictionary:
	if _save:
		return Economy.buy_upgrade(id, part)
	var i := Upgrades.index_of(part)
	if i < 0 or not car_ids().has(id):
		return {"ok": false, "error": "unknown", "price": 0, "level": 0, "short": 0}
	var lv := upgrade_levels(id)
	var p := Upgrades.price(id, part, lv[i] + 1)
	var c: Dictionary = store.career
	var err := ""
	if not owns_car(id):
		err = "locked"
	elif lv[i] >= Upgrades.MAX_LEVEL:
		err = "max"
	elif int(c.money) < p:
		err = "money"
	else:
		c.money = int(c.money) - p
		lv[i] += 1
		if not (c.get("upgrades") is Dictionary):
			c.upgrades = {}
		c.upgrades[id] = Array(lv)
	return {"ok": err == "", "error": err, "price": p if err != "max" else 0, "level": upgrade_levels(id)[i],
		"short": p - int(c.money) if err == "money" else 0}


## Car `id`'s stat bars with the upgrades bought (car_info(id).bars are the stock car's).
static func car_bars(id: String) -> Dictionary:
	return Upgrades.bars(id, upgrade_levels(id))


## Car `id`'s measured stats with the upgrades bought ({top, accel100, ..., grip, ...}).
static func car_stats(id: String) -> Dictionary:
	return Upgrades.stats(id, upgrade_levels(id))


## The picked opponent of Race the AI / Watch the AI: an AI level id (sim/opponents.gd) or MY_AI.
static func opponent() -> String:
	var v := str(get_setting("opponent"))
	return v if v == MY_AI or Opponents.rank(v) >= 0 else str(SETTING_DEFAULTS.opponent)


## The AI opponents of a track with a car for the menu, slowest first: [{id, name, blurb, time (s;
## -1 when there is none for this track and car), pays {money, points} (what beating it would
## pay now, with the levels below it not paid yet), paid (it was beaten before)}].
static func opponent_levels(track: String, car: String) -> Array:
	var out: Array = []
	var paid: PackedStringArray = SaveData.paid_rewards(track, car) if _save else \
		PackedStringArray(store.career.paid.get("%s|%s" % [track, car], []))
	for l: Dictionary in Opponents.LEVELS:
		var p := Economy.payout(track, "", String(l.id), paid)
		out.append({"id": l.id, "name": l.name, "blurb": l.blurb, "time": Opponents.time_of(track, car, String(l.id)),
			"pays": {"money": p.money, "points": p.points}, "paid": paid.has(Economy.AI_PREFIX + String(l.id))})
	return out


## (v6.13) What finishing `place` in a field of level `level` pays now on a track with a car (the place
## rewards not paid yet: {money, points}).
static func field_pays(track: String, car: String, level: String, place: int) -> Dictionary:
	var paid: PackedStringArray = SaveData.paid_rewards(track, car) if _save else \
		PackedStringArray(store.career.paid.get("%s|%s" % [track, car], []))
	var p := Economy.payout(track, "", "", paid, level, place)
	return {"money": p.money, "points": p.points}


# ---------------------------------------------------------------- championships (v6.14.0)

## Every cup's best place per level: {cup id: {level id: place}}.
static func cup_trophies() -> Dictionary:
	if _save:
		return SaveData.cup_trophies()
	var c: Variant = store.career.get("cups", {})
	return ((c as Dictionary).get("trophies", {}) as Dictionary).duplicate(true) if c is Dictionary else {}


## The cups for the cup screen, easiest first (see the header).
static func cup_list() -> Array:
	var out: Array = []
	var tro := cup_trophies()
	for k in Cups.ids().size():
		var id: String = Cups.ids()[k]
		var trs: Array = []
		var miss: PackedStringArray = []
		var diff := 0.0
		for tid: String in Cups.tracks_of(id):
			var i := Tracks.index_of(tid)
			var open := track_open(i)
			trs.append({"id": tid, "name": String(Tracks.def(tid).get("name", tid)), "number": UiFormat.track_number(i), "open": open})
			if not open:
				miss.append(String(Tracks.def(tid).get("name", tid)))
			diff += float(Tracks.def(tid).get("difficulty", 1))
		out.append({"id": id, "name": Cups.name_of(id), "blurb": String(Cups.cup(id).get("blurb", "")), "number": str(k + 1), "open": miss.is_empty(),
			"missing": ", ".join(miss), "difficulty": roundi(diff / maxf(1.0, trs.size())), "tracks": trs, "trophies": tro.get(id, {})})
	return out


## What `place` in cup `cup_id` at `level` would pay now (the cup rewards not paid yet): {money, points}.
static func cup_pays(cup_id: String, level: String, place: int) -> Dictionary:
	var paid: PackedStringArray = SaveData.cup_paid() if _save else PackedStringArray((store.career.get("cups", {}) as Dictionary).get("paid", []))
	var p := Economy.cup_payout(cup_id, level, place, paid)
	return {"money": p.money, "points": p.points}


## The standings of cup run `run` for the cup screen (see the header); {} for null.
static func cup_view(run: CupRun) -> Dictionary:
	if run == null:
		return {}
	var rows: Array = []
	for r: Dictionary in run.table():
		var id := String(r.id)
		var me := id == Cups.PLAYER
		var d := Field.driver(id)
		var col: Variant = Color(String(d.get("color", "#ffffff"))) if not me else car_info(run.car).get("color", UiStyle.ACCENT)
		rows.append({"pos": int(r.pos), "id": id, "name": "You" if me else String(d.get("name", id)), "color": col if col is Color else Color(str(col)),
			"places": Array(r.places), "points": int(r.points), "me": me})
	var races: Array = []
	for tid: String in Cups.tracks_of(run.cup):
		var i := Tracks.index_of(tid)
		races.append({"id": tid, "name": String(Tracks.def(tid).get("name", tid)), "number": UiFormat.track_number(i)})
	var out := {"cup": run.cup, "name": Cups.name_of(run.cup), "level": run.level, "level_name": Opponents.level_name(run.level), "car": run.car,
		"car_name": String(car_info(run.car).get("name", run.car)), "done": run.races_done(), "count": run.race_count(), "finished": run.finished(),
		"place": run.place(), "rows": rows, "races": races, "next": {}}
	if not run.finished():
		var nt := run.next_track()
		out.next = {"id": nt, "name": String(Tracks.def(nt).get("name", nt)), "number": UiFormat.track_number(Tracks.index_of(nt)),
			"slot": run.grid().find(Cups.PLAYER) + 1}
	return out


# ---------------------------------------------------------------- locked tracks (v6.8.0)

## The tracks a finish just opened, for the menu's NEW mark (track id -> true; this session only).
static var _new_tracks: Dictionary = {}


## True when track `i` can be driven (and raced against the AI): the first track always, any
## other once bronze or better was won on the track before it (sim/unlocks.gd), or every track
## after the terminal's `unlock tracks`. Watch the AI and Train the AI work on every track.
static func track_open(i: int) -> bool:
	if i <= 0:
		return true
	if _save:
		return Unlocks.is_open(track_id(i))
	var open: Variant = store.career.get("tracks_open")
	return not (open is Array) or (open as Array).has(track_id(i))


## What opens locked track `i`: {medal ("bronze"), index (the track before it), name (its name)};
## {} when the track is open.
static func track_lock(i: int) -> Dictionary:
	if track_open(i):
		return {}
	return {"medal": Unlocks.MEDAL, "index": i - 1, "name": str(track_info(i - 1).name)}


static func open_track_count() -> int:
	var n := 0
	for i in track_count():
		if track_open(i):
			n += 1
	return n


## A finish opened track `id`: the menu marks its tile NEW (until it is picked or the menu is left).
static func mark_new_track(id: String) -> void:
	_new_tracks[id] = true


static func is_new_track(id: String) -> bool:
	return _new_tracks.has(id)


## Drop the NEW mark of track `id` ("": of every track).
static func clear_new_tracks(id: String = "") -> void:
	if id == "":
		_new_tracks.clear()
	else:
		_new_tracks.erase(id)


# ---------------------------------------------------------------- settings

## A remembered setting ("car", "ghost", "quality", "fullscreen", "vsync", "ui_scale", "opponent",
## "grime", v6.12's "vol_master", "vol_music", "vol_sfx", "vol_engine", "mute_unfocused"), from
## the save file in the game. Quality "auto" (the save file's default: start high and let
## the frame-time governor step down) reads as "high", the Settings screen's matching choice.
static func get_setting(key: String) -> Variant:
	if _save:
		var d: Variant = SETTING_DEFAULTS.get(key)
		var v: Variant = SaveData.get_setting(key, d)
		if key == "quality":
			return "high" if str(v) == "auto" else v
		if key == "ui_scale":
			return v if v is float or v is int or str(v) == "auto" else d
		return d if d != null and typeof(v) != typeof(d) else v # (a stored value of another type reads as the default)
	return store.settings.get(key, SETTING_DEFAULTS.get(key))


static func set_setting(key: String, value: Variant) -> void:
	if _save:
		SaveData.set_setting(key, value)
	else:
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
	_save = false
	store = {"records": {}, "scores": {}, "ghosts": {}, "settings": {}, "network": null, "career": _new_career()}
	_new_tracks.clear()
	_maps.clear()
