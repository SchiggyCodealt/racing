extends "res://modes/play_mode.gd"
## field_mode.gd (v6.13.0): Race the field: you against five AI drivers on a starting grid, with solid
## cars, positions, a podium and pay by finishing place.
## ------------------------------------------------------------------
## The play mode (modes/play_mode.gd) with a field (sim/field_race.gd) instead of one see-through car:
## the AI drivers of sim/field.gd's lineup for the track and the field level, each the shipped AI
## opponent network of its car with its own speed cap, in its own colours, solid (sim/car_contact.gd).
## You start last on the grid, on the usual start spot, so the run counts as in Drive: the record, its
## ghost, the medal and the track it opens (the best-run ghost doesn't race along here).
##
## Every step after GO the whole field steps (FieldRace.step: your controls, the AI's, the contacts,
## the races); the HUD shows your place (P3/6), the gaps to the cars ahead and behind and the standings
## (RaceHud's field block). Mud and snow reach your screen from any car close ahead. The five AI engines
## are heard from where they are, but only the VOICES nearest at once (the others are paused: the
## synthesis costs script time).
##
## At your finish your place is known (whoever is still racing is behind you): the finish panel docks
## on the right with the standings, the times and gaps as they come in, and the payout (the medal as
## in Drive, plus the place rewards of sim/economy.gd for this field level, each place once per track
## and car). The AI still racing finish within a few frames (FAST_USEC of extra steps a frame, hidden),
## and PODIUM_AT s after your finish the top three stand on a podium on the start straight
## (world/podium.gd), with a slow camera move. R races again, Esc goes back.
##
## opts (setup): {track, field: the level id, lineup: Field.lineup(...), nets: one network per AI
## driver (AiLink.clone_net), car (default the picked car), return_to}.

const FAST_USEC := 6000       # script time a frame may spend finishing the AI's races after yours (µs)
const PODIUM_AT := 1.8        # s after your finish
const VOICES := 3             # AI engines heard at once
const VOICE_SWAP := 10.0      # m: a farther car's engine takes over only when it is this much nearer
const BUMP_MIN := 1.5         # m/s: the slowest contact heard

## The field level (an AI level id) and its AI drivers.
var field_level := ""
var lineup: Array = []
var nets: Array = []
var field: FieldRace = null
var ai_models: Array[CarModel] = []
var ai_audio: Array[CarAudio] = []
var podium: Podium = null
var podium_on := false
## The HUD's last field block and the finish panel's rows (tests).
var board: Dictionary = {}
## Script time of the AI cars' sound (µs, summed) and frames (the e2e perf check).
var voice_usec := 0
var voice_frames := 0
var _ai_prev: Array = []
var _since_finish := -1.0
var _voiced: Array = []


func setup(p_app: GameApp, opts: Dictionary) -> void:
	var o := opts.duplicate()
	o.erase("level")
	o.erase("ghost")
	o.driver = "human"
	super.setup(p_app, o)
	name = "FieldMode"
	field_level = str(opts.get("field", "")) if Opponents.rank(str(opts.get("field", ""))) >= 0 else "pro"
	lineup = opts.get("lineup", [])
	nets = opts.get("nets", [])
	uses_pb = false


func enter() -> void:
	for k in lineup.size():
		var e: Dictionary = lineup[k]
		var m := CarModel.new(String(e.car), {"color": Color(String(e.color))})
		m.name = "FieldCar%d" % k
		app.world.add_child(m)
		ai_models.append(m)
		var a := CarAudio.new(app.audio, String(e.car), {"positional": true, "level": 0.5})
		m.add_child(a)
		ai_audio.append(a)
		_ai_prev.append({})
	super.enter()


func exit() -> void:
	for a: CarAudio in ai_audio:
		if is_instance_valid(a):
			a.silence()
	for n: Node in ai_models:
		if is_instance_valid(n):
			n.queue_free()
	if podium != null and is_instance_valid(podium):
		podium.queue_free()
	super.exit()


