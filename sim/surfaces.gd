class_name Surfaces
extends RefCounted
## surfaces.gd: the road surfaces (asphalt, dirt, packed snow; v6.23: gravel, sand, ice, mud) as data (v6.3).
## ------------------------------------------------------------------
## Every surface is one entry of DEFS: what the car physics does on it (CarSpec-independent
## numbers) and how the world draws it. A car's grip on a surface is its own share of its
## asphalt grip: the CarSpec field named by `car_grip` (dirt_grip, snow_grip), or the
## surface's `grip` for a car without one. Asphalt is entry 0 and changes nothing: a track
## without other surfaces runs the physics of v6.2 bit for bit.
## v6.23 (the rally stages): gravel, sand, ice and mud. A car has no grip number of its own for
## them: each takes the car's share on dirt or packed snow times its `scale` (gravel a little
## more than dirt, sand and mud less; ice well under packed snow), so the cars keep their order
## and the "loose grip" upgrade works on all of them.
##
## Physics fields (sim/car.gd reads them per axle, blended where two surfaces meet):
##   grip       share of the asphalt grip kept on it, for a car without its own `car_grip`
##   car_grip   the CarSpec field holding each car's share ("" = always 1)
##   scale      (v6.23, optional) the car's share × this, at most 1 (without it: the share itself)
##   roll       rolling resistance, × the car's roll_resist (loose ground drags)
##   stiffness  how fast the tyre force builds with slip, × the car's (below 1: the force peaks
##              at a bigger slip angle, so slides start sooner and are easier to hold)
##   esc        share of the stability control's corrective moment it can still make (it brakes
##              single wheels, which a loose surface lets slide)
##   brake      (v6.10) the brakes on it: the braking force and the tyres' grip for braking, × this
##              (the tyres dig in and a wedge of gravel or snow builds in front of them; the ABS
##              lets the wheels slip more there), so a car stops sooner than its cornering grip
##              alone would let it; each car keeps its own grip share, so their order stays
##   abs        (v6.10) share of that braking grip the ABS uses at full pedal (asphalt: 0.97, the
##              old rule); the rest is left for steering, so a braking car still turns in instead
##              of ploughing on (a friction ellipse: braking eats less of the cornering grip)
##   wall       (v6.10) wall friction × this: a car touching a barrier along it slides on and
##              loses less of its speed along the wall (the wall hit and the rub; the speed into
##              the wall still goes)
##   plan       (v6.23, optional, 1 without it) not physics: the share of the car's grip on it that
##              the autopilot plans its corner speeds with (sim/autopilot.gd: the medal times and
##              the tests' driver). On ice a car holds well under its tyres' peak through a long
##              bend (the rear steps out on the throttle), so the autopilot plans with 72 %
## Look fields (world/): road (sRGB colour of the road; asphalt keeps its own texture), rough
##   and bumps (the road's roughness and the strength of its relief), dust (what the tyres
##   throw up: "" nothing, "dust", "snow"; also how the barriers look along it: dusty feet or
##   snow on top), marks (tyre mark colour), grime (v6.10, was v6.3's camera "rumble": how much
##   mud or snow it throws at the screen, 0..1, world/screen_grime.gd), lines
##   (whether painted lines and kerbs are drawn on it), spray (v6.4, optional: the colour of
##   what the tyres throw up; without it the road's colour, lightened; snow's is a shaded
##   blue-grey so it shows against the white road).
##   v6.23: tex (the detail texture, world/textures.gd Tex.surface(): "loose" for dirt and snow, or
##   the surface's own), look ("earth", "snow" or "ice": which of the road shader's three looks
##   draws it) and style (four numbers for that look, see road_surface.gdshader), throw (optional:
##   "clumps" = the tyres throw lumps that fall again, like snow, instead of dust that hangs), slot
##   (1 or 2, see slots()).
##
## Slots (v6.23): the road shader, the tyre marks and the road mesh carry the weights of two
## surfaces besides asphalt, so a track can have any two of the table (plus asphalt). slots(track)
## says which: every surface the track uses takes its own `slot` when that is free, else the other
## (dirt 1 and snow 2, as before v6.23; gravel + mud, sand + gravel, ice + snow all fit).
##
## Track data: a definition's "surfaces" is a list of [surface id, from, to] ranges, where
## from / to are control-point indices with a fraction (like checkpoints, which are whole
## control points), made by tools/gen_tracks.gd from the turtle's surface() calls.
## TrackBuilder turns them into a surface per sample and blend weights smoothed over
## BLEND samples each side (about 10 m), so the grip never jumps.
##
##   Surfaces.count()          -> 7
##   Surfaces.index_of("dirt") -> 1 (-1 when unknown);  Surfaces.def(i), Surfaces.id(i)
##   Surfaces.car_grips(spec)  -> PackedFloat64Array, the car's grip share on every surface
##   Surfaces.summary(track)   -> "Asphalt + dirt" (the menu's line), Surfaces.shares(track)
##   Surfaces.slots(track)     -> [surface drawn in slot 1, in slot 2] (table indices, -1 = none)
##   Surfaces.slot_weights(track, i) -> Vector2: the physics weights of those two at sample i

