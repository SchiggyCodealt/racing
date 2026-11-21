class_name CarScreen
extends "res://ui/dialog_screen.gd"
## car_screen.gd (v6.19.0): the car page, over the menu. It opens after you chose what to race (time
## trial, Race the AI, Race the field, a cup or a cup's next race), so the car is picked last, and
## before every race of a cup, so the car can change inside a championship.
## - A line saying what is about to start (`event_text`, set by the menu).
## - The car cards (ui/car_card.gd: side view, name, top speed, mass, five bars with the upgrades in
##   green; a car you don't own shows a padlock and its price). Three a row, four for seven or eight cars (v6.29: three again for nine).
## - The picked car's upgrades (ui/part_chip.gd: level and the next level's price; a chip buys that
##   level, the game asks first) and its description line.
## - Your money, and START: it reads BUY and the price for a car you don't own (the game asks first),
##   LOCKED when the money is short.
## The pick is the "car" setting (UiData.picked_car()); the buttons only emit signals.
## (v6.33) Race the field on a circuit (`laps_choice`, set by the menu): a race length row above the money:
## Normal (the field race) or 10, 20, 30, 40 laps (an endurance race of ten cars); `race_laps` is the
## pick (0: normal), back to Normal each time the page opens for a race; L (or the pad on the chips) picks.
## (v6.38) The wing for the race's track (`track_id`, set by the menu; "" hides it): how many of the
## levels bought the picked car uses there (0 off .. all), with what that does to its grip at speed and
## top speed; free, kept per car and track (UiData.get_setup); F / Shift+F more / less (`setup_picked`).
## (v6.39) Beside it the tyres for that track: Soft, Medium, Hard or Rally (sim/tyres.gd), free and kept
## the same way; T / Shift+T the next / previous compound.
## (v6.41) Beside them the picked car's looks (sim/looks.gd): its paint, a livery and an underglow, free,
## kept per car (on every track; shown on its card and on the car in the race); a button (or P, V, G)
## the next one, a right click (or Shift) the one before (`look_picked`).
##
## Keys: arrows / WASD move over the cars, C / Shift+C next / previous car, 1-9, 0 and - buy the next level
## of that part, F / Shift+F the wing, T / Shift+T the tyres, P / V / G the paint, livery and underglow
## (Shift: back), Enter or Space starts, Esc or Backspace goes back. Gamepad: d-pad / stick over the cars
## (down to the parts, then to START), LB / RB the car, A starts or presses, B goes back.

## START was pressed (the menu starts what was chosen; the game refuses a car you don't own).
signal start
signal car_picked(id: String)
## buy the next level of part `part` of the picked car (the game asks first)
signal upgrade(part: String)
## (v6.33) a race length was picked (0: normal, else an endurance race's laps)
signal laps_picked(laps: int)
## (v6.38) the picked car's setup on `track_id` changed (key "wing": the levels it uses there, 0..5;
## 5 for all it has; (v6.39) key "compound": its tyres, 0..3, Tyres' index)
signal setup_picked(key: String, value: int)
## (v6.41) the picked car's looks changed (key "paint", "livery" or "glow": Looks' index; 0 factory)
signal look_picked(key: String, value: int)

const CarCard := preload("res://ui/car_card.gd")
const PartChip := preload("res://ui/part_chip.gd")
const PadRing := preload("res://ui/pad_ring.gd")
const PadNav := preload("res://ui/pad_nav.gd")
## The width a part chip needs for its name, ten pips and a price; narrower: the chips wrap.
const CHIP_MIN_W := 172.0
const PART_KEYS := [["Digit1", "Numpad1"], ["Digit2", "Numpad2"], ["Digit3", "Numpad3"], ["Digit4", "Numpad4"], ["Digit5", "Numpad5"],
	["Digit6", "Numpad6"], ["Digit7", "Numpad7"], ["Digit8", "Numpad8"], ["Digit9", "Numpad9"], ["Digit0", "Numpad0"],
	["Minus", "NumpadSubtract"]] # (v6.40: the eleventh part, the nitro tune)
## (v6.41) The looks buttons' keys (Shift: the one before) and what they read.
const LOOK_KEYS := {"paint": "KeyP", "livery": "KeyV", "glow": "KeyG"}

## What is about to start, e.g. "Time trial · 03 Harbor Run".
var event_text := "":
	set(v):
		event_text = v
		if _event_l != null:
			_event_l.text = v
