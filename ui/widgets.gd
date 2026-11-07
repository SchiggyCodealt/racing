extends RefCounted
## widgets.gd
## ------------------------------------------------------------------
## Small drawing helpers shared by the custom-drawn widgets (track tiles, car cards, key
## caps, the HUD): CSS-like text placement, the arrow icon and the padlock. Preload it:
##   const W := preload("res://ui/widgets.gd")


## The baseline of a line of `size` px text in a CSS line box `line_h` px tall starting at
## `top` (the half-leading model browsers use), for draw_string.
static func baseline(font: Font, size: int, top: float, line_h: float) -> float:
	var asc := font.get_ascent(size)
	var desc := font.get_descent(size)
	return top + (line_h - (asc + desc)) * 0.5 + asc


## Draw `text` with its CSS line box at `top` (left aligned at x, or right aligned when `right`).
static func text(ci: CanvasItem, font: Font, size: int, x: float, top: float, line_h: float, s: String,
		color: Color, right: bool = false, max_w: float = -1.0) -> void:
	var y := baseline(font, size, top, line_h)
	if right:
		var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		ci.draw_string(font, Vector2(x - w, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
	elif max_w >= 0.0:
		ellipsis(ci, font, size, Vector2(x, y), s, max_w, color)
	else:
		ci.draw_string(font, Vector2(x, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## Draw `s` on baseline `pos`, cut with an ellipsis to `max_w` px (CSS text-overflow: ellipsis).
static func ellipsis(ci: CanvasItem, font: Font, size: int, pos: Vector2, s: String, max_w: float, color: Color) -> void:
	var line := TextLine.new()
	line.add_string(s, font, size)
	line.width = maxf(0.0, max_w)
	line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.draw(ci.get_canvas_item(), Vector2(pos.x, pos.y - line.get_line_ascent()), color)


## The arrow icon of the key caps (index.html #i-arrow, a 12 x 12 up arrow) centred on `c`,
## rotated by `angle` (0 up, PI down, -PI/2 left, PI/2 right), `s` px big.
static func arrow(ci: CanvasItem, c: Vector2, angle: float, color: Color, s: float = 12.0) -> void:
	var k := s / 12.0
	var tf := Transform2D(angle, c)
	var p := func(x: float, y: float) -> Vector2: return tf * (Vector2(x - 6.0, y - 6.0) * k)
	var w := 1.8 * k
	ci.draw_line(p.call(6, 10.5), p.call(6, 2.6), color, w, true)
	ci.draw_polyline(PackedVector2Array([p.call(2.4, 5.8), p.call(6, 2.2), p.call(9.6, 5.8)]), color, w, true)


## A small padlock (the locked cars and tracks), 9 x 11 px at k = 1, its top left at `at`.
static func padlock(ci: CanvasItem, at: Vector2, col: Color, k: float = 1.0) -> void:
	ci.draw_arc(at + Vector2(4.5, 4.0) * k, 3.0 * k, PI, TAU, 8, col, 1.5 * k, true)
	ci.draw_line(at + Vector2(1.5, 4.0) * k, at + Vector2(1.5, 5.5) * k, col, 1.5 * k)
	ci.draw_line(at + Vector2(7.5, 4.0) * k, at + Vector2(7.5, 5.5) * k, col, 1.5 * k)
	ci.draw_rect(Rect2(at + Vector2(0, 5.0) * k, Vector2(9, 6.5) * k), col)


## (v6.14) A cup trophy, `h` px tall (and about 0.9 h wide), centred on `cx` with its top at `top`:
## a two-handled bowl on a stem and a base, filled with `col` (an empty place: a faint colour).
static func trophy(ci: CanvasItem, cx: float, top: float, h: float, col: Color) -> void:
	var rx := 0.3 * h
	var bowl := PackedVector2Array([Vector2(cx - rx, top)])
	for k in 9:
		var a := PI * float(k) / 8.0
		bowl.append(Vector2(cx - rx * cos(a), top + 0.48 * h * sin(a)))
	ci.draw_colored_polygon(bowl, col)
	for side in [-1.0, 1.0]:
		ci.draw_arc(Vector2(cx + side * rx, top + 0.17 * h), 0.13 * h, -PI * 0.5 if side > 0.0 else PI * 0.5, PI * 0.5 if side > 0.0 else PI * 1.5,
			8, col, maxf(1.0, 0.075 * h), true)
	ci.draw_rect(Rect2(cx - 0.05 * h, top + 0.46 * h, 0.1 * h, 0.26 * h), col)
	ci.draw_rect(Rect2(cx - 0.2 * h, top + 0.72 * h, 0.4 * h, 0.1 * h), col)
	ci.draw_rect(Rect2(cx - 0.27 * h, top + 0.84 * h, 0.54 * h, 0.16 * h), col)


## The menu's side view of a car (menu.js silhouette): the profile's parts and wheels, the same
## scale for every car (5.6 m x 1.72 m shown) so their sizes compare, fitted to `r`. A part
## with a `color` (the driver's helmet, a roll cage) is drawn in it; `rim` colours the wheels.
static func silhouette(ci: CanvasItem, r: Rect2, profile: Dictionary, paint: Color, accent: Color) -> void:
	const Z0 := -2.75
	const Z1 := 2.85
	const TOP := 1.72
	var k := minf(r.size.x / (Z1 - Z0), r.size.y / TOP)
	var o := r.position + (r.size - Vector2(Z1 - Z0, TOP) * k) * 0.5
	var fills := {"paint": paint, "accent": accent, "glass": Color("#2a3b52"), "carbon": Color("#121418"), "head": Color("#fff3d6")}
	for part in profile.get("parts", []):
		var src: PackedVector2Array = part.pts
		var pts := PackedVector2Array()
		for q in src:
			pts.append(o + Vector2(q.x - Z0, TOP - q.y) * k)
		var col: Color = part.color if part.has("color") else fills.get(part.mat, fills.carbon)
		if Geometry2D.triangulate_polygon(pts).size() > 0:
			ci.draw_colored_polygon(pts, col)
		else: # (a self-touching outline: fill its convex pieces)
			for piece in Geometry2D.decompose_polygon_in_convex(pts):
				ci.draw_colored_polygon(piece, col)
		var ring := pts.duplicate()
		ring.append(pts[0])
		ci.draw_polyline(ring, col, 0.8, true) # (soft edges: polygons are not anti-aliased)
	var rim: Color = profile.get("rim", Color("#a7adb8"))
	if rim.get_luminance() < 0.25: # (dark rims: a little lighter, or they vanish into the tyre at card size)
		rim = rim.lerp(Color("#a7adb8"), 0.3)
	for wh in profile.get("wheels", []):
		var c := o + Vector2(float(wh[0]) - Z0, TOP - float(wh[1])) * k
		ci.draw_circle(c, float(wh[1]) * k, Color("#0c0d10"), true, -1.0, true)
		ci.draw_circle(c, float(wh[1]) * 0.62 * k, rim, true, -1.0, true)
		ci.draw_circle(c, float(wh[1]) * 0.2 * k, Color("#0c0d10").lerp(rim, 0.4), true, -1.0, true)
