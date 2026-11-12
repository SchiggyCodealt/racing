class_name MainMenu
extends Control
## main_menu.gd
## ------------------------------------------------------------------
## The main menu (Home), in the order you use it since v6.19.0: 1 pick a track, 2 pick what to race;
## the car comes last, on its own page (ui/car_screen.gd, `car_page`) that opens when a race is chosen.
## - Track tiles: number, a minimap of the centre line (drawn from the built track, no image
##   files), name, difficulty, and the medal and best time you hold with the picked car. The tiles
##   take the room the car picker used to: their maps grow with the window's height.
## - One panel for the selected track: description, type and length, a bigger map when the
##   window is tall, your best time, best score and ghost with the picked car ("With the Racer":
##   C / Shift+C or LB / RB look at another car's records), the AI's best from training and the four
##   medal times.
## - "2 Race": TIME TRIAL (with the best-run ghost option), the AI driver row (an AI level, Rookie to
##   Elite: its finish time on this track with the picked car and what beating it pays now; or My AI,
##   the picked car's own trained network), Race the AI, Race the field (five AI drivers at the picked
##   level on a starting grid; off with My AI), and on the heading's right the Cups button, which is
##   also the trophy cabinet (ui/cup_cabinet.gd; it, or T, opens ui/cup_screen.gd, `cups`). Under a
##   rule, the AI's tools: Watch AI, Train AI, Load AI…, Save AI… (the picked car's network).
## - Choosing a race (the buttons, Enter, a double click on a tile, START CUP or a cup's next race)
##   opens the car page: the car cards (a car you don't own shows a lock and its price: START reads BUY
##   there), the picked car's upgrades and START. START emits the signal of the race chosen (`drive`,
##   `race_ghost`, `race_field`, `cup_start`, `cup_next`); before a cup's next race the page shows the
##   cup's car, and another pick changes the car for the rest of the cup. On a locked track the signal
##   goes out at once, so the game says what opens it. Watch AI and Train AI start directly.
## - The header: your money and career points, Settings, Controls. The terminal (ui/terminal_screen.gd)
##   opens from Settings' Terminal row or the ` key on the menu and on Settings; a command that changed
##   the career redraws the menu.
## - Locked tracks (v6.8.0): the tracks open one at a time (bronze or better on a track opens the
##   next, sim/unlocks.gd). A locked tile is darker, with a padlock and what opens it ("Bronze on
##   02"); it can still be picked, and its panel says what opens it and that Watch AI and Train AI
##   work there anyway. TIME TRIAL reads LOCKED. A track a finish just opened is marked NEW until it
##   is picked or the menu is left.
## Every bit of game data comes through UiData; the buttons only emit signals.
##
## Keyboard: arrows / WASD / 1-9, 0, -, = (tracks 1-12; further tracks by arrows, mouse or pad),
## C / Shift+C (next / previous car for the records shown), Enter or Space a time trial (the car page
## first), H or ? opens Controls, O opens Settings, ` opens the terminal, T the cups.
## Gamepad: a highlight moved with the d-pad / stick over the track tiles (moving onto one
## selects it) and the buttons (down from the bottom row of tiles); A races or presses, B goes back
## to the tracks, LB / RB pick the car, View opens Controls.
## The host calls handle_keys(input) once per frame (or sets `input` and the menu polls it);
## `input` is a MenuInput or anything with its interface.

signal drive
signal race_ghost
signal watch_ai
signal train_ai
## (v6.13) Race the field: five AI drivers at the picked AI level on a starting grid
signal race_field
signal load_network
signal save_network
signal track_selected(index: int)
signal car_selected(id: String)
signal opponent_selected(id: String)
## (v6.11) buy the next level of part `part` of the picked car (the game asks first)
signal upgrade(part: String)
## (v6.19) START on the car page for a cup: start cup `cup_id` at field level `level`, or the next
## race of the cup in progress (with the car picked now)
signal cup_start(cup_id: String, level: String)
signal cup_next
## (v6.18.0) Settings' Reset all progress button: the app asks, then wipes.
signal reset_requested

const W := preload("res://ui/widgets.gd")
const TrackTile := preload("res://ui/track_tile.gd")
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
	"keys": [["Arrows, 1–9 0 - =", "track"], ["Enter", "race"], ["T", "cups"]],
	"pad": [["D-pad", "move"], ["A", "race"], ["View", "controls"]],
}

