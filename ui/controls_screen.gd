class_name ControlsScreen
extends "res://ui/dialog_screen.gd"
## controls_screen.gd
## ------------------------------------------------------------------
## The Controls screen (index.html #controls): every keyboard key and gamepad button in two
## columns of tables (Driving, Race | Menu, Tips), over a dark scrim. The menu opens it with
## H, ? or View and closes it with Esc, H, ?, Backspace, Enter, Space or the pad's B, A, View,
## Menu (MainMenu.handle_keys); the Close button or a click beside the panel close it too.
## The tables lay out like the web's (table.keys): the Keyboard and Gamepad columns take 34 %
## and 27 % of the table, or as much as their widest row of caps needs; the action column
## takes the rest and wraps.

## Tables: [heading, has a Keyboard / Gamepad head row, rows]; a row is [action, keys, buttons]
## and a cell is a list of tokens: "k:W" a key cap, "a:up" an arrow cap, "t:Mouse" text,
## "s:–" a tight separator between caps.
const DRIVING := ["Driving", true, [
	["Accelerate", ["a:up", "k:W"], ["k:RT"]],
	["Brake, then reverse", ["a:down", "k:S"], ["k:LT"]],
	["Steer", ["a:left", "a:right", "k:A", "k:D"], ["t:Left stick"]],
	["Handbrake (drift)", ["k:Space"], ["k:A"]],
	["Nitro (hold)", ["k:Shift"], ["k:X", "k:RB"]],
]]
const RACE := ["Race", false, [
	["Restart", ["k:R"], ["k:View"]],
	["Respawn at the last checkpoint", ["k:Enter", "k:Backspace"], ["k:B"]],
	["Ghost on / off", ["k:G"], ["k:Y"]],
	["Back to the menu", ["k:Esc"], ["k:Menu"]],
]]
const MENU := ["Menu", true, [
	["Pick a track", ["k:Arrows", "k:1", "s:–", "k:9", "k:0", "k:-", "k:="], ["t:D-pad"]],
	["Next / previous car", ["k:C", "k:Shift", "s:+", "k:C"], ["k:RB", "k:LB"]],
	["Drive", ["k:Enter"], ["k:A"]],
	["Settings", ["k:O"], ["t:D-pad, then", "k:A"]],
	["Other buttons", ["t:Mouse"], ["t:D-pad, then", "k:A"]],
	["Back to the tracks", [], ["k:B"]],
	["This screen", ["k:H", "k:?", "k:Esc"], ["k:View", "k:B"]],
]]
const TIPS := [
	"Drift: pull the handbrake into a corner, then countersteer and use the throttle to hold the slide.",
	"Clean checkpoints build a combo up to x5; a wall or a respawn resets it. Points refill the nitro.",
	"Any standard gamepad works. On a PlayStation pad A is Cross, B Circle, X Square and Y Triangle.",
]

var _cols: BoxContainer
var _tables: Array = []   # [{keys: [Control], pads: [Control]}] for the column widths


func _init() -> void:
	super("Controls")
	body.add_child(UiStyle.gap(0, UiStyle.S4))
	_cols = BoxContainer.new()
	_cols.add_theme_constant_override("separation", UiStyle.S6)
	_cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_cols)
	var left := UiStyle.vbox(0)
	var right := UiStyle.vbox(0)
	for c in [left, right]:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_cols.add_child(c)
	_add_table(left, DRIVING, true)
	_add_table(left, RACE, false)
	_add_table(right, MENU, true)
	_add_heading(right, "Tips", false)
	for tip in TIPS:
		right.add_child(_tip(tip))


func _add_heading(box: VBoxContainer, text: String, first: bool) -> void:
	box.add_child(UiStyle.gap(0, UiStyle.S2 if first else UiStyle.S5))
	box.add_child(UiStyle.label(text, "display_bold", UiStyle.FS_M, UiStyle.TEXT_2, 0.1, true, false, false, UiStyle.FS_M))
	box.add_child(UiStyle.gap(0, UiStyle.S2))


