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
##   races     tracks=a,b,.. (default rookie-oval, seaside-stunts, mountain-pass and v6.4's
##             summit-rush) cars=a,b,.. (default every car): pick the track and car with the menu
##             keys, Drive (Enter), drive the medal autopilot of the author time to the finish;
##             checks the finish panel (time = the author time, author medal), the saved record,
##             score and ghost, then R: the new ghost replays the run (within 3 cm of the car),
##             then Esc: the menu's tile and panel show the record, score and ghost.
##   modes     loads an AI network file (Load network's code path), Race the AI ghost and Watch the
##             AI by clicking their buttons, respawn (Enter) and restart (R) in Drive, pad buttons
##             in a race (joypad events through the InputMap actions), G toggles the ghost.
##   cars      the AI network of each car (start from an empty save file): car=<id> (default dune)
##             has none yet (the menu's AI block says so, Watch / Race the AI off), the training
##             screen starts with it (the form's car tiles), trains it at Max until it autosaves,
##             Watch best drives it, another car in the run view ends the session (asking first
##             when its best is unsaved); back on the menu its network is ready, Watch the AI and
##             Race the AI ghost drive it, the Racer still has none. net=<file>: then loads that
##             network for the car (Load network's code path) before watching it (screenshots
##             of a trained AI). Shots: cars_menu_none, cars_train_form, cars_train, cars_train_cars
##             (the run view scrolled to its Car tiles), cars_menu_ready, cars_watch.
##   menu      keyboard and gamepad navigation of the menu (v6.4: tracks 13-15 by the arrows and
##             the pad's three rows of tiles; the menu fits 1280 x 720 without scrolling), Controls
##             and Settings screens.
##   settings1 / settings2   change settings with the keyboard on the Settings screen; the second
##             run (a new process on the same save file) checks they persisted and were applied.
##   shots     out=<dir>: menu, driving with nitro, finish panel, the menu after it and (train=0
##             skips it) the AI training screen after train_seconds=40 of Max training with
##             train_car=<id> (default racer) on train_track=<id> (default lighthouse-bay) (PNGs);
##             net=<file> loads that network first (the menu's AI block, training continues it).
##   perf      script time per frame of a race (Drive with the autopilot, real time).
##   surfaces  dirt and snow (v6.3): the menu's track panel names a track's surfaces (Ramp Rally
##             "Asphalt + dirt", Mountain Pass "Asphalt + dirt + packed snow"); Drive with the Dune
##             on Ramp Rally (the medal autopilot): no dust on asphalt; on the dirt the tyres throw
##             up dust (a pooled effect), the tyre marks take the dirt's colour and the camera
##             rumbles; Hairpin Valley with the Racer: snow spray and grey-blue marks on the snow.
##             Shots: surfaces_menu, surfaces_transition, surfaces_dirt, surfaces_snow.
##   economy   money, points and the car shop (v6.5.0) from a new career: $0 and only the Racer;
##             race the Elite AI on Rookie Oval (the medal autopilot of the author time, starting a
##             second late: the AI car leads, then loses) and the Expert AI on Seaside Stunts (the
##             author run): the finish panel's payout, the money and points on the menu; the
##             Vortex is short of money (a message), the Kestrel is bought (BUY asks first) and
##             driven. Shots: economy_race, economy_finish, economy_menu, economy_shop, economy_buy.
##   Every other scenario starts by owning every car and picking My AI as the opponent (they
##   were written before the career: they drive every car and race the car's own network).
## Prints "ok"/"FAIL" lines and "E2E <scenario>: n passed, m failed"; quits with 1 on a failure.
## out=<dir> (default user://e2e) also holds the scratch files of the modes scenario;
## net=<file> is the network it loads (default the test fixture, a browser-format file).

const AiLink := preload("res://game/ai_link.gd")
const PlayMode := preload("res://modes/play_mode.gd")

var app: GameApp
var opts := {}
var scenario := ""
var out_dir := ""
var passed := 0
var failed := 0
var _pilot: Autopilot = null


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() > 1 else "1"
	scenario = str(opts.get("scenario", "races"))
	out_dir = str(opts.get("out", ProjectSettings.globalize_path("user://e2e")))
	DirAccess.make_dir_recursive_absolute(out_dir)
	var scene: PackedScene = load("res://main.tscn")
	app = scene.instantiate()
	root.add_child(app)
	_main.call_deferred()


