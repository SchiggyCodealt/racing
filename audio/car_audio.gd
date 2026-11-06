class_name CarAudio
extends Node3D
## car_audio.gd (v6.12.0): the sounds of one car, driven by its sim state every frame.
## ------------------------------------------------------------------
## The engine (audio/engine_voice.gd, synthesized live into an AudioStreamGenerator on the Engine
## bus), and on the SFX bus: tyre squeal on asphalt (from the sim's slip), gravel crunch on dirt and
## crunching snow on snow (the surface under the car × speed × slip), road roar and wind with speed,
## a scrape along a wall, the nitro's rush; one-shots for wall hits (by the speed into the wall),
## landings (by the speed onto the road), the nitro lighting and the turbo's blow-off on a lift.
##
## The player's car (or the watched AI's) is heard non-positional, at full level. Another car (the
## AI opponent you race, opts.positional) is a quieter 3D sound at its place: this node follows the
## car model it is a child of (play_mode.gd adds it), and the chase camera is the listener. The
## best-run ghost is silent: it is your own car on the same line, and two of the same engine on top
## of each other only blur it.
##
## Use: var a := CarAudio.new(app.audio, "thunder", {positional = false}); model.add_child(a)
##      every frame: a.update(car, track, dt)      after a restart / respawn: a.reset()
## `usec` adds up the script time spent here (the e2e perf run reports it).

## Loops and their bus. Each gets a player when first needed.
const LOOPS := ["road", "wind", "tyre_squeal", "gravel", "snow", "scrape", "nitro"]
const ENGINE_RATE := 24000.0      # the player's engine voice (Hz)
const ENGINE_RATE_3D := 16000.0   # another car's
const BUFFER := 0.25              # s, the generator's buffer
## How far ahead of the audio the engine is rendered (s): enough for an uneven frame, little lag.
const LEAD_MIN := 0.05
const LEAD_MAX := 0.12
## Wall hits: speed into the wall (m/s) for each size, and the quietest hit heard.
const HIT_MIN := 1.5
const HIT_MEDIUM := 5.0
const HIT_HEAVY := 11.0
const LAND_MIN := 2.5             # m/s down onto the road for a landing thump
const REV_SHARE := 0.72           # the countdown's free rev: this share of the rev range at full throttle
const GROUP := "car_audio"        # every CarAudio in the tree (GameAudio.shutdown() silences them)

var audio: GameAudio
var car_id := "racer"
var positional := false
## Overall level 0..1 (the AI opponent's car: 0.6).
var level := 1.0
## After silence(): nothing plays any more.
var silenced := false
## (v6.13) False while the car is not heard for now (set_active: a field race keeps the nearest few AI
## engines on): nothing plays and update() does nothing.
var active := true
var engine: EngineVoice
## Script time spent in update() (µs, summed), how many updates and engine samples rendered.
var usec := 0
var updates := 0
var samples := 0
## What was triggered (tests): name -> count.
var events := {}
## The loops' current levels (0..1, tests).
var levels := {}

var _engine_player: Node = null
var _gen: AudioStreamGeneratorPlayback = null
var _cap := 0               # frames the generator's ring buffer holds (a power of two, more than BUFFER)
var _loops := {}            # name -> player
var _quiet := {}            # name -> s spent silent (the loop stops after a while)
var _first := true
var _hits := 0
var _touching := false
var _vx := 0.0
var _vz := 0.0
var _x := 0.0
var _z := 0.0
var _air := false
var _air_vy := 0.0
var _air_t := 0.0
var _boosting := false
var _load := 0.0
var _scrape := 0.0
var _rev_rpm := 1000.0


func _init(p_audio: GameAudio = null, p_car_id: String = "racer", opts: Dictionary = {}) -> void:
	audio = p_audio
	car_id = p_car_id
	positional = bool(opts.get("positional", false))
	level = float(opts.get("level", 0.6 if positional else 1.0))
	name = "CarAudio"
	engine = EngineVoice.new(car_id, ENGINE_RATE_3D if positional else ENGINE_RATE)


func _ready() -> void:
	add_to_group(GROUP)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = engine.mix_rate
	gen.buffer_length = BUFFER
	_engine_player = _make_player("Engine")
	_engine_player.set("stream", gen)
	_engine_player.set("volume_db", linear_to_db(level))
	_engine_player.call("play")
	_gen = _engine_player.call("get_stream_playback") as AudioStreamGeneratorPlayback
	# empty now: what is free is the whole ring (8191 frames for 0.25 s at 24 kHz, not 6000), so what
	# is queued later is this less what is free
	_cap = _gen.get_frames_available()


func _make_player(bus: String) -> Node:
	var p: Node
	if positional:
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = 10.0
		p3.max_db = -3.0
		p3.max_distance = 300.0
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		p = p3
	else:
		p = AudioStreamPlayer.new()
	p.set("bus", bus)
	add_child(p)
	return p


