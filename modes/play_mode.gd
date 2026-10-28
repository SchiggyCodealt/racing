extends Node
## play_mode.gd (port of web/src/game/playMode.js)
## ------------------------------------------------------------------
## A race on one track. Three flavours:
##   driver "human"                  you drive (Drive)
##   driver "human" + ghost network  you race a see-through AI car (Race the AI ghost)
##   driver "ai"                     watch the AI drive with its live network (Watch the AI:
##                                   modes/watch_mode.gd, which only adds its view)
## The player drives with the keyboard or a gamepad (game/input.gd actions: View restart,
## B respawn, Y ghost, Menu back; the HUD names them while the pad is the last input used).
##
## The player drives the car picked on the menu (the "car" setting); Shift / X / RB burns its
## nitro tank, full at every start and kept on respawn. The watched AI and the AI ghost drive
## the car their network belongs to (opts.ai_car: the menu's car, whose network it is, or the
## training session's car), in that car's own colours, and never use nitro.
##
## Best times, ghosts and medals are per track and car: the player's runs are recorded
## (sim/replay.gd); a new personal best with the car is saved (sim/save.gd) with its ghost.
## In plain Drive the best run's ghost of the car you drive races along (G / Y shows or hides
## it, remembered as the "ghost" setting), drawn as that car with its nitro flames. It is only
## drawn: it never collides and counts for nothing. It runs on the race clock: physics steps
## since GO, the same count the recording was made with.
##
## Medal times (sim/medals.gd, data/medals.json): the HUD shows the next medal above your best
## time with the car, the finish panel the medal the run earned and whether it is new.
##
## Style score (sim/score.gd): the player's runs (Drive and Race the AI ghost, not Watch the
## AI) score points for clean checkpoints (with a combo), drifts, jumps and close calls, and
## lose some for wall contacts and respawns; banked points refill the nitro tank. The HUD shows
## the score, the combo, what is building up and a popup per event; the finish panel the
## breakdown and the best score for this track and car (saved when beaten).
##
## Physics runs at a fixed 60 Hz with an accumulator (the step the AI trains with); the
## frame draws the cars between the last two steps (render interpolation), so any display
## rate stays smooth. AI cars (watched or ghost) are not eliminated by walls: one that makes
## no progress for STUCK_TIME seconds is put back at its last checkpoint.
##
## Mode protocol (game/app.gd): setup(app, opts) before it joins the tree, enter() when it
## becomes the active mode, update(dt) every frame, exit() when it is left (then freed).
## opts: {track: BuiltTrack, driver: "human" | "ai", net: NeuralNetwork (AI and the AI ghost),
## ai_car: the car id the network drives (default the racer), ghost: bool (race the AI ghost),
## car: the player's car id (default: the picked car), return_to: Callable}

const AiLink := preload("res://game/ai_link.gd")

const STEP := 1.0 / 60.0
const COUNTDOWN := 3.0
const STUCK_TIME := 3.0 # s without progress before an AI car is respawned
const PB_COLOR := Color("#8fd6ff") # the best-run ghost (the AI ghost is purple)
const AI_GHOST_COLOR := Color("#b36bff")
const NOTE_TIME := 2.5 # s a HUD note (ghost on / off) stays up
const POPS_KEPT := 8 # score events kept for the HUD between two frames
const RESPAWN_AHEAD := 6 # samples a respawned car is moved past its checkpoint (12 m)

## The app shows the race HUD for this mode.
var uses_hud := true
var app: GameApp
var track: BuiltTrack
var driver := "human"
var net: Object = null
## The car the AI network drives (Watch the AI: car_def is this car; the AI ghost).
var ai_def: Dictionary = {}
var with_ghost := false
var car_def: Dictionary = {}
var rec: Replay.GhostRecorder = null
var pb_shown := true
var medals: Dictionary = {}
var return_to: Callable
var ctrl := Car.Controls.new()