func _mode_text(cname: String) -> String:
	return "%s FIELD · %s · %s" % [Opponents.level_name(field_level).to_upper(), track.name, cname]


## The field's drivers and every car on its grid slot (your car on the last one).
func _place_start() -> void:
	var drivers: Array = []
	for k in lineup.size():
		drivers.append(AiLink.driver(nets[k], float(lineup[k].cap)))
	field = FieldRace.new(track, lineup, drivers, car, race, {"name": "You", "code": "YOU",
		"color": Color(str(car_def.get("look", {}).get("color", "#d7263d")))})
	_since_finish = -1.0
	board = {}
	_voiced = []
	_podium_off()
	for k in ai_models.size():
		ai_models[k].reset_effects()
		ai_models[k].visible = true
		_ai_prev[k] = {}
		ai_audio[k].reset()


func respawn(standing: bool = false) -> void:
	super.respawn(standing)
	field.respawned(field.player_index)


func _race_step(dt: float) -> void:
	race_step += 1
	var c: Car.Controls = roll_out(car, track, _coast) if phase == "finished" else _drive(dt)
	var events := field.step(dt, c)
	if phase == "race":
		if score != null:
			_add_score_events(score.update(car, race, dt))
		if rec != null:
			rec.add(race_step, car, race.finished)
		for ev: Dictionary in events:
			_on_gate(ev)
	_bumps()
	# an AI car put back on the road this step is drawn there at once
	for k in lineup.size():
		if field.racers[k].respawn_step == field.steps:
			_store_pose(_ai_prev[k], field.racers[k].car)


## The contacts of this step, heard where they happened.
func _bumps() -> void:
	for h: CarContact.Hit in field.hits:
		if h.speed >= BUMP_MIN:
			app.audio.play_at("hit_medium" if h.speed > 6.0 else "hit_light", Vector3(h.x, car.y + 0.5, h.z))


func update(dt: float) -> void:
	super.update(dt)
	if phase != "finished" or field == null:
		return
	_since_finish += minf(dt, 0.1)
	if not podium_on and _since_finish >= PODIUM_AT:
		_podium_on()
	if podium_on:
		# the AI still racing finish, a few steps a frame, out of sight
		var t0 := Time.get_ticks_usec()
		var coast := Car.Controls.new()
		while not field.all_done() and Time.get_ticks_usec() - t0 < FAST_USEC:
			field.step(STEP, roll_out(car, track, coast))
		_fill_podium()
	if not finish_state.is_empty():
		_refresh_results()


func _save_prev() -> void:
	super._save_prev()
	if field == null:
		return
	for k in lineup.size():
		_store_pose(_ai_prev[k], field.racers[k].car)


func _render_others(dt: float, alpha: float, _at: Vector3, cam: Vector3) -> void:
	if field == null:
		return
	if podium_on:
		return
	for k in lineup.size():
		var m := ai_models[k]
		m.update(field.racers[k].car, _ai_prev[k] if not (_ai_prev[k] as Dictionary).is_empty() else null, alpha, dt, track)
	_voices(dt, cam)


## The AI engines: only the VOICES nearest the camera are heard (a farther car takes over a voice
## only when it is VOICE_SWAP m nearer than the one it replaces).
func _voices(dt: float, cam: Vector3) -> void:
	var n := lineup.size()
	var dist: Array = []
	for k in n:
		var c: Car = field.racers[k].car
		dist.append(Vector3(c.x, c.y, c.z).distance_to(cam))
	var keep: Array = _voiced.filter(func(k: int) -> bool: return k < n)
	var order: Array = range(n)
	order.sort_custom(func(a: int, b: int) -> bool: return float(dist[a]) < float(dist[b]))
	for k: int in order:
		if keep.has(k):
			continue
		if keep.size() < VOICES:
			keep.append(k)
			continue
		var worst := -1
		for v: int in keep:
			if worst < 0 or float(dist[v]) > float(dist[worst]):
				worst = v
		if float(dist[k]) + VOICE_SWAP < float(dist[worst]):
			keep.erase(worst)
			keep.append(k)
	_voiced = keep
	var t0 := Time.get_ticks_usec()
	for k in n:
		var a := ai_audio[k]
		a.set_active(keep.has(k))
		if a.active:
			a.update(field.racers[k].car, track, dt)
	voice_usec += Time.get_ticks_usec() - t0
	voice_frames += 1