func _main() -> void:
	await frames(3)
	await wait_until(func() -> bool: return not app.building_track(), 60.0)
	var t0 := Time.get_ticks_msec()
	if scenario != "economy":
		for c: String in Cars.ids():
			SaveData.give_car(c)
		app.ui.menu.select_opponent(UiData.MY_AI)
	match scenario:
		"races":
			await races()
		"modes":
			await modes()
		"cars":
			await cars()
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
		"surfaces":
			await surfaces()
		"economy":
			await economy()
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
	await scroll_to(c)
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


## Scroll the ScrollContainer around `c` (if any) so that `c` shows.
func scroll_to(c: Control) -> void:
	var up := c.get_parent()
	while up != null and not (up is ScrollContainer):
		up = up.get_parent()
	if up != null:
		(up as ScrollContainer).ensure_control_visible(c)
		await frames(2)


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, name]
	img.save_png(path)
	print("shot ", path, " ", img.get_size())


## The key that picks track `i` on the menu (1-9, 0, -, =: the first 12 tracks).
static func track_key(i: int) -> Key:
	if i < 9:
		return (KEY_1 + i) as Key
	return [KEY_0, KEY_MINUS, KEY_EQUAL][mini(i, 11) - 9]


## Pick track `id` and car `car` on the menu with the keyboard (tracks past the 12th: = picks
## the 12th, then → moves on to it).
func pick(track_id: String, car: String) -> void:
	var i := Tracks.ids().find(track_id)
	await key(track_key(i))
	for k in maxi(0, i - 11):
		await key(KEY_RIGHT)
	var tries := 0
	while UiData.picked_car() != car and tries < 8:
		await key(KEY_C)
		tries += 1
	await wait_until(func() -> bool: return not app.building_track(), 60.0)


## Drive the race in progress with the medal autopilot (aLat, lookK), feeding the input layer.
## It knows the car's grip on dirt and snow, as the medal sweep's autopilot does.
func autopilot(a_lat: float, look_k: float, nitro: bool = true) -> void:
	var m: Node = app.mode
	var cid: String = str((m.get("car_def") as Dictionary).get("id", Cars.DEFAULT_CAR)) if m.get("car_def") is Dictionary else Cars.DEFAULT_CAR
	_pilot = Autopilot.medal(m.get("track"), a_lat, look_k, nitro, Autopilot.DECEL, Cars.spec(cid))
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
	var tracks: PackedStringArray = str(opts.get("tracks", "rookie-oval,seaside-stunts,mountain-pass,summit-rush")).split(",")
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
	var net_path := str(opts.get("net", "res://tests/fixtures/game_net.json"))
	var err := app.load_network_file(net_path)
	check(err == "" and not app.network.is_empty(), "load a web network file: %s" % (err if err != "" else "ok"))
	check(UiData.ai_status().ready and not app.ui.menu.get("_ghost_btn").disabled and not app.ui.menu.get("_watch_btn").disabled,
		"the menu's AI buttons are enabled")
	check(SaveData.load_network() != null, "the loaded network is remembered in the save file")
	var bad := out_dir.path_join("bad_net.json")
	var f := FileAccess.open(bad, FileAccess.WRITE)
	f.store_string("{\"sizes\": [11, 8, 2], \"weights\": [[0]], \"biases\": [[0]]}")
	f.close()
	var err2 := app.load_network_file(bad)
	check(err2 != "" and app.message.visible, "a v1 network is refused with a message: %s" % err2)
	await key(KEY_ENTER)
	check(not app.message.visible and app.mode == app.menu_mode, "Enter closes the message (and doesn't drive)")
	# save the network to a file and read it back
	var saved := out_dir.path_join("saved_net.json")
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


# ---------------------------------------------------------------- an AI network per car

