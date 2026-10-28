class_name GameApp
extends Node
## app.gd (port of web/src/main.js): the game's shell, the script of main.tscn.
## ------------------------------------------------------------------
## Builds the tracks, the 3D world (one World for the whole session) and the interface
## (UiRoot: menu, HUD, Controls and Settings screens, pad notice) and runs a small state
## machine of modes, each a Node with enter() / update(dt) / exit():
##   menu       track select over a slow camera orbit of the selected track (modes/menu_mode.gd)
##   play       Drive / Race the AI ghost (modes/play_mode.gd)
##   watch      Watch the AI (modes/watch_mode.gd)
##   train      the AI training screen (modes/train_mode.gd, ai/; its session is kept between visits)
## Every frame: the input polls the pads first (GameInput, process_priority -100), then
## _process hands the frame time (at most 0.1 s) to the active mode, which steps its physics
## at a fixed 60 Hz and draws in between.
##
## Also here: the threaded track switch (World.build_track_node on a WorkerThreadPool task,
## so the menu orbit never hitches while a new track is built), the graphics quality (the
## "quality" setting: High = start high with the frame-time governor stepping down to medium
## and low when frames are slow, as the web game; Low = pinned low) and the display settings
## (fullscreen, vsync; the interface size is UiRoot's), the save data wiring (UiData reads
## sim/save.gd's file), the AI networks (one per car, from the save file; the menu's AI block,
## Watch the AI and Race the AI ghost use the picked car's; Load / Save network through file
## dialogs in the web game's JSON format), and short messages.
##
## Command line (after "--"; tools and the end-to-end tests): gfx=high|medium|low pins the
## quality (governor off), save=<path> uses another save file, track=<id> starts on that track.

const AiLink := preload("res://game/ai_link.gd")
const MenuMode := preload("res://modes/menu_mode.gd")
const PlayMode := preload("res://modes/play_mode.gd")
const WatchMode := preload("res://modes/watch_mode.gd")
const MessageScreen := preload("res://game/message_screen.gd")
const TRAIN_MODE_PATH := "res://modes/train_mode.gd"
const TITLE := "Track Rush"

var world: World
var ui: UiRoot
var input: GameInput
## The menu's orbit camera (each race brings its own chase camera).
var menu_camera: Camera3D
var tracks: Array[BuiltTrack] = []
var selected_track := 0
## The picked car's AI network (the menu's AI block, Watch the AI and Race the AI ghost):
## {net: NeuralNetwork, meta: the file's Dictionary}, or {} when that car has none yet.
var network: Dictionary = {}
## Every car's network, parsed from the save file when first asked: car id -> {net, meta} or {}.
var _networks: Dictionary = {}
var mode: Node = null
var menu_mode: Node
var train_mode: Node = null       # the last training screen made (a new one each visit)
var message: Control
var orbit_angle := 0.0
## Command-line options (see the header).
var options: Dictionary = {}
## Quality pinned from the command line ("" none).
var forced_quality := ""
## The longest frame the modes are handed (s): a slower frame runs the game slower instead of
## stepping the physics in big bursts (the end-to-end runs raise it with Engine.time_scale).
var max_frame := 0.1

var _build_task := -1
var _build_for: BuiltTrack = null
var _build_node: Node3D = null
var _want_track: BuiltTrack = null
var _dialog: FileDialog = null
var _dialog_open := false
## Training at Max: the 3D view isn't drawn (the root viewport's 3D is off) and its last
## frame stays under the training screen's Max overlay, as the web game's canvas does.
var _3d_paused := false
var _freeze_layer: CanvasLayer = null
var _freeze: TextureRect = null


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		options[kv[0]] = kv[1] if kv.size() > 1 else "1"
	get_window().title = TITLE
	if options.has("save"):
		SaveData.use_file(str(options.save))
	if ["high", "medium", "low"].has(str(options.get("gfx", ""))):
		forced_quality = str(options.gfx)

	input = GameInput.new()
	input.name = "GameInput"
	add_child(input)

	# the tracks (cached by sim/ Tracks) and the save data, before the interface reads them
	for id: String in Tracks.ids():
		tracks.append(Tracks.build(id))
	UiData.use_tracks(tracks)
	UiData.use_save_data(true)
	UiData.on_setting_changed = _on_setting_changed
	var start: int = Tracks.ids().find(str(options.get("track", "")))
	selected_track = maxi(0, start)
	_sync_network()

	# the 3D world and the menu camera
	world = World.new()
	add_child(world)
	menu_camera = Camera3D.new()
	menu_camera.name = "MenuCamera"
	menu_camera.fov = 60.0
	menu_camera.near = 0.3
	menu_camera.far = 4000.0
	world.add_child(menu_camera)
	_apply_quality()
	_apply_display()

	# the interface, reading keys and pads through the game's input
	ui = UiRoot.new()
	ui.remove_child(ui.input)
	ui.input.free()
	ui.input = input
	ui.menu.input = input
	input.notice = ui.notice.show_text
	add_child(ui)
	message = MessageScreen.new()
	ui.frame.add_child(message)
	message.closed.connect(_on_dialog_closed)
	ui.menu.select(selected_track)
	ui.menu.drive.connect(func() -> void: play("human", false))
	ui.menu.race_ghost.connect(func() -> void: play("human", true))
	ui.menu.watch_ai.connect(func() -> void: play("ai", false))
	ui.menu.train_ai.connect(train)
	ui.menu.load_network.connect(load_network_dialog)
	ui.menu.save_network.connect(save_network_dialog)
	ui.menu.track_selected.connect(func(i: int) -> void:
		selected_track = i
		if mode == menu_mode:
			show_track_async(tracks[i]))
	ui.menu.car_selected.connect(func(_id: String) -> void: _sync_network())

	world.show_track(tracks[selected_track])
	menu_mode = MenuMode.new()
	menu_mode.setup(self)
	add_child(menu_mode)
	show_menu()