## The menu's input (MenuInput or the same interface); polled in _process while the menu shows.
var input: Object = null
var selected_track := 0
var controls: ControlsScreen
var settings: SettingsScreen
var terminal: TerminalScreen
## (v6.14) the cup screen (ui/cup_screen.gd)
var cups: CupScreen
## (v6.19) the car page (ui/car_screen.gd): opens when a race is chosen
var car_page: CarScreen
## what the car page's START starts: "drive", "race_ghost", "race_field", "cup_start" (args: cup id,
## level) or "cup_next"
var pending := ""
var pending_args: Array = []

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
var _track_step: Control
var _tiles: Array = []
var _detail: PanelContainer
var _detail_box: VBoxContainer
var _td_num: Label
var _td_name: Label
var _td_diff: Control
var _td_meta: Label
var _td_desc: Label
var _td_lock: Control          # a locked track's note (v6.8.0)
var _td_lock_text: RichTextLabel
var _td_map: Control
var _td_car_name: Label
var _td_car_gap: Control
var _stats: Array = []       # [{box, label, medal, value}]
var _medals_box: VBoxContainer
var _medal_cells: Array = []  # [{dot, name, time}]
var _gaps := {}              # name -> spacer Control (sizes change with the window)
var _drive_btn: Button
var _ghost_check: Control
var _ai_cap: Label
var _ai_status: RichTextLabel
var _ai_status_text := ""
var _load_btn: Button
var _save_btn: Button
var _ghost_btn: Button
var _watch_btn: Button
var _train_btn: Button
var _field_btn: Button   # (v6.13) Race the field
var _cups_btn: CupCabinet   # (v6.14) the Cups button and trophy cabinet
## (v6.15) the note beside it: no nitro in races against the AI
var nitro_note: Label
const NITRO_NOTE := "No nitro vs AI" # (v6.16: shorter, it fits beside Cups at 1280 x 720)
## (v6.19) the primary button of Home: a time trial (the car page comes first)
const DRIVE_TEXT := "TIME TRIAL"
## The opponent buttons (v6.5.0): AI level id or UiData.MY_AI -> Button.
var _opp_btns: Dictionary = {}
var _opp_row: HBoxContainer
var _wallet: HBoxContainer
var _money_l: Label
var _points_l: Label
var _controls_btn: Button
var _settings_btn: Button
var _ring: Control
var _pad_at: Control = null   # the button or car the pad highlight is on (null: the selected track tile)
var _terminal_was_open := false
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
	cups = CupScreen.new()
	add_child(cups)
	cups.start_cup.connect(func(id: String, lv: String) -> void: ask_car("cup_start", [id, lv]))
	cups.next_race.connect(func() -> void: ask_car("cup_next"))
	car_page = CarScreen.new() # (over the cup screen: a cup's races ask for the car too)
	add_child(car_page)
	car_page.start.connect(_start_pending)
	car_page.upgrade.connect(func(part: String) -> void: upgrade.emit(part))
	car_page.car_picked.connect(func(id: String) -> void:
		car_selected.emit(id)
		refresh())
	terminal = TerminalScreen.new() # (over Settings when opened from it)
	add_child(terminal)
	settings.action.connect(func(key: String) -> void:
		if key == "terminal":
			show_terminal(true)
		elif key == "reset":
			reset_requested.emit())
	terminal.changed.connect(refresh)
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
	var fill := Control.new() # (spare height goes under the tiles)
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
	# the career: money and points (v6.5.0)
	_wallet = UiStyle.hbox(UiStyle.S3)
	_wallet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_wallet.mouse_filter = Control.MOUSE_FILTER_PASS
	_wallet.tooltip_text = "Your money buys cars and upgrades (the car page, after you chose a race); career points add up everything you have won. Medals and wins against the AI opponents pay both, once per track, car and medal or AI level; later tracks pay more."
	_money_l = UiStyle.label("", "display_bold", UiStyle.FS_L, UiStyle.TEXT, 0.02, false, true, false, UiStyle.FS_L)
	_money_l.size_flags_vertical = Control.SIZE_SHRINK_END
	_money_l.mouse_filter = Control.MOUSE_FILTER_PASS
	_wallet.add_child(_money_l)
	_points_l = UiStyle.label("", "display_bold", UiStyle.FS_M, UiStyle.ACCENT, 0.06, true, true, false, UiStyle.FS_M)
	_points_l.size_flags_vertical = Control.SIZE_SHRINK_END
	_points_l.mouse_filter = Control.MOUSE_FILTER_PASS
	var pm := UiStyle.margin([0, 0, 0, 1]) # (on the money's baseline)
	pm.size_flags_vertical = Control.SIZE_SHRINK_END
	pm.mouse_filter = Control.MOUSE_FILTER_PASS
	pm.add_child(_points_l)
	_wallet.add_child(pm)
	_head.add_child(_wallet)
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
	_settings_btn.tooltip_text = "Graphics, ghost, fullscreen, vsync and the terminal"
	_settings_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_settings_btn.pressed.connect(func() -> void:
		UiSound.play("ui_confirm")
		show_settings(true))
	_head.add_child(_settings_btn)
	_controls_btn = Dialog.button_with_cap("Controls", "H")
	_controls_btn.tooltip_text = "Every keyboard and gamepad control"
	_controls_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_controls_btn.pressed.connect(func() -> void:
		UiSound.play("ui_confirm")
		show_controls(true))
	_head.add_child(_controls_btn)