func cars() -> void:
	var tid := str(opts.get("track", "rookie-oval"))
	var car := str(opts.get("car", "dune"))
	var cname: String = Cars.get_car(car).name
	var other := "kestrel" if car != "kestrel" else "thunder"
	var menu: MainMenu = app.ui.menu
	await pick(tid, car)
	await frames(10)
	check(UiData.picked_car() == car and app.network.is_empty() and menu.get("_watch_btn").disabled and menu.get("_ghost_btn").disabled and
		str(menu.get("_ai_status_text")).contains("No %s network yet" % cname) and (menu.get("_ai_cap") as Label).text.ends_with(cname),
		"the %s has no AI network: the menu's AI block says so and offers to train one; Watch / Race the AI are off" % cname)
	await shot("cars_menu_none")
	await click(menu.get("_train_btn"))
	await frames(3)
	var tm := app.train_mode
	if not check(tm != null and app.mode == tm, "Train the AI opens the training screen"):
		return
	var dash: Control = tm.get("dash")
	var s: Object = tm.get("session")
	var chips: Array = dash.get("car_chips")
	var k := Cars.ids().find(car)
	check(str(dash.get("car")) == car and chips.size() == Cars.ids().size() and chips[k].selected and (dash.get("title") as Label).text.ends_with(cname),
		"the training screen starts with the menu's car (%s): its tile is picked" % cname)
	await click(chips[Cars.ids().find(other)])
	check(str(dash.get("car")) == other and str(s.get("car")) == other, "a click on the %s's tile picks it" % Cars.get_car(other).name)
	await click(chips[k])
	check(str(dash.get("car")) == car, "and back to the %s" % cname)
	await frames(3)
	await shot("cars_train_form")
	await click(dash.get("start_btn"))
	await frames(10)
	var tr: Variant = s.get("trainer")
	var fleet: Node = tm.get("fleet")
	if not check(tr != null and str(tr.get("cfg").get("car_id")) == car and fleet != null, "START TRAINING trains the %s" % cname):
		return
	check(str(fleet.get("car_id")) == car, "the training fleet on the track is drawn as the %s" % cname)
	await click((dash.get("speed_segs") as Dictionary)["max"])
	await wait_until(func() -> bool: return float(s.get("last_saved")) > -INF and int(s.get("trainer").get("generation")) >= int(opts.get("gens", "3")), 300.0)
	await click((dash.get("speed_segs") as Dictionary)["1"])
	await frames(int(opts.get("train_frames", "150")))
	tr = s.get("trainer")
	var saved: Variant = SaveData.load_network(car)
	check(saved is Dictionary and str((saved as Dictionary).get("car")) == car and SaveData.load_network("racer") == null,
		"training autosaved the %s's network (generation %s), with its car; the Racer has none" % [cname, str((saved as Dictionary).get("generation")) if saved is Dictionary else "-"])
	await shot("cars_train")
	await click(dash.get("watch_btn"))
	await frames(3)
	var m: Node = app.mode
	check(m != tm and m.get("driver") == "ai" and (m.get("car") as Car).spec == Cars.get_car(car).spec and (m.get("model") as CarModel).car_id == car,
		"Watch best: the AI drives the %s" % cname)
	await key(KEY_ESCAPE)
	await frames(3)
	tm = app.train_mode
	dash = tm.get("dash")
	check(app.mode == tm and tm.get("session").get("trainer") == tr and str(dash.get("car")) == car, "Esc: back to the %s's session" % cname)
	# another car ends the session: asked first when the best is not saved yet
	await scroll_to(dash.get("run_chips")[-1])
	await frames(int(opts.get("train_frames", "150")))
	await shot("cars_train_cars")
	await click(dash.get("run_chips")[Cars.ids().find(other)])
	await frames(3)
	var asked: bool = dash.call("asking")
	if asked:
		await click(dash.get("ask_buttons")[0]) # Save it, then switch
		await frames(3)
	var s2: Object = tm.get("session")
	check(str(s2.get("car")) == other and s2.get("trainer") != null and s2.get("trainer") != tr and str(s2.get("trainer").get("cfg").get("car_id")) == other,
		"the %s's tile in the run view: a new session with it (%s)" % [Cars.get_car(other).name, "asked first, saved" if asked else "nothing unsaved"])
	await click(dash.get("stop_btn"))
	await frames(3)
	await key(KEY_ESCAPE)
	await frames(10)
	check(app.mode == app.menu_mode and UiData.picked_car() == car and not app.network.is_empty() and not menu.get("_watch_btn").disabled and
		str(menu.get("_ai_status_text")).contains("Ready"), "back on the menu: the %s's AI network is ready" % cname)
	if opts.has("net"):
		var err := app.load_network_file(str(opts.net))
		var trained := AiLink.network_car(app.network.get("meta", {}))
		check(err == "" and (trained == car) != app.message.visible, "net=%s loaded as the %s's network (trained with the %s%s)" % [
			str(opts.net).get_file(), cname, Cars.get_car(trained).name, ", a note says so" if app.message.visible else ""])
		if app.message.visible:
			await key(KEY_ENTER)
		await frames(10)
	await shot("cars_menu_ready")
	await click(menu.get("_watch_btn"))
	m = app.mode
	if check(m != app.menu_mode and m.get("driver") == "ai" and (m.get("car") as Car).spec == Cars.get_car(car).spec and (m.get("model") as CarModel).car_id == car,
			"Watch the AI (clicked): the %s's network drives the %s" % [cname, cname]):
		fast(true)
		await wait_until(func() -> bool: return (m.get("race") as RaceState).time > float(opts.get("watch_at", "12")), 120.0)
		fast(false)
		await frames(20)
		check((m.get("car") as Car).prog > 50.0 and str(app.ui.hud.get("_mode").text).contains(cname), "it drives (%.0f samples), the HUD names the %s" % [(m.get("car") as Car).prog, cname])
		await shot("cars_watch")
		await key(KEY_ESCAPE)
	await click(menu.get("_ghost_btn"))
	m = app.mode
	check(m != app.menu_mode and m.get("with_ghost") == true and (m.get("ghost_model") as CarModel).car_id == car and ((m.get("ghost") as Dictionary).car as Car).spec == Cars.get_car(car).spec,
		"Race the AI ghost: the %s AI's ghost is a %s" % [cname, cname])
	await key(KEY_ESCAPE)
	await pick(tid, "racer")
	await frames(3)
	check(app.network.is_empty() and menu.get("_watch_btn").disabled and str(menu.get("_ai_status_text")).contains("No Racer network yet"), "the Racer still has no network")


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
	# v6.4: tracks 13-15 (no key of their own) are on with the arrows, and on screen
	for want in [12, 13, 14]:
		await key(KEY_RIGHT)
		check(menu.selected_track == want, "→ track %d (%s)" % [want + 1, Tracks.build(Tracks.ids()[want]).name])
	await key(KEY_RIGHT)
	check(menu.selected_track == 0, "→ wraps to track 1")
	# the whole menu fits a 1280 x 720 window: no scrolling, every tile and car card inside it
	var win := Vector2(root.size)
	var sc: ScrollContainer = menu.get("_scroll")
	var bar := sc.get_v_scroll_bar()
	var inside := true
	for c: Control in (menu.get("_tiles") as Array) + (menu.get("_cards") as Array):
		var r := c.get_global_rect()
		inside = inside and r.position.y >= 0.0 and r.end.y <= win.y + 0.5 and r.position.x >= 0.0 and r.end.x <= win.x + 0.5 and c.is_visible_in_tree()
	var main: Control = menu.get("_main")
	check(win == Vector2(1280, 720) and inside and bar.max_value <= bar.page + 0.5 and main.get_global_rect().end.y <= win.y + 0.5,
		"the menu with %d tracks fits %dx%d: no scrolling (content %.0f px, page %.0f), every tile and car card on screen" % [n, win.x, win.y, bar.max_value, bar.page])
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
	# down the three rows of tiles to the cars, then A drives
	var rows_seen := {menu.selected_track / maxi(1, menu.columns): true}
	for i in 5:
		inp.pad_active = true
		inp.press("NavDown")
		await frames(2)
		var on: Control = menu.pad_target()
		if on != null and on.get("car_id") != null:
			break
		rows_seen[menu.selected_track / maxi(1, menu.columns)] = true
	var at: Control = menu.pad_target()
	check(at != null and at.get("car_id") != null and rows_seen.size() == 3,
		"pad: down through the %d rows of tiles reaches the car cards (%s)" % [rows_seen.size(), at.name if at else "none"])
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
	check(n == 15, "15 tracks")


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
	if opts.has("net"): # (net=<file>: the menu's AI block shows a trained network)
		check(app.load_network_file(str(opts.net)) == "", "network loaded for the shots")
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
	if str(opts.get("train", "1")) == "1":
		await train_shot(tag)


