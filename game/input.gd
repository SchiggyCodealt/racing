class_name GameInput
extends MenuInput
## input.gd (port of web/src/game/input.js)
## ------------------------------------------------------------------
## Keyboard and gamepad input for the whole game. It is the menu's MenuInput (the web key
## names, the pad's menu directions with their repeat, the connect notice: ui/menu_input.gd)
## plus the race: Godot InputMap actions, created in code at start-up (setup_actions), for
## every race control and key, and the car controls built from them each physics step.
##
## Actions (keyboard by physical key, so WASD stays put on other layouts; Xbox button names):
##   steer_left / steer_right   ← → / A D, d-pad ← →        (digital: smoothed, see controls())
##   accelerate / brake         ↑ / W, ↓ / S
##   pad_steer_left / _right    left stick x                 (analogue: dead zone and curve)
##   pad_throttle / pad_brake   RT / LT                      (analogue)
##   handbrake                  Space, A
##   nitro                      Shift (either), X, RB        (held: burns the tank)
##   restart                    R, View (Back)
##   respawn                    Enter, Backspace, numpad Enter, B
##   ghost                      G, Y
##   menu                       Esc, Menu (Start)
##   menu_up / _down / _left / _right   arrows, W S A D, d-pad   (menu navigation; the menu
##   menu_accept / menu_back            Enter / Space, A; Esc / Backspace, B    screens of ui/
##   menu_car_next / menu_car_prev      C, RB; LB                  read the same keys by their
##   menu_controls / menu_settings      H, View; O                 web names through MenuInput)
##   menu_terminal                      ` (the key under Esc)      (v6.7.0; never in a race)
## A press of an action is kept like a key press (consume(["restart"])) until it is consumed
## or the frame's presses are cleared; held keys never repeat a press (the web ignored key
## auto-repeat too); the pad's menu directions repeat while held (0.4 s, then every 0.13 s).
##
## Steering feel (input.js): the car physics already rate-limits the steering rack and scales
## the full lock with speed, so the keyboard only shapes how a key press builds up: quick at
## parking speeds (7 /s), gentler at high speed (3.2 /s from 50 m/s: a short tap at 200 km/h
## is a small correction, holding the key reaches full steer in ~0.3 s) and a fast return to
## the centre (10 /s). The stick goes straight to the physics through its dead zone and curve
## (half travel ~ 0.30 steer); with keyboard and pad both in use each control takes the
## stronger input. pad_active: the pad was the last thing used (hints name its buttons).

## Steering build-up rates (steer units per second) and the return rate (input.js STEER_KEYS).
const STEER_KEYS := {"rate_slow": 7.0, "rate_fast": 3.2, "fast_speed": 50.0, "ret": 10.0}
## Gamepad tuning (input.js PAD): steer = ((|x| - dead) / (full - dead)) ^ curve; triggers
## ignore their rest noise below trig_dead.
const PAD_TUNE := {"dead": 0.12, "full": 0.96, "curve": 1.5, "trig_dead": 0.04}

## The actions: name -> {keys: [physical Key], buttons: [JoyButton], axes: [[JoyAxis, sign]]}.
const ACTIONS := {
	"steer_left": {"keys": [KEY_LEFT, KEY_A], "buttons": [JOY_BUTTON_DPAD_LEFT]},
	"steer_right": {"keys": [KEY_RIGHT, KEY_D], "buttons": [JOY_BUTTON_DPAD_RIGHT]},
	"accelerate": {"keys": [KEY_UP, KEY_W]},
	"brake": {"keys": [KEY_DOWN, KEY_S]},
	"pad_steer_left": {"axes": [[JOY_AXIS_LEFT_X, -1.0]]},
	"pad_steer_right": {"axes": [[JOY_AXIS_LEFT_X, 1.0]]},
	"pad_throttle": {"axes": [[JOY_AXIS_TRIGGER_RIGHT, 1.0]]},
	"pad_brake": {"axes": [[JOY_AXIS_TRIGGER_LEFT, 1.0]]},
	"handbrake": {"keys": [KEY_SPACE], "buttons": [JOY_BUTTON_A]},
	"nitro": {"keys": [KEY_SHIFT], "buttons": [JOY_BUTTON_X, JOY_BUTTON_RIGHT_SHOULDER]},
	"restart": {"keys": [KEY_R], "buttons": [JOY_BUTTON_BACK]},
	"respawn": {"keys": [KEY_ENTER, KEY_BACKSPACE, KEY_KP_ENTER], "buttons": [JOY_BUTTON_B]},
	"ghost": {"keys": [KEY_G], "buttons": [JOY_BUTTON_Y]},
	"menu": {"keys": [KEY_ESCAPE], "buttons": [JOY_BUTTON_START]},
	"menu_up": {"keys": [KEY_UP, KEY_W], "buttons": [JOY_BUTTON_DPAD_UP]},
	"menu_down": {"keys": [KEY_DOWN, KEY_S], "buttons": [JOY_BUTTON_DPAD_DOWN]},
	"menu_left": {"keys": [KEY_LEFT, KEY_A], "buttons": [JOY_BUTTON_DPAD_LEFT]},
	"menu_right": {"keys": [KEY_RIGHT, KEY_D], "buttons": [JOY_BUTTON_DPAD_RIGHT]},
	"menu_accept": {"keys": [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE], "buttons": [JOY_BUTTON_A]},
	"menu_back": {"keys": [KEY_ESCAPE, KEY_BACKSPACE], "buttons": [JOY_BUTTON_B]},
	"menu_car_next": {"keys": [KEY_C], "buttons": [JOY_BUTTON_RIGHT_SHOULDER]},
	"menu_car_prev": {"buttons": [JOY_BUTTON_LEFT_SHOULDER]},
	"menu_controls": {"keys": [KEY_H, KEY_SLASH], "buttons": [JOY_BUTTON_BACK]},
	"menu_settings": {"keys": [KEY_O]},
	"menu_terminal": {"keys": [KEY_QUOTELEFT]},
}
## Analogue actions: no dead zone of their own (the curve above has one).
const ANALOG := ["pad_steer_left", "pad_steer_right", "pad_throttle", "pad_brake"]

