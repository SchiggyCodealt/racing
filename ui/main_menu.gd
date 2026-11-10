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
## - Drive, the best-run ghost option, the AI block for the picked car (its network's status, or
##   that it has none yet; Load / Save network, Race the AI ghost, Watch the AI, Train the AI);
##   the Controls screen and the Settings screen.
## - v6.7.0, the terminal (ui/terminal_screen.gd): opened by Settings' Terminal row or the ` key on
##   the menu and on Settings (not on Controls, never in a race: the menu isn't there); a command
##   that changed the career redraws the menu.
## - v6.5.0, the career: the header shows your money and career points; the car cards of cars you
##   don't own show a lock and their price (their stats stay readable), and with such a car picked
##   Drive becomes BUY (or LOCKED when the money is short: it says how much is missing); the AI
##   block picks the opponent of Race / Watch the AI: an AI level (Rookie to Elite, its finish
##   time on this track with this car and what beating it pays now) or My AI (the picked car's
##   own trained network, as before).
## - v6.13.0, Race the field: a button beside Train the AI races five AI drivers at the picked AI level
##   on a starting grid (off with My AI picked, or a car you don't own; its tooltip says what a win pays).
## - v6.14.0, championships: on the right of the "3 Drive" heading, the Cups button (ui/cup_cabinet.gd),
##   which is also the trophy cabinet (one trophy per cup in the colour of your best place, pips for the
##   five levels); it, or T, opens the cup screen (ui/cup_screen.gd, `cups`) over the menu; the game opens
##   it between the races of a cup too.
## - v6.11.0, car upgrades (sim/upgrades.gd): under the cards, the picked car's four parts (engine,
##   tyres, nitro, loose grip) as chips with their levels and the next level's price; a chip buys
##   that level (the game asks first: `upgrade`). A car you don't own shows them greyed out. The car
##   cards' bars show the upgrades in green on top of the stock car. In a window under 760 px tall
##   the parts take the place of the car's description line (a locked car shows the description
##   and its price there instead); taller windows show both.
## - v6.8.0, locked tracks: the tracks open one at a time (bronze or better on a track opens the
##   next, sim/unlocks.gd). A locked tile is darker, with a padlock and what opens it ("Bronze on
##   02"); it can still be picked (keys, pad, mouse), and its panel says what opens it and that
##   Watch the AI and Train the AI work there anyway. Drive reads LOCKED (the game refuses Drive
##   and Race the AI there with a message). A track a finish just opened is marked NEW until it is
##   picked or the menu is left.
## Every bit of game data comes through UiData; the buttons only emit signals.
##
## Keyboard: arrows / WASD / 1-9, 0, -, = (tracks 1-12; further tracks by arrows, mouse or pad),
## C / Shift+C (next / previous car),
## Enter or Space drives, H or ? opens Controls, O opens Settings, ` opens the terminal, T the cups.
## Gamepad: a highlight moved with the d-pad / stick over the track tiles (moving onto one
## selects it), the car cards under them (moving onto one picks it) and the buttons; A drives
## or presses, B goes back to the tracks, LB / RB pick the car, View opens Controls.
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