var cards: Array = []
var cars_grid: GridContainer
var part_chips: Array = []
var parts_row: HBoxContainer
var parts_grid: GridContainer   # (v6.21) the chips: one row, or three a row when narrow
var _parts_cap: Control
var desc_row: HBoxContainer
var car_lock: Label
var car_desc_name: Label
var car_desc: Label
var start_btn: Button
var money_l: Label
var _event_l: Label
var _ring: Control
var _pad_at: Control = null   # the chip or START the pad highlight is on (null: the picked car's card)
## (v6.33) the race length: the row, its chips (Normal first), the pick (0 normal), and whether it shows
var laps_row: HBoxContainer
var laps_btns: Array = []
var laps_note: Label
var race_laps := 0
var laps_choice := false:
	set(v):
		laps_choice = v
		if laps_row != null:
			laps_row.visible = v
			_laps_wrap.visible = v
			_hint_text()
var _hint: Label
var _laps_wrap: Control
## (v6.38) the wing row: the track it is for ("" hides it), its buttons, value and note
var track_id := "":
	set(v):
		track_id = v
		if _wing_box != null: # (v6.41: the looks stay, for every track)
			_wing_box.visible = v != ""
			_tyre_box.visible = v != ""
var setup_row: Container
var wing_less: Button
var wing_more: Button
var wing_l: Label
var wing_note: Label # (v6.39: under the row: what the wing and the tyres do there)
## (v6.39) the tyre compound chips (Tyres' order: Soft, Medium, Hard, Rally)
var tyre_btns: Array = []
var _setup_wrap: Control
var _wing_box: Control
var _tyre_box: Control
## (v6.41) the looks buttons: {"paint": Button, "livery": Button, "glow": Button}
var look_btns := {}
var _swatches := {}


