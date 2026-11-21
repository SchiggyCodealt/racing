class_name TrialScreen
extends "res://ui/dialog_screen.gd"
## trial_screen.gd (v6.34.0): the trial that fits a supercharger level (v6.35.0: or an aero tune
## level, v6.40.0: or a nitro tune level; sim/tune_trial.gd has the rules) over the car page.
## ------------------------------------------------------------------
## A row of arrow plates and a time bar. The row shows for a moment ("Get ready"), then the clock
## runs ("Go"): press the arrows in order with the arrow keys, WASD, the d-pad or the four arrow
## buttons under the bar (a click). Each right press turns its plate green; a wrong one, the clock
## running out, Esc, the pad's B or the Give up button end it as a miss (the plate turns red).
## The result stays on the screen for RESULT_TIME seconds (Enter, Space or A skips it), then the
## screen closes and `finished(won)` tells the game, which fits the level or pays half back.
## The trial runs on step(dt) (called every frame; tests call it themselves).
##
##   start(title, line, level, seed = -1)   open the screen and start a trial
##   trial -> TuneTrial;  result_left -> seconds the result still shows
##   step(dt);  handle_keys(inp);  press(dir)  (the arrow buttons; tests)
##   status_text -> "GET READY" | "GO" | "FITTED" | "MISSED: WRONG ARROW" | ...

signal finished(won: bool)

const RESULT_TIME := 1.6
const PLATE := 58.0
const PLATE_GAP := 10.0
const HINT := "Arrow keys, WASD or the d-pad (or click the arrows) · Esc gives up: a miss"
const KEYS := {
	"up": ["ArrowUp", "KeyW", "PadUp", "NavUp"],
	"down": ["ArrowDown", "KeyS", "PadDown", "NavDown"],
	"left": ["ArrowLeft", "KeyA", "PadLeft", "NavLeft"],
	"right": ["ArrowRight", "KeyD", "PadRight", "NavRight"],
}

var trial: TuneTrial = null
var result_left := 0.0
var status_text := ""
var running := false

var _line: Label
var _row: Control
var _bar: Control
var _status: Label
var _hint: Label
var _arrow_btns: Dictionary = {}
var _last_state := ""
var _sent := false


func _init() -> void:
	super("Fit it")
	max_width = 760.0
	var gl: Label = close_button.get_meta("label")
	gl.text = "Give up"
	close_button.custom_minimum_size.x = close_button.get_child(0).get_combined_minimum_size().x + 2 * UiStyle.S3
	close_button.tooltip_text = "Give up: a miss, half the price back"
	body.add_child(UiStyle.gap(0, UiStyle.S2))
	_line = UiStyle.label("", "text", UiStyle.FS_S, UiStyle.TEXT_2, 0.0, false, false, false, 19)
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.custom_minimum_size.x = 1
	body.add_child(_line)
	body.add_child(UiStyle.gap(0, UiStyle.S5))
	_row = Control.new()
	_row.custom_minimum_size = Vector2(1, PLATE + 8)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.draw.connect(_draw_row)
	body.add_child(_row)
	body.add_child(UiStyle.gap(0, UiStyle.S4))
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(1, 10)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	body.add_child(_bar)
	body.add_child(UiStyle.gap(0, UiStyle.S4))
	_status = UiStyle.label("", "display_bold", UiStyle.FS_XL, UiStyle.TEXT, 0.06, true, false, false, UiStyle.FS_XL)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_status)
	body.add_child(UiStyle.gap(0, UiStyle.S4))
	var pads := UiStyle.hbox(UiStyle.S2, BoxContainer.ALIGNMENT_CENTER)
	for d: String in ["left", "up", "down", "right"]:
		var b := ArrowButton.new()
		b.dir = d
		b.tooltip_text = "%s (%s)" % [d.capitalize(), _key_names(d)]
		b.pressed.connect(press.bind(d))
		pads.add_child(b)
		_arrow_btns[d] = b
	body.add_child(pads)
	body.add_child(UiStyle.gap(0, UiStyle.S3))
	_hint = UiStyle.label("", "text", UiStyle.FS_S, UiStyle.TEXT_3, 0.0, false, false, false, 18)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS # (one line: it fits from 700 px wide)
	_hint.clip_text = true
	body.add_child(_hint)
	set_process(false)


