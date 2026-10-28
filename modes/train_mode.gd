extends Node
## train_mode.gd (port of web/src/game/trainMode.js)
## ------------------------------------------------------------------
## The AI training screen: the 3D view of the whole population on the left, the dashboard
## (ui/train_dashboard.gd: settings, live network, stats, AI best times, fitness chart) on
## the right (the bottom half in narrow windows).
##
## Speeds:
##   1×    real time (fixed 60 Hz steps, the cars drawn between the last two steps)
##   Fast  six physics steps per drawn frame
##   Max   no 3D drawing: the session runs on a background thread (MaxRun below), so the
##         screen stays smooth; the dashboard follows it a few times a second. The trainer's
##         simulation is the native FleetSim (native/, several threads) when it is loaded,
##         else GDScript (much slower: the note line says so when training starts).
## Pause, another speed, a button that needs the session (Save, Watch, Race, Stop, Load) or
## leaving the screen takes the session back from the thread first: the thread stops after
## its current slice of steps (a few hundredths of a second) and the run carries on here from
## exactly where it was (the thread and the screen share one Trainer, never at the same time).
##
## Multi-track training: every car drives every ticked track in turn and its fitness is the
## average (ai/trainer.gd). Walls: "ride" (default) or "crash" (Trainer.WALL_RULES). The best
## network is saved (SaveData.save_network, the save file's "network") whenever it improves,
## and with Save best network, which also writes a copy as a file the browser version can load.
##
## The training session (its Trainer, the chart, the speed and camera, the form) survives
## Watch best / Race best / the menu and back: it lives in the static `session`, so a new
## TrainMode resumes it. It waits (no steps) while another screen is shown, like the web game.
##
## Mode protocol (as modes/play_mode.gd, game/app.gd):
##   var mode = preload("res://modes/train_mode.gd").new()
##   mode.setup(app, {track_index = <the menu's track>, network = <{net, meta} or {}>})
##   app.add_child(mode); mode.enter()     # then mode.update(dt) every frame
##   mode.exit()                           # when it is left (then free it, or keep it)
## app: `world` (World), `ui` (UiRoot: the dashboard goes into ui.frame, the HUD and the menu
## are hidden while it is shown), `input` (MenuInput: consume, nav_dir, clear_pressed,
## pad_active) and optionally show_track(track) (else world.show_track), selected_track and
## network (read on every enter(), else setup()'s opts are used). The mode makes its own
## ChaseCamera, AIFleet and SensorRays under app.world and frees them in exit().
## Signals for the app:
##   exit_requested                       Menu, Esc, pad B / Start: back to the menu
##   watch_requested(track, net)          Watch best: the AI drives `track` (modes/watch_mode.gd)
##   race_requested(track, net)           Race best (ghost): the player races the AI ghost
##   network_saved(network)               {net, meta}: the saved network changed (autosave, Save,
##                                        Load); already written with SaveData.save_network
## Uses the ai/ classes (Trainer...): load this script only when the AI scripts load (AiLink).

signal exit_requested
signal watch_requested(track: BuiltTrack, net: NeuralNetwork)
signal race_requested(track: BuiltTrack, net: NeuralNetwork)
signal network_saved(network: Dictionary)

const Dashboard := preload("res://ui/train_dashboard.gd")

const STEP := 1.0 / 60.0
const FAST_STEPS := 6
const FAST_BUDGET_USEC := 30000   # Fast on the GDScript path: at most this long stepping per frame
const STATS_EVERY := 0.2          # s between dashboard text updates (and Max snapshots)
const ORBIT_SPEED := 0.08         # rad/s, the setup screen's slow orbit (main.js orbit())
const CHASE_DISTANCE := 15.0      # further back and higher than in a race to see the cars around;
const CHASE_HEIGHT := 4.4         # low enough to pass under the gate beams (start gate 6.2 m, checkpoints 5.6 m)
const FILE_DIR := "user://networks"


