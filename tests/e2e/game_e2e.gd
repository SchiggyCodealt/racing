extends SceneTree
## game_e2e.gd: end-to-end runs of the real game (main.tscn) under a virtual display.
## ------------------------------------------------------------------
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path <copy> --resolution 1280x720 \
##       --script res://tests/e2e/game_e2e.gd -- scenario=<name> save=/tmp/x.json gfx=low [out=/dir] ...
## The game runs as the player sees it: keys go in as InputEvents (Input.parse_input_event) to
## the same handlers a keyboard reaches, the gamepad's menu presses through the input's press()
## and its race buttons / sticks as joypad InputEvents. A race is driven by sim/autopilot.gd
## feeding the input layer once per physics step (GameInput.feed: the stick and trigger values
## and the nitro button), so the cars go through the game's own controls(), race, score,
## recorder and save code. save=<file> keeps the player's real save file out of it.
##
## Scenarios (scenario=...):
##   races     tracks=a,b,.. cars=a,b,.. (default every car): pick the track and car with the menu
##             keys, Drive (Enter), drive the medal autopilot of the author time to the finish;
##             checks the finish panel (time = the author time, author medal), the saved record,
##             score and ghost, then R: the new ghost replays the run (within 3 cm of the car),
##             then Esc: the menu's tile and panel show the record, score and ghost.
##   modes     loads an AI network file (Load network's code path), Race the AI ghost and Watch the
##             AI by clicking their buttons, respawn (Enter) and restart (R) in Drive, pad buttons
##             in a race (joypad events through the InputMap actions), G toggles the ghost.
##   menu      keyboard and gamepad navigation of the menu, Controls and Settings screens.
##   settings1 / settings2   change settings with the keyboard on the Settings screen; the second
##             run (a new process on the same save file) checks they persisted and were applied.
##   shots     out=<dir>: menu, driving with nitro, finish panel and the menu after it (PNGs).
##   perf      script time per frame of a race (Drive with the autopilot, real time).
## Prints "ok"/"FAIL" lines and "E2E <scenario>: n passed, m failed"; quits with 1 on a failure.

const AiLink := preload("res://game/ai_link.gd")
const PlayMode := preload("res://modes/play_mode.gd")

var app: GameApp
var opts := {}
var scenario := ""
var out_dir := "/tmp/godot-game/shots"
var passed := 0
var failed := 0
var _pilot: Autopilot = null


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() > 1 else "1"
	scenario = str(opts.get("scenario", "races"))
	out_dir = str(opts.get("out", out_dir))
	DirAccess.make_dir_recursive_absolute(out_dir)
	var scene: PackedScene = load("res://main.tscn")
	app = scene.instantiate()
	root.add_child(app)
	_main.call_deferred()


func _main() -> void:
	await frames(3)
	await wait_until(func() -> bool: return not app.building_track(), 60.0)
	var t0 := Time.get_ticks_msec()
	match scenario:
		"races":
			await races()
		"modes":
			await modes()
		"menu":
			await menu_nav()
		"settings1":
			await settings_set()
		"settings2":
			await settings_check()
		"shots":
			await shots()
		"perf":
			await perf()
		_:
			check(false, "unknown scenario " + scenario)
	print("E2E %s: %d passed, %d failed (%.1f s)" % [scenario, passed, failed, (Time.get_ticks_msec() - t0) / 1000.0])
	Engine.time_scale = 1.0
	quit(1 if failed > 0 or passed == 0 else 0)


# ---------------------------------------------------------------- helpers

func check(ok: bool, msg: String) -> bool:
	print("%s %s" % ["ok  " if ok else "FAIL", msg])
	if ok:
		passed += 1
	else:
		failed += 1
	return ok


func frames(n: int) -> void:
	for i in n:
		await process_frame


## Wait until cond() is true (checked every frame) or `timeout` seconds of real time pass.
func wait_until(cond: Callable, timeout: float) -> bool:
	var end := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not cond.call():
		if Time.get_ticks_msec() > end:
			return false
		await process_frame
	return true