const ASPHALT: int = 0
## Samples (2 m each) the blend between two surfaces spreads over on each side of the border.
const BLEND: int = 2

const DEFS: Array[Dictionary] = [
	{
		id = "asphalt", name = "Asphalt",
		grip = 1.0, car_grip = "", roll = 1.0, stiffness = 1.0, esc = 1.0, brake = 1.0, abs = 0.97, wall = 1.0,
		road = "#4a4a4c", rough = 1.0, bumps = 0.55, dust = "", marks = "#0d0d0d", grime = 0.0, lines = true,
	},
	{
		id = "dirt", name = "Dirt",
		grip = 0.7, car_grip = "dirt_grip", roll = 3.0, stiffness = 0.75, esc = 0.6, brake = 1.24, abs = 0.9, wall = 0.55,
		road = "#8a6a48", rough = 0.95, bumps = 0.9, dust = "dust", marks = "#4a3524", grime = 1.0, lines = false,
		tex = "loose", look = "earth", style = [1.0, 1.0, 0.0, 0.0], slot = 1,
	},
	{
		id = "snow", name = "Packed snow",
		grip = 0.5, car_grip = "snow_grip", roll = 2.2, stiffness = 0.8, esc = 0.6, brake = 1.28, abs = 0.9, wall = 0.45,
		road = "#ccd6e1", rough = 0.6, bumps = 0.25, dust = "snow", marks = "#8d9cae", grime = 0.85, lines = false,
		spray = "#7d95b6", tex = "loose", look = "snow", style = [0.0, 0.0, 0.0, 0.0], slot = 2,
	},
	# v6.23, the rally stages. style of the "earth" look: [wetness (damp patches and puddles; dirt 1),
	# ruts (how dark and deep the wheel tracks are; dirt 1), tint (how much the texture's second
	# channel varies the colour, stone by stone), sheen (wet gloss from its third channel)]
	{
		# a hard-packed gravel road: grey crushed stone, loose stones beside the wheel tracks
		id = "gravel", name = "Gravel",
		grip = 0.74, car_grip = "dirt_grip", scale = 1.06, roll = 2.4, stiffness = 0.8, esc = 0.65, brake = 1.2, abs = 0.9, wall = 0.6,
		road = "#9b958a", rough = 0.93, bumps = 1.0, dust = "dust", marks = "#5d574c", grime = 0.45, lines = false,
		spray = "#c3bdb0", tex = "gravel", look = "earth", style = [0.35, 0.75, 0.55, 0.0], slot = 1,
	},
	{
		# soft desert sand: it drags hard, lets go early and slides wide
		id = "sand", name = "Sand",
		grip = 0.58, car_grip = "dirt_grip", scale = 0.84, roll = 4.4, stiffness = 0.68, esc = 0.5, brake = 1.34, abs = 0.9, wall = 0.75,
		road = "#d8b87a", rough = 0.97, bumps = 0.6, dust = "dust", marks = "#a98650", grime = 0.25, lines = false,
		spray = "#e6d2a2", tex = "sand", look = "earth", style = [0.0, 1.35, 0.25, 0.0], slot = 2,
	},
	{
		# a frozen lake: bare ice, far less grip than packed snow, and it hardly drags; the snow banks
		# along it grab a car harder than a barrier on tarmac does (wall: leaning on them never pays)
		id = "ice", name = "Ice",
		grip = 0.4, car_grip = "snow_grip", scale = 0.78, roll = 1.2, stiffness = 0.78, esc = 0.55, brake = 1.12, abs = 0.88, wall = 2.0, plan = 0.72,
		road = "#a9cbe0", rough = 0.14, bumps = 0.35, dust = "snow", marks = "#eef4f9", grime = 0.3, lines = false,
		spray = "#d5e3f0", tex = "ice", look = "ice", style = [0.0, 0.0, 0.0, 0.0], slot = 1,
	},
	{
		# deep wet mud: heavy going, long slides, and it ends up all over the car and the screen
		id = "mud", name = "Mud",
		grip = 0.55, car_grip = "dirt_grip", scale = 0.8, roll = 4.0, stiffness = 0.7, esc = 0.5, brake = 1.2, abs = 0.9, wall = 0.75,
		road = "#553d29", rough = 0.62, bumps = 1.0, dust = "dust", throw = "clumps", marks = "#2c1e13", grime = 1.0, lines = false,
		spray = "#4d3724", tex = "mud", look = "earth", style = [2.3, 1.6, 0.2, 0.75], slot = 2,
	},
]
## The road shader's looks (DEFS.look -> its kind_1 / kind_2 number).
const LOOKS: PackedStringArray = ["earth", "snow", "ice"]

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
		if DEFS[i].has("scale") and key != "" and key in spec:
			out[i] = minf(1.0, out[i] * float(DEFS[i].scale))
	return out


