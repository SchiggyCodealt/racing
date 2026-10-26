class_name Replay
extends RefCounted
## replay.gd: ghost runs, a port of web/src/game/replay.js: the player's race
## recorded as sampled poses, packed small for the save file and played back on
## the race clock. Pure logic (no Nodes).
## ------------------------------------------------------------------
## Poses, not inputs: poses replay the same whatever later tuning does to the physics.
##   - a sample every GHOST_EVERY physics steps (30 Hz), one at the finish, two
##     around each landing or wall hit (the path bends within a step), and one on
##     each side of a respawn (two samples at the same step = a jump, never
##     interpolated across);
##   - per sample: position and height (1 cm), yaw, pitch and roll (1 mrad), front
##     wheel angle (2 mrad) and forward speed (0.1 m/s), each stored as its
##     difference from a prediction (position, height, yaw: last value + last
##     change; the rest: the last value) as a zigzag varint, plus the step gap
##     (about 9 bytes a sample) - the same bytes as the web game's format 2;
##   - the nitro changes (step gap, new amount in tenths) as varints too.
## Godot format (GHOST_FORMAT 3): those bytes as base64 text in the JSON save file
## (the web game wrote them 15 bits a character into localStorage; browser
## ghosts are not carried over). Playback interpolates linearly between samples.
## Timing: sample n is the pose after physics step n since GO (race time n / 60 s).
##
##   var rec := Replay.GhostRecorder.new()
##   rec.add(step, car)                  after every physics step (step 1, 2, ... since GO)
##   rec.before_jump(step, car); car.place(...); rec.after_jump(step, car)   on a respawn
##   var saved := Replay.pack_ghost(rec, {track = track, laps = 3, time = race.finish_time, car = "racer"})
##   var ghost := Replay.unpack_ghost(saved, track, laps[, car_id])   # {} when it doesn't fit / decode
##   var player := Replay.GhostPlayer.new(ghost); player.pose(step_f)  # moves player.car (a Car used as a pose)
##   Replay.ghost_fits(saved, track, laps[, car_id]), Replay.ghost_car_of(saved), Replay.track_signature(track)

const GHOST_FORMAT: int = 3 # Godot: base64 of the format 2 bytes (web: 1 base64, 2 15-bit text)
const GHOST_EVERY: int = 2 # physics steps per sample (60 Hz / 2 = 30 Hz)
const GHOST_MAX_STEPS: int = 60 * 60 * 15 # runs longer than 15 minutes are not kept

# Channels: x, z, y (m), yaw (unwrapped), pitch, roll, steer angle (rad), forward speed (m/s).
const CH: int = 8
const SCALE: Array[float] = [100.0, 100.0, 100.0, 1000.0, 1000.0, 1000.0, 500.0, 10.0]
const ORDER2: Array[bool] = [true, true, true, true, false, false, false, false] # predict with the last change too
const WALL_KINK: float = 0.3 # m/s into a wall removed in one step: keep the samples around it


static func _wrap_angle(a: float) -> float:
	return atan2(sin(a), cos(a))


static func _pose_of(car: Car, out: PackedFloat64Array) -> PackedFloat64Array:
	out[0] = car.x
	out[1] = car.z
	out[2] = car.y
	out[3] = car.yaw
	out[4] = car.pitch
	out[5] = car.roll
	out[6] = car.steer_angle
	out[7] = car.forward_speed
	return out