func _grime_ahead(view: CarEffects.Pose) -> Vector2:
	var out := Vector2.ZERO
	if podium_on:
		return out
	for m in ai_models:
		var a := ScreenGrime.ahead_of(view, m.pose, track)
		out = Vector2(maxf(out.x, a.x), maxf(out.y, a.y))
	return out


func _hud_extra(s: Dictionary) -> void:
	if field == null:
		return
	board = field.board(field.player_index)
	s.field = board


func render(dt: float, alpha: float) -> void:
	if podium_on:
		podium.update(dt)
		_render_hud(dt)
		return
	super.render(dt, alpha)


# ---------------------------------------------------------------- the finish

func _finish_payout(t: float, s: Dictionary) -> Dictionary:
	var place := field.position(field.player_index)
	var medal := Medals.medal_for(medals, t)
	var p := Economy.claim(track.id, car_def.id, medal, "", field_level, place)
	p.medal = medal
	p.level = ""
	p.won = place == 1
	p.field = field_level
	p.place = place
	s.dock = "right"
	s.field = _field_state(place)
	return p


func _field_state(place: int) -> Dictionary:
	return {"place": place, "of": field.racers.size(), "level": Opponents.level_name(field_level), "rows": field.results()}


## The standings on the finish panel as the AI finish (the panel is rebuilt only when a time comes in).
func _refresh_results() -> void:
	var f: Dictionary = finish_state.get("field", {})
	if f.is_empty():
		return
	var done := 0
	for r: Dictionary in field.results():
		if is_finite(float(r.time)) or bool(r.dnf):
			done += 1
	var had := 0
	for r: Dictionary in f.get("rows", []):
		if is_finite(float(r.time)) or bool(r.dnf):
			had += 1
	if done != had:
		finish_state.field = _field_state(int(f.place))
		app.ui.hud.show_panel(finish_state)


## The podium on the start straight (the grid's stretch); the race's cars out of sight, the top three
## put on it as their places are known (_fill_podium).
func _podium_on() -> void:
	if podium == null:
		var i := track.start_idx + roundi(2.0 * Field.SLOT_GAP / track.seg_len)
		podium = Podium.new(track, track.wrap(i) if track.closed else mini(i, track.count - 2))
		app.world.add_child(podium)
	podium.visible = true
	podium.clear()
	podium_on = true
	for m in ai_models:
		m.visible = false
	model.visible = false
	_fill_podium()
	for a: CarAudio in ai_audio:
		a.set_active(false)
	if car_audio != null:
		car_audio.set_active(false)
	if grime != null:
		grime.clear()
	podium.camera.make_current()


## Put each car whose podium place is final (it finished, and so did everyone ahead of it) on its block.
func _fill_podium() -> void:
	var order := field.standings()
	for k in mini(3, order.size()):
		var i: int = order[k]
		var r: FieldRace.Racer = field.racers[i]
		if not r.race.finished:
			return
		if podium.has(k + 1):
			continue
		var m: CarModel = model if r.player else ai_models[i]
		podium.put(k + 1, m, field.name_of(i), field.color_of(i))
		m.celebrate()


func _podium_off() -> void:
	if not podium_on:
		return
	podium_on = false
	if podium != null:
		podium.visible = false
	model.visible = true
	for m in ai_models:
		m.visible = true
	if car_audio != null:
		car_audio.set_active(true)
	camera.make_current()
