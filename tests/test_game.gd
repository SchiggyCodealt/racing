extends RefCounted
## test_game.gd: headless checks of the game shell (game/, modes/): the input layer (InputMap
## actions, keyboard steering ramps, the stick and trigger curves, key presses), the save data
## wiring of the interface (UiData -> SaveData), the app's mode switching and the race modes'
## helpers (respawn, roll-out, the stuck watchdog, a short race through the play mode), and
## (v6.5.0) the career in the app: the car shop, races against the AI opponents and their payout;
## (v6.7.0) the terminal's commands (game/terminal.gd: every command, bad input, Tab, the save file)
## and the terminal in the app (opened from the menu and Settings, the menu redrawn, ` in a race);
## (v6.11.0) car upgrades: the car picker's part chips in the app (asking first, money short, a
## locked car, the top level), the races driving the upgraded car (the AI opponents stock), and the
## terminal's upgrade and buy <car> <part>; (v6.12.0) sound: the buses and their limiter, the volume
## settings (applied, saved, read back, old files), the background mute, the sound files, pooled
## effects, the music's cross-fade and ducking, and in the app the sounds of the countdown, the
## checkpoints, a wall hit, the finish and its stinger, the shop's cash and refusals, the menu's
## clicks (all on the dummy audio driver: headless, nothing is heard and nothing is printed).
## The real game under a display is checked by tests/e2e/game_e2e.gd.

const AiLink := preload("res://game/ai_link.gd")
const PlayMode := preload("res://modes/play_mode.gd")
const Terminal := preload("res://game/terminal.gd")
const SAVE := "user://test_game_save.json"


func run(t) -> bool:
	_input(t)
	_save_wiring(t)
	_helpers(t)
	_app(t)
	_terminal(t)
	_terminal_upgrades(t)
	_audio(t)
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
		"menu_terminal": [KEY_QUOTELEFT],
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
	t.check((labels.inputs as Array).size() == 19 and labels.inputs[18] == "nitro tank" and labels.outputs == ["steer", "throttle", "nitro"],
		"network labels from ai/sensors.gd (v6.15: the nitro tank input and the nitro output)")
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
	SaveData.set_setting("vol_music", 0.3) # (v6.12: a saved volume is on its bus from the start)
	var app: GameApp = (load("res://main.tscn") as PackedScene).instantiate()
	t.tree.root.add_child(app)
	t.check(app.mode == app.menu_mode and app.ui.menu.visible and not app.ui.hud.visible, "starts on the menu")
	var music_db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))
	t.check(is_equal_approx(music_db, GameAudio.volume_db(0.3)), "a saved volume applies from the start (music 30%%: %.1f dB)" % music_db)
	UiData.set_setting("vol_music", 0.7) # (the app applies it)
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
	if AiLink.ready() and FileAccess.file_exists(fixture):
		_app_nitro(t, app, fixture)
	if app.mode != app.menu_mode:
		app.show_menu()
	if AiLink.ready():
		_app_career(t, app)
	if app.mode != app.menu_mode:
		app.show_menu()
	_app_terminal(t, app)
	if app.mode != app.menu_mode:
		app.show_menu()
	_app_upgrades(t, app)
	if app.mode != app.menu_mode:
		app.show_menu()
	_app_unlock(t, app)
	if app.mode != app.menu_mode:
		app.show_menu()
	if AiLink.ready():
		_app_field(t, app)
	if app.mode != app.menu_mode:
		app.show_menu()
	if AiLink.ready():
		_app_cup(t, app)
	if app.mode != app.menu_mode:
		app.show_menu()
	_app_audio(t, app)
	if app.mode != app.menu_mode:
		app.show_menu()
	# (a track still being built on a worker thread runs an app method: wait for it before freeing the app)
	app.show_track(app.world.track)
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



## v6.15: the AI uses nitro in Watch the AI (its tank on the HUD); races against the AI (the AI ghost of
## My AI or a level, the training screen's Race best) have no nitro for anyone; Drive keeps it.
func _app_nitro(t, app: GameApp, fixture: String) -> void:
	t.section("the app: AI nitro, and no nitro in races against the AI (v6.15)")
	var menu: Node = app.ui.menu
	var hud: Node = app.ui.hud
	menu.select_car("racer")
	menu.select(0)
	var note: Label = menu.get("nitro_note")
	t.check(note != null and note.text == "No nitro vs AI" and note.is_visible_in_tree() and note.tooltip_text.contains("no nitro for anyone"), "the menu says: No nitro vs AI (the tooltip says more)")
	# a network that leans on nitro: the test file's network with its nitro output's bias raised
	var parsed := AiLink.parse_network_file(JSON.parse_string(FileAccess.get_file_as_string(fixture)))
	var net: NeuralNetwork = (parsed.net as NeuralNetwork).clone()
	net.biases[net.biases.size() - 1][Sensors.NITRO_OUTPUT] = 3.0
	app.adopt_network({"net": net, "meta": parsed.meta}, {}, "racer")
	menu.select_opponent(UiData.MY_AI)
	app.play("ai", false)
	var m: Node = app.mode
	var car: Car = m.get("car")
	var boosted := false
	var refilled := false
	var low := 1.0
	var gauge_shown := false
	for i in 60 * 30:
		var before := car.nitro
		m.update(1.0 / 60.0)
		boosted = boosted or car.boosting
		low = minf(low, car.nitro)
		refilled = refilled or (car.nitro > before + 1e-9 and m.get("phase") == "race")
		gauge_shown = gauge_shown or (hud.get("_nitro") as Control).visible
	t.check(m.get("driver") == "ai" and m.get("nitro_on") == true and boosted and low < 0.5 and gauge_shown and not (hud.get("_nitro_off") as Control).visible,
		"Watch the AI: the AI burns its nitro (the tank down to %d %%) and the HUD shows its tank" % roundi(low * 100.0))
	t.check(refilled, "and its tank refills at clean checkpoints, as in training")
	app.show_menu()
	# Race my AI: nobody has nitro
	app.play("human", true)
	m = app.mode
	car = m.get("car")
	var gh: Dictionary = m.get("ghost")
	var gcar: Car = gh.car
	var keys := PackedStringArray()
	for k: Array in hud.get("_keys_data"):
		keys.append(str(k[1]))
	t.check(m.get("with_ghost") == true and m.get("nitro_on") == false and car.nitro == 0.0 and gcar.nitro == 0.0 and (gh.ai as Object).get("refill") == false
		and not keys.has("nitro") and not (m.get("score") as ScoreState).refill, "Race my AI: both tanks empty, no refills (the style points' nor the AI's), no nitro key hint")
	app.input.held = {"accelerate": true, "nitro": true}
	var top_off := false
	for i in 60 * 12:
		m.update(1.0 / 60.0)
		top_off = top_off or car.boosting or gcar.boosting or car.nitro > 0.0 or gcar.nitro > 0.0
	app.input.held = {}
	t.check(not top_off and m.get("phase") == "race", "12 s with the nitro key held: no nitro burns and no tank fills (the AI's neither)")
	t.check(not (hud.get("_nitro") as Control).visible and (hud.get("_nitro_off") as Label).visible and (hud.get("_nitro_off") as Label).text == "No nitro in AI races",
		"the HUD hides the nitro gauge and says: No nitro in AI races")
	app.show_menu()
	# an AI level: the same
	menu.select_opponent("rookie")
	app.play("human", true)
	m = app.mode
	t.check(m.get("level") == "rookie" and m.get("nitro_on") == false and (m.get("car") as Car).nitro == 0.0 and ((m.get("ghost") as Dictionary).car as Car).nitro == 0.0,
		"Race the Rookie AI: no nitro either")
	app.show_menu()
	# Drive keeps it
	m = app.start_play({"track": app.tracks[0], "driver": "human"})
	keys = PackedStringArray()
	for k: Array in hud.get("_keys_data"):
		keys.append(str(k[1]))
	m.update(1.0 / 60.0)
	t.check(m.get("nitro_on") == true and (m.get("car") as Car).nitro == 1.0 and keys.has("nitro") and (hud.get("_nitro") as Control).visible
		and not (hud.get("_nitro_off") as Control).visible, "Drive: a full tank, the gauge and the nitro key as before")
	app.show_menu()
	menu.select_opponent(UiData.MY_AI)


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