## Records one run. add() after every physics step; it keeps the samples it needs.
class GhostRecorder:
	var every: int = GHOST_EVERY
	var max_steps: int = GHOST_MAX_STEPS
	var steps: PackedInt32Array = PackedInt32Array()
	## CH numbers per sample
	var vals: PackedFloat64Array = PackedFloat64Array()
	## v4: the steps where the nitro amount (car.boost, in tenths) changed ...
	var boost_steps: PackedInt32Array = PackedInt32Array()
	## ... and the new amount (0..10)
	var boost_levels: PackedInt32Array = PackedInt32Array()
	var last_step: int = -1
	## ran past max_steps: this run can't become a ghost
	var full: bool = false
	var _boost: int = 0
	var _prev_step: int = -1
	var _grounded: bool = true
	var _pose: PackedFloat64Array = PackedFloat64Array()
	## the pose after the previous step, kept for a kink
	var _prev: PackedFloat64Array = PackedFloat64Array()

	func _init(every_steps: int = GHOST_EVERY, max_run_steps: int = GHOST_MAX_STEPS) -> void:
		every = every_steps
		max_steps = max_run_steps
		_pose.resize(CH)
		_prev.resize(CH)
		reset()

	func reset() -> void:
		steps = PackedInt32Array()
		vals = PackedFloat64Array()
		boost_steps = PackedInt32Array()
		boost_levels = PackedInt32Array()
		_boost = 0
		last_step = -1
		full = false
		_prev_step = -1
		_grounded = true

	func count() -> int:
		return steps.size()

	## The car's pose after physics step `step`: kept on the 30 Hz grid, or always with
	## `force`. A landing or a wall hit bends the path within one step, so the poses on
	## both sides of that step are kept.
	func add(step: int, car: Car, force: bool = false) -> void:
		if full:
			return
		if step > max_steps:
			full = true
			return
		var b: int = JsMath.roundi(maxf(0.0, minf(1.0, car.boost)) * 10.0)
		if b != _boost:
			boost_steps.append(step)
			boost_levels.append(b)
			_boost = b
		var kink: bool = last_step >= 0 and (car.grounded != _grounded or car.wall_impact > WALL_KINK)
		_grounded = car.grounded
		if kink and _prev_step > last_step:
			_push(_prev_step, _prev)
		var p: PackedFloat64Array = Replay._pose_of(car, _pose)
		if force or kink or (step % every == 0 and step != last_step):
			_push(step, p)
		_prev = p.duplicate()
		_prev_step = step

	## Call before a respawn moves the car (keeps its pose at this step) ...
	func before_jump(step: int, car: Car) -> void:
		if step > last_step:
			add(step, car, true)

	## ... and after it (the new pose at the same step).
	func after_jump(step: int, car: Car) -> void:
		_push(step, Replay._pose_of(car, _pose))
		_grounded = car.grounded

	func _push(step: int, p: PackedFloat64Array) -> void:
		var n: int = steps.size()
		# unwrapped yaw, so the stored differences stay small through full turns
		var last: float = vals[(n - 1) * CH + 3] if n else 0.0
		steps.append(step)
		vals.append(p[0])
		vals.append(p[1])
		vals.append(p[2])
		vals.append(last + Replay._wrap_angle(p[3] - last) if n else p[3])
		vals.append(p[4])
		vals.append(p[5])
		vals.append(p[6])
		vals.append(p[7])
		last_step = step


# ---- bytes ---------------------------------------------------------------------

## Unsigned varint (7 bits per byte, low first).
@warning_ignore("integer_division")
static func _put_uint(out: PackedByteArray, u: int) -> void:
	while u >= 128:
		out.append((u % 128) + 128)
		u = u / 128
	out.append(u)


## Zigzag varint.
static func _put_int(out: PackedByteArray, v: int) -> void:
	_put_uint(out, 2 * v if v >= 0 else -2 * v - 1)


## Reads varints from bytes; `ok` turns false on truncated or overlong data.
class _Reader:
	var a: PackedByteArray
	var i: int = 0
	var ok: bool = true

	func _init(bytes: PackedByteArray) -> void:
		a = bytes

	func uint() -> int:
		var u: int = 0
		var mul: int = 1
		for k in 7:
			if i >= a.size():
				ok = false
				return 0
			var b: int = a[i]
			i += 1
			u += (b & 127) * mul
			if b < 128:
				return u
			mul *= 128
		ok = false
		return 0

	@warning_ignore("integer_division")
	func sint() -> int:
		var u: int = uint()
		return -(u + 1) / 2 if u % 2 else u / 2

	func read_all() -> bool:
		return i == a.size()


## Short fingerprint of a track's layout, so a ghost of an edited track isn't replayed off the road.
static func track_signature(track: BuiltTrack) -> String:
	return track.signature()


## The varint bytes of a recorder's samples (the web game's format 2 bytes, before the text layer).
static func encode_samples(rec: GhostRecorder) -> PackedByteArray:
	var n: int = rec.count()
	var out := PackedByteArray()
	var q1: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0] # last two quantized values per channel
	var q2: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]
	for i in n:
		_put_uint(out, rec.steps[i] - rec.steps[i - 1] if i else rec.steps[0])
		for c in CH:
			var q: int = JsMath.roundi(rec.vals[i * CH + c] * SCALE[c])
			var pred: int = 0 if i == 0 else (2 * q1[c] - q2[c] if ORDER2[c] and i > 1 else q1[c])
			_put_int(out, q - pred)
			q2[c] = q1[c]
			q1[c] = q
	return out


