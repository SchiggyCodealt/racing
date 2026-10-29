class_name MenuInput
extends Node
## menu_input.gd
## ------------------------------------------------------------------
## Key and gamepad presses for the menu screens, with the web game's names (input.js), so
## the menu logic ports line for line:
##   keys      the physical key's web code: "ArrowUp", "KeyH", "Digit1", "Numpad1", "Minus",
##             "Equal", "NumpadSubtract", "NumpadAdd", "Slash", "Enter", "NumpadEnter", "Space",
##             "Backspace", "Escape", "Backquote" (the key under Esc, whatever it types),
##             "ShiftLeft" ...; a press with Shift held is also kept as
##             "Shift+<code>" (the menu's Shift+C). A typed "?" counts as "Slash" on any layout.
##   pad       "PadA" "PadB" "PadX" "PadY" "PadLB" "PadRB" "PadLT" "PadRT" "PadBack" (View)
##             "PadStart" (Menu) "PadL3" "PadR3" "PadUp" ... "PadHome"
##   menu dirs "NavUp" "NavDown" "NavLeft" "NavRight": the d-pad or the left stick (past 0.55,
##             held until back under 0.35), repeating while held (after 0.4 s, every 0.13 s).
## The interface the screens use (any object with these works, e.g. the game's own input
## once it is ported, or a fake in tests):
##   consume(codes: Array) -> bool   true once per press of any of the codes
##   nav_dir() -> String             "up" / "down" / "left" / "right" pressed this frame, or ""
##   clear_pressed()                 forget this frame's other presses
##   pad_active: bool                the gamepad was the last input used
## Gamepads are polled every frame (like the web's Gamepad API loop); keys come in through
## _input. Pad connect / disconnect notices go to `notice` (a Callable taking the text).

const PAD := {"navOn": 0.55, "navOff": 0.35, "repeatDelay": 0.4, "repeatEvery": 0.13}
const PAD_BUTTONS := {
	JOY_BUTTON_A: "PadA", JOY_BUTTON_B: "PadB", JOY_BUTTON_X: "PadX", JOY_BUTTON_Y: "PadY",
	JOY_BUTTON_LEFT_SHOULDER: "PadLB", JOY_BUTTON_RIGHT_SHOULDER: "PadRB", JOY_BUTTON_BACK: "PadBack",
	JOY_BUTTON_START: "PadStart", JOY_BUTTON_LEFT_STICK: "PadL3", JOY_BUTTON_RIGHT_STICK: "PadR3",
	JOY_BUTTON_DPAD_UP: "PadUp", JOY_BUTTON_DPAD_DOWN: "PadDown", JOY_BUTTON_DPAD_LEFT: "PadLeft",
	JOY_BUTTON_DPAD_RIGHT: "PadRight", JOY_BUTTON_GUIDE: "PadHome",
}
const NAV := {"up": "NavUp", "down": "NavDown", "left": "NavLeft", "right": "NavRight"}
const DPAD := {"up": "PadUp", "down": "PadDown", "left": "PadLeft", "right": "PadRight"}

var pressed := {}            # code -> true, since the last clear_pressed
var pad_active := false
var notice: Callable = Callable()
var _pad_down := {}          # pad codes held last frame
var _nav_held := {}          # nav code -> time of its next repeat
var _time := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.joy_connection_changed.connect(_on_joy)


## True while at least one gamepad is connected.
var pad_connected: bool:
	get:
		return not Input.get_connected_joypads().is_empty()


func consume(codes: Array) -> bool:
	for c in codes:
		if pressed.has(c):
			pressed.erase(c)
			return true
	return false


func nav_dir() -> String:
	for dir in NAV:
		if consume([NAV[dir]]):
			return dir
	return ""


func clear_pressed() -> void:
	pressed.clear()


## Count a press of `code` (tests, or a host feeding its own events).
func press(code: String) -> void:
	pressed[code] = true


func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		pad_active = false
		var code := key_code(e)
		if code != "":
			pressed[code] = true
			if e.shift_pressed:
				pressed["Shift+" + code] = true
		if e.unicode == 63 and code != "Slash": # "?" typed on a layout where it isn't on the slash key
			pressed["Slash"] = true
	elif e is InputEventMouseButton and e.pressed:
		pad_active = false