## A press and release of physical key `k` (with Shift held when `shift`).
func key(k: Key, shift: bool = false) -> void:
	if shift:
		_key_event(KEY_SHIFT, true, false)
	_key_event(k, true, shift)
	await frames(2)
	_key_event(k, false, shift)
	if shift:
		_key_event(KEY_SHIFT, false, false)
	await frames(1)


func _key_event(k: Key, down: bool, shift: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	e.shift_pressed = shift
	Input.parse_input_event(e)


## A gamepad button press and release (device 0) through the InputMap.
func pad_button(b: JoyButton) -> void:
	for down: bool in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = b
		e.pressed = down
		e.device = 0
		Input.parse_input_event(e)
		await frames(2)


func pad_axis(axis: JoyAxis, v: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = v
	e.device = 0
	Input.parse_input_event(e)


## Click the middle of a Control with the left mouse button (scrolled into view first, as a
## player would).
func click(c: Control) -> void:
	var up := c.get_parent()
	while up != null and not (up is ScrollContainer):
		up = up.get_parent()
	if up != null:
		(up as ScrollContainer).ensure_control_visible(c)
		await frames(2)
	# (the interface layer is scaled: the screen transform maps the control to window pixels)
	var p := c.get_screen_transform() * (c.size * 0.5)
	for down: bool in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = p
		e.global_position = p
		Input.parse_input_event(e)
		await frames(2)


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, name]
	img.save_png(path)
	print("shot ", path, " ", img.get_size())


## The key that picks track `i` on the menu (1-9, 0, -, =).
static func track_key(i: int) -> Key:
	if i < 9:
		return (KEY_1 + i) as Key
	return [KEY_0, KEY_MINUS, KEY_EQUAL][i - 9]


## Pick track `id` and car `car` on the menu with the keyboard.
func pick(track_id: String, car: String) -> void:
	var i := Tracks.ids().find(track_id)
	await key(track_key(i))
	var tries := 0
	while UiData.picked_car() != car and tries < 8:
		await key(KEY_C)
		tries += 1
	await wait_until(func() -> bool: return not app.building_track(), 60.0)


## Drive the race in progress with the medal autopilot (aLat, lookK), feeding the input layer.
func autopilot(a_lat: float, look_k: float, nitro: bool = true) -> void:
	var m: Node = app.mode
	_pilot = Autopilot.medal(m.get("track"), a_lat, look_k, nitro)
	var inp := app.input
	inp.feed = func(_speed: float) -> void:
		var mode: Node = app.mode
		if mode == null or mode.get("car") == null:
			return
		var c: Car.Controls = _pilot.drive(mode.get("car"))
		inp.pad_steer = c.steer
		inp.pad_throttle = maxf(0.0, c.throttle)
		inp.pad_brake = maxf(0.0, -c.throttle)
		if c.nitro > 0.0:
			inp.held["nitro"] = true
		else:
			inp.held.erase("nitro")


func stop_autopilot() -> void:
	app.input.feed = Callable()
	app.input.held.clear()
	app.input.pad_steer = 0.0
	app.input.pad_throttle = 0.0
	app.input.pad_brake = 0.0


func fast(on: bool) -> void:
	Engine.time_scale = float(opts.get("speed", "12")) if on else 1.0
	app.max_frame = 1.0 if on else 0.1


# ---------------------------------------------------------------- races

func races() -> void:
	var tracks: PackedStringArray = str(opts.get("tracks", "rookie-oval,seaside-stunts,mountain-pass")).split(",")
	var cars: PackedStringArray = str(opts.get("cars", ",".join(Cars.ids()))).split(",")
	for tid in tracks:
		for cid in cars:
			await one_race(tid, cid)


func one_race(tid: String, cid: String) -> void:
	var tag := "%s / %s" % [tid, cid]
	var track := Tracks.build(tid)
	var medals := Medals.medal_times(track, cid)
	check(not medals.is_empty(), "%s: medal times exist" % tag)
	var run: Dictionary = medals.get("run", {"aLat": 24.0, "lookK": 1.0})
	await pick(tid, cid)
	check(app.mode == app.menu_mode and app.ui.menu.selected_track == Tracks.ids().find(tid) and UiData.picked_car() == cid,
		"%s: picked on the menu with the keys" % tag)
	await key(KEY_ENTER)
	var m: Node = app.mode
	if not check(m != app.menu_mode and m.get("track") == track and str(m.get("car_def").id) == cid, "%s: Enter drives" % tag):
		return
	check(app.world.track == track and app.ui.hud.visible and not app.ui.menu.visible, "%s: the race shows its track and the HUD" % tag)
	autopilot(float(run.aLat), float(run.lookK))
	fast(true)
	var done := await wait_until(func() -> bool: return m.get("phase") == "finished", 900.0)
	fast(false)
	stop_autopilot()
	if not check(done, "%s: the autopilot finishes" % tag):
		return
	var race: RaceState = m.get("race")
	var fs: Dictionary = m.get("finish_state")
	var t := race.finish_time
	check(absf(t - float(medals.author)) < 0.0005, "%s: finish %s = the author time %s (same physics, input and steps as the medal run)" % [
		tag, RaceState.format_time(t), RaceState.format_time(float(medals.author))])
	check(fs.get("medal", {}).get("got") == "author" and fs.has("record") and app.ui.hud.panel_open, "%s: finish panel: author medal, new personal best" % tag)
	var rec := SaveData.get_record(tid, cid)
	check(not rec.is_empty() and absf(float(rec.time) - t) < 1e-9 and (rec.splits as Array).size() == race.splits.size(), "%s: record and splits saved" % tag)
	var sc := SaveData.get_best_score(tid, cid)
	var score: ScoreState = m.get("score")
	if score.total > 0.0:
		check(not sc.is_empty() and is_equal_approx(float(sc.score), score.total), "%s: best score %s saved" % [tag, ScoreState.format_points(score.total)])
	else: # (as the web game: a score of 0 is never a best score)
		check(sc.is_empty(), "%s: score 0 (the run grinds the walls): no best score saved" % tag)
	var g := Replay.unpack_ghost(SaveData.load_ghost(tid, cid), track, race.laps, cid)
	check(not g.is_empty() and absf(float(g.time) - t) < 1e-9, "%s: ghost saved (%d samples)" % [tag, (g.get("steps", PackedInt32Array()) as PackedInt32Array).size()])
	check(str(fs.get("ghost_note", "")).begins_with("Ghost saved"), "%s: finish panel says the ghost is saved" % tag)
	# R: race again against the new ghost; it replays the run within a few cm of the same drive
	await key(KEY_R)
	check(m.get("phase") == "countdown" and m.get("race_step") == 0 and not app.ui.hud.panel_open, "%s: R restarts" % tag)
	check(m.get("pb") != null, "%s: the new best run is raced as the ghost" % tag)
	autopilot(float(run.aLat), float(run.lookK))
	fast(true)
	var worst := [0.0]
	var seen := [0]
	var probe := func() -> bool:
		var pb: Replay.GhostPlayer = m.get("pb")
		var c: Car = m.get("car")
		var s: int = m.get("race_step")
		if s > 0 and pb != null and pb.pose(float(s)):
			worst[0] = maxf(worst[0], Vector3(pb.car.x - c.x, pb.car.y - c.y, pb.car.z - c.z).length())
			seen[0] += 1
		return s > 60 * 25 or m.get("phase") == "finished"
	await wait_until(probe, 300.0)
	fast(false)
	stop_autopilot()
	check(seen[0] > 20 and worst[0] < 0.03, "%s: the ghost replays the run: %d frames, at most %.3f m from the car" % [tag, seen[0], worst[0]])
	check(m.get("pb_model").visible == false or m.get("pb_model").get("_fade") <= 1.0, "%s: ghost drawn faded on top of the car" % tag)
	# Esc: the menu shows the record, the score and the ghost
	await key(KEY_ESCAPE)
	await frames(2)
	check(app.mode == app.menu_mode and app.ui.menu.visible and not app.ui.hud.visible, "%s: Esc goes back to the menu" % tag)
	var r: Variant = UiData.record(tid, cid)
	check(r != null and absf(float(r.time) - t) < 1e-9 and UiData.has_ghost(tid, cid)
		and UiData.best_score(tid, cid) == (int(score.total) if score.total > 0.0 else -1),
		"%s: the menu's data: best %s, score %d, ghost saved" % [tag, RaceState.format_time(t), UiData.best_score(tid, cid)])
	var tile: Control = app.ui.menu.get("_tiles")[Tracks.ids().find(tid)]
	check(str(tile.get("best_text")) == UiFormat.time(t) and str(tile.get("medal")) == "author", "%s: the track tile shows %s and the author medal" % [tag, tile.get("best_text")])


# ---------------------------------------------------------------- modes

func modes() -> void:
	var tid := "rookie-oval"
	await pick(tid, "racer")
	# the AI network: Load network's code path with a file in the web game's format
	var net_path := str(opts.get("net", "/tmp/godot-game/web_net.json"))
	var err := app.load_network_file(net_path)
	check(err == "" and not app.network.is_empty(), "load a web network file: %s" % (err if err != "" else "ok"))
	check(UiData.ai_status().ready and not app.ui.menu.get("_ghost_btn").disabled and not app.ui.menu.get("_watch_btn").disabled,
		"the menu's AI buttons are enabled")
	check(SaveData.load_network() != null, "the loaded network is remembered in the save file")
	var bad := "/tmp/godot-game/bad_net.json"
	var f := FileAccess.open(bad, FileAccess.WRITE)
	f.store_string("{\"sizes\": [11, 8, 2], \"weights\": [[0]], \"biases\": [[0]]}")
	f.close()
	var err2 := app.load_network_file(bad)
	check(err2 != "" and app.message.visible, "a v1 network is refused with a message: %s" % err2)
	await key(KEY_ENTER)
	check(not app.message.visible and app.mode == app.menu_mode, "Enter closes the message (and doesn't drive)")
	# save the network to a file and read it back
	var saved := "/tmp/godot-game/saved_net.json"
	check(app.save_network_file(saved) == "" and AiLink.parse_network_file(JSON.parse_string(FileAccess.get_file_as_string(saved))).has("net"),
		"Save network writes a file that loads back")

	# Race the AI ghost: click the button
	await click(app.ui.menu.get("_ghost_btn"))
	var m: Node = app.mode
	if check(m != app.menu_mode and m.get("with_ghost") == true and m.get("ghost_model") != null, "Race the AI ghost (clicked)"):
		autopilot(24.0, 1.3)
		fast(true)
		await wait_until(func() -> bool: return (m.get("race") as RaceState).next_gate >= 2, 120.0)
		fast(false)
		var g: Dictionary = m.get("ghost")
		check((g.race as RaceState).next_gate > 0 or (g.car as Car).prog > 50.0, "the AI ghost drives (progress %.0f samples)" % (g.car as Car).prog)
		check(str(m.get("ghost_text")).begins_with("AI ghost"), "the HUD compares with the AI ghost: %s" % m.get("ghost_text"))
		stop_autopilot()
		await key(KEY_ESCAPE)
	# Watch the AI
	await click(app.ui.menu.get("_watch_btn"))
	m = app.mode
	if check(m != app.menu_mode and m.get("driver") == "ai", "Watch the AI (clicked)"):
		fast(true)
		await wait_until(func() -> bool: return (m.get("race") as RaceState).time > 20.0, 120.0)
		fast(false)
		await frames(2)
		check((m.get("car") as Car).prog > 100.0, "the AI drives: %.0f samples in 20 s" % (m.get("car") as Car).prog)
		check(m.get("rays").visible and app.ui.hud.watch_panel.visible, "sensor rays and the network panel show")
		check(app.ui.hud.get("_nitro").visible == false, "no nitro gauge for the AI")
		await shot("watch_ai")
		await key(KEY_ESCAPE)
	# Drive: respawn, restart, the gamepad's race buttons and stick, the ghost toggle
	await key(KEY_ENTER)
	m = app.mode
	autopilot(24.0, 1.3)
	fast(true)
	await wait_until(func() -> bool: return (m.get("race") as RaceState).next_gate >= 1, 120.0)
	fast(false)
	stop_autopilot()
	await frames(3)
	var race: RaceState = m.get("race")
	var c: Car = m.get("car")
	var before := c.prog
	var at := float(race.respawn.idx) # (where the car crossed the checkpoint)
	Engine.time_scale = 0.0 # (no steps while the key is down: the car stays where it was put)
	await key(KEY_ENTER)
	Engine.time_scale = 1.0
	check(c.prog < before and absf(c.prog - (at + PlayMode.RESPAWN_AHEAD)) <= 1.5,
		"Enter respawns %d samples past where the car crossed the checkpoint (%.1f, crossed at %.0f -> %.1f)"
		% [PlayMode.RESPAWN_AHEAD, before, at, c.prog])
	check(int((m.get("score") as ScoreState).counts.respawns) == 1, "the respawn costs points")
	await pad_button(JOY_BUTTON_B)
	check(int((m.get("score") as ScoreState).counts.respawns) == 2, "pad B respawns too")
	# the pad's stick and triggers through the InputMap actions
	pad_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	pad_axis(JOY_AXIS_LEFT_X, -0.5)
	await frames(3)
	var ctrl := app.input.controls(1.0 / 60.0, Car.Controls.new(), 30.0)
	check(is_equal_approx(ctrl.throttle, 1.0) and absf(ctrl.steer - GameInput.stick_curve(0.5)) < 1e-4 and app.input.pad_active,
		"stick half left -> steer %.3f, RT -> throttle %.2f, the pad is the active input" % [ctrl.steer, ctrl.throttle])
	pad_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	pad_axis(JOY_AXIS_LEFT_X, 0.0)
	await frames(2)
	# G / Y: no ghost on this run (the menu ghost setting stays); a note says why
	await key(KEY_G)
	check(str(m.get("note").get("text", "")) != "", "G without a ghost: %s" % m.get("note").get("text", ""))
	await pad_button(JOY_BUTTON_BACK)
	check(m.get("phase") == "countdown" and m.get("race_step") == 0, "pad View restarts")
	await key(KEY_R)
	check(m.get("phase") == "countdown", "R restarts")
	await pad_button(JOY_BUTTON_START)
	check(app.mode == app.menu_mode, "pad Menu goes back to the menu")
	# Train the AI: the training screen when it is in the build, else the note
	await click(app.ui.menu.get("_train_btn"))
	await frames(3)
	if app.train_mode != null:
		var tm := app.train_mode
		var dash: Control = tm.get("dash")
		check(app.mode == tm and dash != null and dash.is_visible_in_tree() and not app.ui.menu.visible,
			"Train the AI opens the training screen")
		# START TRAINING (seeded from the loaded network), then Watch best and back
		await click(dash.get("start_btn"))
		await frames(30)
		var tr: Variant = tm.get("session").get("trainer") if tm.get("session") != null else null
		check(tr != null and app.mode == tm, "START TRAINING runs a training session")
		await shot("train")
		# Max: the training screen's overlay, no 3D drawing (the last frame stays under it)
		await click((dash.get("speed_segs") as Dictionary)["max"])
		await frames(10)
		check(app.get_viewport().disable_3d and app.get("_freeze").texture != null and (dash.get("overlay") as CanvasItem).visible,
			"Max speed: the overlay shows and the 3D view is not drawn")
		await shot("train_max")
		await click((dash.get("speed_segs") as Dictionary)["1"])
		await frames(5)
		check(not app.get_viewport().disable_3d and not (dash.get("overlay") as CanvasItem).visible, "1x: the 3D view draws again")
		await click(dash.get("watch_btn"))
		await frames(3)
		check(app.mode != tm and app.mode.get("driver") == "ai", "Watch best: the AI drives")
		await key(KEY_ESCAPE)
		await frames(3)
		check(app.mode == app.train_mode and app.train_mode != tm, "Esc goes back to the training screen")
		var tr2: Variant = app.train_mode.get("session").get("trainer")
		check(tr2 != null and tr2 == tr, "the training session carried on (the same trainer)")
		await click(app.train_mode.get("dash").get("stop_btn"))
		await frames(3)
		await key(KEY_ESCAPE)
		await frames(3)
		check(app.mode == app.menu_mode and app.ui.menu.visible, "Esc leaves the training screen")
	else:
		check(app.message.visible, "Train the AI says the training screen isn't there")
		await key(KEY_ESCAPE)


# ---------------------------------------------------------------- the menu

func menu_nav() -> void:
	var menu: MainMenu = app.ui.menu
	var n := Tracks.ids().size()
	await key(KEY_1)
	check(menu.selected_track == 0, "1 picks track 1")
	await key(KEY_RIGHT)
	check(menu.selected_track == 1, "→ next track")
	await key(KEY_S)
	check(menu.selected_track == 2, "S next track")
	await key(KEY_UP)
	check(menu.selected_track == 1, "↑ previous track")
	await key(KEY_EQUAL)
	check(menu.selected_track == 11, "= picks track 12")
	await key(KEY_RIGHT)
	check(menu.selected_track == 0, "→ wraps to track 1")
	await wait_until(func() -> bool: return not app.building_track(), 60.0)
	check(app.world.track == app.tracks[0], "the 3D track follows the selection (built on a thread)")
	var car0 := UiData.picked_car()
	await key(KEY_C)
	var car1 := UiData.picked_car()
	check(car1 != car0, "C: next car (%s -> %s)" % [car0, car1])
	await key(KEY_C, true)
	check(UiData.picked_car() == car0, "Shift+C: previous car")
	check(str(SaveData.get_setting("car")) == car0, "the picked car is saved")
	await key(KEY_H)
	check(menu.controls.visible, "H opens Controls")
	await key(KEY_ESCAPE)
	check(not menu.controls.visible and app.mode == app.menu_mode, "Esc closes Controls")
	await key(KEY_O)
	check(menu.settings.visible, "O opens Settings")
	await key(KEY_ESCAPE)
	check(not menu.settings.visible, "Esc closes Settings")
	# the gamepad: its menu directions and buttons (MenuInput codes, as its poll makes them)
	var inp := app.input
	inp.pad_active = true
	inp.press("NavRight")
	await frames(2)
	inp.pad_active = true
	inp.press("NavRight")
	await frames(2)
	check(menu.selected_track == 1, "pad: right moves to the next tile (the first press shows the highlight)")
	inp.pad_active = true
	inp.press("PadRB")
	await frames(2)
	check(UiData.picked_car() == car1, "pad RB: next car")
	inp.pad_active = true
	inp.press("PadLB")
	await frames(2)
	check(UiData.picked_car() == car0, "pad LB: previous car")
	inp.pad_active = true
	inp.press("PadBack")
	await frames(2)
	check(menu.controls.visible, "pad View opens Controls")
	inp.pad_active = true
	inp.press("PadB")
	await frames(2)
	check(not menu.controls.visible, "pad B closes Controls")
	# down from the bottom row to the cars, then to Drive, A drives
	for i in 3:
		inp.pad_active = true
		inp.press("NavDown")
		await frames(2)
	var at: Control = menu.pad_target()
	check(at != null and at.get("car_id") != null, "pad: down from the tiles reaches the car cards (%s)" % (at.name if at else "none"))
	inp.pad_active = true
	inp.press("PadB")
	await frames(2)
	check(menu.pad_target() == menu.get("_tiles")[menu.selected_track], "pad B: back to the track tiles")
	inp.pad_active = true
	inp.press("PadA")
	await frames(3)
	check(app.mode != app.menu_mode and app.mode.get("driver") == "human", "pad A on a tile drives")
	await pad_button(JOY_BUTTON_START)
	check(app.mode == app.menu_mode, "pad Menu: back to the menu")
	check(n == 12, "12 tracks")


# ---------------------------------------------------------------- settings

func settings_set() -> void:
	var menu: MainMenu = app.ui.menu
	await key(KEY_O)
	check(menu.settings.visible, "O opens Settings")
	# rows: quality, fullscreen, vsync, interface size, ghost
	await key(KEY_RIGHT) # quality High -> Low
	await key(KEY_DOWN)
	await key(KEY_DOWN)
	await key(KEY_ENTER) # vsync On -> Off
	await key(KEY_DOWN)
	await key(KEY_RIGHT) # interface size Auto -> 100%
	await key(KEY_RIGHT) # -> 125%
	await key(KEY_DOWN)
	await key(KEY_RIGHT) # ghost On -> Off
	await key(KEY_ESCAPE)
	await key(KEY_C) # next car
	await frames(3)
	check(UiData.get_setting("quality") == "low" and app.world.quality == "low" and not app.world.auto_quality, "quality Low applied (pinned)")
	check(UiData.get_setting("vsync") == false and DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED, "vsync off applied")
	check(is_equal_approx(float(UiData.get_setting("ui_scale")), 1.25) and is_equal_approx(app.ui.ui_scale, 1.25), "interface 125% applied")
	check(UiData.get_setting("ghost") == false, "ghost off")
	print("PICKED ", UiData.picked_car())


func settings_check() -> void:
	await frames(5)
	check(UiData.get_setting("quality") == "low" and app.world.quality == "low" and not app.world.auto_quality, "after a restart: quality Low")
	check(UiData.get_setting("vsync") == false and DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED, "after a restart: vsync off")
	check(is_equal_approx(app.ui.ui_scale, 1.25), "after a restart: interface 125%")
	check(UiData.get_setting("ghost") == false and app.ui.menu.get("_ghost_check").checked == false, "after a restart: ghost off (menu tick too)")
	check(UiData.picked_car() == Cars.ids()[1], "after a restart: the picked car (%s)" % UiData.picked_car())
	# put them back (and check the file holds them)
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveData.path))
	check(raw.settings.quality == "low" and raw.settings.vsync == false and raw.settings.ghost == false, "the save file holds the settings")