## The training session, kept across visits (see the header).
class Session:
	var trainer: Trainer = null
	var speed := "1"             # "1" | "6" | "max"
	var paused := false
	var cam := "chase"           # "chase" | "overview"
	var selected := -1           # the clicked car (-1: follow the leader)
	var last_saved := -INF       # best fitness last autosaved
	var history: Array = []      # the chart's copy of trainer.history (the Max thread appends to the trainer's)
	var note := ""
	var list_for := -1           # the menu track the track ticks were last set for
	var form: Dictionary = {}    # the setup form's values while the screen is away


## Max speed: the session's Trainer stepped on a background thread. The thread owns the
## Trainer until finish() returns; it publishes a snapshot for the dashboard every
## STATS_EVERY seconds (a new Dictionary each time, never changed after it is published).
class MaxRun:
	var trainer: Trainer
	var thread := Thread.new()
	var mutex := Mutex.new()
	var stop := false
	var selected := -1
	var snapshot: Dictionary = {}
	var ended := false            # the thread returned (stopped, or failed)
	var _slice := 60              # steps per slice, adapted to take about SLICE_USEC
	const SLICE_USEC := 25000

	func _init(tr: Trainer, sel: int) -> void:
		trainer = tr
		selected = sel

	func start() -> void:
		thread.start(_loop)

	func _loop() -> void:
		var last_snap := 0
		while true:
			mutex.lock()
			var s := stop
			mutex.unlock()
			if s:
				break
			var t0 := Time.get_ticks_usec()
			trainer.step_many(_slice)
			var took := maxi(1, Time.get_ticks_usec() - t0)
			_slice = clampi(int(_slice * clampf(float(SLICE_USEC) / took, 0.5, 2.0)), 1, 20000)
			if Time.get_ticks_usec() - last_snap > int(STATS_EVERY * 1e6):
				last_snap = Time.get_ticks_usec()
				_snap()
		_snap()
		mutex.lock()
		ended = true
		mutex.unlock()

	## The dashboard's numbers and the shown car's network (copies: the thread goes on).
	func _snap() -> void:
		var tr := trainer
		tr.sync_agents()
		mutex.lock()
		var sel := selected
		mutex.unlock()
		var a: Trainer.Agent = tr.agents[sel] if sel >= 0 and sel < tr.agents.size() else tr.agents[tr.leader_index()]
		tr.sync_shown(a)
		var weights: Array = []
		var acts: Array = []
		for w in a.net.weights:
			weights.append(w.duplicate())
		for v in a.net.acts:
			acts.append(v.duplicate())
		var snap := {
			stats = tr.live_stats(),
			shown = TrainModeInfo.shown_info(a, sel),
			net = {sizes = Array(tr.sizes), weights = weights, acts = acts},
			steps = tr.steps_done(),
			usec = Time.get_ticks_usec(),
		}
		mutex.lock()
		snapshot = snap
		mutex.unlock()

	func get_snapshot() -> Dictionary:
		mutex.lock()
		var s := snapshot
		mutex.unlock()
		return s

	func set_selected(k: int) -> void:
		mutex.lock()
		selected = k
		mutex.unlock()

	## Stop the thread and wait for it (at most one slice). The Trainer is the caller's again.
	func finish() -> void:
		mutex.lock()
		stop = true
		mutex.unlock()
		if thread.is_started():
			thread.wait_to_finish()

	func is_ended() -> bool:
		mutex.lock()
		var e := ended
		mutex.unlock()
		return e


## What the dashboard says about the viewed car (plain data, also built on the Max thread).
class TrainModeInfo:
	static func shown_info(a: Trainer.Agent, selected: int) -> Dictionary:
		return {index = a.index, clicked = a.index == selected, alive = a.alive, death_reason = a.death_reason,
			fitness = a.fitness, speed = a.car.speed}


static var session: Session = null

var app: Object = null
var dash: Control = null
var camera: ChaseCamera = null
var rays: SensorRays = null
var fleet: AIFleet = null

