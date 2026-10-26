extends Control
## check_toggle.gd
## ------------------------------------------------------------------
## A check box with its label (style.css label.check): an 18 px slanted box, filled with the
## accent and a check when ticked, then 13 px grey text (white on hover). Click toggles it
## and emits `toggled`. `box_rect()` is where the gamepad highlight goes.

signal toggled(on: bool)

const W := preload("res://ui/widgets.gd")

var text := "":
	set(v):
		text = v
		update_minimum_size()
		queue_redraw()
var checked := false:
	set(v):
		checked = v
		queue_redraw()
var disabled := false:
	set(v):
		disabled = v
		queue_redraw()
var font_size := UiStyle.FS_S
## Wrap the label at this width (0: one line), e.g. beside the Drive button in a narrow column.
var wrap_width := 0.0:
	set(v):
		wrap_width = v
		update_minimum_size()
		queue_redraw()
var _hover := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_NONE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_entered.connect(func() -> void: _hover = true; queue_redraw())
	mouse_exited.connect(func() -> void: _hover = false; queue_redraw())


func _get_minimum_size() -> Vector2:
	if text == "":
		return Vector2(18, 18)
	var w := 0.0
	var lines := _lines()
	for l in lines:
		w = maxf(w, UiStyle.text_width(l, "text", font_size))
	return Vector2(18 + UiStyle.S2 + w, maxf(18, roundf(font_size * 1.4) * lines.size()))


func _lines() -> PackedStringArray:
	if wrap_width <= 0.0:
		return PackedStringArray([text])
	return UiStyle.wrap_text(text, UiStyle.font("text", font_size), font_size, wrap_width).split("\n")


func box_rect() -> Rect2:
	return Rect2(0, (size.y - 18) * 0.5, 18, 18)


## Toggle as a click would (the gamepad's A).
func press() -> void:
	if disabled:
		return
	checked = not checked
	toggled.emit(checked)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		press()
		accept_event()


func _draw() -> void:
	var b := box_rect()
	var a := 0.4 if disabled else 1.0
	if checked:
		UiStyle.draw_skewed_rect(self, b, Color(UiStyle.ACCENT, a))
		var p := func(x: float, y: float) -> Vector2: return b.position + Vector2(3, 3) + Vector2(x, y)
		draw_polyline(PackedVector2Array([p.call(2, 6.3), p.call(4.8, 9), p.call(10, 3.2)]), Color(UiStyle.ACCENT_INK, a), 2.0, true)
	else:
		UiStyle.draw_skewed_rect(self, b, Color(UiStyle.TEXT_3, a))
		UiStyle.draw_skewed_rect(self, b.grow(-2), Color(UiStyle.BG_3, a))
	if text != "":
		var col := UiStyle.TEXT if _hover and not disabled else UiStyle.TEXT_2
		var lh := roundf(font_size * 1.4)
		var lines := _lines()
		var top := (size.y - lh * lines.size()) * 0.5
		for k in lines.size():
			W.text(self, UiStyle.face("text"), font_size, 18 + UiStyle.S2, top + k * lh, lh, lines[k], Color(col, a))
