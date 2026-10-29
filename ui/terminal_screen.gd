class_name TerminalScreen
extends "res://ui/dialog_screen.gd"
## terminal_screen.gd (v6.7.0)
## ------------------------------------------------------------------
## The terminal: a small console over the menu for changing the career by typing (`money 5000`,
## `points 200`, `unlock all`; `help` lists everything). It opens from Settings (the Terminal
## row) or with the ` key on the menu and on Settings, never during a race. The same scrim and
## panel as the Controls and Settings screens: a scrolling log (each line typed after a ">",
## then what it did), a one-line input with a blinking caret, and a row of key hints.
## Keys (the input has the keyboard focus while the terminal is open): Enter runs the line,
## Up / Down step through the lines run before (this session), Tab completes the command name or
## its first argument (several matches are listed in the log), Ctrl+L clears the log, Esc or `
## closes (MainMenu.handle_keys calls handle_keys: also the pad's B or Menu); the Close button and
## a click beside the panel close it too. Typing needs a keyboard; a gamepad can open it from
## Settings and close it.
## The commands are not here: `commands` is any object with
##   run(line) -> {lines: [[kind, text] or ["row", label, value]], changed, close, clear}
##   complete(line) -> {line, options}
## (game/terminal.gd: the app hands it over). `changed` is emitted after a command changed the
## career, so the menu redraws.

signal changed

const MAX_LINES := 300
const MAX_HISTORY := 50
const WELCOME := "Track Rush terminal. Type help for the commands: money 5000, points 200, unlock all ..."
## Line kinds -> colours (game/terminal.gd's kinds; "row" is a table row).
const KIND_COLORS := {
	"ok": UiStyle.TEXT, "info": UiStyle.TEXT_2, "gain": UiStyle.GOOD, "loss": UiStyle.BAD,
	"error": UiStyle.ACCENT, "warn": UiStyle.ACCENT, "echo": UiStyle.TEXT_2,
}

## The command runner (see the header); null: lines are only echoed.
var commands: Object = null
## The lines run, oldest first (Up / Down step through them).
var history: PackedStringArray = []
## The input line and the log.
var line: LineEdit
var log_view: RichTextLabel
var _entries: Array = []   # what the log shows: [kind, text] / ["row", label, value] / ["echo", line]
var _hist_at := -1         # the history entry shown while stepping (-1: the line being typed)
var _draft := ""           # what was typed before stepping into the history
var _greeted := false