func _init() -> void:
	super("Choose your car")
	name = "CarScreen"
	max_width = 1180.0
	close_button.tooltip_text = "Back without starting"
	(close_button.get_meta("label") as Label).text = "Back"
	_event_l = UiStyle.label("", "text", UiStyle.FS_M, UiStyle.TEXT_2, 0.0, false, false, false, 22)
	_event_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_event_l.custom_minimum_size.x = 1
	var em := UiStyle.margin([0, UiStyle.S1, 0, UiStyle.S4])
	em.add_child(_event_l)
	body.add_child(em)
	cars_grid = GridContainer.new()
	cars_grid.columns = 3
	cars_grid.add_theme_constant_override("h_separation", UiStyle.S2)
	cars_grid.add_theme_constant_override("v_separation", UiStyle.S2)
	cars_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(cars_grid)
	for id in UiData.car_ids():
		var card: Control = CarCard.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.setup(id, UiData.car_info(id), UiData.car_profile(id))
		card.picked.connect(func() -> void:
			if id != UiData.picked_car():
				UiSound.play("ui_move")
			pick(id))
		card.activated.connect(press_start)
		cars_grid.add_child(card)
		cards.append(card)
	# the picked car's upgrades: a caption and a chip per part
	parts_row = UiStyle.hbox(UiStyle.S1)
	parts_row.custom_minimum_size.y = 26
	var cap := UiStyle.label("Upgrades", "display_bold", UiStyle.FS_S, UiStyle.TEXT_2, 0.1, true, false, false, UiStyle.FS_S)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cap.mouse_filter = Control.MOUSE_FILTER_PASS
	cap.tooltip_text = "Upgrade the picked car, ten levels a part (the last ones dear), bought in order with your money. Medal times stay the stock car's and the AI opponents keep their own car (every part at level 3), so upgrades make medals and wins easier."
	var cm := UiStyle.margin([0, 0, UiStyle.S2, 0])
	cm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cm.mouse_filter = Control.MOUSE_FILTER_PASS
	cm.add_child(cap)
	parts_row.add_child(cm)
	_parts_cap = cm
	# (v6.21: five parts) the chips in a grid: one row where they fit, three a row in a narrow window
	parts_grid = GridContainer.new()
	parts_grid.columns = UiData.upgrade_parts().size()
	parts_grid.add_theme_constant_override("h_separation", UiStyle.S1)
	parts_grid.add_theme_constant_override("v_separation", UiStyle.S1)
	parts_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parts_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parts_row.add_child(parts_grid)
	for p: Dictionary in UiData.upgrade_parts():
		var chip: Button = PartChip.new()
		chip.part_id = String(p.id)
		chip.part_name = String(p.name)
		chip.short_name = String(p.get("chip", ""))
		chip.pressed.connect(func() -> void: upgrade.emit(String(p.id)))
		parts_grid.add_child(chip)
		part_chips.append(chip)
	var pm := UiStyle.margin([0, UiStyle.S4, 0, 0])
	pm.add_child(parts_row)
	body.add_child(pm)
	desc_row = UiStyle.hbox(UiStyle.S1)
	desc_row.custom_minimum_size.y = 26
	car_lock = UiStyle.label("", "text_semi", UiStyle.FS_S, UiStyle.ACCENT, 0.0, false, false, false, 18)
	car_lock.visible = false
	desc_row.add_child(car_lock)
	car_desc_name = UiStyle.label("", "text", UiStyle.FS_S, UiStyle.TEXT, 0.0, false, false, false, 18)
	car_desc = UiStyle.label("", "text", UiStyle.FS_S, UiStyle.TEXT_2, 0.0, false, false, false, 18)
	car_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	car_desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	car_desc.custom_minimum_size.x = 1
	car_desc.mouse_filter = Control.MOUSE_FILTER_PASS
	desc_row.add_child(car_desc_name)
	desc_row.add_child(car_desc)
	for l: Label in [car_lock, car_desc_name, car_desc]:
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var dm := UiStyle.margin([0, UiStyle.S2, 0, 0])
	dm.add_child(desc_row)
	body.add_child(dm)
	# (v6.38) the wing and (v6.39) the tyres for the race's track (side by side, the tyres on a line of
	# their own in a narrow window), and a line on what they do there
	setup_row = HFlowContainer.new()
	setup_row.add_theme_constant_override("h_separation", UiStyle.S5)
	setup_row.add_theme_constant_override("v_separation", UiStyle.S1)
	setup_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wing_box := UiStyle.hbox(UiStyle.S1)
	var wcap := UiStyle.label("Wing", "display_bold", UiStyle.FS_S, UiStyle.TEXT_2, 0.1, true, false, false, UiStyle.FS_S)
	wcap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wcap.mouse_filter = Control.MOUSE_FILTER_PASS
	wcap.tooltip_text = "How much of its wing the car uses on this track, free and kept for each car and track: more grips harder in fast corners, less is quicker on the straights. Buy wing levels with the Wing chip. Medal times stay stock."
	var wm := UiStyle.margin([0, 0, UiStyle.S1, 0])
	wm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wm.mouse_filter = Control.MOUSE_FILTER_PASS
	wm.add_child(wcap)
	wing_box.add_child(wm)
	wing_less = UiStyle.button("← Less", "ChipButton", 26)
	wing_less.custom_minimum_size.x = 84
	wing_less.tooltip_text = "Less wing on this track: a higher top speed, less grip in fast corners (Shift+F)"
	wing_less.pressed.connect(func() -> void: step_wing(-1))
	wing_box.add_child(wing_less)
	wing_l = UiStyle.label("None", "text_semi", UiStyle.FS_S, UiStyle.TEXT, 0.0, false, false, false, 18)
	wing_l.custom_minimum_size.x = 64
	wing_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wing_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wing_box.add_child(wing_l)
	wing_more = UiStyle.button("More →", "ChipButton", 26)
	wing_more.custom_minimum_size.x = 84
	wing_more.tooltip_text = "More wing on this track: more grip in fast corners, a lower top speed (F)"
	wing_more.pressed.connect(func() -> void: step_wing(1))
	wing_box.add_child(wing_more)
	setup_row.add_child(wing_box)
	var tyre_box := UiStyle.hbox(UiStyle.S1)
	var tcap := UiStyle.label("Tyres", "display_bold", UiStyle.FS_S, UiStyle.TEXT_2, 0.1, true, false, false, UiStyle.FS_S)
	tcap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tcap.mouse_filter = Control.MOUSE_FILTER_PASS
	tcap.tooltip_text = "The tyres the car races on at this track, free and kept for each car and track: Soft grips most but wears from 10 km, Medium is the stock tyre, Hard never wears, Rally grips on dirt and snow. Medal times stay stock."
	var tm := UiStyle.margin([0, 0, UiStyle.S1, 0])
	tm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tm.mouse_filter = Control.MOUSE_FILTER_PASS
	tm.add_child(tcap)
	tyre_box.add_child(tm)
	for i in Tyres.count():
		var d: Dictionary = Tyres.def(i)
		var b := UiStyle.button(String(d.name), "ChipButton", 26)
		b.custom_minimum_size.x = 70
		b.set_meta("compound", i)
		b.tooltip_text = "%s tyres: %s (T / Shift+T)" % [d.name, d.what]
		b.pressed.connect(func() -> void: pick_compound(i))
		tyre_box.add_child(b)
		tyre_btns.append(b)
	setup_row.add_child(tyre_box)
	_wing_box = wing_box
	_tyre_box = tyre_box
	wing_box.visible = track_id != ""
	tyre_box.visible = track_id != ""
	# (v6.41) the picked car's looks: paint, livery, underglow (a click the next, a right click the one before)
	var looks_box := UiStyle.hbox(UiStyle.S1)
	var lkcap := UiStyle.label("Looks", "display_bold", UiStyle.FS_S, UiStyle.TEXT_2, 0.1, true, false, false, UiStyle.FS_S)
	lkcap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lkcap.mouse_filter = Control.MOUSE_FILTER_PASS
	lkcap.tooltip_text = "How the picked car looks, free and kept for each car on every track: its paint, a livery painted over it and an underglow light on the road under it. A click picks the next one, a right click the one before. Looks only: the car drives the same."
	var lkm := UiStyle.margin([0, 0, UiStyle.S1, 0])
	lkm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lkm.mouse_filter = Control.MOUSE_FILTER_PASS
	lkm.add_child(lkcap)
	looks_box.add_child(lkm)
	for key: String in ["paint", "livery", "glow"]:
		var b := UiStyle.button("", "ChipButton", 26)
		b.custom_minimum_size.x = 96
		b.set_meta("look", key)
		b.expand_icon = false
		b.pressed.connect(func() -> void: step_look(key, 1))
		b.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT and not b.disabled:
				b.accept_event()
				step_look(key, -1))
		looks_box.add_child(b)
		look_btns[key] = b
	setup_row.add_child(looks_box)
	wing_note = UiStyle.label("", "text", UiStyle.FS_S, UiStyle.TEXT_3, 0.0, false, false, false, 18)
	wing_note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	wing_note.custom_minimum_size.x = 1
	wing_note.mouse_filter = Control.MOUSE_FILTER_PASS
	var sbox := UiStyle.vbox(UiStyle.S1)
	sbox.add_child(setup_row)
	sbox.add_child(wing_note)
	var srm := UiStyle.margin([0, UiStyle.S2, 0, 0])
	srm.add_child(sbox)
	body.add_child(srm)
	_setup_wrap = srm
	# (v6.33) the race length (Race the field on a circuit)
	laps_row = UiStyle.hbox(UiStyle.S1)
	laps_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var lcap := UiStyle.label("Race length", "display_bold", UiStyle.FS_S, UiStyle.TEXT_2, 0.1, true, false, false, UiStyle.FS_S)
	lcap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lcap.mouse_filter = Control.MOUSE_FILTER_PASS
	lcap.tooltip_text = "Race length: Normal is the usual field race (six cars, the track's own laps, it counts for medals and records); 10 to 40 laps is an endurance race of ten cars (you and nine AI drivers), paid by place."
	var lm := UiStyle.margin([0, 0, UiStyle.S1, 0])
	lm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lm.mouse_filter = Control.MOUSE_FILTER_PASS
	lm.add_child(lcap)
	laps_row.add_child(lm)
	var choices: Array = [0]
	choices.append_array(Array(Field.ENDURANCE_LAPS))
	for n: int in choices:
		var b := UiStyle.button("Normal" if n == 0 else str(n), "ChipButton", 26)
		b.custom_minimum_size.x = 76 if n == 0 else 44
		b.set_meta("laps", n)
		b.tooltip_text = "The usual field race: six cars, the track's own laps" if n == 0 else "An endurance race: ten cars for %d laps (pause with Esc; nothing is saved mid-race)" % n
		b.pressed.connect(func() -> void:
			UiSound.play("ui_move")
			set_laps(n))
		laps_row.add_child(b)
		laps_btns.append(b)
	laps_note = UiStyle.label("", "text", UiStyle.FS_S, UiStyle.TEXT_3, 0.0, false, false, false, 18)
	laps_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	laps_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	laps_note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	laps_note.custom_minimum_size.x = 1
	var nm := UiStyle.margin([UiStyle.S2, 0, 0, 0])
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nm.add_child(laps_note)
	laps_row.add_child(nm)
	laps_row.visible = false
	var lrm := UiStyle.margin([0, UiStyle.S3, 0, 0])
	lrm.add_child(laps_row)
	body.add_child(lrm)
	_laps_wrap = lrm
	lrm.visible = false
	# your money, and START
	var foot := UiStyle.hbox(UiStyle.S4)
	money_l = UiStyle.label("", "display_bold", UiStyle.FS_L, UiStyle.TEXT, 0.02, false, true, false, UiStyle.FS_L)
	money_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	money_l.mouse_filter = Control.MOUSE_FILTER_PASS
	money_l.tooltip_text = "Your money: it buys cars and upgrades. Medals and wins against the AI pay it."
	foot.add_child(money_l)
	var hint := UiStyle.label("C next car · %s upgrade a part · Enter start" % _part_keys_text(), "text", UiStyle.FS_S, UiStyle.TEXT_3)
	_hint = hint
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hint.custom_minimum_size.x = 1
	foot.add_child(hint)
	start_btn = UiStyle.button("Start", "PrimaryButton", 46)
	start_btn.text = "START"
	start_btn.custom_minimum_size.x = 220
	start_btn.pressed.connect(press_start)
	foot.add_child(start_btn)
	var fm := UiStyle.margin([0, UiStyle.S4, 0, 0])
	fm.add_child(foot)
	body.add_child(fm)
	_ring = PadRing.new()
	add_child(_ring)