## The web (KeyboardEvent.code) name of a key event's physical key, or "".
static func key_code(e: InputEventKey) -> String:
	var k: Key = e.physical_keycode if e.physical_keycode != KEY_NONE else e.keycode
	if k >= KEY_A and k <= KEY_Z:
		return "Key" + char(k)
	if k >= KEY_0 and k <= KEY_9:
		return "Digit" + char(k)
	if k >= KEY_KP_0 and k <= KEY_KP_9:
		return "Numpad" + str(k - KEY_KP_0)
	match k:
		KEY_UP: return "ArrowUp"
		KEY_DOWN: return "ArrowDown"
		KEY_LEFT: return "ArrowLeft"
		KEY_RIGHT: return "ArrowRight"
		KEY_ENTER: return "Enter"
		KEY_KP_ENTER: return "NumpadEnter"
		KEY_SPACE: return "Space"
		KEY_BACKSPACE: return "Backspace"
		KEY_ESCAPE: return "Escape"
		KEY_MINUS: return "Minus"
		KEY_EQUAL: return "Equal"
		KEY_KP_SUBTRACT: return "NumpadSubtract"
		KEY_KP_ADD: return "NumpadAdd"
		KEY_SLASH: return "Slash"
		KEY_TAB: return "Tab"
		KEY_QUOTELEFT: return "Backquote" # (the key under Esc: the terminal, v6.7.0)
		KEY_SHIFT: return "ShiftRight" if e.location == KEY_LOCATION_RIGHT else "ShiftLeft"
	return ""


func _process(dt: float) -> void:
	_time += dt
	poll(_time)


## Read every connected pad: new button presses go to `pressed` like key presses; the
## d-pad and stick make the menu directions (with repeat). Several pads add up.
func poll(t: float) -> void:
	var held := {}
	var x := 0.0
	var y := 0.0
	for dev in Input.get_connected_joypads():
		for b in PAD_BUTTONS:
			if Input.is_joy_button_pressed(dev, b):
				held[PAD_BUTTONS[b]] = true
		if Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_LEFT) > 0.5:
			held["PadLT"] = true
		if Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_RIGHT) > 0.5:
			held["PadRT"] = true
		var ax := Input.get_joy_axis(dev, JOY_AXIS_LEFT_X)
		var ay := Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y)
		if absf(ax) > absf(x):
			x = ax
		if absf(ay) > absf(y):
			y = ay
	for dir in NAV:
		var v: float = -x if dir == "left" else x if dir == "right" else -y if dir == "up" else y
		var along: bool = absf(x) >= absf(y) if dir == "left" or dir == "right" else absf(y) > absf(x)
		var limit: float = PAD.navOff if _nav_held.has(NAV[dir]) else PAD.navOn
		if held.has(DPAD[dir]) or (v > limit and along):
			held[NAV[dir]] = true
	var used := false
	for c in held:
		if _pad_down.has(c):
			continue
		pressed[c] = true
		used = true
		if c.begins_with("Nav"):
			_nav_held[c] = t + PAD.repeatDelay
	for c in _nav_held.keys():
		if not held.has(c):
			_nav_held.erase(c)
		elif t >= _nav_held[c]:
			pressed[c] = true
			_nav_held[c] = maxf(_nav_held[c] + PAD.repeatEvery, t)
	_pad_down = held
	if used:
		pad_active = true


func _on_joy(device: int, connected: bool) -> void:
	if not notice.is_valid():
		return
	if connected:
		var name_ := Input.get_joy_name(device).get_slice("(", 0).strip_edges().left(40)
		notice.call("Gamepad connected%s · RT accelerate · LT brake · A handbrake · X nitro · View on the menu lists every button%s" % [
			": " + name_ if name_ != "" else "", "" if Input.is_joy_known(device) else " (unknown layout: some buttons may differ)"])
	else:
		if Input.get_connected_joypads().is_empty():
			pad_active = false
		notice.call("A gamepad was disconnected" if not Input.get_connected_joypads().is_empty() else "Gamepad disconnected")