## After a restart or a respawn: no glide from the old rpm, no hit or landing from the jump.
func reset() -> void:
	engine.reset()
	_first = true


## Silence the car for good (its mode is leaving, or the game is quitting): the engine and every
## loop stop, and later updates play nothing (they would start the loops again).
func silence() -> void:
	silenced = true
	if _engine_player != null:
		_engine_player.call("stop")
	for n: String in _loops:
		(_loops[n] as Node).call("stop")


## (v6.13) Hear the car (on) or not for now (off: its engine and loops stop at once and update() skips
## it; on: the engine starts again from the car's state). The field race (modes/field_mode.gd) turns
## the farthest AI cars off to keep the sound's script time down.
func set_active(on: bool) -> void:
	if on == active or silenced:
		return
	active = on
	if not on:
		if _engine_player != null:
			_engine_player.call("stop")
		for n: String in _loops:
			(_loops[n] as Node).call("stop")
		levels.clear()
		_quiet.clear()
		return
	if _engine_player != null and _engine_player.is_inside_tree():
		_engine_player.call("play")
		_gen = _engine_player.call("get_stream_playback") as AudioStreamGeneratorPlayback
		_cap = _gen.get_frames_available() if _gen != null else 0
	reset()


## One frame: `car` is the sim's car after the last physics step, `dt` the frame time. `rev` 0..1:
## the countdown's free rev (the throttle held before GO; -1 = none, the car drives).
func update(car: Car, track: BuiltTrack, dt: float, rev: float = -1.0) -> void:
	if silenced or not active:
		return
	var t0 := Time.get_ticks_usec()
	dt = clampf(dt, 0.0, 0.1)
	var jump := (car.x - _x) * (car.x - _x) + (car.z - _z) * (car.z - _z) > 400.0
	if _first or jump:
		engine.reset()
		_hits = car.wall_hits
		_air = not car.grounded
		_air_vy = 0.0
		_boosting = car.boosting
		_touching = car.hit_wall
	# ---- the engine ----
	engine.follow(car)
	if rev >= 0.0:
		# standing on the grid: the throttle revs the engine (out of gear, no load on the wheels)
		var idle := car.spec.idle_rpm
		var to := idle + clampf(rev, 0.0, 1.0) * REV_SHARE * (car.spec.redline - idle)
		_rev_rpm += (to - _rev_rpm) * minf(1.0, dt * (6.0 if to > _rev_rpm else 3.0))
		engine.rpm = _rev_rpm
		engine.throttle = rev
		engine.load = rev
		engine.limiter = false
	else:
		_rev_rpm = car.rpm
	engine.level = 1.0
	_feed_engine(dt)
	# ---- events ----
	if not _first and not jump:
		_events(car)
	# ---- loops ----
	var asphalt := 1.0
	var dust := 0.0
	var snow := 0.0
	var loose := loose_at(track, car.idx)
	dust = loose.x
	snow = loose.y
	asphalt = maxf(0.0, 1.0 - dust - snow)
	var sp := car.speed
	var on := 1.0 if car.grounded else 0.0
	var slip := car.slip
	var squeal := on * asphalt * clampf((slip - 0.18) / 0.55, 0.0, 1.0) * clampf((sp - 3.0) / 8.0, 0.0, 1.0)
	var roll := clampf(sp / 30.0, 0.0, 1.0)
	_scrape = maxf(clampf(car.wall_scrape / 22.0, 0.0, 1.0) if car.hit_wall else 0.0, _scrape - dt * 6.0)
	_set_loop("tyre_squeal", 0.9 * squeal, 0.88 + 0.22 * slip + 0.06 * clampf(sp / 60.0, 0.0, 1.0), dt)
	_set_loop("gravel", on * dust * pow(roll, 0.7) * (0.55 + 0.6 * slip), 0.75 + 0.45 * clampf(sp / 45.0, 0.0, 1.2), dt)
	_set_loop("snow", on * snow * pow(roll, 0.7) * (0.55 + 0.6 * slip), 0.8 + 0.35 * clampf(sp / 45.0, 0.0, 1.2), dt)
	_set_loop("road", on * asphalt * 0.45 * clampf(sp / 55.0, 0.0, 1.0), 0.7 + 0.6 * clampf(sp / 80.0, 0.0, 1.0), dt)
	_set_loop("wind", 0.75 * pow(clampf((sp - 6.0) / 75.0, 0.0, 1.0), 1.4), 0.8 + 0.5 * clampf(sp / 90.0, 0.0, 1.0), dt)
	_set_loop("scrape", _scrape, 0.8 + 0.4 * clampf(car.wall_scrape / 40.0, 0.0, 1.0), dt)
	_set_loop("nitro", 0.8 * car.boost, 0.95 + 0.1 * clampf(sp / 80.0, 0.0, 1.0), dt)
	_first = false
	_x = car.x
	_z = car.z
	_vx = car.vx
	_vz = car.vz
	updates += 1
	usec += Time.get_ticks_usec() - t0


