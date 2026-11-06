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
##   races     tracks=a,b,.. (default rookie-oval, seaside-stunts, v6.4's summit-rush and three
##             tracks v6.6 reworked: hairpin-valley, mountain-pass, canyon-run) cars=a,b,.. (default
##             every car): pick the track and car with the menu keys, Drive (Enter), drive the
##             medal autopilot of the author time to the finish;
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
##   settings1 / settings2   change settings with the keyboard on the Settings screen (v6.12: also
##             the Music volume and the background mute, with a shot of the Audio section); the second
##             run (a new process on the same save file) checks they persisted and were applied.
##   shots     out=<dir>: menu, driving with nitro, finish panel, the menu after it and (train=0
##             skips it) the AI training screen after train_seconds=40 of Max training with
##             train_car=<id> (default racer) on train_track=<id> (default lighthouse-bay) (PNGs);
##             net=<file> loads that network first (the menu's AI block, training continues it).
##   perf      script time per frame of a race (Drive with the autopilot, real time); v6.12: and the
##             car's sound's share of it (the engine synthesis, events and loops).
##   surfaces  dirt and snow (v6.3): the menu's track panel names a track's surfaces (Ramp Rally
##             "Asphalt + dirt", Mountain Pass "Asphalt + dirt + packed snow"); Drive with the Dune
##             on Ramp Rally (the medal autopilot): no dust on asphalt; on the dirt the tyres throw
##             up dust (a pooled effect), the tyre marks take the dirt's colour and (v6.10) mud
##             splashes the screen (world/screen_grime.gd: never in the middle, the camera does not
##             rumble), gone again soon after the dirt ends; Hairpin Valley with the Racer: snow
##             spray, grey-blue marks and snow and frost on the screen.
##             Shots: surfaces_menu, surfaces_transition, surfaces_dirt, surfaces_snow, surfaces_after.
##   economy   money, points and the car shop (v6.5.0) from a new career: $0 and only the Racer;
##             race the Elite AI on Rookie Oval (the medal autopilot of the author time, starting a
##             second late: the AI car leads, then loses; v6.8.0: the gold opens Hairpin Valley) and,
##             with tracks 3-12 opened by the scenario (as bronzes on each would), the Expert AI on
##             Seaside Stunts (the author run: it opens Forest Rally): the finish panel's payout, the
##             money and points on the menu (Forest Rally NEW, the last two tracks locked); the
##             Vortex is short of money (a message), the Kestrel is bought (BUY asks first) and
##             driven. Shots: economy_race, economy_finish, economy_menu, economy_shop, economy_buy.
##   unlock    the tracks open one at a time (v6.8.0) from a new career: only Rookie Oval is open,
##             14 tiles locked; 2 still picks Hairpin Valley (its panel says what opens it, Drive
##             reads LOCKED, the menu fits 1280 x 720); Enter (Drive) and Race the Rookie AI are
##             refused with a message; Watch the Rookie AI and Train the AI work there; a bronze on
##             Rookie Oval (a slow autopilot, 50 m/s at most: 2:32.900 against bronze 2:39 and
##             silver 2:27, v6.9.0's faster bronze) opens Hairpin Valley: the finish panel
##             says so, its tile is NEW until picked, then it drives; the save file holds it.
##             Shots: unlock_menu, unlock_locked, unlock_message, unlock_finish, unlock_menu_after.
##   terminal  the terminal (v6.7.0) from a new career: ` on the menu opens it with the input
##             focused; typed commands (key events with their characters) run: help, money 25000
##             (the menu's header shows it at once, the save file holds it), points 200, status; a
##             mistyped command and a bad number give an error and change nothing; Up / Down bring
##             back earlier lines, Tab completes; letters typed there never reach the menu (O, H, C,
##             Enter); ` closes it. Then the money buys the Kestrel on the car picker (BUY asks
##             first); Settings shows the Terminal row, its Open button (clicked) opens the terminal
##             over Settings, where buy dune is short of money, money 3000 then buy dune buys it,
##             Esc closes it back to Settings; ` opens it over Settings and closes it again; the pad
##             opens it from the Terminal row (A) and closes it (B); exit + Enter closes it without
##             driving; in a race (Drive with the Dune) ` does nothing. Shots: terminal_menu,
##             terminal_settings, terminal_over_settings.
##   upgrades  car upgrades (v6.11.0) from a new career: the Racer's four part chips on the car
##             picker (level 0, the next price, greyed while the money is short, a locked car's off);
##             the stock Racer drives Rookie Oval with the medal autopilot of the author run (the
##             author time); then money (the terminal's money) buys every level of every part by
##             clicking the chips (each asks first: Buy for $...), the bars show what they add in
##             green; Drive again with the same autopilot (the author run's settings): faster than
##             the author time (the medal times stay stock), the record and ghost keep the levels, R: the ghost replays the
##             upgraded run within 3 cm; the menu fits 1280 x 720. Shots: upgrades_menu,
##             upgrades_ask, upgrades_max, upgrades_race, upgrades_finish.
##   audio     sound and music (v6.12.0), best run under Movie Maker (--write-movie out.avi: the
##             audio is mixed in lockstep with the 60 fps frames, so every number is exact; without
##             it the dummy driver mixes in real time and the checks hold within a few frames).
##             AudioEffectCaptures tap Master (before and after its limiter), Music, SFX and Engine,
##             every frame is logged (audio_frames.csv: rpm, gear, ground, the bus levels, the car's
##             loop levels; audio_events.csv: each sound and its frame) and clips are recorded
##             (menu_music.wav, race1_*.wav, race2_*.wav; race*_engine.wav: the Engine bus, float).
##             The menu: its music plays at a sane level without clipping, a car change clicks;
##             Settings: two columns at 1280 x 720 with every row on screen (no scrolling), the
##             Master and Music sliders with the arrow keys (the bus volumes follow, Music Off is
##             silent), the window in the background mutes the output (its peak meter) and in front
##             plays again (shot: audio_settings). race1=seaside-stunts car1=drifter and
##             race2=mountain-pass car2=dune with the medal autopilot: the race's theme music, a free
##             rev on the grid, the countdown's beeps 60 frames apart, a chime in the frame of every
##             checkpoint, lap and the finish, each cue raising the SFX bus at once, the finish's
##             stinger 0.9 s later and the music ducked; not silent, no clipping (the limiter's
##             ceiling); the engine sounds at the firing frequency of the sim's rpm (Goertzel, every
##             0.25 s) and through the gear changes (the pitch drops at the upshifts); landings,
##             nitro, blow-off, wind; gravel on dirt and snow on snow, neither on asphalt. Then
##             car3=thunder flat out into Rookie Oval's first barrier: the hit sound in the frame of
##             the contact, heard at once; Race the AI (the test network): its car is a quieter
##             3D sound at its place. Prints "AUDIO" lines with the measured levels.
##   field     Race the field (v6.13.0) on track=<id> (default rookie-oval) at level=<id> (default
##             elite) with the Racer: with My AI the menu's Race the field is off; the level's chip
##             (clicked) turns it on, on screen at 1280 x 720; clicked: the grid (five AI cars ahead,
##             two wide, you last on the start spot); the medal autopilot of the author run drives to
##             the finish (a shot when an AI car is close ahead, the HUD's place and standings); the
##             finish panel docks on the right with the field's order and the pay by place; the
##             podium with the top three; R starts it again, Esc goes back. Prints PERF lines: the
##             physics step of the six cars and the AI engines' script time per frame.
##             Shots: field_menu, field_grid, field_battle, field_finish, field_podium.
##   Every other scenario starts by owning every car, every track open (the terminal's unlock
##   tracks) and picking My AI as the opponent (they were written before the career: they drive
##   every car on every track and race the car's own network).
## Prints "ok"/"FAIL" lines and "E2E <scenario>: n passed, m failed"; quits with 1 on a failure.
## out=<dir> (default user://e2e) also holds the scratch files of the modes scenario;
## net=<file> is the network it loads (default the test fixture, a browser-format file).

const AiLink := preload("res://game/ai_link.gd")
const PlayMode := preload("res://modes/play_mode.gd")
const FieldMode := preload("res://modes/field_mode.gd")

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
	if not (scenario in ["economy", "terminal", "unlock", "upgrades"]):
		for c: String in Cars.ids():
			SaveData.give_car(c)
		SaveData.unlock_tracks(true)
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
		"terminal":
			await terminal()
		"unlock":
			await unlock()
		"upgrades":
			await upgrades()
		"audio":
			await audio_run()
		"field":
			await field_race()
		_:
			check(false, "unknown scenario " + scenario)
	print("E2E %s: %d passed, %d failed (%.1f s)" % [scenario, passed, failed, (Time.get_ticks_msec() - t0) / 1000.0])
	Engine.time_scale = 1.0
	# (v6.12) stop the sound and let the audio thread let go of it before quitting
	app.audio.shutdown()
	await frames(3)
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
	# (v6.11: the car with its upgrades; the stock spec itself when it has none)
	var spec: CarSpec = m.get("car_spec") if m.get("car_spec") is CarSpec else Cars.spec(cid)
	drive_with(Autopilot.medal(m.get("track"), a_lat, look_k, nitro, Autopilot.DECEL, spec))


## Drive the race in progress with autopilot `p`, feeding the input layer.
func drive_with(p: Autopilot) -> void:
	_pilot = p
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
	var tracks: PackedStringArray = str(opts.get("tracks", "rookie-oval,hairpin-valley,seaside-stunts,mountain-pass,canyon-run,summit-rush")).split(",")
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
	# rows: quality, screen dirt and snow (v6.10), fullscreen, vsync, interface size, ghost
	await key(KEY_RIGHT) # quality High -> Low
	await key(KEY_DOWN)
	await key(KEY_ENTER) # screen dirt and snow On -> Off
	await frames(3)
	await shot("settings") # (the new row picked, Off)
	await key(KEY_DOWN)
	await key(KEY_DOWN)
	await key(KEY_ENTER) # vsync On -> Off
	await key(KEY_DOWN)
	await key(KEY_RIGHT) # interface size Auto -> 100%
	await key(KEY_RIGHT) # -> 125%
	await key(KEY_DOWN)
	await key(KEY_RIGHT) # ghost On -> Off
	# (v6.12) Audio: down from the ghost to Master volume (the right column's top), then Music 70% -> 60%
	# and Mute in the background On -> Off
	await key(KEY_DOWN)
	await key(KEY_DOWN)
	await key(KEY_LEFT)
	for i in 3:
		await key(KEY_DOWN)
	await key(KEY_ENTER)
	await frames(3)
	await shot("settings_audio")
	await key(KEY_ESCAPE)
	await key(KEY_C) # next car
	await frames(3)
	check(UiData.get_setting("quality") == "low" and app.world.quality == "low" and not app.world.auto_quality, "quality Low applied (pinned)")
	check(UiData.get_setting("vsync") == false and DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED, "vsync off applied")
	check(is_equal_approx(float(UiData.get_setting("ui_scale")), 1.25) and is_equal_approx(app.ui.ui_scale, 1.25), "interface 125% applied")
	check(UiData.get_setting("ghost") == false, "ghost off")
	check(UiData.get_setting("grime") == false and not ScreenGrime.enabled, "screen dirt and snow off applied")
	check(is_equal_approx(float(UiData.get_setting("vol_music")), 0.6) and UiData.get_setting("mute_unfocused") == false
		and is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), GameAudio.volume_db(0.6)),
		"music 60%% (the Music bus at %.1f dB), mute in the background off" % AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")))
	print("PICKED ", UiData.picked_car())


