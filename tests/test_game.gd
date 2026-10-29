extends RefCounted
## test_game.gd: headless checks of the game shell (game/, modes/): the input layer (InputMap
## actions, keyboard steering ramps, the stick and trigger curves, key presses), the save data
## wiring of the interface (UiData -> SaveData), the app's mode switching and the race modes'
## helpers (respawn, roll-out, the stuck watchdog, a short race through the play mode), and
## (v6.5.0) the career in the app: the car shop, races against the AI opponents and their payout.
## The real game under a display is checked by tests/e2e/game_e2e.gd.

const AiLink := preload("res://game/ai_link.gd")
const PlayMode := preload("res://modes/play_mode.gd")
const SAVE := "user://test_game_save.json"


func run(t) -> bool:
	_input(t)
	_save_wiring(t)
	_helpers(t)
	_app(t)
	UiData.reset()
	SaveData.use_file(SaveData.DEFAULT_PATH)
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	return true


func _key(k: Key, down: bool = true, shift: bool = false) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	e.shift_pressed = shift
	return e


func _input(t) -> void:
	t.section("input: InputMap actions")
	GameInput.setup_actions()
	var missing := []
	for a: String in GameInput.ACTIONS:
		if not InputMap.has_action(a):
			missing.append(a)
	t.check(missing.is_empty(), "every action exists (%d): %s" % [GameInput.ACTIONS.size(), missing])
	var binds := {
		"steer_left": [KEY_LEFT, KEY_A], "steer_right": [KEY_RIGHT, KEY_D], "accelerate": [KEY_UP, KEY_W], "brake": [KEY_DOWN, KEY_S],
		"handbrake": [KEY_SPACE], "nitro": [KEY_SHIFT], "restart": [KEY_R], "respawn": [KEY_ENTER, KEY_BACKSPACE, KEY_KP_ENTER],
		"ghost": [KEY_G], "menu": [KEY_ESCAPE], "menu_accept": [KEY_ENTER, KEY_SPACE], "menu_back": [KEY_ESCAPE, KEY_BACKSPACE],
	}
	var bad := []
	for a: String in binds:
		for k: Key in binds[a]:
			if not InputMap.event_is_action(_key(k), a):
				bad.append("%s:%s" % [a, OS.get_keycode_string(k)])
	t.check(bad.is_empty(), "keys map to their actions %s" % [bad])
	t.check(InputMap.event_is_action(_key(KEY_A, true, true), "steer_left") and InputMap.event_is_action(_key(KEY_W, true, true), "accelerate"),
		"steering and throttle keys still count with Shift (nitro) held")
	var pad := {"handbrake": JOY_BUTTON_A, "respawn": JOY_BUTTON_B, "nitro": JOY_BUTTON_X, "ghost": JOY_BUTTON_Y,
		"restart": JOY_BUTTON_BACK, "menu": JOY_BUTTON_START, "steer_left": JOY_BUTTON_DPAD_LEFT, "steer_right": JOY_BUTTON_DPAD_RIGHT}
	bad = []
	for a: String in pad:
		var e := InputEventJoypadButton.new()
		e.button_index = pad[a]
		e.pressed = true
		e.device = 2
		if not InputMap.event_is_action(e, a):
			bad.append(a)
	var rb := InputEventJoypadButton.new()
	rb.button_index = JOY_BUTTON_RIGHT_SHOULDER
	rb.pressed = true
	t.check(bad.is_empty() and InputMap.event_is_action(rb, "nitro"), "pad buttons map to their actions on any pad (RB nitro too) %s" % [bad])
	var ax := InputEventJoypadMotion.new()
	ax.axis = JOY_AXIS_LEFT_X
	ax.axis_value = -0.7
	var tr := InputEventJoypadMotion.new()
	tr.axis = JOY_AXIS_TRIGGER_RIGHT
	tr.axis_value = 0.6
	t.check(ax.is_action_pressed("pad_steer_left") and not ax.is_action_pressed("pad_steer_right") and tr.is_action_pressed("pad_throttle") and
		is_equal_approx(ax.get_action_strength("pad_steer_left"), 0.7), "stick and trigger axes map to the analogue actions (no dead zone of their own)")

	t.section("input: curves (input.js stickCurve / triggerValue)")
	t.check(GameInput.stick_curve(0.1) == 0.0 and GameInput.stick_curve(-0.12) == 0.0, "stick dead zone 0.12")
	t.check(is_equal_approx(GameInput.stick_curve(0.96), 1.0) and is_equal_approx(GameInput.stick_curve(-1.0), -1.0), "full lock from 0.96")
	t.check(absf(GameInput.stick_curve(0.5) - pow((0.5 - 0.12) / 0.84, 1.5)) < 1e-12 and absf(GameInput.stick_curve(0.5) - 0.304) < 0.01,
		"half travel ~ 0.30 steer (%.3f)" % GameInput.stick_curve(0.5))
	t.check(GameInput.trigger_value(0.03) == 0.0 and is_equal_approx(GameInput.trigger_value(1.0), 1.0) and
		absf(GameInput.trigger_value(0.52) - 0.5) < 1e-9, "trigger rest noise under 0.04 ignored, scaled to 0..1")

	t.section("input: keyboard steering ramps (input.js controls)")
	var inp := GameInput.new()
	var c := Car.Controls.new()
	inp.held = {"steer_left": true}
	for i in 6:
		inp.controls(1.0 / 60.0, c, 0.0)
	t.check(absf(c.steer - 7.0 * 6.0 / 60.0) < 1e-9, "at a standstill a key builds 7 /s (%.3f after 0.1 s)" % c.steer)
	inp.steer = 0.0
	for i in 6:
		inp.controls(1.0 / 60.0, c, 60.0)
	t.check(absf(c.steer - 3.2 * 6.0 / 60.0) < 1e-9, "from 50 m/s it builds 3.2 /s (%.3f)" % c.steer)
	inp.steer = 0.0
	for i in 6:
		inp.controls(1.0 / 60.0, c, 25.0)
	t.check(absf(c.steer - (7.0 + (3.2 - 7.0) * 0.5) * 0.1) < 1e-9, "half way at 25 m/s (%.3f)" % c.steer)
	for i in 60:
		inp.controls(1.0 / 60.0, c, 25.0)
	t.check(c.steer == 1.0, "held: full lock")
	inp.held = {"steer_right": true}
	inp.controls(1.0 / 60.0, c, 25.0)
	t.check(absf(c.steer - (1.0 - 10.0 / 60.0)) < 1e-9, "reversing turns back at 10 /s")
	inp.held = {}
	inp.steer = 0.5
	inp.controls(0.05, c, 25.0)
	t.check(is_equal_approx(c.steer, 0.0), "released: back to the centre at 10 /s")
	inp.held = {"accelerate": true, "handbrake": true, "nitro": true}
	inp.controls(1.0 / 60.0, c, 0.0)
	t.check(c.throttle == 1.0 and c.handbrake and c.nitro == 1.0, "↑ throttle, Space handbrake, Shift nitro")
	inp.held = {"brake": true}
	inp.pad_throttle = 0.4
	inp.controls(1.0 / 60.0, c, 0.0)
	t.check(is_equal_approx(c.throttle, 0.4 - 1.0), "keyboard and pad together: throttle = max(keys, RT) - max(keys, LT)")
	inp.held = {"steer_left": true}
	inp.steer = 0.0
	inp.pad_steer = -0.6
	inp.pad_throttle = 0.0
	inp.controls(1.0 / 60.0, c, 0.0)
	t.check(c.steer == -0.6, "steering: the stronger of keyboard and stick")
	inp.pad_steer = 0.0
	var fed := [0]
	inp.feed = func(_s: float) -> void:
		fed[0] += 1
		inp.pad_steer = 0.25
	inp.held = {}
	inp.steer = 0.0
	inp.controls(1.0 / 60.0, c, 0.0)
	t.check(fed[0] == 1 and c.steer == 0.25, "feed (the e2e autopilot) is asked once per step")
	inp.feed = Callable()

	t.section("input: presses (consume once, no repeat)")
	inp.clear_pressed()
	inp._input(_key(KEY_R))
	t.check(inp.consume(["restart"]) and not inp.consume(["restart"]), "R: one 'restart' press, consumed once")
	inp._input(_key(KEY_ENTER))
	t.check(inp.pressed.has("respawn") and inp.pressed.has("Enter") and inp.pressed.has("menu_accept"), "Enter: respawn, menu_accept and the menu's Enter")
	inp.clear_pressed()
	var echo := _key(KEY_G)
	echo.echo = true
	inp._input(echo)
	t.check(not inp.pressed.has("ghost"), "a key's auto-repeat is not a press")
	var b := InputEventJoypadButton.new()
	b.button_index = JOY_BUTTON_Y
	b.pressed = true
	inp._input(b)
	t.check(inp.consume(["ghost"]), "pad Y: ghost")
	inp.free()


