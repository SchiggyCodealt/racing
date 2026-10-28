extends Control
## train_fitness_chart.gd (port of web/src/ui/fitnessChart.js)
## ------------------------------------------------------------------
## Line chart of the best and average fitness per generation on the training dashboard:
## the menu's type and colours (best in the accent, average in grey), four grid lines with
## their values, the first and last generation under the plot, a small legend on top.
##   chart.draw_history(trainer.history)   # [{gen, best, avg}], redrawn on the next frame
## Before the first generation it says "Fitness per generation appears here".

const C_LABEL := Color("#6f7278")
const C_GRID := Color(1, 1, 1, 0.07)
const C_BEST := Color("#ffc83d")
const C_AVG := Color("#a7a9ae")
const FONT_SIZE := 12
const PAD_L := 40.0
const PAD_R := 10.0
const PAD_T := 18.0
const PAD_B := 20.0

var history: Array = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, 150)
	resized.connect(queue_redraw)


## Draw `h` ([{gen, best, avg}], oldest first) on the next frame.
func draw_history(h: Array) -> void:
	history = h
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), UiStyle.BG_0)
	var f := UiStyle.face("text")
	var pw := w - PAD_L - PAD_R
	var ph := h - PAD_T - PAD_B
	if history.is_empty():
		_text(f, Vector2(w / 2.0, h / 2.0), "Fitness per generation appears here", C_LABEL, HORIZONTAL_ALIGNMENT_CENTER, "middle")
		return
	var top := -INF
	for e: Dictionary in history:
		top = maxf(top, float(e.best))
	var max_y := nice_max(top)
	var g0 := float(history[0].gen)
	var g1 := maxf(float(history[history.size() - 1].gen), g0 + 1.0)
	var px := func(g: float) -> float: return PAD_L + (g - g0) / (g1 - g0) * pw
	var py := func(v: float) -> float: return PAD_T + ph - maxf(0.0, v) / max_y * ph

	# grid + y labels
	for k in 5:
		var v := max_y * k / 4.0
		var y: float = py.call(v)
		draw_line(Vector2(PAD_L, y), Vector2(w - PAD_R, y), C_GRID, 1.0)
		_text(f, Vector2(PAD_L - 4.0, y), str(roundi(v)), C_LABEL, HORIZONTAL_ALIGNMENT_RIGHT, "middle")
	_text(f, Vector2(PAD_L + 14.0, h - PAD_B + 5.0), "gen %d" % int(g0), C_LABEL, HORIZONTAL_ALIGNMENT_CENTER, "top")
	_text(f, Vector2(w - PAD_R - 18.0, h - PAD_B + 5.0), "gen %d" % int(g1), C_LABEL, HORIZONTAL_ALIGNMENT_CENTER, "top")

	for series: Array in [["avg", C_AVG, 1.5], ["best", C_BEST, 2.0]]:
		var pts := PackedVector2Array()
		for e: Dictionary in history:
			pts.append(Vector2(px.call(float(e.gen)), py.call(float(e[series[0]]))))
		if pts.size() == 1:
			pts.append(pts[0] + Vector2(0.01, 0)) # (a single point: a dot, as the canvas draws nothing)
		draw_polyline(pts, series[1], series[2], true)

	# legend
	draw_rect(Rect2(PAD_L, 6, 10, 3), C_BEST)
	_text(f, Vector2(PAD_L + 14.0, 8.0), "best", C_BEST, HORIZONTAL_ALIGNMENT_LEFT, "middle")
	draw_rect(Rect2(PAD_L + 50.0, 6, 10, 3), C_AVG)
	_text(f, Vector2(PAD_L + 64.0, 8.0), "average", C_AVG, HORIZONTAL_ALIGNMENT_LEFT, "middle")


## Canvas-style text: `at` is the anchor point, `align` left / center / right of it and
## `baseline` "middle" (centred on at.y) or "top" (hanging from at.y).
func _text(f: Font, at: Vector2, s: String, color: Color, align: HorizontalAlignment, baseline: String) -> void:
	var tw := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var x := at.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= tw / 2.0
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= tw
	var asc := f.get_ascent(FONT_SIZE)
	var desc := f.get_descent(FONT_SIZE)
	var y := at.y + asc if baseline == "top" else at.y + (asc - desc) / 2.0
	draw_string(f, Vector2(x, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)


## The top of the y axis: 1, 2, 2.5, 5 or 10 times a power of ten, at least `v`.
static func nice_max(v: float) -> float:
	if v <= 0.0:
		return 1.0
	var p := pow(10.0, floorf(log(v) / log(10.0)))
	if p * 10.0 <= v: # (log(1000) / log(10) is a hair under 3)
		p *= 10.0
	for m: float in [1.0, 2.0, 2.5, 5.0, 10.0]:
		if m * p >= v:
			return m * p
	return 10.0 * p