var _network: Dictionary = {}    # the saved network {net, meta} ({} none): "Continue from saved network"
var _track_index := 0            # the menu's track
var _active := false
var _max: MaxRun = null
var _max_broken := false         # the Max thread failed: Max simulates on the main thread instead
var _events: Array = []          # from the Trainer's callbacks (main or Max thread): ["generation", ...] / ["track", t]
var _ev_mutex := Mutex.new()
var _pending_track: BuiltTrack = null
var _preview: BuiltTrack = null
var _orbit := 0.0
var _acc := 0.0
var _sim_rate := 0.0
var _stats_timer := 0.0
var _chart_dirty := true
var _chase_car: Object = null
var _last_steps := -1
var _last_usec := 0
var _file_dialog: FileDialog = null
## Where Save best network writes its file copy (tests point it elsewhere).
var file_dir := FILE_DIR


## Called by the app before the mode joins the tree. opts: track_index (the menu's track),
## network ({net, meta} of the saved network, or {}).
func setup(p_app: Object, opts: Dictionary = {}) -> void:
	app = p_app
	name = "TrainMode"
	_track_index = clampi(int(opts.get("track_index", 0)), 0, maxi(0, Tracks.ids().size() - 1))
	var n: Variant = opts.get("network", {})
	_network = n if n is Dictionary and (n as Dictionary).has("net") else {}
	if session == null:
		session = Session.new()


func enter() -> void:
	_active = true
	# the game's current menu track and network, when it has them (GameApp: selected_track,
	# network), else what setup() was given
	var sel: Variant = app.get("selected_track")
	if sel is int:
		_track_index = clampi(sel, 0, maxi(0, Tracks.ids().size() - 1))
	var net: Variant = app.get("network")
	if net is Dictionary:
		_network = net if (net as Dictionary).has("net") else {}
	var world: World = app.get("world")
	var ui: Object = app.get("ui")
	if ui != null:
		var hud: Object = ui.get("hud")
		if hud != null:
			hud.set("visible", false)
		var menu: Object = ui.get("menu")
		if menu != null and menu.has_method("show_menu"):
			menu.call("show_menu", false)
	dash = Dashboard.new()
	var frame: Control = ui.get("frame") if ui != null else null
	if frame != null:
		frame.add_child(dash)
	else:
		add_child(dash)
	dash.action.connect(_on_action)
	dash.settings_changed.connect(_on_settings_changed)
	camera = ChaseCamera.new()
	camera.name = "TrainCamera"
	camera.distance = CHASE_DISTANCE
	camera.height = CHASE_HEIGHT
	world.add_child(camera)
	camera.make_current()
	rays = SensorRays.new(PackedFloat32Array(Sensors.SENSOR_ANGLES))
	rays.visible = false
	world.add_child(rays)
	_restore_form()
	var s := session
	if s.trainer != null:
		_adopt(s.trainer)
		_show_run()
		_attach_track(s.trainer.track)
	else:
		_show_setup()
	dash.set_note(s.note)


func exit() -> void:
	_stop_max()
	_drain_events()
	_active = false
	var s := session
	if s.trainer != null:
		s.trainer.on_generation = Callable()
		s.trainer.on_track_change = Callable()
	if dash != null:
		s.form = _form_state()
		s.note = dash.note_label.text
		dash.clear_pad()
		dash.queue_free()
		dash = null
	for n: Node in [camera, rays, fleet]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	camera = null
	rays = null
	fleet = null
	if _file_dialog != null and is_instance_valid(_file_dialog):
		_file_dialog.queue_free()
	_file_dialog = null


func _exit_tree() -> void:
	_stop_max() # (never leave the thread running: the app may free the mode without exit())


# ================================================================= the setup form

func _show_setup() -> void:
	dash.show_setup()
	var s := session
	# A track picked on the menu since the last visit replaces the ticks (the player's own
	# multi-track choice is kept while the menu pick is unchanged).
	if s.list_for != _track_index:
		s.list_for = _track_index
		dash.tick_tracks([_track_index])
	dash.set_seed(not _network.is_empty(), "")
	dash.seed_check.checked = not _network.is_empty()
	_show_seed_info()
	_preview_track()