const W := preload("res://ui/widgets.gd")
const TrackTile := preload("res://ui/track_tile.gd")
const CarCard := preload("res://ui/car_card.gd")
const PartChip := preload("res://ui/part_chip.gd")
## The parts row and the car's description line both show from this window height (px); below it
## the parts take the description's place (an owned car; a locked one keeps its description).
const BOTH_LINES_H := 760.0
## The car picker shows three cards a row from this width (px), else two.
const CARS_3COL := 780.0
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
var terminal: TerminalScreen
## (v6.14) the cup screen (ui/cup_screen.gd)
var cups: CupScreen

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
var _car_desc_row: HBoxContainer
var _parts_row: HBoxContainer       # (v6.11) the picked car's upgrades
var _parts_cap: Label
var _part_chips: Array = []
var _both_lines := false
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
## The opponent buttons (v6.5.0): AI level id or UiData.MY_AI -> Button.
var _opp_btns: Dictionary = {}
var _opp_row: HBoxContainer
var _wallet: HBoxContainer
var _money_l: Label
var _points_l: Label
var _car_lock: Label
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
	terminal = TerminalScreen.new() # (over Settings when opened from it)
	add_child(terminal)
	settings.action.connect(func(key: String) -> void:
		if key == "terminal":
			show_terminal(true))
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
	# the career: money and points (v6.5.0)
	_wallet = UiStyle.hbox(UiStyle.S3)
	_wallet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_wallet.mouse_filter = Control.MOUSE_FILTER_PASS
	_wallet.tooltip_text = "Your money buys cars (the car picker); career points add up everything you have won. Medals and wins against the AI opponents pay both, once per track, car and medal or AI level; later tracks pay more."
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
		tile.picked.connect(func() -> void:
			if i != selected_track:
				UiSound.play("ui_move")
			select(i))
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
		card.picked.connect(func() -> void:
			if id != UiData.picked_car():
				UiSound.play("ui_move")
			select_car(id))
		card.activated.connect(func() -> void: drive.emit())
		_cars_grid.add_child(card)
		_cards.append(card)
	var lines := UiStyle.vbox(UiStyle.S2)
	# (v6.11) the picked car's upgrades: a caption and a chip per part
	_parts_row = UiStyle.hbox(UiStyle.S1)
	_parts_row.custom_minimum_size.y = 26
	_parts_cap = UiStyle.label("Upgrades", "display_bold", UiStyle.FS_S, UiStyle.TEXT_2, 0.1, true, false, false, UiStyle.FS_S)
	_parts_cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_parts_cap.mouse_filter = Control.MOUSE_FILTER_PASS
	_parts_cap.tooltip_text = "Upgrade the picked car: engine (power), tyres (grip on asphalt), nitro (a bigger tank that refills faster) and loose grip (grip on dirt and snow), ten levels each (the last ones dear), bought in order with your money. Medal times and the AI opponents stay as they are (stock cars), so upgrades make medals and wins easier."
	var cm := UiStyle.margin([0, 0, UiStyle.S2, 0])
	cm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cm.mouse_filter = Control.MOUSE_FILTER_PASS
	cm.add_child(_parts_cap)
	_parts_row.add_child(cm)
	for p: Dictionary in UiData.upgrade_parts():
		var chip: Button = PartChip.new()
		chip.part_id = String(p.id)
		chip.part_name = String(p.name)
		chip.pressed.connect(func() -> void: upgrade.emit(String(p.id)))
		_parts_row.add_child(chip)
		_part_chips.append(chip)
	lines.add_child(_parts_row)
	var desc := UiStyle.hbox(UiStyle.S1)
	_car_desc_row = desc
	_car_lock = UiStyle.label("", "text_semi", UiStyle.FS_S, UiStyle.ACCENT, 0.0, false, false, false, 18)
	_car_lock.visible = false
	desc.add_child(_car_lock)
	_car_desc_name = UiStyle.label("", "text", UiStyle.FS_S, UiStyle.TEXT, 0.0, false, false, false, 18)
	_car_desc = UiStyle.label("", "text", UiStyle.FS_S, UiStyle.TEXT_2, 0.0, false, false, false, 18)
	_car_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_car_desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_car_desc.custom_minimum_size.x = 1
	_car_desc.mouse_filter = Control.MOUSE_FILTER_PASS
	desc.add_child(_car_desc_name)
	desc.add_child(_car_desc)
	for l: Label in [_car_lock, _car_desc_name, _car_desc]:
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lines.add_child(desc)
	var m := UiStyle.margin([0, UiStyle.S3, 0, 0])
	m.add_child(lines)
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
	var step := _step("3", "Drive")
	_side.add_child(step)
	# (v6.14) the Cups button with the trophy cabinet, on the right of the heading (it overlaps the
	# heading's bottom margin, so the menu keeps its height)
	var head_row: HBoxContainer = step.get_child(0)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head_row.add_child(fill)
	# (v6.15) races against the AI (Race the AI, Race the field, the cups) have no nitro for anyone
	nitro_note = UiStyle.label(NITRO_NOTE, "text", UiStyle.FS_S, UiStyle.TEXT_3)
	nitro_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nitro_note.tooltip_text = "Race the AI, Race the field and the cups have no nitro for anyone (you or the AI). Drive and Watch the AI keep it."
	nitro_note.mouse_filter = Control.MOUSE_FILTER_PASS
	nitro_note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS # (never wider than the room left)
	nitro_note.custom_minimum_size.x = 1
	nitro_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nitro_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fill.size_flags_horizontal = Control.SIZE_FILL # (the note takes the room and pushes Cups right)
	head_row.add_child(nitro_note)
	_cups_btn = CupCabinet.new()
	_cups_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_cups_btn.pressed.connect(func() -> void:
		UiSound.play("ui_confirm")
		show_cups(true))
	head_row.add_child(_cups_btn)
	var actions := UiStyle.hbox(UiStyle.S5)
	_drive_btn = UiStyle.button("Drive", "PrimaryButton", 46)
	_drive_btn.text = "DRIVE"
	_drive_btn.custom_minimum_size.x = 190
	_drive_btn.pressed.connect(func() -> void: drive.emit())
	actions.add_child(_drive_btn)
	_ghost_check = CheckToggle.new()
	_ghost_check.text = "Race my best-run ghost"
	_ghost_check.tooltip_text = "In Drive, a see-through copy of your best run on the track with the car you drive races with you (G switches it during a race)"
	_ghost_check.toggled.connect(func(on: bool) -> void:
		UiSound.play("ui_move")
		UiData.set_setting("ghost", on))
	actions.add_child(_ghost_check)
	_side.add_child(actions)
	_gaps.ai = _spacer(_side, UiStyle.S3)
	# the AI driver
	var head := UiStyle.hbox(UiStyle.S1)
	_ai_cap = UiStyle.label("AI driver", "display_bold", UiStyle.FS_S, UiStyle.TEXT_2, 0.1, true, false, false, UiStyle.FS_S)
	_ai_cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ai_cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_ai_cap.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_ai_cap.custom_minimum_size.x = 1
	head.add_child(_ai_cap)
	_load_btn = UiStyle.button("Load network…", "SmallQuietButton", 30)
	_load_btn.pressed.connect(func() -> void: load_network.emit())
	head.add_child(_load_btn)
	_save_btn = UiStyle.button("Save network…", "SmallQuietButton", 30)
	_save_btn.pressed.connect(func() -> void: save_network.emit())
	head.add_child(_save_btn)
	_side.add_child(head)
	# the opponent: an AI level, or the car's own network (v6.5.0)
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
	var om := UiStyle.margin([0, UiStyle.S1, 0, 0])
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
	# (v6.13) Race the field beside Train the AI (one row: the menu still fits 1280 x 720)
	var pair2 := UiStyle.hbox(UiStyle.S3)
	_field_btn = UiStyle.button("Race the field")
	_train_btn = UiStyle.button("Train the AI")
	for b in [_field_btn, _train_btn]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_stretch_ratio = 1.0
		b.custom_minimum_size.x = 1
		b.clip_text = true
		pair2.add_child(b)
	_field_btn.pressed.connect(func() -> void: race_field.emit())
	_train_btn.pressed.connect(func() -> void: train_ai.emit())
	buttons.add_child(pair2)
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
		var lock := UiData.track_lock(i)
		if lock.is_empty():
			_tiles[i].set_lock(false, "", "", UiData.is_new_track(id))
		else:
			_tiles[i].set_lock(true, "%s on %s" % [UiStyle.MEDAL_NAMES[lock.medal], UiFormat.track_number(int(lock.index))],
				"%s on %s opens it" % [str(UiStyle.MEDAL_NAMES[lock.medal]).to_lower(), lock.name])
	_render_detail()
	_render_cars()
	_render_wallet()
	_cups_btn.refresh()
	# the AI block is the picked car's: the opponent picked (an AI level, or its own network: that
	# network's status, two lines at most (the whole text is in the tooltip), or that it has none yet)
	var st := UiData.ai_status()
	var cname: String = UiData.car_info(car).name
	var opp := UiData.opponent()
	var owned := UiData.owns_car(car)
	_ai_cap.text = "AI driver · %s" % cname
	for id: String in _opp_btns:
		(_opp_btns[id] as Button).theme_type_variation = "ChipOnButton" if id == opp else "ChipButton"
	if opp != UiData.MY_AI:
		_render_opponent(opp, car, cname, owned)
		_ghost_check.checked = bool(UiData.get_setting("ghost"))
		_save_btn.disabled = not st.ready
		_train_btn.tooltip_text = "Train AI drivers with any car (the training screen starts with the %s)" % cname
		_render_track_lock()
		return
	_ghost_btn.text = "Race my AI"
	_watch_btn.text = "Watch my AI"
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
	_ghost_check.checked = bool(UiData.get_setting("ghost"))
	_ghost_btn.disabled = not st.ready or not owned
	_watch_btn.disabled = not st.ready
	_save_btn.disabled = not st.ready
	_ghost_btn.tooltip_text = ("Race your %s AI: a see-through %s driven by the network you trained (it pays no AI rewards)" % [cname, cname] if owned
		else "Buy the %s to race it" % cname) if st.ready else "The %s has no AI network yet: train one first" % cname
	_watch_btn.tooltip_text = "Watch the %s AI drive this track, with its sensors and network" % cname if st.ready \
		else "The %s has no AI network yet: train one first" % cname
	_train_btn.tooltip_text = "Train AI drivers with any car (the training screen starts with the %s)" % cname
	_render_track_lock()