# nodes
var model: CarModel
var ghost_model: CarModel = null
var pb_model: CarModel = null
var camera: ChaseCamera

# the run
var car: Car
var race: RaceState
var record: Dictionary = {}       # your best with this car ({} none)
var medal_target: Variant = null  # the HUD's medal target, fixed for the run
var pb: Replay.GhostPlayer = null
var next_pb: Replay.GhostPlayer = null
var race_step := 0                # physics steps since GO: the clock the ghost replays on
var score: ScoreState = null
var score_events: Array = []
var best_score: Dictionary = {}
var note: Dictionary = {}         # {t, text} a HUD note, {} none
var ghost: Dictionary = {}        # the AI ghost: {car, race, ai, watch}, {} none
var watch: Dictionary = {}        # the stuck watchdog of the main car
var ai: Object = null             # the AI's driver (Watch the AI)
var ai_note := 0.0
var phase := "countdown"
var clock := COUNTDOWN
var go_timer := 0.0
var acc := 0.0
var ghost_text := ""
## The finish panel's state of the last finish ({} before), kept for tests.
var finish_state: Dictionary = {}
## Physics steps and wall-clock time spent in them (the e2e runs measure the script cost).
var steps_run := 0
var step_usec := 0

var _prev := {}       # "car" / "ghost" -> the pose before the last step
var _gates_done := -1
var _coast := Car.Controls.new()
var _spec_info: Dictionary = {}
var _rev_spec: Dictionary = {}


## Called by the app before the mode joins the tree.
func setup(p_app: GameApp, opts: Dictionary) -> void:
	app = p_app
	name = "PlayMode"
	track = opts.track
	driver = str(opts.get("driver", "human"))
	net = opts.get("net")
	with_ghost = bool(opts.get("ghost", false)) and net != null and driver == "human"
	# the player's car (opts.car or the one picked on the menu); the AI drives its network's car
	ai_def = Cars.get_car(str(opts.get("ai_car", Cars.DEFAULT_CAR)))
	var cid: String = str(opts.get("car", UiData.picked_car())) if driver == "human" else String(ai_def.id)
	car_def = Cars.get_car(cid)
	rec = Replay.GhostRecorder.new() if driver == "human" else null
	pb_shown = bool(UiData.get_setting("ghost"))
	medals = Medals.medal_times(track, car_def.id)
	return_to = opts.get("return_to", Callable()) if opts.get("return_to") is Callable else Callable()
	if not return_to.is_valid():
		return_to = app.show_menu
	var sp: CarSpec = car_def.spec
	_rev_spec = {"idle_rpm": sp.idle_rpm, "redline": sp.redline, "upshift_rpm": sp.upshift_rpm}


func enter() -> void:
	app.show_track(track)
	var world := app.world
	# the player's car (or the watched AI's) in its own colours; the AI ghost is its car in purple
	model = CarModel.new(car_def.id)
	world.add_child(model)
	if with_ghost:
		ghost_model = CarModel.new(ai_def.id, {"ghost": true, "color": AI_GHOST_COLOR})
		world.add_child(ghost_model)
	elif driver == "human":
		# your best run on this track with this car (if there is one yet), drawn as that car
		pb = _load_pb()
		pb_model = CarModel.new(car_def.id, {"ghost": true, "color": PB_COLOR})
		pb_model.visible = false
		world.add_child(pb_model)
	camera = ChaseCamera.new()
	camera.name = "ChaseCamera"
	camera.set_track(track)
	world.add_child(camera)
	camera.make_current()
	_enter_view()
	var hud := app.ui.hud
	var cname: String = car_def.name
	hud.set_mode(_mode_text(cname))
	var keys: Array = []
	if driver == "human":
		keys.append(["Shift", "nitro", "X / RB"])
	keys.append(["R", "restart", "View"])
	if driver == "human":
		keys.append(["Enter", "respawn", "B"])
	if pb_model != null:
		keys.append(["G", "ghost", "Y"])
	keys.append(["Esc", "menu", "Menu"])
	hud.set_keys(keys, app.input.pad_active)
	restart()