## A step heading with its number: "1 Track", "2 Race" (style.css .step).
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
	_track_step = _step("1", "Track")
	_left.add_child(_track_step)
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
		tile.picked.connect(func() -> void:
			if i != selected_track:
				UiSound.play("ui_move")
			select(i))
		tile.activated.connect(func() -> void: ask_car("drive"))
		_grid.add_child(tile)
		_tiles.append(tile)


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
	# a locked track: what opens it, and that the AI lab works anyway
	_td_lock = UiStyle.margin([0, UiStyle.S3, 0, 0])
	var lock_row := UiStyle.hbox(UiStyle.S2)
	_td_lock.add_child(lock_row)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(9, 18)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.draw.connect(func() -> void: W.padlock(icon, Vector2(0, 3), UiStyle.ACCENT))
	lock_row.add_child(icon)
	_td_lock_text = RichTextLabel.new()
	_td_lock_text.bbcode_enabled = true
	_td_lock_text.fit_content = true
	_td_lock_text.scroll_active = false
	_td_lock_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_td_lock_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_td_lock_text.custom_minimum_size.x = 1
	_td_lock_text.add_theme_font_override("normal_font", UiStyle.font("text", UiStyle.FS_S, 0, false, 18))
	_td_lock_text.add_theme_font_override("bold_font", UiStyle.font("text_semi", UiStyle.FS_S, 0, false, 18))
	_td_lock_text.add_theme_font_size_override("normal_font_size", UiStyle.FS_S)
	_td_lock_text.add_theme_font_size_override("bold_font_size", UiStyle.FS_S)
	_td_lock_text.add_theme_color_override("default_color", UiStyle.TEXT_2)
	_td_lock_text.add_theme_constant_override("line_separation", 0)
	_td_lock_text.mouse_filter = Control.MOUSE_FILTER_PASS
	lock_row.add_child(_td_lock_text)
	_td_lock.visible = false
	_detail_box.add_child(_td_lock)
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
	var step := _step("2", "Race")
	_side.add_child(step)
	# (v6.14) the Cups button with the trophy cabinet, on the right of the heading (it overlaps the
	# heading's bottom margin, so the menu keeps its height)
	var head_row: HBoxContainer = step.get_child(0)
	# (v6.15) races against the AI (Race the AI, Race the field, the cups) have no nitro for anyone
	nitro_note = UiStyle.label(NITRO_NOTE, "text", UiStyle.FS_S, UiStyle.TEXT_3)
	nitro_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nitro_note.tooltip_text = "Race the AI, Race the field and the cups have no nitro for anyone (you or the AI). The time trial and Watch AI keep it."
	nitro_note.mouse_filter = Control.MOUSE_FILTER_PASS
	nitro_note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS # (never wider than the room left)
	nitro_note.custom_minimum_size.x = 1
	nitro_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL # (the note takes the room and pushes Cups right)
	nitro_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head_row.add_child(nitro_note)
	_cups_btn = CupCabinet.new()
	_cups_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_cups_btn.pressed.connect(func() -> void:
		UiSound.play("ui_confirm")
		show_cups(true))
	head_row.add_child(_cups_btn)
	var actions := UiStyle.hbox(UiStyle.S5)
	_drive_btn = UiStyle.button("Time trial", "PrimaryButton", 46)
	_drive_btn.text = DRIVE_TEXT
	_drive_btn.custom_minimum_size.x = 190
	_drive_btn.pressed.connect(func() -> void: ask_car("drive"))
	actions.add_child(_drive_btn)
	_ghost_check = CheckToggle.new()
	_ghost_check.text = "Race my best-run ghost"
	_ghost_check.tooltip_text = "In a time trial, a see-through copy of your best run on the track with the car you drive races with you (G switches it during a race)"
	_ghost_check.toggled.connect(func(on: bool) -> void:
		UiSound.play("ui_move")
		UiData.set_setting("ghost", on))
	actions.add_child(_ghost_check)
	_side.add_child(actions)
	_gaps.ai = _spacer(_side, UiStyle.S3)
	# the AI driver: an AI level, or the car's own network (v6.5.0)
	_ai_cap = UiStyle.label("AI driver", "display_bold", UiStyle.FS_S, UiStyle.TEXT_2, 0.1, true, false, false, UiStyle.FS_S)
	_ai_cap.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_ai_cap.custom_minimum_size.x = 1
	_side.add_child(_ai_cap)
	_opp_row = UiStyle.hbox(UiStyle.S1)
	var ids: Array = Array(Opponents.ids())
	ids.append(UiData.MY_AI)
	for id: String in ids:
		var b := UiStyle.button("My AI" if id == UiData.MY_AI else Opponents.level_name(id), "ChipButton", 26)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.x = 1
		b.clip_text = true
		b.pressed.connect(func() -> void:
			UiSound.play("ui_move")
			select_opponent(id))
		_opp_row.add_child(b)
		_opp_btns[id] = b
	var om := UiStyle.margin([0, UiStyle.S2, 0, 0])
	om.add_child(_opp_row)
	_side.add_child(om)
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
	# the races against the AI: one car beside you, or five on a grid (v6.13)
	var pair := UiStyle.hbox(UiStyle.S3)
	_ghost_btn = UiStyle.button("Race the AI")
	_field_btn = UiStyle.button("Race the field")
	for b in [_ghost_btn, _field_btn]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_stretch_ratio = 1.0
		b.custom_minimum_size.x = 1
		b.clip_text = true
		pair.add_child(b)
	_ghost_btn.pressed.connect(func() -> void: ask_car("race_ghost"))
	_field_btn.pressed.connect(func() -> void: ask_car("race_field"))
	_side.add_child(pair)
	# the AI's tools under a rule (v6.19: they start directly, no car page)
	var rule := ColorRect.new()
	rule.color = UiStyle.LINE
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rm := UiStyle.margin([0, UiStyle.S3, 0, UiStyle.S2])
	rm.add_child(rule)
	_gaps.lab = rm
	_side.add_child(rm)
	var lab := UiStyle.hbox(UiStyle.S1)
	_watch_btn = UiStyle.button("Watch AI", "SmallButton", 30)
	_train_btn = UiStyle.button("Train AI", "SmallButton", 30)
	_load_btn = UiStyle.button("Load AI…", "SmallButton", 30)
	_save_btn = UiStyle.button("Save AI…", "SmallButton", 30)
	_load_btn.tooltip_text = "Load a network file as the picked car's own AI (My AI)"
	_save_btn.tooltip_text = "Save the picked car's own AI network to a file"
	for b in [_watch_btn, _train_btn, _load_btn, _save_btn]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.x = 1
		b.clip_text = true
		lab.add_child(b)
	_watch_btn.pressed.connect(func() -> void: watch_ai.emit())
	_train_btn.pressed.connect(func() -> void: train_ai.emit())
	_load_btn.pressed.connect(func() -> void: load_network.emit())
	_save_btn.pressed.connect(func() -> void: save_network.emit())
	_side.add_child(lab)


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
		var lock := UiData.track_lock(i)
		if lock.is_empty():
			_tiles[i].set_lock(false, "", "", UiData.is_new_track(id))
		else:
			_tiles[i].set_lock(true, "%s on %s" % [UiStyle.MEDAL_NAMES[lock.medal], UiFormat.track_number(int(lock.index))],
				"%s on %s opens it" % [str(UiStyle.MEDAL_NAMES[lock.medal]).to_lower(), lock.name])
	_render_detail()
	_render_wallet()
	_cups_btn.refresh()
	car_page.refresh()
	# the AI block is the picked car's: the opponent picked (an AI level, or its own network: that
	# network's status, two lines at most (the whole text is in the tooltip), or that it has none yet)
	var st := UiData.ai_status()
	var cname: String = UiData.car_info(car).name
	var opp := UiData.opponent()
	_ai_cap.text = "AI driver · %s" % cname
	for id: String in _opp_btns:
		(_opp_btns[id] as Button).theme_type_variation = "ChipOnButton" if id == opp else "ChipButton"
	_ghost_check.checked = bool(UiData.get_setting("ghost"))
	_save_btn.disabled = not st.ready
	_train_btn.tooltip_text = "Train AI drivers with any car (the training screen starts with the %s)" % cname
	_drive_btn.text = DRIVE_TEXT
	_drive_btn.theme_type_variation = "PrimaryButton"
	_drive_btn.tooltip_text = "Drive %s alone against the clock, for medals, records and score. You pick the car next." % UiData.track_info(selected_track).name
	if opp != UiData.MY_AI:
		_render_opponent(opp, car, cname)
		_render_track_lock()
		return
	_ghost_btn.text = "Race my AI"
	_field_btn.disabled = true
	_field_btn.tooltip_text = "Race the field: five AI drivers on a starting grid. Pick an AI level (Rookie to Elite) for them first; My AI races alone"
	if st.ready:
		var s := "[color=#a7a9ae][b]Ready[/b][/color]: "
		var trained := str(st.get("trained_car", car))
		if trained != car and UiData.car_ids().has(trained):
			# a network trained with another car (a loaded file): it drives this car all the same
			s += "[color=#%s]trained with the %s[/color], " % [UiStyle.ACCENT.to_html(false), UiData.car_info(trained).name]
		s += "generation %s, fitness %d, network %s" % [
			str(st.get("generation", "?")), roundi(float(st.get("fitness", 0))), "-".join(PackedStringArray(st.get("sizes", []).map(func(x: Variant) -> String: return str(int(x)))))]
		var on: Array = st.get("trained_on", [])
		if not on.is_empty():
			s += ", trained on " + ", ".join(PackedStringArray(on.map(_track_name)))
		if str(st.get("walls", "")) != "":
			s += " (walls: %s)" % st.walls
		_ai_status_text = s
	else:
		_ai_status_text = "[color=#a7a9ae][b]No %s network yet[/b][/color]: Train the AI teaches one with the %s, or load a network file." % [cname, cname]
	_ai_status.tooltip_text = _strip_bbcode(_ai_status_text)
	_clamp_status()
	_ghost_btn.disabled = not st.ready
	_watch_btn.disabled = not st.ready
	_ghost_btn.tooltip_text = "Race your %s AI: a see-through %s driven by the network you trained (it pays no AI rewards). You pick the car next." % [cname, cname] if st.ready \
		else "The %s has no AI network yet: train one first" % cname
	_watch_btn.tooltip_text = "Watch the %s AI drive this track, with its sensors and network" % cname if st.ready \
		else "The %s has no AI network yet: train one first" % cname
	_render_track_lock()