# ---------------------------------------------------------------- screenshots

func shots() -> void:
	var size := DisplayServer.window_get_size() # (the window's pixels, not the 2D stretch size)
	var tag := "%dx%d" % [size.x, size.y]
	var tid := str(opts.get("track", "night-highway"))
	await pick(tid, "racer")
	await frames(30)
	await shot("menu_" + tag)
	await key(KEY_ENTER)
	var m: Node = app.mode
	var run: Dictionary = Medals.medal_times(Tracks.build(tid), "racer").get("run", {"aLat": 24.0, "lookK": 1.0})
	autopilot(float(run.aLat), float(run.lookK), false) # (no nitro yet: the banked points fill the tank for the shot)
	fast(true)
	var at := float(opts.get("at", "50"))
	await wait_until(func() -> bool: return (m.get("race") as RaceState).time > at, 600.0)
	fast(false)
	# nitro: hold it for the shot
	var c: Car = m.get("car")
	app.input.feed = func(_s: float) -> void:
		var cc: Car.Controls = _pilot.drive(m.get("car"))
		app.input.pad_steer = cc.steer
		app.input.pad_throttle = 1.0
		app.input.pad_brake = 0.0
		app.input.held["nitro"] = true
	await wait_until(func() -> bool: return c.boosting, 30.0)
	await frames(8)
	check(c.boosting, "nitro burning for the shot (tank %.0f%%)" % (c.nitro * 100.0))
	await shot("drive_" + tag)
	autopilot(float(run.aLat), float(run.lookK))
	fast(true)
	await wait_until(func() -> bool: return m.get("phase") == "finished", 900.0)
	fast(false)
	stop_autopilot()
	await frames(40)
	check(app.ui.hud.panel_open, "finish panel open")
	await shot("finish_" + tag)
	await key(KEY_ESCAPE)
	await frames(30)
	await shot("menu_after_" + tag)