## Open the screen and start a trial of `level` (title: "Fit the supercharger"; line: what is at stake).
func start(title: String, line: String, level: int, seed_: int = -1) -> void:
	var tl: Label = _title_label()
	if tl != null:
		tl.text = title
	_line.text = line
	_hint.text = HINT # (set here, not in _init: a wrapped label shaped before it has a width stays tall)
	trial = TuneTrial.new(level, seed_)
	result_left = 0.0
	running = true
	_sent = false
	_last_state = ""
	open()
	_update()
	set_process(true)
	UiSound.play("count")


func _process(dt: float) -> void:
	step(dt)


## Advance the trial by `dt` seconds (the clock, the result's pause, then closing).
func step(dt: float) -> void:
	if trial == null or not visible:
		return
	if running:
		trial.tick(dt)
		if trial.is_over():
			_end()
	elif result_left > 0.0:
		result_left -= dt
		if result_left <= 0.0:
			_finish()
	_update()


## Arrow `dir` pressed (keys, pad, the arrow buttons).
func press(dir: String) -> void:
	if not running:
		return
	var r := trial.press(dir)
	if r == "ok":
		UiSound.play("key")
	if trial.is_over():
		_end()
	_update()


func handle_keys(inp: Object) -> void:
	if not running:
		if result_left > 0.0 and inp.consume(["Enter", "Space", "NumpadEnter", "PadA", "Escape", "PadB"]):
			_finish()
		return
	if inp.consume(["Escape", "PadB", "PadStart"]):
		give_up()
		return
	for d: String in KEYS:
		if inp.consume(KEYS[d]):
			# one press of a direction can come as two codes (the d-pad is also a menu direction)
			while inp.consume(KEYS[d]):
				pass
			press(d)
			if not running:
				return


## Leave the trial: a miss.
func give_up() -> void:
	if running:
		trial.quit()
		_end()
		_update()


## Esc, the Give up button, a click beside the panel: a miss while the trial runs; afterwards the
## result goes straight to the game.
func close() -> void:
	if running:
		give_up()
	elif visible and result_left > 0.0:
		_finish()


## A click beside the panel: nothing while the trial runs (no miss by accident); afterwards it
## closes the result.
func _on_backdrop_input(e: InputEvent) -> void:
	if not running:
		super._on_backdrop_input(e)


func _end() -> void:
	running = false
	result_left = RESULT_TIME
	UiSound.play("blowoff" if trial.state == "won" else "ui_error")


func _finish() -> void:
	result_left = 0.0
	set_process(false)
	visible = false
	closed.emit()
	if not _sent and trial != null:
		_sent = true
		finished.emit(trial.state == "won")


func _update() -> void:
	if trial == null:
		return
	var st := trial.state
	match st:
		"ready":
			status_text = "GET READY"
			_status.add_theme_color_override("font_color", UiStyle.TEXT_2)
		"go":
			status_text = "GO"
			_status.add_theme_color_override("font_color", UiStyle.ACCENT)
		"won":
			status_text = "FITTED"
			_status.add_theme_color_override("font_color", UiStyle.GOOD)
		_:
			status_text = "MISSED: %s" % {"wrong": "WRONG ARROW", "time": "OUT OF TIME", "quit": "GAVE UP"}.get(trial.why, "MISSED")
			_status.add_theme_color_override("font_color", UiStyle.BAD)
	if st == "go" and _last_state == "ready":
		UiSound.play("go")
	_last_state = st
	_status.text = status_text
	for d: String in _arrow_btns:
		(_arrow_btns[d] as Button).disabled = not running
	_row.queue_redraw()
	_bar.queue_redraw()


func _title_label() -> Label:
	var head: Node = body.get_child(0)
	return head.get_child(0) as Label if head != null and head.get_child_count() > 0 else null


static func _key_names(d: String) -> String:
	return {"up": "Up, W, d-pad up", "down": "Down, S, d-pad down", "left": "Left, A, d-pad left", "right": "Right, D, d-pad right"}[d]


