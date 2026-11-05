extends Control
## volume_bar.gd (v6.12.0)
## ------------------------------------------------------------------
## A volume on the Settings screen: ten slanted blocks (the lit ones in the accent, like the
## picked segment of a choice) and the value in per cent. A click or a drag sets it to the
## nearest tenth; the Settings screen steps it with the keys and the pad (left / right).
## `changed(value)` is emitted on every change (value 0..1 in steps of STEP).

signal changed(value: float)

const STEPS := 10
const STEP := 0.1
const BLOCK_W := 17.0
const BLOCK_GAP := 3.0
const TEXT_W := 44.0

var value := 0.8:
	set(v):
		value = snappedf(clampf(v, 0.0, 1.0), STEP)
		queue_redraw()
var _drag := false


func _init() -> void:
	custom_minimum_size = Vector2(STEPS * (BLOCK_W + BLOCK_GAP) + TEXT_W, 30)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


## Set the value as the player would (snapped, clamped); emits changed when it moved.
func set_value(v: float) -> void:
	var old := value
	value = v
	if not is_equal_approx(old, value):
		changed.emit(value)


## The value per cent as shown ("80%").
func text() -> String:
	return "%d%%" % roundi(value * 100.0)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_drag = (e as InputEventMouseButton).pressed
		if _drag:
			set_value(_value_at((e as InputEventMouseButton).position.x))
		accept_event()
	elif e is InputEventMouseMotion and _drag:
		set_value(_value_at((e as InputEventMouseMotion).position.x))
		accept_event()


## The value a click at x (local) means: the block under it (left of the first: 0).
func _value_at(x: float) -> float:
	var w := STEPS * (BLOCK_W + BLOCK_GAP)
	return clampf(ceilf(x / w * STEPS - 0.15) / STEPS, 0.0, 1.0)


func _draw() -> void:
	var h := 14.0
	var y := roundf((size.y - h) * 0.5)
	var lit := roundi(value * STEPS)
	for k in STEPS:
		var r := Rect2(k * (BLOCK_W + BLOCK_GAP) + 4.0, y, BLOCK_W, h)
		var col := UiStyle.ACCENT if k < lit else UiStyle.BG_4
		var s := UiStyle.SKEW * h * 0.5
		draw_colored_polygon(PackedVector2Array([
			Vector2(r.position.x + s, r.position.y), Vector2(r.end.x + s, r.position.y),
			Vector2(r.end.x - s, r.end.y), Vector2(r.position.x - s, r.end.y)]), col)
	var f := UiStyle.font("text_semi", UiStyle.FS_S, 0, true)
	var t := text() if value > 0.0 else "Off"
	var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.FS_S).x
	var base := roundf((size.y - (f.get_ascent(UiStyle.FS_S) + f.get_descent(UiStyle.FS_S))) * 0.5 + f.get_ascent(UiStyle.FS_S))
	draw_string(f, Vector2(size.x - tw, base), t, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.FS_S, UiStyle.TEXT if value > 0.0 else UiStyle.TEXT_3)
