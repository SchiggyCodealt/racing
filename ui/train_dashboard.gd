extends Control
## train_dashboard.gd
## ------------------------------------------------------------------
## The AI training screen's interface (web/index.html #dashboard + #max-overlay, style.css):
## a 420 px column on the right of the 3D view (the bottom half in windows narrower than
## 1000 px) with
##   - the header: AI TRAINING and the Menu button
##   - the setup form: population size, mutation rate, hidden layer size(s), laps per circuit,
##     walls, the tracks to train on, "Continue from saved network", Start training and
##     Load network file…
##   - the run: Pause / Resume, the speed (1× / Fast ×6 / Max), Follow leader, Overview /
##     Chase camera, the viewed car's live network, what that car is doing, the stats
##     (generation, cars alive, best fitness ever, leader this run, track, run time), this
##     run's outs, the AI's best lap / finish per track, the fitness chart, Save best network,
##     Load network…, Watch best, Race best (ghost), Stop and a note line
## and, over the 3D view, the Max speed overlay (no 3D drawing at Max) with the speed reached.
## It fills its parent (full rect) and leaves the 3D view's part free (mouse clicks go through
## there: picking a car). view_rect() is that part, in this control's coordinates.
##
## Every press comes out as action(name): "start", "load", "menu", "pause", "speed_1",
## "speed_6", "speed_max", "follow", "cam", "save", "watch", "race", "stop"; a change of the
## ticked tracks, the walls or the seed tick as settings_changed(). The mode
## (modes/train_mode.gd) does the rest and fills the read-outs with the set_* functions.
## Gamepad: handle_pad(input) moves a highlight over the buttons, ticks and choices (A presses
## it); the number fields need a keyboard, the file dialog a mouse or the keys.

signal action(name: String)
signal settings_changed

const CheckToggle := preload("res://ui/check_toggle.gd")
const PadRing := preload("res://ui/pad_ring.gd")
const PadNav := preload("res://ui/pad_nav.gd")
const FitnessChart := preload("res://ui/train_fitness_chart.gd")

const DASH_W := 420.0          # style.css --dash-w
const NARROW_BELOW := 1000.0   # narrower windows: the dashboard is the bottom half
## What each wall rule means (the web form's Walls tooltip), under the choice.
const WALL_HINTS := {
	"ride": "A car that hits a wall keeps going, so the AI can learn to use walls instead of braking.",
	"crash": "A wall hit puts the car out, so it learns clean lines.",
}

var panel: PanelContainer
var scroll: ScrollContainer
var setup_box: VBoxContainer
var run_box: VBoxContainer
var overlay: Control
var max_rate: Label

# setup form
var pop: SpinBox
var mut: SpinBox
var hidden_edit: LineEdit
var laps_segs: Array[Button] = []
var walls_segs: Array[Button] = []
var walls_hint: Label
var track_checks: Array = []     # CheckToggle per track (Tracks.defs() order)
var seed_check: Control
var seed_info: Label
var start_btn: Button
var load_btn: Button
var laps := 1
var walls := "ride"

# the run
var pause_btn: Button
var speed_segs: Dictionary = {}  # "1" | "6" | "max" -> Button
var follow_btn: Button
var cam_btn: Button
var net_view: NetworkView
var viewing: RichTextLabel
var stat_values: Dictionary = {} # stat key -> Label
var run_line: Label
var times_box: VBoxContainer
var chart: Control
var save_btn: Button
var load2_btn: Button
var watch_btn: Button
var race_btn: Button
var stop_btn: Button
var note_label: Label
var menu_btn: Button

var _ring: Control
var _pad_at: Control = null
var _times_key := ""
var _narrow := false