func open() -> void:
	_pad_at = null
	refresh()
	super()


## (v6.33) Pick race length `n` (0: normal; else one of Field.ENDURANCE_LAPS).
func set_laps(n: int) -> void:
	race_laps = n if Field.ENDURANCE_LAPS.has(n) else 0
	_style_laps()
	laps_picked.emit(race_laps)


func _style_laps() -> void:
	for b: Button in laps_btns:
		b.theme_type_variation = "ChipOnButton" if int(b.get_meta("laps")) == race_laps else "ChipButton"
	laps_note.text = "Ten cars for %d laps · paid by place · no records or medals" % race_laps if race_laps > 0 \
		else "Six cars, the track's own laps · counts for medals and records"


func _hint_text() -> void:
	if _hint != null:
		_hint.text = "C next car · %s upgrade a part · %sP V G looks · %sEnter start" % [_part_keys_text(), "F wing · T tyres · " if track_id != "" else "", "L laps · " if laps_choice else ""]


## (v6.38) The part keys in the hint: "1-9", "1-9, 0" with a tenth part, (v6.40) "1-9, 0, -" with an eleventh.
func _part_keys_text() -> String:
	var n := mini(part_chips.size(), PART_KEYS.size())
	return "1-%d" % n if n <= 9 else ("1-9, 0" if n == 10 else "1-9, 0, -")