func settings_check() -> void:
	await frames(5)
	check(UiData.get_setting("quality") == "low" and app.world.quality == "low" and not app.world.auto_quality, "after a restart: quality Low")
	check(UiData.get_setting("vsync") == false and DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED, "after a restart: vsync off")
	check(is_equal_approx(app.ui.ui_scale, 1.25), "after a restart: interface 125%")
	check(UiData.get_setting("ghost") == false and app.ui.menu.get("_ghost_check").checked == false, "after a restart: ghost off (menu tick too)")
	check(UiData.picked_car() == Cars.ids()[1], "after a restart: the picked car (%s)" % UiData.picked_car())
	check(UiData.get_setting("grime") == false and not ScreenGrime.enabled, "after a restart: screen dirt and snow off")
	check(is_equal_approx(float(UiData.get_setting("vol_music")), 0.6) and UiData.get_setting("mute_unfocused") == false
		and is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), GameAudio.volume_db(0.6)),
		"after a restart: music 60% on the Music bus, mute in the background off")
	# put them back (and check the file holds them)
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveData.path))
	check(raw.settings.quality == "low" and raw.settings.vsync == false and raw.settings.ghost == false and raw.settings.grime == false
		and is_equal_approx(float(raw.settings.vol_music), 0.6) and raw.settings.mute_unfocused == false,
		"the save file holds the settings")


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
## colour, and mud (or snow) splashes the screen, outside its middle (v6.10, in place of the
## camera's rumble). transition: a shot just before the border too, and the screen clean again on
## the asphalt after the stretch.
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
	# the most puffs alive over 12 frames, against 8 at full emission scaled by the graphics quality's
	# share (CarEffects.spark_share: low emits 30 %, about 8 puffs alive here with random lives, so one
	# frame's count against 8 was a coin flip; v6.9.0)
	var most := 0
	for k in 12:
		await frames(1)
		pool = model.dust if sid == "dirt" else model.spray
		most = maxi(most, pool.alive if pool != null else 0)
	var need: int = maxi(3, ceili(8.0 * CarEffects.spark_share))
	var slot := model.skids.newest_tint.x if si == 1 else model.skids.newest_tint.y
	check(pool != null and most >= need and pool.node.visible, "%s: on the %s (sample %d, %.0f km/h, slip %.2f) the tyres throw up %s: up to %d puffs alive over 12 frames (at least %d at this quality's %d %% emission; pool %d)" % [
		tag, sid, c.idx, c.speed * 3.6, c.slip, "dust" if sid == "dirt" else "snow", most, need, roundi(CarEffects.spark_share * 100.0), pool.max if pool != null else 0])
	check(model.skids.used > 0 and slot > 0.9, "%s: the newest tyre mark has the %s's colour (weight %.2f)" % [tag, sid, slot])
	var g: ScreenGrime = m.get("grime")
	var kind := 0 if sid == "dirt" else 1
	var splats := 0
	var inside := 0
	if g != null:
		for b: ScreenGrime.Blob in g.blobs():
			splats += 1 if b.kind == kind else 0
			inside += 1 if g.keep_metric(b.pos, g.reach(b)) < 0.999 else 0
	var layer := 0.0
	if g != null:
		layer = g.film if sid == "dirt" else g.frost
	check(g != null and g.visible and splats >= 3 and layer > 0.1 and inside == 0,
		"%s: %s on the screen: %d splats, %s %.2f, none in the middle" % [tag, "mud" if sid == "dirt" else "snow", splats, "film" if sid == "dirt" else "frost", layer])
	# (a shake now can only be a wall's)
	check(cam.shake == 0.0 or cam.trauma > 0.0 or cam.rumble > 0.01, "%s: the camera does not rumble on the %s (shake %.3f)" % [tag, sid, cam.shake])
	await shot("surfaces_" + sid)
	if transition and g != null:
		# past the stretch: the screen clears on the asphalt
		fast(true)
		await wait_until(func() -> bool: return c.idx > last + 12, 300.0)
		fast(false)
		var t0 := Time.get_ticks_msec()
		await wait_until(func() -> bool: return g.count() == 0 and g.film < 0.2, 120.0) # (real time: slow frames run the overlay slower)
		var secs := (Time.get_ticks_msec() - t0) / 1000.0
		check(g.count() == 0 and g.film < 0.2 and track.surface[c.idx] == Surfaces.ASPHALT,
			"%s: back on asphalt the mud is gone (after %.1f s of real time at this frame rate; film %.2f)" % [tag, secs, g.film])
		await shot("surfaces_after")
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
	var ca: CarAudio = m.get("car_audio") # (v6.12: the car's sound, part of the frame's script time)
	var au0 := ca.usec if ca != null else 0
	var au_n0 := ca.updates if ca != null else 0
	var au_s0 := ca.samples if ca != null else 0
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
	# (v6.12) the car's sound renders the engine for the time a frame took (up to CarAudio.LEAD_MAX), so
	# on these slow frames it costs several times what it does at 60 fps: take it out of the rest and
	# add back its cost for 1/60 s of engine (400 samples)
	var au_here := 0.0
	var au_60 := 0.0
	var au_per := 0.0
	var au_us := 0.0
	if ca != null:
		var au_frames := maxf(1, ca.updates - au_n0)
		au_here = (ca.usec - au0) / 1000.0 / au_frames
		au_per = float(ca.samples - au_s0) / au_frames
		au_us = (ca.usec - au0) / maxf(1, ca.samples - au_s0)
		au_60 = au_here * 400.0 / maxf(1.0, au_per)
	other_ms -= au_here
	print("PERF %s%s: %d frames, %d physics steps (%.1f per frame, the frames are slow here)" % [
		tid, " + AI ghost" if with_ai else "", n, steps, float(steps) / maxf(1, n)])
	print("PERF script time per frame (all _process, autopilot taken out): avg %.2f ms (raw median %.2f, p95 %.2f)" % [
		frame_ms, sorted[n / 2], sorted[int(n * 0.95)]])
	print("PERF   physics step %.3f ms each; the rest of a frame (model, camera, HUD, world, input) %.2f ms" % [step_ms, other_ms])
	if ca != null:
		print("PERF   sound (audio/car_audio.gd: the engine synthesized at %d Hz, events, loops) %.3f ms per frame here (%.0f engine samples a frame); %.2f µs a sample: %.2f ms a frame at 60 fps (400 samples)" % [
			int(CarAudio.ENGINE_RATE), au_here, au_per, au_us, au_60])
	print("PERF   at 60 fps (1 step a frame, the sound for 1/60 s): %.2f ms of 16.7; worst catch-up frame (6 steps): %.2f ms" % [
		other_ms + step_ms + au_60, other_ms + 6.0 * step_ms + au_60])
	print("PERF   autopilot (test input) %.3f ms per step; wall clock %.1f ms per frame incl. drawing (llvmpipe)" % [
		pilot_ms / maxf(1, steps), wall / maxf(1, n)])
	check(steps > 0 and other_ms + step_ms + au_60 < 16.0, "a race frame's script time fits in 16 ms")
	first.queue_free()
	last.queue_free()
	stop_autopilot()


# ---------------------------------------------------------------- Race the field (v6.13.0)

func field_race() -> void:
	var tid := str(opts.get("track", "rookie-oval"))
	var lv := str(opts.get("level", "elite"))
	var menu: MainMenu = app.ui.menu
	var btns: Dictionary = menu.get("_opp_btns")
	var fbtn: Button = menu.get("_field_btn")
	await pick(tid, "racer")
	check(UiData.opponent() == UiData.MY_AI and fbtn.disabled, "My AI picked: Race the field is off")
	await click(btns[lv])
	var r := fbtn.get_global_rect()
	var win := Vector2(root.size)
	check(UiData.opponent() == lv and not fbtn.disabled and fbtn.is_visible_in_tree() and r.position.y >= 0.0 and r.end.y <= win.y + 0.5 and r.end.x <= win.x + 0.5,
		"the %s chip (clicked): Race the field is on, on screen at %dx%d (%s)" % [Opponents.level_name(lv), int(win.x), int(win.y), fbtn.tooltip_text])
	await shot("field_menu")
	await click(fbtn)
	var m: Node = app.mode
	if not check(m != app.menu_mode and m.name == "FieldMode" and str(app.ui.hud.get("_mode").text).begins_with(Opponents.level_name(lv).to_upper() + " FIELD"),
			"Race the field (clicked): %s" % app.ui.hud.get("_mode").text):
		return
	var fr: FieldRace = m.get("field")
	var track: BuiltTrack = m.get("track")
	var car: Car = m.get("car")
	await frames(6) # (still in the countdown)
	var ahead := 0
	for k in 5:
		if fr.racers[k].car.prog > car.prog and (m.get("ai_models") as Array)[k].visible:
			ahead += 1
	var names: PackedStringArray = []
	for e: Dictionary in m.get("lineup"):
		names.append("%s (%s)" % [e.name, Cars.get_car(String(e.car)).name])
	check(m.get("phase") == "countdown" and ahead == 5 and absf(car.prog - float(track.start_idx)) < 0.05, "the grid: five AI cars ahead of you (%s), you last on the start spot" % ", ".join(names))
	await shot("field_grid")
	var run: Dictionary = Medals.medal_times(track, "racer").run
	await wait_until(func() -> bool: return m.get("phase") == "race", 30.0)
	autopilot(float(run.aLat), float(run.lookK))
	var steps0: int = m.get("steps_run")
	var usec0: int = m.get("step_usec")
	var near := func() -> bool:
		var rt: float = (m.get("race") as RaceState).time
		if rt >= 45.0:
			return true
		if rt < 8.0:
			return false
		for k in 5:
			var c: Car = fr.racers[k].car
			var d := Vector2(c.x - car.x, c.z - car.z)
			var fwd := Vector2(sin(car.yaw), cos(car.yaw))
			if d.dot(fwd) > 5.0 and d.dot(fwd) < 14.0 and absf(d.cross(fwd)) < 4.0:
				return true
		return false
	fast(true)
	await wait_until(near, 120.0)
	fast(false)
	await frames(30)
	var ft: PackedStringArray = app.ui.hud.get("field_text")
	var bd: Dictionary = m.get("board")
	check(ft.size() == 9 and ft[0] == "P%d/6" % int(bd.pos) and (app.ui.hud.get("_field_plate") as Control).is_visible_in_tree(),
		"mid-race (%.0f s): the HUD's field block %s, %s, %s" % [(m.get("race") as RaceState).time, ft[0], ft[1], ft[2]])
	await shot("field_battle")
	var vu0: int = m.get("voice_usec")
	var vf0: int = m.get("voice_frames")
	var vs0 := 0
	for a: CarAudio in m.get("ai_audio"):
		vs0 += a.samples
	await frames(240)
	var vu: int = int(m.get("voice_usec")) - vu0
	var vf: int = int(m.get("voice_frames")) - vf0
	var vs := -vs0
	for a: CarAudio in m.get("ai_audio"):
		vs += a.samples
	var steps: int = int(m.get("steps_run")) - steps0
	var step_ms: float = (int(m.get("step_usec")) - usec0) / 1000.0 / maxf(1, steps)
	var us_sample: float = float(vu) / maxf(1, vs)
	print("PERF field: physics step of the six cars (the AI networks, contacts, races; the autopilot's input included) %.3f ms each over %d steps" % [step_ms, steps])
	print("PERF field: AI engines (%d voices at once) %.3f ms per frame here (%.0f samples a frame), %.2f us a sample: %.2f ms a frame at 60 fps (%d x 400 samples)" % [
		FieldMode.VOICES, float(vu) / 1000.0 / maxf(1, vf), float(vs) / maxf(1, vf), us_sample, us_sample * 400.0 * FieldMode.VOICES / 1000.0, FieldMode.VOICES])
	check(vf > 0 and step_ms < 6.0, "the field's step and the AI engines measured (%.2f ms a step)" % step_ms)
	fast(true)
	await wait_until(func() -> bool: return m.get("phase") == "finished", 600.0)
	fast(false)
	stop_autopilot()
	await frames(20)
	var place := fr.position(fr.player_index)
	var fs: Dictionary = m.get("finish_state")
	var p: Dictionary = fs.get("payout", {})
	var fids: Array = (p.get("items", []) as Array).filter(func(it: Dictionary) -> bool: return String(it.kind) == "field").map(func(it: Dictionary) -> String: return String(it.id))
	var panel: FinishPanel = app.ui.hud.finish
	var texts := _texts(panel)
	check((m.get("race") as RaceState).finished and PackedStringArray(fids) == Economy.field_ids(lv, place) and texts.has(Field.place_name(place)) and
		texts.has("of 6 · %s field" % Opponents.level_name(lv)) and panel.get_global_rect().position.x > win.x * 0.3,
		"the finish: %s in %s, %s paid by place (%s), the panel on the right with the field's order" % [Field.place_name(place),
		RaceState.format_time((m.get("race") as RaceState).finish_time), UiFormat.money(int(p.get("money", 0))), ", ".join(fids)])
	await shot("field_finish")
	await wait_until(func() -> bool: return m.get("podium_on") == true and fr.all_done(), 30.0)
	await frames(90)
	var pod: Podium = m.get("podium")
	check(pod != null and pod.visible and pod.has(1) and pod.has(2) and pod.has(3) and pod.camera.current and fr.all_done(),
		"the podium: the top three on their blocks (%s, %s, %s), every AI finished" % [fr.code_of(fr.standings()[0]), fr.code_of(fr.standings()[1]), fr.code_of(fr.standings()[2])])
	await shot("field_podium")
	await key(KEY_R)
	await frames(10)
	check(m.get("phase") == "countdown" and m.get("podium_on") == false and not panel.visible, "R: the field on the grid again")
	await key(KEY_ESCAPE)
	await frames(10)
	check(app.mode == app.menu_mode, "Esc: back to the menu")


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

	check(Dictionary(fs.get("unlocked", {})).get("id") == "hairpin-valley" and _texts(app.ui.hud.finish).has("Hairpin Valley unlocked") and
		not (menu.get("_tiles")[1] as Control).get("locked") and (menu.get("_tiles")[1] as Control).get("is_new"),
		"the gold opened Hairpin Valley: the finish panel said so, its tile is NEW")

	# the Expert AI on Seaside Stunts (the author run): more money on a later track (v6.8.0: tracks
	# 3-12 opened here as bronzes on each would; the run then opens Forest Rally)
	for i in range(2, 12):
		SaveData.open_track(Tracks.ids()[i])
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
	check(Dictionary((m.get("finish_state") as Dictionary).get("unlocked", {})).get("id") == "forest-rally", "and opens Forest Rally")
	await key(KEY_ESCAPE)
	await frames(30)
	var tiles: Array = menu.get("_tiles")
	check(money_l.text == UiFormat.money(UiData.money()) and points_l.text == "%s pts" % UiFormat.points(UiData.points()) and tiles[12].is_new and
		tiles[13].locked and tiles[14].locked and UiData.open_track_count() == 13, "the menu: %s, %s; Forest Rally NEW, the last two tracks locked" % [money_l.text, points_l.text])
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