## What "Continue from saved network" continues from, with the wall rule it was trained with.
func _show_seed_info() -> void:
	if _network.is_empty():
		dash.set_seed_info("(none yet)")
		return
	var meta: Dictionary = _network.get("meta", {})
	var rule := Trainer.saved_wall_rule(meta)
	var chosen: String = dash.walls
	var gen: Variant = meta.get("generation")
	var fit: Variant = meta.get("fitness")
	dash.set_seed_info("(gen %s, fitness %d, %s%s)%s" % [
		str(int(gen)) if (gen is int or gen is float) else "?",
		roundi(float(fit)) if (fit is int or fit is float) else 0,
		_sizes_text((_network.net as NeuralNetwork).sizes),
		", walls: %s" % rule if rule != "" else "",
		" – would continue with walls: %s" % chosen if rule != "" and rule != chosen else ""])


func _preview_track() -> void:
	var ticked: Array[int] = dash.ticked_tracks()
	var i: int = ticked[0] if not ticked.is_empty() else _track_index
	var t := Tracks.build(Tracks.ids()[i])
	if t != _preview:
		_preview = t
		_show_track(t)


func _on_settings_changed() -> void:
	if session.trainer == null:
		_show_seed_info()
		_preview_track()


func _form_state() -> Dictionary:
	var f: Dictionary = dash.read_form()
	f.tracks = dash.ticked_tracks()
	f.seed = dash.seed_check.checked
	return f


func _restore_form() -> void:
	var f: Dictionary = session.form
	if f.is_empty():
		return
	dash.pop.value = int(f.population_size)
	dash.mut.value = float(f.mutation_rate)
	dash.hidden_edit.text = ",".join(PackedStringArray(f.hidden.map(func(v: Variant) -> String: return str(int(v)))))
	dash.set_laps(int(f.laps))
	dash.set_walls(String(f.walls))
	dash.tick_tracks(f.tracks)


## Start a new session from the form (and the saved network when ticked, or `seed_override`
## {net, meta}: a loaded file).
func start(seed_override: Dictionary = {}) -> void:
	var f: Dictionary = dash.read_form()
	var ids := Tracks.ids()
	var tracks: Array = []
	for i: int in dash.ticked_tracks():
		tracks.append(Tracks.build(ids[i]))
	if tracks.is_empty():
		tracks.append(Tracks.build(ids[_track_index]))
	var seed: NeuralNetwork = null
	var seed_meta: Variant = null
	if not seed_override.is_empty():
		seed = seed_override.net
		seed_meta = seed_override.get("meta")
	elif dash.seed_check.checked and not _network.is_empty():
		seed = _network.net
		seed_meta = _network.get("meta")
	_stop_max()
	_remove_fleet()
	var cfg := f.duplicate()
	cfg.tracks = tracks
	cfg.seed = seed
	cfg.seed_meta = seed_meta
	cfg.threads = 0
	var tr := Trainer.new(cfg)
	var s := session
	s.trainer = tr
	s.history = []
	for h in tr.history:
		s.history.append(h.duplicate())
	# only a seed scored on the same tracks counts as already saved (see Trainer)
	s.last_saved = tr.population.best_ever.fitness if tr.population.best_ever != null else -INF
	s.selected = -1
	s.paused = false
	_adopt(tr)
	_show_run()
	_attach_track(tr.track)
	_render_dashboard()
	_sim_rate = 0.0
	var note := ("Continuing from a saved network (%s).%s" % [_sizes_text(seed.sizes), _rule_change(seed_meta)]) if seed != null \
		else "New population of %d random drivers." % tr.population.size()
	if tr.native_note != "":
		note += " " + tr.native_note
	_note(note)


## Make the session's Trainer report to this screen.
func _adopt(tr: Trainer) -> void:
	tr.on_track_change = _on_track_change
	tr.on_generation = _on_generation
	if fleet == null:
		fleet = AIFleet.new(tr.population.size())
		(app.get("world") as Node).add_child(fleet)


## A note for when a network trained with one wall rule continues with the other.
func _rule_change(meta: Variant) -> String:
	var was := Trainer.saved_wall_rule(meta)
	var now: String = session.trainer.cfg.walls
	return " It was trained with walls: %s; this run uses walls: %s, so its old best fitness doesn't carry over." % [was, now] \
		if was != "" and was != now else ""


func _show_run() -> void:
	dash.show_run()
	_sync_buttons()
	_chart_dirty = true
	_stats_timer = 0.0


