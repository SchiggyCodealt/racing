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
##   Tracks.build_asphalt(id) -> BuiltTrack of `id` without its road surfaces (cached): the track as
##                            the browser version (v5) has it, for the parity tools and checks
##   Tracks.signature(id)  -> the built track's signature (BuiltTrack.signature(); "" if unknown)
##   Tracks.legacy_signature(id) -> its signature up to v6.2 (LEGACY_SIGS), for data saved without one
##
## Built tracks are read-only once built (physics, AI and rendering share
## them; the only lazily filled parts are the gate and physics caches).

const DATA_PATH: String = "res://data/tracks.json"
## Every track's signature up to v6.2, before road surfaces (all asphalt then). Records and best
## scores saved before v6.3, and AI best times in network files, carry no signature: they were
## made on these, so they count only while the track still has this signature (sim/save.gd,
## ui/ui_data.gd). A track whose layout or surfaces change gets a new signature, and what was
## made on the old one stops counting.
const LEGACY_SIGS: Dictionary = {
	"rookie-oval": "1083:2167", "hairpin-valley": "1209:2417", "ramp-rally": "1187:2374",
	"banked-speedway": "1422:2844", "technical-trial": "1296:2591", "grand-marathon": "3735:7468",
	"coastal-gp": "1448:2895", "mountain-pass": "2393:4783", "canyon-run": "1426:2853",
	"night-highway": "1558:3117", "lighthouse-bay": "1175:2351", "seaside-stunts": "1654:3306",
}

static var _defs: Array[Dictionary] = []
static var _by_id: Dictionary = {}
static var _built: Dictionary = {}
static var _sigs: Dictionary = {}
static var _asphalt: Dictionary = {}
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


## Track `id` all asphalt (its "surfaces" left out; cached), or null when unknown. A track
## without surfaces is the same BuiltTrack as build(id).
static func build_asphalt(id: String) -> BuiltTrack:
	var t: BuiltTrack = build(id)
	if t == null or not t.has_surfaces():
		return t
	_mutex.lock()
	var a: BuiltTrack = _asphalt.get(id)
	if a == null:
		var d: Dictionary = (_by_id[id] as Dictionary).duplicate(true)
		d.erase("surfaces")
		a = build_def(d)
		_asphalt[id] = a
	_mutex.unlock()
	return a


## The signature of track `id` (BuiltTrack.signature(): layout and surfaces), "" when unknown.
static func signature(id: String) -> String:
	_mutex.lock()
	var known: bool = _sigs.has(id)
	var sig: String = _sigs.get(id, "")
	_mutex.unlock()
	if known:
		return sig
	var t: BuiltTrack = build(id)
	sig = t.signature() if t != null else ""
	_mutex.lock()
	_sigs[id] = sig
	_mutex.unlock()
	return sig


## The signature track `id` had up to v6.2 (LEGACY_SIGS), "" when unknown: what data saved
## without a signature was made on.
static func legacy_signature(id: String) -> String:
	return String(LEGACY_SIGS.get(id, ""))


## A fresh BuiltTrack from any definition (not cached), e.g. a test road.
## Its lazily cached data (car physics slope/curvature, the gates of a full race and of
## one lap) is filled here, so threads can share the track read-only.
static func build_def(d: Dictionary) -> BuiltTrack:
	var t: BuiltTrack = TrackBuilder.build_track(d)
	Car.track_phys(t)
	TrackBuilder.get_gates(t, t.laps if t.closed else 1)
	TrackBuilder.get_gates(t, 1)
	return t