## Decode encode_samples' bytes to {steps: PackedInt32Array, ch: [PackedFloat64Array × CH]}, or {} on bad data.
static func decode_samples(n: int, bytes: PackedByteArray) -> Dictionary:
	if n < 1 or n > GHOST_MAX_STEPS + 64 or n * (CH + 1) > bytes.size(): # (a sample takes 9 bytes or more)
		return {}
	var r := _Reader.new(bytes)
	var steps := PackedInt32Array()
	steps.resize(n)
	var ch: Array[PackedFloat64Array] = []
	for c in CH:
		var a := PackedFloat64Array()
		a.resize(n)
		ch.append(a)
	var q1: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]
	var q2: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]
	for i in n:
		steps[i] = (steps[i - 1] if i else 0) + r.uint()
		if steps[i] > GHOST_MAX_STEPS:
			return {}
		for c in CH:
			var pred: int = 0 if i == 0 else (2 * q1[c] - q2[c] if ORDER2[c] and i > 1 else q1[c])
			var q: int = pred + r.sint()
			ch[c][i] = q / SCALE[c]
			q2[c] = q1[c]
			q1[c] = q
		if not r.ok:
			return {}
	if not r.read_all():
		return {}
	return {steps = steps, ch = ch}


## The nitro changes of a recorder as varint bytes: per change, the step gap and the new level (0..10).
static func encode_boost(rec: GhostRecorder) -> PackedByteArray:
	var out := PackedByteArray()
	for i in rec.boost_steps.size():
		_put_uint(out, rec.boost_steps[i] - (rec.boost_steps[i - 1] if i else 0))
		_put_uint(out, rec.boost_levels[i])
	return out


## Decode encode_boost's bytes to {steps: PackedInt32Array, level: PackedFloat32Array (0..1)}, or {} on bad
## data or a change after `end`.
static func decode_boost(bytes: PackedByteArray, end: int) -> Dictionary:
	var r := _Reader.new(bytes)
	var steps := PackedInt32Array()
	var level := PackedFloat32Array()
	while r.i < bytes.size():
		var gap: int = r.uint()
		var b: int = r.uint()
		var step: int = (steps[steps.size() - 1] if steps.size() else 0) + gap
		if not r.ok or (steps.size() and gap < 1) or step > end or b > 10:
			return {}
		steps.append(step)
		level.append(b / 10.0)
	return {steps = steps, level = level}


## The object to save for a finished run (JSON-safe).
## info: {track: BuiltTrack, laps, time (finish time, s), car (id, default the racer)}.
static func pack_ghost(rec: GhostRecorder, info: Dictionary) -> Dictionary:
	var track: BuiltTrack = info.track
	var out: Dictionary = {
		format = GHOST_FORMAT, physics = Car.PHYSICS_VERSION,
		track = track.id, sig = track_signature(track), laps = int(info.laps),
		car = String(info.get("car", Cars.DEFAULT_CAR)),
		time = float(info.time), steps = rec.last_step, every = rec.every,
		date = Time.get_datetime_string_from_system(true) + "Z", n = rec.count(),
		data = Marshalls.raw_to_base64(encode_samples(rec)),
	}
	if rec.boost_steps.size():
		out.boost = Marshalls.raw_to_base64(encode_boost(rec))
	return out


## The car that drove saved ghost data (its car tag; none: the racer; not a string: "").
static func ghost_car_of(saved: Dictionary) -> String:
	var c: Variant = saved.get("car", Cars.DEFAULT_CAR)
	return c if c is String else ""


## True when saved ghost data is tagged for this format, physics, track layout and lap
## count, and for a known car (car `car_id` when given), without decoding it.
static func ghost_fits(saved: Variant, track: BuiltTrack, laps: int, car_id: String = "") -> bool:
	if not (saved is Dictionary):
		return false
	var s: Dictionary = saved
	for k: String in ["format", "physics", "track", "sig", "laps", "time", "n", "steps", "data"]:
		if not s.has(k):
			return false
	if not (s.time is float or s.time is int) or not (s.laps is float or s.laps is int):
		return false
	var car: String = ghost_car_of(s)
	return JsMath.same(s.format, GHOST_FORMAT) and JsMath.same(s.physics, Car.PHYSICS_VERSION) and \
		JsMath.same(s.track, track.id) and JsMath.same(s.sig, track_signature(track)) and JsMath.same(s.laps, laps) and \
		Cars.has_car(car) and (car_id == "" or car == car_id) and \
		float(s.time) > 0.0 and float(s.time) < GHOST_MAX_STEPS / 60.0


static var _b64_re: RegEx = RegEx.create_from_string("^[A-Za-z0-9+/]*={0,2}$")


## base64 text to bytes; empty for text that isn't base64 (checked first: the engine's
## decoder prints an error for it).
static func _from_base64(text: String) -> PackedByteArray:
	if text.length() % 4 != 0 or _b64_re.search(text) == null:
		return PackedByteArray()
	return Marshalls.base64_to_raw(text)


