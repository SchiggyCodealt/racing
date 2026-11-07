class_name CupScreen
extends "res://ui/dialog_screen.gd"
## cup_screen.gd (v6.14.0): Championships, over the menu (opened by its Cups button or T, and by the
## game between the races of a cup). The same panel and scrim as Settings. Two faces:
## - The picker (no cup in progress): one row per cup (sim/cups.gd: its number, name, tracks, difficulty,
##   or what still has to open; its trophies per level, the cabinet: gold, silver, bronze or an empty
##   place for Rookie .. Elite), the field level's chips, a line saying the car you race and what a win
##   pays at that level now, and START CUP. A locked cup can be picked but not started.
## - The standings (a cup in progress): the cup, level and car, the table after the races run
##   (ui/cup_table.gd), the next race and your grid slot, RACE n: <track> and Quit cup (the game asks
##   first). Esc closes it and keeps the cup: the menu's Cups button opens it here again.
## Data comes through UiData (cup_list, cup_pays, cup_trophies) and `run_view` (a Callable the game
## sets: UiData.cup_view of its cup in progress, {} none); the buttons only emit signals.
##
## Keys: picker: up / down (W / S) a cup, left / right (A / D) the level, Enter or Space starts; standings:
## Enter or Space races, Q quits; Esc, Backspace or T closes. Gamepad: d-pad / stick, A, X quits, B closes.

signal start_cup(cup_id: String, level: String)
signal next_race
signal quit_cup

const DiffBars := preload("res://ui/diff_bars.gd")
const W := preload("res://ui/widgets.gd")

## Returns the standings view of the cup in progress ({} none): the game's UiData.cup_view(cup).
var run_view: Callable = Callable()
## The picker's choice (kept while the game runs).
static var picked_cup := ""
static var picked_level := ""

var title_label: Label
var _intro: Label
var _list: VBoxContainer
var _rows: Array = []          # [{id, box, open}]
var _levels: HBoxContainer
var _level_btns: Dictionary = {}
var _info: RichTextLabel
var _start_btn: Button
var _stand: VBoxContainer
var _stand_sub: Label
var _table: CupTable
var _next_l: Label
var _race_btn: Button
var _quit_btn: Button
var _picker: VBoxContainer
var _view: Dictionary = {}