## The texts of every Label under `n`.
func _texts(n: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if n is Label:
		out.append((n as Label).text.strip_edges())
	for c in n.get_children():
		out.append_array(_texts(c))
	return out


## The money (x) and points (y) of rewards `ids` on track `tid`.
func _sum(tid: String, ids: Array) -> Vector2i:
	var v := Vector2i.ZERO
	for id: String in ids:
		var r := Economy.reward(tid, id)
		v += Vector2i(int(r.money), int(r.points))
	return v


# ---------------------------------------------------------------- the terminal (v6.7.0)

## Type `text` as key presses with their characters (letters, digits, space, minus; others by
## character only), then Enter when `enter`.
func type_text(text: String, enter: bool = true) -> void:
	for ch in text:
		var k: Key = KEY_NONE
		var c := ch.to_upper().unicode_at(0)
		if (c >= KEY_A and c <= KEY_Z) or (c >= KEY_0 and c <= KEY_9):
			k = c as Key
		elif ch == " ":
			k = KEY_SPACE
		elif ch == "-":
			k = KEY_MINUS
		for down: bool in [true, false]:
			var e := InputEventKey.new()
			e.keycode = k
			e.physical_keycode = k
			e.unicode = ch.unicode_at(0) if down else 0
			e.pressed = down
			Input.parse_input_event(e)
		await frames(1)
	if enter:
		await key(KEY_ENTER)
	await frames(1)


func terminal() -> void:
	var menu: MainMenu = app.ui.menu
	var term: TerminalScreen = menu.terminal
	var money_l: Label = menu.get("_money_l")
	var points_l: Label = menu.get("_points_l")
	var drive_btn: Button = menu.get("_drive_btn")
	check(UiData.money() == 0 and SaveData.owned_cars() == PackedStringArray(["racer"]) and not term.visible, "a new career: $0, only the Racer; the terminal is closed")
	await key(KEY_QUOTELEFT)
	check(term.visible and term.line.has_focus() and app.mode == app.menu_mode, "` on the menu opens the terminal, the input has the keyboard focus")
	await type_text("help")
	check(term.log_text().contains("> help") and term.log_text().contains("money <n> | set <n>") and term.log_text().contains("unlock all"), "help lists the commands")
	await type_text("money 25000")
	var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(SaveData.path))
	check(UiData.money() == 25000 and money_l.text == "$25,000" and term.log_text().contains("Money +$25,000: now $25,000") and
		disk is Dictionary and int(disk.career.money) == 25000, "money 25000: +$25,000 (the menu's header %s at once, the save file too)" % money_l.text)
	await type_text("points 200")
	check(UiData.points() == 200 and points_l.text == "200 pts", "points 200: %s" % points_l.text)
	await type_text("mony 5")
	await type_text("money lots")
	check(UiData.money() == 25000 and term.log_text().contains("Did you mean money?") and term.log_text().contains("\"lots\" is not a whole number"),
		"a mistyped command and a bad number: short errors, nothing changes")
	await type_text("status")
	check(term.log_text().contains("$25,000") and term.log_text().contains("Racer (1 of 6)") and term.log_text().contains("0 author"), "status: money, points, cars, medals")
	check(menu.selected_track == 0 and not menu.settings.visible and not menu.controls.visible and app.mode == app.menu_mode and UiData.picked_car() == "racer",
		"the letters and Enter typed there never reached the menu (no Settings on O, no Controls on H, no next car on C, no Drive on Enter)")
	await frames(10)
	await shot("terminal_menu")
	# history and Tab
	await key(KEY_UP)
	var first := term.line.text
	await key(KEY_UP)
	var second := term.line.text
	await key(KEY_DOWN)
	await key(KEY_DOWN)
	check(first == "status" and second == "money lots" and term.line.text == "" and term.line.has_focus(), "Up / Down: the lines typed before (%s, %s), then the empty line again" % [first, second])
	await type_text("unl", false)
	await key(KEY_TAB)
	check(term.line.text == "unlock " and term.line.has_focus() and term.visible, "Tab completes unl to \"unlock \" (the focus stays)")
	for i in term.line.text.length():
		await key(KEY_BACKSPACE)
	await type_text("c", false)
	await key(KEY_TAB)
	check(term.line.text == "c" and term.log_text().contains("Tab: car, clear"), "Tab with two matches lists them (car, clear)")
	await key(KEY_BACKSPACE)
	await key(KEY_QUOTELEFT)
	check(not term.visible and app.mode == app.menu_mode and not menu.settings.visible, "` closes it")
	await key(KEY_QUOTELEFT)
	check(term.visible and term.line.text == "", "` again: open, and no ` was typed into the input")
	await key(KEY_ESCAPE)
	check(not term.visible and app.mode == app.menu_mode, "Esc closes it (still on the menu)")

	# the money buys the Kestrel on the car picker
	while UiData.picked_car() != "kestrel":
		await key(KEY_C)
	await frames(4)
	check(drive_btn.text == "BUY $10,000", "the Kestrel: BUY $10,000 (the terminal's money counts)")
	await key(KEY_ENTER)
	await frames(4)
	check(app.message.asking, "BUY asks first")
	await key(KEY_ENTER)
	await frames(4)
	check(SaveData.owns_car("kestrel") and UiData.money() == 15000 and money_l.text == "$15,000" and drive_btn.text == "DRIVE", "bought: the Kestrel is yours, $15,000 left")

	# Settings: the Terminal row and its button
	await key(KEY_O)
	await frames(4)
	var set_bar := (menu.settings.get("_scroll") as ScrollContainer).get_v_scroll_bar()
	check(set_bar.max_value <= set_bar.page + 0.5, "Settings with the Terminal row fits 1280 x 720 without scrolling (content %.0f px, page %.0f)" % [set_bar.max_value, set_bar.page])
	var rows: Array = menu.settings.get("_rows")
	var row: Dictionary = rows[rows.size() - 1]
	var open_btn: Button = row.segs[0]
	check(menu.settings.visible and str(row.def.key) == "terminal" and open_btn.is_visible_in_tree(), "Settings shows the Terminal row with its Open button")
	await frames(10)
	await shot("terminal_settings")
	await click(open_btn)
	check(term.visible and menu.settings.visible and term.line.has_focus(), "Open (clicked) opens the terminal over Settings")
	await type_text("buy dune")
	check(not SaveData.owns_car("dune") and term.log_text().contains("$3,000 short"), "buy dune with $15,000: $3,000 short, nothing bought")
	await type_text("money 3000")
	await type_text("buy dune")
	check(SaveData.owns_car("dune") and UiData.money() == 0 and money_l.text == "$0" and term.log_text().contains("Bought the Dune for $18,000"), "money 3000, buy dune: the Dune is bought with it ($0 left)")
	await frames(6)
	await shot("terminal_over_settings")
	await key(KEY_ESCAPE)
	check(not term.visible and menu.settings.visible, "Esc closes the terminal: back to Settings")
	await key(KEY_QUOTELEFT)
	check(term.visible and menu.settings.visible, "` on Settings opens it again")
	await key(KEY_QUOTELEFT)
	check(not term.visible and menu.settings.visible, "and ` closes it")
	await key(KEY_ESCAPE)
	check(not menu.settings.visible and app.mode == app.menu_mode, "Esc closes Settings")
	# the gamepad: Settings' Terminal row, A opens it, B closes it
	var inp := app.input
	inp.pad_active = true
	await key(KEY_O)
	for i in rows.size():
		if menu.settings.selected_row == rows.size() - 1:
			break
		inp.pad_active = true
		inp.press("NavDown")
		await frames(2)
	check(menu.settings.selected_row == rows.size() - 1, "pad: down to the Terminal row")
	inp.pad_active = true
	inp.press("PadA")
	await frames(2)
	check(term.visible, "pad A opens the terminal")
	inp.pad_active = true
	inp.press("PadB")
	await frames(2)
	check(not term.visible and menu.settings.visible, "pad B closes it (back to Settings)")
	inp.press("PadB")
	await frames(2)
	check(not menu.settings.visible, "pad B closes Settings")
	# exit + Enter closes it without the Enter reaching the menu
	await key(KEY_QUOTELEFT)
	await type_text("exit")
	await frames(3)
	check(not term.visible and app.mode == app.menu_mode, "exit + Enter closes the terminal and doesn't drive")

	# in a race ` does nothing
	while UiData.picked_car() != "dune":
		await key(KEY_C)
	await key(KEY_ENTER)
	var m: Node = app.mode
	check(m != app.menu_mode and str((m.get("car_def") as Dictionary).id) == "dune", "Enter drives the Dune")
	await wait_until(func() -> bool: return m.get("phase") == "race", 30.0)
	app.input.held = {"accelerate": true}
	await frames(30)
	var step0 := int(m.get("race_step"))
	await key(KEY_QUOTELEFT)
	await frames(30)
	app.input.held = {}
	check(app.mode == m and m.get("phase") == "race" and int(m.get("race_step")) > step0 and not term.visible and not menu.visible,
		"in a race ` does nothing: no terminal, the race goes on (step %d -> %d)" % [step0, int(m.get("race_step"))])
	await key(KEY_ESCAPE)
	await frames(4)
	check(app.mode == app.menu_mode and not term.visible, "Esc: back on the menu, the terminal closed")