## The texts of every Label under `n`.
func _texts(n: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if n is Label:
		out.append((n as Label).text.strip_edges())
	for c in n.get_children():
		out.append_array(_texts(c))
	return out


## v6.13.0: Race the field. The menu's button (off with My AI, a locked track's refused, an unowned
## car offered), a Pro field on Rookie Oval through the app: five AI cars on the grid ahead of you, the
## HUD's place and standings, the finish panel docked right with the field's rows and pay by place,
## the podium, the medal and the track it opens counting as in Drive, R and Esc.
func _app_field(t, app: GameApp) -> void:
	t.section("the app: Race the field (v6.13.0)")
	var path := "user://test_game_field.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	SaveData.use_file(path)
	var menu: Node = app.ui.menu
	var msg: Label = app.message.get("_text")
	var btn: Button = menu.get("_field_btn")
	menu.select_car("racer")
	menu.select(0)
	menu.select_opponent(UiData.MY_AI)
	var off_my := btn.disabled
	app.play_field()
	var refused_my := app.mode == app.menu_mode and app.message.visible and msg.text.contains("Pick their level")
	app.message.close()
	menu.select_opponent("pro")
	var win_pay := UiData.field_pays(Tracks.ids()[0], "racer", "pro", 1)
	t.check(off_my and refused_my and not btn.disabled and btn.text == "Race the field" and btn.tooltip_text.contains("+" + UiFormat.money(int(win_pay.money))),
		"the menu: Race the field is off with My AI (and refused, asking for a level); with the Pro AI picked it is on, its tooltip saying a win pays %s" % UiFormat.money(int(win_pay.money)))
	menu.select(1)
	app.play_field()
	t.check(app.mode == app.menu_mode and app.message.visible and msg.text.contains("opens when you win"), "a locked track's field race is refused, saying what opens it")
	app.message.close()
	menu.select(0)
	menu.select_car("kestrel")
	app.play_field()
	t.check(app.mode == app.menu_mode and app.message.visible and msg.text.contains("costs"), "a car not owned: the shop's message, no race")
	app.message.close()
	menu.select_car("racer")
	app.play_field()
	var m: Node = app.mode
	var fr: FieldRace = m.get("field") if m != app.menu_mode else null
	t.check(fr != null and m.name == "FieldMode" and str(app.ui.hud.get("_mode").text).begins_with("PRO FIELD") and fr.racers.size() == 6 and (m.get("ai_models") as Array).size() == 5,
		"Race the field: the field mode, the HUD says PRO FIELD, six cars (five AI models in the world)")
	if fr == null:
		return
	var track: BuiltTrack = m.get("track")
	var car: Car = m.get("car")
	var ahead := true
	for k in 5:
		ahead = ahead and fr.racers[k].car.prog > car.prog and fr.racers[k].car != car
	t.check(fr.racers[fr.player_index].car == car and absf(car.prog - float(track.start_idx)) < 0.05 and ahead and m.get("phase") == "countdown",
		"the grid: your car last, on the usual start spot (sample %d), the five AI ahead of it" % track.start_idx)
	var empty := true
	for r: FieldRace.Racer in fr.racers:
		empty = empty and r.car.nitro == 0.0 and (r.player or r.driver.get("refill") == false)
	t.check(empty and m.get("nitro_on") == false and not (m.get("score") as ScoreState).refill, "no nitro in the field (v6.15): every tank empty, no refills")
	var medals := Medals.medal_times(track, "racer")
	_feed(app, Autopilot.medal(track, float(medals.run.aLat), float(medals.run.lookK), true, Autopilot.DECEL, Cars.spec("racer")))
	_run_until(m, func() -> bool: return float((m.get("race") as RaceState).time) > 20.0, 40.0)
	var ft: PackedStringArray = app.ui.hud.get("field_text")
	var bd: Dictionary = m.get("board")
	t.check(ft.size() == 9 and ft[0] == "P%d/6" % int(bd.pos) and int(bd.of) == 6 and (bd.rows as Array).size() == 6 and ft[3 + int(bd.pos) - 1].contains("YOU"),
		"20 s in, the HUD's field block: %s, %s, %s and the standings" % [ft[0], ft[1], ft[2]])
	var money0 := UiData.money()
	_run_until(m, func() -> bool: return m.get("phase") == "finished", 200.0)
	_feed(app, null)
	var place := fr.position(fr.player_index)
	var fs: Dictionary = m.get("finish_state")
	var pay: Dictionary = fs.get("payout", {})
	var fids: PackedStringArray = []
	for it: Dictionary in pay.get("items", []):
		if String(it.kind) == "field":
			fids.append(String(it.id))
	var panel: FinishPanel = app.ui.hud.finish
	var ptexts := _texts(panel)
	var place_line := "%s of 6 · Pro field" % Field.place_name(place)
	var has_line := ptexts.has(Field.place_name(place)) and ptexts.has("of 6 · Pro field")
	t.check(m.get("phase") == "finished" and fids == Economy.field_ids("pro", place) and UiData.money() == money0 + int(pay.money) and int(pay.place) == place and
		fs.get("dock") == "right" and has_line and ptexts.has("You"),
		"the finish: %s, paid by place (%s: %s in all with the medal), the finish panel docked right with the field (\"%s\")" % [
		Field.place_name(place), ", ".join(fids), UiFormat.money(int(pay.money)), place_line])
	t.check(String(pay.get("medal", "")) != "" and float(SaveData.get_record(track.id, "racer").get("time", 0.0)) > 0.0 and UiData.track_open(1),
		"the run counts as in Drive: its %s medal, the record (%s) and the track it opens (Hairpin Valley)" % [String(pay.get("medal", "")), UiFormat.time(float(SaveData.get_record(track.id, "racer").get("time", 0.0)))])
	_run_until(m, func() -> bool: return m.get("podium_on") == true and fr.all_done(), 30.0)
	var pod: Podium = m.get("podium")
	var done := 0
	for r: Dictionary in fr.results():
		if is_finite(float(r.time)):
			done += 1
	var rows_now: Array = (m.get("finish_state") as Dictionary).get("field", {}).get("rows", [])
	var timed := 0
	for r: Dictionary in rows_now:
		if is_finite(float(r.time)):
			timed += 1
	t.check(pod != null and pod.visible and pod.has(1) and pod.has(2) and pod.has(3) and pod.camera.current and done == 6 and timed == 6,
		"the podium: the top three on their blocks, its camera on; every AI finished out of sight, the finish panel's times filled in (%d of 6)" % timed)
	app.input.pressed["restart"] = true
	m.update(1.0 / 60.0)
	var fr2: FieldRace = m.get("field")
	t.check(m.get("phase") == "countdown" and fr2 != fr and not pod.visible and m.get("podium_on") == false and not app.ui.hud.finish.visible,
		"R: the same field on the grid again, the podium and the panel gone")
	app.input.pressed["menu"] = true
	m.update(1.0 / 60.0)
	t.check(app.mode == app.menu_mode and app.ui.menu.visible, "Esc: back to the menu")
	SaveData.use_file(SAVE)


## v6.14.0: championships through the app, on a new save file: the menu's Cups button (the empty
## cabinet) and T open the cup screen; a locked cup is refused; with the tracks open a Pro Rookie Cup
## starts its first race (the field's grid, you last); race 1 driven by the medal autopilot: the finish
## panel's cup line and keys, R doesn't race it again, Enter goes to the standings (the menu with the cup
## screen, the next track picked, the cup in the save file); race 2 from your slot by the standings, Esc
## before the finish doesn't count it; race 2's results given, race 3 left at once: the trophy moment
## (the top three of the standings with their trophies on the podium, the final standings and the cup's
## pay on the panel, the trophy in the cabinet), Enter to the menu; the same cup again pays nothing new;
## Quit cup asks, then drops the cup and pays nothing.
func _app_cup(t, app: GameApp) -> void:
	t.section("the app: championships (v6.14.0)")
	var path := "user://test_game_cups.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	SaveData.use_file(path)
	app.cup = null
	var menu: MainMenu = app.ui.menu
	var cups: CupScreen = menu.cups
	var msg: Label = app.message.get("_text")
	menu.select_car("racer")
	menu.select(0)
	menu.refresh()
	var cab: CupCabinet = menu.get("_cups_btn")
	var empty_cab := cab.cells.size() == Cups.ids().size()
	for c: Dictionary in cab.cells:
		empty_cab = empty_cab and String(c.trophy) == ""
	app.input.press("KeyT")
	menu.handle_keys(app.input)
	var picker_ok := cups.visible and not cups.is_standings and cups.picked_cup == "rookie" and (cups.get("_start_btn") as Button).disabled
	t.check(empty_cab and cab.text == "" and cab.tooltip_text.contains("0 of 25") and picker_ok,
		"the menu's Cups button shows an empty cabinet (5 cups, 0 of 25 trophies); T opens the cup picker: the Rookie Cup picked but locked (START off) on a new career")
	app.start_cup("rookie", "pro")
	t.check(app.mode == app.menu_mode and app.cup == null and app.message.visible and msg.text.contains("Hairpin Valley"), "a locked cup is refused, naming the tracks still locked")
	app.message.close()
	SaveData.unlock_tracks(true)
	cups.refresh()
	cups.pick_level("pro")
	var info: String = (cups.get("_info") as RichTextLabel).get_parsed_text()
	var win := UiData.cup_pays("rookie", "pro", 1)
	t.check(not (cups.get("_start_btn") as Button).disabled and info.contains("+" + UiFormat.money(int(win.money))) and info.contains("you pick your car before each race"),
		"with the tracks open START is on: \"%s\"" % info)
	app.input.press("Enter")
	menu.handle_keys(app.input)
	t.check(menu.car_page.is_open and app.cup == null and app.mode == app.menu_mode and menu.car_page.event_text.begins_with("Rookie Cup · Pro field"),
		"v6.19: START CUP (Enter) asks for the car first: the car page (\"%s\"); no cup yet" % menu.car_page.event_text)
	app.input.press("Enter")
	menu.handle_keys(app.input)
	var m: Node = app.mode
	var fr: FieldRace = m.get("field") if m != app.menu_mode else null
	t.check(fr != null and not menu.car_page.is_open and app.cup != null and m.get("cup") == app.cup and str(app.ui.hud.get("_mode").text).begins_with("ROOKIE CUP · RACE 1/3 · PRO") and not cups.visible and
		fr.racers[fr.player_index].slot == 5 and SaveData.get_cup_run().get("cup") == "rookie",
		"Enter starts it: race 1 of 3 on Rookie Oval (%s), you last on the grid, the cup in the save file" % str(app.ui.hud.get("_mode").text))
	if fr == null:
		return
	var track: BuiltTrack = m.get("track")
	var medals := Medals.medal_times(track, "racer")
	_feed(app, Autopilot.medal(track, float(medals.run.aLat), float(medals.run.lookK), true, Autopilot.DECEL, Cars.spec("racer")))
	var money0 := UiData.money()
	_run_until(m, func() -> bool: return m.get("phase") == "finished", 200.0)
	_feed(app, null)
	var place := fr.position(fr.player_index)
	var fs: Dictionary = m.get("finish_state")
	var texts := _texts(app.ui.hud.finish)
	var cup_line := "Rookie Cup, race 1 of 3: +%d points" % Cups.points_for(place)
	t.check(m.get("phase") == "finished" and texts.has(cup_line) and texts.has("standings") and not texts.has("race again") and
		UiData.money() == money0 + int((fs.payout as Dictionary).money) and String((fs.payout as Dictionary).get("medal", "")) != "" and app.cup.races_done() == 0,
		"race 1 driven to the finish: %s, paid as a field race (%s with the medal), the panel says \"%s\" and Enter: standings" % [
		Field.place_name(place), UiFormat.money(int((fs.payout as Dictionary).money)), cup_line])
	app.input.pressed["restart"] = true
	m.update(1.0 / 60.0)
	var still: bool = app.mode == m and m.get("phase") == "finished"
	_run_until(m, func() -> bool: return m.get("podium_on") == true, 5.0)
	app.input.pressed["respawn"] = true
	m.update(1.0 / 60.0)
	var after1: Array = app.cup.races[0].keys() if app.cup != null and app.cup.races.size() > 0 else []
	t.check(still and app.mode == app.menu_mode and cups.visible and cups.is_standings and app.cup.races_done() == 1 and after1.size() == 6 and
		int(app.cup.races[0]["you"].place) == place and menu.selected_track == 1 and CupRun.from_dict(SaveData.get_cup_run()).to_dict() == app.cup.to_dict() and
		(cups.get("_table") as CupTable).rows.size() == 6 and (cups.get("_race_btn") as Button).text == "RACE 2: HAIRPIN VALLEY",
		"R after the finish doesn't race it again; Enter: the standings over the menu (six rows, you %s), Hairpin Valley picked behind them, the cup saved; RACE 2: HAIRPIN VALLEY" % Field.place_name(app.cup.place()))
	# race 2: from your slot by the standings; Esc before the finish doesn't count it (v6.19: Enter on the
	# standings opens the car page, Enter there starts the race)
	app.input.press("Enter")
	menu.handle_keys(app.input)
	app.input.press("Enter")
	menu.handle_keys(app.input)
	m = app.mode
	fr = m.get("field") if m != app.menu_mode else null
	var slot_ok := false
	if fr != null:
		var g := app.cup.grid()
		var me: Car = m.get("car")
		var tr2: BuiltTrack = m.get("track")
		slot_ok = fr.racers[fr.player_index].slot == g.find(Cups.PLAYER) and absf(me.prog - float(tr2.start_idx)) < 0.05 and tr2.id == "hairpin-valley"
		for k in Field.AI_COUNT:
			var r: FieldRace.Racer = fr.racers[k]
			slot_ok = slot_ok and String(r.info.id) == g[r.slot] and ((r.car.prog > me.prog) == (r.slot < fr.racers[fr.player_index].slot))
	t.check(slot_ok and str(app.ui.hud.get("_mode").text).contains("RACE 2/3"),
		"race 2 on Hairpin Valley: the grid in standings order (%s), you %s on the usual start spot, the cars ahead of you in the standings ahead of you" % [", ".join(app.cup.grid()), Field.place_name(app.cup.grid().find(Cups.PLAYER) + 1)])
	_run_until(m, func() -> bool: return m.get("phase") == "race", 5.0)
	app.input.pressed["menu"] = true
	m.update(1.0 / 60.0)
	t.check(app.mode == app.menu_mode and cups.is_standings and app.cup.races_done() == 1, "Esc during race 2: back to the standings, the race not counted (still 1 of 3 done)")
	# race 2's results given (you win it), race 3 started and left at once: the trophy moment
	var rows2: Array = [{"id": Cups.PLAYER, "place": 1}]
	for k in Field.AI_COUNT:
		rows2.append({"id": app.cup.drivers[k], "place": k + 2})
	app.cup_result(rows2)
	app.cup_standings()
	# (v6.19) the car page comes up before every cup race, with the cup's car picked: another car you own
	# becomes the cup's car from this race on; one you don't own is offered for sale and nothing starts
	menu.select_car("kestrel")
	cups.next_race.emit()
	var page_ok: bool = menu.car_page.is_open and UiData.picked_car() == "racer" and app.mode == app.menu_mode and menu.car_page.event_text.contains("race 3 of 3")
	menu.car_page.pick("kestrel")
	menu.car_page.press_start()
	var refused: bool = app.mode == app.menu_mode and app.cup.car == "racer" and app.message.visible and msg.text.contains("Kestrel costs")
	app.message.close()
	SaveData.give_car("kestrel")
	menu.refresh()
	var reads_start: bool = menu.car_page.start_btn.text == "START"
	app.input.press("Enter")
	menu.handle_keys(app.input)
	m = app.mode
	fr = m.get("field") if m != app.menu_mode else null
	if fr == null:
		t.check(false, "race 3 starts")
		return
	t.check(page_ok and refused and reads_start and app.cup.car == "kestrel" and SaveData.get_cup_run().get("car") == "kestrel" and str((m.get("car_def") as Dictionary).id) == "kestrel" and
		app.cup.races_done() == 2 and not menu.car_page.is_open,
		"v6.19: RACE 3 opens the car page with the cup's car (the Racer); the Kestrel is refused until it is yours, then race 3 runs with it and the cup keeps it (2 races stay counted)")
	var money1 := UiData.money()
	m.set("phase", "finished")
	app.input.pressed["respawn"] = true
	m.update(1.0 / 60.0)
	var cplace := app.cup.place() if app.cup != null else 0
	var pod: Podium = m.get("podium")
	var fs3: Dictionary = m.get("finish_state")
	var pay: Dictionary = fs3.get("payout", {})
	var cupids := Economy.cup_ids("rookie", "pro", cplace)
	var pids: PackedStringArray = []
	for it: Dictionary in pay.get("items", []):
		pids.append(String(it.id))
	var texts3 := _texts(app.ui.hud.finish)
	var podium_ok := (pod != null and pod.visible and pod.has(1) and pod.has(2) and pod.has(3) and pod.trophy(1) != null and pod.trophy(1).kind == "gold" and
		pod.trophy(3).kind == "bronze" and pod.camera.current)
	t.check(m.get("trophy_on") == true and podium_ok and fs3.has("cup_final") and texts3.has("Rookie Cup") and texts3.has(Field.place_name(cplace)) and texts3.has("menu") and
		pids == cupids and UiData.money() == money1 + int(pay.get("money", 0)) and SaveData.cup_place("rookie", "pro") == cplace and SaveData.get_cup_run().is_empty(),
		"race 3 left at once: the trophy moment: the top three of the standings on the podium with gold, silver and bronze trophies, the panel with the final standings (you %s) and the cup's pay (%s: %s), the place in the cabinet, the cup gone from the save file" % [
		Field.place_name(cplace), ", ".join(pids), UiFormat.money(int(pay.get("money", 0)))])
	app.input.pressed["respawn"] = true
	m.update(1.0 / 60.0)
	var cell: Dictionary = cab.cells[0]
	t.check(app.mode == app.menu_mode and app.cup == null and menu.visible and not cups.visible and String(cell.trophy) == Cups.trophy(cplace) and String((cell.levels as Array)[2]) == Cups.trophy(cplace),
		"Enter: the menu; the cabinet shows the Rookie Cup's %s at Pro (%s)" % [Cups.trophy(cplace) if cplace <= 3 else "place", cab.tooltip_text.get_slice("\n", 2)])
	# the same cup and place again pays nothing new
	var again := Economy.cup_payout("rookie", "pro", cplace, SaveData.cup_paid())
	# Quit cup: asks, then drops the cup without pay
	app.start_cup("asphalt", "amateur")
	var money2 := UiData.money()
	app.cup_result(rows2.map(func(r: Dictionary) -> Dictionary: return {"id": String(r.id) if String(r.id) == Cups.PLAYER else app.cup.drivers[int(r.place) - 2], "place": r.place}))
	app.cup_standings()
	app.input.press("KeyQ")
	menu.handle_keys(app.input)
	var asked: bool = app.message.visible and app.message.asking and msg.text.contains("pays nothing")
	app.message.confirm()
	t.check(again.items.is_empty() and asked and app.cup == null and SaveData.get_cup_run().is_empty() and UiData.money() == money2 and cups.visible and not cups.is_standings,
		"the same place in the same cup again pays nothing new; Q (Quit cup) asks first, then the cup is gone, nothing paid, the picker back")
	cups.close()
	# (a sound's minimum gap is real time: the next section's first Buy confirm isn't held back by Quit cup's)
	(app.audio.get("_last") as Dictionary).clear()
	SaveData.use_file(SAVE)


## v6.8.0: the tracks open one at a time, on a new save file. Only Rookie Oval is open; the other
## tiles are locked (a padlock, "Bronze on 01"); a locked track can be picked, and its panel says
## what opens it; Drive reads LOCKED and Drive / Race the AI are refused with a message, while
## Watch the AI and the training screen (but not its Race best) work there. A bronze on Rookie
## Oval opens Hairpin Valley: the finish panel says so and its tile is NEW until it is picked.
func _app_unlock(t, app: GameApp) -> void:
	t.section("the app: the tracks open one at a time (v6.8.0)")
	var path := "user://test_game_unlock.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	SaveData.use_file(path)
	var menu: MainMenu = app.ui.menu
	var msg: Label = app.message.get("_text")
	var drive_btn: Button = menu.get("_drive_btn")
	var tiles: Array = menu.get("_tiles")
	menu.select_car("racer")
	menu.select_opponent("rookie")
	menu.select(1)
	var locked := tiles.filter(func(x: Control) -> bool: return x.locked).size()
	t.check(not tiles[0].locked and locked == 14 and tiles[1].lock_note == "Bronze on 01" and tiles[2].lock_note == "Bronze on 02" and
		str(tiles[1].tooltip_text).contains("bronze on Rookie Oval opens it") and UiData.open_track_count() == 1,
		"a new career: only Rookie Oval is open; 14 tiles locked (Hairpin Valley: %s)" % tiles[1].lock_note)
	var lock_note: Control = menu.get("_td_lock")
	var lock_text: String = (menu.get("_td_lock_text") as RichTextLabel).get_parsed_text()
	t.check(menu.selected_track == 1 and lock_note.visible and lock_text.contains("Locked: win bronze or better on Rookie Oval") and
		lock_text.contains("Watch AI and Train AI work here anyway") and drive_btn.text == "LOCKED" and drive_btn.tooltip_text.contains("Hairpin Valley is locked"),
		"Hairpin Valley can be picked: its panel says what opens it and that the AI lab works there; Drive reads LOCKED")
	app.play("human", false)
	t.check(app.mode == app.menu_mode and app.message.visible and msg.text.contains("Hairpin Valley opens when you win a bronze medal or better on Rookie Oval") and
		msg.text.contains("Watch the AI and Train the AI work on every track"), "Drive there: refused with a message saying what opens it")
	app.message.close()
	app.play("human", true)
	t.check(app.mode == app.menu_mode and app.message.visible and msg.text.contains("Hairpin Valley opens"), "Race the Rookie AI there: refused too")
	app.message.close()
	inp_enter(app)
	t.check(app.mode == app.menu_mode and app.message.visible, "Enter on the locked tile: the same message")
	app.message.close()
	if AiLink.ready():
		app.play("ai", false)
		t.check(app.mode != app.menu_mode and app.mode.get("driver") == "ai" and app.mode.get("track") == app.tracks[1],
			"Watch the Rookie AI on Hairpin Valley: it works (the AI lab works on every track)")
		app.show_menu()
		app.train()
		var tm := app.train_mode
		t.check(tm != null and app.mode == tm and int(tm.get("_track_index")) == 1, "Train the AI opens there too (on Hairpin Valley; its Race best is checked in test_ai.gd)")
		if tm != null and app.mode == tm:
			tm.emit_signal("exit_requested")
		t.check(app.mode == app.menu_mode, "back on the menu")
	# a bronze on Rookie Oval opens Hairpin Valley
	menu.select(0)
	var track: BuiltTrack = app.tracks[0]
	var medals := Medals.medal_times(track, "racer")
	app.play("human", false)
	var m: Node = app.mode
	t.check(m != app.menu_mode and m.get("track") == track and drive_btn.text == "TIME TRIAL", "Rookie Oval drives")
	# (the medal autopilot's author run: any medal from bronze up opens the next track)
	_feed(app, Autopilot.medal(track, float(medals.run.aLat), float(medals.run.lookK), true, Autopilot.DECEL, Cars.spec("racer")))
	_run_until(m, func() -> bool: return m.get("phase") == "finished", 200.0)
	_feed(app, null)
	var fs: Dictionary = m.get("finish_state")
	var u: Dictionary = fs.get("unlocked", {})
	# (the panel at 1280 x 720: the headless window it is given depends on the tests run before,
	# and 520 px wide or less shows only the first part of the line)
	var panel: Control = app.ui.hud.finish
	var win0: Vector2 = panel.get("_win")
	panel.call("set_window_size", Vector2(1280, 720))
	var texts := _texts(panel)
	panel.call("set_window_size", win0)
	t.check(m.get("phase") == "finished" and String(fs.get("payout", {}).get("medal", "")) != "" and u.get("id") == "hairpin-valley" and u.get("name") == "Hairpin Valley" and
		texts.has("Hairpin Valley unlocked") and texts.has("track 02 is open: pick it on the menu"),
		"the %s medal on Rookie Oval: the finish panel says Hairpin Valley unlocked (track 02 is open)" % String(fs.get("payout", {}).get("medal", "")))
	app.show_menu()
	t.check(not tiles[1].locked and tiles[1].is_new and tiles[2].locked and UiData.open_track_count() == 2 and SaveData.opened_tracks() == PackedStringArray(["hairpin-valley"]),
		"back on the menu: Hairpin Valley's tile is open and NEW; Ramp Rally is still locked")
	menu.select(1)
	t.check(not tiles[1].is_new and drive_btn.text == "TIME TRIAL" and not (menu.get("_td_lock") as Control).visible, "picking it clears NEW; the button reads TIME TRIAL")
	UiData.mark_new_track("hairpin-valley")
	menu.refresh()
	var shown: bool = tiles[1].is_new
	m = app.start_play({"track": track, "driver": "human"})
	app.show_menu()
	t.check(shown and not UiData.is_new_track("hairpin-valley") and not tiles[1].is_new, "NEW shows once: leaving the menu clears it too")
	# a finish without a medal opens nothing; a bronze on an open track whose next one is open: no announcement
	var none := Unlocks.claim("hairpin-valley", "")
	var again := Unlocks.claim("rookie-oval", "author")
	t.check(none == "" and again == "" and not Unlocks.is_open("ramp-rally"), "no medal: nothing opens; a medal again on Rookie Oval: nothing new to announce")
	app._finish_build_task()
	SaveData.use_file(SAVE)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	menu.select(0)
	app._finish_build_task()
	menu.refresh()


## Enter on the menu (the menu reads the game's input).
func inp_enter(app: GameApp) -> void:
	app.input.clear_pressed()
	app.input.press("Enter")
	app.ui.menu.handle_keys(app.input)
	app.input.clear_pressed()


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
		points_l.text == "0 pts" and drive_btn.text == "TIME TRIAL", "a new career: $0, 0 points, only the Racer (the menu's header: %s, %s)" % [money_l.text, points_l.text])

	# the shop (v6.19: the car page, opened by choosing a race): a locked car's START
	menu.ask_car("drive")
	var start_btn: Button = menu.car_page.start_btn
	menu.car_page.pick("kestrel")
	var lock: Label = menu.car_page.car_lock
	t.check(menu.car_page.is_open and start_btn.text == "LOCKED" and lock.visible and lock.text.contains("$10,000") and not ghost_btn.disabled and not (menu.get("_watch_btn") as Button).disabled and
		drive_btn.text == "TIME TRIAL", "the Kestrel picked on the car page: locked at $10,000 (START reads LOCKED; the menu's race buttons stay on)")
	app.play("human", false)
	t.check(app.mode == app.menu_mode and app.message.visible and not app.message.asking and msg.text.contains("costs $10,000") and
		msg.text.contains("$10,000 more to go"), "Drive it with $0: a message says how much is missing; still on the menu")
	app.message.close()
	SaveData.add_money(12500)
	menu.refresh()
	t.check(start_btn.text == "BUY $10,000" and money_l.text == "$12,500" and menu.car_page.money_l.text == "$12,500", "with $12,500 START reads BUY $10,000")
	app.play("human", false)
	t.check(app.message.asking and msg.text.contains("costs $10,000") and msg.text.contains("$2,500 is left") and app.mode == app.menu_mode,
		"BUY asks first (what it costs, what is left)")
	app.message.close()
	t.check(not SaveData.owns_car("kestrel") and UiData.money() == 12500, "Cancel: nothing bought")
	app.play("human", false)
	app.message.confirm()
	t.check(SaveData.owns_car("kestrel") and UiData.money() == 2500 and start_btn.text == "START" and not lock.visible and money_l.text == "$2,500" and
		app.mode == app.menu_mode and not app.message.visible and menu.car_page.is_open, "yes: the Kestrel is yours, $2,500 left (the header says so); the car page reads START")
	start_btn.pressed.emit()
	t.check(app.mode != app.menu_mode and str(app.mode.get("car_def").id) == "kestrel" and not menu.car_page.is_open, "now START drives it (the car page closes)")
	app.show_menu()

	# Race the Rookie AI on Seaside Stunts with the Racer (the author run of the medal sweep; the
	# track is opened first, as a bronze on Lighthouse Bay would: this new career has only track 1)
	var tid := "seaside-stunts"
	var ti := Tracks.ids().find(tid)
	SaveData.open_track(tid)
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
	# (v6.15: no nitro in races against the AI, so the author run's autopilot is slower here than the
	# author time; the medal it earns still counts and pays)
	var got := Medals.medal_for(medals, race.finish_time)
	var want: Array = []
	for k in range(Medals.ORDER.size() - 1, Medals.ORDER.find(got) - 1, -1):
		want.append(Medals.ORDER[k])
	want.append("ai-rookie")
	var w_money := 0
	var w_points := 0
	for id: String in want:
		w_money += int(Economy.reward(tid, id).money)
		w_points += int(Economy.reward(tid, id).points)
	t.check(race.finished and race.finish_time > float(medals.author) and got != "" and ids == want and int(p.money) == w_money and int(p.points) == w_points and
		p.get("won") == true and p.get("level") == "rookie" and str(fs.get("lines", [""])[0]).contains("Rookie AI hasn't finished: you win!") and
		UiData.money() == money0 + w_money and UiData.points() == points0 + w_points and app.ui.hud.panel_open,
		"the author run without nitro (%s, author %s) beats the Rookie AI: paid %s and the Rookie win, %s and %d pts (the finish panel's payout)" % [
		RaceState.format_time(race.finish_time), RaceState.format_time(float(medals.author)), ", ".join(PackedStringArray(want.slice(0, want.size() - 1))), UiFormat.money(w_money), w_points])
	var u: Dictionary = fs.get("unlocked", {})
	t.check(u.get("id") == "forest-rally" and u.get("number") == "13" and SaveData.opened_tracks().has("forest-rally") and UiData.is_new_track("forest-rally") and
		_texts(app.ui.hud.finish).has("Forest Rally unlocked"), "and it opens the next track: the finish panel says Forest Rally unlocked (track 13)")
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