func stop() -> void:
	_stop_max()
	var s := session
	if s.trainer != null:
		s.trainer.on_generation = Callable()
		s.trainer.on_track_change = Callable()
	s.trainer = null
	s.history = []
	_pending_track = null
	_remove_fleet()
	rays.visible = false
	dash.set_max(false)
	_preview = null
	_show_setup()


func _remove_fleet() -> void:
	if fleet != null and is_instance_valid(fleet):
		fleet.queue_free()
	fleet = null


func _show_track(t: BuiltTrack) -> void:
	if app.has_method("show_track"):
		app.call("show_track", t)
	else:
		(app.get("world") as World).show_track(t)
	camera.set_track(t)


## Show the track the session drives now. At Max nothing is drawn, so building the next
## track's 3D scene would only stall the training (multi-track training switches track every
## run): it is shown when the view comes back (another speed, or pause).
func _attach_track(t: BuiltTrack) -> void:
	session.selected = -1
	if _max != null:
		_max.set_selected(-1)
	if (session.speed == "max" and not session.paused) or not _active:
		_pending_track = t
		return
	_pending_track = null
	_show_track(t)
	var tr := session.trainer
	tr.sync_agents()
	if not tr.agents.is_empty():
		camera.snap(tr.agents[tr.leader_index()].car, t)
	_chase_car = null


# ================================================================= the Trainer's callbacks

## (main thread, or the Max thread) A generation ended: autosave when the best improved.
func _on_generation(entry: Dictionary) -> void:
	var tr := session.trainer
	var data: Variant = null
	if tr.best_fitness > session.last_saved:
		session.last_saved = tr.best_fitness
		data = tr.export_best()
	_ev_mutex.lock()
	_events.append(["generation", entry.duplicate(), data, tr.generation - 1, tr.best_fitness])
	_ev_mutex.unlock()


## (main thread, or the Max thread) A track run started.
func _on_track_change(t: BuiltTrack) -> void:
	_ev_mutex.lock()
	_events.append(["track", t])
	_ev_mutex.unlock()


## Handle what the callbacks reported (main thread).
func _drain_events() -> void:
	_ev_mutex.lock()
	var evs := _events
	_events = []
	_ev_mutex.unlock()
	var s := session
	for ev: Array in evs:
		if ev[0] == "generation":
			s.history.append(ev[1])
			s.selected = -1
			if _max != null:
				_max.set_selected(-1)
			_chart_dirty = true # (drawn once per frame: Max can end several generations in one)
			if ev[2] != null:
				var parsed := _keep_network(ev[2])
				if not parsed.is_empty():
					_note("Gen %d: new best (%d), autosaved." % [int(ev[3]), roundi(float(ev[4]))])
		elif ev[0] == "track" and s.trainer != null:
			_attach_track(ev[1])


## Write `data` (a network file) to the save file and make it the saved network. {net, meta}.
func _keep_network(data: Dictionary) -> Dictionary:
	if not SaveData.save_network(data):
		_note("The network could not be saved (the save file can't be written).")
	var parsed := Trainer.parse_network_file(data)
	if parsed.has("error"):
		return {}
	_network = parsed
	network_saved.emit(parsed)
	return parsed


# ================================================================= per frame

