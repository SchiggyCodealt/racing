class_name MainMenu
extends Control
## main_menu.gd
## ------------------------------------------------------------------
## The main menu, in the order you use it (web/src/ui/menu.js, v5 layout): 1 pick a track,
## 2 pick a car, 3 drive.
## - Track tiles: number, a minimap of the centre line (drawn from the built track, no image
##   files), name, difficulty, and the medal and best time you hold with the picked car.
## - One panel for the selected track: description, type and length, a bigger map when the
##   window is tall, your best time, best score and ghost with the picked car, the AI's best
##   from training and the four medal times.
## - The car picker (side view, name, top speed, mass, five stat bars, the picked car's
##   description line). The pick is the "car" setting, which Drive and Race the AI ghost use.
## - Drive, the best-run ghost option, the AI block (status, Load / Save network, Race the AI
##   ghost, Watch the AI, Train the AI); the Controls screen and the Settings screen.
## Every bit of game data comes through UiData; the buttons only emit signals.
##
## Keyboard: arrows / WASD / 1-9, 0, -, = (tracks 1-12), C / Shift+C (next / previous car),
## Enter or Space drives, H or ? opens Controls, O opens Settings.
## Gamepad: a highlight moved with the d-pad / stick over the track tiles (moving onto one
## selects it), the car cards under them (moving onto one picks it) and the buttons; A drives
## or presses, B goes back to the tracks, LB / RB pick the car, View opens Controls.
## The host calls handle_keys(input) once per frame (or sets `input` and the menu polls it);
## `input` is a MenuInput or anything with its interface.

signal drive
signal race_ghost
signal watch_ai
signal train_ai
signal load_network
signal save_network
signal track_selected(index: int)
signal car_selected(id: String)

const W := preload("res://ui/widgets.gd")
const TrackTile := preload("res://ui/track_tile.gd")
const CarCard := preload("res://ui/car_card.gd")
const TrackMapView := preload("res://ui/track_map_view.gd")
const KeyCap := preload("res://ui/key_cap.gd")
const MedalDot := preload("res://ui/medal_dot.gd")
const DiffBars := preload("res://ui/diff_bars.gd")
const Dialog := preload("res://ui/dialog_screen.gd")
const CheckToggle := preload("res://ui/check_toggle.gd")
const PadRing := preload("res://ui/pad_ring.gd")
const PadNav := preload("res://ui/pad_nav.gd")

## Number-row keys that pick track 1-12: 1-9, then 0, - and = (numpad 0-9, -, +).
const TRACK_KEYS := [
	["Digit1", "Numpad1"], ["Digit2", "Numpad2"], ["Digit3", "Numpad3"], ["Digit4", "Numpad4"],
	["Digit5", "Numpad5"], ["Digit6", "Numpad6"], ["Digit7", "Numpad7"], ["Digit8", "Numpad8"],
	["Digit9", "Numpad9"], ["Digit0", "Numpad0"], ["Minus", "NumpadSubtract"], ["Equal", "NumpadAdd"],
]
## The one hint line beside the title: [keys, what] for the keyboard, or the gamepad while it is the last input used.
const HINTS := {
	"keys": [["Arrows, 1–9 0 - =", "track"], ["C", "car"], ["Enter", "drive"]],
	"pad": [["D-pad", "move"], ["LB RB", "car"], ["A", "drive"], ["View", "controls"]],
}

## The menu's input (MenuInput or the same interface); polled in _process while the menu shows.
var input: Object = null
var selected_track := 0
var controls: ControlsScreen
var settings: SettingsScreen

# layout state
var map_h := 56.0
var compact := true
var columns := 6

# nodes
var _scroll: ScrollContainer
var _frame: Control
var _main: BoxContainer
var _left: VBoxContainer
var _side: VBoxContainer
var _head: HBoxContainer
var _hint: HBoxContainer
var _hint_holder: Control
var _hint_mode := ""
var _grid: GridContainer
var _tiles: Array = []
var _cars_grid: GridContainer
var _cards: Array = []
var _car_desc_name: Label
var _car_desc: Label
var _detail: PanelContainer
var _detail_box: VBoxContainer
var _td_num: Label
var _td_name: Label
var _td_diff: Control
var _td_meta: Label
var _td_desc: Label
var _td_map: Control
var _td_car_name: Label
var _td_car_gap: Control
var _stats: Array = []       # [{box, label, medal, value}]
var _medals_box: VBoxContainer
var _medal_cells: Array = []  # [{dot, name, time}]
var _gaps := {}              # name -> spacer Control (sizes change with the window)
var _drive_btn: Button
var _ghost_check: Control
var _ai_status: RichTextLabel
var _ai_status_text := ""
var _load_btn: Button
var _save_btn: Button
var _ghost_btn: Button
var _watch_btn: Button
var _train_btn: Button
var _controls_btn: Button
var _settings_btn: Button
var _ring: Control
var _pad_at: Control = null   # the button or car the pad highlight is on (null: the selected track tile)
var _maps: Array = []


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiStyle.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var scrim := ColorRect.new()
	scrim.color = UiStyle.SCRIM_MENU
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_scroll)
	_frame = Control.new()
	_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_frame)
	_build()
	_ring = PadRing.new()
	add_child(_ring)
	controls = ControlsScreen.new()
	add_child(controls)
	settings = SettingsScreen.new()
	add_child(settings)
	resized.connect(_layout)
	_main.minimum_size_changed.connect(_place)