## v6.11.0: the car picker's part chips in the app: a locked car's part says so, money short says
## how much, the chip asks first and buys the next level; the races drive the upgraded car, the AI
## opponents and their stored times stay stock; Watch the AI with the player's own network too.
func _app_upgrades(t, app: GameApp) -> void:
	t.section("the app: car upgrades (v6.11.0)")
	var path := "user://test_game_upgrades.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	SaveData.use_file(path)
	var menu: MainMenu = app.ui.menu
	var msg: Label = app.message.get("_text")
	var money_l: Label = menu.get("_money_l")
	var chips: Array = menu.car_page.part_chips # (v6.19: on the car page; the menu's refresh redraws it)
	menu.select_car("kestrel")
	menu.refresh()
	t.check(chips.size() == 5 and (chips[0] as Button).disabled and bool(chips[4].get("locked")), "the Kestrel not yours: its five part chips are off")
	app.offer_upgrade("kestrel", "engine")
	t.check(app.message.visible and not app.message.asking and msg.text.contains("Buy the Kestrel first"), "a locked car's part: a message says buy the car first")
	app.message.close()
	menu.select_car("racer")
	menu.refresh()
	var e1 := Upgrades.price("racer", "engine", 1)
	t.check(not (chips[0] as Button).disabled and int(chips[0].get("price")) == e1 and not bool(chips[0].get("affordable")) and int(chips[0].get("level")) == 0,
		"the Racer (yours) with $0: its engine chip shows level 0 and the next level's %s, not affordable" % UiFormat.money(e1))
	(chips[0] as Button).pressed.emit()
	t.check(app.message.visible and not app.message.asking and msg.text.contains("%s more to go" % UiFormat.money(e1)) and SaveData.get_upgrades("racer")[0] == 0,
		"pressing it with $0: a message says %s more to go; nothing bought" % UiFormat.money(e1))
	app.message.close()
	SaveData.add_money(e1 + 1000)
	menu.refresh()
	(chips[0] as Button).pressed.emit()
	t.check(app.message.asking and msg.text.contains("Level 1 of 10") and msg.text.contains("+5 % power") and msg.text.contains("Medal times and the AI opponents stay") and
		msg.text.contains("$1,000 is left"), "with the money: it asks first (level 1 of 10, +5 % power, what is left, medals and AI opponents stock)")
	app.message.close()
	t.check(SaveData.get_upgrades("racer")[0] == 0 and UiData.money() == e1 + 1000, "Cancel: nothing bought")
	(chips[0] as Button).pressed.emit()
	app.message.confirm()
	t.check(SaveData.get_upgrades("racer") == PackedInt32Array([1, 0, 0, 0, 0]) and UiData.money() == 1000 and money_l.text == "$1,000" and int(chips[0].get("level")) == 1 and
		int(chips[0].get("price")) == Upgrades.price("racer", "engine", 2) and not app.message.visible,
		"yes: the Racer's engine is at level 1, $1,000 left; the chip shows level 1 and the next price")
	SaveData.set_upgrades("racer", PackedInt32Array([3, 3, 3, 3, 3]))
	menu.refresh()
	t.check(not (chips[1] as Button).disabled and int(chips[1].get("price")) == Upgrades.price("racer", "tyres", 4) and int(chips[1].get("max_level")) == 10,
		"v6.16: at level 3 the chip offers level 4 (%s) of 10" % UiFormat.money(Upgrades.price("racer", "tyres", 4)))
	SaveData.set_upgrades("racer", PackedInt32Array([10, 10, 10, 10, 10]))
	menu.refresh()
	app.offer_upgrade("racer", "tyres")
	t.check((chips[1] as Button).disabled and chips[1].call("price_text") == "MAX" and app.message.visible and not app.message.asking and msg.text.contains("level 10 of 10 already"),
		"every level bought: the chip reads MAX and is off; the app says so")
	app.message.close()
	# Drive: the upgraded car; Race the Rookie AI: the AI's car stock, its time the stored one
	app.selected_track = 0
	menu.select(0)
	var m: Node = app.start_play({"track": app.tracks[0], "driver": "human"})
	var up_spec := Upgrades.spec("racer", PackedInt32Array([10, 10, 10, 10, 10]))
	t.check((m.get("car") as Car).spec == up_spec and m.get("levels") == PackedInt32Array([10, 10, 10, 10, 10]), "Drive: the Racer with everything at level 10")
	app.show_menu()
	var fixture := "res://tests/fixtures/game_net.json"
	if AiLink.ready() and FileAccess.file_exists(fixture):
		var parsed: Dictionary = AiLink.parse_network_file(JSON.parse_string(FileAccess.get_file_as_string(fixture)))
		# an AI opponent: its car stock (its stored times are the stock car's)
		m = app.start_play({"track": app.tracks[0], "driver": "human", "ghost": true, "net": parsed.net, "level": "rookie", "ai_car": "racer"})
		t.check((m.get("car") as Car).spec == up_spec and m.get("with_ghost") == true and (m.get("ghost").car as Car).spec == Cars.spec("racer"),
			"Race the Rookie AI: you drive the upgraded Racer, the AI opponent a stock one")
		app.show_menu()
		# the player's own network: the upgraded car (Watch the AI and Race my AI)
		m = app.start_play({"track": app.tracks[0], "driver": "ai", "net": parsed.net, "ai_car": "racer"})
		var watched: CarSpec = (m.get("car") as Car).spec
		app.show_menu()
		m = app.start_play({"track": app.tracks[0], "driver": "human", "ghost": true, "net": parsed.net, "ai_car": "racer"})
		t.check(watched == up_spec and (m.get("ghost").car as Car).spec == up_spec, "your own network (Watch the AI, Race my AI) drives the upgraded Racer")
		app.show_menu()
	SaveData.set_upgrades("racer", Upgrades.stock())
	m = app.start_play({"track": app.tracks[0], "driver": "human"})
	t.check((m.get("car") as Car).spec == Cars.spec("racer"), "back to stock: Drive drives the stock Racer (the same spec object)")
	app.show_menu()
	SaveData.use_file(SAVE)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	menu.refresh()