func _save_wiring(t) -> void:
	t.section("save data wiring (UiData -> SaveData)")
	var path := SAVE
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	SaveData.use_file(path)
	UiData.reset()
	UiData.store.records["rookie-oval|racer"] = {"time": 99.0}
	t.check(UiData.record("rookie-oval", "racer") != null, "before wiring: the in-memory store")
	UiData.use_save_data(true)
	t.check(UiData.record("rookie-oval", "racer") == null and UiData.best_score("rookie-oval", "racer") == -1 and
		not UiData.has_ghost("rookie-oval", "racer"), "wired: an empty save file has no records, scores or ghosts")
	SaveData.submit_record("rookie-oval", "racer", 130.5, [40.0, 80.0, 130.5])
	SaveData.submit_score("rookie-oval", "racer", 12345.0)
	var r: Variant = UiData.record("rookie-oval", "racer")
	t.check(r != null and is_equal_approx(float(r.time), 130.5) and (r.splits as Array).size() == 3 and UiData.best_score("rookie-oval", "racer") == 12345,
		"records and best scores come from the save file")
	t.check(UiData.record("rookie-oval", "kestrel") == null, "per car")
	# a ghost: a real (short) recording packed for this track
	var track := Tracks.build("rookie-oval")
	UiData.use_tracks([track])
	var rec := Replay.GhostRecorder.new()
	var car := Car.new(track)
	var pilot := Autopilot.basic(track)
	rec.add(0, car, true)
	for s in range(1, 120):
		car.step(track, pilot.drive(car), 1.0 / 60.0)
		rec.add(s, car, s == 119)
	SaveData.save_ghost("rookie-oval", "racer", Replay.pack_ghost(rec, {"track": track, "laps": 3, "time": 119 / 60.0, "car": "racer"}))
	t.check(UiData.has_ghost("rookie-oval", "racer"), "Ghost: Saved when a fitting ghost is in the file")
	SaveData.save_ghost("rookie-oval", "racer", Replay.pack_ghost(rec, {"track": track, "laps": 1, "time": 119 / 60.0, "car": "racer"}))
	t.check(not UiData.has_ghost("rookie-oval", "racer"), "a ghost for other laps doesn't count")
	# settings
	t.check(UiData.get_setting("quality") == "high", "quality 'auto' (the file's default) reads as High")
	UiData.set_setting("quality", "low")
	UiData.set_setting("ui_scale", 1.25)
	UiData.set_setting("fullscreen", true)
	UiData.set_setting("ghost", false)
	SaveData.use_file(path) # read back from the file
	t.check(UiData.get_setting("quality") == "low" and is_equal_approx(float(UiData.get_setting("ui_scale")), 1.25) and
		UiData.get_setting("fullscreen") == true and UiData.get_setting("ghost") == false, "settings are written to the file and read back")
	SaveData.set_setting("vsync", "yes")
	SaveData.set_setting("ui_scale", [1])
	t.check(UiData.get_setting("vsync") == true and UiData.get_setting("ui_scale") == "auto", "a stored value of the wrong type reads as the default")
	var got := []
	UiData.on_setting_changed = func(k: String, v: Variant) -> void: got.append([k, v])
	UiData.set_setting("car", "drifter")
	UiData.on_setting_changed = Callable()
	t.check(got == [["car", "drifter"]] and UiData.picked_car() == "drifter" and SaveData.get_setting("car") == "drifter", "the picked car: saved, and the game is told")
	UiData.set_ai_status({"generation": 8, "fitness": 1500.0, "sizes": [18, 12, 2], "trained_on": ["rookie-oval"], "walls": "ride", "best_times": {"rookie-oval": {"lap": 47.0, "finish": 47.0}}})
	t.check(UiData.ai_status().ready and UiData.ai_best(0) == 47.0, "the AI status and its best lap reach the menu")
	var labels := UiData.network_labels()
	t.check((labels.inputs as Array).size() == 18 and labels.outputs == ["steer", "throttle"], "network labels from ai/sensors.gd")
	UiData.reset()
	t.check(UiData.record("rookie-oval", "racer") == null and UiData.get_setting("quality") == "high", "reset(): back to the in-memory store (tests)")
	UiData.use_tracks([])