## (v6.38) The picked car's wing on `track_id` one level more (1) or less (-1), between off and all it
## has (all of it is kept as the default, so a level bought later is used there too); a car you don't
## own or without a wing: nothing.
func step_wing(step: int) -> void:
	var car := UiData.picked_car()
	if track_id == "" or not UiData.owns_car(car):
		return
	var have := UiData.upgrade_levels(car)[Upgrades.index_of("wing")]
	var now := mini(have, int(UiData.get_setup(car, track_id).wing))
	var to := clampi(now + step, 0, have)
	if to == now:
		return
	UiSound.play("ui_move")
	setup_picked.emit("wing", to if to < have else int(SaveData.SETUP_KEYS.wing[2]))
	refresh()


## (v6.39) Put the picked car on tyre compound `i` (Tyres) at `track_id`: free; a car you don't own,
## or the compound it is on already: nothing.
func pick_compound(i: int) -> void:
	var car := UiData.picked_car()
	if track_id == "" or not UiData.owns_car(car) or i < 0 or i >= Tyres.count():
		return
	if int(UiData.get_setup(car, track_id).compound) == i:
		return
	UiSound.play("ui_move")
	setup_picked.emit("compound", i)
	refresh()


## (v6.41) The picked car's look `key` ("paint", "livery", "glow") one on (1) or back (-1), round the
## list (Looks); free, for a car you own (else nothing).
func step_look(key: String, step: int) -> void:
	var car := UiData.picked_car()
	if not UiData.owns_car(car) or not Looks.KEYS.has(key):
		return
	var n := Looks.list(key).size()
	var to := posmod(int(UiData.get_looks(car).get(key, 0)) + step, n)
	UiSound.play("ui_move")
	look_picked.emit(key, to)
	refresh()


## (v6.41) A small square of colour `c` for a looks button's icon (kept per colour).
func _swatch(c: Color) -> Texture2D:
	var k := c.to_html()
	if not _swatches.has(k):
		var img := Image.create(12, 12, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0.55))
		img.fill_rect(Rect2i(1, 1, 10, 10), c)
		_swatches[k] = ImageTexture.create_from_image(img)
	return _swatches[k]


func close() -> void:
	_ring.set_target(null)
	super()


