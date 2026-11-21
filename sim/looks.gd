class_name Looks
extends RefCounted
## looks.gd (v6.41.0): cosmetics, chosen for each car you own on the car page (SaveData's looks:
## `paint`, `livery`, `glow`, each an index into the lists below; 0, the default, is the car as it
## comes). Looks only: nothing here touches the physics, the AI or the medal times. Free.
## ------------------------------------------------------------------
##   paint    the body colour: Factory (the car's own, sim/cars.gd look.color) or one of PAINTS
##   livery   a pattern painted over the body by the car shader (world/shaders/car.gdshader `livery`):
##            Factory (the car's own stripes only) or one of five; drawn from the body's own box
##            (CarBuild.body_box: its length and height), so it fits every car
##   glow     underglow: a coloured light on the road under the car (world/car_model.gd), or Off
## The colours a livery uses: `trim` (white on a dark paint, near-black on a light one) and the car's
## accent (sim/cars.gd look.accent).
##
##   Looks.KEYS -> {paint: [0, top, 0], livery: [...], glow: [...]}  (SaveData's ranges)
##   Looks.paint_count() / livery_count() / glow_count()
##   Looks.paint(i) / livery(i) / glow(i) -> {id, name, ...} (i clamped)
##   Looks.paint_color(car_id, i) -> Color   (0: the car's own)
##   Looks.trim(paint) -> Color               (white or near-black, whichever stands out)
##   Looks.glow_color(i) -> Color (alpha 0 for Off)
##   Looks.text(looks) -> "Blue paint, Stripes livery, cyan underglow" ("factory looks" when all 0)

const PAINTS: Array[Dictionary] = [
	{id = "factory", name = "Factory"},
	{id = "red", name = "Red", color = "#d7263d"},
	{id = "orange", name = "Orange", color = "#ff6b1a"},
	{id = "yellow", name = "Yellow", color = "#f2c14e"},
	{id = "lime", name = "Lime", color = "#8cc63f"},
	{id = "green", name = "Green", color = "#1f8a4c"},
	{id = "teal", name = "Teal", color = "#2ec4b6"},
	{id = "blue", name = "Blue", color = "#3a86ff"},
	{id = "navy", name = "Navy", color = "#24408e"},
	{id = "purple", name = "Purple", color = "#6f4cff"},
	{id = "pink", name = "Pink", color = "#ff6fae"},
	{id = "white", name = "White", color = "#f1f2f4"},
	{id = "silver", name = "Silver", color = "#a9adb5"},
	{id = "black", name = "Black", color = "#24272e"},
]

## The car shader's `livery` is the index (0: none).
const LIVERIES: Array[Dictionary] = [
	{id = "factory", name = "Factory", what = "the car's own paint and stripes"},
	{id = "stripes", name = "Stripes", what = "twin racing stripes over the top, nose to tail"},
	{id = "twotone", name = "Two-tone", what = "the lower body in the car's accent colour"},
	{id = "sash", name = "Sash", what = "a broad diagonal band across the sides"},
	{id = "chequer", name = "Chequer", what = "a chequered band along the sides"},
	{id = "fade", name = "Fade", what = "the paint fading into the accent colour towards the tail"},
]

const GLOWS: Array[Dictionary] = [
	{id = "off", name = "Off"},
	{id = "cyan", name = "Cyan", color = "#19e3ff"},
	{id = "magenta", name = "Magenta", color = "#ff2bd6"},
	{id = "lime", name = "Lime", color = "#7dff3a"},
	{id = "amber", name = "Amber", color = "#ffb000"},
	{id = "red", name = "Red", color = "#ff3040"},
	{id = "blue", name = "Blue", color = "#3a6bff"},
	{id = "white", name = "White", color = "#f4f6ff"},
]

## SaveData's ranges: [lowest, highest, default].
const KEYS: Dictionary = {paint = [0, 13, 0], livery = [0, 5, 0], glow = [0, 7, 0]}


static func paint_count() -> int:
	return PAINTS.size()


static func livery_count() -> int:
	return LIVERIES.size()


static func glow_count() -> int:
	return GLOWS.size()


static func paint(i: int) -> Dictionary:
	return PAINTS[clampi(i, 0, PAINTS.size() - 1)]


static func livery(i: int) -> Dictionary:
	return LIVERIES[clampi(i, 0, LIVERIES.size() - 1)]


static func glow(i: int) -> Dictionary:
	return GLOWS[clampi(i, 0, GLOWS.size() - 1)]


## The list behind key `key` ("paint", "livery", "glow").
static func list(key: String) -> Array[Dictionary]:
	match key:
		"paint":
			return PAINTS
		"livery":
			return LIVERIES
		"glow":
			return GLOWS
	return []


## Car `car_id`'s body colour with paint `i` (0, or a car with no look: its own colour).
static func paint_color(car_id: String, i: int) -> Color:
	var p: Dictionary = paint(i)
	if p.has("color"):
		return Color(String(p.color))
	var look: Dictionary = Cars.get_car(car_id).get("look", {}) if Cars.has_car(car_id) else {}
	return Color(str(look.get("color", "#d7263d")))


## The livery's trim colour on `paint`: near-black on a light paint, white on a dark one (the
## shader's stripe rule).
static func trim(p: Color) -> Color:
	var lin := p.srgb_to_linear()
	var lum := (maxf(lin.r, maxf(lin.g, lin.b)) + minf(lin.r, minf(lin.g, lin.b))) / 2.0
	return Color.hex(0x1b1d22ff) if lum > 0.62 else Color.hex(0xf4f4f2ff)


## Underglow `i`'s colour (Off: transparent).
static func glow_color(i: int) -> Color:
	var g: Dictionary = glow(i)
	return Color(String(g.color)) if g.has("color") else Color(0, 0, 0, 0)


## The looks in words: "Blue paint, Stripes livery, cyan underglow" (only what isn't factory;
## "factory looks" when nothing is).
static func text(looks: Dictionary) -> String:
	var parts: PackedStringArray = []
	var p := int(looks.get("paint", 0))
	var l := int(looks.get("livery", 0))
	var g := int(looks.get("glow", 0))
	if p > 0:
		parts.append("%s paint" % paint(p).name)
	if l > 0:
		parts.append("%s livery" % livery(l).name)
	if g > 0:
		parts.append("%s underglow" % String(glow(g).name).to_lower())
	return "factory looks" if parts.is_empty() else ", ".join(parts)