func update(dt: float) -> void:
	var inp: Object = app.get("input")
	if inp != null:
		if inp.call("consume", ["Escape", "PadB", "PadStart"]):
			_leave()
			return
		dash.handle_pad(inp)
		inp.call("clear_pressed")
	if not _active:
		return # (the pad pressed Menu, Watch best or Race best)
	_drain_events()
	var s := session
	if s.trainer == null:
		# setup screen: slowly orbit the preview track
		_orbit += dt * ORBIT_SPEED
		if _preview != null:
			ChaseCamera.orbit_pose(camera, _preview, _orbit)
		_fit_camera()
		return

	_sync_max()
	if _max != null:
		_update_max(dt)
		return

	var tr := s.trainer
	var steps := 0
	var alpha := 1.0 # between the last two physics steps (1× only)
	if not s.paused:
		if s.speed == "max":
			# the Max thread failed: simulate here for most of the frame
			var t0 := Time.get_ticks_usec()
			while Time.get_ticks_usec() - t0 < 28000 and _active:
				tr.step_many(20)
				steps += 20
		elif s.speed == "1":
			# fixed 60 Hz steps; agent.prev is each car's pose before its last step, so the
			# fleet is drawn in between for smooth motion
			_acc += minf(dt, 0.1)
			while _acc >= STEP:
				_acc -= STEP
				tr.step(STEP)
				steps += 1
			alpha = _acc / STEP
		elif tr.is_native():
			tr.step_many(FAST_STEPS)
			steps = FAST_STEPS
		else:
			var t0 := Time.get_ticks_usec()
			while steps < FAST_STEPS and Time.get_ticks_usec() - t0 < FAST_BUDGET_USEC:
				tr.step(STEP)
				steps += 1
	elif s.speed == "1":
		alpha = _acc / STEP
	_sim_rate = _sim_rate * 0.9 + (steps / maxf(dt, 1e-3) / 60.0) * 0.1
	_drain_events()
	if session.trainer != tr:
		return
	tr.sync_agents()
	var shown := _shown_agent()
	tr.sync_shown(shown)
	var drawing := not (s.speed == "max" and not s.paused) # (Max without its thread draws nothing either)
	dash.set_max(not drawing, "%d× real time" % roundi(_sim_rate))
	if drawing:
		if _pending_track != null:
			_attach_track(_pending_track)
		fleet.update(tr.agents, tr.track, shown.index if shown != null else -1, Time.get_ticks_msec() / 1000.0, alpha)
		if shown != null:
			var view: Variant = fleet.selected_view if fleet.has_selected_view else shown.car # (the shown car between two steps)
			rays.visible = true
			rays.update(view, shown.rays, Sensors.SENSOR_RANGE)
			# the view is one copy reused for whichever car is shown: when that changes (a new
			# leader, a click), the new car's earlier wall contacts are no news (no shake)
			if shown.car != _chase_car:
				_chase_car = shown.car
				camera.wall.ready = false
			if s.cam == "chase":
				camera.update(view, dt, tr.track)
		if s.cam == "overview":
			_overview_pose(tr.track)
		_fit_camera()

	# dashboard: the network every frame (cheap), the text a few times a second
	if shown != null:
		dash.draw_net({sizes = Array(tr.sizes), weights = shown.net.weights, acts = shown.net.acts})
	_draw_chart()
	_stats_timer -= dt
	if _stats_timer <= 0.0:
		_stats_timer = STATS_EVERY
		dash.set_stats(tr.live_stats(), tr.tracks, tr.cfg.walls)
		dash.set_viewing(TrainModeInfo.shown_info(shown, s.selected) if shown != null else {})


## A frame while the Max thread trains: nothing to simulate or draw here but the dashboard.
func _update_max(dt: float) -> void:
	dash.set_max(true, dash.max_rate.text)
	rays.visible = false
	_draw_chart()
	_stats_timer -= dt
	if _stats_timer > 0.0:
		return
	_stats_timer = STATS_EVERY
	var snap := _max.get_snapshot()
	if snap.is_empty():
		return
	var tr := session.trainer
	if _last_steps >= 0 and int(snap.usec) > _last_usec:
		var rate := (int(snap.steps) - _last_steps) / 60.0 / ((int(snap.usec) - _last_usec) / 1e6)
		_sim_rate = _sim_rate * 0.6 + rate * 0.4 if _sim_rate > 0.0 else rate
	_last_steps = int(snap.steps)
	_last_usec = int(snap.usec)
	var how := "" if tr.is_native() else "\n(GDScript: the fast training extension is not loaded)"
	dash.set_max(true, "%d× real time%s" % [roundi(_sim_rate), how])
	dash.draw_net(snap.net)
	dash.set_stats(snap.stats, tr.tracks, tr.cfg.walls)
	var shown: Dictionary = snap.shown
	shown.clicked = session.selected >= 0 and int(shown.index) == session.selected
	dash.set_viewing(shown)