func _process(delta: float) -> void:
	_poll_build()
	if message.visible:
		message.handle_keys(input)
	if mode != null:
		mode.update(minf(delta, max_frame))
	_sync_3d()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_finish_build_task()


# ---------------------------------------------------------------- modes

## Make `m` the active mode: the old one exits (and is freed, except the menu), the new one
## enters. Clicked buttons lose focus, so Space or Enter in a race never press one.
func set_mode(m: Node) -> void:
	get_viewport().gui_release_focus()
	var old := mode
	if old != null:
		old.exit()
	mode = m
	if m.get_parent() == null:
		add_child(m)
	ui.menu.show_menu(m == menu_mode)
	ui.hud.show_hud(m.get("uses_hud") == true) # (the race modes draw the HUD)
	m.enter()
	input.clear_pressed()
	if old != null and old != m and old != menu_mode:
		old.queue_free()
	_sync_3d()


## The training screen at Max shows its overlay (train_mode.gd: dash.overlay) and draws no
## 3D: stop rendering the 3D view then, keeping its last frame under the overlay.
func _sync_3d() -> void:
	var paused := false
	if mode != null and mode == train_mode:
		var dash: Variant = mode.get("dash")
		var ov: Variant = (dash as Object).get("overlay") if dash is Object and is_instance_valid(dash) else null
		paused = ov is CanvasItem and (ov as CanvasItem).is_visible_in_tree()
	if paused == _3d_paused:
		return
	_3d_paused = paused
	var vp := get_viewport()
	if paused:
		if _freeze == null:
			_freeze_layer = CanvasLayer.new()
			_freeze_layer.layer = -1 # (under the interface)
			add_child(_freeze_layer)
			_freeze = TextureRect.new()
			_freeze.set_anchors_preset(Control.PRESET_FULL_RECT)
			_freeze.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			_freeze.stretch_mode = TextureRect.STRETCH_SCALE
			_freeze.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_freeze_layer.add_child(_freeze)
		var img: Image = null
		if DisplayServer.get_name() != "headless":
			img = vp.get_texture().get_image() # (the last frame drawn, once)
		_freeze.texture = ImageTexture.create_from_image(img) if img != null and not img.is_empty() else null
		_freeze_layer.visible = true
	else:
		if _freeze_layer != null:
			_freeze_layer.visible = false
			_freeze.texture = null
	vp.disable_3d = paused


func show_menu() -> void:
	set_mode(menu_mode)


## Drive (driver "human"), Race the AI ghost (ghost) or Watch the AI (driver "ai") on the
## selected track. The AI is the picked car's network, driving that car.
func play(driver: String, ghost: bool) -> void:
	var car := UiData.picked_car()
	if driver == "ai" or ghost:
		if not AiLink.ready():
			show_message("AI not ready", AiLink.not_ready_text())
			return
		_sync_network()
		if network.is_empty():
			show_message("No AI network", "The %s has no trained AI network yet. Train the AI teaches one (it starts with the %s), or Load network… uses a saved file." % [
				Cars.get_car(car).name, Cars.get_car(car).name])
			return
	start_play({"track": tracks[selected_track], "driver": driver, "ghost": ghost, "ai_car": car,
		"net": AiLink.clone_net(network.net) if not network.is_empty() else null})


## Start a race mode (opts: see modes/play_mode.gd; return_to: where Esc goes, default the
## menu; the training screen passes its own). Returns the mode.
func start_play(opts: Dictionary) -> Node:
	var m: Node = (WatchMode if str(opts.get("driver", "human")) == "ai" else PlayMode).new()
	m.setup(self, opts)
	set_mode(m)
	return m