func _init() -> void:
	name = "TrainDashboard"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiStyle.theme()

	overlay = _make_overlay()
	add_child(overlay)

	panel = UiStyle.panel(UiStyle.box(UiStyle.BG_1, false, [UiStyle.S5, UiStyle.S4, UiStyle.S2, UiStyle.S4]))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP # (clicks on the dashboard never pick a car)
	add_child(panel)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(scroll)
	var pad := UiStyle.margin([0, 0, UiStyle.S3, 0]) # (room for the scroll bar)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pad)
	var col := UiStyle.vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(col)

	# header
	var head := UiStyle.hbox(UiStyle.S3)
	head.add_child(UiStyle.label("AI training", "display_bold", UiStyle.FS_L, UiStyle.TEXT, 0.06, true))
	head.get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.get_child(0).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	menu_btn = _button("Menu", "menu", "SmallButton", 30)
	head.add_child(menu_btn)
	col.add_child(head)
	col.add_child(UiStyle.gap(0, UiStyle.S3))

	setup_box = _build_setup()
	col.add_child(setup_box)
	run_box = _build_run()
	run_box.visible = false
	col.add_child(run_box)

	_ring = PadRing.new()
	add_child(_ring)
	resized.connect(_layout)


# ================================================================= building

func _build_setup() -> VBoxContainer:
	var box := UiStyle.vbox(0)
	box.add_child(_text("Each generation, every car drives the selected track(s). The best networks are kept, mixed and mutated to make the next generation.",
		UiStyle.TEXT_3))
	box.add_child(UiStyle.gap(0, UiStyle.S3))
	var form := GridContainer.new()
	form.columns = 2
	form.add_theme_constant_override("h_separation", UiStyle.S3)
	form.add_theme_constant_override("v_separation", UiStyle.S3)
	pop = _spin(4, 400, 1, Trainer.DEFAULT_TRAINING.population_size, 0)
	form.add_child(_field("Population size", pop))
	mut = _spin(0.005, 1.0, 0.005, Trainer.DEFAULT_TRAINING.mutation_rate, 3)
	form.add_child(_field("Mutation rate", mut))
	hidden_edit = LineEdit.new()
	hidden_edit.text = ",".join(PackedStringArray(Trainer.DEFAULT_TRAINING.hidden.map(func(v: int) -> String: return str(v))))
	hidden_edit.tooltip_text = "One number per hidden layer, e.g. 12 or 16,8"
	_style_edit(hidden_edit)
	form.add_child(_field("Hidden layer size(s)", hidden_edit))
	var lap_row := UiStyle.hbox(3)
	for n in [1, 2, 3]:
		var b := _seg_button(str(n))
		b.pressed.connect(func() -> void: set_laps(n))
		laps_segs.append(b)
		lap_row.add_child(b)
	form.add_child(_field("Laps per circuit", lap_row))
	box.add_child(form)
	box.add_child(UiStyle.gap(0, UiStyle.S3))
	var wall_row := UiStyle.hbox(3)
	wall_row.tooltip_text = "Ride: a car that hits a wall keeps going, so the AI can learn to use walls instead of braking. Crash: a wall hit puts the car out, so it learns clean lines."
	wall_row.mouse_filter = Control.MOUSE_FILTER_PASS
	for rule: String in Trainer.WALL_RULES:
		# (the label before its bracket on the button: "Ride them", "Crash out"; what it means under it)
		var b := _seg_button(String(Trainer.WALL_RULES[rule]).get_slice(" (", 0))
		b.set_meta("rule", rule)
		b.tooltip_text = String(Trainer.WALL_RULES[rule])
		b.pressed.connect(func() -> void:
			set_walls(rule)
			settings_changed.emit())
		walls_segs.append(b)
		wall_row.add_child(b)
	box.add_child(_field("Walls", wall_row))
	walls_hint = _text("", UiStyle.TEXT_3)
	box.add_child(UiStyle.gap(0, UiStyle.S1))
	box.add_child(walls_hint)
	set_laps(1)
	set_walls(String(Trainer.DEFAULT_TRAINING.walls))

	box.add_child(UiStyle.gap(0, UiStyle.S4))
	box.add_child(UiStyle.label("Train on", "display_bold", UiStyle.FS_S, UiStyle.TEXT_2, 0.1, true))
	box.add_child(UiStyle.gap(0, UiStyle.S3))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", UiStyle.S3)
	grid.add_theme_constant_override("v_separation", UiStyle.S2)
	var defs := Tracks.defs()
	for i in defs.size():
		var c: Control = CheckToggle.new()
		c.text = "%d. %s" % [i + 1, String(defs[i].get("name", defs[i].get("id", "?")))]
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.toggled.connect(func(_on: bool) -> void: settings_changed.emit())
		track_checks.append(c)
		grid.add_child(c)
	box.add_child(grid)
	box.add_child(UiStyle.gap(0, UiStyle.S4))
	seed_check = CheckToggle.new()
	seed_check.text = "Continue from saved network"
	seed_check.toggled.connect(func(_on: bool) -> void: settings_changed.emit())
	box.add_child(seed_check)
	seed_info = _text("(none yet)", UiStyle.TEXT_3)
	box.add_child(seed_info)
	var row := _row()
	start_btn = _button("START TRAINING", "start", "PrimaryButton", 40)
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		# (style.css #dashboard .row > .btn: 8 px beside the text, so two fit side by side)
		var sb: StyleBoxFlat = UiStyle.theme().get_stylebox(st, "PrimaryButton").duplicate()
		sb.content_margin_left = UiStyle.S2
		sb.content_margin_right = UiStyle.S2
		start_btn.add_theme_stylebox_override(st, sb)
	load_btn = _button("Load network file…", "load", "TightButton")
	row.add_child(start_btn)
	row.add_child(load_btn)
	_add_row(box, row)
	return box