func _init() -> void:
	super("Championships")
	name = "CupScreen"
	max_width = 860.0
	title_label = (body.get_child(0) as HBoxContainer).get_child(0)
	close_button.tooltip_text = "Back to the menu (a cup in progress is kept)"
	_picker = UiStyle.vbox(0)
	body.add_child(_picker)
	_intro = UiStyle.label("Three races back to back against the same five AI drivers, with the car you picked. Each race pays as a field race; points 10-8-6-5-4-3 make the standings, which set the next grid. The top three win trophies; the cup pays by your final place, once per cup, level and place.",
		"text", UiStyle.FS_S, UiStyle.TEXT_2, 0.0, false, false, false, 19)
	_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_intro.custom_minimum_size.x = 1
	var im := UiStyle.margin([0, UiStyle.S2, 0, UiStyle.S3])
	im.add_child(_intro)
	_picker.add_child(im)
	_list = UiStyle.vbox(UiStyle.S1)
	_picker.add_child(_list)
	for c: Dictionary in UiData.cup_list():
		_add_row(c)
	# the field level
	var lv_row := UiStyle.hbox(UiStyle.S3)
	var cap := UiStyle.label("Field level", "display_bold", UiStyle.FS_S, UiStyle.TEXT_2, 0.1, true, false, false, UiStyle.FS_S)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cap.custom_minimum_size.x = 96
	lv_row.add_child(cap)
	_levels = UiStyle.hbox(UiStyle.S1)
	_levels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id: String in Opponents.ids():
		var b := UiStyle.button(Opponents.level_name(id), "ChipButton", 26)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.x = 1
		b.pressed.connect(func() -> void:
			UiSound.play("ui_move")
			pick_level(id))
		_levels.add_child(b)
		_level_btns[id] = b
	lv_row.add_child(_levels)
	var lm := UiStyle.margin([0, UiStyle.S4, 0, 0])
	lm.add_child(lv_row)
	_picker.add_child(lm)
	_info = RichTextLabel.new()
	_info.bbcode_enabled = true
	_info.fit_content = true
	_info.scroll_active = false
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size.x = 1
	_info.add_theme_font_override("normal_font", UiStyle.font("text", UiStyle.FS_S, 0, false, 19))
	_info.add_theme_font_override("bold_font", UiStyle.font("text_semi", UiStyle.FS_S, 0, false, 19))
	_info.add_theme_font_size_override("normal_font_size", UiStyle.FS_S)
	_info.add_theme_font_size_override("bold_font_size", UiStyle.FS_S)
	_info.add_theme_color_override("default_color", UiStyle.TEXT_2)
	var nm := UiStyle.margin([0, UiStyle.S3, 0, UiStyle.S3])
	nm.add_child(_info)
	_picker.add_child(nm)
	_start_btn = UiStyle.button("Start cup", "PrimaryButton", 46)
	_start_btn.text = "START CUP"
	_start_btn.custom_minimum_size.x = 220
	_start_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_start_btn.pressed.connect(start)
	_picker.add_child(_start_btn)
	# the standings of a cup in progress
	_stand = UiStyle.vbox(0)
	_stand.visible = false
	body.add_child(_stand)
	_stand_sub = UiStyle.label("", "text", UiStyle.FS_M, UiStyle.TEXT_2, 0.0, false, false, false, 22)
	var sm := UiStyle.margin([0, UiStyle.S2, 0, UiStyle.S4])
	sm.add_child(_stand_sub)
	_stand.add_child(sm)
	_table = CupTable.new()
	_stand.add_child(_table)
	_next_l = UiStyle.label("", "text", UiStyle.FS_M, UiStyle.TEXT, 0.0, false, false, false, 22)
	_next_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_next_l.custom_minimum_size.x = 1
	var xm := UiStyle.margin([0, UiStyle.S5, 0, UiStyle.S4])
	xm.add_child(_next_l)
	_stand.add_child(xm)
	var bar := UiStyle.hbox(UiStyle.S4)
	_race_btn = UiStyle.button("Race", "PrimaryButton", 46)
	_race_btn.custom_minimum_size.x = 260
	_race_btn.pressed.connect(func() -> void:
		UiSound.play("ui_confirm")
		next_race.emit())
	bar.add_child(_race_btn)
	_quit_btn = button_with_cap("Quit cup", "Q")
	_quit_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_quit_btn.tooltip_text = "End this cup: it pays nothing and gives no trophy (the races you ran keep their pay)"
	_quit_btn.pressed.connect(func() -> void: quit_cup.emit())
	bar.add_child(_quit_btn)
	_stand.add_child(bar)


func _add_row(c: Dictionary) -> void:
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var row := UiStyle.hbox(UiStyle.S4)
	box.add_child(row)
	var num := UiStyle.label(str(c.number), "display_bold", UiStyle.FS_L, UiStyle.ACCENT, 0.0, false, true, false, UiStyle.FS_L)
	num.custom_minimum_size.x = 16
	num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(num)
	var col := UiStyle.vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := UiStyle.hbox(UiStyle.S3)
	var nm := UiStyle.label(str(c.name), "display_bold", UiStyle.FS_L, UiStyle.TEXT, 0.02, true, false, false, 24)
	head.add_child(nm)
	var diff := DiffBars.new()
	diff.level = int(c.difficulty)
	head.add_child(diff)
	col.add_child(head)
	var sub := UiStyle.hbox(UiStyle.S2)
	var lock := Control.new()
	lock.custom_minimum_size = Vector2(9, 18)
	lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock.draw.connect(func() -> void: W.padlock(lock, Vector2(0, 4), UiStyle.ACCENT))
	sub.add_child(lock)
	var tr := UiStyle.label("", "text", UiStyle.FS_S, UiStyle.TEXT_2, 0.0, false, false, false, 18)
	tr.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr.custom_minimum_size.x = 1
	sub.add_child(tr)
	col.add_child(sub)
	row.add_child(col)
	# the cabinet: a trophy place per level
	var cab := Control.new()
	cab.custom_minimum_size = Vector2(Opponents.ids().size() * 34, 40)
	cab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cab.mouse_filter = Control.MOUSE_FILTER_PASS
	cab.draw.connect(_draw_cabinet.bind(cab, String(c.id)))
	row.add_child(cab)
	box.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			if picked_cup != String(c.id):
				UiSound.play("ui_move")
			pick_cup(String(c.id)))
	_list.add_child(box)
	_rows.append({"id": String(c.id), "box": box, "num": num, "name": nm, "tracks": tr, "lock": lock, "cab": cab})