## The AI training screen (modes/train_mode.gd). A new screen each visit: the training
## session itself (trainer, chart, speed, form) lives in train_mode.gd's static `session`, so
## it survives the menu, Watch best and Race best and resumes here.
func train() -> void:
	if not AiLink.ready() or not ResourceLoader.exists(TRAIN_MODE_PATH):
		show_message("AI not ready", AiLink.not_ready_text() if not AiLink.ready()
			else "The training screen (modes/train_mode.gd) is not part of this build yet.")
		return
	var s: Variant = load(TRAIN_MODE_PATH)
	if not (s is GDScript) or not (s as GDScript).can_instantiate():
		show_message("AI not ready", "The training screen failed to load.")
		return
	var m: Node = (s as GDScript).new()
	m.call("setup", self, {"track_index": selected_track, "car": UiData.picked_car()})
	m.connect("exit_requested", show_menu)
	m.connect("watch_requested", _on_train_play.bind("ai", false))
	m.connect("race_requested", _on_train_play.bind("human", true))
	m.connect("network_saved", _set_network)
	train_mode = m
	set_mode(m)


## Watch best / Race best on the training screen: the race goes back to training. The AI drives
## the session's car (car_id); racing it, the player drives the menu's car.
func _on_train_play(t: BuiltTrack, net: Object, car_id: String, driver: String, ghost: bool) -> void:
	start_play({"track": t, "driver": driver, "ghost": ghost, "net": AiLink.clone_net(net), "ai_car": car_id,
		"return_to": train})


# ---------------------------------------------------------------- the 3D track

## Show `t` now (a race needs it): waits for a build already running, else builds it here.
func show_track(t: BuiltTrack) -> void:
	_want_track = t
	if _build_task != -1:
		_finish_build_task()
	if world.track != t:
		world.show_track(t)


## Show `t` when it is built on a worker thread (the menu: the old track stays and the orbit
## goes on meanwhile). Asking again before it is done only changes which track comes next.
func show_track_async(t: BuiltTrack) -> void:
	_want_track = t
	if _build_task != -1 or world.track == t:
		return
	_build_for = t
	_build_task = WorkerThreadPool.add_task(_build_in_thread.bind(t), false, "Track Rush: build track")


func _build_in_thread(t: BuiltTrack) -> void:
	_build_node = World.build_track_node(t)


## True while a track is being built on a worker thread.
func building_track() -> bool:
	return _build_task != -1


func _poll_build() -> void:
	if _build_task != -1 and WorkerThreadPool.is_task_completed(_build_task):
		_finish_build_task()
		if _want_track != null and world.track != _want_track and mode == menu_mode:
			show_track_async(_want_track)


## Wait for the build task (if any) and show its track when it is still the one wanted.
func _finish_build_task() -> void:
	if _build_task == -1:
		return
	WorkerThreadPool.wait_for_task_completion(_build_task)
	_build_task = -1
	var node := _build_node
	_build_node = null
	if node == null:
		return
	if _build_for == _want_track and is_instance_valid(world):
		world.show_track(_build_for, node)
	else:
		node.free()


## Slow orbit around the shown track (the menu background).
func orbit(dt: float) -> void:
	if world.track == null:
		return
	orbit_angle += dt * 0.08
	ChaseCamera.orbit_pose(menu_camera, world.track, orbit_angle)


# ---------------------------------------------------------------- settings

func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "quality":
		_apply_quality()


## The graphics quality: the setting (High: the governor may step down; Low: pinned), or the
## command line's gfx= (pinned).
func _apply_quality() -> void:
	if forced_quality != "":
		world.auto_quality = false
		world.set_quality(forced_quality)
		return
	var q := str(UiData.get_setting("quality"))
	world.auto_quality = q != "low"
	world.set_quality("low" if q == "low" else "high")


## Fullscreen and vsync as saved (the Settings screen applies changes itself).
func _apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if bool(UiData.get_setting("fullscreen")):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(UiData.get_setting("vsync")) else DisplayServer.VSYNC_DISABLED)


# ---------------------------------------------------------------- the AI networks

## Car `car_id`'s AI network {net, meta}, or {} when it has none (parsed from the save file once).
func network_for(car_id: String) -> Dictionary:
	if not _networks.has(car_id):
		var parsed: Dictionary = {}
		var saved: Variant = SaveData.load_network(car_id)
		if saved != null and AiLink.ready():
			parsed = AiLink.parse_network_file(saved)
			if parsed.has("error"):
				push_warning("The %s's saved network could not be read: %s" % [car_id, parsed.error])
				parsed = {}
		_networks[car_id] = parsed
	return _networks[car_id]