func _init() -> void:
	super("Terminal")
	max_width = 880.0
	body.add_child(UiStyle.gap(0, UiStyle.S3))
	# the log: a dark well that scrolls, newest at the bottom
	var well := UiStyle.panel(UiStyle.box(UiStyle.BG_0, false, [UiStyle.S3, UiStyle.S2, UiStyle.S3, UiStyle.S2]))
	well.mouse_filter = Control.MOUSE_FILTER_PASS
	well.gui_input.connect(_on_click)
	log_view = RichTextLabel.new()
	log_view.bbcode_enabled = false
	log_view.scroll_following = true
	log_view.selection_enabled = false
	log_view.focus_mode = Control.FOCUS_NONE
	log_view.mouse_filter = Control.MOUSE_FILTER_PASS
	log_view.custom_minimum_size = Vector2(1, 300)
	log_view.add_theme_font_override("normal_font", UiStyle.font("text", UiStyle.FS_M, 0.0, true))
	log_view.add_theme_font_override("bold_font", UiStyle.font("text_semi", UiStyle.FS_M, 0.0, true))
	log_view.add_theme_font_size_override("normal_font_size", UiStyle.FS_M)
	log_view.add_theme_font_size_override("bold_font_size", UiStyle.FS_M)
	log_view.add_theme_color_override("default_color", UiStyle.TEXT)
	log_view.add_theme_constant_override("line_separation", 3)
	log_view.add_theme_constant_override("table_h_separation", UiStyle.S5)
	log_view.add_theme_constant_override("table_v_separation", 3)
	well.add_child(log_view)
	body.add_child(well)
	body.add_child(UiStyle.gap(0, UiStyle.S2))
	# the input: a ">" prompt and the line, on a darker plate with the accent edge
	var sb := UiStyle.box(UiStyle.BG_0, false, [UiStyle.S3, 0, UiStyle.S3, 0])
	sb.border_width_left = 3
	sb.border_color = UiStyle.ACCENT
	var plate := UiStyle.panel(sb)
	plate.mouse_filter = Control.MOUSE_FILTER_PASS
	plate.gui_input.connect(_on_click)
	var row := UiStyle.hbox(UiStyle.S2)
	plate.add_child(row)
	var prompt := UiStyle.label(">", "display_bold", UiStyle.FS_L, UiStyle.ACCENT)
	prompt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(prompt)
	line = LineEdit.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.custom_minimum_size.y = 40
	line.placeholder_text = "Type a command (help lists them)"
	line.caret_blink = true
	line.caret_blink_interval = 0.5
	line.context_menu_enabled = false
	line.max_length = 200
	line.add_theme_font_override("font", UiStyle.font("text_semi", UiStyle.FS_M, 0.0, true))
	line.add_theme_font_size_override("font_size", UiStyle.FS_M)
	line.add_theme_color_override("font_color", UiStyle.TEXT)
	line.add_theme_color_override("font_placeholder_color", UiStyle.TEXT_3)
	line.add_theme_color_override("caret_color", UiStyle.ACCENT)
	line.add_theme_color_override("selection_color", Color(UiStyle.ACCENT, 0.3))
	line.add_theme_constant_override("caret_width", 2)
	for st in ["normal", "focus", "read_only"]:
		line.add_theme_stylebox_override(st, UiStyle.empty_box())
	line.gui_input.connect(_on_line_input)
	row.add_child(line)
	body.add_child(plate)
	# the keys
	body.add_child(UiStyle.gap(0, UiStyle.S3))
	var hints := UiStyle.hbox(UiStyle.S4)
	for h: Array in [[["k:Enter"], "run"], [["k:Tab"], "complete"], [["a:up", "a:down"], "earlier lines"], [["k:Esc", "k:`"], "close"]]:
		var p := UiStyle.hbox(UiStyle.S1)
		for cap: String in h[0]:
			p.add_child(KeyCap.arrow(cap.substr(2)) if cap.begins_with("a:") else KeyCap.make(cap.substr(2)))
		var l := UiStyle.label(h[1], "text", UiStyle.FS_S, UiStyle.TEXT_3)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		p.add_child(l)
		hints.add_child(p)
	body.add_child(hints)


## Open with the input focused (the first time with a short welcome).
func open() -> void:
	if not _greeted:
		_greeted = true
		print_lines([["info", WELCOME]])
	super()
	focus_line()


func close() -> void:
	if line != null and line.has_focus():
		line.release_focus()
	super()


## Give the input the keyboard focus (typing goes there).
func focus_line() -> void:
	if line == null or not line.is_visible_in_tree():
		return
	line.grab_focus()
	if line.has_method("edit"):
		line.call("edit") # (Godot 4.4+: a LineEdit focused from code waits for a key before editing)
	line.caret_column = line.text.length()


## Keys and pad while it is open (MainMenu forwards them; the typing itself goes to the input):
## Esc, ` and the pad's B or Menu close it.
func handle_keys(inp: Object) -> void:
	if inp.consume(["Escape", "Backquote", "PadB", "PadStart"]):
		close()
		return
	if is_open and not line.has_focus():
		focus_line()


## Run `text` as if typed and entered (also what Enter does with the input's text).
func submit(text: String = "") -> Dictionary:
	var cmd := text if text != "" else line.text
	line.text = ""
	_hist_at = -1
	_draft = ""
	if cmd.strip_edges() == "":
		return {}
	if history.is_empty() or history[history.size() - 1] != cmd:
		history.append(cmd)
		if history.size() > MAX_HISTORY:
			history = history.slice(history.size() - MAX_HISTORY)
	print_lines([["echo", cmd]])
	var r: Dictionary = {}
	if commands != null:
		r = commands.call("run", cmd)
	else:
		r = {"lines": [["info", "No commands here."]]}
	if bool(r.get("clear", false)):
		clear_log()
	print_lines(r.get("lines", []))
	if bool(r.get("changed", false)):
		changed.emit()
	if bool(r.get("close", false)):
		close()
	return r


