extends SceneTree
## Race + score parity, Godot side: drives the races of tools/parity/score_runs.mjs with
## sim/ (Car, RaceState, ScoreState, Autopilot) and compares every race and score event,
## the totals, counts, breakdown, splits and nitro with the JS; then the formatters.
##   godot --headless --path . --script res://tools/parity/check_score.gd -- /abs/runs.json

const DT: float = 1.0 / 60.0
var bad: int = 0


func _initialize() -> void:
	var meta: Dictionary = HexJson.read(OS.get_cmdline_user_args()[0])
	var same_runs: int = 0
	var n_events: int = 0
	for r: Dictionary in meta.runs:
		var track: BuiltTrack = Tracks.build_asphalt(r.track)
		var car := Car.new(track, -1, Cars.spec(r.car))
		var race := RaceState.new(track)
		var score := ScoreState.new(track)
		var auto := Autopilot.medal(track, 24.0, 0.75, true)
		var tape := ParityTape.new(int(r.seed))
		var tape_run: bool = r.driver == "tape"
		var steps: int = 5400 if tape_run else 54000
		var events: Array = []
		var k: int = 0
		while k < steps and not race.finished:
			var ctrl: Car.Controls = auto.drive(car) if not tape_run or k % 300 < 180 else tape.next()
			car.step(track, ctrl, DT)
			for e: Dictionary in race.update(car, DT):
				events.append([k, "race:" + e.kind, e.gate_index])
			for e: Dictionary in score.update(car, race, DT):
				events.append([k, e.kind, e.points, e.get("mult"), e.get("combo_lost")])
			if tape_run and k % 900 == 899 and not race.respawn.is_empty():
				car.place(track, int(race.respawn.idx), race.respawn)
				for e: Dictionary in score.respawn():
					events.append([k, e.kind, e.points, null, e.get("combo_lost")])
			k += 1
		n_events += events.size()
		var name: String = "%s %s %s" % [r.track, r.car, r.driver]
		var before: int = bad
		_same(name + " steps", k, r.steps)
		_same(name + " finished", race.finished, r.finished)
		_same(name + " total", score.total, r.total)
		_same(name + " nitro", car.nitro, r.nitro)
		_same(name + " refilled", score.nitro, r.refilled)
		_same(name + " earned", score.nitro_earned, r.earned)
		for ck: String in (r.counts as Dictionary):
			_same(name + " counts." + ck, score.counts[ck.to_snake_case()], r.counts[ck])
		for pk: String in (r.points as Dictionary):
			_same(name + " points." + pk, score.points[pk], r.points[pk])
		_same(name + " splits", Array(race.splits), r.splits)
		_same(name + " lapTimes", Array(race.lap_times), r.lapTimes)
		var bd: Array = []
		for row: Dictionary in score.breakdown():
			bd.append([row.key, row.label, row.points, row.note])
		var bd_js: Array = []
		for row: Dictionary in r.breakdown:
			bd_js.append([row.key, row.label, row.points, row.note])
		_same(name + " breakdown", bd, bd_js)
		var live: Dictionary = score.live()
		_same(name + " live", live.get("kind"), (r.live as Dictionary).get("kind") if r.live != null else null)
		_same(name + " events", events, r.events)
		if bad == before:
			same_runs += 1
		print("%s %-40s %5d steps, %3d events, score %6d, nitro refilled %.3f tanks%s" % [
			"ok  " if bad == before else "FAIL", name, k, events.size(), int(score.total), score.nitro,
			"" if r.finished else " (no finish)"])
	print("%d of %d runs identical to the JS (%d events)" % [same_runs, meta.runs.size(), n_events])
	var fmt_bad: int = 0
	for f: Array in meta.formats:
		var v: Variant = f[0]
		var t: String = RaceState.format_time(INF if v == null else float(v))
		var d: String = "" if v == null else RaceState.format_delta(float(v))
		var p: String = ScoreState.format_points(-1234567.5 if v == null else float(v) * 1000.0)
		if t != f[1] or d != f[2] or p != f[3]:
			fmt_bad += 1
			print("FAIL format %s: gd %s %s %s, js %s %s %s" % [v, t, d, p, f[1], f[2], f[3]])
	print("formatters: %d of %d values formatted as in JS" % [meta.formats.size() - fmt_bad, meta.formats.size()])
	quit(1 if bad or fmt_bad else 0)


func _same(what: String, gd: Variant, js: Variant) -> void:
	if _eq(gd, js):
		return
	bad += 1
	if bad <= 12:
		var a: String = str(gd)
		var b: String = str(js)
		if a.length() > 300:
			# show where long lists first differ
			if gd is Array and js is Array:
				for i in mini(gd.size(), js.size()):
					if not _eq(gd[i], js[i]):
						a = "[%d] %s" % [i, gd[i]]
						b = "[%d] %s" % [i, js[i]]
						break
		print("  differ %s: gd %s  js %s" % [what, a, b])


func _eq(a: Variant, b: Variant) -> bool:
	if a == null or b == null:
		return a == null and b == null
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _eq(a[i], b[i]):
				return false
		return true
	if (typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT or typeof(a) == TYPE_BOOL) and (typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT or typeof(b) == TYPE_BOOL):
		return float(a) == float(b)
	return a == b