## A playable ghost from saved data ({time, date, steps, ch, end, car, boost}), or {} when
## it is missing, from another format / physics version / track layout / lap count / car
## (when `car_id` is given), or doesn't decode. Never fails loudly.
static func unpack_ghost(saved: Variant, track: BuiltTrack, laps: int, car_id: String = "") -> Dictionary:
	if not ghost_fits(saved, track, laps, car_id):
		return {}
	var s: Dictionary = saved
	if not (s.data is String) or not (s.n is float or s.n is int) or not (s.steps is float or s.steps is int):
		return {}
	var n: int = int(s.n)
	var end: int = int(s.steps)
	var d: Dictionary = decode_samples(n, _from_base64(s.data))
	if d.is_empty():
		return {}
	var steps: PackedInt32Array = d.steps
	# the last sample is the finish; the samples must not run backwards
	if steps[0] != 0 or steps[n - 1] != end:
		return {}
	if absf(end / 60.0 - float(s.time)) > 0.02:
		return {}
	for i in range(1, n):
		if steps[i] < steps[i - 1]:
			return {}
	var boost: Dictionary = {}
	if s.has("boost"):
		if not (s.boost is String):
			return {}
		var bytes: PackedByteArray = _from_base64(s.boost)
		boost = decode_boost(bytes, end) if bytes.size() else {} # (saved only when there are changes)
		if boost.is_empty():
			return {}
	return {time = float(s.time), date = str(s.get("date", "")), steps = steps, ch = d.ch, end = end, car = ghost_car_of(s), boost = boost}


## Plays an unpacked ghost: pose(step) for any (fractional) step since GO.
class GhostPlayer:
	var g: Dictionary
	var i: int = 0
	## the last nitro change at or before the pose (-1: none yet)
	var k: int = -1
	## a car-like pose holder for the car model (x, y, z, yaw, pitch, roll, steer_angle,
	## forward_speed, speed, vx, vz, boost, boosting; everything else stays at rest)
	var car: Car = Car.new()

	func _init(ghost: Dictionary) -> void:
		g = ghost

	func end() -> int:
		return int(g.end)

	## Move `out` (default: car) to the ghost's pose at `s` steps after GO (s may be
	## fractional). Returns false after the ghost's finish (it is then gone).
	func pose(s: float, out: Car = null) -> bool:
		if out == null:
			out = car
		var steps: PackedInt32Array = g.steps
		var ch: Array[PackedFloat64Array] = g.ch
		var n: int = steps.size()
		if not (s <= steps[n - 1]):
			return false
		if s < 0.0:
			s = 0.0
		# last sample at or before s (the later one of a respawn pair)
		var j0: int = i
		if j0 >= n or steps[j0] > s:
			var lo: int = 0
			var hi: int = n - 1
			while lo < hi:
				var m: int = (lo + hi + 1) >> 1
				if steps[m] <= s:
					lo = m
				else:
					hi = m - 1
			j0 = lo
		while j0 + 1 < n and steps[j0 + 1] <= s:
			j0 += 1
		i = j0
		var j: int = mini(j0 + 1, n - 1)
		var u: float = (s - steps[j0]) / (steps[j] - steps[j0]) if j > j0 else 0.0
		out.x = _v(ch[0], j0, j, u)
		out.z = _v(ch[1], j0, j, u)
		out.y = _v(ch[2], j0, j, u)
		out.yaw = _v(ch[3], j0, j, u)
		out.pitch = _v(ch[4], j0, j, u)
		out.roll = _v(ch[5], j0, j, u)
		out.steer_angle = _v(ch[6], j0, j, u)
		out.forward_speed = _v(ch[7], j0, j, u)
		out.speed = absf(out.forward_speed)
		out.vx = sin(out.yaw) * out.forward_speed
		out.vz = cos(out.yaw) * out.forward_speed
		out.boost = boost_at(s)
		out.boosting = out.boost > 0.0
		return true

	static func _v(a: PackedFloat64Array, i0: int, i1: int, u: float) -> float:
		return a[i0] + (a[i1] - a[i0]) * u

	## The nitro amount (0..1) the ghost burned at step `s` (0 for a ghost without nitro data).
	func boost_at(s: float) -> float:
		var b: Dictionary = g.boost
		if b.is_empty() or (b.steps as PackedInt32Array).is_empty():
			return 0.0
		var bs: PackedInt32Array = b.steps
		var kk: int = k
		if kk >= 0 and bs[kk] > s:
			var lo: int = -1 # the last change at or before s (-1: none)
			var hi: int = kk
			while lo < hi:
				var m: int = (lo + hi + 1) >> 1
				if bs[m] <= s:
					lo = m
				else:
					hi = m - 1
			kk = lo
		while kk + 1 < bs.size() and bs[kk + 1] <= s:
			kk += 1
		k = kk
		return (b.level as PackedFloat32Array)[kk] if kk >= 0 else 0.0
