class_name SettingsScreen
extends "res://ui/dialog_screen.gd"
## settings_screen.gd
## ------------------------------------------------------------------
## The Settings screen (new in the Godot port; opened from the menu with the Settings button,
## O, or the gamepad highlight): one row per setting, each a name, a line of explanation and
## its choices as slanted segments (the picked one in the accent). The same panel and scrim
## as the Controls screen.
##
## Rows are data (ROWS, or add_row for more): {key, label, hint, type, options?, section?, column?}
##   type "choice"  options [[value, "Label"], ...]
##   type "toggle"  On / Off (a bool setting)
##   type "slider"  a volume 0..1 in tenths (ui/volume_bar.gd; v6.12.0's Audio rows)
##   type "action"  a button (def.button, default "Open", with def.cap's key cap when given);
##                  pressing it emits action(key): v6.7.0's Terminal row ("terminal")
##   type "custom"  any Control in def.control (it handles its own input)
## Values are read and written with UiData.get_setting / set_setting; every change also emits
## setting_changed(key, value) for the game. "fullscreen" and "vsync" are window settings with
## no game meaning, so this screen applies them itself (apply_display; off in tests).
##
## Keys: up / down (W / S) pick a row, left / right (A / D) or Enter / Space change it (or press
## an action row's button; a slider goes up or down a tenth, Enter up), Esc, Backspace or O
## closes; ` opens the terminal over it (MainMenu). Gamepad: d-pad / stick, A changes, B or Menu
## closes. The mouse clicks the segments and clicks or drags a slider.
##
## (v6.12.0) Two columns from TWO_COLUMNS px of width (1280 x 720 and up): a section with
## "column": 1 and the rows after it go to the right-hand column (Audio and Career); the keys and
## the pad still go through the rows in ROWS order (down from the left column's last row goes to
## the top of the right one). Narrower windows show one column, as before (1024 x 600 scrolls now:
## the keys and the pad keep the picked row in view). Changing a value plays the interface's click
## (ui/ui_sound.gd), closing its back sound.

signal setting_changed(key: String, value: Variant)
signal action(key: String)

const ROWS := [
	{"section": "Graphics", "key": "quality", "label": "Graphics quality", "type": "choice",
		"options": [["high", "High"], ["low", "Low"]],
		"hint": "Low draws less scenery, fewer sparks and shorter nitro trails, turns off scenery shadows and renders at a lower resolution."},
	{"key": "grime", "label": "Screen dirt and snow", "type": "toggle",
		"hint": "On dirt and snow, mud and snow splash onto the screen around its edges (never over the middle) and slide off on asphalt."},
	{"section": "Display", "key": "fullscreen", "label": "Fullscreen", "type": "toggle",
		"hint": "Fill the whole screen instead of a window."},
	{"key": "vsync", "label": "Vertical sync", "type": "toggle",
		"hint": "Match the monitor's refresh rate: no tearing, a little more input lag."},
	{"key": "ui_scale", "label": "Interface size", "type": "choice",
		"options": [["auto", "Auto"], [1.0, "100%"], [1.25, "125%"], [1.5, "150%"], [2.0, "200%"]],
		"hint": "The size of the menus and the HUD. Auto: 100% up to 1920x1080, bigger on larger screens."},
	{"section": "Race", "key": "ghost", "label": "Race my best-run ghost", "type": "toggle",
		"hint": "In Drive, a see-through copy of your best run with the same car races with you (G or Y switches it during a race)."},
	{"section": "Audio", "column": 1, "key": "vol_master", "label": "Master volume", "type": "slider",
		"hint": "Everything the game plays."},
	{"key": "vol_music", "label": "Music", "type": "slider", "hint": "The menu and race music."},
	{"key": "vol_sfx", "label": "Effects", "type": "slider", "hint": "Tyres, ground, walls, wind, race cues, menus."},
	{"key": "vol_engine", "label": "Engines", "type": "slider", "hint": "Your car's engine and the AI car's."},
	{"key": "mute_unfocused", "label": "Mute in the background", "type": "toggle",
		"hint": "No sound while another window is in front."},
	{"section": "Career", "key": "terminal", "label": "Terminal", "type": "action", "button": "Open", "cap": "`",
		"hint": "Change your career by typing: money 5000, points 200, unlock all (help lists all). The ` key opens it too."},
]

const VolumeBar := preload("res://ui/volume_bar.gd")
## Two columns from this window width (interface px).
const TWO_COLUMNS := 1100.0
const WIDTH_ONE := 720.0
const WIDTH_TWO := 1232.0