## v6.7.0: the terminal in the app: ` opens it on the menu and on Settings (and Settings' Terminal
## row), its commands change the save file and the menu at once, the keys typed into it never
## reach the menu, and ` in a race does nothing.
func _app_terminal(t, app: GameApp) -> void:
	t.section("the app: the terminal (v6.7.0)")
	var path := "user://test_game_terminal.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	SaveData.use_file(path)
	var menu: MainMenu = app.ui.menu
	var term: TerminalScreen = menu.terminal
	var inp: GameInput = app.input
	var money_l: Label = menu.get("_money_l")
	var points_l: Label = menu.get("_points_l")
	var drive_btn: Button = menu.get("_drive_btn")
	menu.select_car("racer")
	menu.refresh()
	t.check(term.commands != null and term.commands.has_method("run") and not term.is_open, "the app hands the terminal its commands (game/terminal.gd)")
	inp.clear_pressed()
	inp.press("Backquote")
	menu.handle_keys(inp)
	t.check(term.is_open and app.mode == app.menu_mode, "` on the menu opens it")
	term.submit("money 25000")
	term.submit("points 200")
	t.check(SaveData.get_money() == 25000 and money_l.text == "$25,000" and points_l.text == "200 pts", "money 25000, points 200: the menu's header shows %s, %s at once" % [money_l.text, points_l.text])
	term.submit("car dune")
	menu.select_car("dune")
	# (Drive reads LOCKED instead when the track picked by the tests before is locked in this new career)
	t.check(SaveData.owns_car("dune") and drive_btn.text == ("DRIVE" if UiData.track_open(menu.selected_track) else "LOCKED"),
		"car dune: the Dune is yours (%s, not BUY)" % drive_btn.text)
	term.submit("buy kestrel")
	t.check(SaveData.owns_car("kestrel") and SaveData.get_money() == 15000 and money_l.text == "$15,000", "buy kestrel: bought with the money, $15,000 left")
	inp.press("Escape")
	menu.handle_keys(inp)
	t.check(not term.is_open and app.mode == app.menu_mode, "Esc closes it (the Esc doesn't reach the menu)")
	inp.press("KeyO")
	menu.handle_keys(inp)
	inp.press("Backquote")
	menu.handle_keys(inp)
	t.check(term.is_open and menu.settings.is_open, "O, then `: the terminal over Settings")
	inp.press("Backquote")
	menu.handle_keys(inp)
	var rows: Array = menu.settings.get("_rows")
	var row_of := func(key: String) -> int:
		for k in rows.size():
			if str((rows[k].def as Dictionary).get("key", "")) == key:
				return k
		return -1
	menu.settings.step_row(row_of.call("terminal"), 1)
	t.check(term.is_open and menu.settings.is_open, "` closes it; Settings' Terminal row opens it again")
	term.submit("reset career")
	t.check(SaveData.get_money() == 15000 and SaveData.owns_car("dune"), "reset career only asks")
	term.submit("reset career confirm")
	t.check(SaveData.get_money() == 0 and SaveData.owned_cars() == PackedStringArray(["racer"]) and money_l.text == "$0" and menu.car_page.start_btn.text == "LOCKED",
		"reset career confirm: $0, only the Racer; the picked Dune is for sale again (the car page's START reads %s)" % menu.car_page.start_btn.text)
	term.submit("unlock all")
	t.check(SaveData.owned_cars().size() == Cars.ids().size() and SaveData.tracks_unlocked() and menu.car_page.start_btn.text == "START" and drive_btn.text == "TIME TRIAL", "unlock all: every car (START), every track")
	# (v6.17) reset everything: it asks first; then a backup next to the save file, a fresh install with the
	# settings kept, and the app drops the network and the cup it held; a second one keeps the first backup
	var clean_bk := func() -> void:
		var dir := DirAccess.open("user://")
		if dir != null:
			for f: String in dir.get_files():
				if f.begins_with("test_game_terminal.backup"):
					dir.remove(f)
	clean_bk.call()
	var net_err := app.load_network_file("res://tests/fixtures/game_net.json") if AiLink.ready() else "no AI"
	term.submit("money 15000")
	SaveData.submit_record("rookie-oval", "racer", 130.0, [])
	SaveData.set_upgrades("racer", PackedInt32Array([10, 4, 0, 2, 0]))
	SaveData.set_cup_place("rookie", "pro", 1)
	UiData.set_setting("grime", false)
	menu.select(4)
	term.submit("reset everything")
	t.check(SaveData.get_money() == 15000 and not SaveData.get_record("rookie-oval", "racer").is_empty() and not FileAccess.file_exists(SaveData.backup_path()),
		"reset everything only asks")
	term.submit("reset everything confirm")
	var bk_text := FileAccess.get_file_as_string(SaveData.backup_path())
	var bk: Variant = JSON.parse_string(bk_text) if bk_text != "" else null
	var log_t: String = term.log_text()
	t.check(SaveData.get_money() == 0 and SaveData.get_points() == 0 and SaveData.owned_cars() == PackedStringArray(["racer"]) and Upgrades.is_stock(SaveData.get_upgrades("racer")) and
		SaveData.get_record("rookie-oval", "racer").is_empty() and SaveData.network_cars().is_empty() and SaveData.cup_trophies().is_empty() and
		not SaveData.tracks_unlocked() and SaveData.opened_tracks().size() <= 1 and UiData.get_setting("grime") == false and UiData.picked_car() == "racer" and
		money_l.text == "$0" and app.network.is_empty() and app.cup == null and app.selected_track == 0 and drive_btn.text == "TIME TRIAL" and menu.car_page.start_btn.text == "START",
		"reset everything confirm: $0, 0 pts, the Racer stock, no records, networks, trophies; Rookie Oval only, picked; a setting kept (no mud on the screen); the app holds no network (%s before)" % ("loaded" if net_err == "" else net_err))
	t.check(bk is Dictionary and int(bk.career.money) == 15000 and (bk.records as Dictionary).has("rookie-oval") and (bk.networks as Dictionary).size() == (1 if net_err == "" else 0) and
		log_t.contains("Backup of the old save: %s" % ProjectSettings.globalize_path(SaveData.backup_path())) and log_t.contains("To undo it"),
		"the backup next to the save file holds the old save ($15,000, the record, the network); the terminal says where and how to undo")
	SaveData.add_money(77)
	term.submit("reset everything confirm")
	var kept := DirAccess.get_files_at("user://")
	var older := Array(kept).filter(func(f: String) -> bool: return f.begins_with("test_game_terminal.backup-"))
	var bk2: Variant = JSON.parse_string(FileAccess.get_file_as_string(SaveData.backup_path()))
	var bk1: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://" + older[0])) if older.size() == 1 else null
	t.check(older.size() == 1 and bk1 is Dictionary and int(bk1.career.money) == 15000 and bk2 is Dictionary and int(bk2.career.money) == 77 and SaveData.get_money() == 0,
		"a second reset keeps the first backup (renamed %s) and backs up the save before it" % (older[0] if older.size() == 1 else "-"))
	clean_bk.call()
	UiData.set_setting("grime", true)
	term.submit("unlock all")
	term.submit("exit")
	inp.press("Enter")
	menu.handle_keys(inp)
	t.check(not term.is_open and app.mode == app.menu_mode, "exit + Enter: closed, still on the menu (the Enter doesn't drive)")
	inp.press("Escape")
	menu.handle_keys(inp)
	t.check(not menu.settings.is_open, "Esc closes Settings")
	# (v6.18.0) Settings' Reset all progress row: no typing; it asks twice, then the terminal's wipe
	clean_bk.call()
	SaveData.add_money(900)
	SaveData.submit_record("rookie-oval", "racer", 131.0, [])
	Unlocks.claim("rookie-oval", "gold")
	menu.refresh()
	inp.press("KeyO")
	menu.handle_keys(inp)
	t.check(row_of.call("reset") >= 0 and row_of.call("reset") == rows.size() - 1, "Settings has a Reset all progress row, the last one (after the Terminal)")
	menu.settings.step_row(row_of.call("reset"), 1)
	t.check(app.message.asking and app.message.text().contains("fresh install") and app.message.text().contains("backup") and SaveData.get_money() == 900,
		"the Reset row asks first (what goes, the backup); nothing changed")
	app.message.handle_keys(inp) # (no key: it stays)
	inp.press("menu_back")
	app.message.handle_keys(inp)
	t.check(not app.message.visible and SaveData.get_money() == 900 and not SaveData.get_record("rookie-oval", "racer").is_empty() and not FileAccess.file_exists(SaveData.backup_path()),
		"Esc on the question: nothing reset, no backup")
	menu.settings.step_row(row_of.call("reset"), 1)
	app.message.confirm()
	t.check(app.message.asking and app.message.text().contains("Last check") and SaveData.get_money() == 900 and not SaveData.get_record("rookie-oval", "racer").is_empty(),
		"the first yes asks again (a stray Enter never wipes): still $900 and the best time")
	app.message.confirm()
	t.check(SaveData.get_money() == 0 and SaveData.get_record("rookie-oval", "racer").is_empty() and SaveData.opened_tracks().size() <= 1 and not SaveData.tracks_unlocked() and
		Terminal.medal_counts().tracks == 0 and money_l.text == "$0" and app.selected_track == 0 and FileAccess.file_exists(SaveData.backup_path()),
		"the second yes resets everything: $0, no best time, no medal, only Rookie Oval open; the menu redrew; a backup was written")
	t.check(app.message.visible and not app.message.asking and app.message.text().contains("Backup of the old save") and app.message.text().contains("To undo it"),
		"a message says it is done, where the backup is and how to undo it")
	inp.press("menu_accept")
	app.message.handle_keys(inp)
	SaveData.use_file(path) # (as a restart: the file is read again)
	t.check(SaveData.get_money() == 0 and SaveData.get_record("rookie-oval", "racer").is_empty() and SaveData.opened_tracks().size() <= 1,
		"read again from the file (a restart): still reset")
	clean_bk.call()
	inp.press("Escape")
	menu.handle_keys(inp)
	t.check(not menu.settings.is_open and not app.message.visible, "Enter closes the message, Esc Settings")
	# in a race ` does nothing (on the menu's track: going back builds no other track on a thread)
	var m: Node = app.start_play({"track": app.tracks[app.selected_track], "driver": "human"})
	for i in 60 * 4:
		inp.held = {"accelerate": true}
		app.mode.update(1.0 / 60.0)
	inp.press("Backquote")
	inp.press("menu_terminal")
	var step0 := int(m.get("race_step"))
	for i in 10:
		app.mode.update(1.0 / 60.0)
	inp.held = {}
	t.check(app.mode == m and m.get("phase") == "race" and int(m.get("race_step")) == step0 + 10 and not term.is_open and not menu.visible,
		"in a race ` does nothing: the race goes on, no terminal")
	app.show_menu()
	app._finish_build_task()
	t.check(not term.is_open and menu.visible, "back on the menu: the terminal is closed")
	SaveData.use_file(SAVE)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	menu.refresh()


