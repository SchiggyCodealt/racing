extends Control
## car_card.gd
## ------------------------------------------------------------------
## One car of the menu's car picker (style.css .car-card): the side view, the name, top speed
## and mass, and five stat bars (speed, acceleration, grip, drift, nitro). The picked car's
## card is lighter, underlined with the accent and its bars are in the accent. Drawn by hand.
## Click picks the car, a double click drives.

signal picked
signal activated

const W := preload("res://ui/widgets.gd")
const STATS := [["speed", "Speed"], ["acceleration", "Accel"], ["grip", "Grip"], ["drift", "Drift"], ["nitro", "Nitro"]]

var car_id := ""
var info: Dictionary = {}
var profile: Dictionary = {}
var selected := false:
	set(v):
		if v != selected:
			selected = v
			queue_redraw()
## Narrow cards (two a row in a narrow picker): the bars go under the side view and name.
var stacked := false:
	set(v):
		if v != stacked:
			stacked = v
			update_minimum_size()
			queue_redraw()
## Narrow cards (three a row): the head shows the top speed without the mass.
var short_spec := false:
	set(v):
		if v != short_spec:
			short_spec = v
			queue_redraw()
var _hover := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_NONE
	mouse_entered.connect(func() -> void: _hover = true; queue_redraw())
	mouse_exited.connect(func() -> void: _hover = false; queue_redraw())


func setup(id: String, car: Dictionary, side_view: Dictionary) -> void:
	car_id = id
	info = car
	profile = side_view
	tooltip_text = "%s (%d km/h, %.2f t): %s (C changes the car)" % [car.name, roundi(car.top), car.mass / 1000.0, car.description]
	queue_redraw()


func _sil_w() -> float:
	return 72.0 if stacked else 96.0


func _get_minimum_size() -> Vector2:
	# padding 12 / 16, the head row (20 px name) and the bars row (13 px label, 6 px, 4 px bar) 8 px apart
	var rows := 21.0 + UiStyle.S2 + 23.0
	if stacked:
		rows = maxf(21.0, _sil_w() * 1.62 / 5.6) + UiStyle.S2 + 23.0
	return Vector2(0, UiStyle.S3 * 2 + rows)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		picked.emit()
		if e.double_click:
			activated.emit()
		accept_event()


func _draw() -> void:
	if info.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, size), UiStyle.CARD_HI if selected or _hover else UiStyle.CARD)
	if selected:
		draw_rect(Rect2(0, size.y - 3, size.x, 3), UiStyle.ACCENT)
	var px := float(UiStyle.S4)
	var py := float(UiStyle.S3)
	var sw := _sil_w()
	var sh := sw * 1.62 / 5.6
	var head_h := 21.0
	var right_x := px + sw + (UiStyle.S3 if stacked else UiStyle.S4)
	var content_w := size.x - right_x - px
	var head_top := py
	var bars_top := py + head_h + UiStyle.S2
	var bars_x := right_x
	var bars_w := content_w
	if stacked:
		head_top = py + maxf(0.0, (sh - head_h) * 0.5)
		bars_top = py + maxf(head_h, sh) + UiStyle.S2
		bars_x = px
		bars_w = size.x - 2 * px
		W.silhouette(self, Rect2(px, py, sw, sh), profile, info.color, info.accent)
	else:
		W.silhouette(self, Rect2(px, (size.y - sh) * 0.5, sw, sh), profile, info.color, info.accent)
	# head: name, then top speed and mass on the same baseline
	var name_font := UiStyle.face("display")
	var base := W.baseline(name_font, UiStyle.FS_L, head_top, UiStyle.FS_L)
	draw_string(name_font, Vector2(right_x, base), info.name, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.FS_L, UiStyle.TEXT)
	var name_w := name_font.get_string_size(info.name, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.FS_L).x
	# top speed and mass; in narrow cards the top speed alone (the mass is in the tooltip)
	var spec := ("%d km/h" % roundi(info.top)) if short_spec else ("%d km/h · %.2f t" % [roundi(info.top), info.mass / 1000.0])
	var spec_x := right_x + name_w + UiStyle.S3
	W.ellipsis(self, UiStyle.font("text", UiStyle.FS_S, 0, true), UiStyle.FS_S, Vector2(spec_x, base), spec,
		size.x - px - spec_x, UiStyle.TEXT_3)
	# five stat bars
	var g := float(UiStyle.S2)
	var cw := (bars_w - 4 * g) / 5.0
	var lab_font := UiStyle.face("text")
	for k in STATS.size():
		var x := bars_x + k * (cw + g)
		W.text(self, lab_font, UiStyle.FS_S, x, bars_top, UiStyle.FS_S, STATS[k][1],
			UiStyle.TEXT_2 if selected else UiStyle.TEXT_3, false, cw)
		var bar := Rect2(x, bars_top + UiStyle.FS_S + 6, cw, 4)
		draw_rect(bar, UiStyle.BG_4)
		var f := clampf(float(info.bars.get(STATS[k][0], 0.0)), 0.0, 1.0)
		draw_rect(Rect2(bar.position, Vector2(roundf(cw * f), 4)), UiStyle.ACCENT if selected else UiStyle.TEXT_2)