## The training screen for the screenshot: a new session on the menu's track, trained at Max
## for train_seconds (no 3D drawing meanwhile), then 1x for a moment so the cars are drawn.
func train_shot(tag: String) -> void:
	await pick(str(opts.get("train_track", "lighthouse-bay")), str(opts.get("train_car", "racer")))
	await click(app.ui.menu.get("_train_btn"))
	await frames(3)
	var tm := app.train_mode
	if not check(tm != null and app.mode == tm, "Train the AI opens the training screen"):
		return
	var dash: Control = tm.get("dash")
	await click(dash.get("start_btn"))
	await frames(10)
	await click((dash.get("speed_segs") as Dictionary)["max"])
	var t_end := Time.get_ticks_msec() + int(float(opts.get("train_seconds", "40")) * 1000.0)
	await wait_until(func() -> bool: return Time.get_ticks_msec() > t_end, 600.0)
	await click((dash.get("speed_segs") as Dictionary)["1"])
	await frames(int(opts.get("train_frames", "90")))
	var tr: Variant = tm.get("session").get("trainer")
	check(tr != null and int(tr.get("generation")) > 0 and not app.get_viewport().disable_3d,
		"training for the shot: generation %s, the 3D view drawn" % (str(tr.get("generation")) if tr != null else "-"))
	await shot("train_" + tag)