## The HUD's top line.
func _mode_text(cname: String) -> String:
	if with_ghost:
		var vs := "VS AI GHOST" if ai_def.id == car_def.id else "VS AI GHOST (%s)" % ai_def.name
		return "%s · %s · %s" % [vs, track.name, cname]
	return "%s · %s" % [track.name, cname]


## Hook for the AI view (watch_mode.gd).
func _enter_view() -> void:
	pass


func exit() -> void:
	for n: Node in [model, ghost_model, pb_model, camera]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_exit_view()
	app.ui.hud.hide_panel()


func _exit_view() -> void:
	pass


func restart() -> void:
	car = Car.new(track, track.start_idx, car_def.spec) # a full nitro tank
	race = RaceState.new(track)
	record = SaveData.get_record(track.id, car_def.id) # your best with this car
	medal_target = _aim_for() # fixed for the run: the HUD ticks it at the finish if won
	# a best run saved during the last race is raced from now on
	if next_pb != null:
		pb = next_pb
		next_pb = null
	race_step = 0
	if rec != null:
		rec.reset()
		rec.add(0, car, true)
	# the player's style score (its points refill the nitro tank); the AI scores nothing
	score = ScoreState.new(track) if driver == "human" else null
	score_events.clear()
	best_score = SaveData.get_best_score(track.id, car_def.id) if score != null else {}
	note = {}
	if with_ghost:
		ghost = {"car": Car.new(track, track.start_idx, ai_def.spec), "race": RaceState.new(track), "ai": AiLink.driver(net)}
		ghost.watch = _new_watch(ghost.car, 0.0)
	watch = _new_watch(car, 0.0)
	ai_note = 0.0
	phase = "countdown"
	clock = COUNTDOWN
	go_timer = 0.0
	acc = 0.0
	ghost_text = ""
	finish_state = {}
	app.ui.hud.hide_panel()
	app.ui.hud.reset_score()
	app.input.steer = 0.0
	_restart_view()
	_save_prev()
	model.reset_effects()
	camera.snap(car, track)
	_update_gates(true)


func _restart_view() -> void:
	pass


## Back to the last checkpoint. The player keeps the speed they had there; a stuck AI restarts standing.
func respawn(standing: bool = false) -> void:
	if score != null:
		_add_score_events(score.respawn()) # (the player only: the AI scores nothing)
	if rec != null:
		rec.before_jump(race_step, car)
	respawn_car(car, race, track, not standing)
	if rec != null:
		rec.after_jump(race_step, car)
	app.input.steer = 0.0
	watch = _new_watch(car, race.time)
	_save_prev()
	camera.snap(car, track)


func update(dt: float) -> void:
	var inp := app.input
	if inp.consume(["menu"]):
		return_to.call()
		return
	if inp.consume(["restart"]):
		restart()
	if driver == "human" and phase == "race" and inp.consume(["respawn"]):
		respawn()
	if pb_model != null and inp.consume(["ghost"]):
		toggle_ghost()
	inp.clear_pressed()
	if not note.is_empty():
		note.t = float(note.t) - dt
		if float(note.t) <= 0.0:
			note = {}

	acc += dt
	var t0 := Time.get_ticks_usec()
	while acc >= STEP:
		acc -= STEP
		_save_prev()
		fixed_step(STEP)
		steps_run += 1
	step_usec += Time.get_ticks_usec() - t0
	render(dt, acc / STEP)


