extends Control
## car_chip.gd
## ------------------------------------------------------------------
## A small car tile for compact car pickers (the training screen's Car choice): the car's side
## view (the menu's car card silhouette, in its colours) over its name. Like the menu's car cards
## the picked one is lighter and underlined with the accent; `badge` is a short note in its top
## right corner (the training screen: the generation of the car's saved AI network). Click (or
## press(), the gamepad's A) emits `picked`; box_rect() is where the gamepad highlight goes.

signal picked

const W := preload("res://ui/widgets.gd")
const HEIGHT := 62.0

var car_id := ""
var info: Dictionary = {}
var profile: Dictionary = {}
var selected := false:
	set(v):
		if v != selected:
			selected = v
			queue_redraw()
## A short note in the top right corner ("" none).
var badge := "":
	set(v):
		if v != badge:
			badge = v
			queue_redraw()
var _hover := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(1, HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_entered.connect(func() -> void: _hover = true; queue_redraw())
	mouse_exited.connect(func() -> void: _hover = false; queue_redraw())


func setup(id: String, car: Dictionary, side_view: Dictionary) -> void:
	car_id = id
	info = car
	profile = side_view
	tooltip_text = "%s (%d km/h): %s" % [car.name, roundi(car.top), car.description]
	queue_redraw()


func box_rect() -> Rect2:
	return Rect2(Vector2.ZERO, size)


## Pick it as a click would (the gamepad's A).
func press() -> void:
	picked.emit()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		press()
		accept_event()


func _draw() -> void:
	if info.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, size), UiStyle.CARD_HI if selected or _hover else UiStyle.CARD)
	if selected:
		draw_rect(Rect2(0, size.y - 3, size.x, 3), UiStyle.ACCENT)
	var name_h := 18.0
	var pad := float(UiStyle.S2)
	var sil_h := size.y - pad - name_h - 4.0 - pad * 0.5
	var sil_w := minf(size.x - 2 * pad, sil_h * 5.6 / 1.72)
	W.silhouette(self, Rect2((size.x - sil_w) * 0.5, pad, sil_w, sil_h), profile, info.color, info.accent)
	var font := UiStyle.face("display")
	var fs := UiStyle.FS_M
	var tw := font.get_string_size(info.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var top := size.y - name_h - pad * 0.5 - 3.0
	W.text(self, font, fs, maxf(pad, (size.x - tw) * 0.5), top, name_h, info.name,
		UiStyle.TEXT if selected or _hover else UiStyle.TEXT_2, false, size.x - 2 * pad)
	if badge != "":
		var bf := UiStyle.font("text_semi", UiStyle.FS_S, 0, true)
		var bw := bf.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.FS_S).x
		W.text(self, bf, UiStyle.FS_S, size.x - bw - 5.0, 2.0, 16.0, badge, UiStyle.ACCENT)