## A locked track (v6.8.0): the time trial reads LOCKED and Race the AI's tooltip says why it won't
## start; the game refuses both with a message.
func _render_track_lock() -> void:
	var lock := UiData.track_lock(selected_track)
	if lock.is_empty():
		return
	var why := "%s is locked: win %s or better on %s (any car) to open it" % [UiData.track_info(selected_track).name,
		str(UiStyle.MEDAL_NAMES[lock.medal]).to_lower(), lock.name]
	_drive_btn.text = "LOCKED"
	_drive_btn.theme_type_variation = ""
	_drive_btn.tooltip_text = why + ". Watch AI and Train AI work here anyway."
	if not _ghost_btn.disabled:
		_ghost_btn.tooltip_text = why + ". Watch AI works here."
	if not _field_btn.disabled:
		_field_btn.tooltip_text = why + "."


## The AI block with AI level `opp` picked: its finish time here with the picked car and what
## beating it pays now; Race / Watch drive it.
func _render_opponent(opp: String, car: String, cname: String) -> void:
	var lv: Dictionary = {}
	for l: Dictionary in UiData.opponent_levels(UiData.track_id(selected_track), car):
		if l.id == opp:
			lv = l
	var lname := str(lv.get("name", opp))
	var has := float(lv.get("time", -1.0)) > 0.0
	var good := "#" + UiStyle.GOOD.to_html(false)
	if not has:
		_ai_status_text = "[color=#a7a9ae][b]No %s AI here[/b][/color]: this track has no AI opponents with the %s in this version." % [lname, cname]
	else:
		var s := "[color=#a7a9ae][b]%s AI[/b][/color] (%s) finishes in [b]%s[/b]" % [lname, str(lv.get("blurb", "")), UiFormat.time(float(lv.time))]
		var pays: Dictionary = lv.get("pays", {})
		if int(pays.get("money", 0)) > 0:
			s += ". Beat it: [color=%s]+%s[/color] · +%s pts" % [good, UiFormat.money(int(pays.money)), UiFormat.points(int(pays.points))]
		else:
			s += ". Beaten: paid"
		_ai_status_text = s
	_ai_status.tooltip_text = _strip_bbcode(_ai_status_text)
	_clamp_status()
	_ghost_btn.text = "Race the %s AI" % lname
	_ghost_btn.disabled = not has
	_watch_btn.disabled = not has
	_ghost_btn.tooltip_text = "Race the %s AI: a see-through car next to you; finish ahead of it to win. You pick the car next (the time shown is with the %s)." % [lname, cname] if has \
		else "No %s AI on this track with the %s" % [lname, cname]
	_watch_btn.tooltip_text = "Watch the %s AI drive this track with the %s, with its sensors and network" % [lname, cname] if has \
		else "No %s AI on this track with the %s" % [lname, cname]
	# (v6.13) Race the field at this level: what a win pays now
	_field_btn.disabled = not has
	var win: Dictionary = UiData.field_pays(UiData.track_id(selected_track), car, opp, 1)
	_field_btn.tooltip_text = "Race the field: five AI drivers at %s pace on a starting grid; you start last. You pick the car next. Places pay once per track and car%s" % [
		lname, (": a win with the %s pays +%s · +%s pts now" % [cname, UiFormat.money(int(win.money)), UiFormat.points(int(win.points))]) if int(win.money) > 0 else " (every place here is paid with the %s)" % cname] if has \
		else "No %s AI on this track with the %s" % [lname, cname]