func fixed_step(dt: float) -> void:
	if phase == "countdown":
		clock -= dt
		if clock <= 0.0:
			phase = "race"
			go_timer = 0.8
		return
	if go_timer > 0.0:
		go_timer -= dt
	race_step += 1

	# --- the main car ---
	var c: Car.Controls
	if phase == "finished":
		c = roll_out(car, track, _coast)
	else:
		c = _drive(dt)
	car.step(track, c, dt)
	if phase == "race":
		var events := race.update(car, dt)
		if score != null:
			_add_score_events(score.update(car, race, dt)) # before _on_finish, which shows the score
		if rec != null:
			rec.add(race_step, car, race.finished) # before _on_finish, which saves the run
		for ev: Dictionary in events:
			_on_gate(ev)
		_watchdog()
	if ai_note > 0.0:
		ai_note -= dt

	# --- the AI ghost ---
	if not ghost.is_empty():
		var gcar: Car = ghost.car
		var grace: RaceState = ghost.race
		var gc: Car.Controls = roll_out(gcar, track, _coast) if grace.finished else ghost.ai.call("drive", track, gcar, grace)
		gcar.step(track, gc, dt)
		grace.update(gcar, dt)
		if not grace.finished and is_stuck(ghost.watch, gcar, grace):
			respawn_car(gcar, grace, track, false)
			ghost.watch = _new_watch(gcar, grace.time)
			_store_pose(_prev.ghost, gcar)


## The main car's controls for this step: the player's input (watch_mode.gd: the AI).
func _drive(dt: float) -> Car.Controls:
	return app.input.controls(dt, ctrl, car.speed)


## After a race step (watch_mode.gd: put a stuck AI back on the road).
func _watchdog() -> void:
	pass


func _on_gate(ev: Dictionary) -> void:
	var hud := app.ui.hud
	var gi: int = ev.gate_index
	var gate: Dictionary = race.gates[gi]
	var splits: Array = record.get("splits", [])
	var best: Variant = splits[gi] if gi < splits.size() else null
	var delta: Variant = float(ev.time) - float(best) if best != null else null
	var label: String
	if ev.kind == "cp":
		label = "CP %d" % (int(gate.cp) + 1)
	elif ev.kind == "lap":
		label = "LAP %d" % (int(gate.lap) + 1)
	else:
		label = "FINISH"
	hud.split(label, ev.time, delta)
	if not ghost.is_empty():
		var gs: PackedFloat64Array = (ghost.race as RaceState).splits
		ghost_text = ("AI ghost %s" % RaceState.format_delta(float(ev.time) - gs[gi])) if gi < gs.size() else "AI ghost behind you"
	_update_gates(ev.kind != "cp")
	if ev.kind == "finish":
		_on_finish()


func _on_finish() -> void:
	phase = "finished"
	model.celebrate() # the driver's fist pump (reset_effects() on restart ends it)
	var t: float = race.finish_time
	var s := {"title": "AI finished" if driver == "ai" else "Finish", "time": t, "ai": driver == "ai"}
	if driver == "human":
		var is_record := SaveData.submit_record(track.id, car_def.id, t, race.splits)
		var prev: Variant = record.get("time")
		s.medal = _medal_line(t, prev)
		if is_record:
			s.record = {"prev": prev}
			s.ghost_note = _save_run(t)
		else:
			s.best = {"car": car_def.name, "time": prev}
		var nx := _next_medal(t, t if is_record else prev)
		if not nx.is_empty():
			s.next = nx
		if not ghost.is_empty():
			var gr: RaceState = ghost.race
			if gr.finished:
				s.lines = ["AI ghost: %s, %s" % [RaceState.format_time(gr.finish_time), "you win!" if t <= gr.finish_time else "the AI wins"]]
			else:
				s.lines = ["AI ghost hasn't finished: you win!"]
		s.score = _score_state()
		record = SaveData.get_record(track.id, car_def.id)
	else:
		s.medal = _medal_line(t, null)
		if not record.is_empty():
			s.best = {"car": car_def.name, "time": record.time}
	if race.lap_times.size() > 1:
		s.laps = Array(race.lap_times)
	s.pad = app.input.pad_connected # name the gamepad buttons too
	finish_state = s
	app.ui.hud.show_panel(s)