## A locked track (v6.8.0): Drive reads LOCKED (unless the picked car is for sale: BUY first) and
## Race the AI's tooltip says why it won't start; the game refuses both with a message.
func _render_track_lock() -> void:
	var lock := UiData.track_lock(selected_track)
	if lock.is_empty():
		return
	var why := "%s is locked: win %s or better on %s (any car) to open it" % [UiData.track_info(selected_track).name,
		str(UiStyle.MEDAL_NAMES[lock.medal]).to_lower(), lock.name]
	if UiData.owns_car(UiData.picked_car()):
		_drive_btn.text = "LOCKED"
		_drive_btn.theme_type_variation = ""
		_drive_btn.tooltip_text = why + ". Watch the AI and Train the AI work here anyway."
	if not _ghost_btn.disabled:
		_ghost_btn.tooltip_text = why + ". Watch the AI works here."
	if not _field_btn.disabled:
		_field_btn.tooltip_text = why + "."


## The AI block with AI level `opp` picked: its finish time here with the picked car and what
## beating it pays now; Race / Watch drive it.
func _render_opponent(opp: String, car: String, cname: String, owned: bool) -> void:
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
	_watch_btn.text = "Watch the %s AI" % lname
	_ghost_btn.disabled = not has or not owned
	_watch_btn.disabled = not has
	_ghost_btn.tooltip_text = ("Race the %s AI: a see-through %s next to you; finish ahead of it to win" % [lname, cname] if owned
		else "Buy the %s to race it" % cname) if has else "No %s AI on this track with the %s" % [lname, cname]
	_watch_btn.tooltip_text = "Watch the %s AI drive this track with the %s, with its sensors and network" % [lname, cname] if has \
		else "No %s AI on this track with the %s" % [lname, cname]
	# (v6.13) Race the field at this level: what a win pays now
	_field_btn.disabled = not has or not owned
	var win: Dictionary = UiData.field_pays(UiData.track_id(selected_track), car, opp, 1)
	_field_btn.tooltip_text = ("Race the field: five AI drivers at %s pace on a starting grid; you start last. Places pay once per track and car%s" % [
		lname, (": a win pays +%s · +%s pts now" % [UiFormat.money(int(win.money)), UiFormat.points(int(win.points))]) if int(win.money) > 0 else " (every place here is paid)"]
		if owned else "Buy the %s to race it" % cname) if has else "No %s AI on this track with the %s" % [lname, cname]


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