## The keyboard's smoothed steering (-1..1, + = left).
var steer := 0.0
## The pads' analogue state after the last poll: steer (curved, + = left), throttle, brake.
var pad_steer := 0.0
var pad_throttle := 0.0
var pad_brake := 0.0
## Test hooks (the end-to-end runs drive the real game with them): actions held as if their
## keys were down, and `feed`, called with the car's speed at the start of every controls()
## (one physics step), which may set held, pad_steer, pad_throttle and pad_brake.
var held := {}
var feed: Callable = Callable()


func _init() -> void:
	setup_actions()
	process_priority = -100 # (poll the pads before the modes read them)


## Create the actions in the InputMap (once; existing ones are left as they are, so a
## project setting or a later key-binding screen can override them).
static func setup_actions() -> void:
	for a: String in ACTIONS:
		if InputMap.has_action(a):
			continue
		InputMap.add_action(a, 0.0 if ANALOG.has(a) else 0.5)
		var def: Dictionary = ACTIONS[a]
		for k: Key in def.get("keys", []):
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(a, e)
		for b: JoyButton in def.get("buttons", []):
			var e := InputEventJoypadButton.new()
			e.button_index = b
			e.device = -1 # (every pad)
			InputMap.action_add_event(a, e)
		for ax: Array in def.get("axes", []):
			var e := InputEventJoypadMotion.new()
			e.axis = ax[0]
			e.axis_value = ax[1]
			e.device = -1
			InputMap.action_add_event(a, e)


## Stick axis -> steer amount (same sign), with the dead zone and response curve.
static func stick_curve(v: float) -> float:
	var a := absf(v)
	if not (a > PAD_TUNE.dead):
		return 0.0
	return signf(v) * pow(minf(1.0, (a - PAD_TUNE.dead) / (PAD_TUNE.full - PAD_TUNE.dead)), PAD_TUNE.curve)


## Trigger value 0..1 without its rest noise.
static func trigger_value(v: float) -> float:
	return minf(1.0, (v - PAD_TUNE.trig_dead) / (1.0 - PAD_TUNE.trig_dead)) if v > PAD_TUNE.trig_dead else 0.0


func _input(e: InputEvent) -> void:
	super(e) # (the web key names for the menu screens)
	if e.is_echo() or not e.is_pressed() or e is InputEventMouse:
		return
	for a: String in ACTIONS:
		if not ANALOG.has(a) and e.is_action_pressed(a):
			pressed[a] = true


## True while action `a` is held (keyboard or pad, or the test hook).
func is_down(a: String) -> bool:
	return held.has(a) or Input.is_action_pressed(a)


## Forget held keys (the window lost focus, a mode starts).
func release_all() -> void:
	held.clear()
	steer = 0.0


func poll(t: float) -> void:
	super(t)
	# the analogue stick and triggers through their actions (raw: the curve has the dead zone)
	var x := Input.get_action_raw_strength("pad_steer_right") - Input.get_action_raw_strength("pad_steer_left")
	var s := stick_curve(-x) # stick right = +x; steer + = left
	var th := trigger_value(Input.get_action_raw_strength("pad_throttle"))
	var br := trigger_value(Input.get_action_raw_strength("pad_brake"))
	if (s != 0.0 and pad_steer == 0.0) or (th != 0.0 and pad_throttle == 0.0) or (br != 0.0 and pad_brake == 0.0):
		pad_active = true
	pad_steer = s
	pad_throttle = th
	pad_brake = br


## Car controls for this physics step (input.js controls): `speed` is the car's speed in m/s
## (shapes the steering build-up). Fills and returns `out`.
func controls(dt: float, out: Car.Controls, speed: float = 0.0) -> Car.Controls:
	if feed.is_valid():
		feed.call(speed)
	var target := (1.0 if is_down("steer_left") else 0.0) - (1.0 if is_down("steer_right") else 0.0)
	var rate: float
	if target == 0.0 or target * steer < 0.0:
		rate = STEER_KEYS.ret # centring or reversing: quick
	else:
		var f := clampf(speed / STEER_KEYS.fast_speed, 0.0, 1.0)
		rate = STEER_KEYS.rate_slow + (STEER_KEYS.rate_fast - STEER_KEYS.rate_slow) * f
	var d := target - steer
	steer += signf(d) * minf(absf(d), rate * dt)
	# keyboard and pad together: each control takes the stronger input
	out.steer = pad_steer if absf(pad_steer) > absf(steer) else steer
	out.throttle = maxf(1.0 if is_down("accelerate") else 0.0, pad_throttle) - maxf(1.0 if is_down("brake") else 0.0, pad_brake)
	out.handbrake = is_down("handbrake")
	out.nitro = 1.0 if is_down("nitro") else 0.0 # held: burns the tank (car.gd)
	return out


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		steer = 0.0 # (Godot releases the held keys itself)
