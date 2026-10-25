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


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiStyle.theme()
	_plate = UiStyle.panel(UiStyle.box(UiStyle.PANEL, true, [UiStyle.S5, UiStyle.S2, UiStyle.S5, UiStyle.S2]))
	_label = UiStyle.label("", "text", UiStyle.FS_S, UiStyle.TEXT, 0.0, false, false, false, 18)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_plate.add_child(_label)
	_plate.modulate.a = 0.0
	add_child(_plate)
	resized.connect(_place)


func show_text(text: String) -> void:
	_label.text = text
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
	var max_w := size.x - 32.0
	var font := UiStyle.font("text", UiStyle.FS_S)
	var tw := font.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.FS_S).x + 2 * UiStyle.S5 + 2
	var w := minf(tw, max_w)
	# (the label wraps at the plate's inner width: give it that width before measuring, or its
	# minimum height is that of the text wrapped at its old width)
	_label.size = Vector2(w - 2 * UiStyle.S5, 0)
	_plate.size = Vector2(w, 0)
	_plate.size = Vector2(w, _plate.get_combined_minimum_size().y)
	var b := bottom if size.x >= 1000 else 132.0
	_plate.position = Vector2(roundf((size.x - w) * 0.5), size.y - b - _plate.size.y)