func _add_table(box: VBoxContainer, table: Array, first: bool) -> void:
	_add_heading(box, table[0], first)
	var t := {"keys": [], "pads": []}
	_tables.append(t)
	if table[1]:
		# thead th: 600 13/1, padding-bottom S2
		var head := _row()
		head.add_child(_cell_text("", UiStyle.TEXT_3, "text_semi", UiStyle.FS_S))
		for k in 2:
			var l := _cell_text(["Keyboard", "Gamepad"][k], UiStyle.TEXT_3, "text_semi", UiStyle.FS_S)
			l.size_flags_horizontal = Control.SIZE_FILL
			head.add_child(l)
			t["keys" if k == 0 else "pads"].append(l)
		box.add_child(head)
		box.add_child(UiStyle.gap(0, UiStyle.S2))
	var rows: Array = table[2]
	for k in rows.size():
		if k > 0:
			var rule := ColorRect.new()
			rule.color = UiStyle.LINE
			rule.custom_minimum_size = Vector2(0, 1)
			rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(rule)
		var row := _row()
		# tbody th: padding 5px S3 5px 0, wraps
		var am := UiStyle.margin([0, 5, UiStyle.S3, 5])
		am.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		am.custom_minimum_size.x = 1
		var action := _cell_text(rows[k][0], UiStyle.TEXT, "text", 19)
		action.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		am.add_child(action)
		row.add_child(am)
		var kc := _cell_keys(rows[k][1])
		var pc := _cell_keys(rows[k][2])
		row.add_child(kc)
		row.add_child(pc)
		t.keys.append(kc)
		t.pads.append(pc)
		box.add_child(row)


func _row() -> HBoxContainer:
	return UiStyle.hbox(0)


func _cell_text(text: String, color: Color, kind: String, line_h: float) -> Label:
	var l := UiStyle.label(text, kind, UiStyle.FS_S, color, 0.0, false, false, false, line_h)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.custom_minimum_size.x = 1
	return l


## A cell of key caps (td: padding 5px 0, caps 22 px high, 2 px apart (+ the web's whitespace)).
func _cell_keys(tokens: Array) -> Control:
	var m := UiStyle.margin([0, 5, 0, 5])
	m.size_flags_horizontal = Control.SIZE_FILL
	m.custom_minimum_size.y = 32
	var row := UiStyle.hbox(0)
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	m.add_child(row)
	for k in tokens.size():
		var tok: String = tokens[k]
		var kind := tok.left(1)
		var val := tok.substr(2)
		if k > 0:
			var tight := kind == "s" or str(tokens[k - 1]).left(1) == "s"
			row.add_child(UiStyle.gap(2 if tight else 5))
		match kind:
			"k":
				row.add_child(KeyCap.make(val))
			"a":
				row.add_child(KeyCap.arrow(val))
			_:
				var l := UiStyle.label(val, "text", UiStyle.FS_S, UiStyle.TEXT_2 if kind == "t" else UiStyle.TEXT_3)
				l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				row.add_child(l)
	return m


func _tip(text: String) -> Control:
	var row := UiStyle.hbox(0)
	var bullet := Control.new()
	bullet.custom_minimum_size = Vector2(UiStyle.S4, 18)
	bullet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bullet.draw.connect(func() -> void: UiStyle.draw_skewed_rect(bullet, Rect2(0, 0.55 * UiStyle.FS_S + 1, 6, 6), UiStyle.ACCENT))
	bullet.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(bullet)
	var l := UiStyle.label(text, "text", UiStyle.FS_S, UiStyle.TEXT_2, 0.0, false, false, false, roundf(UiStyle.FS_S * 1.45))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 1
	row.add_child(l)
	var m := UiStyle.margin([0, 0, 0, UiStyle.S2])
	m.add_child(row)
	return m


## Two columns (one under 760 px); each table's Keyboard / Gamepad columns as wide as the
## web's auto table layout makes them.
func _on_layout(w: float) -> void:
	_cols.vertical = w < 760
	var inner := inner_width(w)
	var col_w := inner if _cols.vertical else (inner - UiStyle.S6) / 2.0
	for t in _tables:
		for part in [["keys", 0.34], ["pads", 0.27]]:
			var cells: Array = t[part[0]]
			var need := roundf(col_w * part[1])
			for c in cells:
				c.custom_minimum_size.x = 0
				need = maxf(need, c.get_combined_minimum_size().x)
			for c in cells:
				c.custom_minimum_size.x = need