## One cup's trophies, Rookie to Elite: a trophy in its colour where you finished in the top three,
## a faint one where not, the level's initial under it.
func _draw_cabinet(cab: Control, cup_id: String) -> void:
	var tro: Dictionary = UiData.cup_trophies().get(cup_id, {})
	var ids := Opponents.ids()
	var f := UiStyle.face("text_semi")
	for k in ids.size():
		var cx := 17.0 + 34.0 * k
		var place := int(tro.get(ids[k], 0))
		var kind := Cups.trophy(place)
		W.trophy(cab, cx, 2.0, 22.0, trophy_color(kind))
		var t := Opponents.level_name(ids[k]).substr(0, 3)
		var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		cab.draw_string(f, Vector2(cx - w * 0.5, 38), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiStyle.TEXT_2 if kind != "" else UiStyle.TEXT_3)


## The colour of a trophy ("gold", "silver", "bronze"; "": an empty place).
static func trophy_color(kind: String) -> Color:
	return UiStyle.MEDAL_COLORS[kind] if UiStyle.MEDAL_COLORS.has(kind) else Color(1, 1, 1, 0.1)


func open() -> void:
	refresh()
	super()


## Show the picker or the standings of the cup in progress, from the data now.
func refresh() -> void:
	_view = run_view.call() if run_view.is_valid() else {}
	var standing := not _view.is_empty()
	_picker.visible = not standing
	_stand.visible = standing
	if standing:
		_render_standings()
	else:
		title_label.text = "CHAMPIONSHIPS"
		if picked_cup == "" or Cups.cup(picked_cup).is_empty():
			picked_cup = _first_open()
		if Opponents.rank(picked_level) < 0:
			var opp := UiData.opponent()
			picked_level = opp if Opponents.rank(opp) >= 0 else "rookie"
		_render_picker()


var is_standings: bool:
	get:
		return visible and _stand.visible


func _first_open() -> String:
	for c: Dictionary in UiData.cup_list():
		if bool(c.open):
			return String(c.id)
	return Cups.ids()[0]


func pick_cup(id: String) -> void:
	if Cups.cup(id).is_empty():
		return
	picked_cup = id
	_render_picker()


func pick_level(id: String) -> void:
	if Opponents.rank(id) < 0:
		return
	picked_level = id
	_render_picker()


func _render_picker() -> void:
	var list := UiData.cup_list()
	var picked: Dictionary = {}
	for k in list.size():
		var c: Dictionary = list[k]
		var r: Dictionary = _rows[k]
		var on := String(c.id) == picked_cup
		if on:
			picked = c
		var sb := UiStyle.box(UiStyle.BG_2 if on else Color(1, 1, 1, 0.025), false, [UiStyle.S3, UiStyle.S2, UiStyle.S3, UiStyle.S2])
		if on:
			sb.border_width_left = 3
			sb.border_color = UiStyle.ACCENT
		(r.box as PanelContainer).add_theme_stylebox_override("panel", sb)
		var open := bool(c.open)
		(r.num as Label).add_theme_color_override("font_color", UiStyle.ACCENT if open else UiStyle.TEXT_3)
		(r.name as Label).add_theme_color_override("font_color", UiStyle.TEXT if open else UiStyle.TEXT_2)
		(r.lock as Control).visible = not open
		var names := PackedStringArray((c.tracks as Array).map(func(t: Dictionary) -> String: return "%s %s" % [t.number, t.name]))
		(r.tracks as Label).text = "  ·  ".join(names) if open else "Opens with %s: %s" % [String(c.missing), "  ·  ".join(names)]
		(r.box as Control).tooltip_text = String(c.blurb)
		(r.cab as Control).tooltip_text = _cabinet_text(c)
		(r.cab as Control).queue_redraw()
	for id: String in _level_btns:
		(_level_btns[id] as Button).theme_type_variation = "ChipOnButton" if id == picked_level else "ChipButton"
	var car := UiData.picked_car()
	var cname := String(UiData.car_info(car).name)
	var lname := Opponents.level_name(picked_level)
	var good := "#" + UiStyle.GOOD.to_html(false)
	var s := ""
	if picked.is_empty():
		s = ""
	elif not bool(picked.open):
		s = "[color=#a7a9ae][b]%s is locked[/b][/color]: it opens when %s %s open (a bronze on the track before each opens it)." % [String(picked.name), String(picked.missing),
			"is" if not String(picked.missing).contains(",") else "are"]
	elif not UiData.owns_car(car):
		s = "[color=#a7a9ae][b]The %s is locked[/b][/color]: buy it on the car picker, or pick a car you own (you race the car picked on the menu)." % cname
	else:
		var win := UiData.cup_pays(String(picked.id), picked_level, 1)
		s = "[color=#a7a9ae][b]%s[/b][/color] with the [b]%s[/b] against a %s field" % [String(picked.name), cname, lname]
		if int(win.money) > 0:
			s += ". A win pays [color=%s]+%s[/color] · +%s pts on top of each race's pay" % [good, UiFormat.money(int(win.money)), UiFormat.points(int(win.points))]
		else:
			s += ". Every place of this cup at this level is paid"
		var best := int((picked.trophies as Dictionary).get(picked_level, 0))
		if best > 0:
			s += "; your best here: %s" % Field.place_name(best)
		s += "."
	_info.text = s
	_start_btn.disabled = picked.is_empty() or not bool(picked.open) or not UiData.owns_car(car)
	_start_btn.tooltip_text = _info.get_parsed_text()