# ---------------------------------------------------------------- drawing

func _draw_row() -> void:
	if trial == null:
		return
	var n := trial.sequence.size()
	var w := _row.size.x
	var plate := minf(PLATE, (w - (n - 1) * PLATE_GAP) / maxf(1, n))
	var total := n * plate + (n - 1) * PLATE_GAP
	var x0 := (w - total) * 0.5
	var y := (_row.size.y - plate) * 0.5
	for k in n:
		var r := Rect2(x0 + k * (plate + PLATE_GAP), y, plate, plate)
		var fill := UiStyle.BG_3
		var ink := UiStyle.TEXT_2
		var edge := Color(0, 0, 0, 0)
		if k < trial.done:
			fill = UiStyle.GOOD
			ink = UiStyle.ACCENT_INK
		elif k == trial.done and trial.state == "missed":
			fill = UiStyle.BAD
			ink = UiStyle.ACCENT_INK
		elif k == trial.done and trial.state == "go":
			edge = UiStyle.ACCENT
			ink = UiStyle.TEXT
			fill = UiStyle.BG_4
		elif trial.state == "won":
			fill = UiStyle.GOOD
			ink = UiStyle.ACCENT_INK
		_skewed(_row, r, fill)
		if edge.a > 0.0:
			_skewed_outline(_row, r, edge, 3.0)
		draw_arrow(_row, r.get_center(), plate * 0.56, trial.sequence[k], ink)


func _draw_bar() -> void:
	if trial == null:
		return
	var w := _bar.size.x
	var h := _bar.size.y
	_bar.draw_rect(Rect2(0, 0, w, h), UiStyle.BG_4)
	var share := clampf(trial.left() / maxf(0.001, trial.limit), 0.0, 1.0)
	var col := UiStyle.ACCENT if share > 0.25 else UiStyle.BAD
	if trial.state == "won":
		col = UiStyle.GOOD
	elif trial.state == "ready":
		col = UiStyle.TEXT_3
	_bar.draw_rect(Rect2(0, 0, w * share, h), col)


## An arrow pointing `dir` ("up" ...), `s` across, centred on `c`, drawn on `ci`.
static func draw_arrow(ci: CanvasItem, c: Vector2, s: float, dir: String, col: Color) -> void:
	# pointing up, then turned: a head and a stem
	var pts := PackedVector2Array([
		Vector2(0, -0.5), Vector2(0.45, -0.02), Vector2(0.17, -0.02), Vector2(0.17, 0.5),
		Vector2(-0.17, 0.5), Vector2(-0.17, -0.02), Vector2(-0.45, -0.02)])
	var ang: float = {"up": 0.0, "right": PI * 0.5, "down": PI, "left": -PI * 0.5}.get(dir, 0.0)
	var out := PackedVector2Array()
	for p in pts:
		out.append(c + (p * s).rotated(ang))
	ci.draw_colored_polygon(out, col)


static func _skewed(ci: CanvasItem, r: Rect2, col: Color) -> void:
	ci.draw_colored_polygon(_skew_pts(r), col)


static func _skewed_outline(ci: CanvasItem, r: Rect2, col: Color, width: float) -> void:
	var p := _skew_pts(r)
	p.append(p[0])
	ci.draw_polyline(p, col, width, true)


static func _skew_pts(r: Rect2) -> PackedVector2Array:
	var k := UiStyle.SKEW * r.size.y * 0.5
	return PackedVector2Array([
		Vector2(r.position.x + k, r.position.y), Vector2(r.end.x + k, r.position.y),
		Vector2(r.end.x - k, r.end.y), Vector2(r.position.x - k, r.end.y)])


## One of the four arrow buttons under the bar (a click presses that arrow).
class ArrowButton extends Button:
	var dir := "up"

	func _init() -> void:
		theme_type_variation = "ChipButton"
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(56, 40)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _draw() -> void:
		var col := UiStyle.TEXT_3 if disabled else (UiStyle.TEXT if is_hovered() else UiStyle.TEXT_2)
		TrialScreen.draw_arrow(self, size * 0.5, minf(size.x, size.y) * 0.5, dir, col)