# ---------------------------------------------------------------- road surfaces

func surfaces() -> void:
	var meta: Label = app.ui.menu.get("_td_meta")
	for want: Array in [["rookie-oval", "Asphalt"], ["mountain-pass", "Asphalt + dirt + packed snow"], ["ramp-rally", "Asphalt + dirt"]]:
		await pick(want[0], "dune")
		await frames(4)
		check(meta.text.ends_with(" · " + want[1]), "the track panel names the surfaces of %s: \"%s\"" % [want[0], meta.text])
	await frames(20)
	await shot("surfaces_menu")
	await _surface_drive("ramp-rally", "dune", "dirt", true)
	await _surface_drive("hairpin-valley", "racer", "snow", false)


## Drive (medal autopilot) to the first stretch of `sid` on track `tid` with car `cid`: the tyres
## throw up nothing on asphalt; on the surface they throw up its dust (or snow), leave marks of its
## colour, and the camera rumbles. transition: a shot just before the border too.
func _surface_drive(tid: String, cid: String, sid: String, transition: bool) -> void:
	var tag := "%s / %s" % [tid, cid]
	await pick(tid, cid)
	await key(KEY_ENTER)
	var m: Node = app.mode
	var track: BuiltTrack = m.get("track")
	var si := Surfaces.index_of(sid)
	var first := -1
	for i in track.count:
		if track.surface[i] == si:
			first = i
			break
	if not check(first > 0, "%s: the track has %s (from sample %d)" % [tag, sid, first]):
		return
	var last := first
	while last + 1 < track.count and track.surface[last + 1] == si:
		last += 1
	var run: Dictionary = Medals.medal_times(track, cid).get("run", {"aLat": 20.0, "lookK": 1.0})
	autopilot(float(run.aLat), float(run.lookK))
	var c: Car = m.get("car")
	var model: CarModel = m.get("model")
	var cam: ChaseCamera = m.get("camera")
	fast(true)
	await wait_until(func() -> bool: return c.idx >= first - 70, 300.0)
	fast(false) # (the last stretch at normal speed: a fast frame could jump the border)
	await wait_until(func() -> bool: return c.idx >= first - 8, 300.0)
	var pool: CarEffects.Spray = model.dust if sid == "dirt" else model.spray
	check(pool == null or pool.alive == 0, "%s: on asphalt (sample %d) the tyres throw up no %s" % [tag, c.idx, "dust" if sid == "dirt" else "snow"])
	if transition:
		await shot("surfaces_transition")
	# into the stretch, then a moment sliding on it (or the last of it)
	await wait_until(func() -> bool: return c.idx >= first + 30 and c.idx < last - 10, 60.0)
	await wait_until(func() -> bool: return c.slip > 0.35 or c.idx >= mini(last - 10, first + 160), 40.0)
	await frames(12)
	pool = model.dust if sid == "dirt" else model.spray
	var slot := model.skids.newest_tint.x if si == 1 else model.skids.newest_tint.y
	check(pool != null and pool.alive >= 8 and pool.node.visible, "%s: on the %s (sample %d, %.0f km/h, slip %.2f) the tyres throw up %s: %d puffs alive (pool %d)" % [
		tag, sid, c.idx, c.speed * 3.6, c.slip, "dust" if sid == "dirt" else "snow", pool.alive if pool != null else 0, pool.max if pool != null else 0])
	check(model.skids.used > 0 and slot > 0.9, "%s: the newest tyre mark has the %s's colour (weight %.2f)" % [tag, sid, slot])
	check(cam.ground_rumble > 0.02, "%s: the camera rumbles on the %s (%.3f)" % [tag, sid, cam.ground_rumble])
	await shot("surfaces_" + sid)
	stop_autopilot()
	await key(KEY_ESCAPE)
	await frames(4)


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