## A cup's cabinet as text (the tooltip): "Rookie: gold (1st), Pro: bronze (3rd)" or none yet.
func _cabinet_text(c: Dictionary) -> String:
	var tro: Dictionary = c.get("trophies", {})
	var parts: PackedStringArray = []
	for id: String in Opponents.ids():
		var p := int(tro.get(id, 0))
		if p > 0:
			var kind := Cups.trophy(p)
			parts.append("%s: %s" % [Opponents.level_name(id), ("%s (%s)" % [kind, Field.place_name(p)]) if kind != "" else Field.place_name(p)])
	return "%s trophies: %s" % [String(c.name), ", ".join(parts) if not parts.is_empty() else "none yet (finish in the top three)"]


func _render_standings() -> void:
	var v := _view
	title_label.text = String(v.name).to_upper()
	var done := int(v.done)
	_stand_sub.text = "%s field · %s · %s" % [String(v.level_name), String(v.car_name),
		("after race %d of %d: you are %s" % [done, int(v.count), Field.place_name(int(v.place))]) if done > 0 else "%d races, none run yet" % int(v.count)]
	var names: Array = (v.races as Array).map(func(r: Dictionary) -> String: return String(r.name))
	_table.show_rows(v.rows, names, UiStyle.FS_M)
	var nx: Dictionary = v.get("next", {})
	if nx.is_empty():
		_next_l.text = "The cup is over."
		_race_btn.disabled = true
	else:
		_next_l.text = "Race %d of %d: %s %s. You start %s on the grid%s." % [done + 1, int(v.count), String(nx.number), String(nx.name), Field.place_name(int(nx.slot)),
			", on the usual start spot (the race counts for medals and records as in Drive)" if done > 0 else ", behind the five AI"]
		_race_btn.disabled = false
		_race_btn.text = "RACE %d: %s" % [done + 1, String(nx.name).to_upper()]


## Start the picked cup (the game refuses a locked one, an unowned car).
func start() -> void:
	if _start_btn.disabled:
		UiSound.play("ui_error")
		return
	UiSound.play("ui_confirm")
	start_cup.emit(picked_cup, picked_level)


## Keys and gamepad while the screen is open (MainMenu forwards them).
func handle_keys(inp: Object) -> void:
	if inp.consume(["Escape", "Backspace", "KeyT", "PadB", "PadStart"]):
		UiSound.play("ui_back")
		close()
		return
	var dir: String = inp.nav_dir()
	if _stand.visible:
		if inp.consume(["Enter", "Space", "NumpadEnter", "PadA"]):
			if not _race_btn.disabled:
				UiSound.play("ui_confirm")
				next_race.emit()
		elif inp.consume(["KeyQ", "PadX"]):
			quit_cup.emit()
		return
	var ids := Cups.ids()
	var at := maxi(0, ids.find(picked_cup))
	var lv := Opponents.ids()
	var li := maxi(0, lv.find(picked_level))
	if inp.consume(["ArrowUp", "KeyW"]) or dir == "up":
		UiSound.play("ui_move")
		pick_cup(ids[(at + ids.size() - 1) % ids.size()])
	elif inp.consume(["ArrowDown", "KeyS"]) or dir == "down":
		UiSound.play("ui_move")
		pick_cup(ids[(at + 1) % ids.size()])
	elif inp.consume(["ArrowLeft", "KeyA"]) or dir == "left":
		UiSound.play("ui_move")
		pick_level(lv[(li + lv.size() - 1) % lv.size()])
	elif inp.consume(["ArrowRight", "KeyD"]) or dir == "right":
		UiSound.play("ui_move")
		pick_level(lv[(li + 1) % lv.size()])
	elif inp.consume(["Enter", "Space", "NumpadEnter", "PadA"]):
		start()