## Start or end the Max thread so it matches the speed and pause buttons.
func _sync_max() -> void:
	var s := session
	var want := s.trainer != null and s.speed == "max" and not s.paused and _active and not _max_broken
	if want and _max == null:
		_max = MaxRun.new(s.trainer, s.selected)
		_last_steps = -1
		_stats_timer = 0.0
		_max.start()
	elif _max != null and (not want or _max.is_ended()):
		var failed := _max.is_ended() and want
		_stop_max()
		if failed:
			_max_broken = true
			_note("Max speed now simulates on this screen (the background thread stopped).")


## Take the session back from the Max thread (it stops after its current slice).
func _stop_max() -> void:
	if _max == null:
		return
	_max.finish()
	_max = null
	_drain_events()
	_acc = 0.0
	_stats_timer = 0.0 # (and refreshed again on the next frame)
	var tr := session.trainer
	if tr != null and _active and dash != null and is_instance_valid(dash):
		_pending_track = tr.track # shown, and the camera put behind the leader, when the view is back
		dash.set_max(false)
		# the session's numbers as they are now, at once: the thread's last snapshot can be
		# a few generations old (it is published every STATS_EVERY seconds)
		tr.sync_agents(false)
		dash.set_stats(tr.live_stats(), tr.tracks, tr.cfg.walls)


func _draw_chart() -> void:
	if not _chart_dirty:
		return
	_chart_dirty = false
	dash.draw_chart(session.history)


func _shown_agent() -> Trainer.Agent:
	var tr := session.trainer
	if tr.agents.is_empty():
		return null
	var k := session.selected
	if k >= 0 and k < tr.agents.size():
		return tr.agents[k]
	return tr.agents[tr.leader_index()]


## The dashboard right away (a new session: its first numbers before the first frame).
func _render_dashboard() -> void:
	var tr := session.trainer
	var a := _shown_agent()
	if a != null:
		dash.draw_net({sizes = Array(tr.sizes), weights = a.net.weights, acts = a.net.acts})
		dash.set_viewing(TrainModeInfo.shown_info(a, session.selected))
	dash.set_stats(tr.live_stats(), tr.tracks, tr.cfg.walls)
	_chart_dirty = true
	_draw_chart()


# ================================================================= the camera

## The 3D view is the part of the window not under the dashboard: an off-axis frustum puts
## the camera's centre in the middle of that part, with the camera's vertical field of view
## over its height (the web game's view canvas beside the dashboard).
func _fit_camera() -> void:
	if dash == null or camera == null:
		return
	var fs: Vector2 = dash.size
	if fs.x <= 0.0 or fs.y <= 0.0:
		return
	var v: Rect2 = dash.view_rect()
	if v.size.x <= 0.0 or v.size.y <= 0.0:
		return
	var h := 2.0 * camera.near * tan(deg_to_rad(camera.fov) / 2.0) * fs.y / v.size.y
	var cx := (v.position.x + v.size.x / 2.0) / fs.x
	var cy := (v.position.y + v.size.y / 2.0) / fs.y
	camera.projection = Camera3D.PROJECTION_FRUSTUM
	camera.size = h
	camera.frustum_offset = Vector2((0.5 - cx) * h * fs.x / fs.y, (cy - 0.5) * h)


## Above the whole track (ChaseCamera.overview_pose for the free part of the window).
func _overview_pose(t: BuiltTrack) -> void:
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for i in t.count:
		min_x = minf(min_x, t.px[i])
		max_x = maxf(max_x, t.px[i])
		min_z = minf(min_z, t.pz[i])
		max_z = maxf(max_z, t.pz[i])
	var v: Rect2 = dash.view_rect()
	var aspect := v.size.x / v.size.y if v.size.y > 0.0 else 16.0 / 9.0
	var cx := (min_x + max_x) / 2.0
	var cz := (min_z + max_z) / 2.0
	var size := maxf(max_x - min_x, (max_z - min_z) * aspect)
	var hgt := (size / 2.0 / tan(deg_to_rad(camera.fov) / 2.0)) * 1.05 + 30.0
	var p := Vector3(cx, hgt, cz + hgt * 0.25)
	camera.global_transform = Transform3D(Basis.looking_at(Vector3(cx, 0.0, cz) - p, Vector3.UP), p)
	camera.shake = 0.0