## v6.7.0: game/terminal.gd on its own save file: every command with good and bad input, Tab,
## what reaches the file. Nothing typed may raise a script error.
func _terminal(t) -> void:
	t.section("the terminal's commands (v6.7.0, game/terminal.gd)")
	var path := "user://test_terminal.json"
	var fresh := func() -> void:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		SaveData.use_file(path)
	fresh.call()
	var term: Object = Terminal.new()
	var kinds := ["ok", "info", "gain", "loss", "error", "warn", "row"]
	var text_of := func(r: Dictionary) -> String:
		var out := PackedStringArray()
		for l: Array in r.lines:
			out.append(" | ".join(PackedStringArray(l.slice(1).map(func(x: Variant) -> String: return str(x)))))
		return "\n".join(out)
	var kind_of := func(r: Dictionary) -> String: return str(r.lines[0][0]) if not (r.lines as Array).is_empty() else ""
	# the table: every command has its help text, its method and a usage line
	var bad := []
	for c: Dictionary in Terminal.COMMANDS:
		if str(c.get("help", "")) == "" or not term.has_method(str(c.run)) or not c.has("args"):
			bad.append(c.name)
	t.check(bad.is_empty() and term.names() == PackedStringArray(["help", "money", "points", "car", "buy", "upgrade", "unlock", "cup", "status", "reset", "clear", "exit"]),
		"one table: %d commands, each with its help, usage and method %s" % [Terminal.COMMANDS.size(), bad])
	var r: Dictionary = term.run("")
	t.check((r.lines as Array).is_empty() and not r.changed and (term.run("   \t ").lines as Array).is_empty(), "an empty line does nothing")
	r = term.run("help")
	var rows := (r.lines as Array).filter(func(l: Array) -> bool: return l[0] == "row")
	t.check(rows.size() == Terminal.COMMANDS.size() and text_of.call(r).contains("money <n> | set <n>") and text_of.call(r).contains("unlock all | cars | tracks"), "help: a row per command")
	r = term.run("help money")
	t.check(kind_of.call(r) == "ok" and text_of.call(r).contains("money set 12000") and (r.lines as Array).size() >= 3, "help money explains it")
	r = term.run("help bogus")
	t.check(kind_of.call(r) == "error" and text_of.call(r).contains("no command \"bogus\""), "help bogus: an error naming the commands")
	r = term.run("mony 5000")
	t.check(kind_of.call(r) == "error" and text_of.call(r).contains("Did you mean money?") and SaveData.get_money() == 0 and not r.changed, "mony 5000: unknown, did you mean money; nothing changes")
	r = term.run("xyzzy")
	t.check(kind_of.call(r) == "error" and text_of.call(r).contains("Unknown command \"xyzzy\"") and not text_of.call(r).contains("Did you mean"), "xyzzy: unknown, no wild guess")

	# money and points
	r = term.run("money")
	t.check(text_of.call(r).contains("Money: $0") and not r.changed, "money on its own shows it")
	r = term.run("money 5000")
	t.check(kind_of.call(r) == "gain" and text_of.call(r) == "Money +$5,000: now $5,000" and r.changed and SaveData.get_money() == 5000, "money 5000: +$5,000")
	r = term.run("money -200")
	t.check(kind_of.call(r) == "loss" and text_of.call(r).contains("−$200: now $4,800") and SaveData.get_money() == 4800, "money -200: takes $200")
	r = term.run("money -999999")
	t.check(SaveData.get_money() == 0 and text_of.call(r).contains("now $0") and text_of.call(r).contains("never goes below $0"), "money -999999: stops at $0, says so")
	r = term.run("money -5")
	t.check(kind_of.call(r) == "info" and text_of.call(r).contains("unchanged") and not r.changed, "taking money from $0: unchanged")
	r = term.run("money set 1234")
	var r2: Dictionary = term.run("money set 1234")
	t.check(SaveData.get_money() == 1234 and r.changed and not r2.changed and text_of.call(r2).contains("unchanged"), "money set 1234 sets it (again: unchanged)")
	r = term.run("MONEY 5,000")
	var r3: Dictionary = term.run("money +$1_000")
	t.check(SaveData.get_money() == 7234 and r.changed and r3.changed, "MONEY 5,000 and money +$1_000: any case, commas, a sign, a $ and _ are fine")
	var errs := 0
	for l: String in ["money abc", "money 1.5", "money 5 6", "money set", "money set -5", "money --5", "money $", "money 5k", "money 99999999999", "money set x",
			"points lots", "points set -1", "points 1e3", "money ５０００"]:
		r = term.run(l)
		if kind_of.call(r) == "error" and not r.changed and (r.lines as Array).size() == 1:
			errs += 1
	t.check(errs == 14 and SaveData.get_money() == 7234 and SaveData.get_points() == 0, "14 bad amounts (letters, decimals, two numbers, none, below 0, too big, ...): one short error each, nothing changes")
	r = term.run("money 1000000000")
	t.check(SaveData.get_money() == 1000007234 and r.changed, "the most at a time: 1,000,000,000")
	term.run("money set 0")
	r = term.run("points 200")
	t.check(kind_of.call(r) == "gain" and text_of.call(r) == "Points +200 pts: now 200 pts" and SaveData.get_points() == 200, "points 200")
	r = term.run("points set 10")
	t.check(kind_of.call(r) == "loss" and SaveData.get_points() == 10, "points set 10: down to 10 (a loss)")
	r = term.run("points -50")
	t.check(SaveData.get_points() == 0 and text_of.call(r).contains("never go below 0"), "points -50: stops at 0")

	# cars
	r = term.run("car")
	t.check((r.lines as Array).filter(func(l: Array) -> bool: return l[0] == "row").size() == 6 and text_of.call(r).contains("Racer | yours") and
		text_of.call(r).contains("Vortex | $30,000 in the shop") and not r.changed, "car on its own lists the six cars and their prices")
	r = term.run("car Vortex")
	t.check(kind_of.call(r) == "gain" and SaveData.owns_car("vortex") and r.changed and SaveData.get_money() == 0, "car Vortex (any case): yours, free")
	r = term.run("car vortex")
	t.check(kind_of.call(r) == "info" and text_of.call(r).contains("Already yours: Vortex") and not r.changed, "car vortex again: already yours")
	r = term.run("car bus")
	t.check(kind_of.call(r) == "error" and text_of.call(r).contains("no car called \"bus\"") and text_of.call(r).contains("racer, kestrel") and not r.changed, "car bus: an error listing the cars")
	r = term.run("car kestrel THUNDER")
	t.check(SaveData.owns_car("kestrel") and SaveData.owns_car("thunder") and text_of.call(r).contains("Kestrel, Thunder"), "car kestrel THUNDER: two at once")
	r = term.run("car all")
	t.check(SaveData.owned_cars().size() == 6 and text_of.call(r).contains("Now yours: Drifter, Dune") and text_of.call(r).contains("6 of 6"), "car all: every car")
	r = term.run("car all")
	t.check(text_of.call(r).contains("You already own every car") and not r.changed, "car all again: already")

	# buy (the shop's Economy.buy)
	fresh.call()
	r = term.run("buy kestrel")
	t.check(kind_of.call(r) == "error" and text_of.call(r).contains("$10,000 short") and text_of.call(r).contains("Try: money 10000") and not SaveData.owns_car("kestrel"), "buy kestrel with $0: $10,000 short")
	term.run("money 12000")
	r = term.run("buy Kestrel")
	t.check(kind_of.call(r) == "loss" and SaveData.owns_car("kestrel") and SaveData.get_money() == 2000 and r.changed and text_of.call(r).contains("$2,000 left"), "with $12,000: bought, $2,000 left")
	r = term.run("buy kestrel")
	var r4: Dictionary = term.run("buy")
	var r5: Dictionary = term.run("buy bus")
	t.check(kind_of.call(r) == "info" and SaveData.get_money() == 2000 and kind_of.call(r4) == "error" and kind_of.call(r5) == "error", "buy it again: already yours; buy alone or an unknown car: errors")

	# unlock
	r = term.run("unlock")
	var r6: Dictionary = term.run("unlock everything")
	t.check(kind_of.call(r) == "error" and kind_of.call(r6) == "error" and not SaveData.tracks_unlocked(), "unlock alone or unlock everything: try unlock all")
	r = term.run("unlock tracks")
	t.check(SaveData.tracks_unlocked() and SaveData.owned_cars().size() == 2 and r.changed, "unlock tracks: the tracks flag only")
	fresh.call()
	r = term.run("unlock cars")
	t.check(SaveData.owned_cars().size() == 6 and not SaveData.tracks_unlocked(), "unlock cars: the cars only")
	fresh.call()
	r = term.run("unlock all")
	var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	t.check(SaveData.owned_cars().size() == 6 and SaveData.tracks_unlocked() and r.changed and disk is Dictionary and JsMath.same(disk.version, SaveData.VERSION) and
		disk.career.tracks_unlocked == true and (disk.career.cars as Array).size() == 6, "unlock all: every car and the tracks flag, in the save file (the current version)")
	r = term.run("unlock all")
	t.check(not r.changed and text_of.call(r).contains("already"), "unlock all again: nothing new")

	# status (a gold on Rookie Oval with the Racer: it opens Hairpin Valley, for good)
	var ro := Tracks.build("rookie-oval")
	SaveData.submit_record("rookie-oval", "racer", float(Medals.medal_times(ro, "racer").gold) - 0.1, [])
	var opened := Unlocks.claim("rookie-oval", "gold")
	SaveData.submit_record("rookie-oval", "dune", float(Medals.medal_times(ro, "dune").bronze), [])
	term.run("money set 4321")
	r = term.run("status")
	var st: String = text_of.call(r)
	t.check(st.contains("Money | $4,321") and st.contains("Points | 0 pts") and st.contains("(6 of 6)") and st.contains("0 author, 1 gold, 0 silver, 1 bronze") and
		st.contains("1 of 15 tracks") and st.contains("Tracks | all 15 open (unlock tracks)") and opened == "" and SaveData.opened_tracks().has("hairpin-valley"),
		"status: money, points, cars, medal counts (1 gold, 1 bronze on one track), the tracks flag (the gold opened Hairpin Valley for good, unannounced: it was open)")
	# v6.14.0: cup (the trophy cabinet; a place set without racing, nothing paid)
	var money_c := SaveData.get_money()
	var rc1: Dictionary = term.run("cup rookie pro 1")
	var rc2: Dictionary = term.run("Cup Finale elite 4")
	var rc3: Dictionary = term.run("cup")
	var rbad: Array = [term.run("cup nope pro 1"), term.run("cup rookie master 1"), term.run("cup rookie pro 9"), term.run("cup rookie")]
	var bad_ok := rbad.all(func(x: Dictionary) -> bool: return kind_of.call(x) == "error" and not x.changed)
	var cab_ok: bool = text_of.call(rc3).contains("Rookie Cup | Pro gold") and text_of.call(rc3).contains("Grand Finale | Elite 4th") and text_of.call(rc3).contains("Asphalt Cup | -")
	st = text_of.call(term.run("status"))
	t.check(rc1.changed and text_of.call(rc1).contains("a gold trophy") and rc2.changed and SaveData.cup_place("finale", "elite") == 4 and cab_ok and bad_ok and
		st.contains("Cups | 1 of 25 trophies") and SaveData.get_money() == money_c and SaveData.cup_paid().is_empty(),
		"cup rookie pro 1 records a gold, Cup Finale elite 4 a 4th (no trophy), cup lists the cabinet, status counts 1 of 25; bad cups, levels, places error; nothing paid")
	term.run("cup rookie pro 0")
	term.run("cup finale elite 0")
	t.check(SaveData.cup_trophies().is_empty(), "cup <cup> <level> 0 takes a place away")
	var mc: Dictionary = Terminal.medal_counts()
	t.check(int(mc.gold) == 1 and int(mc.bronze) == 1 and int(mc.tracks) == 1, "medal_counts: the best medal of each track and car")

	# reset (asks first)
	r = term.run("reset career")
	t.check(kind_of.call(r) == "warn" and text_of.call(r).contains("Type yes to do it (or reset career confirm)") and text_of.call(r).contains("Tracks opened by medals stay open") and
		SaveData.get_money() == 4321 and not r.changed, "reset career: says what it would do (tracks opened by medals stay open) and how to confirm; nothing changes")
	r = term.run("reset everything")
	t.check(kind_of.call(r) == "warn" and text_of.call(r).contains("Nothing has changed yet") and text_of.call(r).contains("Type yes to do it (or reset everything confirm)") and text_of.call(r).contains("Your settings stay") and
		text_of.call(r).contains("backup") and SaveData.get_money() == 4321 and not r.changed, "reset everything: says what it would do (settings stay, a backup first), that nothing changed yet and how to confirm; nothing changes")
	# (v6.18.0) the next line may answer: no leaves it, another command drops the question, yes runs it
	r = term.run("no")
	var r_no2: Dictionary = term.run("yes")
	t.check(kind_of.call(r) == "info" and text_of.call(r).contains("was not run") and kind_of.call(r_no2) == "error" and SaveData.get_money() == 4321,
		"reset everything, then no: left as it is; a yes with nothing asked is an unknown command")
	term.run("reset career")
	term.run("money 1")
	r = term.run("yes")
	t.check(kind_of.call(r) == "error" and SaveData.get_money() == 4322, "a command in between drops the question: yes after it does nothing")
	term.run("money set 4321")
	term.run("reset career")
	r = term.run("y")
	t.check(r.changed and SaveData.get_money() == 0 and not SaveData.get_record("rookie-oval", "racer").is_empty(), "reset career, then y: the career starts over (the records stay)")
	term.run("money set 4321")
	r = term.run("reset")
	var r7: Dictionary = term.run("reset records confirm")
	var r8: Dictionary = term.run("money 5 confirm")
	t.check(kind_of.call(r) == "error" and kind_of.call(r7) == "error" and kind_of.call(r8) == "error" and SaveData.get_money() == 4321,
		"reset alone, reset records confirm, money 5 confirm: errors (confirm only follows a command that wipes)")
	r = term.run("Reset Career CONFIRM")
	t.check(r.changed and SaveData.get_money() == 0 and SaveData.owned_cars() == PackedStringArray(["racer"]) and not SaveData.tracks_unlocked() and
		not SaveData.get_record("rookie-oval", "racer").is_empty(), "reset career confirm: $0, only the Racer, the flag off; the records stay")
	st = text_of.call(term.run("status"))
	t.check(Unlocks.is_open("hairpin-valley") and not Unlocks.is_open("ramp-rally") and st.contains("Tracks | 2 of 15 open; next: Ramp Rally (bronze on Hairpin Valley)"),
		"after the reset the track the gold opened stays open, those the flag opened lock again: %s" % st.get_slice("Tracks | ", 1))
	# clear, exit
	r = term.run("clear")
	r2 = term.run("exit")
	t.check(r.clear and not r.close and r2.close and not r2.clear and (r.lines as Array).is_empty(), "clear asks the screen to clear, exit to close")

	# Tab
	var tab_ok := true
	var cases := [["", "", 12], ["mo", "money ", 1], ["M", "money ", 1], ["c", "c", 3], ["car v", "car vortex ", 1], ["car ", "car ", 7], ["car D", "car D", 2],
		["help m", "help money ", 1], ["unlock a", "unlock all ", 1], ["reset c", "reset career ", 1], ["zz", "zz", 0], ["money s", "money set ", 1],
		["car all x", "car all x", 0], ["status x", "status x", 0], ["p", "points ", 1]]
	var tab_bad := []
	for c: Array in cases:
		var res: Dictionary = term.complete(c[0])
		if res.line != c[1] or (res.options as PackedStringArray).size() != int(c[2]):
			tab_bad.append([c[0], res.line, res.options])
	t.check(tab_bad.is_empty(), "Tab: the command name, then its first argument (cars, set, all ...); several matches go as far as they agree %s" % [tab_bad])

	# nothing typed raises a script error (a script error would stop this file)
	var weird := 0
	for l: String in ["\u0001", "[b]money[/b]", "money 5000 5000 5000", "car " + "x".repeat(300), "help help help", "--", "$$$", "money -", "points +",
			"reset career confirm confirm", "unlock all all", "buy all", "status now", "exit please", "clear 5", "😀", "money 0", "points -0"]:
		r = term.run(l)
		var ok_kinds := true
		for line: Array in r.lines:
			ok_kinds = ok_kinds and kinds.has(str(line[0]))
		if r.lines is Array and ok_kinds:
			weird += 1
	t.check(weird == 18, "%d of 18 odd lines answered with known kinds of lines (no script error)" % weird)
	SaveData.use_file(SaveData.DEFAULT_PATH)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## v6.11.0: the terminal's upgrade command and buy <car> <part>; status shows the upgrades.