## The header's money and points.
func _render_wallet() -> void:
	_money_l.text = UiFormat.money(UiData.money())
	_points_l.text = "%s pts" % UiFormat.points(UiData.points())


## Pick the opponent of Race / Watch the AI: an AI level id or UiData.MY_AI (remembered).
func select_opponent(id: String) -> void:
	UiData.set_setting("opponent", id)
	opponent_selected.emit(id)
	refresh()


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
	_td_meta.text = (("Circuit · %d laps · %s km a lap" % [t.laps, UiFormat.km(t.length)]) if t.closed \
		else ("Sprint · %s km" % UiFormat.km(t.sprint_length))) + " · " + str(t.get("surfaces", "Asphalt"))
	_td_desc.text = t.description
	var lock := UiData.track_lock(i)
	_td_lock.visible = not lock.is_empty()
	if not lock.is_empty():
		_td_lock_text.text = "[color=#%s][b]Locked[/b][/color]: win %s or better on [b]%s[/b] (%s, any car) to open it. Watch AI and Train AI work here anyway; they pay nothing." % [
			UiStyle.ACCENT.to_html(false), str(UiStyle.MEDAL_NAMES[lock.medal]).to_lower(), lock.name, UiFormat.track_number(int(lock.index))]
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
			"The %s AI's best %s here, from its training" % [cinfo.name, "lap" if t.closed else "time"] if ai > 0
			else "The %s AI has no time here yet (it has no network, or was not trained on this track)" % cinfo.name],
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
	UiData.clear_new_tracks(UiData.track_id(i)) # (seen)
	track_selected.emit(i)
	refresh()
	_scroll.ensure_control_visible(_tiles[i])