func _build_run() -> VBoxContainer:
	var box := UiStyle.vbox(0)
	var row := _row()
	pause_btn = _button("Pause", "pause", "TightButton")
	row.add_child(pause_btn)
	var seg := UiStyle.hbox(3)
	seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seg.size_flags_stretch_ratio = 2.0
	for s: Array in [["1", "1×"], ["6", "Fast ×6"], ["max", "Max"]]:
		var b := _seg_button(s[1])
		b.pressed.connect(func() -> void: action.emit("speed_" + String(s[0])))
		speed_segs[s[0]] = b
		seg.add_child(b)
	row.add_child(seg)
	_add_row(box, row)
	row = _row()
	follow_btn = _button("Follow leader", "follow", "TightButton")
	cam_btn = _button("Overview camera", "cam", "TightButton")
	row.add_child(follow_btn)
	row.add_child(cam_btn)
	_add_row(box, row)

	var net_bg := UiStyle.panel(UiStyle.box(UiStyle.BG_0))
	net_view = NetworkView.new()
	net_view.custom_minimum_size = Vector2(0, 300)
	net_bg.add_child(net_view)
	box.add_child(net_bg)

	viewing = RichTextLabel.new()
	viewing.bbcode_enabled = true
	viewing.fit_content = true
	viewing.scroll_active = false
	viewing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	viewing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewing.custom_minimum_size = Vector2(1, 18)
	viewing.add_theme_font_override("normal_font", UiStyle.font("text", UiStyle.FS_S, 0.0, true))
	viewing.add_theme_font_override("bold_font", UiStyle.font("text_semi", UiStyle.FS_S, 0.0, true))
	viewing.add_theme_font_size_override("normal_font_size", UiStyle.FS_S)
	viewing.add_theme_font_size_override("bold_font_size", UiStyle.FS_S)
	viewing.add_theme_color_override("default_color", UiStyle.TEXT_2)
	box.add_child(UiStyle.gap(0, UiStyle.S2))
	box.add_child(viewing)
	box.add_child(UiStyle.gap(0, UiStyle.S2))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", UiStyle.S4)
	grid.add_theme_constant_override("v_separation", UiStyle.S2)
	for s: Array in [["generation", "Generation"], ["alive", "Cars alive"], ["best", "Best fitness ever"],
			["leader", "Leader this run"], ["track", "Track"], ["time", "Run time"]]:
		var cell := UiStyle.vbox(0)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(UiStyle.label(s[1], "text", UiStyle.FS_S, UiStyle.TEXT_3))
		var v := UiStyle.label("—", "display", UiStyle.FS_L, UiStyle.TEXT, 0.0, false, true, false, 24)
		v.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.custom_minimum_size.x = 1
		cell.add_child(v)
		stat_values[s[0]] = v
		grid.add_child(cell)
	box.add_child(grid)
	box.add_child(UiStyle.gap(0, UiStyle.S3))
	run_line = _text("This run: all cars still driving", UiStyle.TEXT_2)
	box.add_child(run_line)
	box.add_child(UiStyle.gap(0, UiStyle.S2))
	times_box = UiStyle.vbox(0)
	box.add_child(times_box)

	var chart_gap := UiStyle.gap(0, UiStyle.S3)
	box.add_child(chart_gap)
	chart = FitnessChart.new()
	box.add_child(chart)

	row = _row()
	save_btn = _button("Save best network", "save", "TightButton")
	load2_btn = _button("Load network…", "load", "TightButton")
	row.add_child(save_btn)
	row.add_child(load2_btn)
	_add_row(box, row)
	row = _row()
	watch_btn = _button("Watch best", "watch", "TightButton")
	race_btn = _button("Race best (ghost)", "race", "TightButton")
	stop_btn = _button("Stop", "stop", "TightButton")
	row.add_child(watch_btn)
	row.add_child(race_btn)
	row.add_child(stop_btn)
	_add_row(box, row)
	note_label = _text("", UiStyle.TEXT)
	note_label.custom_minimum_size.y = 18
	box.add_child(note_label)
	box.add_child(UiStyle.gap(0, UiStyle.S2))
	box.add_child(_text("Click any car in the 3D view to see its network.", UiStyle.TEXT_3))
	return box