## Queue score events for the HUD's popups (only the last few are kept between frames).
func _add_score_events(events: Array) -> void:
	if events.is_empty():
		return
	score_events.append_array(events)
	if score_events.size() > POPS_KEPT:
		score_events = score_events.slice(score_events.size() - POPS_KEPT)


## The finish panel's score: total, breakdown, the nitro it refilled and the best score for
## this track and car (saved if beaten).
func _score_state() -> Dictionary:
	var sc := score
	var prev := best_score
	var is_best := SaveData.submit_score(track.id, car_def.id, sc.total)
	var now := SaveData.get_best_score(track.id, car_def.id)
	best_score = now if not now.is_empty() else prev
	var rows: Array = []
	for r: Dictionary in sc.breakdown():
		rows.append({"label": r.label, "note": r.note, "points": r.points})
	return {
		"total": sc.total, "new_best": is_best, "prev": int(prev.score) if not prev.is_empty() else -1,
		"car": car_def.name, "rows": rows, "nitro_earned": sc.nitro_earned, "nitro_lost": sc.nitro_earned - sc.nitro,
	}


## The HUD's medal target for this run: the next medal above your best time ({medal, time};
## all: every medal won), or null.
func _aim_for() -> Variant:
	if medals.is_empty() or driver != "human":
		return null
	var n := Medals.next_medal(medals, float(record.get("time", INF)))
	return n if not n.is_empty() else {"medal": "author", "time": float(medals.author), "all": true}


## The medal time `t` earns ({got, new} / {got: "", bronze} / {} no medal times); NEW when it
## beats the medal of the best time before (`prev`; never for the AI).
func _medal_line(t: float, prev: Variant) -> Dictionary:
	if medals.is_empty():
		return {}
	var got := Medals.medal_for(medals, t)
	if got == "":
		return {"got": "", "bronze": float(medals.bronze)}
	var had := Medals.medal_for(medals, float(prev) if prev != null else INF)
	var is_new := driver == "human" and (had == "" or Medals.ORDER.find(got) < Medals.ORDER.find(had))
	return {"got": got, "new": is_new}


## The next medal above best time `best` ({medal, time}; none before the first medal).
func _next_medal(_t: float, best: Variant) -> Dictionary:
	var b := float(best) if best != null else INF
	if Medals.medal_for(medals, b) == "":
		return {}
	return Medals.next_medal(medals, b)


## The best-run ghost saved for this track and the player's car, ready to play, or null.
func _load_pb() -> Replay.GhostPlayer:
	var cid: String = car_def.id
	var laps: int = race.laps if race != null else (track.laps if track.closed else 1)
	var g := Replay.unpack_ghost(SaveData.load_ghost(track.id, cid), track, laps, cid)
	return Replay.GhostPlayer.new(g) if not g.is_empty() else null


## Save the run that just set a personal best as the ghost of this track and car. Returns the
## line for the finish panel.
func _save_run(time: float) -> String:
	var cid: String = car_def.id
	if rec == null or rec.full:
		return "Run too long to keep as a ghost"
	var data := Replay.pack_ghost(rec, {"track": track, "laps": race.laps, "time": time, "car": cid})
	if not SaveData.save_ghost(track.id, cid, data):
		return "Ghost not saved: the save file can't be written"
	var g := Replay.unpack_ghost(data, track, race.laps, cid)
	# the ghost that is still racing keeps going; the new one starts with the next race
	if not g.is_empty():
		next_pb = Replay.GhostPlayer.new(g)
	if not pb_shown:
		return "Ghost saved (ghosts are off: %s)" % ('tick "Race my best-run ghost" on the menu' if with_ghost
			else "%s shows it" % ("Y" if app.input.pad_active else "G"))
	return "Ghost saved: race it in Drive" if with_ghost else "Ghost saved: race it with R"


