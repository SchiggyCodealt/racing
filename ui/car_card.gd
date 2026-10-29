extends Control
## car_card.gd
## ------------------------------------------------------------------
## One car of the menu's car picker (style.css .car-card): the side view, the name, top speed
## and mass, and five stat bars (speed, acceleration, grip, drift, nitro). The picked car's
## card is lighter, underlined with the accent and its bars are in the accent. Drawn by hand.
## Click picks the car, a double click drives. A car you don't own (v6.5.0: set_lock) shows a
## padlock and its price where the top speed was (in the accent when you can afford it), its
## side view dimmed; its stats stay readable.

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
## Not owned (v6.5.0): the price shows instead of the top speed.
var locked := false
var price := 0
var affordable := false


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


## Show the car as not owned (`on`), costing `p`; `can`: the money is there to buy it.
func set_lock(on: bool, p: int, can: bool) -> void:
	if on == locked and p == price and can == affordable:
		return
	locked = on
	price = p
	affordable = can
	if not info.is_empty():
		tooltip_text = "%s (%d km/h, %.2f t): %s%s (C changes the car)" % [info.name, roundi(info.top), info.mass / 1000.0, info.description,
			(" Locked: it costs %s." % UiFormat.money(p)) if on else ""]
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
	var sil_rect := Rect2(px, (size.y - sh) * 0.5, sw, sh)
	if stacked:
		head_top = py + maxf(0.0, (sh - head_h) * 0.5)
		bars_top = py + maxf(head_h, sh) + UiStyle.S2
		bars_x = px
		bars_w = size.x - 2 * px
		sil_rect = Rect2(px, py, sw, sh)
	if locked:
		W.silhouette(self, sil_rect, profile, (info.color as Color).darkened(0.45), (info.accent as Color).darkened(0.45))
	else:
		W.silhouette(self, sil_rect, profile, info.color, info.accent)
	# head: name, then top speed and mass on the same baseline
	var name_font := UiStyle.face("display")
	var base := W.baseline(name_font, UiStyle.FS_L, head_top, UiStyle.FS_L)
	draw_string(name_font, Vector2(right_x, base), info.name, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.FS_L, UiStyle.TEXT_2 if locked else UiStyle.TEXT)
	var name_w := name_font.get_string_size(info.name, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.FS_L).x
	var spec_x := right_x + name_w + UiStyle.S3
	if locked:
		# a padlock and the price (in the accent when you can buy it)
		var col := UiStyle.ACCENT if affordable else UiStyle.TEXT_2
		_padlock(Vector2(spec_x, base - 10.0), col)
		var pf := UiStyle.font("text_semi", UiStyle.FS_S, 0, true)
		W.ellipsis(self, pf, UiStyle.FS_S, Vector2(spec_x + 13.0, base), UiFormat.money(price), size.x - px - spec_x - 13.0, col)
	else:
		# top speed and mass; in narrow cards the top speed alone (the mass is in the tooltip)
		var spec := ("%d km/h" % roundi(info.top)) if short_spec else ("%d km/h · %.2f t" % [roundi(info.top), info.mass / 1000.0])
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


## A small padlock, 9 x 11 px, its top left at `at`.
func _padlock(at: Vector2, col: Color) -> void:
	draw_arc(at + Vector2(4.5, 4.0), 3.0, PI, TAU, 8, col, 1.5, true)
	draw_line(at + Vector2(1.5, 4.0), at + Vector2(1.5, 5.5), col, 1.5)
	draw_line(at + Vector2(7.5, 4.0), at + Vector2(7.5, 5.5), col, 1.5)
	draw_rect(Rect2(at + Vector2(0, 5.0), Vector2(9, 6.5)), col)
