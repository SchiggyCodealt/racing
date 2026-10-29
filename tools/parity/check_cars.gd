extends SceneTree
## Car physics parity, Godot side: reads tools/parity/car_runs.mjs's scenarios (every
## step's controls and the JS car's whole state, raw float64) and
##   1. lockstep: sets the GDScript car to the JS state before every step, steps it with
##      the same controls and compares the whole state after it with the JS one;
##   2. free run: drives a GDScript car through the same control tape from the start and
##      measures how far it drifts from the JS trajectory;
##   3. races (when the JS ran --races): the medal autopilot (nitro on) closed-loop on every
##      track with every car, finish steps against the JS ones.
##   godot --headless --path . --script res://tools/parity/check_cars.gd -- /abs/prefix

const DT: float = 1.0 / 60.0


func _initialize() -> void:
	var prefix: String = OS.get_cmdline_user_args()[0]
	var meta: Dictionary = HexJson.read(prefix + ".json")
	var data: PackedFloat64Array = FileAccess.get_file_as_bytes(prefix + ".bin").to_float64_array()
	var keys: PackedStringArray = PackedStringArray(meta.keys)
	if keys != Car.STATE_KEYS:
		print("FAIL state keys differ from Car.STATE_KEYS")
		quit(1)
		return
	var nk: int = keys.size()
	var all_steps: int = 0
	var all_exact: int = 0
	var all_fields: int = 0
	var all_bad_fields: int = 0
	var worst_all: float = 0.0
	var field_bad: Dictionary = {}
	print("scenario                          steps  air wall  hb boost | lockstep: exact steps, worst field diff | free run: first diff step, |dpos| at 5 s / 10 s / end")
	for s: Dictionary in meta.scenarios:
		var track: BuiltTrack = Tracks.build_asphalt(s.track)
		var spec: CarSpec = Cars.spec(s.car)
		var steps: int = int(s.steps)
		var base: int = int(s.offset)
		var stride: int = 4 + nk
		var car := Car.new(track, int(s.get("start", -1)), spec)
		# createCar parity
		var init_bad: PackedStringArray = []
		var st0: Dictionary = _state(data, base, keys)
		var mine0: Dictionary = car.to_state()
		for k: String in keys:
			if float(mine0[k]) != float(st0[k]):
				init_bad.append("%s %s/%s" % [k, mine0[k], st0[k]])
		# 1. lockstep
		var ctrl := Car.Controls.new()
		var exact: int = 0
		var worst: float = 0.0
		var worst_key: String = ""
		for i in steps:
			var p: int = base + nk + i * stride
			car.from_state(_state(data, p - nk if i == 0 else p - nk, keys))
			ctrl.set_to(data[p], data[p + 1], data[p + 2] != 0.0, data[p + 3])
			car.step(track, ctrl, DT)
			var mine: Dictionary = car.to_state()
			var ok: bool = true
			for j in nk:
				var js: float = data[p + 4 + j]
				var gd: float = float(mine[keys[j]])
				all_fields += 1
				if gd != js:
					ok = false
					all_bad_fields += 1
					field_bad[keys[j]] = int(field_bad.get(keys[j], 0)) + 1
					var d: float = absf(gd - js)
					if d > worst:
						worst = d
						worst_key = keys[j]
			if ok:
				exact += 1
		# 2. free run from the start with the same controls
		car = Car.new(track, int(s.get("start", -1)), spec)
		var first: int = -1
		var d5: float = -1.0
		var d10: float = -1.0
		var dend: float = 0.0
		for i in steps:
			var p: int = base + nk + i * stride
			ctrl.set_to(data[p], data[p + 1], data[p + 2] != 0.0, data[p + 3])
			car.step(track, ctrl, DT)
			var jx: float = data[p + 4]
			var jz: float = data[p + 4 + 2]
			var dp: float = sqrt((car.x - jx) * (car.x - jx) + (car.z - jz) * (car.z - jz))
			if first < 0 and (car.x != jx or car.z != jz or car.yaw != data[p + 4 + 6] or car.y != data[p + 4 + 1]):
				first = i + 1
			if i + 1 == 300:
				d5 = dp
			if i + 1 == 600:
				d10 = dp
			dend = dp
		all_steps += steps
		all_exact += exact
		worst_all = maxf(worst_all, worst)
		print("%-32s %5d %4d %4d %4d %4d | %5d/%d exact, worst %s (%s) | %s, %s / %s / %s m%s" % [
			s.name, steps, int(s.air), int(s.wall), int(s.hb), int(s.boost), exact, steps, _g(worst), worst_key,
			"never" if first < 0 else str(first), _g(d5), _g(d10), _g(dend), ("  INIT DIFF " + ", ".join(init_bad)) if init_bad.size() else ""])
	print("lockstep total: %d of %d steps bit-identical; %d of %d numbers differ (largest %s)" % [all_exact, all_steps, all_bad_fields, all_fields, _g(worst_all)])
	print("fields that differed (steps): ", field_bad)

	# 3. races
	var races: Array = meta.races
	if races.size():
		var same: int = 0
		var worst_steps: int = 0
		var t0: int = Time.get_ticks_msec()
		var total_steps: int = 0
		for r: Dictionary in races:
			var track: BuiltTrack = Tracks.build_asphalt(r.track)
			var car := Car.new(track, -1, Cars.spec(r.car))
			var race := RaceState.new(track)
			var pilot := Autopilot.medal(track, 24.0, 0.75, true)
			var steps: int = 0
			var wall: int = 0
			while not race.finished and steps < 54000:
				car.step(track, pilot.drive(car), DT)
				race.update(car, DT)
				steps += 1
				if car.hit_wall:
					wall += 1
			total_steps += steps
			var ds: int = steps - int(r.steps)
			if ds == 0 and race.finished == bool(r.finished):
				same += 1
			worst_steps = maxi(worst_steps, absi(ds))
			print("race %-16s %-8s js %s (%d steps, %d wall)  gd %s (%d steps, %d wall)  %s" % [r.track, r.car,
				RaceState.format_time(float(r.time)) if r.finished else "DNF", int(r.steps), int(r.wall),
				RaceState.format_time(race.finish_time), steps, wall, "same" if ds == 0 else "DIFF %+d steps" % ds])
		print("races: %d of %d finish on the same step (worst %d steps); %d steps in %d ms" % [same, races.size(), worst_steps, total_steps, Time.get_ticks_msec() - t0])
	quit(0)


## x in 3 significant digits ("1.23e-14").
static func _g(x: float) -> String:
	if x == 0.0 or not is_finite(x):
		return str(x)
	var e: int = floori(log(absf(x)) / log(10.0))
	if e >= -2 and e <= 3:
		return String.num(x, maxi(0, 2 - e))
	return "%.2fe%d" % [x / pow(10.0, e), e]


func _state(data: PackedFloat64Array, p: int, keys: PackedStringArray) -> Dictionary:
	var d: Dictionary = {}
	for j in keys.size():
		d[keys[j]] = data[p + j]
	return d