func _ready() -> void:
	_update_hint(false)
	refresh()
	_layout()


# ================================================================= building

func _build() -> void:
	_main = BoxContainer.new()
	_main.add_theme_constant_override("separation", UiStyle.S5)
	_main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(_main)
	_left = UiStyle.vbox(0)
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main.add_child(_left)
	_side = UiStyle.vbox(0)
	_main.add_child(_side)
	_build_head()
	_gaps.head = _spacer(_left)
	_build_tracks()
	_gaps.tracks = _spacer(_left)
	_build_cars()
	var fill := Control.new() # (the car row takes the spare height: the cars stay at the top of it)
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left.add_child(fill)
	_build_detail()
	_gaps.side = _spacer(_side)
	_build_go()


func _spacer(box: Control, h: float = 0.0) -> Control:
	var g := UiStyle.gap(0, h)
	box.add_child(g)
	return g


func _build_head() -> void:
	_head = UiStyle.hbox(UiStyle.S5)
	_left.add_child(_head)
	var mark := UiStyle.hbox(UiStyle.S3)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(12, 28)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.draw.connect(func() -> void: UiStyle.draw_skewed_rect(bar, Rect2(Vector2.ZERO, bar.size), UiStyle.ACCENT))
	mark.add_child(bar)
	mark.add_child(UiStyle.label("Track Rush", "display_bold", UiStyle.FS_XL, UiStyle.TEXT, 0.04, true, false, false, UiStyle.FS_XL))
	_head.add_child(mark)
	# the hint line takes the room the buttons leave; items it has no room for go, last first
	# (the web hides it under 760 px; the Godot header also has the Settings button)
	_hint_holder = Control.new()
	_hint_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint_holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hint_holder.custom_minimum_size.y = 18
	_hint_holder.clip_contents = true
	_hint_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_holder.resized.connect(_fit_hint)
	_hint = UiStyle.hbox(UiStyle.S4, BoxContainer.ALIGNMENT_END)
	_hint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hint_holder.add_child(_hint)
	_head.add_child(_hint_holder)
	_settings_btn = Dialog.button_with_cap("Settings", "O")
	_settings_btn.tooltip_text = "Graphics, ghost, fullscreen and vsync"
	_settings_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_settings_btn.pressed.connect(func() -> void: show_settings(true))
	_head.add_child(_settings_btn)
	_controls_btn = Dialog.button_with_cap("Controls", "H")
	_controls_btn.tooltip_text = "Every keyboard and gamepad control"
	_controls_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_controls_btn.pressed.connect(func() -> void: show_controls(true))
	_head.add_child(_controls_btn)


## A step heading with its number: "1 Track", "2 Car", "3 Drive" (style.css .step).
func _step(n: String, text: String) -> Control:
	var row := UiStyle.hbox(UiStyle.S3)
	var badge := Control.new()
	badge.custom_minimum_size = Vector2(24, 22)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.draw.connect(func() -> void:
		UiStyle.draw_skewed_rect(badge, Rect2(Vector2.ZERO, badge.size), UiStyle.ACCENT)
		var f := UiStyle.face("display_bold")
		var w := f.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.FS_M).x
		badge.draw_string(f, Vector2(roundf((24 - w) * 0.5), W.baseline(f, UiStyle.FS_M, 3, UiStyle.FS_M)), n,
			HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.FS_M, UiStyle.ACCENT_INK))
	row.add_child(badge)
	var l := UiStyle.label(text, "display_bold", UiStyle.FS_M, UiStyle.TEXT, 0.1, true, false, false, UiStyle.FS_M)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	var m := UiStyle.margin([0, 0, 0, UiStyle.S3])
	m.add_child(row)
	return m


func _build_tracks() -> void:
	_left.add_child(_step("1", "Track"))
	_grid = GridContainer.new()
	_grid.columns = 6
	_grid.add_theme_constant_override("h_separation", UiStyle.S2)
	_grid.add_theme_constant_override("v_separation", UiStyle.S2)
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left.add_child(_grid)
	for i in UiData.track_count():
		var tile: Control = TrackTile.new()
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var m := UiData.track_map(i)
		_maps.append(m)
		tile.setup(i, UiData.track_info(i), m)
		tile.picked.connect(select.bind(i))
		tile.activated.connect(func() -> void: drive.emit())
		_grid.add_child(tile)
		_tiles.append(tile)


