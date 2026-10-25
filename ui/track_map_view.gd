extends Control
## track_map_view.gd
## ------------------------------------------------------------------
## A track's centre line seen from above (the menu's minimaps; menu.js trackMap): about 160
## points of the road, turned a quarter when the track is taller than wide so it fills a wide
## tile, with a dot on the start line (and, for a sprint, one on the finish line). x / z go
## to screen x / y and the quarter turn is a rotation, never a mirror, so corners turn the
## way they do from the car. The line keeps its width in pixels whatever the track's size,
## and the map is fitted into the control's rect, centred (SVG "meet").

## {points: PackedVector2Array, size: Vector2, start: Vector2, finish: Vector2 or null, closed: bool}
var map: Dictionary = {}:
	set(v):
		map = v
		queue_redraw()
var line_color: Color = UiStyle.TEXT_2:
	set(v):
		line_color = v
		queue_redraw()
var line_width: float = 2.0
var dot_color: Color = UiStyle.TEXT
var dot_size: float = 6.0
## Space above the map inside the rect, and the rect height at or under which nothing is drawn
## (the track panel's map: s5 under the description, only when it has more than 64 px).
var top_gap: float = 0.0
var hide_below: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


## The map of a centre line given as sample arrays (`n` samples used; circuits close the loop).
## `start` / `finish`: sample indices of the start and finish lines (finish -1 on circuits).
static func make_map(px: Variant, pz: Variant, n: int, closed: bool, start: int, finish: int) -> Dictionary:
	var step := maxi(1, int(roundf(n / 160.0)))
	var x0 := INF
	var x1 := -INF
	var z0 := INF
	var z1 := -INF
	for i in n:
		x0 = minf(x0, px[i])
		x1 = maxf(x1, px[i])
		z0 = minf(z0, pz[i])
		z1 = maxf(z1, pz[i])
	var turn := z1 - z0 > x1 - x0
	var w := z1 - z0 if turn else x1 - x0
	var h := x1 - x0 if turn else z1 - z0
	var pad := maxf(w, h) * 0.04
	var at := func(i: int) -> Vector2:
		var uv := Vector2(z1 - pz[i], px[i] - x0) if turn else Vector2(px[i] - x0, pz[i] - z0)
		return uv + Vector2(pad, pad)
	var pts := PackedVector2Array()
	var i := 0
	while i < n:
		pts.append(at.call(i))
		i += step
	if not closed and (n - 1) % step != 0:
		pts.append(at.call(n - 1))
	return {
		"points": pts, "size": Vector2(w + 2 * pad, h + 2 * pad), "closed": closed,
		"start": at.call(start), "finish": at.call(finish) if not closed and finish >= 0 else null,
	}


func _draw() -> void:
	if map.is_empty() or size.x < 4 or size.y <= maxf(4.0, hide_below):
		return
	var area := Vector2(size.x, size.y - top_gap)
	var vb: Vector2 = map.size
	var k := minf(area.x / vb.x, area.y / vb.y)
	var off := Vector2(0, top_gap) + (area - vb * k) * 0.5
	var src: PackedVector2Array = map.points
	var pts := PackedVector2Array()
	pts.resize(src.size() + (1 if map.closed else 0))
	for i in src.size():
		pts[i] = off + src[i] * k
	if map.closed:
		pts[src.size()] = pts[0]
	draw_polyline(pts, line_color, line_width, true)
	draw_circle(off + map.start * k, dot_size * 0.5, dot_color, true, -1.0, true)
	if map.finish != null:
		draw_circle(off + map.finish * k, dot_size * 0.5, dot_color, true, -1.0, true)