## Pick car `id` (remembered: the car page starts with it); the tiles and the panel follow it.
func select_car(id: String) -> void:
	UiData.set_setting("car", id)
	car_selected.emit(id)
	refresh()


## A race was chosen (v6.19.0): `kind` "drive" (a time trial), "race_ghost", "race_field", "cup_start"
## (args: cup id, level) or "cup_next". The car page comes up, and its START starts it. On a locked
## track the signal goes out at once: the game says what opens the track. Before a cup's next race the
## page shows the cup's car.
func ask_car(kind: String, args: Array = []) -> void:
	pending = kind
	pending_args = args
	if kind in ["drive", "race_ghost", "race_field"] and not UiData.track_lock(selected_track).is_empty():
		_start_pending()
		return
	if kind == "cup_next":
		var v: Dictionary = cups.run_view.call() if cups.run_view.is_valid() else {}
		var c := String(v.get("car", ""))
		if UiData.car_ids().has(c) and c != UiData.picked_car():
			select_car(c)
	car_page.event_text = event_text(kind, args)
	UiSound.play("ui_confirm")
	_ring.set_target(null)
	car_page.open()


## The car page's line for race `kind`: what is about to start.
func event_text(kind: String, args: Array = []) -> String:
	var t := UiData.track_info(selected_track)
	var where := "%s %s" % [UiFormat.track_number(selected_track), t.name]
	var opp := UiData.opponent()
	match kind:
		"drive":
			return "Time trial · %s" % where
		"race_ghost":
			return ("Race my AI · %s" % where) if opp == UiData.MY_AI else "Race the %s AI · %s · no nitro" % [Opponents.level_name(opp), where]
		"race_field":
			return "Race the field (%s) · %s · no nitro" % [Opponents.level_name(opp), where]
		"cup_start":
			return "%s · %s field · you can change cars before every race" % [Cups.name_of(String(args[0])), Opponents.level_name(String(args[1]))]
		"cup_next":
			var v: Dictionary = cups.run_view.call() if cups.run_view.is_valid() else {}
			if v.is_empty():
				return "Cup race"
			var nx: Dictionary = v.get("next", {})
			return "%s · race %d of %d: %s %s · change cars if you like" % [String(v.name), int(v.done) + 1, int(v.count), String(nx.get("number", "")), String(nx.get("name", ""))]
	return ""


## START on the car page (or a race chosen on a locked track): the chosen race's signal goes out.
func _start_pending() -> void:
	match pending:
		"drive":
			drive.emit()
		"race_ghost":
			race_ghost.emit()
		"race_field":
			race_field.emit()
		"cup_start":
			cup_start.emit(String(pending_args[0]), String(pending_args[1]))
		"cup_next":
			cup_next.emit()


## The next (step 1) or previous (step -1) car.
func cycle_car(step: int) -> void:
	var ids := UiData.car_ids()
	var i := ids.find(UiData.picked_car())
	select_car(ids[(i + step + ids.size()) % ids.size()])


## The picked car's card on the car page.
func car_card() -> Control:
	return car_page.card()


## (v6.19) Close the car page (a race started, or the menu is left).
func show_car_page(on: bool) -> void:
	if on:
		_ring.set_target(null)
		car_page.open()
	else:
		car_page.close()


func show_menu(on: bool) -> void:
	if not on and visible:
		UiData.clear_new_tracks() # (the NEW marks were seen)
	visible = on
	if on:
		refresh()
	else:
		_ring.set_target(null)
		show_controls(false)
		show_settings(false)
		show_terminal(false)
		show_cups(false)
		show_car_page(false)


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


## (v6.14) The cup screen over the menu (the picker, or the standings of the cup in progress).
func show_cups(on: bool) -> void:
	if on:
		_ring.set_target(null)
		cups.open()
	else:
		cups.close()