## Apply "fullscreen" and "vsync" to the window when they change.
var apply_display := true
## True while the rows are in two columns.
var two_columns := false
var selected_row := 0
var _rows: Array = []        # [{def, box, segs: [Button], label}]
var _list: VBoxContainer
var _section_gaps: Array = []
var _row_pad := UiStyle.S2 + 2   # a row's padding above and below (less in short windows)
var _cols: HBoxContainer          # the two columns (v6.12.0)
var _col: Array[VBoxContainer] = []
var _items: Array = []            # [Control, column] in order: section gaps, headings, rows
var _column := 0                  # the column add_row puts things in


func _init() -> void:
	super("Settings")
	max_width = WIDTH_ONE
	body.add_child(UiStyle.gap(0, UiStyle.S2))
	_list = UiStyle.vbox(0)
	body.add_child(_list)
	_cols = UiStyle.hbox(UiStyle.S6)
	_cols.visible = false
	body.add_child(_cols)
	for i in 2:
		var c := UiStyle.vbox(0)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_cols.add_child(c)
		_col.append(c)
	for def in ROWS:
		add_row(def)


## Put item `c` in the current column (and the list it belongs to now).
func _put(c: Control) -> void:
	_items.append([c, _column])
	(_col[_column] if two_columns else _list).add_child(c)


## Move every item to one column (false) or two (true).
func _arrange(two: bool) -> void:
	if two == two_columns:
		return
	two_columns = two
	for it: Array in _items:
		var c: Control = it[0]
		c.get_parent().remove_child(c)
		(_col[int(it[1])] if two else _list).add_child(c)
	_list.visible = not two
	_cols.visible = two


## Add a setting row (see the header for `def`). Returns the row's Control.
func add_row(def: Dictionary) -> Control:
	if def.has("section"):
		_column = clampi(int(def.get("column", _column)), 0, 1)
		var g := UiStyle.gap(0, UiStyle.S4)
		_section_gaps.append(g)
		_put(g)
		var h := UiStyle.label(def.section, "display_bold", UiStyle.FS_M, UiStyle.TEXT_2, 0.1, true, false, false, UiStyle.FS_M)
		_put(h)
		_put(UiStyle.gap(0, UiStyle.S2))
	var row := UiStyle.panel(UiStyle.box(Color(0, 0, 0, 0), false, [UiStyle.S3, UiStyle.S2 + 2, UiStyle.S3, UiStyle.S2 + 2]))
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var line := UiStyle.hbox(UiStyle.S5)
	row.add_child(line)
	var text := UiStyle.vbox(2)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var name_l := UiStyle.label(def.label, "text_semi", UiStyle.FS_M, UiStyle.TEXT, 0.0, false, false, false, 22)
	text.add_child(name_l)
	if str(def.get("hint", "")) != "":
		var hint := UiStyle.label(def.hint, "text", UiStyle.FS_S, UiStyle.TEXT_3, 0.0, false, false, false, 18)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size.x = 1
		text.add_child(hint)
	line.add_child(text)
	var entry := {"def": def, "box": row, "segs": [], "label": name_l}
	var idx := _rows.size()
	match str(def.type):
		"choice", "toggle":
			var segs := UiStyle.hbox(3)
			segs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			for opt in _options(def):
				var b := UiStyle.button(opt[1], "SmallButton", 30)
				b.custom_minimum_size.x = 64
				b.pressed.connect(func() -> void:
					_select(idx)
					set_value(str(def.key), opt[0]))
				segs.add_child(b)
				entry.segs.append(b)
			line.add_child(segs)
		"action":
			var b := button_with_cap(str(def.get("button", "Open")), str(def.cap)) if def.has("cap") else UiStyle.button(str(def.get("button", "Open")), "SmallButton", 30)
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			b.pressed.connect(func() -> void: action.emit(str(def.key)))
			line.add_child(b)
			entry.segs.append(b)
		"slider":
			var bar := VolumeBar.new()
			bar.value = float(UiData.get_setting(str(def.key)))
			bar.changed.connect(func(v: float) -> void:
				_select(idx)
				set_value(str(def.key), v))
			line.add_child(bar)
			entry.segs.append(bar)
		"custom":
			line.add_child(def.control)
	row.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_select(idx))
	_put(row)
	_rows.append(entry)
	_render()
	return row


## Values of any type compared without an error ("auto" against 1.25, 1 against 1.0).
static func _same(a: Variant, b: Variant) -> bool:
	var na := a is float or a is int
	var nb := b is float or b is int
	if na and nb:
		return is_equal_approx(float(a), float(b))
	return typeof(a) == typeof(b) and a == b