# ---------------------------------------------------------------- performance

## Script time of a race frame, measured in the game while it races (Drive with the autopilot,
## real time): two marker nodes, processed first and last of every frame, time everything the
## frame's _process callbacks do (the input poll, the mode's physics steps, the car model,
## camera, HUD, world), without the drawing; the play mode times its physics steps itself and
## the autopilot (test input, not part of the game) is timed and taken out.
## (Performance.TIME_PROCESS is no use here: it includes the wait for the renderer.)
class Stamp extends Node:
	var t := 0
	func _process(_d: float) -> void:
		t = Time.get_ticks_usec()


func perf() -> void:
	var tid := str(opts.get("track", "night-highway"))
	var with_ai := opts.has("net") # (net=<file>: Race the AI ghost, the AI network stepping too)
	if with_ai:
		check(app.load_network_file(str(opts.net)) == "", "network loaded for Race the AI ghost")
	await pick(tid, str(opts.get("car", "racer")))
	if with_ai:
		app.play("human", true)
		await frames(2)
	else:
		await key(KEY_ENTER)
	var m: Node = app.mode
	autopilot(24.0, 1.3)
	var pilot_feed: Callable = app.input.feed
	var pilot_usec := [0]
	app.input.feed = func(sp: float) -> void:
		var t0 := Time.get_ticks_usec()
		pilot_feed.call(sp)
		pilot_usec[0] += Time.get_ticks_usec() - t0
	var first := Stamp.new()
	first.process_priority = -1000000
	var last := Stamp.new()
	last.process_priority = 1000000
	root.add_child(first)
	root.add_child(last)
	await wait_until(func() -> bool: return m.get("phase") == "race", 30.0)
	await frames(30) # (past the start)
	var steps0: int = m.get("steps_run")
	var usec0: int = m.get("step_usec")
	var pilot0: int = pilot_usec[0]
	var per_frame := PackedFloat64Array()
	var t_end := Time.get_ticks_msec() + int(float(opts.get("seconds", "20")) * 1000.0)
	var t_prev := Time.get_ticks_usec()
	var wall := 0.0
	await process_frame
	while Time.get_ticks_msec() < t_end:
		await process_frame
		# (the stamps of the frame just processed: this coroutine resumes before the next one)
		per_frame.append((last.t - first.t) / 1000.0)
		var t_now := Time.get_ticks_usec()
		wall += (t_now - t_prev) / 1000.0
		t_prev = t_now
	var n := per_frame.size()
	var steps: int = int(m.get("steps_run")) - steps0
	var pilot_ms: float = (pilot_usec[0] - pilot0) / 1000.0
	var step_ms: float = ((int(m.get("step_usec")) - usec0) / 1000.0 - pilot_ms) / maxf(1, steps)
	var total := 0.0
	for v in per_frame:
		total += v
	var sorted := per_frame.duplicate()
	sorted.sort()
	var frame_ms: float = (total - pilot_ms) / maxf(1, n)
	var other_ms: float = frame_ms - step_ms * steps / maxf(1, n)
	print("PERF %s%s: %d frames, %d physics steps (%.1f per frame, the frames are slow here)" % [
		tid, " + AI ghost" if with_ai else "", n, steps, float(steps) / maxf(1, n)])
	print("PERF script time per frame (all _process, autopilot taken out): avg %.2f ms (raw median %.2f, p95 %.2f)" % [
		frame_ms, sorted[n / 2], sorted[int(n * 0.95)]])
	print("PERF   physics step %.3f ms each; the rest of a frame (model, camera, HUD, world, input) %.2f ms" % [step_ms, other_ms])
	print("PERF   at 60 fps (1 step a frame): %.2f ms of 16.7; worst catch-up frame (6 steps): %.2f ms" % [
		other_ms + step_ms, other_ms + 6.0 * step_ms])
	print("PERF   autopilot (test input) %.3f ms per step; wall clock %.1f ms per frame incl. drawing (llvmpipe)" % [
		pilot_ms / maxf(1, steps), wall / maxf(1, n)])
	check(steps > 0 and other_ms + step_ms < 16.0, "a race frame's script time fits in 16 ms")
	first.queue_free()
	last.queue_free()
	stop_autopilot()
