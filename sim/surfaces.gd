class_name Surfaces
extends RefCounted
## surfaces.gd: the road surfaces (asphalt, dirt, packed snow) as data (v6.3).
## ------------------------------------------------------------------
## Every surface is one entry of DEFS: what the car physics does on it (CarSpec-independent
## numbers) and how the world draws it. A car's grip on a surface is its own share of its
## asphalt grip: the CarSpec field named by `car_grip` (dirt_grip, snow_grip), or the
## surface's `grip` for a car without one. Asphalt is entry 0 and changes nothing: a track
## without other surfaces runs the physics of v6.2 bit for bit.
##
## Physics fields (sim/car.gd reads them per axle, blended where two surfaces meet):
##   grip       share of the asphalt grip kept on it, for a car without its own `car_grip`
##   car_grip   the CarSpec field holding each car's share ("" = always 1)
##   roll       rolling resistance, × the car's roll_resist (loose ground drags)
##   stiffness  how fast the tyre force builds with slip, × the car's (below 1: the force peaks
##              at a bigger slip angle, so slides start sooner and are easier to hold)
##   esc        share of the stability control's corrective moment it can still make (it brakes
##              single wheels, which a loose surface lets slide)
## Look fields (world/): road (sRGB colour of the road; asphalt keeps its own texture), rough
##   and bumps (the road's roughness and the strength of its relief), dust (what the tyres
##   throw up: "" nothing, "dust", "snow"; also how the barriers look along it: dusty feet or
##   snow on top), marks (tyre mark colour), rumble (camera rumble at speed, 0..1), lines
##   (whether painted lines and kerbs are drawn on it), spray (v6.4, optional: the colour of
##   what the tyres throw up; without it the road's colour, lightened; snow's is a shaded
##   blue-grey so it shows against the white road). The road shader has slots for table
##   entries 1 and 2 (world/shaders/road_surface.gdshader): a fourth surface needs a third.
##
## Track data: a definition's "surfaces" is a list of [surface id, from, to] ranges, where
## from / to are control-point indices with a fraction (like checkpoints, which are whole
## control points), made by tools/gen_tracks.gd from the turtle's surface() calls.
## TrackBuilder turns them into a surface per sample and blend weights smoothed over
## BLEND samples each side (about 10 m), so the grip never jumps.
##
##   Surfaces.count()          -> 3
##   Surfaces.index_of("dirt") -> 1 (-1 when unknown);  Surfaces.def(i), Surfaces.id(i)
##   Surfaces.car_grips(spec)  -> PackedFloat64Array, the car's grip share on every surface
##   Surfaces.summary(track)   -> "Asphalt + dirt" (the menu's line), Surfaces.shares(track)

const ASPHALT: int = 0
## Samples (2 m each) the blend between two surfaces spreads over on each side of the border.
const BLEND: int = 2

const DEFS: Array[Dictionary] = [
	{
		id = "asphalt", name = "Asphalt",
		grip = 1.0, car_grip = "", roll = 1.0, stiffness = 1.0, esc = 1.0,
		road = "#4a4a4c", rough = 1.0, bumps = 0.55, dust = "", marks = "#0d0d0d", rumble = 0.0, lines = true,
	},
	{
		id = "dirt", name = "Dirt",
		grip = 0.7, car_grip = "dirt_grip", roll = 3.0, stiffness = 0.75, esc = 0.6,
		road = "#8a6a48", rough = 0.95, bumps = 0.9, dust = "dust", marks = "#4a3524", rumble = 0.35, lines = false,
	},
	{
		id = "snow", name = "Packed snow",
		grip = 0.5, car_grip = "snow_grip", roll = 2.2, stiffness = 0.8, esc = 0.6,
		road = "#ccd6e1", rough = 0.6, bumps = 0.25, dust = "snow", marks = "#8d9cae", rumble = 0.15, lines = false,
		spray = "#7d95b6",
	},
]

static var _index: Dictionary = _make_index()


static func _make_index() -> Dictionary:
	var out: Dictionary = {}
	for i in DEFS.size():
		out[String(DEFS[i].id)] = i
	return out


static func count() -> int:
	return DEFS.size()


## The table index of surface `sid`, or -1 when unknown.
static func index_of(sid: String) -> int:
	return int(_index.get(sid, -1))


static func has(sid: String) -> bool:
	return _index.has(sid)


static func def(i: int) -> Dictionary:
	return DEFS[clampi(i, 0, DEFS.size() - 1)]


static func id(i: int) -> String:
	return String(def(i).id)


## The car's grip share on every surface, in table order (asphalt 1).
static func car_grips(spec: CarSpec) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(DEFS.size())
	for i in DEFS.size():
		var key: String = DEFS[i].car_grip
		out[i] = float(spec.get(key)) if key != "" and key in spec else float(DEFS[i].grip)
	return out


## Σ weight × value of every surface at fractional sample p of the track (values: a column,
## e.g. column("rumble")); the asphalt value on a track without surfaces.
static func mix_at(track: BuiltTrack, p: float, values: PackedFloat64Array) -> float:
	if track.surf_w.is_empty():
		return values[ASPHALT]
	var out: float = 0.0
	for s in mini(values.size(), track.surf_n):
		out += track.surface_weight(s, p) * values[s]
	return out


## A table column as numbers (physics: "roll", "stiffness", "esc"; look: "rumble", ...).
static func column(field: String) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for d: Dictionary in DEFS:
		out.append(float(d[field]))
	return out


## The share of the road length on each surface (index -> 0..1; only surfaces that are there).
static func shares(track: BuiltTrack) -> Dictionary:
	var out: Dictionary = {}
	var n: int = track.N if track.closed else track.count
	if track.surface.is_empty():
		return {ASPHALT: 1.0}
	for i in n:
		var s: int = track.surface[i]
		out[s] = float(out.get(s, 0.0)) + 1.0 / n
	return out


## The surfaces of a track for the menu, in table order: "Asphalt", "Asphalt + dirt",
## "Asphalt + dirt + packed snow" (later names in lower case).
static func summary(track: BuiltTrack) -> String:
	return summary_of(track.surfaces_used())


static func summary_of(ids: PackedStringArray) -> String:
	var parts: PackedStringArray = []
	for i in DEFS.size():
		if ids.has(String(DEFS[i].id)):
			var nm: String = DEFS[i].name
			parts.append(nm if parts.is_empty() else nm.to_lower())
	return " + ".join(parts) if not parts.is_empty() else String(DEFS[ASPHALT].name)