static func _options(def: Dictionary) -> Array:
	if str(def.type) == "toggle":
		return [[true, "On"], [false, "Off"]]
	return def.get("options", [])


## Set a setting (as a click on its segment would).
func set_value(key: String, value: Variant) -> void:
	var moved := not _same(UiData.get_setting(key), value)
	UiData.set_setting(key, value)
	if apply_display:
		if key == "fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if value else DisplayServer.WINDOW_MODE_WINDOWED)
		elif key == "vsync":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if value else DisplayServer.VSYNC_DISABLED)
	setting_changed.emit(key, value)
	if moved:
		UiSound.play("ui_move") # (after the change: a volume is heard at its new level)
	_render()


## Step row `i`'s value to the next (+1) or previous (-1) option (wrapping); actions are pressed.
func step_row(i: int, dir: int) -> void:
	var def: Dictionary = _rows[i].def
	match str(def.type):
		"choice", "toggle":
			var opts := _options(def)
			var at := -1
			for k in opts.size():
				if _same(opts[k][0], UiData.get_setting(str(def.key))):
					at = k
			set_value(str(def.key), opts[(at + dir + opts.size()) % opts.size()][0])
		"slider":
			set_value(str(def.key), snappedf(clampf(float(UiData.get_setting(str(def.key))) + dir * VolumeBar.STEP, 0.0, 1.0), VolumeBar.STEP))
		"action":
			UiSound.play("ui_confirm")
			action.emit(str(def.key))


func _select(i: int) -> void:
	var to := clampi(i, 0, _rows.size() - 1)
	if to != selected_row:
		UiSound.play("ui_move")
	selected_row = to
	_render()
	# (a short window scrolls, since v6.12.0's Audio rows: 1024 x 600 in one column; keep the picked
	# row in view)
	if _scroll != null and is_inside_tree():
		_scroll.ensure_control_visible.call_deferred(_rows[selected_row].box)


## Show every row's value and the selected row.
func _render() -> void:
	for i in _rows.size():
		var r: Dictionary = _rows[i]
		# the selected row: a card with the accent edge (the segments keep their own plates)
		var sb := UiStyle.box(UiStyle.BG_2 if i == selected_row else Color(0, 0, 0, 0), false,
			[UiStyle.S3, _row_pad, UiStyle.S3, _row_pad])
		if i == selected_row:
			sb.border_width_left = 3
			sb.border_color = UiStyle.ACCENT
		r.box.add_theme_stylebox_override("panel", sb)
		if str(r.def.type) in ["choice", "toggle"]:
			var opts := _options(r.def)
			var v: Variant = UiData.get_setting(str(r.def.key))
			for k in opts.size():
				r.segs[k].theme_type_variation = "SegOnButton" if _same(opts[k][0], v) else "SmallButton"
		elif str(r.def.type) == "slider":
			r.segs[0].value = float(UiData.get_setting(str(r.def.key)))


func open() -> void:
	_render()
	super()


## Keys and gamepad while the screen is open (MainMenu forwards them).
func handle_keys(inp: Object) -> void:
	if inp.consume(["Escape", "Backspace", "KeyO", "PadB", "PadStart"]):
		UiSound.play("ui_back")
		close()
		return
	var dir: String = inp.nav_dir()
	if inp.consume(["ArrowUp", "KeyW"]) or dir == "up":
		_select((selected_row + _rows.size() - 1) % _rows.size())
	elif inp.consume(["ArrowDown", "KeyS"]) or dir == "down":
		_select((selected_row + 1) % _rows.size())
	elif inp.consume(["ArrowLeft", "KeyA"]) or dir == "left":
		step_row(selected_row, -1)
	elif inp.consume(["ArrowRight", "KeyD"]) or dir == "right":
		step_row(selected_row, 1)
	elif inp.consume(["Enter", "Space", "NumpadEnter", "PadA"]):
		step_row(selected_row, 1)


## Short windows (1280x720 and less since v6.7.0's Terminal row): rows and sections closer
## together, so every setting fits (v6.11.0: 4 px a row, as 1024x600 had, since v6.10.0's Screen
## dirt and snow row made 1280x720 scroll by 20 px).
func _on_layout(w: float) -> void:
	_arrange(w >= TWO_COLUMNS)
	max_width = WIDTH_TWO if two_columns else WIDTH_ONE
	panel.custom_minimum_size.x = panel_width(w)
	var short := size.y <= 760
	_row_pad = UiStyle.S1 if short else UiStyle.S2 + 2
	for g in _section_gaps:
		g.custom_minimum_size.y = UiStyle.S2 if short else UiStyle.S4
	_render()