## The terminal (over the menu, or over Settings when opened from there).
func show_terminal(on: bool) -> void:
	if on:
		_ring.set_target(null)
		terminal.open()
	else:
		terminal.close()


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
			UiSound.play("ui_back")
			show_controls(false)
		inp.clear_pressed()
		return
	if terminal.visible or _terminal_was_open:
		# the terminal: the typing goes to its input; Esc, `, the pad's B or Menu close it. When it
		# closed itself this frame (exit + Enter, its Close button), this frame's keys were typed
		# into it: they don't reach the menu either.
		if terminal.visible:
			terminal.handle_keys(inp)
		_terminal_was_open = terminal.visible
		inp.clear_pressed()
		return
	if car_page.visible:
		car_page.handle_keys(inp)
		inp.clear_pressed()
		return
	if cups.visible:
		cups.handle_keys(inp)
		inp.clear_pressed()
		return
	if settings.visible:
		if inp.consume(["Backquote"]):
			UiSound.play("ui_confirm")
			show_terminal(true)
		else:
			settings.handle_keys(inp)
		_terminal_was_open = terminal.visible
		inp.clear_pressed()
		return
	if inp.consume(["Backquote"]):
		UiSound.play("ui_confirm")
		show_terminal(true)
		_terminal_was_open = terminal.visible
		inp.clear_pressed()
		return
	if inp.consume(["KeyH", "Slash", "PadBack"]):
		UiSound.play("ui_confirm")
		show_controls(true)
		inp.clear_pressed()
		return
	if inp.consume(["KeyO"]):
		UiSound.play("ui_confirm")
		show_settings(true)
		inp.clear_pressed()
		return
	if inp.consume(["KeyT"]):
		UiSound.play("ui_confirm")
		show_cups(true)
		inp.clear_pressed()
		return
	var n := _tiles.size()
	var was_track := selected_track
	var was_car := UiData.picked_car()
	if inp.consume(["ArrowRight", "ArrowDown", "KeyD", "KeyS"]):
		select((selected_track + 1) % n)
	if inp.consume(["ArrowLeft", "ArrowUp", "KeyA", "KeyW"]):
		select((selected_track + n - 1) % n)
	for k in mini(n, TRACK_KEYS.size()):
		if inp.consume(TRACK_KEYS[k]):
			select(k)
	if inp.consume(["KeyC"]):
		cycle_car(-1 if inp.consume(["Shift+KeyC"]) else 1)
	if selected_track != was_track or UiData.picked_car() != was_car:
		UiSound.play("ui_move") # (v6.12.0: ui/ui_sound.gd)
	if inp.consume(["Enter", "Space", "NumpadEnter"]):
		ask_car("drive")
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


## The controls the pad highlight can go to (shown and enabled).
func _pad_controls() -> Array:
	var out: Array = []
	var list: Array = [_controls_btn, _settings_btn, _cups_btn, _drive_btn, _ghost_btn, _field_btn, _watch_btn, _train_btn, _ghost_check, _save_btn]
	list.append_array(_opp_btns.values())
	for c in list:
		if c.is_visible_in_tree() and not (c is BaseButton and c.disabled):
			out.append(c)
	return out


## Gamepad on the menu (menu.js handlePad). The highlight is on the selected track tile
## (_pad_at null) or a button. On the tiles the d-pad moves like the arrow keys (left / right
## along the tiles, wrapping; up / down a row; moving onto a tile selects it); down from the
## bottom row goes to TIME TRIAL, up from the top row to the Controls button. Between the buttons
## it moves to the nearest one (left / right only along a row); left from the first button of a
## row goes back to the tracks. A opens the car page for a time trial (on a tile) or presses the
## button. B goes back to the tracks, LB / RB pick the previous / next car (the records shown)
## from anywhere. The highlight shows while the pad is the last input used; a press while it is
## hidden only shows it. "Load AI…" is left out (its file dialog needs a mouse or keyboard anyway).
func handle_pad(inp: Object) -> void:
	var was_track := selected_track
	var was_car := UiData.picked_car()
	var dir: String = inp.nav_dir()
	var a: bool = inp.consume(["PadA"])
	var b: bool = inp.consume(["PadB"])
	var ctrls := _pad_controls()
	var shown := _ring.target != null
	var at: Control = _pad_at if ctrls.has(_pad_at) else null
	var step := (1 if inp.consume(["PadRB"]) else 0) - (1 if inp.consume(["PadLB"]) else 0)
	if step != 0:
		cycle_car(step)
	var drive_btn: Control = _drive_btn if ctrls.has(_drive_btn) else null
	if dir != "" and shown:
		var card: Control = _tiles[selected_track]
		if (at == _controls_btn or at == _settings_btn) and dir == "down":
			at = null # under the header buttons: the track tiles
		elif at != null:
			var next := PadNav.nearest_control(at, dir, ctrls)
			if next != null and (dir == "up" or dir == "down" or PadNav.same_row(at.get_global_rect(), next.get_global_rect())):
				at = next # (left / right: only along a row)
			elif dir == "left":
				at = null
		elif dir == "left" or dir == "right":
			var n := _tiles.size()
			select((selected_track + (1 if dir == "right" else n - 1)) % n)
		else:
			var next := PadNav.nearest_control(card, dir, _tiles)
			if next != null:
				select(_tiles.find(next))
			elif dir == "down":
				at = drive_btn # below the last row: the race buttons
			else:
				at = _controls_btn if ctrls.has(_controls_btn) else null # above the top row: Controls
	elif a and shown:
		if at != null:
			_press(at)
			return
		else:
			ask_car("drive")
			return
	if b:
		if at != null:
			UiSound.play("ui_back")
		at = null
	if (dir != "" and shown) or step != 0:
		if at != _pad_at or selected_track != was_track or UiData.picked_car() != was_car:
			UiSound.play("ui_move") # (v6.12.0: ui/ui_sound.gd)
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