# ---------------------------------------------------------------- the tracks open one at a time (v6.8.0)

func unlock() -> void:
	var menu: MainMenu = app.ui.menu
	var tiles: Array = menu.get("_tiles")
	var drive_btn: Button = menu.get("_drive_btn")
	var lock_note: Control = menu.get("_td_lock")
	var msg: Label = app.message.get("_text")
	menu.select_opponent("rookie")
	var locked := tiles.filter(func(x: Control) -> bool: return x.get("locked")).size()
	check(UiData.open_track_count() == 1 and locked == 14 and not tiles[0].locked and tiles[1].lock_note == "Bronze on 01" and tiles[14].lock_note == "Bronze on 14",
		"a new career: only Rookie Oval is open, 14 tiles locked (Hairpin Valley's: %s)" % tiles[1].lock_note)
	await frames(10)
	await shot("unlock_menu")
	# the keys still pick a locked track
	await key(KEY_2)
	await wait_until(func() -> bool: return not app.building_track(), 60.0)
	await frames(10)
	var lock_text := (menu.get("_td_lock_text") as RichTextLabel).get_parsed_text()
	check(menu.selected_track == 1 and lock_note.is_visible_in_tree() and lock_text.begins_with("Locked: win bronze or better on Rookie Oval") and drive_btn.text == "LOCKED",
		"2 picks locked Hairpin Valley: %s; Drive reads LOCKED" % lock_text)
	# the whole menu still fits 1280 x 720 with the lock note (on every locked track)
	var win := Vector2(root.size)
	var bar := (menu.get("_scroll") as ScrollContainer).get_v_scroll_bar()
	var worst := 0.0
	var worst_id := ""
	for i in range(1, 15):
		menu.select(i)
		await frames(3)
		var end := maxf((menu.get("_train_btn") as Control).get_global_rect().end.y, (menu.get("_detail") as Control).get_global_rect().end.y)
		if end > worst:
			worst = end
			worst_id = UiData.track_id(i)
	await key(KEY_2)
	await wait_until(func() -> bool: return not app.building_track(), 60.0)
	await frames(5)
	var note_r := lock_note.get_global_rect()
	var stats_r := ((menu.get("_stats") as Array)[0].box as Control).get_global_rect()
	check(win == Vector2(1280, 720) and worst <= win.y + 0.5 and bar.max_value <= bar.page + 0.5 and note_r.end.y <= stats_r.position.y,
		"1280 x 720 with the lock note on every locked track: no scrolling, the lowest button ends at %d px (%s); the note (%d px high) sits above the stats" % [
		roundi(worst), worst_id, roundi(note_r.size.y)])
	await shot("unlock_locked")
	# Drive and Race the AI: refused with a message
	await key(KEY_ENTER)
	await frames(5)
	check(app.mode == app.menu_mode and app.message.visible and msg.text.contains("Hairpin Valley opens when you win a bronze medal or better on Rookie Oval") and
		msg.text.contains("Watch the AI and Train the AI work on every track"), "Enter (Drive): refused: %s" % msg.text)
	await shot("unlock_message")
	await key(KEY_ESCAPE)
	await frames(3)
	check(not app.message.visible, "Esc closes the message")
	await click(menu.get("_ghost_btn"))
	await frames(3)
	check(app.mode == app.menu_mode and app.message.visible and msg.text.contains("Hairpin Valley opens"), "Race the Rookie AI (clicked): refused too")
	await key(KEY_ESCAPE)
	await frames(3)
	# Watch the AI and Train the AI work on a locked track
	await click(menu.get("_watch_btn"))
	await frames(30)
	var wm: Node = app.mode
	check(wm != app.menu_mode and wm.get("driver") == "ai" and (wm.get("track") as BuiltTrack).id == "hairpin-valley", "Watch the Rookie AI (clicked): the AI drives Hairpin Valley")
	await key(KEY_ESCAPE)
	await frames(10)
	check(app.mode == app.menu_mode, "Esc: back on the menu")
	await click(menu.get("_train_btn"))
	await frames(5)
	check(app.train_mode != null and app.mode == app.train_mode, "Train the AI (clicked): the training screen opens on Hairpin Valley")
	await key(KEY_ESCAPE)
	await frames(10)
	check(app.mode == app.menu_mode, "Esc: back on the menu")
	# a bronze on Rookie Oval opens Hairpin Valley
	await key(KEY_1)
	await wait_until(func() -> bool: return not app.building_track(), 60.0)
	check(drive_btn.text == "DRIVE" and not lock_note.is_visible_in_tree(), "1: Rookie Oval, DRIVE")
	await key(KEY_ENTER)
	var m: Node = app.mode
	if not check(m != app.menu_mode and m.get("driver") == "human" and (m.get("track") as BuiltTrack).id == "rookie-oval", "Enter drives Rookie Oval"):
		return
	# (v6.9.0: bronze is 2:39 now; corner grip 13 m/s² and 50 m/s at most finish in 2:32.900, between
	# silver and bronze; v6.8.0's 11 m/s² and 40 m/s took 2:49.750)
	drive_with(Autopilot.basic(m.get("track"), 13.0, 7.5, 50.0, Cars.spec("racer")))
	fast(true)
	await wait_until(func() -> bool: return m.get("phase") == "finished", 900.0)
	fast(false)
	stop_autopilot()
	await frames(40)
	var fs: Dictionary = m.get("finish_state")
	var race: RaceState = m.get("race")
	var u: Dictionary = fs.get("unlocked", {})
	check(race.finished and Dictionary(fs.get("payout", {})).get("medal") == "bronze" and u.get("id") == "hairpin-valley" and app.ui.hud.panel_open and
		_texts(app.ui.hud.finish).has("Hairpin Valley unlocked") and _texts(app.ui.hud.finish).has("track 02 is open: pick it on the menu"),
		"%s, a bronze: the finish panel says Hairpin Valley unlocked (track 02 is open)" % RaceState.format_time(race.finish_time))
	await shot("unlock_finish")
	await key(KEY_ESCAPE)
	await frames(30)
	check(app.mode == app.menu_mode and not tiles[1].locked and tiles[1].is_new and tiles[2].locked and tiles[2].lock_note == "Bronze on 02" and UiData.open_track_count() == 2,
		"back on the menu: Hairpin Valley open and NEW; Ramp Rally locked (Bronze on 02)")
	await shot("unlock_menu_after")
	await key(KEY_2)
	await wait_until(func() -> bool: return not app.building_track(), 60.0)
	check(not tiles[1].is_new and drive_btn.text == "DRIVE" and not lock_note.is_visible_in_tree(), "2 picks it: NEW gone, DRIVE")
	await key(KEY_ENTER)
	await frames(5)
	check(app.mode != app.menu_mode and (app.mode.get("track") as BuiltTrack).id == "hairpin-valley", "Enter drives Hairpin Valley")
	await key(KEY_ESCAPE)
	await frames(10)
	var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(SaveData.path))
	check(disk is Dictionary and JsMath.same(disk.get("version"), 4) and (disk.career as Dictionary).get("tracks_open") == ["hairpin-valley"],
		"the save file: career.tracks_open = [\"hairpin-valley\"] (still version 4)")


# ---------------------------------------------------------------- upgrades (v6.11.0)