func _helpers(t) -> void:
	t.section("race helpers (playMode.js)")
	var track := Tracks.build("rookie-oval")
	var car := Car.new(track)
	var race := RaceState.new(track)
	var pilot := Autopilot.medal(track, 24.0, 1.3, false)
	while race.next_gate < 1:
		car.step(track, pilot.drive(car), 1.0 / 60.0)
		race.update(car, 1.0 / 60.0)
	var r: Dictionary = race.respawn
	for i in 120:
		car.step(track, pilot.drive(car), 1.0 / 60.0)
	var speed := JsMath.hypot2(float(r.vx), float(r.vz))
	PlayMode.respawn_car(car, race, track, true)
	t.check(absf(car.idx - (int(r.idx) + PlayMode.RESPAWN_AHEAD)) <= 1 and absf(car.speed - speed) < 1e-6,
		"respawn: 6 samples past the checkpoint at the speed it had there (sample %d -> %d, %.2f m/s)" % [int(r.idx), car.idx, car.speed])
	PlayMode.respawn_car(car, race, track, false)
	t.check(car.speed == 0.0, "a stuck AI respawns standing")
	var w := {"best": car.prog, "at": 0.0}
	race.time = 2.9
	t.check(not PlayMode.is_stuck(w, car, race), "not stuck before 3 s")
	race.time = 3.1
	t.check(PlayMode.is_stuck(w, car, race), "stuck after 3 s without 2 samples of progress")
	car.place(track, 100, {"x": track.px[100], "z": track.pz[100], "yaw": track.heading(100), "vx": sin(track.heading(100)) * 40.0,
		"vz": cos(track.heading(100)) * 40.0, "idx": 100, "laps": 0})
	var ctl := Car.Controls.new()
	var steps := 0
	while car.speed > 0.5 and steps < 1200:
		car.step(track, PlayMode.roll_out(car, track, ctl), 1.0 / 60.0)
		steps += 1
	t.check(car.speed <= 2.0 and car.forward_speed >= -0.1 and not car.hit_wall, "roll-out after the finish brakes to a stop, never into reverse (%d steps)" % steps)