func _render_cars() -> void:
	var car := UiData.picked_car()
	var have := UiData.money()
	for c in _cards:
		c.selected = c.car_id == car
		var price := UiData.car_price(c.car_id)
		c.set_lock(not UiData.owns_car(c.car_id), price, have >= price)
	for c in _cards:
		c.set_upgrades(UiData.car_bars(c.car_id), float(UiData.car_stats(c.car_id).top), UiData.upgrade_levels(c.car_id))
	_render_parts(car, have)
	var info := UiData.car_info(car)
	_car_desc_name.text = info.name
	_car_desc.text = info.description
	_car_desc.tooltip_text = "%s: %s" % [info.name, info.description]
	# a car you don't own: its price on the line under the cards, and Drive buys it
	var owned := UiData.owns_car(car)
	var price := UiData.car_price(car)
	_car_lock.visible = not owned
	_car_lock.text = ("Locked · %s ·" % UiFormat.money(price)) if not owned else ""
	if owned:
		_drive_btn.text = "DRIVE"
		_drive_btn.theme_type_variation = "PrimaryButton"
		_drive_btn.tooltip_text = ""
	elif have >= price:
		_drive_btn.text = "BUY %s" % UiFormat.money(price)
		_drive_btn.theme_type_variation = "PrimaryButton"
		_drive_btn.tooltip_text = "Buy the %s for %s (you have %s): it asks first" % [info.name, UiFormat.money(price), UiFormat.money(have)]
	else:
		_drive_btn.text = "LOCKED"
		_drive_btn.theme_type_variation = ""
		_drive_btn.tooltip_text = "The %s costs %s: %s more to go. Medals and wins against the AI opponents pay money." % [
			info.name, UiFormat.money(price), UiFormat.money(price - have)]


## The picked car's upgrades (v6.11): each part's chip (levels, the next price), the rows shown.
func _render_parts(car: String, have: int) -> void:
	var owned := UiData.owns_car(car)
	var cname: String = UiData.car_info(car).name
	var lv := UiData.upgrade_levels(car)
	var parts := UiData.upgrade_parts()
	for k in _part_chips.size():
		var chip: Button = _part_chips[k]
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
	# one line under the cards in a short window: an owned car's parts, a locked car's description
	_parts_row.visible = _both_lines or owned
	_car_desc_row.visible = _both_lines or not owned
	_car_desc_row.custom_minimum_size.y = 0.0 if _both_lines else 26.0