## The Max speed overlay over the 3D view (style.css #max-overlay).
func _make_overlay() -> Control:
	var o := ColorRect.new()
	o.color = Color(10 / 255.0, 11 / 255.0, 13 / 255.0, 0.86)
	o.mouse_filter = Control.MOUSE_FILTER_IGNORE
	o.visible = false
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	o.add_child(center)
	var col := UiStyle.vbox(UiStyle.S3, BoxContainer.ALIGNMENT_CENTER)
	center.add_child(col)
	var tag := UiStyle.panel(UiStyle.plate([UiStyle.S5, UiStyle.S1, UiStyle.S5, UiStyle.S1]))
	tag.name = "tag"
	tag.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tag.add_child(UiStyle.label("Max speed", "display_bold", UiStyle.FS_XL, UiStyle.TEXT, 0.06, true))
	col.add_child(tag)
	var small := UiStyle.label("3D rendering paused to train as fast as possible", "text", UiStyle.FS_S, UiStyle.TEXT_2)
	small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(small)
	max_rate = UiStyle.label("", "display_bold", UiStyle.FS_L, UiStyle.TEXT, 0.0, false, true)
	max_rate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(max_rate)
	return o


func _row() -> HBoxContainer:
	return UiStyle.hbox(UiStyle.S3)


## Add a button row with 12 px above and below it (style.css #dashboard .row; the margins of
## two rows in a row collapse into one 12 px gap).
func _add_row(box: VBoxContainer, r: Control) -> void:
	var n := box.get_child_count()
	if n == 0 or not box.get_child(n - 1).has_meta("row_gap"):
		var g := UiStyle.gap(0, UiStyle.S3)
		g.set_meta("row_gap", true)
		box.add_child(g)
	box.add_child(r)
	var g2 := UiStyle.gap(0, UiStyle.S3)
	g2.set_meta("row_gap", true)
	box.add_child(g2)


func _button(text: String, act: String, variation: String = "", min_h: float = 40.0) -> Button:
	var b := UiStyle.button(text, variation, min_h)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = false # (as wide as its label at least, like the web .btn: nowrap)
	b.pressed.connect(func() -> void: action.emit(act))
	return b


## A button of a segmented choice (style.css .seg: the active one in the accent).
func _seg_button(text: String) -> Button:
	var b := UiStyle.button(text, "TightButton")
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = false # (as wide as its label at least, like the web .btn: nowrap)
	return b