func _terminal_upgrades(t) -> void:
	t.section("the terminal: upgrades (v6.11.0)")
	var path := "user://test_terminal_up.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	SaveData.use_file(path)
	var term: Object = Terminal.new()
	var text_of := func(r: Dictionary) -> String:
		var out := PackedStringArray()
		for l: Array in r.lines:
			out.append(" | ".join(PackedStringArray(l.slice(1).map(func(x: Variant) -> String: return str(x)))))
		return "\n".join(out)
	var kind_of := func(r: Dictionary) -> String: return str(r.lines[0][0]) if not (r.lines as Array).is_empty() else ""
	var stock := Upgrades.stock()
	var r: Dictionary = term.run("upgrade")
	var rows := (r.lines as Array).filter(func(l: Array) -> bool: return l[0] == "row")
	t.check(rows.size() == 6 and text_of.call(r).contains("Racer | engine 0, tyres 0, nitro 0, loose 0") and text_of.call(r).contains("Vortex | not yours") and not r.changed,
		"upgrade alone: every car's levels (cars not yours say so)")
	r = term.run("upgrade racer")
	t.check(text_of.call(r).contains("Engine | level 0 of 10, next %s" % UiFormat.money(Upgrades.price("racer", "engine", 1))) and
		text_of.call(r).contains("Loose grip | level 0 of 10") and not r.changed, "upgrade racer: its four parts, levels and next prices")
	r = term.run("upgrade racer engine 3")
	t.check(kind_of.call(r) == "gain" and r.changed and SaveData.get_upgrades("racer") == PackedInt32Array([3, 0, 0, 0, 0]) and SaveData.get_money() == 0 and
		text_of.call(r).contains("engine level 3 (+15 % power)"), "upgrade racer engine 3: free, at once (%s)" % text_of.call(r))
	r = term.run("upgrade Racer TIRES 2")
	var r2: Dictionary = term.run("upgrade racer tyres 2")
	t.check(SaveData.get_upgrades("racer") == PackedInt32Array([3, 2, 0, 0, 0]) and r.changed and kind_of.call(r2) == "info" and not r2.changed,
		"upgrade Racer TIRES 2: any case, the part's other names; again: already")
	r = term.run("upgrade racer tyres 9")
	t.check(SaveData.get_upgrades("racer") == PackedInt32Array([3, 9, 0, 0, 0]) and r.changed and text_of.call(r).contains("tyres level 9 (+25 % asphalt grip)"),
		"upgrade racer tyres 9 (v6.16: levels up to 10): %s" % text_of.call(r))
	r = term.run("upgrade racer max")
	t.check(SaveData.get_upgrades("racer") == PackedInt32Array([10, 10, 10, 10, 10]) and r.changed and text_of.call(r).contains("every part at level 10"), "upgrade racer max: every part at 10")
	r = term.run("upgrade racer stock")
	t.check(SaveData.get_upgrades("racer") == stock and r.changed, "upgrade racer stock: back to 0")
	r = term.run("upgrade vortex max")
	t.check(kind_of.call(r) == "error" and text_of.call(r).contains("you don't own the Vortex") and not r.changed and SaveData.get_upgrades("vortex") == stock,
		"upgrade vortex max without the Vortex: an error (car vortex first)")
	term.run("car dune")
	r = term.run("upgrade all max")
	t.check(r.changed and SaveData.get_upgrades("racer") == PackedInt32Array([10, 10, 10, 10, 10]) and SaveData.get_upgrades("dune") == PackedInt32Array([10, 10, 10, 10, 10]) and
		SaveData.get_upgrades("vortex") == stock and text_of.call(r).contains("Every car you own (2)"), "upgrade all max: every car you own (the Racer and the Dune)")
	var st: String = text_of.call(term.run("status"))
	var spent := Upgrades.car_total("racer") + Upgrades.car_total("dune")
	t.check(st.contains("Upgrades | Racer E10 T10 N10 L10 W10, Dune E10 T10 N10 L10 W10 (%s of the %s" % [UiFormat.money(spent), UiFormat.money(Upgrades.total_all())]),
		"status: the upgraded cars and what their parts cost (%s)" % st.get_slice("Upgrades | ", 1).get_slice("\n", 0))
	r = term.run("upgrade all stock")
	st = text_of.call(term.run("status"))
	t.check(SaveData.get_upgrades("dune") == stock and st.contains("Upgrades | none: every car stock"), "upgrade all stock: every car stock; status says none")
	var errs := 0
	for l: String in ["upgrade bus max", "upgrade racer turbo 2", "upgrade racer engine 11", "upgrade racer engine -1", "upgrade racer engine x", "upgrade racer engine",
			"upgrade racer engine 1.5", "upgrade all", "upgrade all engine 3", "upgrade racer max now", "upgrade racer engine +2"]:
		r = term.run(l)
		if kind_of.call(r) == "error" and not r.changed:
			errs += 1
	t.check(errs == 11 and SaveData.get_upgrades("racer") == stock, "11 bad upgrade lines (unknown car or part, level 11, -1, letters, missing, decimals, all with one part ...): an error each, nothing changes")
	# buy <car> <part>: the car picker's chip, with money
	var e1 := Upgrades.price("racer", "engine", 1)
	r = term.run("buy racer engine")
	t.check(kind_of.call(r) == "error" and text_of.call(r).contains("%s short" % UiFormat.money(e1)) and text_of.call(r).contains("Try: money %d" % e1) and SaveData.get_upgrades("racer") == stock,
		"buy racer engine with $0: %s short" % UiFormat.money(e1))
	term.run("money %d" % (e1 + 100))
	r = term.run("buy Racer Engine")
	t.check(kind_of.call(r) == "loss" and r.changed and SaveData.get_upgrades("racer")[0] == 1 and SaveData.get_money() == 100 and text_of.call(r).contains("level 1 (+5 % power)") and
		text_of.call(r).contains("$100 left"), "with the money: buy Racer Engine buys level 1, $100 left")
	term.run("upgrade racer engine 10")
	r = term.run("buy racer engine")
	var r3: Dictionary = term.run("buy vortex tyres")
	var r4: Dictionary = term.run("buy racer turbo")
	var r5: Dictionary = term.run("buy racer engine now")
	t.check(kind_of.call(r) == "info" and text_of.call(r).contains("level 10 already") and kind_of.call(r3) == "error" and text_of.call(r3).contains("don't own the Vortex") and
		kind_of.call(r4) == "error" and text_of.call(r4).contains("no part called") and kind_of.call(r5) == "error" and SaveData.get_money() == 100,
		"buy at the top level: already; a car not yours, an unknown part, too many words: errors")
	# Tab: the command, then the car
	var tab_bad := []
	for c: Array in [["up", "upgrade ", 1], ["u", "u", 2], ["upgrade v", "upgrade vortex ", 1], ["upgrade a", "upgrade all ", 1], ["upgrade d", "upgrade d", 2]]:
		var res: Dictionary = term.complete(c[0])
		if res.line != c[1] or (res.options as PackedStringArray).size() != int(c[2]):
			tab_bad.append([c[0], res.line, res.options])
	t.check(tab_bad.is_empty(), "Tab: up -> upgrade, then the car or all %s" % [tab_bad])
	term.run("reset career confirm")
	t.check(SaveData.get_upgrades("racer") == stock and SaveData.get_upgrades("dune") == stock, "reset career confirm: every car stock again")
	SaveData.use_file(SaveData.DEFAULT_PATH)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))



