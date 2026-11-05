class_name GameAudio
extends Node
## game_audio.gd (v6.12.0): the game's sound: buses, volumes, pooled players, music.
## ------------------------------------------------------------------
## One per game (GameApp.audio). It makes the buses (setup_buses: Music, SFX and Engine under
## Master, with a hard limiter on Master so a loud moment never clips), applies the volume
## settings (vol_master, vol_music, vol_sfx, vol_engine: 0..1, amplitude = value², 0 = off) and
## mutes everything while the window is in the background ("mute_unfocused", on by default).
##
## Sound effects (audio/sound_bank.gd SFX) play from pools of players made once: play(name)
## non-positional (the interface, race cues, the player's own car), play_at(name, position) in 3D
## (another car: its distance and side). Each name has a level, a random pitch spread, a
## shortest gap between two plays and a voice limit (the oldest stops). Loops for the cars are
## made by audio/car_audio.gd with loop_stream(name).
##
## Music: music(name) cross-fades to a loop (SoundBank.MUSIC; "" stops it); duck(db) lowers it
## (the finish panel), music_level(db) sets the context's level (races play it a little lower).
##
## Headless (tests, tools, CI) it runs on Godot's dummy audio driver: everything plays and
## nothing is heard; nothing here prints. `history` keeps the last LOG_SIZE sounds played (tests).

const POOL_2D := 14
const POOL_3D := 8
const LOG_SIZE := 96
const FADE := 1.2            # s, music cross-fade
const SILENT := -80.0
## Settings: key -> bus.
const VOLUMES := {"vol_master": "Master", "vol_music": "Music", "vol_sfx": "SFX", "vol_engine": "Engine"}
## The limiter on Master: ceiling (dB) and release (s).
const LIMIT_DB := -0.5
const LIMIT_RELEASE := 0.08

## Sounds played: [[name, msec, opts, process frame]] (tests read it; the e2e audio run lines the
## frame up with what it recorded).
var history: Array = []
## How many sounds were played in all (history keeps the last LOG_SIZE; sounds_since() reads it).
var total := 0
## The music playing ("" none) and the ducking now (dB, 0 none).
var music_name := ""
var duck_db := 0.0
var music_db := 0.0
## False while the window is in the background.
var focused := true

var _streams := {}          # file -> AudioStream
var _pool: Array[AudioStreamPlayer] = []
var _pool3: Array[AudioStreamPlayer3D] = []
var _started := {}          # player -> msec it started (voice stealing)
var _owner := {}            # player -> sound name
var _last := {}             # name -> msec last played
var _music: Array[AudioStreamPlayer] = []
var _music_now := 0         # which of the two music players is the current one
var _fade := [0.0, 0.0]     # the players' fade levels (0..1)
var _duck_now := 0.0
var _queue: Array = []      # [[s left, name, opts]]


func _init() -> void:
	name = "GameAudio"
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	setup_buses()
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.name = "Sfx%d" % i
		add_child(p)
		_pool.append(p)
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.name = "Sfx3D%d" % i
		p.unit_size = 12.0
		p.max_distance = 260.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(p)
		_pool3.append(p)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.name = "Music%d" % i
		m.bus = "Music"
		m.volume_db = SILENT
		add_child(m)
		_music.append(m)
	apply_settings()


## Make the buses once: Music, SFX and Engine sending to Master, a hard limiter on Master.
## Safe to call again (and from tests without a game).
static func setup_buses() -> void:
	for b: String in SoundBank.BUSES:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
	var m := AudioServer.get_bus_index("Master")
	for k in AudioServer.get_bus_effect_count(m):
		if AudioServer.get_bus_effect(m, k) is AudioEffectHardLimiter:
			return
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = LIMIT_DB
	lim.release = LIMIT_RELEASE
	lim.pre_gain_db = 0.0
	AudioServer.add_bus_effect(m, lim)


## A volume setting (0..1) as dB: amplitude value² (half way is -12 dB), 0 is silence.
static func volume_db(v: float) -> float:
	return SILENT if v <= 0.001 else maxf(SILENT, linear_to_db(v * v))


## Apply the volume settings and the background mute (the Settings screen calls this on a change).
func apply_settings() -> void:
	setup_buses()
	for key: String in VOLUMES:
		var i := AudioServer.get_bus_index(VOLUMES[key])
		var v := float(UiData.get_setting(key))
		AudioServer.set_bus_volume_db(i, volume_db(v))
		AudioServer.set_bus_mute(i, v <= 0.001)
	_apply_mute()