## Redraw from UiData: the cards (picked, locks, upgrades), the parts, the description, START.
func refresh() -> void:
	var car := UiData.picked_car()
	var have := UiData.money()
	money_l.text = UiFormat.money(have)
	for c in cards:
		c.selected = c.car_id == car
		var p := UiData.car_price(c.car_id)
		c.set_lock(not UiData.owns_car(c.car_id), p, have >= p)
		var st := UiData.car_stats(c.car_id)
		c.set_upgrades(UiData.car_bars(c.car_id), float(st.top), UiData.upgrade_levels(c.car_id), float(st.get("mass", 0.0)))
		var lk := UiData.get_looks(c.car_id) # (v6.41) its paint and livery on the card
		c.set_looks(Looks.paint_color(c.car_id, int(lk.paint)) if int(lk.paint) > 0 else null, int(lk.livery))
	var info := UiData.car_info(car)
	var owned := UiData.owns_car(car)
	var price := UiData.car_price(car)
	var cname := String(info.name)
	var lv := UiData.upgrade_levels(car)
	var parts := UiData.upgrade_parts()
	for k in part_chips.size():
		var chip: Button = part_chips[k]
		var p: Dictionary = parts[k]
		var level: int = lv[k]
		var nxt := UiData.upgrade_cost(car, String(p.id), level + 1)
		# (v6.34) a part another one opens (the supercharger: engine 5; the aero tune: weight 5; the nitro tune: nitro 5) says so while it is shut
		var need: Dictionary = p.get("needs", {})
		var shut := not need.is_empty() and lv[Upgrades.index_of(String(need.part))] < int(need.level)
		var need_text := "%s %d" % [String(Upgrades.part(String(need.part)).name), int(need.level)] if shut else ""
		chip.show_part(String(p.id), String(p.name), level, int(p.max), nxt, have >= nxt, not owned, need_text)
		var now := "level %d of %d (%s)" % [level, int(p.max), Upgrades.effect(String(p.id), level)] if level > 0 else "stock (level 0 of %d)" % int(p.max)
		var trial_note := " Each level is fitted with a quick trial of arrows: a miss gives half the price back." if bool(p.get("trial", false)) else ""
		if not owned:
			chip.tooltip_text = "%s: %s. Buy the %s first to upgrade it." % [p.name, p.what, cname]
		elif shut:
			chip.tooltip_text = "%s: %s. Opens once the %s's %s is at level %d.%s" % [p.name, p.what, cname, need_text.to_lower().get_slice(" ", 0),
				int(need.level), trial_note]
		elif level >= int(p.max):
			chip.tooltip_text = "%s: %s. Every level bought (%s)." % [p.name, p.what, Upgrades.effect(String(p.id), level)]
		else:
			chip.tooltip_text = "%s of the %s: %s. Now %s. Level %d (%s) costs %s; you have %s.%s%s Medal times stay stock; the AI opponents keep their level 3 car." % [
				p.name, cname, p.what, now, level + 1, Upgrades.effect(String(p.id), level + 1), UiFormat.money(nxt), UiFormat.money(have),
				"" if have >= nxt else " %s more to go." % UiFormat.money(nxt - have), trial_note]
	_refresh_setup(car, owned, cname, lv)
	car_desc_name.text = cname
	car_desc.text = info.description
	car_desc.tooltip_text = "%s: %s" % [cname, info.description]
	car_lock.visible = not owned
	car_lock.text = ("Locked · %s ·" % UiFormat.money(price)) if not owned else ""
	if owned:
		start_btn.text = "START"
		start_btn.theme_type_variation = "PrimaryButton"
		start_btn.tooltip_text = "Start with the %s" % cname
	elif have >= price:
		start_btn.text = "BUY %s" % UiFormat.money(price)
		start_btn.theme_type_variation = "PrimaryButton"
		start_btn.tooltip_text = "Buy the %s for %s (you have %s): it asks first" % [cname, UiFormat.money(price), UiFormat.money(have)]
	else:
		start_btn.text = "LOCKED"
		start_btn.theme_type_variation = ""
		start_btn.tooltip_text = "The %s costs %s: %s more to go. Medals and wins against the AI opponents pay money." % [
			cname, UiFormat.money(price), UiFormat.money(price - have)]


## (v6.38) The wing row for car `car` on `track_id`: the levels it uses there of those bought, the
## buttons (off at the ends, for a car not yours or one without a wing) and what that does to its grip at
## speed and top speed (Upgrades.stats); (v6.39) the tyre chips (the compound lit) and what it does.
func _refresh_setup(car: String, owned: bool, cname: String, lv: PackedInt32Array) -> void:
	_hint_text()
	_refresh_looks(car, owned, cname)
	if track_id == "":
		wing_note.text = ("%s: %s" % [cname, Looks.text(UiData.get_looks(car))]) if owned else "Buy the %s to choose its looks" % cname
		wing_note.tooltip_text = wing_note.text
		return
	var wi := Upgrades.index_of("wing")
	var have: int = lv[wi]
	var use := mini(have, int(UiData.get_setup(car, track_id).wing))
	wing_l.text = "None" if have == 0 else ("Off" if use == 0 else "%d of %d" % [use, have])
	wing_less.disabled = not owned or use <= 0
	wing_more.disabled = not owned or use >= have
	var tname := String(Tracks.def(track_id).get("name", track_id))
	# (v6.39) the tyres
	var ci := clampi(int(UiData.get_setup(car, track_id).compound), 0, Tyres.count() - 1)
	for btn: Button in tyre_btns:
		btn.theme_type_variation = "ChipOnButton" if int(btn.get_meta("compound")) == ci and owned else "ChipButton"
		btn.disabled = not owned
	var tyre_text := "%s tyres: %s" % [Tyres.def(ci).name, Tyres.text(ci)]
	var wing_text := ""
	if not owned:
		wing_note.text = "Buy the %s to fit a wing and choose its tyres" % cname
	else:
		if have == 0:
			wing_text = "no wing yet (the Wing chip buys one)"
		else:
			var used := Upgrades.with_setup(lv, {"wing": use})
			var off := lv.duplicate()
			off[wi] = 0
			var st := Upgrades.stats(car, used)
			var st0 := Upgrades.stats(car, off)
			wing_text = "wing: grip at speed %.2f → %.2f g, top speed %d → %d km/h" % [float(st0.gripFast), float(st.gripFast),
				roundi(float(st0.top)), roundi(float(st.top))]
		wing_note.text = "On %s · %s · %s" % [tname, wing_text, tyre_text]
	wing_note.tooltip_text = "%s on %s: the wing %s (without it → with it); %s. Free; kept for this car and track." % [cname, tname,
		wing_l.text.to_lower(), tyre_text]