static func _set_active(b: Button, on: bool) -> void:
	if on:
		for st in ["normal", "hover", "pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(st, UiStyle.box(UiStyle.ACCENT_HI if st == "hover" else UiStyle.ACCENT, true, [UiStyle.S2, 0, UiStyle.S2, 0]))
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(c, UiStyle.ACCENT_INK)
	else:
		for st in ["normal", "hover", "pressed", "hover_pressed"]:
			b.remove_theme_stylebox_override(st)
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			b.remove_theme_color_override(c)


## A caption over a form control (style.css .form label).
func _field(caption: String, c: Control) -> VBoxContainer:
	var v := UiStyle.vbox(6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UiStyle.label(caption, "text", UiStyle.FS_S, UiStyle.TEXT_2))
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(c)
	return v


## Small wrapped text (style.css .hint / .note / .viewing).
func _text(s: String, color: Color) -> Label:
	var l := UiStyle.label(s, "text", UiStyle.FS_S, color, 0.0, false, false, false, 19)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 1
	return l


func _spin(lo: float, hi: float, step_v: float, value: float, decimals: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step_v
	s.value = value
	s.custom_arrow_step = 0.01 if decimals > 0 else 1.0
	s.select_all_on_focus = true
	if decimals > 0:
		s.get_line_edit().text = String.num(value, decimals)
	_style_edit(s.get_line_edit())
	return s


## style.css input: 13 px on a grey box, 32 px tall.
static func _style_edit(e: LineEdit) -> void:
	e.add_theme_font_override("font", UiStyle.font("text", UiStyle.FS_S, 0.0, true))
	e.add_theme_font_size_override("font_size", UiStyle.FS_S)
	e.add_theme_color_override("font_color", UiStyle.TEXT)
	e.add_theme_color_override("caret_color", UiStyle.TEXT)
	e.add_theme_stylebox_override("normal", UiStyle.box(UiStyle.BG_3, false, [UiStyle.S2, 7, UiStyle.S2, 7]))
	e.add_theme_stylebox_override("focus", UiStyle.ring(false, 1.0))
	e.add_theme_stylebox_override("read_only", UiStyle.box(UiStyle.BG_2, false, [UiStyle.S2, 7, UiStyle.S2, 7]))
	e.custom_minimum_size.y = 32


# ================================================================= layout

## Lay out for the parent's size: the dashboard on the right (or the bottom half), the overlay
## over the rest. Call it after a resize (it follows its own `resized` too).
func _layout() -> void:
	var s := size
	_narrow = s.x < NARROW_BELOW
	if _narrow:
		panel.position = Vector2(0, roundf(s.y / 2.0))
		panel.size = Vector2(s.x, s.y - panel.position.y)
	else:
		panel.position = Vector2(s.x - DASH_W, 0)
		panel.size = Vector2(DASH_W, s.y)
	var v := view_rect()
	overlay.position = v.position
	overlay.size = v.size
	var tag: Control = overlay.find_child("tag", true, false)
	if tag != null and tag.get_child_count() > 0:
		var l: Label = tag.get_child(0)
		UiStyle.style_label(l, "display_bold", UiStyle.FS_L if _narrow else UiStyle.FS_XL, UiStyle.TEXT, 0.06, true)


## The part of the screen the 3D view shows (not under the dashboard), in this control's pixels.
func view_rect() -> Rect2:
	var s := size
	if s.x < NARROW_BELOW:
		return Rect2(0, 0, s.x, roundf(s.y / 2.0))
	return Rect2(0, 0, maxf(0.0, s.x - DASH_W), s.y)


# ================================================================= the setup form

func show_setup() -> void:
	setup_box.visible = true
	run_box.visible = false
	overlay.visible = false
	scroll.scroll_vertical = 0
	_pad_at = null


func show_run() -> void:
	setup_box.visible = false
	run_box.visible = true
	scroll.scroll_vertical = 0
	_pad_at = null


func set_laps(n: int) -> void:
	laps = clampi(n, 1, 3)
	for i in laps_segs.size():
		_set_active(laps_segs[i], i + 1 == laps)


func set_walls(rule: String) -> void:
	walls = rule if Trainer.WALL_RULES.has(rule) else String(Trainer.DEFAULT_TRAINING.walls)
	for b in walls_segs:
		_set_active(b, String(b.get_meta("rule")) == walls)
	walls_hint.text = WALL_HINTS.get(walls, "")


## Indices (Tracks.defs() order) of the ticked tracks.
func ticked_tracks() -> Array[int]:
	var out: Array[int] = []
	for i in track_checks.size():
		if track_checks[i].checked:
			out.append(i)
	return out


## Tick exactly the tracks in `indices`.
func tick_tracks(indices: Array) -> void:
	for i in track_checks.size():
		track_checks[i].checked = indices.has(i)


## The form's settings (trainMode.js readSettings, without the tracks): numbers clamped as there.
func read_form() -> Dictionary:
	var hidden: Array = []
	for s in hidden_edit.text.split(","):
		var t := s.strip_edges()
		if t.is_valid_int() and int(t) > 0 and int(t) <= 64:
			hidden.append(int(t))
	for sb: SpinBox in [pop, mut]:
		if sb.get_line_edit().has_focus():
			sb.apply() # (typed but not entered yet)
	return {
		population_size = clampi(int(pop.value), 4, 400),
		mutation_rate = minf(1.0, maxf(0.005, mut.value)),
		hidden = hidden if not hidden.is_empty() else Trainer.DEFAULT_TRAINING.hidden.duplicate(),
		laps = laps,
		walls = walls,
	}


## "Continue from saved network": enabled and ticked when there is one; `info` beside it.
func set_seed(available: bool, info: String) -> void:
	seed_check.disabled = not available
	if not available:
		seed_check.checked = false
	seed_info.text = info


func set_seed_info(info: String) -> void:
	seed_info.text = info


# ================================================================= the run

## Pause / Resume, the active speed ("1" | "6" | "max"), the camera button's text.
func sync_buttons(paused: bool, speed: String, cam: String) -> void:
	pause_btn.text = "Resume" if paused else "Pause"
	for k: String in speed_segs:
		_set_active(speed_segs[k], k == speed)
	cam_btn.text = "Overview camera" if cam == "chase" else "Chase camera"


## The Max overlay (on: shown over the 3D view) and its speed line.
func set_max(on: bool, rate_text: String = "") -> void:
	overlay.visible = on
	if on:
		max_rate.text = rate_text


func set_note(text: String) -> void:
	note_label.text = text


## What the dashboard says about the viewed car: {index, clicked, alive, death_reason, fitness, speed}.
func set_viewing(shown: Dictionary) -> void:
	if shown.is_empty():
		viewing.text = ""
		return
	var state: String = "driving" if shown.alive else ("finished" if shown.death_reason == "finished" else "out (%s)" % shown.death_reason)
	viewing.text = "Viewing [b][color=#%s]car #%d[/color][/b] %s · %s · fitness %d · %d km/h" % [
		UiStyle.TEXT.to_html(false), int(shown.index) + 1, "(clicked)" if shown.clicked else "(leader)", state,
		roundi(float(shown.fitness)), roundi(float(shown.speed) * 3.6)]


## The stats (Trainer.live_stats()), for `tracks` (the session's BuiltTracks) and its wall rule.
func set_stats(s: Dictionary, tracks: Array, walls_rule: String) -> void:
	stat_values.generation.text = str(int(s.generation))
	stat_values.alive.text = "%d / %d" % [int(s.alive), int(s.size)]
	stat_values.best.text = str(roundi(float(s.best_fitness))) if s.best_fitness != null else "—"
	stat_values.leader.text = str(roundi(float(s.leader_fitness)))
	var pos: int = int(s.track_pos)
	var t: BuiltTrack = tracks[mini(pos, tracks.size() - 1)]
	stat_values.track.text = t.name + (" (%d/%d)" % [pos + 1, tracks.size()] if tracks.size() > 1 else "")
	stat_values.time.text = "%.1f s" % float(s.sim_time)
	var outs: PackedStringArray = []
	for k: String in s.deaths:
		outs.append("%s %d" % [k, int(s.deaths[k])])
	var deaths := " · ".join(outs)
	if walls_rule == "ride" and int(s.wall_cars) > 0:
		deaths = "%s · %d used a wall" % [deaths if deaths != "" else "all cars still driving", int(s.wall_cars)]
	run_line.text = "This run: " + (deaths if deaths != "" else "all cars still driving")
	_set_times(s.best_times, tracks)


## The AI best table: one row per track, its best lap (circuits) and finish.
func _set_times(best: Dictionary, tracks: Array) -> void:
	var rows: Array = []
	for t: BuiltTrack in tracks:
		var r: Variant = best.get(t.id)
		var lap: String = UiFormat.time(r.lap) if r is Dictionary and r.lap != null else "—"
		var fin: String = UiFormat.time(r.finish) if r is Dictionary and r.finish != null else "—"
		rows.append([t.name, lap if t.closed else "—", fin])
	var key := str(rows)
	if key == _times_key:
		return
	_times_key = key
	for c in times_box.get_children():
		times_box.remove_child(c)
		c.queue_free()
	times_box.add_child(_times_row(["AI best", "lap", "finish"], true))
	for r: Array in rows:
		times_box.add_child(_times_row(r, false))


func _times_row(cells: Array, head: bool) -> Control:
	var v := UiStyle.vbox(0)
	var h := UiStyle.hbox(UiStyle.S1)
	for i in 3:
		var l: Label
		if head:
			l = UiStyle.label(cells[i], "text", UiStyle.FS_S, UiStyle.TEXT_3, 0.0, false, false, false, 26)
		elif i == 0:
			l = UiStyle.label(cells[i], "text", UiStyle.FS_S, UiStyle.TEXT, 0.0, false, false, false, 26)
		else:
			l = UiStyle.label(cells[i], "display", UiStyle.FS_M, UiStyle.TEXT, 0.0, false, true, false, 26)
		if i == 0:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			l.custom_minimum_size.x = 1
		else:
			l.custom_minimum_size.x = 92
		h.add_child(l)
	v.add_child(h)
	var line := ColorRect.new()
	line.color = UiStyle.LINE
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(line)
	return v


func draw_net(net: Dictionary) -> void:
	net_view.draw_net(net)


func draw_chart(history: Array) -> void:
	chart.draw_history(history)


# ================================================================= gamepad

## The controls the pad highlight can go to (shown and enabled), Menu last (trainMode.js PadFocus).
func pad_controls() -> Array:
	var out: Array = []
	var all: Array = []
	if setup_box.visible:
		all.append_array(laps_segs)
		all.append_array(walls_segs)
		all.append_array(track_checks)
		all.append_array([seed_check, start_btn])
	else:
		all.append_array([pause_btn, speed_segs["1"], speed_segs["6"], speed_segs["max"], follow_btn, cam_btn,
			save_btn, watch_btn, race_btn, stop_btn])
	all.append(menu_btn)
	for c: Control in all:
		if c.is_visible_in_tree() and not (c is BaseButton and c.disabled) and not (c.get("disabled") == true):
			out.append(c)
	return out


## Gamepad: the d-pad / stick move the highlight to the nearest control that way, A presses
## it. The highlight starts on Start training (or the run's first button) and shows while the
## pad is the last input used. Returns true when A pressed something.
func handle_pad(inp: Object) -> bool:
	var ctrls := pad_controls()
	var pad := bool(inp.get("pad_active"))
	var at: Control = _pad_at if ctrls.has(_pad_at) else null
	if at == null and not ctrls.is_empty():
		at = start_btn if ctrls.has(start_btn) else ctrls[0]
	var dir: String = inp.call("nav_dir")
	var pressed := false
	if at != null and pad:
		if dir != "":
			var next := PadNav.nearest_control(at, dir, ctrls)
			if next != null:
				at = next
		if inp.call("consume", ["PadA"]):
			press(at)
			pressed = true
	_pad_at = at
	if not pad or at == null:
		_ring.set_target(null)
	elif at is BaseButton:
		_ring.set_target(at, true, 3.0)
		scroll.ensure_control_visible(at)
	else:
		_ring.set_target(at, false, 3.0, at.call("box_rect"))
		scroll.ensure_control_visible(at)
	return pressed


## Press a control as a click would (the pad's A, tests).
func press(c: Control) -> void:
	if c is BaseButton:
		if not (c as BaseButton).disabled:
			(c as BaseButton).pressed.emit()
	elif c != null and c.has_method("press"):
		c.call("press")


func clear_pad() -> void:
	_pad_at = null
	_ring.set_target(null)