func _app(t) -> void:
	t.section("the app: modes")
	var path := SAVE
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	SaveData.use_file(path)
	var app: GameApp = (load("res://main.tscn") as PackedScene).instantiate()
	t.tree.root.add_child(app)
	t.check(app.mode == app.menu_mode and app.ui.menu.visible and not app.ui.hud.visible, "starts on the menu")
	t.check(app.tracks.size() == 15 and app.world.track == app.tracks[0], "15 tracks, the first one shown")
	t.check(app.ui.input == app.input and app.ui.menu.input == app.input, "the interface reads the game's input")
	# (the player's own network first: the opponent "My AI"; the AI levels are checked in _app_career)
	app.ui.menu.select_opponent(UiData.MY_AI)
	t.check(app.ui.menu.get("_ghost_btn").disabled and app.network.is_empty(), "no AI network yet: Race the AI ghost is off")
	app.play("ai", false)
	var msg: Label = app.message.get("_text")
	t.check(app.mode == app.menu_mode and (not AiLink.ready() or (app.message.visible and msg.text.contains("Racer has no trained AI network") and
		msg.text.contains("Train the AI"))), "Watch the AI without a network stays on the menu, saying so (and how to train one)")
	app.message.close()
	var m: Node = app.start_play({"track": app.tracks[0], "driver": "human"})
	t.check(app.mode == m and m.get("phase") == "countdown" and app.ui.hud.visible and not app.ui.menu.visible, "Drive: the race mode with the HUD")
	app.input.held = {"accelerate": true}
	for i in 60 * 4:
		app.mode.update(1.0 / 60.0)
	app.input.held = {}
	var car: Car = m.get("car")
	t.check(m.get("phase") == "race" and car.speed > 10.0 and int(m.get("race_step")) > 0, "after the countdown the car drives (%.1f m/s)" % car.speed)
	app.input.pressed["menu"] = true
	app.mode.update(1.0 / 60.0)
	t.check(app.mode == app.menu_mode and app.ui.menu.visible and not app.ui.hud.visible, "Esc: back to the menu")
	var fixture := "res://tests/fixtures/game_net.json"
	if FileAccess.file_exists(fixture):
		var err := app.load_network_file(ProjectSettings.globalize_path(fixture))
		t.check(err == "" and not app.network.is_empty() and not app.ui.menu.get("_ghost_btn").disabled, "a network file loads: the AI buttons are on")
		app.play("ai", false)
		t.check(app.mode != app.menu_mode and app.mode.get("driver") == "ai", "Watch the AI")
		for i in 60 * 6:
			app.mode.update(1.0 / 60.0)
		t.check((app.mode.get("car") as Car).prog > 20.0, "the AI drives")
		app.show_menu()
		app.play("human", true)
		t.check(app.mode.get("with_ghost") == true, "Race the AI ghost")
		app.show_menu()
		var saved: Variant = SaveData.load_network()
		t.check(saved is Dictionary and AiLink.parse_network_file(saved).has("net"), "the loaded network is kept in the save file")
	app.train()
	if not AiLink.ready() or not ResourceLoader.exists(app.TRAIN_MODE_PATH):
		t.check(app.message.visible, "Train the AI without the AI: a note")
	else:
		# modes/train_mode.gd's interface: setup(app, opts), enter/update/exit and its signals
		var tm := app.train_mode
		t.check(app.mode == tm and tm != null and tm.get_parent() == app, "Train the AI opens the training screen")
		t.check(not app.ui.menu.visible and not app.ui.hud.visible, "the menu and the HUD are hidden there")
		tm.update(1.0 / 60.0)
		if not app.network.is_empty():
			tm.emit_signal("watch_requested", app.tracks[1], app.network.net, "racer")
			t.check(app.mode != tm and app.mode.get("driver") == "ai" and app.mode.get("track") == app.tracks[1],
				"Watch best: the AI drives the training track")
			t.check(tm.is_queued_for_deletion(), "the training screen is freed (its session is static)")
			(app.mode.get("return_to") as Callable).call()
			t.check(app.mode == app.train_mode and app.train_mode != tm, "Esc after Watch best: back to (a new) training screen")
			app.train_mode.emit_signal("race_requested", app.tracks[1], app.network.net, "racer")
			t.check(app.mode.get("driver") == "human" and app.mode.get("with_ghost") == true, "Race best: the player races the AI ghost")
			(app.mode.get("return_to") as Callable).call()
			t.check(app.mode == app.train_mode, "and back to training")
			var gen0: Variant = UiData.ai_status().get("generation")
			var kept := {"net": app.network.net, "meta": {"generation": 42, "fitness": 2000.0}}
			app.train_mode.emit_signal("network_saved", kept, "racer")
			t.check(app.network == kept and UiData.ai_status().get("generation") == 42,
				"a network saved by training becomes the menu's (generation %s -> 42)" % str(gen0))
			var kept_t := {"net": app.network.net, "meta": {"generation": 5, "fitness": 900.0, "car": "thunder"}}
			app.train_mode.emit_signal("network_saved", kept_t, "thunder")
			t.check(app.network == kept and UiData.ai_status().get("generation") == 42 and app.network_for("thunder") == kept_t,
				"a network trained with another car (the Thunder) is that car's: the menu's Racer AI stays")
		# Max speed: the screen's overlay shows and the app stops drawing the 3D view
		var ov: CanvasItem = app.train_mode.get("dash").get("overlay")
		ov.visible = true
		app._sync_3d()
		t.check(app.get_viewport().disable_3d, "training at Max (its overlay shown): no 3D drawing")
		ov.visible = false
		app._sync_3d()
		t.check(not app.get_viewport().disable_3d, "1x / Fast: the 3D view draws again")
		ov.visible = true
		app._sync_3d()
		app.train_mode.emit_signal("exit_requested")
		t.check(app.mode == app.menu_mode and app.ui.menu.visible, "Menu / Esc on the training screen: back to the menu")
		t.check(not app.get_viewport().disable_3d, "leaving the training screen at Max: the 3D view draws again")
	if app.mode != app.menu_mode:
		app.show_menu()
	if AiLink.ready() and FileAccess.file_exists(fixture):
		_app_cars(t, app, fixture)
	if app.mode != app.menu_mode:
		app.show_menu()
	if AiLink.ready():
		_app_career(t, app)
	if app.mode != app.menu_mode:
		app.show_menu()
	app.free()
	UiData.reset()