func toggle_ghost() -> void:
	var k := "Y" if app.input.pad_active else "G"
	# nothing to show yet: the remembered setting stays as it is (a best time can lack a ghost
	# when its run was too long to keep or the save failed)
	if pb == null and next_pb == null:
		note = {"t": NOTE_TIME, "text": "No ghost: beat your best to save one" if not record.is_empty()
			else "No %s ghost yet: set a best time first" % car_def.name}
		return
	pb_shown = not pb_shown
	UiData.set_setting("ghost", pb_shown)
	note = {"t": NOTE_TIME, "text": ("Ghost on (%s)" if pb_shown else "Ghost off (%s)") % k}


## Colour the checkpoint gates: passed this lap = green, next = cyan.
func _update_gates(force: bool) -> void:
	var n := track.cp_samples.size()
	var done := n if race.finished else race.cp_in_lap()
	if not force and done == _gates_done:
		return
	_gates_done = done
	for k in n:
		app.world.set_checkpoint_state(k, "passed" if k < done else ("next" if k == done else "idle"))


func _save_prev() -> void:
	if not _prev.has("car"):
		_prev.car = {}
	_store_pose(_prev.car, car)
	if not ghost.is_empty():
		if not _prev.has("ghost"):
			_prev.ghost = {}
		_store_pose(_prev.ghost, ghost.car)


static func _store_pose(p: Dictionary, c: Car) -> void:
	p.x = c.x
	p.y = c.y
	p.z = c.z
	p.yaw = c.yaw
	p.pitch = c.pitch
	p.roll = c.roll
	p.steer_angle = c.steer_angle
	p.wheel_rot = c.wheel_rot


func render(dt: float, alpha: float) -> void:
	var hud := app.ui.hud
	model.update(car, _prev.get("car"), alpha, dt, track)
	var view: CarEffects.Pose = model.pose # the car between the last two steps
	camera.update(view, dt, track)
	var cam := camera.global_position
	var at := Vector3(view.x, view.y, view.z)
	if not ghost.is_empty():
		ghost_model.update(ghost.car, _prev.get("ghost"), alpha, dt, track)
		var gp := ghost_model.pose
		ghost_model.set_fade(CarModel.ghost_fade(Vector3(gp.x, gp.y, gp.z), at, cam, true))
	if pb_model != null:
		# the frame shows the car between the last two steps: race time (race_step - 1 + alpha)
		# steps; after its finish the ghost is gone
		var on := pb != null and pb_shown and pb.pose(maxf(0.0, race_step - 1 + alpha))
		if on:
			pb_model.update(pb.car, null, 1.0, dt, track)
			var pp := pb_model.pose
			pb_model.set_fade(CarModel.ghost_fade(Vector3(pp.x, pp.y, pp.z), at, cam, true))
		else:
			pb_model.set_fade(0.0)
	_render_view(view)

	# HUD
	if phase == "countdown":
		hud.countdown(str(ceili(clock)))
	elif go_timer > 0.0:
		hud.countdown("GO!")
	else:
		hud.countdown("")
	_update_gates(false)
	var live: Variant = null
	var sc: Variant = null
	if score != null:
		var l := score.live()
		live = l if not l.is_empty() else null
		sc = {"total": score.total, "mult": score.multiplier(), "live": live}
	var gt := ghost_text
	if ai_note > 0.0:
		gt = "AI was stuck: back to its last checkpoint"
	elif not note.is_empty():
		gt = note.text
	hud.update({
		"time": race.finish_time if race.finished else race.time,
		"lap": race.lap(),
		"laps": race.laps,
		"cp": race.cp_per_lap - 1 if race.finished else mini(race.cp_in_lap(), race.cp_per_lap - 1),
		"cps": race.cp_per_lap - 1,
		"sprint": not track.closed,
		"speed": car.speed,
		"gear": car.gear,
		"rpm": car.rpm,
		"spec": _rev_spec, # the rev bar's scale
		"nitro": car.nitro if driver == "human" else null, # the AI never uses nitro: no gauge
		"boosting": car.boosting,
		"score": sc, # none when watching the AI
		"best": record.get("time"),
		"medal": medal_target,
		"finished": race.finished,
		"ghost_text": gt,
		"pad": app.input.pad_active, # key hints name the gamepad buttons
	}, dt)
	if not score_events.is_empty():
		hud.score_pops(score_events)
		score_events = []