## Apply the window-size rules (in interface pixels: UiRoot lays the interface out at the window's
## size divided by the interface scale, like CSS pixels):
##   up to six tiles a row from 1200 px wide, four below (three under 760), as many a row as keeps the
##   rows full (15 tracks make three rows of five); the side column 30 % of the width (360-440 px);
##   denser spacing when the window is short. Since v6.19.0 (no car picker on Home) the tiles take the
##   window's height: their maps are as tall as the rows allow (40 px at least, 0.75 of the tile's width
##   and 140 px at most); in one column (under 1000 px wide) the maps are 56 px and the page scrolls.
func _layout() -> void:
	var w := size.x
	var h := size.y
	if w <= 0 or h <= 0:
		return
	compact = h <= 800
	var big := w >= 1600 and h >= 940
	var one_col := w < 1000
	# at most six tiles a row (four, three in narrow windows), spread so the rows are as full as they
	# can be: 12 tracks make two rows of six, 15 three rows of five
	var max_cols := 6 if w >= 1200 else (4 if w >= 760 else 3)
	var rows := ceili(float(_tiles.size()) / max_cols)
	columns = ceili(float(_tiles.size()) / maxi(1, rows))
	_grid.columns = columns
	var tile_px := float(UiStyle.S3)
	if big:
		tile_px = UiStyle.S4
	elif w < 1280 and w >= 1200:
		tile_px = UiStyle.S2
	var tile_py := float(UiStyle.S4 if big else UiStyle.S3)
	var name_px := UiStyle.FS_L if big else UiStyle.FS_M
	var side_w := clampf(0.3 * w, 360.0, 440.0) if w >= 1200 else 340.0
	_main.vertical = one_col
	_side.custom_minimum_size.x = 0.0 if one_col else side_w
	_gaps.head.custom_minimum_size.y = UiStyle.S4 if compact else UiStyle.S5
	var pad_x := float(UiStyle.S6) if w >= 1000 else float(UiStyle.S4)
	var pad_y := float(UiStyle.S4) if compact else float(UiStyle.S5)
	var mw := minf(1480.0, w - 2 * pad_x)
	map_h = 56.0
	if not one_col:
		var left_w := mw - side_w - _main.get_theme_constant("separation")
		var tile_w := (left_w - (columns - 1) * UiStyle.S2) / columns
		var avail: float = h - 2 * pad_y - _head.get_combined_minimum_size().y - _gaps.head.custom_minimum_size.y - _track_step.get_combined_minimum_size().y
		var tile_h: float = floorf((avail - (rows - 1) * UiStyle.S2) / rows)
		var foot: float = 2 * UiStyle.S2 + roundf(name_px * 1.25) + (UiStyle.S2 if name_px > UiStyle.FS_M else UiStyle.S1) + 18
		if tile_h - foot - 2 * tile_py < 48.0:
			tile_py = UiStyle.S2 # (many rows in a short window: tighter tiles)
		map_h = clampf(tile_h - foot - 2 * tile_py, 40.0, minf(roundf((tile_w - 2 * tile_px) * 0.75), 140.0))
	for t in _tiles:
		t.set_metrics(map_h, tile_px, tile_py, name_px)
	_gaps.side.custom_minimum_size.y = UiStyle.S3 if compact else UiStyle.S5
	_gaps.ai.custom_minimum_size.y = UiStyle.S3 if compact else UiStyle.S5
	_gaps.status.add_theme_constant_override("margin_bottom", UiStyle.S2 if compact else UiStyle.S3)
	_gaps.lab.add_theme_constant_override("margin_top", UiStyle.S3 if compact else UiStyle.S4)
	_td_car_gap.custom_minimum_size.y = UiStyle.S3 if compact else UiStyle.S5
	_detail.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, false,
		[UiStyle.S5, UiStyle.S4 if compact else UiStyle.S5, UiStyle.S5, UiStyle.S4 if compact else UiStyle.S5]))
	_td_desc.custom_minimum_size.y = 0.0 if compact else ceilf(UiStyle.FS_M * 1.45 * 3)
	_drive_btn.custom_minimum_size.y = 46.0 if compact else 52.0
	# the ghost check box wraps its label beside the primary button when the side column is narrow
	var row_sep := float(_ghost_check.get_parent().get_theme_constant("separation"))
	var room := side_w - _drive_btn.custom_minimum_size.x - row_sep - 18 - UiStyle.S2
	_ghost_check.wrap_width = room if (not one_col and room < UiStyle.text_width(_ghost_check.text, "text", UiStyle.FS_S)) else 0.0
	# the two race buttons side by side in the 340 px side column: tighter padding
	for b in [_ghost_btn, _field_btn]:
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