func _build_cars() -> void:
	_left.add_child(_step("2", "Car"))
	_cars_grid = GridContainer.new()
	_cars_grid.columns = 2
	_cars_grid.add_theme_constant_override("h_separation", UiStyle.S2)
	_cars_grid.add_theme_constant_override("v_separation", UiStyle.S2)
	_cars_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left.add_child(_cars_grid)
	for id in UiData.car_ids():
		var card: Control = CarCard.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.setup(id, UiData.car_info(id), UiData.car_profile(id))
		card.picked.connect(select_car.bind(id))
		card.activated.connect(func() -> void: drive.emit())
		_cars_grid.add_child(card)
		_cards.append(card)
	var desc := UiStyle.hbox(UiStyle.S1)
	_car_desc_name = UiStyle.label("", "text", UiStyle.FS_S, UiStyle.TEXT, 0.0, false, false, false, 18)
	_car_desc = UiStyle.label("", "text", UiStyle.FS_S, UiStyle.TEXT_2, 0.0, false, false, false, 18)
	_car_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_car_desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_car_desc.custom_minimum_size.x = 1
	_car_desc.mouse_filter = Control.MOUSE_FILTER_PASS
	desc.add_child(_car_desc_name)
	desc.add_child(_car_desc)
	var m := UiStyle.margin([0, UiStyle.S3, 0, 0])
	m.add_child(desc)
	_left.add_child(m)