## `network` and the menu's AI status follow the picked car.
func _sync_network() -> void:
	var car := UiData.picked_car()
	network = network_for(car)
	UiData.set_ai_status(AiLink.status_of(network, car))
	if ui != null:
		ui.menu.refresh()


## Car `car_id`'s network is now `parsed` ({net, meta} or {}; already in the save file, e.g. by
## the training screen). Default: the picked car's.
func _set_network(parsed: Dictionary, car_id: String = "") -> void:
	_networks[car_id if car_id != "" else UiData.picked_car()] = parsed
	_sync_network()


## A network chosen or trained elsewhere: car `car_id`'s network from now on (default: the
## picked car's), remembered in the save file. `data` is its file (the web format).
func adopt_network(parsed: Dictionary, data: Dictionary = {}, car_id: String = "") -> void:
	var car := car_id if car_id != "" else UiData.picked_car()
	_set_network(parsed, car)
	if not parsed.is_empty():
		SaveData.save_network(data if data.has("network") else AiLink.network_file(parsed.net, parsed.get("meta", {})), car)


## Load network… : a JSON file picked in a file dialog (the web game's format).
func load_network_dialog() -> void:
	if not AiLink.ready():
		show_message("AI not ready", AiLink.not_ready_text())
		return
	_open_dialog(FileDialog.FILE_MODE_OPEN_FILE, "Load network", "", load_network_file)


## Load the network file at `path` as the picked car's network. A network trained with another
## car is allowed: it drives the picked car from now on, and a message says so. Returns "" or
## the error shown to the player.
func load_network_file(path: String) -> String:
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var err := ""
	if text == "" or json.parse(text) != OK:
		err = "Not a network file"
	else:
		var parsed := AiLink.parse_network_file(json.data)
		if parsed.has("error"):
			err = str(parsed.error)
		else:
			var car := UiData.picked_car()
			adopt_network(parsed, json.data if json.data is Dictionary else {}, car)
			var trained := AiLink.network_car(parsed.get("meta", {}))
			if trained != car:
				show_message("Network loaded", other_car_note(trained, car))
	if err != "":
		show_message("Load network", "Could not load network: %s" % err)
	return err


## What to say about a network trained with car `trained` that now drives car `car`.
static func other_car_note(trained: String, car: String) -> String:
	var t: String = Cars.get_car(trained).name
	var c: String = Cars.get_car(car).name
	return "This network was trained with the %s. It is now the %s's AI network and drives the %s, a car it has not learned, so it may brake too early or too late and hit walls. To adapt it, train it with the %s (Train the AI, Continue from saved network)." % [
		t, c, c, c]


## Save network… : the loaded network as a JSON file (with its training info when it has it).
func save_network_dialog() -> void:
	if network.is_empty():
		return
	var data := network_file_data()
	_open_dialog(FileDialog.FILE_MODE_SAVE_FILE, "Save network", "ai-%s-gen%d.json" % [AiLink.network_car(data), int(data.get("generation", 0))],
		save_network_file)


## The loaded network's file: its own file when it has one, else a new one around the network.
func network_file_data() -> Dictionary:
	var meta: Dictionary = network.get("meta", {})
	return meta if meta.has("network") else AiLink.network_file(network.net)


## Write the loaded network to `path` (JSON, one-space indent like the web's download).
## Returns "" or the error.
func save_network_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		show_message("Save network", "Could not save the network to %s" % path)
		return "Could not write the file"
	f.store_string(JSON.stringify(network_file_data(), " "))
	f.close()
	return ""


func _open_dialog(file_mode: FileDialog.FileMode, title: String, file_name: String, done: Callable) -> void:
	if _dialog != null and is_instance_valid(_dialog):
		_dialog.queue_free()
	_dialog = FileDialog.new()
	_dialog.title = title
	_dialog.file_mode = file_mode
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.filters = PackedStringArray(["*.json ; Network files"])
	_dialog.use_native_dialog = true
	if file_name != "":
		_dialog.current_file = file_name
	_dialog.file_selected.connect(func(p: String) -> void:
		_dialog_open = false
		_on_dialog_closed()
		done.call(p))
	_dialog.canceled.connect(func() -> void:
		_dialog_open = false
		_on_dialog_closed())
	add_child(_dialog)
	_dialog_open = true
	ui.menu.input = null # (the menu ignores the keys typed into the dialog)
	_dialog.popup_file_dialog()


## A file dialog or the message closed: the menu reads the keys again once neither is open.
func _on_dialog_closed() -> void:
	if not message.visible and not _dialog_open:
		ui.menu.input = input
		input.clear_pressed()


## A short message over everything (the web's alert()).
func show_message(title: String, text: String) -> void:
	ui.menu.input = null
	message.show_message(title, text)