## Hook for the AI view (sensor rays, the network): watch_mode.gd.
func _render_view(_view: CarEffects.Pose) -> void:
	pass


# ---------------------------------------------------------------- helpers (playMode.js)

## Progress watchdog for an AI car (`time`: the race time now).
static func _new_watch(c: Car, time: float) -> Dictionary:
	return {"best": c.prog, "at": time}


## True when the car has made no real progress for STUCK_TIME seconds of race time.
static func is_stuck(w: Dictionary, c: Car, r: RaceState) -> bool:
	if c.prog > float(w.best) + 2.0:
		w.best = c.prog
		w.at = r.time
		return false
	return r.time - float(w.at) > STUCK_TIME


## Put a car back at its last checkpoint (or the start), with the speed it had there or
## standing. It reappears RESPAWN_AHEAD samples past the gate with the same offset and angle
## to the road it had when it crossed it.
static func respawn_car(c: Car, r: RaceState, t: BuiltTrack, keep_speed: bool) -> void:
	var s: Dictionary = r.respawn
	if s.is_empty():
		c.place(t, t.start_idx)
		return
	var i: int = s.idx
	var j := i + RESPAWN_AHEAD
	var laps: int = s.laps
	if t.closed and j >= t.N:
		j -= t.N
		laps += 1
	if not t.closed:
		j = mini(j, mini(t.finish_idx - 1, t.count - 2))
	var lat: float = (float(s.x) - t.px[i]) * t.nx[i] + (float(s.z) - t.pz[i]) * t.nz[i]
	var turn: float = atan2(t.tx[j], t.tz[j]) - atan2(t.tx[i], t.tz[i])
	turn = atan2(sin(turn), cos(turn))
	var co := cos(turn)
	var si := sin(turn) # rotate the velocity with the road (+ = left)
	var vx: float = float(s.vx) * co + float(s.vz) * si if keep_speed else 0.0
	var vz: float = -float(s.vx) * si + float(s.vz) * co if keep_speed else 0.0
	c.place(t, j, {"x": t.px[j] + t.nx[j] * lat, "z": t.pz[j] + t.nz[j] * lat, "yaw": float(s.yaw) + turn,
		"vx": vx, "vz": vz, "idx": j, "laps": laps})


## After the finish: follow the road and brake to a stop (never into reverse), then coast.
## Sprints brake hard: the road ends 250 m after the finish line. The car keeps its own lane
## (at least 2.5 m inside the barrier) instead of aiming at the centre line.
static func roll_out(c: Car, t: BuiltTrack, out: Car.Controls) -> Car.Controls:
	var look := maxi(3, JsMath.roundi((6.0 + c.speed * 0.3) / t.seg_len))
	var i := (c.idx + look) % t.N if t.closed else mini(t.count - 1, c.idx + look)
	var room := maxf(0.0, t.hw[i] - 2.5)
	var lat := clampf(c.lat, -room, room)
	var gx: float = t.px[i] + t.nx[i] * lat - c.x
	var gz: float = t.pz[i] + t.nz[i] * lat - c.z
	var fx := sin(c.yaw)
	var fz := cos(c.yaw)
	var ang := atan2(gx * fz - gz * fx, gx * fx + gz * fz)
	out.steer = clampf(2.5 * ang, -1.0, 1.0) if c.forward_speed > 1.0 else 0.0
	out.throttle = ((-0.5 if t.closed else -1.0) if c.speed > 2.0 and c.forward_speed > 0.0 else 0.0)
	out.handbrake = false
	out.nitro = 0.0
	return out