func _apply_mute() -> void:
	var m := AudioServer.get_bus_index("Master")
	var off := float(UiData.get_setting("vol_master")) <= 0.001
	AudioServer.set_bus_mute(m, off or (not focused and bool(UiData.get_setting("mute_unfocused"))))


## True when nothing is heard because the window is in the background.
func muted_in_background() -> bool:
	return not focused and bool(UiData.get_setting("mute_unfocused"))


## The window came to the front (true) or went to the background (false).
func set_focused(on: bool) -> void:
	focused = on
	_apply_mute()


# ---------------------------------------------------------------- streams

## The stream of a sound file (cached): `file` without its folder and extension.
func stream(file: String) -> AudioStream:
	if _streams.has(file):
		return _streams[file]
	var path := SoundBank.sfx_path(file)
	var s: AudioStream = load(path) if ResourceLoader.exists(path) else null
	_streams[file] = s
	return s


## The (looping) stream of loop sound `name` (car_audio.gd's players), or null.
func loop_stream(name_: String) -> AudioStream:
	var d := SoundBank.sfx(name_)
	if d.is_empty():
		return null
	var s := stream(String(d.files[0]))
	if s is AudioStreamWAV and (s as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(round(w.get_length() * w.mix_rate))
	return s


# ---------------------------------------------------------------- effects

## Play sound `name` (SoundBank.SFX) non-positional. opts: db (added), pitch (× the random pitch),
## bus. Returns the player, or null (unknown, too soon after the last one, no file).
func play(name_: String, opts: Dictionary = {}) -> AudioStreamPlayer:
	var d := _ready_to_play(name_, opts)
	if d.is_empty():
		return null
	var p := _take(_pool, name_, int(d.voices)) as AudioStreamPlayer
	p.stream = d.stream
	p.bus = String(opts.get("bus", d.bus))
	p.volume_db = float(d.db) + float(opts.get("db", 0.0))
	p.pitch_scale = d.pitch_now
	p.play()
	return p


## The interface's sounds (UiSound.player): play(name).
func play_ui(name_: String) -> void:
	play(name_)


## Play sound `name` after `delay` seconds (the finish's stingers, one after another). Cleared by
## clear_queue() (a restart, leaving the race).
func play_after(name_: String, delay: float, opts: Dictionary = {}) -> void:
	_queue.append([maxf(0.0, delay), name_, opts])


## The sounds waiting to be played: [[seconds left, name, opts]] (tests).
func queued() -> Array:
	return _queue


func clear_queue() -> void:
	_queue.clear()


## Play sound `name` at world position `at` (another car's hit, ...). Same opts as play().
func play_at(name_: String, at: Vector3, opts: Dictionary = {}) -> AudioStreamPlayer3D:
	var d := _ready_to_play(name_, opts)
	if d.is_empty():
		return null
	var p := _take(_pool3, name_, int(d.voices)) as AudioStreamPlayer3D
	p.stream = d.stream
	p.bus = String(opts.get("bus", d.bus))
	p.volume_db = float(d.db) + float(opts.get("db", 0.0))
	p.pitch_scale = d.pitch_now
	p.global_position = at if p.is_inside_tree() else Vector3.ZERO
	p.play()
	return p


func _ready_to_play(name_: String, opts: Dictionary) -> Dictionary:
	var d := SoundBank.sfx(name_)
	if d.is_empty():
		return {}
	var now := Time.get_ticks_msec()
	if float(d.gap) > 0.0 and now - int(_last.get(name_, -1000000)) < int(float(d.gap) * 1000.0):
		return {}
	var files: Array = d.files
	var s := stream(String(files[randi() % files.size()]))
	if s == null:
		return {}
	_last[name_] = now
	d.stream = s
	var pr := float(d.pitch)
	d.pitch_now = maxf(0.05, float(opts.get("pitch", 1.0)) * (1.0 + randf_range(-pr, pr)))
	history.append([name_, now, opts, Engine.get_process_frames()])
	total += 1
	if history.size() > LOG_SIZE:
		history = history.slice(history.size() - LOG_SIZE)
	return d


## A free player of `pool` for sound `name`: the oldest of its own voices beyond `voices`, else a
## free one, else the one that started first.
func _take(pool: Array, name_: String, voices: int) -> Node:
	var mine: Array = []
	var free_p: Node = null
	var oldest: Node = null
	for p: Node in pool:
		var playing: bool = p.playing
		if playing and _owner.get(p, "") == name_:
			mine.append(p)
		if not playing and free_p == null:
			free_p = p
		if oldest == null or int(_started.get(p, 0)) < int(_started.get(oldest, 0)):
			oldest = p
	var pick: Node = free_p if free_p != null else oldest
	if mine.size() >= voices:
		mine.sort_custom(func(a: Node, b: Node) -> bool: return int(_started.get(a, 0)) < int(_started.get(b, 0)))
		pick = mine[0]
	pick.stop()
	_owner[pick] = name_
	_started[pick] = Time.get_ticks_usec()
	return pick


## The names of the sounds played since `total` was `n` (tests: n = total before, then this).
func sounds_since(n: int) -> PackedStringArray:
	var out := PackedStringArray()
	var k := mini(total - n, history.size())
	for i in range(history.size() - k, history.size()):
		out.append(str(history[i][0]))
	return out


## How many times sound `name` was played since `since_msec` (tests).
func played(name_: String, since_msec: int = 0) -> int:
	var n := 0
	for e: Array in history:
		if e[0] == name_ and int(e[1]) >= since_msec:
			n += 1
	return n


## Stop every pooled effect and drop the queued ones (leaving a race).
func stop_effects() -> void:
	_queue.clear()
	for p in _pool:
		p.stop()
	for p in _pool3:
		p.stop()


## Stop everything at once (the game is quitting): the effects, the queue, both music players and
## every car's sound (the CarAudio nodes in the "car_audio" group). The audio thread lets go of a
## stopped sound on its next mix, so a caller that quits on purpose (the end-to-end runs) lets a few
## frames pass after this.
func shutdown() -> void:
	stop_effects()
	for p in _music:
		p.stop()
	music_name = ""
	if is_inside_tree():
		get_tree().call_group(CarAudio.GROUP, "silence")


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		set_focused(false)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		set_focused(true)
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		shutdown()


# ---------------------------------------------------------------- music

## Cross-fade to music `name` (SoundBank.MUSIC; "" fades out). The same name keeps playing.
func music(name_: String) -> void:
	if name_ == music_name:
		return
	music_name = name_
	var old := _music_now
	_music_now = 1 - _music_now
	var p := _music[_music_now]
	p.stop()
	p.stream = null
	var path := SoundBank.music_path(name_) if name_ != "" else ""
	if path != "" and SoundBank.MUSIC.has(name_) and ResourceLoader.exists(path):
		var s: AudioStream = load(path)
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
		p.stream = s
		_fade[_music_now] = 0.0
		p.volume_db = SILENT
		p.play()
	_fade[old] = minf(_fade[old], 1.0)


## Lower the music by `db` (a negative number; 0: back to normal), gliding there.
func duck(db_: float) -> void:
	duck_db = db_


## The music's level for the context (dB: races -3).
func music_level(db_: float) -> void:
	music_db = db_


func _process(dt: float) -> void:
	_step_music(minf(dt, 0.1))
	step_queue(minf(dt, 0.1))


## Count down the queued sounds by `dt` and play the ones that are due.
func step_queue(dt: float) -> void:
	if _queue.is_empty():
		return
	var keep: Array = []
	for q: Array in _queue:
		q[0] = float(q[0]) - dt
		if float(q[0]) <= 0.0:
			play(String(q[1]), q[2])
		else:
			keep.append(q)
	_queue = keep


## Fades and ducking, one frame of `dt` seconds (the game calls it through _process).
func _step_music(dt: float) -> void:
	var k := dt / FADE
	_duck_now += (duck_db - _duck_now) * minf(1.0, dt * 3.0)
	for i in 2:
		var p := _music[i]
		if i == _music_now and p.stream != null:
			_fade[i] = minf(1.0, _fade[i] + k)
		else:
			_fade[i] = maxf(0.0, _fade[i] - k)
			if _fade[i] <= 0.0 and p.playing:
				p.stop()
		var f: float = _fade[i]
		p.volume_db = SILENT if f <= 0.0 else linear_to_db(f) + music_db + _duck_now



## The music's level now (dB, the playing player's), for tests.
func music_volume_db() -> float:
	return _music[_music_now].volume_db