## Seconds of engine sound rendered and not yet played (0 without a generator).
func queued() -> float:
	if _gen == null:
		return 0.0
	return float(_cap - _gen.get_frames_available()) / engine.mix_rate


## How many times the audio found the engine's buffer empty (a gap) since it started.
func skips() -> int:
	return _gen.get_skips() if _gen != null else 0


## Render the engine ahead of what the audio has played (enough for an uneven frame).
func _feed_engine(dt: float) -> void:
	if _gen == null:
		return
	var rate := engine.mix_rate
	var free := _gen.get_frames_available()
	var have := _cap - free
	var want := int(clampf(dt * 2.5, LEAD_MIN, LEAD_MAX) * rate)
	var n := mini(want - have, free)
	if n > 0:
		_gen.push_buffer(engine.render(n))
		samples += n


func _events(car: Car) -> void:
	# a wall hit: new contact steps; the speed into the wall (from the last frame's velocity when
	# the hit fell on a step in between)
	var steps := car.wall_hits - _hits
	if steps > 0 and steps < 60:
		var imp := car.wall_impact
		if not _touching:
			imp = maxf(imp, -(_vx * car.wall_nx + _vz * car.wall_nz))
		if imp >= HIT_MIN:
			var nm := "hit_heavy" if imp >= HIT_HEAVY else ("hit_medium" if imp >= HIT_MEDIUM else "hit_light")
			var lo := HIT_MIN if nm == "hit_light" else (HIT_MEDIUM if nm == "hit_medium" else HIT_HEAVY)
			var hi := HIT_MEDIUM if nm == "hit_light" else (HIT_HEAVY if nm == "hit_medium" else 25.0)
			_shot(nm, -9.0 + 9.0 * clampf((imp - lo) / (hi - lo), 0.0, 1.0))
	_hits = car.wall_hits
	_touching = car.hit_wall
	# a landing
	if not car.grounded:
		if not _air:
			_air_t = 0.0
		_air = true
		_air_vy = car.vy
		_air_t += 1.0 / 60.0
	elif _air:
		_air = false
		var down := -_air_vy
		if down >= LAND_MIN:
			_shot("land", -14.0 + 14.0 * clampf((down - LAND_MIN) / 9.0, 0.0, 1.0))
	# the nitro lights
	if car.boosting and not _boosting:
		_shot("nitro_on", 0.0)
	_boosting = car.boosting
	# the turbo's blow-off on a lift
	if float(engine.character.get("turbo", 0.0)) > 0.0 and _load > 0.5 and engine.load < 0.1 and engine.spool > 0.45:
		_shot("blowoff", -12.0 + 10.0 * engine.spool)
	_load = engine.load


func _shot(nm: String, db_: float) -> void:
	events[nm] = int(events.get(nm, 0)) + 1
	if audio == null:
		return
	var o := {"db": db_ + linear_to_db(maxf(level, 0.001))}
	if positional:
		audio.play_at(nm, global_position if is_inside_tree() else Vector3.ZERO, o)
	else:
		audio.play(nm, o)


## Set loop `nm` to level `v` (0..1) and pitch `pitch`, smoothly; it starts and stops on demand.
func _set_loop(nm: String, v: float, pitch: float, dt: float) -> void:
	var cur := float(levels.get(nm, 0.0))
	var k := minf(1.0, dt * (14.0 if v > cur else 7.0))
	cur += (v * level - cur) * k
	levels[nm] = cur
	var p: Node = _loops.get(nm)
	if cur < 0.003:
		_quiet[nm] = float(_quiet.get(nm, 0.0)) + dt
		if p != null and bool(p.get("playing")) and float(_quiet[nm]) > 0.4:
			p.call("stop")
		return
	_quiet[nm] = 0.0
	if p == null:
		if audio == null:
			return
		var s := audio.loop_stream(nm)
		if s == null:
			return
		p = _make_player("SFX")
		p.set("stream", s)
		_loops[nm] = p
	p.set("volume_db", linear_to_db(cur))
	p.set("pitch_scale", clampf(pitch, 0.3, 3.0))
	if not bool(p.get("playing")):
		var len_s := float((p.get("stream") as AudioStream).get_length())
		p.call("play", randf() * maxf(0.0, len_s - 0.05))


## The loose ground at sample `idx` of `track`: Vector2(dirt-like share, snow share).
static func loose_at(track: BuiltTrack, idx: int) -> Vector2:
	if track == null or track.surf_w.is_empty() or idx < 0:
		return Vector2.ZERO
	var n := track.surf_n
	var i := clampi(idx, 0, track.count - 1)
	var out := Vector2.ZERO
	for s in n:
		var w := track.surf_w[i * n + s]
		var kind: String = Surfaces.def(s).dust
		if kind == "dust":
			out.x += w
		elif kind == "snow":
			out.y += w
	return out