# ---------------------------------------------------------------- money, points, the car shop (v6.5.0)

func economy() -> void:
	var menu: MainMenu = app.ui.menu
	var btns: Dictionary = menu.get("_opp_btns")
	var money_l: Label = menu.get("_money_l")
	var points_l: Label = menu.get("_points_l")
	var drive_btn: Button = menu.get("_drive_btn")
	check(UiData.money() == 0 and UiData.points() == 0 and SaveData.owned_cars() == PackedStringArray(["racer"]) and money_l.text == "$0" and
		points_l.text == "0 pts" and money_l.is_visible_in_tree(), "a new career: $0, 0 pts, only the Racer; the header shows them")
	await pick("rookie-oval", "racer")
	await click(btns["elite"])
	check(UiData.opponent() == "elite" and (menu.get("_ghost_btn") as Button).text == "Race the Elite AI", "the Elite chip (clicked) picks the Elite AI")
	# the menu still fits 1280 x 720 with the wallet and the opponent chips
	var win := Vector2(root.size)
	var bar := (menu.get("_scroll") as ScrollContainer).get_v_scroll_bar()
	var inside := true
	for c: Control in btns.values() + [menu.get("_ghost_btn"), menu.get("_watch_btn"), menu.get("_train_btn"), drive_btn, money_l, points_l]:
		var r := c.get_global_rect()
		inside = inside and r.position.y >= 0.0 and r.end.y <= win.y + 0.5 and r.position.x >= 0.0 and r.end.x <= win.x + 0.5 and c.is_visible_in_tree()
	check(win == Vector2(1280, 720) and inside and bar.max_value <= bar.page + 0.5, "1280 x 720: the money, the points, the opponent chips and the race buttons on screen, no scrolling")

	# race the Elite AI on Rookie Oval: start a second late, so its car leads for the shot
	var money0 := UiData.money()
	await click(menu.get("_ghost_btn"))
	var m: Node = app.mode
	if not check(m != app.menu_mode and m.get("with_ghost") == true and m.get("level") == "elite" and str(app.ui.hud.get("_mode").text).begins_with("VS ELITE AI"),
			"Race the Elite AI (clicked): %s" % app.ui.hud.get("_mode").text):
		return
	var track: BuiltTrack = m.get("track")
	var run: Dictionary = Medals.medal_times(track, "racer").run
	fast(true)
	await wait_until(func() -> bool: return m.get("phase") == "race" and (m.get("race") as RaceState).time >= 1.0, 60.0)
	autopilot(float(run.aLat), float(run.lookK))
	var gcar: Car = m.get("ghost").car
	var c: Car = m.get("car")
	# (the shot when the player has closed in on it: under 22 m behind, from 15 s)
	await wait_until(func() -> bool: return (m.get("race") as RaceState).time >= 15.0 and gcar.prog > c.prog and \
		Vector3(gcar.x - c.x, gcar.y - c.y, gcar.z - c.z).length() < 22.0 or (m.get("race") as RaceState).time >= 40.0, 120.0)
	fast(false)
	await frames(20)
	var gap := Vector3(gcar.x - c.x, gcar.y - c.y, gcar.z - c.z).length()
	check(gcar.prog > c.prog and gap < 60.0 and (m.get("ghost_model") as CarModel).visible, "the Elite AI's car leads, %.0f m ahead: %s" % [gap, m.get("ghost_text")])
	await shot("economy_race")
	fast(true)
	await wait_until(func() -> bool: return m.get("phase") == "finished", 600.0)
	fast(false)
	stop_autopilot()
	await frames(40)
	var race: RaceState = m.get("race")
	var fs: Dictionary = m.get("finish_state")
	var p: Dictionary = fs.get("payout", {})
	var want := ["bronze", "silver", "gold", "ai-rookie", "ai-amateur", "ai-pro", "ai-expert", "ai-elite"]
	var w := _sum("rookie-oval", want)
	var ids: Array = (p.get("items", []) as Array).map(func(it: Dictionary) -> String: return String(it.id))
	check(race.finished and Medals.medal_for(Medals.medal_times(track, "racer"), race.finish_time) == "gold" and p.get("won") == true and ids == want and
		int(p.money) == w.x and int(p.points) == w.y and UiData.money() == money0 + w.x and app.ui.hud.panel_open,
		"%s (gold) beats the Elite AI: paid three medals and all five AI levels, %s and %d pts" % [RaceState.format_time(race.finish_time), UiFormat.money(w.x), w.y])
	check(str(fs.get("lines", [""])[0]).begins_with("Elite AI") and str(fs.get("lines", [""])[0]).contains("you win"), "the finish panel: %s" % fs.get("lines", [""])[0])
	await shot("economy_finish")
	await key(KEY_ESCAPE)
	await frames(10)
	check(app.mode == app.menu_mode and money_l.text == UiFormat.money(UiData.money()) and str(menu.get("_ai_status_text")).contains("Beaten: paid"),
		"back on the menu: %s, %s; the Elite AI is paid" % [money_l.text, points_l.text])

	# the Expert AI on Seaside Stunts (the author run): more money on a later track
	await pick("seaside-stunts", "racer")
	await click(btns["expert"])
	var money1 := UiData.money()
	await click(menu.get("_ghost_btn"))
	m = app.mode
	if not check(m != app.menu_mode and m.get("level") == "expert", "Race the Expert AI on Seaside Stunts"):
		return
	run = Medals.medal_times(m.get("track"), "racer").run
	autopilot(float(run.aLat), float(run.lookK))
	fast(true)
	await wait_until(func() -> bool: return m.get("phase") == "finished", 600.0)
	fast(false)
	stop_autopilot()
	await frames(10)
	p = (m.get("finish_state") as Dictionary).get("payout", {})
	want = ["bronze", "silver", "gold", "author", "ai-rookie", "ai-amateur", "ai-pro", "ai-expert"]
	w = _sum("seaside-stunts", want)
	ids = (p.get("items", []) as Array).map(func(it: Dictionary) -> String: return String(it.id))
	check(ids == want and int(p.money) == w.x and UiData.money() == money1 + w.x, "the author time beats the Expert AI on Seaside Stunts (x2.1): %s, %d pts" % [UiFormat.money(w.x), w.y])
	await key(KEY_ESCAPE)
	await frames(30)
	check(money_l.text == UiFormat.money(UiData.money()) and points_l.text == "%s pts" % UiFormat.points(UiData.points()), "the menu: %s, %s" % [money_l.text, points_l.text])
	await shot("economy_menu")

	# the shop: the Vortex is short of money, the Kestrel is bought
	while UiData.picked_car() != "vortex":
		await key(KEY_C)
	check(drive_btn.text == "LOCKED", "the Vortex picked: LOCKED (it costs %s)" % UiFormat.money(UiData.car_price("vortex")))
	await key(KEY_ENTER)
	var msg: Label = app.message.get("_text")
	check(app.mode == app.menu_mode and app.message.visible and not app.message.asking and msg.text.contains("more to go"), "Enter: %s" % msg.text)
	await key(KEY_ESCAPE)
	check(not app.message.visible, "Esc closes it")
	while UiData.picked_car() != "kestrel":
		await key(KEY_C)
	await frames(10)
	var money2 := UiData.money()
	check(drive_btn.text == "BUY $10,000" and not SaveData.owns_car("kestrel"), "the Kestrel picked: BUY $10,000")
	await shot("economy_shop")
	await key(KEY_ENTER)
	await frames(10)
	check(app.message.asking and msg.text.contains("costs $10,000"), "Enter (BUY) asks first: %s" % msg.text)
	await shot("economy_buy")
	await key(KEY_ENTER)
	await frames(4)
	check(SaveData.owns_car("kestrel") and UiData.money() == money2 - 10000 and drive_btn.text == "DRIVE" and money_l.text == UiFormat.money(money2 - 10000) and
		app.mode == app.menu_mode, "Enter (yes): the Kestrel is yours, %s left" % UiFormat.money(UiData.money()))
	await key(KEY_ENTER)
	check(app.mode != app.menu_mode and str((app.mode.get("car_def") as Dictionary).id) == "kestrel", "Enter drives the Kestrel")
	await key(KEY_ESCAPE)
	await frames(4)
	check(app.mode == app.menu_mode, "back on the menu")


## The money (x) and points (y) of rewards `ids` on track `tid`.
func _sum(tid: String, ids: Array) -> Vector2i:
	var v := Vector2i.ZERO
	for id: String in ids:
		var r := Economy.reward(tid, id)
		v += Vector2i(int(r.money), int(r.points))
	return v