# ---------------------------------------------------------------- sound (v6.12.0)

func _audio(t) -> void:
	t.section("sound: buses, volumes, the background mute, effects and music (audio/game_audio.gd)")
	var path := "user://test_game_audio.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	SaveData.use_file(path)
	UiData.use_save_data(true)
	GameAudio.setup_buses()
	GameAudio.setup_buses()
	var names := []
	var sends := []
	for i in AudioServer.bus_count:
		names.append(AudioServer.get_bus_name(i))
		sends.append(str(AudioServer.get_bus_send(i)) if i > 0 else "")
	var m := AudioServer.get_bus_index("Master")
	var limiters := 0
	for k in AudioServer.get_bus_effect_count(m):
		if AudioServer.get_bus_effect(m, k) is AudioEffectHardLimiter:
			limiters += 1
	var lim := AudioServer.get_bus_effect(m, 0) as AudioEffectHardLimiter
	t.check(names == ["Master", "Music", "SFX", "Engine"] and sends == ["", "Master", "Master", "Master"] and limiters == 1 and lim != null
		and is_equal_approx(lim.ceiling_db, GameAudio.LIMIT_DB), "buses Music, SFX and Engine into Master, one hard limiter on Master at %.1f dB (made twice: still one)" % GameAudio.LIMIT_DB)
	t.check(GameAudio.volume_db(1.0) == 0.0 and absf(GameAudio.volume_db(0.5) - -12.04) < 0.01 and GameAudio.volume_db(0.0) == GameAudio.SILENT,
		"a volume v is v² in amplitude: 100% 0 dB, 50% -12 dB, 0 silent")
	var ga := GameAudio.new()
	t.tree.root.add_child(ga)
	t.check(ga.get_child_count() == GameAudio.POOL_2D + GameAudio.POOL_3D + 2, "pooled players made once: %d plain, %d positional, 2 for the music" % [GameAudio.POOL_2D, GameAudio.POOL_3D])
	var vol := func(b: String) -> float: return AudioServer.get_bus_volume_db(AudioServer.get_bus_index(b))
	t.check(is_equal_approx(vol.call("Master"), GameAudio.volume_db(1.0)) and is_equal_approx(vol.call("Music"), GameAudio.volume_db(0.7))
		and is_equal_approx(vol.call("SFX"), GameAudio.volume_db(0.8)) and is_equal_approx(vol.call("Engine"), GameAudio.volume_db(0.8)),
		"the default volumes on the buses (master 100%, music 70%, effects and engines 80%)")
	UiData.set_setting("vol_sfx", 0.5)
	UiData.set_setting("vol_music", 0.0)
	UiData.set_setting("vol_engine", 0.3)
	ga.apply_settings()
	t.check(absf(vol.call("SFX") - -12.04) < 0.01 and AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")) and absf(vol.call("Engine") - GameAudio.volume_db(0.3)) < 0.001,
		"changed volumes reach the buses (effects 50%: -12 dB; music 0: muted)")
	SaveData.use_file(path) # read back from the file
	t.check(is_equal_approx(float(UiData.get_setting("vol_sfx")), 0.5) and float(UiData.get_setting("vol_music")) == 0.0 and is_equal_approx(float(UiData.get_setting("vol_engine")), 0.3),
		"the volumes are saved in the save file and read back")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	(raw.settings as Dictionary).erase("vol_sfx")
	(raw.settings as Dictionary).erase("mute_unfocused")
	raw.settings["vol_master"] = "loud"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(raw))
	f.close()
	SaveData.use_file(path)
	t.check(is_equal_approx(float(UiData.get_setting("vol_sfx")), 0.8) and UiData.get_setting("mute_unfocused") == true and is_equal_approx(float(UiData.get_setting("vol_master")), 1.0),
		"an older file without them (or a bad value) reads the defaults")
	UiData.set_setting("vol_music", 0.7)
	UiData.set_setting("vol_sfx", 0.8)
	UiData.set_setting("vol_engine", 0.8)
	ga.apply_settings()
	# the window in the background
	ga.set_focused(false)
	var muted := AudioServer.is_bus_mute(m) and ga.muted_in_background()
	ga.set_focused(true)
	t.check(muted and not AudioServer.is_bus_mute(m), "the window in the background mutes Master; in front again it plays")
	ga.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var by_note := AudioServer.is_bus_mute(m) and not ga.focused
	ga.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	t.check(by_note and not AudioServer.is_bus_mute(m), "the same from the window's focus notifications")
	UiData.set_setting("mute_unfocused", false)
	ga.apply_settings()
	ga.set_focused(false)
	t.check(not AudioServer.is_bus_mute(m) and not ga.muted_in_background(), "Mute in the background off: it keeps playing")
	ga.set_focused(true)
	UiData.set_setting("mute_unfocused", true)
	UiData.set_setting("vol_master", 0.0)
	ga.apply_settings()
	t.check(AudioServer.is_bus_mute(m), "master volume 0: Master muted")
	UiData.set_setting("vol_master", 1.0)
	ga.apply_settings()
	# every sound and the music exist and load (loops loop)
	var bad := []
	for nm: String in SoundBank.SFX:
		var d := SoundBank.sfx(nm)
		for file: String in d.files:
			var st := ga.stream(file)
			if st == null:
				bad.append(file)
			elif bool(d.loop) and not (st is AudioStreamWAV and (st as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD):
				bad.append(file + " (no loop)")
	for nm: String in SoundBank.MUSIC:
		var ms: Variant = load(SoundBank.music_path(nm))
		if not (ms is AudioStreamOggVorbis) or not (ms as AudioStreamOggVorbis).loop or (ms as AudioStreamOggVorbis).get_length() < 20.0:
			bad.append(nm)
	var themes := []
	for th: String in SoundBank.RACE_MUSIC:
		if not SoundBank.MUSIC.has(SoundBank.race_music(th)):
			themes.append(th)
	for tid: String in Tracks.ids():
		var th: String = str(Tracks.build(tid).theme)
		if not SoundBank.RACE_MUSIC.has(th):
			themes.append(tid + ": " + th)
	t.check(bad.is_empty() and themes.is_empty(), "every sound file loads (%d sounds, the loops loop), the %d music tracks loop, every track's theme has its race music %s %s" % [
		SoundBank.SFX.size(), SoundBank.MUSIC.size(), bad, themes])
	# effects: pooled, on their bus, logged; unknown names do nothing
	var h0 := ga.total
	var p := ga.play("checkpoint")
	t.check(p != null and p.playing and p.bus == "SFX" and ga.sounds_since(h0) == PackedStringArray(["checkpoint"]), "play(): a pooled player on the SFX bus, logged")
	t.check(ga.play("no_such_sound") == null and ga.total == h0 + 1, "an unknown sound: nothing (no error)")
	for i in 6:
		ga.play("key")
	var keys := 0
	for c: Node in ga.get_children():
		if c is AudioStreamPlayer and (c as AudioStreamPlayer).playing and (c as AudioStreamPlayer).bus == "SFX" and ga.get("_owner").get(c, "") == "key":
			keys += 1
	t.check(keys == int(SoundBank.sfx("key").voices), "six quick key clicks: at most %d at once (the oldest stops)" % int(SoundBank.sfx("key").voices))
	t.check(ga.play("hit_heavy") != null and ga.play("hit_heavy") == null, "the same hit twice in one moment: once (its gap)")
	var p3 := ga.play_at("land", Vector3(10, 0, 0))
	t.check(p3 is AudioStreamPlayer3D and p3.playing, "play_at(): a positional player")
	ga.play_after("medal", 0.9)
	ga.step_queue(0.5)
	var early := ga.played("medal")
	ga.step_queue(0.5)
	t.check(early == 0 and ga.played("medal") == 1 and ga.queued().is_empty(), "play_after(): the medal stinger plays 0.9 s later")
	ga.play_after("best", 0.5)
	ga.stop_effects()
	ga.step_queue(1.0)
	t.check(ga.played("best") == 0, "stop_effects() drops the queued ones too")
	# music: a cross-fade, its level for the context, ducking
	ga.music("menu")
	ga._step_music(2.0)
	var full := ga.music_volume_db()
	ga.music_level(-3.0)
	ga.duck(-8.0)
	for i in 120:
		ga._step_music(1.0 / 60.0)
	var ducked := ga.music_volume_db()
	ga.music("overdrive")
	ga._step_music(0.6)
	var mp: Array = ga.get("_music")
	var both := (mp[0] as AudioStreamPlayer).playing and (mp[1] as AudioStreamPlayer).playing
	ga._step_music(2.0)
	t.check(absf(full) < 0.01 and absf(ducked - -11.0) < 0.3 and both and not ((mp[0] as AudioStreamPlayer).playing and (mp[1] as AudioStreamPlayer).playing)
		and ga.music_name == "overdrive", "music: full level, -3 dB in a race and -8 dB more under the finish panel (%.1f dB), a cross-fade to the next" % ducked)
	ga.music("")
	ga._step_music(2.0)
	t.check(not (mp[0] as AudioStreamPlayer).playing and not (mp[1] as AudioStreamPlayer).playing, "music(\"\") fades out")
	t.check(AudioServer.get_mix_rate() > 0.0, "headless: the dummy audio driver runs (mix rate %d Hz)" % int(AudioServer.get_mix_rate()))
	ga.free()
	UiData.reset()
	SaveData.use_file(SAVE)


## The sounds of the game in the app: the menu's clicks and music, the shop, a race's cues.
func _app_audio(t, app: GameApp) -> void:
	t.section("the app: sound (v6.12.0)")
	var path := "user://test_game_app_audio.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	SaveData.use_file(path)
	var a := app.audio
	var menu: MainMenu = app.ui.menu
	t.check(a != null and a.music_name == SoundBank.MENU_MUSIC and UiSound.player.is_valid(), "the app's audio: the menu music plays, the interface's sounds go to it")
	var h := a.total
	var since := func(from: int) -> PackedStringArray: return a.sounds_since(from)
	# the shop: a refusal, a purchase
	menu.select_car("vortex")
	app.play("human", false)
	t.check(app.message.visible and since.call(h).has("ui_error"), "Drive a locked car without the money: the refusal's sound (ui_error)")
	app.message.close()
	SaveData.add_money(100000)
	h = a.total
	var r := app.buy_car("kestrel")
	t.check(r.ok and since.call(h) == PackedStringArray(["cash"]), "buying a car: the cash sound")
	h = a.total
	r = app.buy_upgrade("racer", "engine")
	t.check(r.ok and since.call(h) == PackedStringArray(["cash"]), "buying an upgrade: the cash sound")
	h = a.total
	app.offer_car("dune")
	t.check(app.message.asking and since.call(h).has("ui_confirm"), "BUY asks first, with the confirm sound")
	app.message.close()
	# a volume changed on the Settings screen reaches its bus
	menu.settings.set_value("vol_engine", 0.4)
	t.check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Engine")), GameAudio.volume_db(0.4)), "Settings' Engines slider: the Engine bus follows")
	menu.settings.set_value("vol_engine", 0.8)
	# a race: the theme's music, the countdown, the checkpoints, the finish and its stinger
	menu.select_car("racer")
	h = a.total
	var m: Node = app.start_play({"track": app.tracks[0], "driver": "human"})
	var ca: CarAudio = m.get("car_audio")
	t.check(a.music_name == SoundBank.race_music(app.tracks[0].theme) and ca != null and ca.car_id == "racer" and m.get("ghost_audio") == null,
		"Drive: the race music (%s), the car's sound; no AI car" % a.music_name)
	app.input.held = {"accelerate": true}
	for i in 60:
		m.update(1.0 / 60.0)
	var rev := ca.engine.rpm
	app.input.held = {}
	_run_until(m, func() -> bool: return m.get("phase") == "race", 5.0)
	var cd: PackedStringArray = since.call(h)
	t.check(cd.count("count") == 3 and cd.count("go") == 1 and cd[cd.size() - 1] == "go", "the countdown: three beeps and GO %s" % [cd])
	t.check(rev > (m.get("car") as Car).spec.idle_rpm + 1500.0 and ca.updates > 60, "the throttle on the grid revs the engine (%d rpm)" % rev)
	var run: Dictionary = Medals.medal_times(app.tracks[0], "racer").get("run", {"aLat": 24.0, "lookK": 1.0})
	_feed(app, Autopilot.medal(app.tracks[0], float(run.aLat), float(run.lookK), true, Autopilot.DECEL, Cars.spec("racer")))
	var race: RaceState = m.get("race")
	var gates := [0]
	var same_step := [true]
	h = a.total
	var watch := func() -> bool:
		if race.splits.size() > gates[0]:
			gates[0] = race.splits.size()
			var last: String = str(a.history.back()[0]) if a.history.size() > 0 else ""
			same_step[0] = same_step[0] and (last in ["checkpoint", "lap", "finish", "medal", "best"])
		return m.get("phase") == "finished"
	_run_until(m, watch, 200.0)
	_feed(app, null)
	var got: PackedStringArray = since.call(h)
	t.check(m.get("phase") == "finished" and got.count("checkpoint") + got.count("lap") == race.splits.size() - 1 and got.has("finish") and same_step[0],
		"the race: a chime at every checkpoint (%d) and lap (%d), the finish's sound, each in the step it is taken" % [got.count("checkpoint"), got.count("lap")])
	var q: Array = a.queued()
	t.check(is_equal_approx(a.duck_db, PlayMode.FINISH_DUCK_DB) and q.size() >= 1 and str(q[0][1]) == "medal" and is_equal_approx(float(q[0][0]), PlayMode.STINGER_AT),
		"the finish: the music down %d dB, the new medal's stinger %.1f s after" % [int(PlayMode.FINISH_DUCK_DB), PlayMode.STINGER_AT])
	a.step_queue(1.0)
	t.check(a.played("medal") >= 1, "and it plays")
	# R: the countdown again, the stingers dropped, the music back up
	app.input.pressed["restart"] = true
	m.update(1.0 / 60.0)
	t.check(m.get("phase") == "countdown" and a.queued().is_empty() and a.duck_db == 0.0, "R: the queued stingers dropped, the music back up")
	# a wall: flat out into the first corner
	_run_until(m, func() -> bool: return m.get("phase") == "race", 5.0)
	app.input.held = {"accelerate": true}
	h = a.total
	var car: Car = m.get("car")
	_run_until(m, func() -> bool: return car.wall_hits > 0, 60.0)
	m.update(1.0 / 60.0)
	app.input.held = {}
	var hits: PackedStringArray = since.call(h)
	t.check(car.wall_hits > 0 and (hits.has("hit_heavy") or hits.has("hit_medium") or hits.has("hit_light")), "flat out into the wall: a hit sound %s" % [hits])
	# quitting mid-race (the window's close request): the music and every car's sound stop
	var ep: AudioStreamPlayer = ca.get("_engine_player")
	var was := ep.playing
	a.shutdown()
	m.update(1.0 / 60.0) # (the race goes on until the game has quit: the car's sound must not start again)
	var music_on := false
	for p: AudioStreamPlayer in a.get("_music"):
		music_on = music_on or p.playing
	var loops_on := false
	for p: Node in (ca.get("_loops") as Dictionary).values():
		loops_on = loops_on or bool(p.get("playing"))
	t.check(was and not ep.playing and not loops_on and not music_on and a.music_name == "",
		"quitting mid-race: the music and the car's engine and loops stop and stay stopped (GameAudio.shutdown)")
	# Esc: the menu, its music, the car silent
	app.input.pressed["menu"] = true
	m.update(1.0 / 60.0)
	t.check(app.mode == app.menu_mode and a.music_name == SoundBank.MENU_MUSIC and not ep.playing, "Esc: the menu music, the car's engine stops")
	# the menu's clicks
	UiSound.clear()
	app.input.press("KeyC")
	menu.handle_keys(app.input)
	t.check(UiSound.count("ui_move") >= 1, "a car change on the menu clicks")
	SaveData.use_file(SAVE)
