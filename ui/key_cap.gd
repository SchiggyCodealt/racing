extends Control
## key_cap.gd
## ------------------------------------------------------------------
## A key cap (style.css kbd): a small grey cap with a darker bottom edge and the key's name
## in Barlow Condensed, or an arrow icon (the fonts have no arrow glyphs). `in_button`: the
## flatter cap inside a button (Controls H). Use KeyCap.make("Esc") / KeyCap.arrow("left").

const W := preload("res://ui/widgets.gd")
const ARROWS := {"up": 0.0, "down": PI, "left": -PI / 2, "right": PI / 2}

var text := "":
	set(v):
		text = v
		update_minimum_size()
		queue_redraw()
var arrow_dir := ""          # "", "up", "down", "left", "right"
var in_button := false
var cap_h := 22.0
var font_size := UiStyle.FS_S


static func make(t: String, h: float = 22.0, fs: int = UiStyle.FS_S) -> Control:
	var k: Control = load("res://ui/key_cap.gd").new()
	k.cap_h = h
	k.font_size = fs
	k.text = t
	return k


static func arrow(dir: String) -> Control:
	var k: Control = load("res://ui/key_cap.gd").new()
	k.arrow_dir = dir
	return k


## The flat cap inside a button (style.css .btn kbd: 18 px, translucent, grey text).
static func in_btn(t: String) -> Control:
	var k: Control = load("res://ui/key_cap.gd").new()
	k.in_button = true
	k.cap_h = 18.0
	k.text = t
	return k


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _font() -> Font:
	return UiStyle.font("display", font_size, 0.02)


func _get_minimum_size() -> Vector2:
	var pad := 5.0 if in_button else 6.0
	if arrow_dir != "":
		return Vector2(cap_h, cap_h)
	var w := _font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 2 * pad
	return Vector2(maxf(cap_h, ceilf(w)), cap_h)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if in_button:
		draw_rect(r, Color(1, 1, 1, 0.08))
	else:
		draw_rect(r, UiStyle.BG_4)
		draw_rect(Rect2(0, size.y - 2, size.x, 2), Color("#1b1d20")) # (inset 0 -2px 0 rgba(0,0,0,.45) on --bg-4)
	var ink := UiStyle.TEXT_2 if in_button else UiStyle.TEXT
	if arrow_dir != "":
		W.arrow(self, size * 0.5 - Vector2(0, 1), ARROWS[arrow_dir], ink, 12.0)
		return
	var f := _font()
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var y := W.baseline(f, font_size, (size.y - font_size) * 0.5 - (1.0 if not in_button else 0.0), font_size)
	draw_string(f, Vector2(roundf((size.x - w) * 0.5), y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)