## The two surfaces besides asphalt that the look of `track` carries: [slot 1, slot 2] as table
## indices, -1 for an empty slot. Each surface of the track, in table order, takes its own `slot`
## when free, else the other one (a third one is left out: tools/gen_tracks.gd refuses such a track).
static func slots(track: BuiltTrack) -> PackedInt32Array:
	var out := PackedInt32Array([-1, -1])
	if track == null or track.surface.is_empty():
		return out
	if track.slot_cache.size() == 2:
		return track.slot_cache
	var used := track.surfaces_used()
	for i in range(1, DEFS.size()):
		if not used.has(String(DEFS[i].id)):
			continue
		var k: int = clampi(int(DEFS[i].get("slot", 1)), 1, 2) - 1
		if out[k] >= 0:
			k = 1 - k
		if out[k] < 0:
			out[k] = i
	track.slot_cache = out
	return out


## The physics blend weights at sample i of the two surfaces in the slots (0 for an empty slot).
static func slot_weights(track: BuiltTrack, i: int) -> Vector2:
	if track == null or track.surf_w.is_empty():
		return Vector2.ZERO
	var sl := slots(track)
	var n := track.surf_n
	return Vector2(track.surf_w[i * n + sl[0]] if sl[0] >= 0 else 0.0, track.surf_w[i * n + sl[1]] if sl[1] >= 0 else 0.0)


## How a surface's spray flies: "clumps" (lumps thrown up that fall again: snow, ice, mud), "puffs"
## (dust that hangs in the air) or "" (nothing).
static func throw_of(i: int) -> String:
	var d := def(i)
	if d.has("throw"):
		return String(d.throw)
	return "clumps" if d.dust == "snow" else ("puffs" if d.dust == "dust" else "")


## Σ weight × value of every surface at fractional sample p of the track (values: a column,
## e.g. column("grime")); the asphalt value on a track without surfaces.
static func mix_at(track: BuiltTrack, p: float, values: PackedFloat64Array) -> float:
	if track.surf_w.is_empty():
		return values[ASPHALT]
	var out: float = 0.0
	for s in mini(values.size(), track.surf_n):
		out += track.surface_weight(s, p) * values[s]
	return out


## A table column as numbers (physics: "roll", "stiffness", "esc", "brake", "abs", "wall"; look: "grime", ...);
## `missing` for an entry without the field ("plan": 1).
static func column(field: String, missing: float = 0.0) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for d: Dictionary in DEFS:
		out.append(float(d.get(field, missing)))
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
