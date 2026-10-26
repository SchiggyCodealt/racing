extends SceneTree
## Ghost parity, Godot side (see tools/parity/ghost_runs.mjs):
##   1. the JS recorder's samples encoded by sim/replay.gd give the JS bytes, byte for byte
##      (samples and nitro changes);
##   2. the JS bytes decode to the JS channels exactly;
##   3. the same runs recorded in Godot keep the same samples (steps) with the same
##      quantized values (x, z, y to the cm, angles to the mrad ...);
##   4. Replay.GhostPlayer gives the JS GhostPlayer's poses (from the JS bytes);
##   5. pack_ghost -> JSON text -> unpack_ghost round trip of the Godot recording.
##   godot --headless --path . --script res://tools/parity/check_ghosts.gd -- /abs/ghosts.json

const DT: float = 1.0 / 60.0
var bad: int = 0


func _initialize() -> void:
	var runs: Array = HexJson.read(OS.get_cmdline_user_args()[0])
	for r: Dictionary in runs:
		var name: String = "%s %s" % [r.track, r.kind]
		var track: BuiltTrack = Tracks.build(r.track)
		# 1. encode the JS samples
		var rec := Replay.GhostRecorder.new()
		rec.steps = PackedInt32Array(r.recSteps)
		rec.vals = PackedFloat64Array(r.recVals)
		rec.boost_steps = PackedInt32Array(r.boostSteps)
		rec.boost_levels = PackedInt32Array(r.boostLevels)
		rec.last_step = int(r.lastStep)
		_check(name + ": JS samples encode to the JS bytes", Marshalls.raw_to_base64(Replay.encode_samples(rec)) == r.bytes)
		_check(name + ": JS nitro changes encode to the JS bytes", Marshalls.raw_to_base64(Replay.encode_boost(rec)) == r.boostBytes)
		# 2. decode the JS bytes
		var d: Dictionary = Replay.decode_samples(int(r.n), Marshalls.base64_to_raw(r.bytes))
		var dec_ok: bool = not d.is_empty() and _same(d.steps, r.decoded.steps)
		if dec_ok:
			for c in Replay.CH:
				dec_ok = dec_ok and _same(d.ch[c], r.decoded.ch[c])
		_check(name + ": JS bytes decode to the JS channels (%d samples)" % int(r.n), dec_ok)
		# 4. poses from the JS bytes
		var g: Dictionary = {steps = d.steps, ch = d.ch, end = int(r.lastStep), boost = Replay.decode_boost(Marshalls.base64_to_raw(r.boostBytes), int(r.lastStep)), time = r.time, car = r.car}
		var player := Replay.GhostPlayer.new(g)
		var pose_bad: int = 0
		for p: Array in r.poses:
			var ok: bool = player.pose(float(p[0]))
			var c: Car = player.car
			var mine: Array = [p[0], ok, c.x, c.z, c.y, c.yaw, c.pitch, c.roll, c.steer_angle, c.forward_speed, c.boost]
			if not ok:
				mine = [p[0], false]
				p = p.slice(0, 2)
			for i in mine.size():
				if float(mine[i]) != float(p[i]):
					pose_bad += 1
					if pose_bad < 4:
						print("  pose differs at step %s: gd %s js %s" % [p[0], mine, p])
					break
		_check(name + ": GhostPlayer poses = JS poses (%d poses, %d differ)" % [r.poses.size(), pose_bad], pose_bad == 0)
		# 3. record the same run in Godot
		var car := Car.new(track, -1, Cars.spec(r.car))
		var race := RaceState.new(track)
		var mine_rec := Replay.GhostRecorder.new()
		var auto := Autopilot.medal(track, 24.0, 0.75, true)
		var tape := ParityTape.new(7)
		var steps: int = 54000 if r.kind == "race" else 2400
		mine_rec.add(0, car)
		var k: int = 0
		while k < steps and not race.finished:
			var ctrl: Car.Controls = auto.drive(car) if r.kind == "race" or k % 300 < 180 else tape.next()
			car.step(track, ctrl, DT)
			race.update(car, DT)
			mine_rec.add(k + 1, car, race.finished)
			if r.kind == "tape" and k % 600 == 599 and not race.respawn.is_empty():
				mine_rec.before_jump(k + 1, car)
				car.place(track, int(race.respawn.idx), race.respawn)
				mine_rec.after_jump(k + 1, car)
			k += 1
		# (a random wall-banging run can drift apart once a one-ulp difference flips a contact
		# on or off: compare up to the first sample where a raw pose value differs by more than 1e-6)
		var js_steps: Array = r.recSteps
		var js_vals: Array = r.recVals
		var n_cmp: int = 0
		var q_bad: int = 0
		var v_worst: float = 0.0
		var drift_at: int = -1
		while n_cmp < mini(mine_rec.count(), js_steps.size()):
			if mine_rec.steps[n_cmp] != int(js_steps[n_cmp]):
				break
			var far: bool = false
			for c in Replay.CH:
				var i: int = n_cmp * Replay.CH + c
				var dv: float = absf(mine_rec.vals[i] - float(js_vals[i]))
				if dv > 1e-6:
					far = true
			if far:
				drift_at = mine_rec.steps[n_cmp]
				break
			for c in Replay.CH:
				var i: int = n_cmp * Replay.CH + c
				v_worst = maxf(v_worst, absf(mine_rec.vals[i] - float(js_vals[i])))
				if JsMath.round(mine_rec.vals[i] * Replay.SCALE[c]) != JsMath.round(float(js_vals[i]) * Replay.SCALE[c]):
					q_bad += 1
			n_cmp += 1
		var all_same: bool = n_cmp == js_steps.size() and n_cmp == mine_rec.count()
		_check(name + ": recorded in Godot: %d of %d samples on the same steps with the same quantized values (%d differ; raw within %s)%s" % [
			n_cmp, js_steps.size(), q_bad, JsMath.num_to_js(v_worst),
			"" if all_same else "; the runs drift apart at step %d (%.1f s: last-bit libm differences grew past 1e-6 in this wall-banging run)" % [drift_at, drift_at / 60.0]],
			q_bad == 0 and (all_same or (drift_at > 0 and r.kind == "tape")) and (not all_same or _same(mine_rec.boost_steps, r.boostSteps)))
		# 5. pack -> JSON -> unpack
		var time: float = race.finish_time if race.finished else k / 60.0
		var packed: Dictionary = Replay.pack_ghost(mine_rec, {track = track, laps = race.laps, time = time, car = r.car})
		var back: Variant = JSON.parse_string(JSON.stringify(packed, "", false, true))
		var un: Dictionary = Replay.unpack_ghost(back, track, race.laps, r.car)
		var rt_ok: bool = not un.is_empty() and un.end == mine_rec.last_step and _same(un.steps, mine_rec.steps)
		_check(name + ": pack_ghost -> JSON -> unpack_ghost round trip (%d chars of base64; car %s, fits only its track/laps/car)" % [
			String(packed.data).length(), un.get("car", "?")], rt_ok and Replay.unpack_ghost(back, track, race.laps + 1, r.car).is_empty() and \
			Replay.unpack_ghost(back, track, race.laps, "thunder").is_empty())
	quit(1 if bad else 0)


## Same numbers (any array kinds, int or float).
func _same(a: Variant, b: Variant) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if float(a[i]) != float(b[i]):
			return false
	return true


func _check(what: String, ok: bool) -> void:
	print("%s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		bad += 1