func upgrades() -> void:
	var menu: MainMenu = app.ui.menu
	var chips: Array = menu.get("_part_chips")
	var money_l: Label = menu.get("_money_l")
	var msg: Label = app.message.get("_text")
	var tid := "rookie-oval"
	check(UiData.money() == 0 and SaveData.owned_cars() == PackedStringArray(["racer"]) and Upgrades.is_stock(SaveData.get_upgrades("racer")),
		"a new career: $0, the Racer, stock")
	await pick(tid, "racer")
	await frames(4)
	var shown := chips.size() == 4
	for c: Button in chips:
		shown = shown and c.is_visible_in_tree() and not c.disabled and int(c.get("level")) == 0 and not bool(c.get("affordable"))
	check(shown, "the Racer's four part chips on the car picker: level 0, the next level's price (grey: $0)")
	# the Kestrel (not yours): its chips are off and its description shows
	while UiData.picked_car() != "kestrel":
		await key(KEY_C)
	await frames(4)
	check((chips[0] as Button).disabled and not (menu.get("_parts_row") as Control).is_visible_in_tree() and (menu.get("_car_desc_row") as Control).is_visible_in_tree(),
		"the Kestrel (not yours): its parts are off, its description shows instead")
	while UiData.picked_car() != "racer":
		await key(KEY_C)
	await frames(4)
	# the stock Racer: the author run
	var track: BuiltTrack = app.tracks[0]
	var medals := Medals.medal_times(track, "racer")
	var run: Dictionary = medals.run
	await key(KEY_ENTER)
	var m: Node = app.mode
	if not check(m != app.menu_mode and (m.get("car") as Car).spec == Cars.spec("racer"), "Enter drives the stock Racer"):
		return
	autopilot(float(run.aLat), float(run.lookK))
	fast(true)
	await wait_until(func() -> bool: return m.get("phase") == "finished", 600.0)
	fast(false)
	stop_autopilot()
	var t0: float = (m.get("race") as RaceState).finish_time
	var w0: int = int((m.get("score") as ScoreState).counts.wall_hits)
	check(absf(t0 - float(medals.author)) < 0.0005, "the stock Racer's author run: %s (the author time %s)" % [RaceState.format_time(t0), RaceState.format_time(float(medals.author))])
	await key(KEY_ESCAPE)
	await frames(10)
	# money (the terminal), then the chips buy every level of every part
	await key(KEY_QUOTELEFT)
	var need := Upgrades.car_total("racer")
	await type_text("money %d" % (need + 5000 - UiData.money()))
	await key(KEY_QUOTELEFT)
	await frames(6)
	check(UiData.money() == need + 5000 and bool(chips[0].get("affordable")), "the terminal's money: %s; the chips' prices in the accent" % money_l.text)
	# the menu still fits 1280 x 720 with the parts row
	var win := Vector2(root.size)
	var bar := (menu.get("_scroll") as ScrollContainer).get_v_scroll_bar()
	var inside := true
	for c: Control in chips + [menu.get("_drive_btn"), menu.car_card()]:
		var r := c.get_global_rect()
		inside = inside and r.position.y >= 0.0 and r.end.y <= win.y + 0.5 and r.position.x >= 0.0 and r.end.x <= win.x + 0.5 and c.is_visible_in_tree()
	check(win == Vector2(1280, 720) and inside and bar.max_value <= bar.page + 0.5, "1280 x 720: the part chips, the cars and Drive on screen, no scrolling")
	await shot("upgrades_menu")
	var money0 := UiData.money()
	await click(chips[0])
	await frames(6)
	check(app.message.asking and msg.text.contains("Level 1 of 3") and msg.text.contains("Medal times and the AI opponents stay"), "the Engine chip (clicked) asks first: %s" % msg.text.left(90))
	await shot("upgrades_ask")
	await click(app.message.get("_yes"))
	await frames(4)
	check(SaveData.get_upgrades("racer")[0] == 1 and UiData.money() == money0 - Upgrades.price("racer", "engine", 1) and money_l.text == UiFormat.money(UiData.money()) and
		not app.message.visible, "Buy (clicked): the engine at level 1, %s left" % money_l.text)
	var asked := 1
	for k in 4:
		while int(chips[k].get("level")) < 3 and asked < 20:
			await click(chips[k])
			await frames(3)
			asked += 1
			if app.message.asking:
				await click(app.message.get("_yes"))
				await frames(3)
	await frames(6)
	var maxed := true
	for c: Button in chips:
		maxed = maxed and c.disabled and c.call("price_text") == "MAX"
	check(SaveData.get_upgrades("racer") == PackedInt32Array([3, 3, 3, 3]) and maxed and UiData.money() == 5000 and asked == 12,
		"12 clicks (each asked and bought): every part at level 3, the chips read MAX, %s spent, $5,000 left" % UiFormat.money(need))
	var card: Control = menu.car_card()
	var b0: Dictionary = UiData.car_info("racer").bars
	var bu: Dictionary = card.get("bars_up")
	check(float(bu.speed) > float(b0.speed) and float(bu.grip) > float(b0.grip) and float(bu.acceleration) > float(b0.acceleration) and float(bu.nitro) > float(b0.nitro),
		"the Racer's card: speed %.2f -> %.2f, acceleration %.2f -> %.2f, grip %.2f -> %.2f, nitro %.2f -> %.2f (green on top of the stock bars)" % [
		float(b0.speed), float(bu.speed), float(b0.acceleration), float(bu.acceleration), float(b0.grip), float(bu.grip), float(b0.nitro), float(bu.nitro)])
	await shot("upgrades_max")
	# the upgraded Racer, the same autopilot: faster than the author time
	await key(KEY_ENTER)
	m = app.mode
	if not check(m != app.menu_mode and (m.get("car") as Car).spec == Upgrades.spec("racer", PackedInt32Array([3, 3, 3, 3])), "Enter drives the upgraded Racer"):
		return
	autopilot(float(run.aLat), float(run.lookK))
	fast(true)
	await wait_until(func() -> bool: return (m.get("race") as RaceState).time >= 20.0, 120.0)
	fast(false)
	await frames(20)
	await shot("upgrades_race")
	fast(true)
	await wait_until(func() -> bool: return m.get("phase") == "finished", 600.0)
	fast(false)
	stop_autopilot()
	await frames(30)
	var t3: float = (m.get("race") as RaceState).finish_time
	var fs: Dictionary = m.get("finish_state")
	var rec := SaveData.get_record(tid, "racer")
	# (the autopilot keeps the stock car's author settings: its corner speeds don't use the extra grip, and the
	# quicker car arrives at the corners faster, so it gains less than a sweep tuned for it would)
	var w3: int = int((m.get("score") as ScoreState).counts.wall_hits)
	check(t3 < t0 * 0.995 and fs.get("medal", {}).get("got") == "author" and absf(float(rec.time) - t3) < 1e-9 and rec.up == PackedInt32Array([3, 3, 3, 3]),
		"the upgraded Racer, the same autopilot (the author run's settings): %s against %s stock (%.1f %% quicker; the author time stays %s); the record keeps the levels; wall contacts %d (stock %d)" % [
		RaceState.format_time(t3), RaceState.format_time(t0), (1.0 - t3 / t0) * 100.0, RaceState.format_time(float(medals.author)), w3, w0])
	await shot("upgrades_finish")
	# R: the upgraded run's ghost replays it
	await key(KEY_R)
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
	check(seen[0] > 20 and worst[0] < 0.03, "R: the upgraded run's ghost replays it: %d frames, at most %.3f m from the car" % [seen[0], worst[0]])
	await key(KEY_ESCAPE)
	await frames(6)
	check(app.mode == app.menu_mode, "back on the menu")


# ---------------------------------------------------------------- sound and music (v6.12.0)

## One bus tapped with an AudioEffectCapture (`pre`: in front of the bus's other effects, the
## Master's limiter; else after them). A bus's effects run before its own volume and mute: the
## Music, SFX and Engine taps hear their bus before its volume, the Master tap the mix of the
## three after their volumes but before the master volume (the output's level is the Master tap's
## plus GameAudio.volume_db(vol_master); AudioServer's Master peak meter is after it). Every frame drain() takes what was mixed since: its RMS and peak, and while
## `keep` the samples as mono at half the mix rate (pairs averaged).
class Tap:
	var bus := ""
	var cap := AudioEffectCapture.new()
	var keep := false
	var samples := PackedFloat32Array()
	var rms := 0.0
	var peak := 0.0
	var got := 0
	var _odd := false
	var _half := 0.0

	func _init(p_bus: String, pre: bool = false) -> void:
		bus = p_bus
		cap.buffer_length = 2.0
		AudioServer.add_bus_effect(AudioServer.get_bus_index(bus), cap, 0 if pre else -1)

	func remove() -> void:
		var b := AudioServer.get_bus_index(bus)
		for k in AudioServer.get_bus_effect_count(b):
			if AudioServer.get_bus_effect(b, k) == cap:
				AudioServer.remove_bus_effect(b, k)
				return

	func drain() -> void:
		var n := cap.get_frames_available()
		got = n
		rms = 0.0
		peak = 0.0
		if n <= 0:
			return
		var buf := cap.get_buffer(n)
		var s2 := 0.0
		var pk := 0.0
		for v: Vector2 in buf:
			s2 += v.x * v.x + v.y * v.y
			pk = maxf(pk, maxf(absf(v.x), absf(v.y)))
			if keep:
				var m := (v.x + v.y) * 0.5
				if _odd:
					samples.append((_half + m) * 0.5)
				else:
					_half = m
				_odd = not _odd
		rms = sqrt(s2 / (2.0 * n))
		peak = pk


## Runs last in every frame: drains the taps, then calls on_frame (the scenario's log).
class Probe extends Node:
	var taps: Array = []
	var on_frame: Callable

	func _init() -> void:
		process_priority = 2000000
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(_d: float) -> void:
		for t: Tap in taps:
			t.drain()
		if on_frame.is_valid():
			on_frame.call()


## The audio run's state: the taps, the frame log, the sounds played and where each part began.
var _au := {}
const AU_COLS := ["frame", "part", "phase", "rpm", "gear", "speed", "slip", "dust", "snow", "splits", "wall_hits",
	"mix_rms", "mix_peak", "pre_peak", "out_peak_db", "engine_rms", "sfx_rms", "music_rms", "engine_n",
	"gravel", "snow_lvl", "squeal", "wind", "scrape", "nitro", "boost", "limiter", "music_db", "t_game", "t_audio", "spool"]
const COL_T_GAME := 28
const COL_T_AUDIO := 29
const COL_SPOOL := 30


func audio_run() -> void:
	var a: GameAudio = app.audio
	var out := out_dir
	var rate := AudioServer.get_mix_rate()
	var movie := Engine.get_write_movie_path() != ""
	print("AUDIO mix rate %d Hz, %s, %s" % [rate, "Movie Maker (lockstep) " + Engine.get_write_movie_path() if movie else "real time (no Movie Maker)",
		AudioServer.get_output_device()])
	var names := PackedStringArray()
	for i in AudioServer.bus_count:
		names.append("%s -> %s" % [AudioServer.get_bus_name(i), AudioServer.get_bus_send(i)] if i > 0 else AudioServer.get_bus_name(i))
	check(AudioServer.get_bus_index("Music") > 0 and AudioServer.get_bus_index("SFX") > 0 and AudioServer.get_bus_index("Engine") > 0,
		"the buses: %s" % ", ".join(names))
	var lim := AudioServer.get_bus_effect(0, 0)
	check(lim is AudioEffectHardLimiter, "a hard limiter on Master (ceiling %.1f dB)" % (lim as AudioEffectHardLimiter).ceiling_db if lim is AudioEffectHardLimiter else "no limiter")
	# the taps: Master before and after the limiter, Music, SFX and Engine
	var taps := {"pre": Tap.new("Master", true), "mix": Tap.new("Master"), "music": Tap.new("Music"), "sfx": Tap.new("SFX"), "engine": Tap.new("Engine")}
	var rec := AudioEffectRecord.new()
	rec.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(0, rec, -1)
	var probe := Probe.new()
	probe.taps = taps.values()
	_au = {"rows": [], "events": [], "seen": -1, "part": 0, "taps": taps, "parts": {}, "t_game": 0.0, "f0": Engine.get_process_frames(),
		"w0": Time.get_ticks_usec(), "lockstep": movie}
	probe.on_frame = _audio_log
	root.add_child(probe)
	# ---- the menu: its music, then the clicks
	await wait_until(func() -> bool: return a.music_name == "menu", 10.0)
	await game_seconds(1.5) # (the music fades in)
	_audio_part("menu")
	rec.set_recording_active(true)
	await game_seconds(8.0)
	rec.set_recording_active(false)
	_save_clip(rec, out.path_join("menu_music.wav"))
	var mm := _audio_stats("menu")
	print("AUDIO menu music (8 s, master %.0f%%, music %.0f%%): mix RMS %.1f dBFS, peak %.1f dBFS; heard (after the master volume) RMS %.1f dBFS" % [
		float(UiData.get_setting("vol_master")) * 100.0, float(UiData.get_setting("vol_music")) * 100.0,
		mm.mix_rms_db, mm.mix_peak_db, mm.mix_rms_db + GameAudio.volume_db(float(UiData.get_setting("vol_master")))])
	check(mm.covered > 0.9 and mm.mix_rms_db > -40.0 and mm.mix_rms_db < -12.0 and mm.music_rms_db > -45.0,
		"the menu music plays: RMS %.1f dBFS, %.0f%% of the time has sound" % [mm.mix_rms_db, mm.covered * 100.0])
	check(mm.mix_peak < 0.95, "the menu: no clipping (peak %.3f)" % mm.mix_peak)
	var n0 := a.total
	await key(KEY_C)
	await frames(3)
	check(_sounds_since(n0).has("ui_move"), "a car change on the menu clicks (ui_move)")
	# ---- Settings: the Audio rows (two columns at 1280 x 720), the sliders with the keys
	var menu: MainMenu = app.ui.menu
	var st: SettingsScreen = menu.settings
	n0 = a.total
	await key(KEY_O)
	await frames(4)
	check(st.is_open and _sounds_since(n0).has("ui_confirm"), "O opens Settings (ui_confirm)")
	var win := Vector2(root.size)
	var bar := (st.get("_scroll") as ScrollContainer).get_v_scroll_bar()
	var inside := true
	for r: Dictionary in st.get("_rows"):
		var rr := (r.box as Control).get_global_rect()
		inside = inside and rr.position.y >= 0.0 and rr.end.y <= win.y + 0.5 and rr.position.x >= 0.0 and rr.end.x <= win.x + 0.5
	if win.x >= 1280.0 and win.y >= 720.0:
		check(st.two_columns == (win.x >= SettingsScreen.TWO_COLUMNS) and inside and bar.max_value <= bar.page + 0.5,
			"%dx%d: Settings in %s, every row on screen, no scrolling" % [win.x, win.y, "two columns" if st.two_columns else "one column"])
	else: # (a small window, e.g. a quicker Movie Maker run: Settings may scroll there)
		print("AUDIO %dx%d: Settings in %s, %s" % [win.x, win.y, "two columns" if st.two_columns else "one column",
			"no scrolling" if bar.max_value <= bar.page + 0.5 else "scrolls %d px" % int(bar.max_value - bar.page)])
	var rows: Array = st.get("_rows")
	var at_master := -1
	for i in rows.size():
		if str(rows[i].def.key) == "vol_master":
			at_master = i
	while st.selected_row != at_master:
		await key(KEY_DOWN)
	n0 = a.total
	var v_master := float(UiData.get_setting("vol_master"))
	await key(KEY_LEFT)
	await frames(2)
	var mi := AudioServer.get_bus_index("Master")
	var v1 := float(UiData.get_setting("vol_master"))
	check(is_equal_approx(v1, v_master - 0.1) and is_equal_approx(AudioServer.get_bus_volume_db(mi), GameAudio.volume_db(v1))
		and _sounds_since(n0).has("ui_move"), "left on Master volume: %d%% -> %d%% (Master bus %.1f dB), a click at the new level" % [
		roundi(v_master * 100.0), roundi(v1 * 100.0), AudioServer.get_bus_volume_db(mi)])
	await key(KEY_RIGHT)
	check(is_equal_approx(float(UiData.get_setting("vol_master")), v_master), "right: back to %d%%" % roundi(v_master * 100.0))
	await key(KEY_DOWN) # Music
	var v_music := float(UiData.get_setting("vol_music"))
	var steps := roundi(v_music * 10.0)
	for i in steps + 1: # (the last one stays at Off)
		await key(KEY_LEFT)
	_audio_part("music_off")
	await game_seconds(0.8)
	var off_stats := _audio_stats("music_off", 0.4)
	check(float(UiData.get_setting("vol_music")) == 0.0 and AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")) and off_stats.mix_rms_db < -60.0,
		"Music down to Off: the Music bus is muted, the mix is silent (%.0f dBFS)" % off_stats.mix_rms_db)
	for i in steps:
		await key(KEY_RIGHT)
	check(is_equal_approx(float(UiData.get_setting("vol_music")), v_music), "and back up to %d%% with the keys" % roundi(v_music * 100.0))
	await frames(30)
	await shot("audio_settings")
	# the window to the background: everything is muted; back to the front: heard again
	_audio_part("background")
	root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await game_seconds(0.5)
	var bg_peak: float = _audio_stats("background", 0.3).out_peak_db
	var muted := AudioServer.is_bus_mute(mi) and a.muted_in_background()
	root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	_audio_part("foreground")
	await game_seconds(0.5)
	var fg_peak: float = _audio_stats("foreground", 0.3).out_peak_db
	check(muted and bg_peak < -100.0 and fg_peak > -40.0 and not AudioServer.is_bus_mute(mi),
		"in the background the output is silent (peak %.0f dB), in front it plays again (peak %.1f dB)" % [bg_peak, fg_peak])
	n0 = a.total
	await key(KEY_ESCAPE)
	check(not st.is_open and _sounds_since(n0).has("ui_back"), "Esc closes Settings (ui_back)")
	# ---- race 1: Seaside Stunts with the Drifter (turbo four): countdown, jumps, checkpoints, finish
	await _audio_race(str(opts.get("race1", "seaside-stunts")), str(opts.get("car1", "drifter")), "race1", true)
	# ---- race 2: Mountain Pass with the Dune: gravel and snow
	await _audio_race(str(opts.get("race2", "mountain-pass")), str(opts.get("car2", "dune")), "race2", true)
	# ---- a wall: Rookie Oval with the Thunder, full throttle and full lock into the barrier
	await _audio_wall(str(opts.get("car3", "thunder")))
	# ---- the AI opponent's car: positional
	await _audio_ai()
	# back on the menu: the menu music again, no car sounds
	await game_seconds(2.0)
	check(app.mode == app.menu_mode and a.music_name == "menu", "back on the menu: its music again (%s, %s)" % [app.mode.name if app.mode != null else "-", a.music_name])
	_write_audio_log(out.path_join("audio_frames.csv"), out.path_join("audio_events.csv"))
	for t: Tap in taps.values():
		t.remove()
	for k in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, k) == rec:
			AudioServer.remove_bus_effect(0, k)
			break
	probe.queue_free()