## Step through the history: -1 an older line, +1 a newer one (past the newest: what was being
## typed before).
func history_step(dir: int) -> void:
	if history.is_empty():
		return
	if _hist_at == -1:
		if dir > 0:
			return
		_draft = line.text
		_hist_at = history.size() - 1
	else:
		_hist_at += dir
	if _hist_at >= history.size():
		_hist_at = -1
		line.text = _draft
	else:
		_hist_at = clampi(_hist_at, 0, history.size() - 1)
		line.text = history[_hist_at]
	line.caret_column = line.text.length()


## Tab: complete the input's last word (commands.complete); several matches are listed.
func complete() -> void:
	if commands == null or not commands.has_method("complete"):
		return
	var r: Dictionary = commands.call("complete", line.text)
	line.text = str(r.get("line", line.text))
	line.caret_column = line.text.length()
	var opts: PackedStringArray = PackedStringArray(r.get("options", []))
	if opts.size() > 1:
		print_lines([["info", "Tab: %s" % ", ".join(opts)]])


## Add lines to the log (see the header for their shapes); the oldest go past MAX_LINES.
func print_lines(lines: Array) -> void:
	_entries.append_array(lines)
	if _entries.size() > MAX_LINES:
		_entries = _entries.slice(_entries.size() - MAX_LINES)
		_render_all()
	else:
		_render(lines)


func clear_log() -> void:
	_entries.clear()
	log_view.clear()


## The log's text as shown (tests).
func log_text() -> String:
	return log_view.get_parsed_text()


func _render_all() -> void:
	log_view.clear()
	_render(_entries)


func _render(lines: Array) -> void:
	var i := 0
	while i < lines.size():
		var l: Array = lines[i]
		var kind := str(l[0])
		if kind == "row":
			# consecutive rows: one table (the labels' column as wide as the widest)
			log_view.push_table(2)
			log_view.set_table_column_expand(0, false)
			log_view.set_table_column_expand(1, true)
			while i < lines.size() and str(lines[i][0]) == "row":
				var r: Array = lines[i]
				log_view.push_cell()
				log_view.push_color(UiStyle.TEXT_2)
				log_view.add_text(str(r[1]))
				log_view.pop()
				log_view.pop()
				log_view.push_cell()
				log_view.push_color(UiStyle.TEXT)
				log_view.add_text(str(r[2]) if r.size() > 2 else "")
				log_view.pop()
				log_view.pop()
				i += 1
			log_view.pop()
			log_view.newline()
			continue
		if kind == "echo":
			log_view.push_color(UiStyle.ACCENT)
			log_view.push_bold()
			log_view.add_text("> ")
			log_view.pop()
			log_view.pop()
			log_view.push_color(UiStyle.TEXT_2)
			log_view.add_text(str(l[1]))
			log_view.pop()
		else:
			log_view.push_color(KIND_COLORS.get(kind, UiStyle.TEXT))
			log_view.add_text(str(l[1]) if l.size() > 1 else "")
			log_view.pop()
		log_view.newline()
		i += 1


## The input's keys: Enter, Up / Down, Tab and Ctrl+L are the terminal's; Esc and ` are left
## to handle_keys (they close it) but never reach the input, so ` types nothing.
func _on_line_input(e: InputEvent) -> void:
	var k := e as InputEventKey
	if k == null or not k.pressed:
		return
	var code: Key = k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
	match code:
		KEY_ENTER, KEY_KP_ENTER:
			if not k.echo:
				submit()
		KEY_UP:
			history_step(-1)
		KEY_DOWN:
			history_step(1)
		KEY_TAB:
			if not k.echo:
				complete()
		KEY_QUOTELEFT, KEY_ESCAPE:
			pass
		KEY_L:
			if not k.ctrl_pressed:
				return
			clear_log()
		_:
			return
	line.accept_event()


## A click on the log or the input plate puts the focus back on the input.
func _on_click(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		focus_line()


## The log is about half the window's height (shorter windows keep room for the rest).
func _on_layout(_w: float) -> void:
	var h := size.y
	log_view.custom_minimum_size.y = clampf(roundf(h * 0.5), 140.0, 460.0)