# ================================================================= interaction

func _on_action(act: String) -> void:
	var s := session
	match act:
		"menu":
			_leave()
		"start":
			start()
		"load":
			_load_file()
		"pause":
			s.paused = not s.paused
			_stats_timer = 0.0 # (the dashboard text follows on the next frame)
			_sync_buttons()
			_sync_max()
		"speed_1", "speed_6", "speed_max":
			s.speed = act.trim_prefix("speed_")
			_acc = 0.0
			_stats_timer = 0.0
			_sync_buttons()
			_sync_max()
		"follow":
			s.selected = -1
			if _max != null:
				_max.set_selected(-1)
			_note("Following the leading car.")
		"cam":
			s.cam = "overview" if s.cam == "chase" else "chase"
			if s.cam == "chase" and s.trainer != null and _max == null:
				var a := _shown_agent()
				if a != null:
					camera.snap(a.car, s.trainer.track)
			_sync_buttons()
		"save":
			_save_best()
		"watch", "race":
			_play_best(act == "race")
		"stop":
			stop()


func _leave() -> void:
	exit_requested.emit()


func _sync_buttons() -> void:
	var s := session
	dash.sync_buttons(s.paused, s.speed, s.cam)


func _note(text: String) -> void:
	session.note = text
	if dash != null:
		dash.set_note(text)


## Click a car in the 3D view to see its network (not at Max: nothing is drawn).
func _unhandled_input(e: InputEvent) -> void:
	if not _active or fleet == null or session.trainer == null or _max != null:
		return
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var k := fleet.pick(camera, (e as InputEventMouseButton).position)
		if k >= 0:
			session.selected = k
			_note('Viewing car #%d. Click "Follow leader" to go back to the best car.' % (k + 1))
			get_viewport().set_input_as_handled()


## Save best network: into the save file (Watch / Race the AI on the menu use it) and as a file.
func _save_best() -> void:
	var tr := session.trainer
	if tr == null:
		return
	_stop_max()
	var data := tr.export_best()
	_keep_network(data)
	var path := _write_file(data, "ai-driver-gen%d.json" % int(data.generation))
	_note("Best network saved (generation %d)%s." % [int(data.generation),
		", and as a file: %s" % ProjectSettings.globalize_path(path) if path != "" else ""])


## Write a network file into file_dir (user://networks); its path, or "" when it can't be written.
func _write_file(data: Dictionary, file_name: String) -> String:
	DirAccess.make_dir_recursive_absolute(file_dir)
	var path := file_dir.path_join(file_name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	return path


func _play_best(ghost: bool) -> void:
	var tr := session.trainer
	if tr == null:
		return
	_stop_max()
	var net: NeuralNetwork = tr.best_net if tr.best_net != null else tr.population.genomes[0].net
	if ghost:
		race_requested.emit(tr.track, net.clone())
	else:
		watch_requested.emit(tr.track, net.clone())


## Load network file…: pick a JSON file; training starts again from it.
func _load_file() -> void:
	if _file_dialog != null and is_instance_valid(_file_dialog):
		return
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.json ; Network files"])
	fd.use_native_dialog = true
	fd.title = "Load a network file"
	fd.file_selected.connect(func(path: String) -> void:
		load_network_text(FileAccess.get_file_as_string(path))
		fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	_file_dialog = fd
	add_child(fd)
	fd.popup_centered_ratio(0.6)


## A network file's text (Load network…): kept as the saved network and trained on.
func load_network_text(text: String) -> void:
	var parsed := Trainer.parse_network_file(text)
	if parsed.has("error"):
		_note("Could not load: %s" % parsed.error)
		return
	var meta: Dictionary = parsed.meta
	_keep_network(meta if meta.has("network") else Trainer.network_file(parsed.net))
	start(parsed)
	_note("Loaded network (%s), training continues from it.%s" % [_sizes_text(parsed.net.sizes), _rule_change(meta)])


static func _sizes_text(sizes: PackedInt32Array) -> String:
	var out: PackedStringArray = []
	for n in sizes:
		out.append(str(n))
	return "-".join(out)
