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
##
## (v6.37) The setup for the race's track (`track_id`, set by the menu; "" hides it): the gearbox tune,
## Short 2 to Long 2, with what it does to the picked car's top speed and 0-200 km/h; free, kept per car
## and track (UiData.get_setup); G / Shift+G longer / shorter (`setup_picked` goes out).
##
## Keys: arrows / WASD move over the cars, C / Shift+C next / previous car, 1-9 buy the next level of
## that part, G / Shift+G the gearbox, Enter or Space starts, Esc or Backspace goes back. Gamepad: d-pad / stick over the cars
## (down to the parts, then to START), LB / RB the car, A starts or presses, B goes back.

## START was pressed (the menu starts what was chosen; the game refuses a car you don't own).
signal start
signal car_picked(id: String)
## buy the next level of part `part` of the picked car (the game asks first)
signal upgrade(part: String)
## (v6.33) a race length was picked (0: normal, else an endurance race's laps)
signal laps_picked(laps: int)
## (v6.37) the picked car's setup on `track_id` changed (key "gear": the gearbox step, -2..2)
signal setup_picked(key: String, value: int)

const CarCard := preload("res://ui/car_card.gd")
const PartChip := preload("res://ui/part_chip.gd")
const PadRing := preload("res://ui/pad_ring.gd")
const PadNav := preload("res://ui/pad_nav.gd")
## The width a part chip needs for its name, ten pips and a price; narrower: the chips wrap.
const CHIP_MIN_W := 172.0
const PART_KEYS := [["Digit1", "Numpad1"], ["Digit2", "Numpad2"], ["Digit3", "Numpad3"], ["Digit4", "Numpad4"], ["Digit5", "Numpad5"],
	["Digit6", "Numpad6"], ["Digit7", "Numpad7"], ["Digit8", "Numpad8"], ["Digit9", "Numpad9"]]

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
## (v6.37) the setup row: the track it is for ("" hides it), the gearbox buttons, its value and note
var track_id := "":
	set(v):
		track_id = v
		if setup_row != null:
			_setup_wrap.visible = v != ""
var setup_row: HBoxContainer
var gear_shorter: Button
var gear_longer: Button
var gear_l: Label
var gear_note: Label
var _setup_wrap: Control


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
	# (v6.37) the gearbox tune for the race's track
	setup_row = UiStyle.hbox(UiStyle.S1)
	setup_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var gcap := UiStyle.label("Gearbox", "display_bold", UiStyle.FS_S, UiStyle.TEXT_2, 0.1, true, false, false, UiStyle.FS_S)
	gcap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gcap.mouse_filter = Control.MOUSE_FILTER_PASS
	gcap.tooltip_text = "The gearbox tune, free and kept for each car and track: short gears pull harder out of the corners but run out of revs sooner (a lower top speed), long gears reach a higher top speed but pull less. Medal times stay stock."
	var gm := UiStyle.margin([0, 0, UiStyle.S1, 0])
	gm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gm.mouse_filter = Control.MOUSE_FILTER_PASS
	gm.add_child(gcap)
	setup_row.add_child(gm)
	gear_shorter = UiStyle.button("← Shorter", "ChipButton", 26)
	gear_shorter.custom_minimum_size.x = 96
	gear_shorter.tooltip_text = "Shorter gears: quicker off the line and out of corners, a lower top speed (Shift+G)"
	gear_shorter.pressed.connect(func() -> void: step_gear(-1))
	setup_row.add_child(gear_shorter)
	gear_l = UiStyle.label("Stock", "text_semi", UiStyle.FS_S, UiStyle.TEXT, 0.0, false, false, false, 18)
	gear_l.custom_minimum_size.x = 64
	gear_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gear_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	setup_row.add_child(gear_l)
	gear_longer = UiStyle.button("Longer →", "ChipButton", 26)
	gear_longer.custom_minimum_size.x = 96
	gear_longer.tooltip_text = "Longer gears: a higher top speed, slower off the line (G)"
	gear_longer.pressed.connect(func() -> void: step_gear(1))
	setup_row.add_child(gear_longer)
	gear_note = UiStyle.label("", "text", UiStyle.FS_S, UiStyle.TEXT_3, 0.0, false, false, false, 18)
	gear_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gear_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gear_note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	gear_note.custom_minimum_size.x = 1
	gear_note.mouse_filter = Control.MOUSE_FILTER_PASS
	var gnm := UiStyle.margin([UiStyle.S2, 0, 0, 0])
	gnm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gnm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gnm.mouse_filter = Control.MOUSE_FILTER_PASS
	gnm.add_child(gear_note)
	setup_row.add_child(gnm)
	var srm := UiStyle.margin([0, UiStyle.S2, 0, 0])
	srm.add_child(setup_row)
	body.add_child(srm)
	_setup_wrap = srm
	srm.visible = false
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
	var hint := UiStyle.label("C next car · 1-%d upgrade a part · Enter start" % part_chips.size(), "text", UiStyle.FS_S, UiStyle.TEXT_3)
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
		_hint.text = "C next car · 1-%d upgrade a part · %s%sEnter start" % [part_chips.size(), "G gears · " if track_id != "" else "", "L laps · " if laps_choice else ""]