func _build_detail() -> void:
	_detail = UiStyle.panel(UiStyle.box(UiStyle.PANEL, false, [UiStyle.S5, UiStyle.S4, UiStyle.S5, UiStyle.S4]))
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_side.add_child(_detail)
	_detail_box = UiStyle.vbox(0)
	_detail.add_child(_detail_box)
	# number and name
	var head := UiStyle.hbox(UiStyle.S3)
	_td_num = UiStyle.label("", "display_bold", UiStyle.FS_L, UiStyle.ACCENT, 0.0, false, true, false, UiStyle.FS_L)
	_td_num.size_flags_vertical = Control.SIZE_SHRINK_END
	var num_box := UiStyle.margin([0, 0, 0, 2]) # (the number's baseline on the name's)
	num_box.size_flags_vertical = Control.SIZE_SHRINK_END
	num_box.add_child(_td_num)
	head.add_child(num_box)
	_td_name = UiStyle.label("", "display_bold", UiStyle.FS_XL, UiStyle.TEXT, 0.02, true, false, false, UiStyle.FS_XL)
	_td_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_td_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_td_name.custom_minimum_size.x = 1
	head.add_child(_td_name)
	_detail_box.add_child(head)
	# difficulty, type, laps, length
	_detail_box.add_child(UiStyle.gap(0, UiStyle.S3))
	var meta := UiStyle.hbox(UiStyle.S3)
	_td_diff = DiffBars.new()
	meta.add_child(_td_diff)
	_td_meta = UiStyle.label("", "text", UiStyle.FS_S, UiStyle.TEXT_2, 0.0, false, false, false, 18)
	meta.add_child(_td_meta)
	_detail_box.add_child(meta)
	# description
	_detail_box.add_child(UiStyle.gap(0, UiStyle.S3))
	_td_desc = UiStyle.label("", "text", UiStyle.FS_M, UiStyle.TEXT_2, 0.0, false, false, false, 22)
	_td_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_td_desc.custom_minimum_size.x = 1
	_detail_box.add_child(_td_desc)
	# the bigger map: the panel's spare height (hidden while that is 64 px or less)
	_td_map = TrackMapView.new()
	_td_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_td_map.line_width = 2.5
	_td_map.top_gap = UiStyle.S5
	_td_map.hide_below = 64.0
	_detail_box.add_child(_td_map)
	# "With the Racer" and a rule
	_td_car_gap = _spacer(_detail_box, UiStyle.S3)
	var car := UiStyle.hbox(UiStyle.S2)
	car.add_child(UiStyle.label("With the", "text", UiStyle.FS_S, UiStyle.TEXT_3, 0.0, false, false, false, 18))
	_td_car_name = UiStyle.label("", "text_semi", UiStyle.FS_S, UiStyle.TEXT_2, 0.0, false, false, false, 18)
	car.add_child(_td_car_name)
	var rule := ColorRect.new()
	rule.color = UiStyle.LINE
	rule.custom_minimum_size = Vector2(0, 1)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	car.add_child(rule)
	_detail_box.add_child(car)
	# your best (with its medal), best score, ghost, the AI's best
	_detail_box.add_child(UiStyle.gap(0, UiStyle.S3))
	var stats := GridContainer.new()
	stats.columns = 4
	stats.add_theme_constant_override("h_separation", UiStyle.S3)
	stats.add_theme_constant_override("v_separation", UiStyle.S3)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_box.add_child(stats)
	for k in 4:
		var cell := UiStyle.vbox(UiStyle.S1)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.custom_minimum_size.x = 1
		cell.mouse_filter = Control.MOUSE_FILTER_PASS
		var dt := UiStyle.hbox(6)
		var lab := UiStyle.label("", "text", UiStyle.FS_S, UiStyle.TEXT_3, 0.0, false, false, false, 18)
		dt.add_child(lab)
		var dot: Control = MedalDot.make("", 12 * 0.78)
		dt.add_child(dot)
		cell.add_child(dt)
		var value := UiStyle.label("", "display", UiStyle.FS_L, UiStyle.TEXT, 0.0, false, true, false, 22)
		cell.add_child(value)
		stats.add_child(cell)
		_stats.append({"box": cell, "label": lab, "medal": dot, "value": value})
	# the four medal times
	_medals_box = UiStyle.vbox(UiStyle.S1)
	var mm := UiStyle.margin([0, UiStyle.S4, 0, 0])
	mm.add_child(_medals_box)
	_detail_box.add_child(mm)
	_medals_box.add_child(UiStyle.label("Medal times", "text", UiStyle.FS_S, UiStyle.TEXT_3, 0.0, false, false, false, 18))
	var row := GridContainer.new()
	row.columns = 4
	row.add_theme_constant_override("h_separation", UiStyle.S3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_medals_box.add_child(row)
	for medal in UiStyle.MEDAL_ORDER:
		var cell := UiStyle.vbox(UiStyle.S1)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.custom_minimum_size.x = 1
		cell.mouse_filter = Control.MOUSE_FILTER_PASS
		var em := UiStyle.hbox(5)
		var dot: Control = MedalDot.make(medal, 13 * 0.78)
		em.add_child(dot)
		var nm := UiStyle.label(UiStyle.MEDAL_NAMES[medal], "text", UiStyle.FS_S, UiStyle.TEXT_3, 0.0, false, false, false, 18)
		em.add_child(nm)
		cell.add_child(em)
		var t := UiStyle.label("", "display", UiStyle.FS_M, UiStyle.TEXT_2, 0.0, false, true, false, 18)
		cell.add_child(t)
		row.add_child(cell)
		_medal_cells.append({"cell": cell, "dot": dot, "time": t})


func _build_go() -> void:
	_side.add_child(_step("3", "Drive"))
	var actions := UiStyle.hbox(UiStyle.S5)
	_drive_btn = UiStyle.button("Drive", "PrimaryButton", 46)
	_drive_btn.text = "DRIVE"
	_drive_btn.custom_minimum_size.x = 190
	_drive_btn.pressed.connect(func() -> void: drive.emit())
	actions.add_child(_drive_btn)
	_ghost_check = CheckToggle.new()
	_ghost_check.text = "Race my best-run ghost"
	_ghost_check.tooltip_text = "In Drive, a see-through copy of your best run on the track with the car you drive races with you (G switches it during a race)"
	_ghost_check.toggled.connect(func(on: bool) -> void: UiData.set_setting("ghost", on))
	actions.add_child(_ghost_check)
	_side.add_child(actions)
	_gaps.ai = _spacer(_side, UiStyle.S3)
	# the AI driver
	var head := UiStyle.hbox(UiStyle.S1)
	var cap := UiStyle.label("AI driver", "display_bold", UiStyle.FS_S, UiStyle.TEXT_2, 0.1, true, false, false, UiStyle.FS_S)
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(cap)
	_load_btn = UiStyle.button("Load network…", "SmallQuietButton", 30)
	_load_btn.pressed.connect(func() -> void: load_network.emit())
	head.add_child(_load_btn)
	_save_btn = UiStyle.button("Save network…", "SmallQuietButton", 30)
	_save_btn.pressed.connect(func() -> void: save_network.emit())
	head.add_child(_save_btn)
	_side.add_child(head)
	_ai_status = RichTextLabel.new()
	_ai_status.bbcode_enabled = true
	_ai_status.fit_content = true
	_ai_status.scroll_active = false
	_ai_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ai_status.custom_minimum_size.x = 1
	_ai_status.add_theme_font_override("normal_font", UiStyle.font("text", UiStyle.FS_S, 0, false, 18))
	_ai_status.add_theme_font_override("bold_font", UiStyle.font("text_semi", UiStyle.FS_S, 0, false, 18))
	_ai_status.add_theme_font_size_override("normal_font_size", UiStyle.FS_S)
	_ai_status.add_theme_font_size_override("bold_font_size", UiStyle.FS_S)
	_ai_status.add_theme_color_override("default_color", UiStyle.TEXT_3)
	_ai_status.add_theme_constant_override("line_separation", 0)
	_ai_status.mouse_filter = Control.MOUSE_FILTER_PASS
	_ai_status.resized.connect(_clamp_status)
	var sm := UiStyle.margin([0, UiStyle.S1, 0, UiStyle.S2])
	sm.add_child(_ai_status)
	_gaps.status = sm
	_side.add_child(sm)
	var buttons := UiStyle.vbox(UiStyle.S2)
	var pair := UiStyle.hbox(UiStyle.S3)
	_ghost_btn = UiStyle.button("Race the AI ghost")
	_watch_btn = UiStyle.button("Watch the AI")
	for b in [_ghost_btn, _watch_btn]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_stretch_ratio = 1.0
		b.custom_minimum_size.x = 1
		b.clip_text = true
		pair.add_child(b)
	_ghost_btn.pressed.connect(func() -> void: race_ghost.emit())
	_watch_btn.pressed.connect(func() -> void: watch_ai.emit())
	buttons.add_child(pair)
	_train_btn = UiStyle.button("Train the AI")
	_train_btn.pressed.connect(func() -> void: train_ai.emit())
	buttons.add_child(_train_btn)
	_side.add_child(buttons)


# ================================================================= showing the data

## Redraw everything from UiData (records, scores, the picked car, the AI status).
func refresh() -> void:
	var car := UiData.picked_car()
	for i in _tiles.size():
		var id := UiData.track_id(i)
		var rec: Variant = UiData.record(id, car)
		var t: Variant = rec.time if rec != null else null
		_tiles[i].selected = i == selected_track
		_tiles[i].set_record(UiFormat.time(t) if t != null else "", UiData.medal_for(UiData.medal_times(id, car), t))
	_render_detail()
	_render_cars()
	# the AI status: two lines at most (the whole text is in the tooltip)
	var st := UiData.ai_status()
	if st.ready:
		var s := "[color=#a7a9ae][b]Ready[/b][/color]: generation %s, fitness %d, network %s" % [
			str(st.get("generation", "?")), roundi(float(st.get("fitness", 0))), "-".join(PackedStringArray(st.get("sizes", []).map(func(x: Variant) -> String: return str(int(x)))))]
		var on: Array = st.get("trained_on", [])
		if not on.is_empty():
			s += ", trained on " + ", ".join(PackedStringArray(on.map(_track_name)))
		if str(st.get("walls", "")) != "":
			s += " (walls: %s)" % st.walls
		_ai_status_text = s
	else:
		_ai_status_text = "[color=#a7a9ae][b]None yet[/b][/color]: train one or load a saved network file."
	_ai_status.tooltip_text = _strip_bbcode(_ai_status_text)
	_clamp_status()
	_ghost_check.checked = bool(UiData.get_setting("ghost"))
	_ghost_btn.disabled = not st.ready
	_watch_btn.disabled = not st.ready
	_save_btn.disabled = not st.ready


func _track_name(id: Variant) -> String:
	for i in UiData.track_count():
		if UiData.track_id(i) == str(id):
			return UiData.track_info(i).name
	return str(id)


static func _strip_bbcode(s: String) -> String:
	var re := RegEx.create_from_string("\\[[^\\]]*\\]")
	return re.sub(s, "", true)


## Two lines at most, cut at a word with an ellipsis (CSS line-clamp: 2).
func _clamp_status() -> void:
	if _ai_status == null or _ai_status.size.x < 10:
		_ai_status.text = _ai_status_text
		return
	var full := _ai_status_text
	_ai_status.text = full
	var font := UiStyle.font("text", UiStyle.FS_S)
	var plain := _strip_bbcode(full)
	var w := _ai_status.size.x
	# measure with a TextParagraph (the RichTextLabel lays out a frame later)
	var para := TextParagraph.new()
	para.width = w
	para.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	para.add_string(plain, font, UiStyle.FS_S)
	if para.get_line_count() <= 2:
		return
	var words := full.split(" ")
	while words.size() > 1:
		words.resize(words.size() - 1)
		var cut := " ".join(words).trim_suffix(",") + "…"
		para.clear()
		para.width = w
		para.add_string(_strip_bbcode(cut), font, UiStyle.FS_S)
		if para.get_line_count() <= 2:
			_ai_status.text = cut
			return


func _render_cars() -> void:
	var car := UiData.picked_car()
	for c in _cards:
		c.selected = c.car_id == car
	var info := UiData.car_info(car)
	_car_desc_name.text = info.name
	_car_desc.text = info.description
	_car_desc.tooltip_text = "%s: %s" % [info.name, info.description]


## The panel of the selected track, with your records and its medal times with the picked car.
func _render_detail() -> void:
	var i := selected_track
	var t := UiData.track_info(i)
	var car := UiData.picked_car()
	var cinfo := UiData.car_info(car)
	var rec: Variant = UiData.record(t.id, car)
	var best: Variant = rec.time if rec != null else null
	var medals := UiData.medal_times(t.id, car)
	var medal := UiData.medal_for(medals, best)
	var score := UiData.best_score(t.id, car)
	var ai := UiData.ai_best(i)
	_td_num.text = UiFormat.track_number(i)
	_td_name.text = t.name
	_td_diff.level = t.difficulty
	_td_meta.text = ("Circuit · %d laps · %s km a lap" % [t.laps, UiFormat.km(t.length)]) if t.closed \
		else ("Sprint · %s km" % UiFormat.km(t.sprint_length))
	_td_desc.text = t.description
	_td_map.map = _maps[i]
	_td_car_name.text = cinfo.name
	var cells := [
		["Your best", UiFormat.time(best) if best != null else "", best != null,
			"Your best time on %s with the %s%s" % [t.name, cinfo.name, " (%s medal)" % UiStyle.MEDAL_NAMES[medal] if medal != "" else ""]],
		["Best score", UiFormat.points(score) if score >= 0 else "", score >= 0,
			"Your best score on %s with the %s. Points for clean checkpoints (a combo up to x%d), drifts, jumps and close calls; walls and respawns cost points. Points refill the nitro." % [t.name, cinfo.name, UiData.COMBO_MAX]],
		["Ghost", "Saved", UiData.has_ghost(t.id, car),
			"Your best run with the %s is saved as a ghost" % cinfo.name if UiData.has_ghost(t.id, car) else "No ghost yet: set a best time"],
		["AI best lap" if t.closed else "AI best", UiFormat.time(ai) if ai > 0 else "", ai > 0,
			"The AI's best %s here, from training (the AI always drives the Racer)" % ("lap" if t.closed else "time")],
	]
	for k in 4:
		var s: Dictionary = _stats[k]
		s.label.text = cells[k][0]
		s.value.text = cells[k][1] if cells[k][2] else "—"
		s.value.add_theme_color_override("font_color", UiStyle.TEXT if cells[k][2] else UiStyle.TEXT_3)
		s.box.tooltip_text = cells[k][3]
		s.medal.visible = k == 0 and medal != ""
		s.medal.medal = medal
	# medal times: the ones the best time has won are lit
	_medals_box.visible = not medals.is_empty()
	if not medals.is_empty():
		var from := UiStyle.MEDAL_ORDER.find(medal) if medal != "" else UiStyle.MEDAL_ORDER.size()
		for k in UiStyle.MEDAL_ORDER.size():
			var m: String = UiStyle.MEDAL_ORDER[k]
			var won := k >= from
			var c: Dictionary = _medal_cells[k]
			c.dot.off = not won
			c.time.text = UiFormat.time(medals[m])
			c.time.add_theme_color_override("font_color", UiStyle.TEXT if won else UiStyle.TEXT_2)
			c.cell.tooltip_text = "%s medal%s" % [UiStyle.MEDAL_NAMES[m], ": won" if won else ""]


# ================================================================= picking

## Select track `i` (the host swaps the 3D track on track_selected).
func select(i: int) -> void:
	selected_track = i
	track_selected.emit(i)
	refresh()
	_scroll.ensure_control_visible(_tiles[i])


## Pick car `id` (remembered: Drive and Race the AI ghost use it); the tiles and the panel follow it.
func select_car(id: String) -> void:
	UiData.set_setting("car", id)
	car_selected.emit(id)
	refresh()


## The next (step 1) or previous (step -1) car.
func cycle_car(step: int) -> void:
	var ids := UiData.car_ids()
	var i := ids.find(UiData.picked_car())
	select_car(ids[(i + step + ids.size()) % ids.size()])


func car_card() -> Control:
	for c in _cards:
		if c.car_id == UiData.picked_car():
			return c
	return null


func show_menu(on: bool) -> void:
	visible = on
	if on:
		refresh()
	else:
		_ring.set_target(null)
		show_controls(false)
		show_settings(false)


func show_controls(on: bool) -> void:
	if on:
		_ring.set_target(null)
		controls.open()
	else:
		controls.close()


func show_settings(on: bool) -> void:
	if on:
		_ring.set_target(null)
		settings.open()
	else:
		settings.close()


var controls_open: bool:
	get:
		return controls.visible


# ================================================================= keys and the gamepad

func _process(_dt: float) -> void:
	if input != null and is_visible_in_tree():
		handle_keys(input)


## Keys and gamepad on the menu (menu.js handleKeys); call once per frame.
func handle_keys(inp: Object) -> void:
	_update_hint(bool(inp.get("pad_active")))
	if controls.visible:
		# the Controls screen: Esc, H, ?, Backspace, Enter or Space close it (pad: B, A, View or Menu); nothing else
		if inp.consume(["Escape", "KeyH", "Slash", "Backspace", "Enter", "Space", "PadB", "PadA", "PadBack", "PadStart"]):
			show_controls(false)
		inp.clear_pressed()
		return
	if settings.visible:
		settings.handle_keys(inp)
		inp.clear_pressed()
		return
	if inp.consume(["KeyH", "Slash", "PadBack"]):
		show_controls(true)
		inp.clear_pressed()
		return
	if inp.consume(["KeyO"]):
		show_settings(true)
		inp.clear_pressed()
		return
	var n := _tiles.size()
	if inp.consume(["ArrowRight", "ArrowDown", "KeyD", "KeyS"]):
		select((selected_track + 1) % n)
	if inp.consume(["ArrowLeft", "ArrowUp", "KeyA", "KeyW"]):
		select((selected_track + n - 1) % n)
	for k in mini(n, TRACK_KEYS.size()):
		if inp.consume(TRACK_KEYS[k]):
			select(k)
	if inp.consume(["KeyC"]):
		cycle_car(-1 if inp.consume(["Shift+KeyC"]) else 1)
	if inp.consume(["Enter", "Space", "NumpadEnter"]):
		drive.emit()
	else:
		handle_pad(inp)
	inp.clear_pressed()


## The hint line beside the title names the gamepad's buttons while the pad is the last input used.
func _update_hint(pad: bool) -> void:
	var h := "pad" if pad else "keys"
	if h == _hint_mode:
		return
	_hint_mode = h
	for c in _hint.get_children():
		_hint.remove_child(c)
		c.queue_free()
	for pair in HINTS[h]:
		var p := UiStyle.hbox(3)
		p.add_child(UiStyle.label(pair[0], "text_semi", UiStyle.FS_S, UiStyle.TEXT_2))
		p.add_child(UiStyle.label(pair[1], "text", UiStyle.FS_S, UiStyle.TEXT_3))
		_hint.add_child(p)
	_fit_hint()


## Show as many hint items as the header has room for (from the first).
func _fit_hint() -> void:
	var items := _hint.get_children()
	for c in items:
		c.visible = true
	var k := items.size()
	while k > 0 and _hint.get_combined_minimum_size().x > _hint_holder.size.x + 0.5:
		k -= 1
		items[k].visible = false


## The controls the pad highlight can go to (shown and enabled), in the web's order.
func _pad_controls() -> Array:
	var out: Array = []
	for c in [_controls_btn, _settings_btn, _drive_btn, _ghost_btn, _watch_btn, _train_btn, _ghost_check, _save_btn]:
		if c.is_visible_in_tree() and not (c is BaseButton and c.disabled):
			out.append(c)
	return out


func _pad_cars() -> Array:
	return _cards.filter(func(c: Control) -> bool: return c.is_visible_in_tree())


## Gamepad on the menu (menu.js handlePad). The highlight is on the selected track tile
## (_pad_at null), a car card or a button. On the tiles the d-pad moves like the arrow keys
## (left / right along the tiles, wrapping; up / down a row; moving onto a tile selects it);
## down from the bottom row goes to the cars, up from the top row to the Controls button. On
## the cars, moving onto one picks it; up from the top row goes back to the tracks, right from
## the last car or down from the bottom row to Drive. Between the buttons it moves to the
## nearest one (left / right only along a row); left from the first button of a row goes back
## to the picked car or the tracks, whichever is beside. A drives (on a tile) or presses the
## button; on a car it goes back to the tracks. B goes back to the tracks, LB / RB pick the
## previous / next car from anywhere. The highlight shows while the pad is the last input
## used; a press while it is hidden only shows it. "Load network…" is left out (its file
## dialog needs a mouse or keyboard anyway).
func handle_pad(inp: Object) -> void:
	var dir: String = inp.nav_dir()
	var a: bool = inp.consume(["PadA"])
	var b: bool = inp.consume(["PadB"])
	var ctrls := _pad_controls()
	var cars := _pad_cars()
	var shown := _ring.target != null
	var at: Control = _pad_at if (ctrls.has(_pad_at) or cars.has(_pad_at)) else null
	var on_car := cars.has(at)
	var step := (1 if inp.consume(["PadRB"]) else 0) - (1 if inp.consume(["PadLB"]) else 0)
	if step != 0:
		cycle_car(step)
		if on_car:
			at = car_card()
	var drive_btn: Control = _drive_btn if ctrls.has(_drive_btn) else null
	if dir != "" and shown:
		var card: Control = _tiles[selected_track]
		if on_car:
			var next := PadNav.nearest_control(at, dir, cars)
			if next != null:
				select_car(next.car_id)
				at = next
			elif dir == "up":
				at = null
			elif dir == "right" or dir == "down":
				at = drive_btn if drive_btn != null else at
		elif (at == _controls_btn or at == _settings_btn) and dir == "down":
			at = null # under the header buttons: the track tiles
		elif at != null:
			var next := PadNav.nearest_control(at, dir, ctrls)
			if next != null and (dir == "up" or dir == "down" or PadNav.same_row(at.get_global_rect(), next.get_global_rect())):
				at = next # (left / right: only along a row)
			elif dir == "left":
				var back := PadNav.nearest_control(at, "left", [car_card(), card].filter(func(c: Variant) -> bool: return c != null))
				at = back if back != null and back != card else null
		elif dir == "left" or dir == "right":
			var n := _tiles.size()
			select((selected_track + (1 if dir == "right" else n - 1)) % n)
		else:
			var next := PadNav.nearest_control(card, dir, _tiles)
			if next != null:
				select(_tiles.find(next))
			elif dir == "down":
				at = car_card() # below the last row: the cars
			else:
				at = _controls_btn if ctrls.has(_controls_btn) else null # above the top row: Controls
	elif a and shown:
		if on_car:
			at = null # the car is picked: back to the tracks
		elif at != null:
			_press(at)
			return
		else:
			drive.emit()
			return
	if b:
		at = null
	_pad_at = at
	_mark(at if bool(inp.get("pad_active")) else null, bool(inp.get("pad_active")))


## Draw the highlight on `at` (null: the selected tile while the pad is in use; nothing otherwise).
func _mark(at: Control, pad: bool) -> void:
	if not pad:
		_ring.set_target(null)
	elif at == null:
		_ring.set_target(_tiles[selected_track])
		_scroll.ensure_control_visible(_tiles[selected_track])
	elif at == _ghost_check:
		_ring.set_target(at, true, 3.0, _ghost_check.box_rect()) # (the check box itself, not its label)
	elif at is BaseButton:
		_ring.set_target(at, true, 3.0)
	else:
		_ring.set_target(at, false, 3.0)
	if at != null:
		_scroll.ensure_control_visible(at)


## Press a highlighted control (the pad's A): a button is clicked, the check box toggled.
func _press(c: Control) -> void:
	if c is BaseButton:
		(c as BaseButton).pressed.emit()
	elif c.has_method("press"):
		c.press()


## The control the pad highlight is on (null: the selected track tile), for tests.
func pad_target() -> Control:
	return _ring.target


# ================================================================= layout

## Apply the window-size rules of style.css (in interface pixels: UiRoot lays the interface
## out at the window's size divided by the interface scale, like CSS pixels):
##   six tiles a row from 1200 px wide, four below; map 56 px in short windows (≤ 800 px),
##   64 px, 80 px from 860 px tall, 104 px from 1600 x 940 (with roomier tiles); the side
##   column 30 % of the width (360-440 px); denser spacing when the window is short.
func _layout() -> void:
	var w := size.x
	var h := size.y
	if w <= 0 or h <= 0:
		return
	compact = h <= 800
	var big := w >= 1600 and h >= 940
	var one_col := w < 1000
	columns = 6 if w >= 1200 else (4 if w >= 760 else 3)
	map_h = 64.0
	if w >= 1200 and h >= 860:
		map_h = 80.0
	if big:
		map_h = 104.0
	if w < 1200 or compact:
		map_h = 56.0
	if w < 1200 and w >= 1000 and compact:
		map_h = 44.0
	_grid.columns = columns
	var tile_px := float(UiStyle.S3)
	if big:
		tile_px = UiStyle.S4
	elif w < 1280 and w >= 1200:
		tile_px = UiStyle.S2
	for t in _tiles:
		t.set_metrics(map_h, tile_px, UiStyle.S4 if big else UiStyle.S3, UiStyle.FS_L if big else UiStyle.FS_M)
	var side_w := clampf(0.3 * w, 360.0, 440.0) if w >= 1200 else 340.0
	_main.vertical = one_col
	_side.custom_minimum_size.x = 0.0 if one_col else side_w
	_gaps.head.custom_minimum_size.y = UiStyle.S4 if compact else UiStyle.S5
	_gaps.tracks.custom_minimum_size.y = UiStyle.S4 if compact else UiStyle.S5
	_gaps.side.custom_minimum_size.y = UiStyle.S3 if compact else UiStyle.S5
	_gaps.ai.custom_minimum_size.y = UiStyle.S3 if compact else UiStyle.S5
	_gaps.status.add_theme_constant_override("margin_bottom", UiStyle.S2 if compact else UiStyle.S3)
	_td_car_gap.custom_minimum_size.y = UiStyle.S3 if compact else UiStyle.S5
	_detail.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, false,
		[UiStyle.S5, UiStyle.S4 if compact else UiStyle.S5, UiStyle.S5, UiStyle.S4 if compact else UiStyle.S5]))
	_td_desc.custom_minimum_size.y = 0.0 if compact else ceilf(UiStyle.FS_M * 1.45 * 3)
	_drive_btn.custom_minimum_size.y = 46.0 if compact else 52.0
	# the car cards stack (bars under the side view and name) when the picker is 500-760 px wide
	# (style.css @container car-picker)
	var pad_x := float(UiStyle.S6) if w >= 1000 else float(UiStyle.S4)
	var mw := minf(1480.0, w - 2 * pad_x)
	var picker_w := mw if one_col else mw - side_w - _main.get_theme_constant("separation")
	for c in _cards:
		c.stacked = picker_w >= 500.0 and picker_w <= 760.0
	# the ghost check box wraps its label beside the Drive button when the side column is narrow
	var row_sep := float(_ghost_check.get_parent().get_theme_constant("separation"))
	var room := side_w - _drive_btn.custom_minimum_size.x - row_sep - 18 - UiStyle.S2
	_ghost_check.wrap_width = room if (not one_col and room < UiStyle.text_width(_ghost_check.text, "text", UiStyle.FS_S)) else 0.0
	# the AI's two buttons side by side in the 340 px side column: tighter padding
	for b in [_ghost_btn, _watch_btn]:
		b.theme_type_variation = "TightButton" if (side_w < 360.0 and not one_col) else ""
	# the stats two a row in the narrower side column (1000-1199 px)
	_stats[0].box.get_parent().columns = 2 if (w < 1200 and w >= 1000) else 4
	_place()


## Centre the menu (at most 1480 wide) in the window, or put it at the top and let it scroll
## when it is taller than the window.
func _place() -> void:
	var w := size.x
	var h := size.y
	var pad_x := float(UiStyle.S6) if w >= 1000 else float(UiStyle.S4)
	var pad_y := float(UiStyle.S4) if compact else float(UiStyle.S5)
	var mw := minf(1480.0, w - 2 * pad_x)
	_main.size = Vector2(mw, 0)
	var mh := _main.get_combined_minimum_size().y
	_main.size = Vector2(mw, mh)
	_main.position = Vector2(roundf((w - mw) * 0.5), roundf(maxf(pad_y, (h - mh) * 0.5)))
	_frame.custom_minimum_size = Vector2(0, mh + 2 * pad_y)
	_td_map.queue_redraw()
