class_name PadNotice
extends Control
## pad_notice.gd
## ------------------------------------------------------------------
## A short notice at the bottom centre of the screen (input.js notify / style.css #pad-note):
## "Gamepad connected: … · RT accelerate · …", "Gamepad disconnected". It fades in, stays
## 4.5 s and fades out, above everything, and never takes the mouse.
## show_text(text) shows it; `bottom` is its distance from the bottom edge (72 px; 132 px in
## narrow windows, above the nitro gauge and the menu's Drive bar).

const NOTE_TIME := 4.5
const FADE := 0.3

var bottom := 72.0
var _plate: PanelContainer
var _label: Label
var _t := 0.0
var _text := ""


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiStyle.theme()
	_plate = UiStyle.panel(UiStyle.box(UiStyle.PANEL, true, [UiStyle.S5, UiStyle.S2, UiStyle.S5, UiStyle.S2]))
	_label = UiStyle.label("", "text", UiStyle.FS_S, UiStyle.TEXT, 0.0, false, false, false, 18)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_plate.add_child(_label)
	_plate.modulate.a = 0.0
	add_child(_plate)
	resized.connect(_place)


func show_text(text: String) -> void:
	_text = text
	_t = NOTE_TIME
	_place()


func _process(dt: float) -> void:
	if _t > 0.0:
		_t = maxf(0.0, _t - dt)
		_plate.modulate.a = minf(1.0, _plate.modulate.a + dt / FADE)
	elif _plate.modulate.a > 0.0:
		_plate.modulate.a = maxf(0.0, _plate.modulate.a - dt / FADE)


## True while the notice shows (or fades).
var showing: bool:
	get:
		return _t > 0.0 or _plate.modulate.a > 0.0


func _place() -> void:
	if size.x <= 0:
		return
	var max_w := size.x - 32.0
	var inner := max_w - 2 * UiStyle.S5 - 2
	var font := _label.get_theme_font("font")
	_label.text = UiStyle.wrap_text(_text, font, UiStyle.FS_S, inner)
	_plate.reset_size()
	var w := minf(_plate.get_combined_minimum_size().x, max_w)
	_plate.size = Vector2(w, _plate.get_combined_minimum_size().y)
	var b := bottom if size.x >= 1000 else 132.0
	_plate.position = Vector2(roundf((size.x - w) * 0.5), size.y - b - _plate.size.y)
