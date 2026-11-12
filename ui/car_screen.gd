class_name CarScreen
extends "res://ui/dialog_screen.gd"
## car_screen.gd (v6.19.0): the car page, over the menu. It opens after you chose what to race (time
## trial, Race the AI, Race the field, a cup or a cup's next race), so the car is picked last, and
## before every race of a cup, so the car can change inside a championship.
## - A line saying what is about to start (`event_text`, set by the menu).
## - The car cards (ui/car_card.gd: side view, name, top speed, mass, five bars with the upgrades in
##   green; a car you don't own shows a padlock and its price). Three a row, four from seven cars.
## - The picked car's upgrades (ui/part_chip.gd: level and the next level's price; a chip buys that
##   level, the game asks first) and its description line.
## - Your money, and START: it reads BUY and the price for a car you don't own (the game asks first),
##   LOCKED when the money is short.
## The pick is the "car" setting (UiData.picked_car()); the buttons only emit signals.
##
## Keys: arrows / WASD move over the cars, C / Shift+C next / previous car, 1-9 buy the next level of
## that part, Enter or Space starts, Esc or Backspace goes back. Gamepad: d-pad / stick over the cars
## (down to the parts, then to START), LB / RB the car, A starts or presses, B goes back.

## START was pressed (the menu starts what was chosen; the game refuses a car you don't own).
signal start
signal car_picked(id: String)
## buy the next level of part `part` of the picked car (the game asks first)
signal upgrade(part: String)

const CarCard := preload("res://ui/car_card.gd")
const PartChip := preload("res://ui/part_chip.gd")
const PadRing := preload("res://ui/pad_ring.gd")
const PadNav := preload("res://ui/pad_nav.gd")
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
var desc_row: HBoxContainer
var car_lock: Label
var car_desc_name: Label
var car_desc: Label
var start_btn: Button
var money_l: Label
var _event_l: Label
var _ring: Control
var _pad_at: Control = null   # the chip or START the pad highlight is on (null: the picked car's card)


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
	cap.tooltip_text = "Upgrade the picked car, ten levels a part (the last ones dear), bought in order with your money. Medal times and the AI opponents stay as they are (stock cars), so upgrades make medals and wins easier."
	var cm := UiStyle.margin([0, 0, UiStyle.S2, 0])
	cm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cm.mouse_filter = Control.MOUSE_FILTER_PASS
	cm.add_child(cap)
	parts_row.add_child(cm)
	for p: Dictionary in UiData.upgrade_parts():
		var chip: Button = PartChip.new()
		chip.part_id = String(p.id)
		chip.part_name = String(p.name)
		chip.pressed.connect(func() -> void: upgrade.emit(String(p.id)))
		parts_row.add_child(chip)
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
	# your money, and START
	var foot := UiStyle.hbox(UiStyle.S4)
	money_l = UiStyle.label("", "display_bold", UiStyle.FS_L, UiStyle.TEXT, 0.02, false, true, false, UiStyle.FS_L)
	money_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	money_l.mouse_filter = Control.MOUSE_FILTER_PASS
	money_l.tooltip_text = "Your money: it buys cars and upgrades. Medals and wins against the AI pay it."
	foot.add_child(money_l)
	var hint := UiStyle.label("C next car · 1-%d upgrade a part · Enter start" % part_chips.size(), "text", UiStyle.FS_S, UiStyle.TEXT_3)
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
		c.set_upgrades(UiData.car_bars(c.car_id), float(UiData.car_stats(c.car_id).top), UiData.upgrade_levels(c.car_id))
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
		chip.show_part(String(p.id), String(p.name), level, int(p.max), nxt, have >= nxt, not owned)
		var now := "level %d of %d (%s)" % [level, int(p.max), Upgrades.effect(String(p.id), level)] if level > 0 else "stock (level 0 of %d)" % int(p.max)
		if not owned:
			chip.tooltip_text = "%s: %s. Buy the %s first to upgrade it." % [p.name, p.what, cname]
		elif level >= int(p.max):
			chip.tooltip_text = "%s: %s. Every level bought (%s)." % [p.name, p.what, Upgrades.effect(String(p.id), level)]
		else:
			chip.tooltip_text = "%s of the %s: %s. Now %s. Level %d (%s) costs %s; you have %s.%s Medal times and the AI opponents stay stock." % [
				p.name, cname, p.what, now, level + 1, Upgrades.effect(String(p.id), level + 1), UiFormat.money(nxt), UiFormat.money(have),
				"" if have >= nxt else " %s more to go." % UiFormat.money(nxt - have)]
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
func _pad_parts() -> Array:
	return part_chips.filter(func(c: Control) -> bool: return c.is_visible_in_tree() and not (c as BaseButton).disabled)


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
## from the parts to START, up back again. LB / RB pick the previous / next car. A starts (on a card or
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
		elif dir == "up":
			at = null
		elif dir == "down":
			at = start_btn
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
	var cols := 3 if n <= 6 else 4
	if inner < 760.0:
		cols = 2
	cars_grid.columns = cols
	var card_w := (inner - (cols - 1) * UiStyle.S2) / cols
	for c in cards:
		c.stacked = card_w < 330.0
		c.short_spec = card_w < 300.0