## (v6.41) The looks buttons for car `car`: what it wears (the paint and the underglow with a swatch),
## off for a car you don't own.
func _refresh_looks(car: String, owned: bool, cname: String) -> void:
	var lk := UiData.get_looks(car)
	var p := int(lk.paint)
	var l := int(lk.livery)
	var g := int(lk.glow)
	var pb: Button = look_btns.paint
	var lb: Button = look_btns.livery
	var gb: Button = look_btns.glow
	pb.text = "%s paint" % Looks.paint(p).name
	pb.icon = _swatch(Looks.paint_color(car, p))
	lb.text = "%s livery" % Looks.livery(l).name
	gb.text = "%s glow" % Looks.glow(g).name if g > 0 else "No glow"
	gb.icon = _swatch(Looks.glow_color(g)) if g > 0 else null
	var keys := " (P, Shift+P or a right click: the one before)"
	pb.tooltip_text = "The %s's paint: %s%s. Free; looks only." % [cname, "its factory colour" if p == 0 else Looks.paint(p).name.to_lower(), keys]
	lb.tooltip_text = "The %s's livery: %s, %s%s. Free; looks only." % [cname, Looks.livery(l).name, Looks.livery(l).what, keys.replace("P,", "V,").replace("+P", "+V")]
	gb.tooltip_text = "The %s's underglow, a coloured light on the road under it: %s%s. Free; looks only." % [cname,
		"off" if g == 0 else Looks.glow(g).name.to_lower(), keys.replace("P,", "G,").replace("+P", "+G")]
	for b: Button in [pb, lb, gb]:
		b.disabled = not owned
		if not owned:
			b.tooltip_text = "Buy the %s to choose its looks" % cname


## Pick car `id` (remembered: the "car" setting).
func pick(id: String) -> void:
	if not UiData.car_ids().has(id):
		return
	UiData.set_setting("car", id)
	car_picked.emit(id)
	refresh()


## The next (step 1) or previous (step -1) car.
func cycle(step: int) -> void:
	var ids := UiData.car_ids()
	var i := ids.find(UiData.picked_car())
	pick(ids[(i + step + ids.size()) % ids.size()])


## The picked car's card.
func card() -> Control:
	for c in cards:
		if c.car_id == UiData.picked_car():
			return c
	return null


func press_start() -> void:
	start.emit()


## The part chips the pad highlight can go to (enabled).
## (v6.33) And the race length chips, when they show.
func _pad_parts() -> Array:
	var all: Array = part_chips.duplicate()
	if track_id != "": # (v6.38) the wing buttons, (v6.39) the tyres
		all.append_array([wing_less, wing_more])
		all.append_array(tyre_btns)
	all.append_array([look_btns.paint, look_btns.livery, look_btns.glow]) # (v6.41)
	if laps_choice:
		all.append_array(laps_btns)
	return all.filter(func(c: Control) -> bool: return c.is_visible_in_tree() and not (c as BaseButton).disabled)


## The control the pad highlight is on (null: none shown), for tests.
func pad_target() -> Control:
	return _ring.target