## Wait `s` seconds of game time (Movie Maker: exactly s × fps frames).
func game_seconds(s: float) -> void:
	var t := 0.0
	while t < s:
		await process_frame
		t += app.get_process_delta_time()


func _audio_part(nm: String) -> void:
	var parts: Dictionary = _au.parts
	parts[nm] = (_au.rows as Array).size()
	_au.part = parts.size()


## The sound names played since app.audio.total was `n0`.
func _sounds_since(n0: int) -> PackedStringArray:
	return app.audio.sounds_since(n0)


## One frame of the log (Probe.on_frame).
func _audio_log() -> void:
	var t: Dictionary = _au.taps
	var f := Engine.get_process_frames()
	var m: Node = app.mode
	var car: Car = m.get("car") if m != null and m != app.menu_mode and m.get("car") is Car else null
	var ca: CarAudio = m.get("car_audio") if car != null and m.get("car_audio") is CarAudio else null
	var loose := CarAudio.loose_at(m.get("track"), car.idx) if car != null else Vector2.ZERO
	var race: RaceState = m.get("race") if car != null and m.get("race") is RaceState else null
	var lv: Dictionary = ca.levels if ca != null else {}
	var ph := ["countdown", "race", "finished"].find(str(m.get("phase"))) if car != null else -1
	var out_db := maxf(AudioServer.get_bus_peak_volume_left_db(0, 0), AudioServer.get_bus_peak_volume_right_db(0, 0))
	# the clocks: game time (what the modes step: the frame's delta, capped as the app caps it) and
	# audio time (Movie Maker: the frames at 60 fps; real time: the wall clock the driver mixes by)
	_au.t_game = float(_au.t_game) + minf(app.get_process_delta_time(), app.max_frame)
	var t_audio: float = (f - int(_au.f0)) / 60.0 if bool(_au.lockstep) else (Time.get_ticks_usec() - int(_au.w0)) / 1e6
	(_au.rows as Array).append(PackedFloat32Array([f, _au.part, ph,
		ca.engine.rpm if ca != null else 0.0, car.gear if car != null else 0, car.speed if car != null else 0.0, car.slip if car != null else 0.0,
		loose.x, loose.y, race.splits.size() if race != null else 0, car.wall_hits if car != null else 0,
		(t.mix as Tap).rms, (t.mix as Tap).peak, (t.pre as Tap).peak, out_db, (t.engine as Tap).rms, (t.sfx as Tap).rms, (t.music as Tap).rms,
		(t.engine as Tap).samples.size(),
		lv.get("gravel", 0.0), lv.get("snow", 0.0), lv.get("tyre_squeal", 0.0), lv.get("wind", 0.0), lv.get("scrape", 0.0), lv.get("nitro", 0.0),
		car.boost if car != null else 0.0, 1.0 if ca != null and ca.engine.limiter else 0.0, app.audio.music_volume_db(),
		_au.t_game, t_audio, ca.engine.spool if ca != null else 0.0]))
	# the sounds played since the last frame
	var h: Array = app.audio.history
	var seen: int = _au.seen
	var new: Array = []
	for i in range(h.size() - 1, -1, -1):
		if int(h[i][3]) <= seen:
			break
		new.push_front([int(h[i][3]), str(h[i][0])])
	(_au.events as Array).append_array(new)
	_au.seen = f


## Levels over part `nm` (from where it began, or its last `last_s` seconds): RMS in dBFS of the mix
## (Master before its volume), Music, SFX and Engine; the peaks; how much of the time had sound.
func _audio_stats(nm: String, last_s: float = -1.0, to: int = -1) -> Dictionary:
	var rows: Array = _au.rows
	var a: int = int((_au.parts as Dictionary).get(nm, 0))
	var b := rows.size() if to < 0 else to
	if last_s > 0.0 and b > 0:
		var t_end: float = rows[b - 1][COL_T_AUDIO]
		while a < b - 1 and float(rows[a][COL_T_AUDIO]) < t_end - last_s:
			a += 1
	var s := {"mix": 0.0, "music": 0.0, "sfx": 0.0, "engine": 0.0}
	var col := {"mix": 11, "music": 17, "sfx": 16, "engine": 15}
	var peak := 0.0
	var pre := 0.0
	var out_peak := -400.0
	var with_sound := 0
	for i in range(a, b):
		var r: PackedFloat32Array = rows[i]
		for k: String in s:
			s[k] += r[col[k]] * r[col[k]]
		peak = maxf(peak, r[12])
		pre = maxf(pre, r[13])
		out_peak = maxf(out_peak, r[14])
		if r[12] > 0.0005:
			with_sound += 1
	var n := maxi(1, b - a)
	var db := func(x: float) -> float: return linear_to_db(maxf(1e-10, sqrt(x / n)))
	return {"mix_rms_db": db.call(s.mix), "music_rms_db": db.call(s.music), "sfx_rms_db": db.call(s.sfx), "engine_rms_db": db.call(s.engine),
		"mix_peak": peak, "mix_peak_db": linear_to_db(maxf(1e-10, peak)), "pre_peak": pre, "out_peak_db": out_peak, "covered": float(with_sound) / n, "frames": n}


func _save_clip(rec: AudioEffectRecord, path: String) -> void:
	var w := rec.get_recording()
	if w != null:
		w.save_to_wav(path)
		print("clip ", path, " %.1f s" % w.get_length())


