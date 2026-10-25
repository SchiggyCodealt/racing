extends Control
## rev_bar.gd
## ------------------------------------------------------------------
## Gear and revs under the speed (hud.js buildRevMeter / style.css #hud-rev): the gear (R / N /
## 1-6) on a small plate, then a thin slanted bar filled with the revs: white, the accent near
## the shift point, red at the limiter, with the red zone from the upshift point marked.

const W := preload("res://ui/widgets.gd")

var gear_text := "N"
var fill := 0.0           # 0..1
var fill_color := UiStyle.TEXT
var red_from := 0.95      # where the red zone starts (upshift / redline)
var _state := ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(240, 26)


## Gear (<0 R, 0 N) and rpm for a car's rev limits {idle_rpm, redline, upshift_rpm} (hud.js updateRev).
func set_revs(gear: int, rpm: float, spec: Dictionary) -> void:
	var idle := float(spec.get("idle_rpm", 1000))
	var redline := float(spec.get("redline", 8000))
	var up := float(spec.get("upshift_rpm", 7600))
	var g := "R" if gear < 0 else "N" if gear == 0 else str(gear)
	var r := roundf(rpm / 25.0) * 25.0
	var st := "%s %s %s %s" % [g, r, redline, up]
	if st == _state:
		return
	_state = st
	gear_text = g
	red_from = up / redline
	fill = clampf((r - idle * 0.8) / (redline - idle * 0.8), 0.0, 1.0)
	fill_color = UiStyle.BAD if r >= redline - 150 else UiStyle.ACCENT if r >= up - 600 else UiStyle.TEXT
	queue_redraw()


func _draw() -> void:
	# gear plate (min 30 px wide, 26 px line)
	var gr := Rect2(0, (size.y - 26) * 0.5, 30, 26)
	UiStyle.draw_skewed_rect(self, gr, UiStyle.PLATE)
	var f := UiStyle.font("display_bold", UiStyle.FS_L, 0, true)
	var tw := f.get_string_size(gear_text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.FS_L).x
	draw_string(f, Vector2(roundf(gr.position.x + (30 - tw) * 0.5), W.baseline(f, UiStyle.FS_L, gr.position.y, 26)), gear_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.FS_L, UiStyle.TEXT)
	# the bar
	var x0 := 30.0 + UiStyle.S3
	var bar := Rect2(x0, (size.y - 6) * 0.5, size.x - x0, 6)
	UiStyle.draw_skewed_rect(self, bar, UiStyle.PLATE)
	var rx := bar.size.x * red_from
	UiStyle.draw_skewed_rect(self, Rect2(bar.position.x + rx, bar.position.y, bar.size.x - rx, 6), Color(1.0, 93 / 255.0, 82 / 255.0, 0.3))
	if fill > 0.0:
		UiStyle.draw_skewed_rect(self, Rect2(bar.position, Vector2(bar.size.x * fill, 6)), fill_color)
