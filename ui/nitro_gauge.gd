extends Control
## nitro_gauge.gd
## ------------------------------------------------------------------
## The nitro tank above the speed (hud.js buildNitroGauge / style.css #hud-nitro): a NITRO
## label and a slanted ten-segment tank. White normally, red under a quarter, the nitro blue
## and a glow while it burns; EMPTY in red with a red rim when it is out.

const W := preload("res://ui/widgets.gd")

var level := 1.0          # 0..1
var boosting := false
var label_w := 46.0
var _state := ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(240, 16)


## Show tank `lvl` (0..1); `boost` while the nitro burns. Redraws only when it changes (half-percent steps).
func set_level(lvl: float, boost: bool) -> void:
	var pct := roundf(clampf(lvl, 0.0, 1.0) * 200.0) / 2.0
	var st := "%s %s" % [pct, state_for(pct, boost)]
	if st == _state:
		return
	_state = st
	level = pct / 100.0
	boosting = boost
	queue_redraw()


## "empty", "boost", "low" or "" (hud.js updateNitro's classes).
static func state_for(pct: float, boost: bool) -> String:
	if pct <= 0.0:
		return "empty"
	if boost:
		return "boost"
	if pct < 25.0:
		return "low"
	return ""


func _draw() -> void:
	var cls := state_for(level * 100.0, boosting)
	var f := UiStyle.font("display_bold", UiStyle.FS_S, 0.1)
	var text := "EMPTY" if cls == "empty" else "NITRO"
	var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.FS_S).x
	var base := W.baseline(f, UiStyle.FS_S, (size.y - UiStyle.FS_S) * 0.5, UiStyle.FS_S)
	var lx := label_w - tw
	var col := UiStyle.BAD if cls == "empty" else UiStyle.BOOST if cls == "boost" else UiStyle.TEXT_2
	if cls == "boost": # (text-shadow 0 0 10px: a soft halo)
		draw_string_outline(f, Vector2(lx, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.FS_S, 8, Color(UiStyle.BOOST, 0.16))
		draw_string_outline(f, Vector2(lx, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.FS_S, 4, Color(UiStyle.BOOST, 0.22))
	else:
		draw_string(f, Vector2(lx, base + 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.FS_S, Color(0, 0, 0, 0.6))
	draw_string(f, Vector2(lx, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.FS_S, col)
	# the tank
	var x0 := label_w + UiStyle.S3
	var tank := Rect2(x0, (size.y - 10.0) * 0.5, size.x - x0, 10.0)
	if cls == "boost": # glow: 0 0 10px .85, 0 0 24px .45
		for k in range(12, 0, -2):
			UiStyle.draw_skewed_rect(self, tank.grow(k), Color(UiStyle.BOOST, 0.055 if k > 6 else 0.09))
	UiStyle.draw_skewed_rect(self, tank, UiStyle.PLATE)
	var fill_col := UiStyle.BOOST if cls == "boost" else UiStyle.BAD if cls == "low" else UiStyle.TEXT
	if level > 0.0:
		_part(tank, 0.0, tank.size.x * level, fill_col)
	# segment gaps: the last 3 px of every tenth
	for k in range(1, 11):
		var e := tank.size.x * k / 10.0
		_part(tank, e - 3.0, e, Color(10 / 255.0, 11 / 255.0, 13 / 255.0, 0.9))
	if cls == "empty": # inset 1.5 px red rim
		var d := tank.size.y * UiStyle.SKEW * 0.5
		var p := PackedVector2Array([Vector2(tank.position.x + d, tank.position.y), Vector2(tank.end.x + d, tank.position.y),
			Vector2(tank.end.x - d, tank.end.y), Vector2(tank.position.x - d, tank.end.y), Vector2(tank.position.x + d, tank.position.y)])
		draw_polyline(p, UiStyle.BAD, 1.5, true)


## Fill the part [a, b] (px from the tank's left, measured along its middle) of the slanted tank.
func _part(tank: Rect2, a: float, b: float, c: Color) -> void:
	a = clampf(a, 0.0, tank.size.x)
	b = clampf(b, 0.0, tank.size.x)
	if b <= a:
		return
	UiStyle.draw_skewed_rect(self, Rect2(tank.position.x + a, tank.position.y, b - a, tank.size.y), c)