## A race with the medal autopilot of the author run, logged; checks what was heard.
func _audio_race(tid: String, cid: String, tag: String, finish: bool) -> void:
	var a: GameAudio = app.audio
	var taps: Dictionary = _au.taps
	var eng: Tap = taps.engine
	await pick(tid, cid)
	var medals := Medals.medal_times(Tracks.build(tid), cid)
	var run: Dictionary = medals.get("run", {"aLat": 24.0, "lookK": 1.0})
	eng.samples = PackedFloat32Array()
	eng.keep = true
	_audio_part(tag)
	var e0 := (_au.events as Array).size()
	var rec := AudioEffectRecord.new()
	rec.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(0, rec, -1)
	rec.set_recording_active(true)
	await key(KEY_ENTER)
	var m: Node = app.mode
	if not check(m != app.menu_mode and str(m.get("car_def").id) == cid, "%s: Enter drives %s on %s" % [tag, cid, tid]):
		return
	var ca: CarAudio = m.get("car_audio")
	check(ca != null and ca.engine.car_id == cid and not ca.positional, "%s: the car's sound (%s, %s)" % [tag, cid, ca.engine.character.get("name", "?") if ca != null else "-"])
	var theme := (m.get("track") as BuiltTrack).theme
	check(a.music_name == SoundBank.race_music(theme), "%s: the race music for the %s theme (%s)" % [tag, theme, a.music_name])
	# the countdown: hold the throttle (a free rev), then let go
	app.input.held["accelerate"] = true
	await game_seconds(1.2)
	var rev_rpm := ca.engine.rpm
	app.input.held.erase("accelerate")
	check(rev_rpm > (m.get("car") as Car).spec.idle_rpm + 1500.0,
		"%s: the throttle on the grid revs the engine (%d rpm, idle %d)" % [tag, rev_rpm, (m.get("car") as Car).spec.idle_rpm])
	var skips0 := ca.skips()
	autopilot(float(run.aLat), float(run.lookK))
	# (the limit in game time: Movie Maker runs at a few frames a second here, 1/60 s of game each)
	var race: RaceState = m.get("race")
	await wait_until(func() -> bool: return m.get("phase") == "finished" or race.time > 400.0, 6000.0)
	var done: bool = m.get("phase") == "finished"
	stop_autopilot()
	await game_seconds(3.5) # (the finish, the medal stinger, the music down)
	var dry := ca.skips() - skips0
	var lead := ca.queued()
	rec.set_recording_active(false)
	eng.keep = false
	var rows: Array = _au.rows
	var r0: int = int((_au.parts as Dictionary)[tag])
	var r1 := rows.size()
	_save_clip(rec, out_dir.path_join("%s_%s_%s.wav" % [tag, tid, cid]))
	for k in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, k) == rec:
			AudioServer.remove_bus_effect(0, k)
			break
	_save_f32(eng.samples, rate_half(), out_dir.path_join("%s_engine.wav" % tag))
	check(done, "%s: the autopilot finishes (%.1f s)" % [tag, race.time])
	# the sounds and the frames they fell on
	var ev: Array = (_au.events as Array).slice(e0)
	var first := {}
	var counts := {}
	for e: Array in ev:
		counts[e[1]] = int(counts.get(e[1], 0)) + 1
		if not first.has(e[1]):
			first[e[1]] = int(e[0])
	print("AUDIO %s sounds: %s" % [tag, counts])
	print("AUDIO %s car events: %s" % [tag, ca.events])
	# the game time of each frame (Movie Maker: 1/60 s a frame; real time: the frames' deltas)
	var tg := {}
	var frame_dt := PackedFloat32Array()
	for i in range(r0, r1):
		tg[int(rows[i][0])] = float(rows[i][COL_T_GAME])
		if i > r0:
			frame_dt.append(float(rows[i][COL_T_AUDIO]) - float(rows[i - 1][COL_T_AUDIO]))
	frame_dt.sort()
	var med_dt: float = frame_dt[frame_dt.size() / 2] if frame_dt.size() > 0 else 1.0
	# the engine is fed a frame ahead (CarAudio.LEAD_MAX): at fewer than ~10 fps it runs dry between
	# frames, so its pitch and the turbo are measured only when the frames keep up (Movie Maker always)
	var smooth := bool(_au.lockstep) or med_dt <= 1.0 / 30.0
	var slack := 1.0 / 60.0 + 0.002 if bool(_au.lockstep) else app.max_frame + 0.002
	print("AUDIO %s: %d frames, median %.1f ms of audio a frame%s" % [tag, r1 - r0, med_dt * 1000.0, " (Movie Maker)" if bool(_au.lockstep) else ""])
	# countdown: 3, 2, 1 a second apart, GO a second after the 1
	var beeps: Array = ev.filter(func(e: Array) -> bool: return e[1] == "count" or e[1] == "go")
	var spaced := beeps.size() == 4 and str(beeps[3][1]) == "go"
	var gaps := []
	for i in range(1, beeps.size()):
		var d: float = float(tg.get(int(beeps[i][0]), 0.0)) - float(tg.get(int(beeps[i - 1][0]), 0.0))
		gaps.append(snappedf(d, 0.001))
		spaced = spaced and absf(d - 1.0) <= slack
	check(spaced, "%s: countdown 3, 2, 1, GO: %d beeps, %s s apart" % [tag, beeps.size(), gaps])
	# gates: a chime in the frame each split was taken
	var gate_frames := []
	for i in range(r0 + 1, r1):
		if rows[i][9] > rows[i - 1][9]:
			gate_frames.append(int(rows[i][0]))
	var chimes: Array = ev.filter(func(e: Array) -> bool: return e[1] in ["checkpoint", "lap", "finish"])
	var on_time := 0
	for g: int in gate_frames:
		for c: Array in chimes:
			if absi(int(c[0]) - g) <= 1:
				on_time += 1
				break
	check(gate_frames.size() == race.splits.size() and on_time == gate_frames.size(),
		"%s: every checkpoint, lap and the finish chimes in the frame it is taken (%d of %d)" % [tag, on_time, gate_frames.size()])
	# heard: the SFX bus rises right after each cue (the 5 frames after against the 8 before)
	var rises := _rises(ev, ["count", "go", "checkpoint", "lap", "finish", "medal", "best"], r0, r1)
	print("AUDIO %s cue onsets (dB rise of the SFX bus in the 83 ms after): %s" % [tag, rises])
	var heard := 0
	var total := 0
	for k: String in rises:
		for d: float in rises[k]:
			total += 1
			if d >= 3.0:
				heard += 1
	check(total > 0 and heard >= int(ceil(total * 0.8)), "%s: the cues are heard when they play (%d of %d raise the SFX bus 3 dB or more)" % [tag, heard, total])
	# the finish: the music goes down, the stinger after it
	var fs: Dictionary = m.get("finish_state")
	if done:
		var fin := int(first.get("finish", -1))
		var sting := "medal" if bool(fs.get("medal", {}).get("new", false)) else ("best" if fs.has("record") else "")
		var after: float = float(tg.get(int(first.get(sting, -1)), -9.0)) - float(tg.get(fin, 0.0)) if sting != "" else PlayMode.STINGER_AT
		var duck_ok := float(rows[r1 - 1][27]) < PlayMode.MUSIC_DB - 6.0
		check(fin > 0 and absf(after - PlayMode.STINGER_AT) <= slack and duck_ok,
			"%s: finish, then the %s stinger %.3f s later; the music down to %.1f dB" % [tag, sting, after, rows[r1 - 1][27]])
	var st := _audio_stats(tag, -1.0, r1)
	var lim_frames := 0
	for i in range(r0, r1):
		if rows[i][13] > db_to_linear(GameAudio.LIMIT_DB):
			lim_frames += 1
	print("AUDIO %s levels: mix RMS %.1f dBFS (heard %.1f), engine %.1f, SFX %.1f, music %.1f; peak %.3f after the limiter, %.3f before (the limiter works in %.1f%% of the frames)" % [
		tag, st.mix_rms_db, st.mix_rms_db + GameAudio.volume_db(float(UiData.get_setting("vol_master"))), st.engine_rms_db, st.sfx_rms_db, st.music_rms_db,
		st.mix_peak, st.pre_peak, 100.0 * lim_frames / maxf(1, r1 - r0)])
	check(st.covered > 0.98 and st.mix_rms_db > -32.0 and st.mix_rms_db < -8.0, "%s: not silent, sane level (mix RMS %.1f dBFS)" % [tag, st.mix_rms_db])
	check(st.mix_peak <= db_to_linear(GameAudio.LIMIT_DB) + 0.01, "%s: no clipping (peak %.3f, the limiter's ceiling %.3f)" % [tag, st.mix_peak, db_to_linear(GameAudio.LIMIT_DB)])
	# the engine's pitch follows the rpm
	print("AUDIO %s engine buffer: %.0f ms rendered ahead at the end, ran dry %d times in the race" % [tag, lead * 1000.0, dry])
	if smooth:
		check(dry == 0 and lead <= CarAudio.LEAD_MAX, "%s: the engine never runs dry and is rendered %.0f ms ahead" % [tag, lead * 1000.0])
	var pt := _pitch_track(eng.samples, rows, r0, r1, int(ca.engine.character.cylinders))
	print("AUDIO %s engine pitch: %d windows, lag %d frames: firing frequency %.1f dB above its neighbours (median); %.0f%% of windows >= 6 dB, %.0f%% of the %d windows just after a gear change; %d upshifts, the pitch drops at %d" % [
		tag, pt.windows, pt.lag, pt.median_db, pt.share * 100.0, pt.shift_share * 100.0, pt.shift_windows, pt.upshifts, pt.drops])
	if smooth:
		check(pt.windows > 50 and pt.share >= 0.8, "%s: the engine sounds at the firing frequency of the sim's rpm (%.0f%% of %d windows)" % [tag, pt.share * 100.0, pt.windows])
		check(pt.upshifts == 0 or (pt.shift_share >= 0.7 and pt.drops >= int(ceil(pt.upshifts * 0.7))),
			"%s: through the gear changes too (%d upshifts, the pitch drops at %d)" % [tag, pt.upshifts, pt.drops])
	else:
		print("AUDIO %s: the engine's pitch is not checked: %.0f ms frames (run it under Movie Maker)" % [tag, med_dt * 1000.0])
	# the ground under the car
	var on_dirt := [0, 0.0]
	var on_snow := [0, 0.0]
	var on_road := [0, 0.0, 0.0]
	for i in range(r0, r1):
		var r: PackedFloat32Array = rows[i]
		if r[2] != 1.0 or r[5] < 15.0:
			continue
		if r[7] > 0.9:
			on_dirt[0] += 1
			on_dirt[1] += r[19]
		elif r[8] > 0.9:
			on_snow[0] += 1
			on_snow[1] += r[20]
		elif r[7] + r[8] < 0.05:
			on_road[0] += 1
			on_road[1] += r[19]
			on_road[2] += r[20]
	if on_dirt[0] > 0 or on_snow[0] > 0:
		print("AUDIO %s ground: dirt %d frames (gravel %.2f), snow %d frames (snow %.2f), asphalt %d frames (gravel %.3f, snow %.3f)" % [
			tag, on_dirt[0], on_dirt[1] / maxf(1, on_dirt[0]), on_snow[0], on_snow[1] / maxf(1, on_snow[0]), on_road[0],
			on_road[1] / maxf(1, on_road[0]), on_road[2] / maxf(1, on_road[0])])
		check((on_dirt[0] == 0 or on_dirt[1] / on_dirt[0] > 0.25) and (on_snow[0] == 0 or on_snow[1] / on_snow[0] > 0.25)
			and on_road[1] / maxf(1, on_road[0]) < 0.02 and on_road[2] / maxf(1, on_road[0]) < 0.02,
			"%s: gravel crunch on the dirt, snow on the snow, neither on asphalt" % tag)
	if int(ca.events.get("land", 0)) > 0 or tid == "seaside-stunts":
		check(int(ca.events.get("land", 0)) > 0 and int(counts.get("land", 0)) > 0, "%s: landings thump (%d)" % [tag, int(ca.events.get("land", 0))])
	if float(ca.engine.character.get("turbo", 0.0)) > 0.0:
		var spool := 0.0
		for i in range(r0, r1):
			spool = maxf(spool, rows[i][COL_SPOOL])
		print("AUDIO %s turbo: spool up to %.2f, %d blow-offs" % [tag, spool, int(counts.get("blowoff", 0))])
		if smooth:
			check(int(counts.get("blowoff", 0)) > 0, "%s: the turbo blows off on a lift (%d, spool up to %.2f)" % [tag, int(counts.get("blowoff", 0)), spool])
	var boosted := 0
	var nitro_lvl := 0.0
	for i in range(r0, r1):
		if rows[i][26] > 0.3:
			boosted += 1
		nitro_lvl = maxf(nitro_lvl, rows[i][25])
	if boosted > 0:
		check(int(counts.get("nitro_on", 0)) > 0 and nitro_lvl > 0.2, "%s: the nitro lights (%d) and rushes (loop up to %.2f)" % [tag, int(counts.get("nitro_on", 0)), nitro_lvl])
	var wind := 0.0
	for i in range(r0, r1):
		wind = maxf(wind, rows[i][22])
	check(wind > 0.2, "%s: wind with speed (up to %.2f)" % [tag, wind])
	var ep: Node = ca.get("_engine_player")
	await key(KEY_ESCAPE)
	_audio_part(tag + "_menu")
	await game_seconds(0.5)
	var after := _audio_stats(tag + "_menu", 0.3)
	check(app.mode == app.menu_mode and (not is_instance_valid(ep) or not bool(ep.get("playing"))) and after.engine_rms_db < -80.0 and a.music_name == "menu",
		"%s: Esc to the menu: the engine stops (%.0f dBFS), the menu music comes back" % [tag, after.engine_rms_db])


