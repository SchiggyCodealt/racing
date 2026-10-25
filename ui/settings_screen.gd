class_name SettingsScreen
extends "res://ui/dialog_screen.gd"
## settings_screen.gd
## ------------------------------------------------------------------
## The Settings screen (new in the Godot port; opened from the menu with the Settings button,
## O, or the gamepad highlight): one row per setting, each a name, a line of explanation and
## its choices as slanted segments (the picked one in the accent). The same panel and scrim
## as the Controls screen.
##
## Rows are data (ROWS, or add_row for more): {key, label, hint, type, options?, section?}
##   type "choice"  options [[value, "Label"], ...]
##   type "toggle"  On / Off (a bool setting)
##   type "action"  a button; pressing it emits action(key) (e.g. a terminal, later)
##   type "custom"  any Control in def.control (it handles its own input)
## Values are read and written with UiData.get_setting / set_setting; every change also emits
## setting_changed(key, value) for the game. "fullscreen" and "vsync" are window settings with
## no game meaning, so this screen applies them itself (apply_display; off in tests).
##
## Keys: up / down (W / S) pick a row, left / right (A / D) or Enter / Space change it, Esc,
## Backspace or O closes. Gamepad: d-pad / stick, A changes, B or Menu closes. The mouse
## clicks the segments.

signal setting_changed(key: String, value: Variant)
signal action(key: String)

const ROWS := [
	{"section": "Graphics", "key": "quality", "label": "Graphics quality", "type": "choice",
		"options": [["high", "High"], ["low", "Low"]],
		"hint": "Low draws less scenery, fewer sparks and shorter nitro trails, turns off scenery shadows and renders at a lower resolution."},
	{"section": "Display", "key": "fullscreen", "label": "Fullscreen", "type": "toggle",
		"hint": "Fill the whole screen instead of a window."},
	{"key": "vsync", "label": "Vertical sync", "type": "toggle",
		"hint": "Match the monitor's refresh rate: no tearing, a little more input lag."},
	{"section": "Race", "key": "ghost", "label": "Race my best-run ghost", "type": "toggle",
		"hint": "In Drive, a see-through copy of your best run with the same car races with you (G or Y switches it during a race)."},
]

## Apply "fullscreen" and "vsync" to the window when they change.
var apply_display := true
var selected_row := 0
var _rows: Array = []        # [{def, box, segs: [Button], label}]
var _list: VBoxContainer


func _init() -> void:
	super("Settings")
	max_width = 720.0
	body.add_child(UiStyle.gap(0, UiStyle.S2))
	_list = UiStyle.vbox(0)
	body.add_child(_list)
	for def in ROWS:
		add_row(def)


## Add a setting row (see the header for `def`). Returns the row's Control.
func add_row(def: Dictionary) -> Control:
	if def.has("section"):
		_list.add_child(UiStyle.gap(0, UiStyle.S4))
		var h := UiStyle.label(def.section, "display_bold", UiStyle.FS_M, UiStyle.TEXT_2, 0.1, true, false, false, UiStyle.FS_M)
		_list.add_child(h)
		_list.add_child(UiStyle.gap(0, UiStyle.S2))
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
			var b := UiStyle.button(str(def.get("button", "Open")), "SmallButton", 30)
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			b.pressed.connect(func() -> void: action.emit(str(def.key)))
			line.add_child(b)
			entry.segs.append(b)
		"custom":
			line.add_child(def.control)
	row.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_select(idx))
	_list.add_child(row)
	_rows.append(entry)
	_render()
	return row


static func _options(def: Dictionary) -> Array:
	if str(def.type) == "toggle":
		return [[true, "On"], [false, "Off"]]
	return def.get("options", [])


## Set a setting (as a click on its segment would).
func set_value(key: String, value: Variant) -> void:
	UiData.set_setting(key, value)
	if apply_display:
		if key == "fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if value else DisplayServer.WINDOW_MODE_WINDOWED)
		elif key == "vsync":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if value else DisplayServer.VSYNC_DISABLED)
	setting_changed.emit(key, value)
	_render()


## Step row `i`'s value to the next (+1) or previous (-1) option (wrapping); actions are pressed.
func step_row(i: int, dir: int) -> void:
	var def: Dictionary = _rows[i].def
	match str(def.type):
		"choice", "toggle":
			var opts := _options(def)
			var at := -1
			for k in opts.size():
				if opts[k][0] == UiData.get_setting(str(def.key)):
					at = k
			set_value(str(def.key), opts[(at + dir + opts.size()) % opts.size()][0])
		"action":
			action.emit(str(def.key))


func _select(i: int) -> void:
	selected_row = clampi(i, 0, _rows.size() - 1)
	_render()


## Show every row's value and the selected row.
func _render() -> void:
	for i in _rows.size():
		var r: Dictionary = _rows[i]
		# the selected row: a card with the accent edge (the segments keep their own plates)
		var sb := UiStyle.box(UiStyle.BG_2 if i == selected_row else Color(0, 0, 0, 0), false,
			[UiStyle.S3, UiStyle.S2 + 2, UiStyle.S3, UiStyle.S2 + 2])
		if i == selected_row:
			sb.border_width_left = 3
			sb.border_color = UiStyle.ACCENT
		r.box.add_theme_stylebox_override("panel", sb)
		if str(r.def.type) in ["choice", "toggle"]:
			var opts := _options(r.def)
			var v: Variant = UiData.get_setting(str(r.def.key))
			for k in opts.size():
				r.segs[k].theme_type_variation = "SegOnButton" if opts[k][0] == v else "SmallButton"


func open() -> void:
	_render()
	super()


## Keys and gamepad while the screen is open (MainMenu forwards them).
func handle_keys(inp: Object) -> void:
	if inp.consume(["Escape", "Backspace", "KeyO", "PadB", "PadStart"]):
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