## The AI networks per car: the menu's AI block, Watch the AI, Race the AI ghost and Load
## network… use the picked car's network, which drives that car.
func _app_cars(t, app: GameApp, fixture: String) -> void:
	t.section("the app: an AI network per car")
	var menu: Node = app.ui.menu
	var msg: Label = app.message.get("_text")
	SaveData.give_car("dune") # (the shop is checked in _app_career)
	menu.select_car("racer")
	var racer_net: Dictionary = app.network
	menu.select_car("dune")
	var st := UiData.ai_status()
	t.check(app.network.is_empty() and not st.ready and menu.get("_ghost_btn").disabled and menu.get("_watch_btn").disabled and
		(menu.get("_ai_cap") as Label).text == "AI driver · Dune" and str(menu.get("_ai_status_text")).contains("No Dune network yet") and
		str(menu.get("_ai_status_text")).contains("Train the AI"), "pick the Dune (no network): the AI block says so and offers to train one; Watch and Race the AI ghost are off")
	app.play("human", true)
	t.check(app.mode == app.menu_mode and app.message.visible and msg.text.contains("The Dune has no trained AI network yet"), "Race the AI ghost with the Dune: a note, still on the menu")
	app.message.close()
	t.check(app.load_network_file(ProjectSettings.globalize_path(fixture)) == "" and app.message.visible and msg.text.contains("trained with the Racer") and
		msg.text.contains("drives the Dune"), "loading a Racer network with the Dune picked: allowed, with a note")
	app.message.close()
	st = UiData.ai_status()
	var dune_saved: Variant = SaveData.load_network("dune")
	t.check(not app.network.is_empty() and app.network != racer_net and st.ready and st.get("car") == "dune" and st.get("trained_car") == "racer" and
		str(menu.get("_ai_status_text")).contains("trained with the Racer") and dune_saved is Dictionary and SaveData.load_network("racer") is Dictionary and
		not menu.get("_watch_btn").disabled, "it is the Dune's network now (in the save file); the AI block says it was trained with the Racer")
	app.play("ai", false)
	var car: Car = app.mode.get("car")
	t.check(app.mode != app.menu_mode and app.mode.get("driver") == "ai" and car.spec == Cars.get_car("dune").spec and
		(app.mode.get("model") as CarModel).car_id == "dune" and app.ui.hud.get("_mode").text.contains("Dune"), "Watch the AI: the Dune's network drives the Dune")
	for i in 60 * 6:
		app.mode.update(1.0 / 60.0)
	t.check(car.prog > 20.0, "and drives it (%.0f m)" % car.prog)
	app.show_menu()
	app.play("human", true)
	var gh: Dictionary = app.mode.get("ghost")
	t.check(app.mode.get("with_ghost") == true and (gh.car as Car).spec == Cars.get_car("dune").spec and (app.mode.get("ghost_model") as CarModel).car_id == "dune" and
		(app.mode.get("car") as Car).spec == Cars.get_car("dune").spec, "Race the AI ghost: the Dune against the Dune AI's ghost")
	app.show_menu()
	menu.select_car("racer")
	t.check(app.network == racer_net and UiData.ai_status().get("car") == "racer" and UiData.ai_status().get("trained_car") == "racer" and
		not str(menu.get("_ai_status_text")).contains("trained with"), "back to the Racer: its own network again")
	menu.select_car("kestrel")
	t.check(app.network.is_empty() and SaveData.network_cars() == PackedStringArray(["racer", "dune"]), "the Kestrel has none; the save file holds the Racer's and the Dune's")
	menu.select_car("racer")