## (v6.37) The picked car's gearbox one step longer (1) or shorter (-1) on `track_id` (it stops at
## Short 2 and Long 2); a car you don't own: nothing.
func step_gear(step: int) -> void:
	var car := UiData.picked_car()
	if track_id == "" or not UiData.owns_car(car):
		return
	var g := Upgrades.gear_of(UiData.get_setup(car, track_id))
	var to := clampi(g + step, Upgrades.GEAR_MIN, Upgrades.GEAR_MAX)
	if to == g:
		return
	UiSound.play("ui_move")
	setup_picked.emit("gear", to)
	refresh()


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
		# (v6.34) a part another one opens (the supercharger: engine 5; the aero tune: weight 5) says so while it is shut
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


## (v6.37) The gearbox row for car `car` on `track_id`: its step, the buttons (off at the ends or for
## a car not yours) and what the step does to the top speed and 0-200 km/h (Upgrades.stats).
func _refresh_setup(car: String, owned: bool, cname: String, lv: PackedInt32Array) -> void:
	_hint_text()
	if track_id == "":
		return
	var g := Upgrades.gear_of(UiData.get_setup(car, track_id))
	gear_l.text = Upgrades.gear_name(g)
	gear_shorter.disabled = not owned or g <= Upgrades.GEAR_MIN
	gear_longer.disabled = not owned or g >= Upgrades.GEAR_MAX
	var tname := String(Tracks.def(track_id).get("name", track_id))
	if not owned:
		gear_note.text = "Buy the %s to tune its gears" % cname
	else:
		var st0 := Upgrades.stats(car, lv)
		var st := Upgrades.stats(car, lv, {"gear": g})
		if g == 0:
			gear_note.text = "Stock gears on %s · %d km/h · 0-200 in %.1f s" % [tname, roundi(float(st0.top)), float(st0.accel200)]
		else:
			gear_note.text = "On %s · top speed %d → %d km/h · 0-200 %.1f → %.1f s" % [tname, roundi(float(st0.top)), roundi(float(st.top)),
				float(st0.accel200), float(st.accel200)]
	gear_note.tooltip_text = "%s's gears on %s: %s. Free; kept for this car and track." % [cname, tname, Upgrades.gear_name(g)]


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
	if track_id != "": # (v6.37) the gearbox buttons
		all.append_array([gear_shorter, gear_longer])
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
	if track_id != "" and inp.consume(["KeyG"]): # (v6.37) the gearbox: G longer, Shift+G shorter
		step_gear(-1 if inp.consume(["Shift+KeyG"]) else 1)
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
	# (v6.34-6.35: seven parts) one row while they fit, else two rows (four and three), else three
	var cols_p := ceili(np / 3.0)
	for c: int in [np, ceili(np / 2.0)]:
		if (chips_w - (c - 1) * UiStyle.S1) / c >= CHIP_MIN_W:
			cols_p = c
			break
	parts_grid.columns = cols_p
	for c in cards:
		c.stacked = card_w < 330.0
		c.short_spec = card_w < 300.0