## The part chips the pad highlight can go to (shown and enabled).
func _pad_parts() -> Array:
	return _part_chips.filter(func(c: Control) -> bool: return c.is_visible_in_tree() and not (c as BaseButton).disabled)


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
		_td_lock_text.text = "[color=#%s][b]Locked[/b][/color]: win %s or better on [b]%s[/b] (%s, any car) to open it. Watch the AI and Train the AI work here anyway; they pay nothing." % [
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
	var list: Array = [_controls_btn, _settings_btn, _cups_btn, _drive_btn, _ghost_btn, _watch_btn, _field_btn, _train_btn, _ghost_check, _save_btn]
	list.append_array(_opp_btns.values())
	list.append_array(_part_chips)
	for c in list:
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
	var was_track := selected_track
	var was_car := UiData.picked_car()
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
			elif dir == "down" and not _pad_parts().is_empty():
				at = PadNav.nearest_control(at, "down", _pad_parts()) # (v6.11: the picked car's parts)
				if at == null:
					at = _pad_parts()[0]
			elif dir == "right" or dir == "down":
				at = drive_btn if drive_btn != null else at
		elif (at == _controls_btn or at == _settings_btn) and dir == "down":
			at = null # under the header buttons: the track tiles
		elif _part_chips.has(at) and dir == "up":
			at = car_card() # (v6.11) above the parts: the picked car
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
			UiSound.play("ui_confirm")
			at = null # the car is picked: back to the tracks
		elif at != null:
			_press(at)
			return
		else:
			drive.emit()
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

## Apply the window-size rules of style.css (in interface pixels: UiRoot lays the interface
## out at the window's size divided by the interface scale, like CSS pixels):
##   up to six tiles a row from 1200 px wide, four below (three under 760), as many a row as
##   keeps the rows full (v6.4: 15 tracks make three rows of five); map 56 px in short windows
##   (≤ 800 px; 40 px with three rows of tiles from 1200 px wide), 64 px, 80 px from 860 px tall,
##   104 px from 1600 x 940 (with roomier tiles); the side column 30 % of the width
##   (360-440 px); denser spacing when the window is short.
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
	# three rows of tiles in a short window: shorter maps and tighter tiles, so 1280 x 720 still
	# shows the whole menu without scrolling
	var dense := rows >= 3 and compact and w >= 1200
	map_h = 64.0
	if w >= 1200 and h >= 860:
		map_h = 80.0
	if big:
		map_h = 104.0
	if w < 1200 or compact:
		map_h = 56.0
	if w < 1200 and w >= 1000 and compact:
		map_h = 44.0
	if dense:
		map_h = 40.0
	_grid.columns = columns
	var tile_px := float(UiStyle.S3)
	if big:
		tile_px = UiStyle.S4
	elif w < 1280 and w >= 1200:
		tile_px = UiStyle.S2
	var tile_py := float(UiStyle.S4 if big else (UiStyle.S2 if dense else UiStyle.S3))
	for t in _tiles:
		t.set_metrics(map_h, tile_px, tile_py, UiStyle.FS_L if big else UiStyle.FS_M)
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
	# (v6.11) the parts row and the description line both, or one in its place
	var both := h >= BOTH_LINES_H or one_col
	if both != _both_lines:
		_both_lines = both
		_render_parts(UiData.picked_car(), UiData.money())
	_drive_btn.custom_minimum_size.y = 46.0 if compact else 52.0
	# the car picker: three cards a row when it is at least CARS_3COL px wide (six cars in two rows),
	# else two; the cards stack (bars under the side view and name) three a row, or two a row in a
	# 500-760 px picker (style.css @container car-picker)
	var pad_x := float(UiStyle.S6) if w >= 1000 else float(UiStyle.S4)
	var mw := minf(1480.0, w - 2 * pad_x)
	var picker_w := mw if one_col else mw - side_w - _main.get_theme_constant("separation")
	var car_cols := 3 if picker_w >= CARS_3COL else 2
	_cars_grid.columns = car_cols
	var card_w := (picker_w - (car_cols - 1) * UiStyle.S2) / car_cols
	for c in _cards:
		c.stacked = car_cols == 3 or (picker_w >= 500.0 and picker_w <= 760.0)
		c.short_spec = card_w < 300.0
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