## Feed the race in progress with `pilot` (the e2e tests' way: the input layer's stick and
## triggers, so the car goes through the game's own controls()); an invalid pilot stops it.
func _feed(app: GameApp, pilot: Autopilot) -> void:
	var inp := app.input
	inp.held.clear()
	inp.pad_steer = 0.0
	inp.pad_throttle = 0.0
	inp.pad_brake = 0.0
	if pilot == null:
		inp.feed = Callable()
		return
	inp.feed = func(_speed: float) -> void:
		var c: Car.Controls = pilot.drive(app.mode.get("car"))
		inp.pad_steer = c.steer
		inp.pad_throttle = maxf(0.0, c.throttle)
		inp.pad_brake = maxf(0.0, -c.throttle)
		if c.nitro > 0.0:
			inp.held["nitro"] = true
		else:
			inp.held.erase("nitro")


## Run the race mode `m` until cond() or `max_s` seconds of race steps.
func _run_until(m: Node, cond: Callable, max_s: float) -> void:
	var n := 0
	while not cond.call() and n < int(max_s * 60.0):
		m.update(1.0 / 60.0)
		n += 1


## v6.5.0: the career in the app, on a new save file: $0, 0 points and only the Racer; a locked
## car's Drive says how much money is missing, or (with the money) asks and buys it; Race the AI
## against a level is the shipped network with that level's speed cap, which finishes in its
## stored time; the finish pays the medal and the win (once); losing to the Elite pays nothing
## new; an older save file's medals are paid once, with a message.
func _app_career(t, app: GameApp) -> void:
	t.section("the app: money, points, the car shop and the AI opponents (v6.5.0)")
	var path := "user://test_game_career.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	SaveData.use_file(path)
	var menu: Node = app.ui.menu
	var msg: Label = app.message.get("_text")
	var money_l: Label = menu.get("_money_l")
	var points_l: Label = menu.get("_points_l")
	var drive_btn: Button = menu.get("_drive_btn")
	var ghost_btn: Button = menu.get("_ghost_btn")
	menu.select_car("racer")
	menu.select_opponent("rookie")
	t.check(UiData.money() == 0 and UiData.points() == 0 and SaveData.owned_cars() == PackedStringArray(["racer"]) and money_l.text == "$0" and
		points_l.text == "0 pts" and drive_btn.text == "DRIVE", "a new career: $0, 0 points, only the Racer (the menu's header: %s, %s)" % [money_l.text, points_l.text])

	# the shop: a locked car's Drive
	menu.select_car("kestrel")
	var lock: Label = menu.get("_car_lock")
	t.check(drive_btn.text == "LOCKED" and lock.visible and lock.text.contains("$10,000") and ghost_btn.disabled and not (menu.get("_watch_btn") as Button).disabled,
		"the Kestrel picked: locked at $10,000 (Drive reads LOCKED, Race the AI is off, Watch the AI is on)")
	app.play("human", false)
	t.check(app.mode == app.menu_mode and app.message.visible and not app.message.asking and msg.text.contains("costs $10,000") and
		msg.text.contains("$10,000 more to go"), "Drive it with $0: a message says how much is missing; still on the menu")
	app.message.close()
	SaveData.add_money(12500)
	menu.refresh()
	t.check(drive_btn.text == "BUY $10,000" and money_l.text == "$12,500", "with $12,500 Drive reads BUY $10,000")
	app.play("human", false)
	t.check(app.message.asking and msg.text.contains("costs $10,000") and msg.text.contains("$2,500 is left") and app.mode == app.menu_mode,
		"BUY asks first (what it costs, what is left)")
	app.message.close()
	t.check(not SaveData.owns_car("kestrel") and UiData.money() == 12500, "Cancel: nothing bought")
	app.play("human", false)
	app.message.confirm()
	t.check(SaveData.owns_car("kestrel") and UiData.money() == 2500 and drive_btn.text == "DRIVE" and not lock.visible and money_l.text == "$2,500" and
		app.mode == app.menu_mode and not app.message.visible, "yes: the Kestrel is yours, $2,500 left (the header says so)")
	app.play("human", false)
	t.check(app.mode != app.menu_mode and str(app.mode.get("car_def").id) == "kestrel", "now Drive drives it")
	app.show_menu()

	# Race the Rookie AI on Seaside Stunts with the Racer (the author run of the medal sweep)
	var tid := "seaside-stunts"
	var ti := Tracks.ids().find(tid)
	menu.select_car("racer")
	menu.select(ti)
	var track: BuiltTrack = app.tracks[ti]
	var rookie_t := Opponents.time_of(tid, "racer", "rookie")
	var elite_t := Opponents.time_of(tid, "racer", "elite")
	var st := str(menu.get("_ai_status_text"))
	var pays: int = int(Economy.payout(tid, "", "rookie", PackedStringArray()).money)
	t.check(rookie_t > 0.0 and st.contains("Rookie AI") and st.contains(UiFormat.time(rookie_t)) and st.contains("+" + UiFormat.money(pays)) and
		ghost_btn.text == "Race the Rookie AI" and not ghost_btn.disabled, "the AI block: the Rookie AI finishes Seaside Stunts in %s; beating it pays %s" % [
		UiFormat.time(rookie_t), UiFormat.money(pays)])
	var money0 := UiData.money()
	var points0 := UiData.points()
	app.play("human", true)
	var m: Node = app.mode
	t.check(m != app.menu_mode and m.get("with_ghost") == true and m.get("level") == "rookie" and float(m.get("cap")) == Opponents.cap_of(tid, "racer", "rookie") and
		str(app.ui.hud.get("_mode").text).begins_with("VS ROOKIE AI") and (m.get("ghost").car as Car).spec == Cars.get_car("racer").spec,
		"Race the Rookie AI: its car next to yours (cap %.1f m/s); the HUD says VS ROOKIE AI" % float(m.get("cap")))
	var medals := Medals.medal_times(track, "racer")
	_feed(app, Autopilot.medal(track, float(medals.run.aLat), float(medals.run.lookK), true, Autopilot.DECEL, Cars.spec("racer")))
	_run_until(m, func() -> bool: return m.get("phase") == "finished", 200.0)
	_feed(app, null)
	var race: RaceState = m.get("race")
	var fs: Dictionary = m.get("finish_state")
	var p: Dictionary = fs.get("payout", {})
	var ids: Array = (p.get("items", []) as Array).map(func(it: Dictionary) -> String: return String(it.id))
	var want := ["bronze", "silver", "gold", "author", "ai-rookie"]
	var w_money := 0
	var w_points := 0
	for id: String in want:
		w_money += int(Economy.reward(tid, id).money)
		w_points += int(Economy.reward(tid, id).points)
	t.check(race.finished and absf(race.finish_time - float(medals.author)) < 0.0005 and ids == want and int(p.money) == w_money and int(p.points) == w_points and
		p.get("won") == true and p.get("level") == "rookie" and str(fs.get("lines", [""])[0]).contains("Rookie AI hasn't finished: you win!") and
		UiData.money() == money0 + w_money and UiData.points() == points0 + w_points and app.ui.hud.panel_open,
		"the author time beats the Rookie AI: paid bronze, silver, gold, author and the Rookie win, %s and %d pts (the finish panel's payout)" % [UiFormat.money(w_money), w_points])
	var gr: RaceState = m.get("ghost").race
	_run_until(m, func() -> bool: return gr.finished, 120.0)
	t.check(gr.finished and absf(gr.finish_time - rookie_t) < 0.0005, "the Rookie AI finishes in its stored time %s (%s: the race against it is the one tools/opponents.gd measured)" % [
		UiFormat.time(rookie_t), RaceState.format_time(gr.finish_time)])
	app.show_menu()
	t.check(money_l.text == UiFormat.money(money0 + w_money) and str(menu.get("_ai_status_text")).contains("Beaten: paid"), "back on the menu: %s; the Rookie AI is paid" % money_l.text)

	# lose to the Elite AI: nothing new is paid
	menu.select_opponent("elite")
	var money1 := UiData.money()
	app.play("human", true)
	m = app.mode
	_feed(app, Autopilot.medal(track, 15.0, 1.3, false, Autopilot.DECEL, Cars.spec("racer")))
	_run_until(m, func() -> bool: return m.get("phase") == "finished", 200.0)
	_feed(app, null)
	race = m.get("race")
	gr = m.get("ghost").race
	fs = m.get("finish_state")
	p = fs.get("payout", {})
	t.check(race.finished and gr.finished and absf(gr.finish_time - elite_t) < 0.0005 and race.finish_time > gr.finish_time and
		str(fs.get("lines", [""])[0]).contains("the AI wins by") and m.get("level") == "elite" and p.get("won") == false and (p.get("items", [1]) as Array).is_empty() and
		int(p.get("money", -1)) == 0 and UiData.money() == money1, "a slower run (%s) loses to the Elite AI (%s, its stored time): nothing new is paid" % [
		RaceState.format_time(race.finish_time), RaceState.format_time(gr.finish_time)])
	app.show_menu()

	# My AI: the player's own network as before (no AI rewards)
	menu.select_opponent(UiData.MY_AI)
	t.check(ghost_btn.text == "Race my AI" and UiData.get_setting("opponent") == UiData.MY_AI, "My AI: the buttons race and watch the car's own network again")
	menu.select_opponent("rookie")

	# an older save file: its medals are paid once, with a message
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 3, "records": {"rookie-oval": {"racer": {"time": float(Medals.medal_times(app.tracks[0], "racer").gold) - 0.1,
		"splits": [], "physics": Car.PHYSICS_VERSION, "sig": app.tracks[0].signature(), "date": "x"}}}}))
	f.close()
	SaveData.use_file(path)
	app._welcome()
	t.check(app.message.visible and msg.text.contains("3 medals you already hold paid $1,600 and 70 points") and money_l.text == "$1,600" and
		UiData.money() == 1600, "a version 3 save file with a gold time: paid $1,600 and 70 points once, and a message says so")
	app.message.close()
	app._welcome()
	t.check(not app.message.visible, "the message shows once")
	SaveData.use_file(SAVE)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	menu.refresh()