func rate_half() -> float:
	return AudioServer.get_mix_rate() * 0.5


## Save mono float samples as a 32-bit float WAV (the analysis reads it).
func _save_f32(buf: PackedFloat32Array, rate: float, path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	var data := buf.to_byte_array()
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + data.size())
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(3) # IEEE float
	f.store_16(1)
	f.store_32(int(rate))
	f.store_32(int(rate) * 4)
	f.store_16(4)
	f.store_16(32)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(data.size())
	f.store_buffer(data)
	f.close()
	print("engine audio ", path, " %.1f s" % (buf.size() / rate))


## The rise of the SFX bus (dB) right after each sound named in `names`: the loudest of the 5
## frames after it against the RMS of the 8 frames before.
func _rises(ev: Array, names: Array, r0: int, r1: int) -> Dictionary:
	var rows: Array = _au.rows
	var at := {}
	for i in range(r0, r1):
		at[int(rows[i][0])] = i
	var out := {}
	for e: Array in ev:
		if not (e[1] in names) or not at.has(int(e[0])):
			continue
		var i: int = at[int(e[0])]
		if i - 8 < r0 or i + 6 > r1:
			continue
		var before := 0.0
		for k in range(i - 8, i):
			before += rows[k][16] * rows[k][16]
		before = sqrt(before / 8.0)
		var after := 0.0
		for k in range(i + 1, i + 6):
			after = maxf(after, rows[k][16])
		if not out.has(e[1]):
			out[e[1]] = []
		(out[e[1]] as Array).append(snappedf(linear_to_db(maxf(after, 1e-9)) - linear_to_db(maxf(before, 1e-9)), 0.1))
	return out


## Goertzel power of `n` samples of `s` from `a` (Hann window) at `f` Hz (`rate`).
static func _goertzel(s: PackedFloat32Array, a: int, n: int, f: float, rate: float) -> float:
	var w := TAU * f / rate
	var c := 2.0 * cos(w)
	var s1 := 0.0
	var s2 := 0.0
	var k := TAU / (n - 1)
	for i in n:
		var s0 := s[a + i] * (0.5 - 0.5 * cos(k * i)) + c * s1 - s2
		s2 = s1
		s1 = s0
	return s1 * s1 + s2 * s2 - c * s1 * s2


## Does the engine's sound follow the sim's rpm? Every 0.25 s of driving, a window of the Engine bus
## (85-170 ms) is measured at the firing frequency of the rpm logged `lag` frames earlier
## (EngineVoice.firing_hz) and 2.5 semitones either side; the firing frequency should stand out.
## The lag (the generator's lead and the mix) is the one that fits best over the first windows.
## Upshifts: the pitch 0.15 s before against 0.25 s after (it should drop).
func _pitch_track(s: PackedFloat32Array, rows: Array, r0: int, r1: int, cyl: int) -> Dictionary:
	var rate := rate_half()
	var cand := []
	for i in range(r0 + 30, r1 - 30, 15):
		var r: PackedFloat32Array = rows[i]
		if r[2] == 1.0 and r[3] > 1500.0:
			cand.append(i)
	var shift_rows := {}
	var upshifts := []
	for i in range(r0 + 1, r1):
		if rows[i][2] == 1.0 and rows[i][4] > rows[i - 1][4] and rows[i - 1][4] >= 1.0:
			upshifts.append(i)
			for k in range(i, mini(r1, i + 24)):
				shift_rows[k] = true
	var prom := func(i: int, lag: int) -> float:
		var rpm: float = rows[i - lag][3]
		var f0 := EngineVoice.firing_hz(cyl, rpm)
		var n := clampi(int(12.0 * rate / f0), 2048, 4096)
		var c := int(rows[i][18]) - n / 2
		if c < 0 or c + n >= s.size():
			return -999.0
		var p0 := _goertzel(s, c, n, f0, rate)
		var pl := _goertzel(s, c, n, f0 * pow(2.0, -2.5 / 12.0), rate)
		var ph := _goertzel(s, c, n, f0 * pow(2.0, 2.5 / 12.0), rate)
		return 10.0 * log(maxf(p0, 1e-20) / maxf(0.5 * (pl + ph), 1e-20)) / log(10.0)
	var best_lag := 4
	var best := -1e9
	for lag: int in range(1, 11):
		var sum := 0.0
		var cnt := 0
		for j in range(0, mini(cand.size(), 60)):
			var v: float = prom.call(cand[j], lag)
			if v > -900.0:
				sum += v
				cnt += 1
		if cnt > 0 and sum / cnt > best:
			best = sum / cnt
			best_lag = lag
	var vals := PackedFloat32Array()
	var good := 0
	var sw := 0
	var sgood := 0
	for i: int in cand:
		var v: float = prom.call(i, best_lag)
		if v < -900.0:
			continue
		vals.append(v)
		if v >= 6.0:
			good += 1
		if shift_rows.has(i):
			sw += 1
			if v >= 6.0:
				sgood += 1
	# the windows right after the upshifts (every one, not only those on the 0.25 s grid)
	var drops := 0
	for i: int in upshifts:
		var before := _peak_hz(s, rows, i - 9, best_lag, cyl, rate)
		var after := _peak_hz(s, rows, i + 15, best_lag, cyl, rate)
		if before > 0.0 and after > 0.0 and after < before * 0.95:
			drops += 1
		var v: float = prom.call(mini(i + 15, r1 - 31), best_lag)
		if v > -900.0:
			sw += 1
			if v >= 6.0:
				sgood += 1
	vals.sort()
	return {"windows": vals.size(), "lag": best_lag, "median_db": vals[vals.size() / 2] if vals.size() > 0 else 0.0,
		"share": float(good) / maxf(1, vals.size()), "shift_windows": sw, "shift_share": float(sgood) / maxf(1, sw),
		"upshifts": upshifts.size(), "drops": drops}


## The strongest frequency near the firing frequency of row `i` (± 40 %, 1/4-semitone steps), Hz.
func _peak_hz(s: PackedFloat32Array, rows: Array, i: int, lag: int, cyl: int, rate: float) -> float:
	if i - lag < 0 or i >= rows.size():
		return -1.0
	var f0 := EngineVoice.firing_hz(cyl, rows[i - lag][3])
	var n := 4096
	var c := int(rows[i][18]) - n / 2
	if c < 0 or c + n >= s.size() or f0 < 20.0:
		return -1.0
	var best := 0.0
	var at := -1.0
	for k in range(-24, 25):
		var f := f0 * pow(2.0, k / 48.0)
		var p := _goertzel(s, c, n, f, rate)
		if p > best:
			best = p
			at = f
	return at


## Full throttle down the straight into the first corner's barrier: the hit is heard when it happens.
func _audio_wall(cid: String) -> void:
	await pick("rookie-oval", cid)
	_audio_part("wall")
	var e0 := (_au.events as Array).size()
	await key(KEY_ENTER)
	var m: Node = app.mode
	var ca: CarAudio = m.get("car_audio")
	var car: Car = m.get("car")
	await wait_until(func() -> bool: return m.get("phase") == "race", 30.0)
	var inp := app.input
	inp.feed = func(_sp: float) -> void:
		inp.pad_throttle = 1.0
		inp.pad_steer = 0.0
	var hit := await wait_until(func() -> bool: return car.wall_hits > 0, 120.0)
	await game_seconds(2.0)
	stop_autopilot()
	var rows: Array = _au.rows
	var r0: int = int((_au.parts as Dictionary).wall)
	var r1 := rows.size()
	var first := -1
	var speed := 0.0
	for i in range(r0 + 1, r1):
		if rows[i][10] > rows[i - 1][10]:
			first = int(rows[i][0])
			speed = rows[i - 1][5]
			break
	var ev: Array = (_au.events as Array).slice(e0)
	var hits: Array = ev.filter(func(e: Array) -> bool: return str(e[1]).begins_with("hit_"))
	var rises := _rises(ev, ["hit_light", "hit_medium", "hit_heavy"], r0, r1)
	var scrape := 0.0
	for i in range(r0, r1):
		scrape = maxf(scrape, rows[i][23])
	print("AUDIO wall: first contact frame %d at %.1f m/s; hits %s; SFX rise %s dB; car events %s; scrape loop up to %.2f" % [
		first, speed, hits, rises, ca.events, scrape])
	check(hit and hits.size() > 0 and absi(int(hits[0][0]) - first) <= 1,
		"the %s into the wall at %.0f m/s: %s in the frame it hits (frame %d, the contact %d)" % [cid, speed, hits[0][1] if hits.size() > 0 else "no hit sound", int(hits[0][0]) if hits.size() > 0 else -1, first])
	var rose := false
	for k: String in rises:
		for d: float in rises[k]:
			rose = rose or d >= 3.0
	check(rose, "the hit is heard at once (the SFX bus up %s dB in the 83 ms after it)" % [rises])
	await key(KEY_ESCAPE)
	await frames(4)


## Race the AI ghost (the test network) for a few seconds: its car is a quieter positional sound.
func _audio_ai() -> void:
	var net_path := str(opts.get("net", "res://tests/fixtures/game_net.json"))
	await pick("rookie-oval", "racer")
	if not check(app.load_network_file(net_path) == "", "the AI network loaded"):
		return
	if app.message.visible: # (a note: the network was trained with another car)
		app.message.close()
		await frames(2)
	app.play("human", true)
	await frames(2)
	var m: Node = app.mode
	var ga: CarAudio = m.get("ghost_audio")
	autopilot(24.0, 1.3)
	await wait_until(func() -> bool: return m.get("phase") == "race", 30.0)
	await game_seconds(5.0)
	stop_autopilot()
	var ep: Node = ga.get("_engine_player") if ga != null else null
	check(ga != null and ga.positional and ep is AudioStreamPlayer3D and bool(ep.get("playing")) and ga.updates > 30 and is_equal_approx(ga.level, 0.6)
		and ga.get_parent() == m.get("ghost_model") and m.get("pb_model") == null,
		"Race the AI: the AI car's engine plays in 3D from its car (level %.1f, %d updates); no best-run ghost sound" % [ga.level if ga != null else 0.0, ga.updates if ga != null else 0])
	if ga != null:
		var d := (ga.global_position - (m.get("ghost_model") as Node3D).global_position).length()
		check(d < 0.01, "the AI car's sound is where its car is")
	await key(KEY_ESCAPE)
	await frames(4)


## The frame log (one row a frame, AU_COLS) and the sounds played (frame, name) as CSV.
func _write_audio_log(frames_path: String, events_path: String) -> void:
	var f := FileAccess.open(frames_path, FileAccess.WRITE)
	if f == null:
		return
	var parts := PackedStringArray()
	for k: String in _au.parts:
		parts.append("%s=%d" % [k, int(_au.parts[k])])
	f.store_line("# parts (row index where each began): " + " ".join(parts))
	f.store_line(",".join(PackedStringArray(AU_COLS)))
	for r: PackedFloat32Array in _au.rows:
		var line := PackedStringArray()
		for v in r:
			line.append(str(snappedf(v, 0.00001)))
		f.store_line(",".join(line))
	f.close()
	var g := FileAccess.open(events_path, FileAccess.WRITE)
	if g == null:
		return
	g.store_line("frame,sound")
	for e: Array in _au.events:
		g.store_line("%d,%s" % [int(e[0]), e[1]])
	g.close()
	print("audio log %s (%d frames), %s (%d sounds)" % [frames_path, (_au.rows as Array).size(), events_path, (_au.events as Array).size()])
