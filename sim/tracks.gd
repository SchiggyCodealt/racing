class_name Tracks
extends RefCounted
## tracks.gd: the built-in tracks, one simple entry point for every folder.
## ------------------------------------------------------------------
## The definitions live in data/tracks.json (written by tools/gen_tracks.gd,
## the same data as web/src/tracks/trackData.js: id, name, difficulty,
## description, type, laps / startAt + runOff, width, theme, checkpoints,
## points). Built tracks are cached, so every caller shares one per id.
##
##   Tracks.ids()          -> ["rookie-oval", "hairpin-valley", ...] (menu order)
##   Tracks.def(id)        -> the definition Dictionary (or {} for an unknown id)
##   Tracks.build(id)      -> BuiltTrack (cached; null for an unknown id)
##   Tracks.index_of(id)   -> menu position (0-based), -1 if unknown
##   Tracks.build_def(def) -> BuiltTrack from any definition (not cached)
##
## Built tracks are read-only once built (physics, AI and rendering share
## them; the only lazily filled parts are the gate and physics caches).

const DATA_PATH: String = "res://data/tracks.json"

static var _defs: Array[Dictionary] = []
static var _by_id: Dictionary = {}
static var _built: Dictionary = {}
static var _mutex: Mutex = Mutex.new()


static func _load() -> void:
	if not _defs.is_empty():
		return
	var text: String = FileAccess.get_file_as_string(DATA_PATH)
	var data: Variant = JSON.parse_string(text)
	if not (data is Array):
		push_error("Tracks: cannot read %s" % DATA_PATH)
		return
	for d: Variant in data:
		if d is Dictionary:
			_defs.append(d)
			_by_id[String(d.id)] = d


## Track ids in menu order.
static func ids() -> PackedStringArray:
	_mutex.lock()
	_load()
	var out: PackedStringArray = []
	for d in _defs:
		out.append(String(d.id))
	_mutex.unlock()
	return out


## Every definition, in menu order.
static func defs() -> Array[Dictionary]:
	_mutex.lock()
	_load()
	_mutex.unlock()
	return _defs


## The definition of track `id` ({} when unknown).
static func def(id: String) -> Dictionary:
	_mutex.lock()
	_load()
	var d: Dictionary = _by_id.get(id, {})
	_mutex.unlock()
	return d


static func index_of(id: String) -> int:
	return ids().find(id)


## The built track `id` (cached), or null when unknown.
static func build(id: String) -> BuiltTrack:
	_mutex.lock()
	_load()
	var t: BuiltTrack = _built.get(id)
	if t == null and _by_id.has(id):
		t = build_def(_by_id[id])
		_built[id] = t
	_mutex.unlock()
	return t


## A fresh BuiltTrack from any definition (not cached), e.g. a test road.
## Its lazily cached data (car physics slope/curvature, the gates of a full race and of
## one lap) is filled here, so threads can share the track read-only.
static func build_def(d: Dictionary) -> BuiltTrack:
	var t: BuiltTrack = TrackBuilder.build_track(d)
	Car.track_phys(t)
	TrackBuilder.get_gates(t, t.laps if t.closed else 1)
	TrackBuilder.get_gates(t, 1)
	return t