## Keys and gamepad while the page is open (MainMenu forwards them).
func handle_keys(inp: Object) -> void:
	if inp.consume(["Escape", "Backspace", "PadB"]):
		UiSound.play("ui_back")
		close()
		return
	var was := UiData.picked_car()
	var at := maxi(0, UiData.car_ids().find(was))
	var n := cards.size()
	var cols := maxi(1, cars_grid.columns)
	if inp.consume(["ArrowRight", "KeyD"]):
		pick(cards[(at + 1) % n].car_id)
	elif inp.consume(["ArrowLeft", "KeyA"]):
		pick(cards[(at + n - 1) % n].car_id)
	elif inp.consume(["ArrowDown", "KeyS"]):
		pick(cards[mini(at + cols, n - 1)].car_id)
	elif inp.consume(["ArrowUp", "KeyW"]):
		pick(cards[at - cols if at - cols >= 0 else at].car_id)
	if inp.consume(["KeyC"]):
		cycle(-1 if inp.consume(["Shift+KeyC"]) else 1)
	if track_id != "" and inp.consume(["KeyF"]): # (v6.38) the wing: F more, Shift+F less
		step_wing(-1 if inp.consume(["Shift+KeyF"]) else 1)
	if track_id != "" and inp.consume(["KeyT"]): # (v6.39) the tyres: T next, Shift+T previous
		var now := int(UiData.get_setup(UiData.picked_car(), track_id).compound)
		pick_compound(posmod(now + (-1 if inp.consume(["Shift+KeyT"]) else 1), Tyres.count()))
	for key: String in LOOK_KEYS: # (v6.41) the looks: P paint, V livery, G underglow (Shift: the one before)
		if inp.consume([LOOK_KEYS[key]]):
			step_look(key, -1 if inp.consume(["Shift+" + LOOK_KEYS[key]]) else 1)
	if laps_choice and inp.consume(["KeyL"]): # (v6.33) the next race length
		var choices: Array = [0]
		choices.append_array(Array(Field.ENDURANCE_LAPS))
		UiSound.play("ui_move")
		set_laps(choices[(choices.find(race_laps) + 1) % choices.size()])
	for k in mini(part_chips.size(), PART_KEYS.size()):
		if inp.consume(PART_KEYS[k]):
			upgrade.emit(String(part_chips[k].part_id))
			return
	if inp.consume(["Enter", "Space", "NumpadEnter"]):
		press_start()
		return
	_handle_pad(inp)
	if UiData.picked_car() != was:
		UiSound.play("ui_move")


## Gamepad: the highlight is on the picked car's card (_pad_at null), a part chip or START. On the
## cards the d-pad picks the nearest card; down from the last row goes to the parts (or START), down
## from the parts to START (the second row of chips first when they take two), up back again. LB / RB pick the previous / next car. A starts (on a card or
## START) or buys the part's next level. The highlight shows while the pad is the last input used.
func _handle_pad(inp: Object) -> void:
	var dir: String = inp.nav_dir()
	var a: bool = inp.consume(["PadA"])
	var step := (1 if inp.consume(["PadRB"]) else 0) - (1 if inp.consume(["PadLB"]) else 0)
	var pad := bool(inp.get("pad_active"))
	var shown: bool = _ring.target != null
	var parts := _pad_parts()
	var at: Control = _pad_at if (_pad_at == start_btn or parts.has(_pad_at)) else null
	if step != 0:
		cycle(step)
	if dir != "" and shown:
		if at == null:
			var next := PadNav.nearest_control(card(), dir, cards)
			if next != null:
				pick(next.car_id)
			elif dir == "down":
				at = start_btn if parts.is_empty() else (PadNav.nearest_control(card(), "down", parts) if PadNav.nearest_control(card(), "down", parts) != null else parts[0])
		elif at == start_btn:
			if dir == "up" or dir == "left":
				at = parts[parts.size() - 1] if not parts.is_empty() else null
		elif dir == "up": # (v6.34: two rows of chips when narrow) the row above, else the car
			at = PadNav.nearest_control(at, "up", parts)
		elif dir == "down":
			var below := PadNav.nearest_control(at, "down", parts)
			at = below if below != null else start_btn
		else:
			var next := PadNav.nearest_control(at, dir, parts)
			if next != null:
				at = next
			elif dir == "right":
				at = start_btn
		if at != _pad_at:
			UiSound.play("ui_move")
	elif a and shown:
		if at == null or at == start_btn:
			press_start()
		else:
			(at as BaseButton).pressed.emit()
		return
	_pad_at = at
	if not pad:
		_ring.set_target(null)
	elif at == null:
		_ring.set_target(card(), false, 3.0)
	else:
		_ring.set_target(at, true, 3.0)


func _on_layout(w: float) -> void:
	var inner := inner_width(w)
	var n := cards.size()
	var cols := 3 if n <= 6 or n == 9 else 4 # (v6.29: nine cars, three rows of three)
	if inner < 760.0:
		cols = 2
	cars_grid.columns = cols
	var card_w := (inner - (cols - 1) * UiStyle.S2) / cols
	# the part chips: one row while a chip keeps room for its name, pips and price
	var np := part_chips.size()
	var chips_w := inner - _parts_cap.get_combined_minimum_size().x - UiStyle.S1
	# (v6.34-6.40: eleven parts) one row while they fit, else two rows (six and five), else rows of
	# four or three, the widest that keeps every chip CHIP_MIN_W wide
	var tries: Array[int] = [np, ceili(np / 2.0), ceili(np / 3.0), ceili(np / 4.0), ceili(np / 5.0)]
	var cols_p: int = tries[-1]
	for c: int in tries:
		if (chips_w - (c - 1) * UiStyle.S1) / c >= CHIP_MIN_W:
			cols_p = c
			break
	parts_grid.columns = cols_p
	for c in cards:
		c.stacked = card_w < 330.0
		c.short_spec = card_w < 300.0
