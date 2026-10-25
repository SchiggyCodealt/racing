extends SceneTree
## gen_tracks.gd: regenerates data/tracks.json from the turtle programs below
## and validates every track against the design rules (port of
## web/tools/generateTracks.mjs; the overview SVG of the web version is not
## made here).
##
##   godot --headless --path . --script res://tools/gen_tracks.gd                validate, then write data/tracks.json
##   godot --headless --path . --script res://tools/gen_tracks.gd -- --check     validate and compare with data/tracks.json, write nothing
##   ... -- --out=/abs/path.json                                                  write somewhere else
##
## Any rule violation is printed and the tool exits with code 1 without
## writing. The output has the same fields as web/src/tracks/trackData.js
## (a JSON array of definitions in menu order, points in the same compact
## form), and for the built-in tracks it is the same data, number for number.
##
## Design rules (RULES below):
##   - no part of the track comes within hwA + hwB + 6 m of another part
##     (no crossings or bridges: physics is 2.5D)
##   - centre-line radius >= half width + 4 m everywhere (walls never fold)
##   - grades <= 12 %; only kicker ramps may be steeper (<= 25 %), and every
##     kicker lip is followed by >= 120 m of straight landing zone whose
##     downslope is <= 15 %
##   - crests (outside kickers) have a vertical radius >= 300 m
##   - heights between 0 and 18 m, banking <= 30°, width changes <= 1:10
##   - checkpoints every 250-500 m and never on a jump
##   - the start is on a straight with >= 80 m to the first corner; circuits
##     close within 1 m with the start/finish line on a straight; sprints
##     finish on a straight
##   - sprints have 36 m of straight road before the cars' start position and
##     250 m of flat, straight run-off after the FINISH line

const OUT_PATH: String = "res://data/tracks.json"

const RULES: Dictionary = {
	clearance = 6.0, # m between the road edges of two separate parts of the track
	radiusMargin = 4.0, # centre-line radius >= hw + 4 m
	maxGrade = TrackBuilder.KICKER_GRADE, # 12 %
	maxKickerGrade = 0.25,
	maxLandingGrade = 0.15,
	landingZone = 120.0, # m of straight road after a kicker lip
	minCrestRadius = 300.0, # m, vertical radius of crests outside kickers
	minHeight = 0.0,
	maxHeight = 18.0,
	maxBank = 30.0, # degrees
	maxTaper = 0.1, # |d(half width)/ds|: walls angle in at most 1:10
	cpGap = [250.0, 500.0], # m between consecutive gates (start, checkpoints, finish)
	startStraight = 80.0, # m of straight after the start
	finishStraight = 40.0, # m of straight before a sprint finish / around a start line
	closure = 1.0, # m
	straightTol = 1.0, # degrees of heading change still counted as "straight"
	sprintRunIn = 36.0, # m of road before a sprint's start position
	sprintRunOff = 250.0, # m of straight, flat road after a sprint's finish line
}
const RUN_IN: float = 36.0
const RUN_OFF: float = 250.0
const THEMES: Array[String] = ["meadow", "desert", "alpine", "canyon", "dusk", "night", "seaside"]
const DEGR: float = PI / 180.0

## The designs, in menu order: {kind, meta, make (Callable), close (closeLoop options), req}
var designs: Array[Dictionary] = []


func _initialize() -> void:
	_define()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var check_only: bool = args.has("--check")
	var out_path: String = OUT_PATH
	for a in args:
		if a.begins_with("--out="):
			out_path = a.substr(6)
	var t0: int = Time.get_ticks_msec()
	var failed: int = 0
	var results: Array[Dictionary] = []
	for d in designs:
		var e: Dictionary = _realise(d)
		if e.is_empty():
			print("%s ! could not be built" % String(d.meta.id).rpad(16))
			failed += 1
			continue
		var r: Dictionary = _validate(e)
		results.append(r)
		var s: Dictionary = r.stats
		var kick: Array = r.kick
		var kick_txt: String = ""
		if kick.size():
			var hs: PackedStringArray = []
			for k in kick:
				hs.append("%.1f" % k.height)
			kick_txt = " (%s m, ramp %.0f%%, land %.0f%%)" % ["/".join(hs), s.kickGrade * 100.0, s.landGrade * 100.0]
		var gmin: float = INF
		var gmax: float = -INF
		for g: float in r.gaps:
			gmin = minf(gmin, g)
			gmax = maxf(gmax, g)
		print("%s %.2f km %s  minR %.1f (R-hw %.1f)  h %.1f-%.1f m  grade %.1f%%  kick %d%s  cp %d (gaps %d-%d)  clear +%.1f  crestR %s  w %.0f-%.0f  bank %.0f°  hairpins %d  start %.0f m  %spts %d" % [
			String(e.def.id).rpad(16), s.race / 1000.0, "sprint " if e.def.type == "sprint" else "%d laps" % s.laps,
			s.minR, s.minMargin, s.minY, s.maxY, s.maxGrade * 100.0, kick.size(), kick_txt, s.cps, JsMath.roundi(gmin), JsMath.roundi(gmax),
			s.minClear, ("%.0f" % s.minCrest) if is_finite(s.minCrest) else "-", s.wMin, s.wMax, s.maxBank, s.hairpins, s.startRun,
			("closure %.3f m  " % s.closure) if e.def.type == "circuit" else "", s.points])
		for msg: String in r.issues:
			print("   ! " + msg)
		if r.issues.size():
			failed += 1
	var longest: float = 0.0
	var ids: Dictionary = {}
	for r in results:
		longest = maxf(longest, float(r.stats.race))
		ids[r.def.id] = true
	for r in results:
		if r.def.id == "grand-marathon" and float(r.stats.race) < longest:
			print("   ! grand-marathon must be the longest track")
			failed += 1
	if ids.size() != results.size():
		print("   ! duplicate track ids")
		failed += 1
	print("%.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	if failed:
		print("\n%d track(s) break the design rules: tracks.json NOT written" % failed)
		quit(1)
		return
	var defs: Array = []
	for r in results:
		defs.append(r.def)
	var text: String = tracks_json(defs)
	if check_only:
		var old: String = FileAccess.get_file_as_string(out_path)
		var same: bool = old == text
		print("all %d tracks pass the design rules; %s %s" % [results.size(), out_path, "is up to date" if same else "is OUT OF DATE: run tools/gen_tracks.gd"])
		quit(0 if same else 1)
		return
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var f: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		print("cannot write %s" % out_path)
		quit(1)
		return
	f.store_string(text)
	f.close()
	print("wrote %s (%d tracks, all design rules pass)" % [out_path, results.size()])
	quit(0)


# =============================================================================
# The tracks. Lengths in metres, angles in degrees; L/R = left/right turn
# (deg, radius, {bank, y}); y = height at the end of a piece.
# =============================================================================

func _circuit(meta: Dictionary, make: Callable, close: Dictionary, req: Dictionary = {}) -> void:
	designs.append({kind = "circuit", meta = meta, make = make, close = close, req = req})


func _sprint(meta: Dictionary, make: Callable, req: Dictionary = {}) -> void:
	designs.append({kind = "sprint", meta = meta, make = make, close = {}, req = req})


func _define() -> void:
	# 1 - Rookie Oval: a wide, flowing beginner circuit with gentle slopes.
	_circuit({id = "rookie-oval", name = "Rookie Oval", difficulty = 1, width = 22, theme = "meadow",
		description = "A wide, flowing loop with gentle slopes: learn the car and carry speed through the sweepers."},
		func(a: float, b: float) -> Turtle: return (Turtle.new({width = 22, y = 2})
			.S(a, {y = 2}).width(20, 60)
			.L(110, 100, {bank = 6})
			.S(b, {y = 3})
			.L(70, 70, {bank = 6, y = 4})
			.S(160, {y = 5}).R(40, 150).L(40, 150).S(100, {y = 3.5})
			.L(90, 90, {bank = 6})
			.S(160).width(22, 60)
			.L(90, 120, {bank = 5, y = 2.5})
			.S(100, {y = 2})),
		{a0 = 300, b0 = 200, minA = 150, minB = 60},
		{minLength = 1600, width = [18, 22], maxGrade = 0.06, kickers = 0})

	# 2 - Hairpin Valley: switchbacks up one side of the valley, a ridge road, switchbacks down the other.
	_circuit({id = "hairpin-valley", name = "Hairpin Valley", difficulty = 2, width = 13, theme = "alpine",
		description = "Climb three switchbacks, cross the ridge and drop down two more: brake early, power out."},
		func(a: float, b: float) -> Turtle: return (Turtle.new({width = 13, y = 1, yaw = PI / 2})
			.S(a, {y = 1})
			.S(60)
			# up: three switchbacks, each leg climbs 5 m at up to 7 %
			.L(90, 16).S(64).L(90, 16).S(20).climb(110, 6).S(20)
			.R(90, 16).S(64).R(90, 16).S(20).climb(110, 11).S(20)
			.L(90, 16).S(64).L(90, 16).S(20).climb(110, 16)
			# the ridge
			.S(100).hill(200, 1.5)
			.L(90, 40)
			# down: two hairpins
			.climb(b, 12.5)
			.hairpin("R", 17).climb(b - 40, 8)
			.hairpin("L", 17).climb(b + 20, 3)
			.L(90, 40, {y = 1.5})
			.S(120, {y = 1})),
		{a0 = 100, b0 = 160, minA = 60, minB = 100},
		{minLength = 2200, hairpins = 5, minClimb = 10, kickers = 0})

	# 3 - Ramp Rally: four kicker jumps on long straights, chicanes and dunes in between.
	_circuit({id = "ramp-rally", name = "Ramp Rally", difficulty = 3, width = 15, theme = "desert",
		description = "Four kicker jumps from 4 to 7 m: hit each ramp straight and land on the long run-outs."},
		func(a: float, b: float) -> Turtle: return (Turtle.new({width = 15, y = 2})
			.S(a, {y = 2})
			.kicker({h = 4.2, ramp = 22, land = 32, run = 130, lead = 30})
			.L(90, 40, {bank = 6})
			.S(b).SL(30, 70, {}, 20)
			.kicker({h = 5.5, ramp = 28, land = 42, run = 130})
			.hill(180, 3)
			.L(90, 35, {bank = 8})
			.S(60).kicker({h = 7, ramp = 34, land = 55, run = 130})
			.L(90, 45, {bank = 6})
			.S(60).hill(160, 2.5).SR(35, 60, {}, 30)
			.kicker({h = 5, ramp = 26, land = 45, run = 130, drop = 1.5}).y(0.5)
			.L(90, 40, {y = 2})
			.S(80, {y = 2})),
		{a0 = 120, b0 = 100, minA = 90, minB = 40},
		{minLength = 2000, kickers = 4, kickerHeight = [4, 7]})

	# 4 - Banked Speedway: huge banked bowls, banked esses and long straights.
	_circuit({id = "banked-speedway", name = "Banked Speedway", difficulty = 3, width = 18, theme = "dusk",
		description = "Steep banked bowls hold the car at full speed: trust the banking and stay flat out."},
		func(a: float, b: float) -> Turtle: return (Turtle.new({width = 18, y = 6})
			.S(a, {y = 6})
			.L(95, 170, {bank = 24})
			.S(b)
			.L(85, 160, {bank = 26})
			.S(20, {y = 6}).hill(320, 3)
			.L(45, 180, {bank = 12}).R(45, 180, {bank = 12})
			.S(120)
			.L(180, 150, {bank = 28})
			.S(120, {y = 6})),
		{a0 = 400, b0 = 120, minA = 200, minB = 60},
		{minLength = 2500, bank = [20, 30], kickers = 0})

	# 5 - Technical Trial: everything mixed, the road narrows and widens.
	_circuit({id = "technical-trial", name = "Technical Trial", difficulty = 4, width = 14, theme = "canyon",
		description = "Narrow chicanes, a jump, banked sweepers and a switchback climb: rhythm beats top speed."},
		func(a: float, b: float) -> Turtle: return (Turtle.new({width = 16, y = 3})
			.S(a, {y = 3}).width(12, 40)
			.L(90, 30, {bank = 5})
			.S(40).kicker({h = 5, ramp = 26, land = 40, run = 120, lead = 10})
			.width(10, 40).SL(55, 24, {}, 12).S(40).width(14, 40).hill(200, -2)
			.L(90, 30, {y = 4})
			.S(220, {y = 9})
			.hairpin("R", 15, {y = 10}).S(170, {y = 12})
			.hairpin("L", 15, {y = 13}).width(14, 40).S(230, {y = 13})
			.L(90, 40, {bank = 8})
			.S(b)
			.R(40, 60, {bank = 12}).L(80, 60, {bank = 14}).R(40, 60, {bank = 12})
			.S(60, {y = 8}).width(10, 40)
			.L(35, 30).R(35, 30).S(40, {y = 4}).width(16, 60)
			.L(90, 45, {bank = 10, y = 3})
			.S(100, {y = 3})),
		{a0 = 150, b0 = 150, minA = 100, minB = 40},
		{minLength = 2500, width = [10, 16], widthSpread = 5.5})

	# 6 - Grand Marathon: the long point-to-point run with every element.
	# Four long rows joined by U-turns (a banked bowl, a switchback, a wide banked turn).
	_sprint({id = "grand-marathon", name = "Grand Marathon", difficulty = 5, width = 15, theme = "meadow",
		description = "Over 6 km point to point: jumps, switchbacks, banked bowls and narrow chicanes in one run."},
		func() -> Turtle: return (Turtle.new({width = 16, y = 2, yaw = PI / 2})
			.S(RUN_IN, {y = 2}) # road behind the start position
			# row 1 (east): start, fast sweepers, first jump
			.S(260, {y = 2}).width(15, 60)
			.L(30, 220, {bank = 6}).R(30, 220, {bank = 6})
			.S(60).kicker({h = 5, ramp = 26, land = 40, run = 140})
			.S(100).R(25, 180).L(25, 180).S(140, {y = 5})
			.R(30, 150, {bank = 6}).L(30, 150, {bank = 6}).S(100, {y = 5})
			# U-turn 1: banked bowl
			.L(180, 115, {bank = 24}).S(80, {y = 5})
			# row 2 (west): climb, switchback tongue, narrow chicanes
			.S(220, {y = 9})
			.R(90, 20).S(110, {y = 12}).hairpin("L", 16, {y = 13}).S(110, {y = 15}).R(90, 20, {y = 15})
			.S(80).width(11, 40).S(60).SR(45, 28, {}, 12).S(60).width(15, 40)
			.S(260, {y = 12}).R(20, 200).L(20, 200)
			.S(120, {y = 11})
			# U-turn 2: a slow double-right
			.R(90, 35, {bank = 6}).S(170).R(90, 35, {bank = 6, y = 10})
			# row 3 (east): descent, banked esses, second jump
			.S(240, {y = 7})
			.L(50, 100, {bank = 15}).R(50, 100, {bank = 15})
			.S(120, {y = 6})
			.kicker({h = 6, ramp = 30, land = 50, run = 150, drop = 2})
			.S(120, {y = 4}).R(30, 120).L(30, 120)
			.S(160, {y = 4})
			# U-turn 3: wide banked turn
			.L(180, 110, {bank = 20})
			# row 4 (west): technical run home
			.S(180, {y = 3}).width(12, 40)
			.R(60, 35).L(120, 40, {bank = 8}).R(60, 35).width(16, 40)
			.S(300, {y = 2}).L(25, 250).R(25, 250)
			.S(250, {y = 2})
			.S(RUN_OFF, {y = 2})), # run-off after the finish line
		{minLength = 6000})

	# 7 - Coastal GP: a fast, flowing grand-prix circuit; wide main straight, narrower twisty sector.
	_circuit({id = "coastal-gp", name = "Coastal GP", difficulty = 3, width = 14, theme = "dusk",
		description = "A fast grand-prix circuit at sunset: big braking zones, quick esses and a narrow final sector."},
		func(a: float, b: float) -> Turtle: return (Turtle.new({width = 18, y = 2})
			.S(a, {y = 2}).width(14, 80)
			.R(90, 30, {bank = 4})
			.L(30, 60)
			.S(150, {y = 3})
			.R(60, 110, {bank = 8}).L(40, 150, {bank = 6})
			.S(b, {y = 4})
			.R(120, 70, {bank = 10})
			.S(330, {y = 8})
			.L(50, 60, {bank = 6}).R(50, 60, {bank = 6})
			.S(160, {y = 7})
			.R(90, 45, {bank = 6})
			.S(330, {y = 5}).width(12, 40)
			.L(35, 30).R(35, 30)
			.S(150, {y = 3}).width(18, 60)
			.R(70, 90, {bank = 8, y = 2})
			.S(120, {y = 2})),
		{a0 = 400, b0 = 200, minA = 250, minB = 100},
		{minLength = 2800, width = [12, 18], widthSpread = 5.5, kickers = 0})

	# 8 - Mountain Pass: a point-to-point climb over banked switchbacks to 18 m and down the other side.
	_sprint({id = "mountain-pass", name = "Mountain Pass", difficulty = 4, width = 13, theme = "alpine",
		description = "A 4.5 km sprint over the pass: banked switchbacks up to the summit and a fast, twisting descent."},
		func() -> Turtle: return (Turtle.new({width = 14, y = 1, yaw = PI})
			.S(RUN_IN, {y = 1}) # road behind the start position
			# valley run north, then a steep pull up the first slope
			.S(240, {y = 1})
			.L(35, 160, {bank = 6}).R(35, 160, {bank = 6})
			.S(40).climb(150, 8).S(40).width(13, 40)
			# the climb: three banked switchbacks
			.L(90, 40, {bank = 8})
			.S(40).climb(150, 11.5).S(30).hairpin("R", 18, {bank = 12})
			.S(40).climb(150, 14.5).S(30).hairpin("L", 18, {bank = 12})
			.S(40).climb(150, 17).S(30).hairpin("R", 18, {bank = 12})
			.climb(240, 17.5)
			# summit ridge
			.S(60).L(30, 90, {bank = 10}).R(30, 90, {bank = 10})
			.S(60).hill(240, 0.5).S(200)
			# the descent: three banked switchbacks, steep legs
			.hairpin("R", 19, {bank = 12})
			.S(30).climb(140, 12.5).S(30).hairpin("L", 19, {bank = 12})
			.S(30).climb(140, 8).S(30).hairpin("R", 19, {bank = 12})
			.S(30).climb(140, 4.5).S(30)
			# fast run to the finish
			.L(90, 60, {bank = 8})
			.climb(200, 3).L(30, 180, {bank = 6}).R(30, 180, {bank = 6})
			.S(320, {y = 3})
			.S(RUN_OFF, {y = 3})), # run-off after the finish line
		{minLength = 4300, minClimb = 14})

	# 9 - Canyon Run: out along one narrow canyon, back along the next; twisty, narrow and jumpy.
	_circuit({id = "canyon-run", name = "Canyon Run", difficulty = 5, width = 11, theme = "canyon",
		description = "Out and back through narrow red-rock badlands with jumps, blind crests and tight S-bends: the hardest circuit."},
		func(a: float, b: float) -> Turtle: return (Turtle.new({width = 13, y = 4, yaw = PI / 2})
			# out along the south canyon
			.S(a, {y = 4}).width(11, 40)
			.SR(40, 40, {bank = 6}, 10)
			.S(40).kicker({h = 4.5, lead = 15})
			.SL(55, 26, {bank = 8}, 10).width(10, 40)
			.S(60, {y = 6}).hill(170, 2.5, {y = 7})
			.SR(65, 24, {bank = 8}, 12)
			.S(80, {y = 9})
			# far end: a tight double-left onto the north canyon
			.L(90, 22, {bank = 8}).S(140, {y = 10}).L(90, 22, {bank = 8}).width(12, 40)
			# back along the north canyon
			.S(80, {y = 11}).hill(160, 2, {y = 11}).S(60)
			.SL(45, 30, {bank = 8}, 10)
			.kicker({h = 5, drop = 3})
			.SR(60, 26, {bank = 10}, 8).width(10, 40)
			.S(60, {y = 7})
			.R(90, 20, {bank = 6}).S(60, {y = 8}).hairpin("L", 13, {y = 8}).S(60, {y = 6}).R(90, 20, {bank = 6})
			.S(100, {y = 5}).SL(40, 40, {bank = 6}, 20).width(13, 40)
			# home: back down to the start straight
			.L(90, 30, {bank = 6}).S(b, {y = 4}).L(90, 30, {bank = 6})
			.S(80, {y = 4})),
		{a0 = 150, b0 = 60, minA = 100, minB = 20},
		{minLength = 2600, width = [10, 13], kickers = 2})

	# 10 - Night Highway: long straights joined by slow, heavy-braking corners; the fastest circuit, built for nitro.
	_circuit({id = "night-highway", name = "Night Highway", difficulty = 2, width = 18, theme = "night",
		description = "Kilometre-long straights under the lights: brake hard for the slow corners and fire the nitro out of them."},
		func(a: float, b: float) -> Turtle: return (Turtle.new({width = 18, y = 3})
			.S(a, {y = 3})
			.R(90, 28, {bank = 4}).S(70).R(90, 28, {bank = 4})
			.S(300, {y = 3}).hill(400, 3).L(12, 500).R(12, 500).S(200, {y = 4})
			.R(90, 30, {bank = 4})
			.S(b, {y = 4})
			.R(90, 120, {bank = 12})
			.S(250, {y = 3})
			.R(90, 45, {bank = 6})
			.S(60)
			.L(90, 30, {bank = 4})
			.S(100, {y = 3})),
		{a0 = 650, b0 = 160, minA = 450, minB = 100},
		{minLength = 2800, kickers = 0})

	# 11 - Lighthouse Bay: long, constant-radius sweepers round the bay; made for holding drifts.
	_circuit({id = "lighthouse-bay", name = "Lighthouse Bay", difficulty = 3, width = 17, theme = "seaside",
		description = "Long sweeping bends round the bay, past the lighthouse: throw the car sideways and hold the drift."},
		func(a: float, b: float) -> Turtle: return (Turtle.new({width = 18, y = 2})
			.S(a, {y = 2}).width(17, 60)
			.L(110, 104, {bank = 4})
			.S(70, {y = 3})
			.R(50, 80, {bank = 4})
			.S(92, {y = 4})
			.L(40, 92)
			.S(b, {y = 5})
			.L(140, 63, {bank = 5})
			.S(126, {y = 6})
			.L(80, 80, {bank = 4})
			.R(170, 109, {bank = 5, y = 5})
			.L(70, 75, {bank = 4, y = 4})
			.S(92, {y = 3})
			.L(140, 69, {bank = 5}).width(18, 60)
			.S(115, {y = 2})),
		{a0 = 185, b0 = 80, minA = 120, minB = 40},
		{minLength = 2200, kickers = 0})

	# 12 - Seaside Stunts: a point-to-point run down the coast over six kickers.
	_sprint({id = "seaside-stunts", name = "Seaside Stunts", difficulty = 4, width = 16, theme = "seaside",
		description = "Six kickers down the coast road, with step-downs and a 7.5 m launch: line up straight and fly far."},
		func() -> Turtle: return (Turtle.new({width = 16, y = 13, yaw = PI / 2})
			.S(RUN_IN, {y = 13})
			.S(100, {y = 13})
			.kicker({h = 4.5, drop = 2})
			.L(90, 55, {bank = 8}).S(30).cp().S(30)
			.kicker({h = 5.5, drop = 2})
			.R(100, 50, {bank = 8}).S(30).cp().S(30)
			.kicker({h = 7, drop = 1})
			.R(70, 70, {bank = 6}).S(30).cp().S(30)
			.kicker({h = 4, drop = 3})
			.L(110, 50, {bank = 8}).S(30).cp().S(30)
			.kicker({h = 6, drop = 2})
			.R(70, 80, {bank = 6}).S(30).cp().S(30)
			.kicker({h = 7.5, drop = 2})
			.R(60, 70, {bank = 6})
			.S(60, {y = 1}).cp().S(300)
			.S(RUN_OFF, {y = 1})),
		{minLength = 3000, kickers = 6})


## A design turned into its track definition: {def, f (finish() result), turtle, req}, or {} on an error.
func _realise(d: Dictionary) -> Dictionary:
	var meta: Dictionary = d.meta
	var req: Dictionary = d.req
	var t: Turtle
	if d.kind == "circuit":
		var solved: Dictionary = Turtle.close_loop(d.make, d.close)
		if solved.is_empty():
			return {}
		t = solved.t
	else:
		t = (d.make as Callable).call()
	var fo: Dictionary = {closed = d.kind == "circuit", cpSpacing = float(req.get("cpSpacing", 400.0))}
	if d.kind == "sprint":
		fo.startAt = RUN_IN
		fo.runOff = RUN_OFF
	var f: Dictionary = t.finish(fo)
	if f.is_empty():
		return {}
	# the same keys, in the same order, as generateTracks.mjs writes them
	var def: Dictionary = {
		id = meta.id, name = meta.name, difficulty = meta.difficulty, width = meta.width, theme = meta.theme,
		description = meta.description, type = d.kind,
	}
	if d.kind == "circuit":
		def.laps = 3
	else:
		def.startAt = RUN_IN
		def.runOff = RUN_OFF
	def.checkpoints = f.checkpoints
	def.points = f.points
	return {def = def, f = f, turtle = t, req = req}


static func _ang_diff(a: float, b: float) -> float:
	return atan2(sin(a - b), cos(a - b))


# =============================================================================
# Validation (generateTracks.mjs validate())
# =============================================================================
func _validate(e: Dictionary) -> Dictionary:
	var def: Dictionary = e.def
	var f: Dictionary = e.f
	var req: Dictionary = e.req
	var turtle: Turtle = e.turtle
	var tr: BuiltTrack = TrackBuilder.build_track(def)
	var issues: Array[String] = []
	var count: int = tr.count
	var N: int = tr.N
	var closed: bool = tr.closed
	var seg_len: float = tr.seg_len
	var px: PackedFloat32Array = tr.px
	var pz: PackedFloat32Array = tr.pz
	var py: PackedFloat32Array = tr.py
	var hw: PackedFloat32Array = tr.hw
	var bank: PackedFloat32Array = tr.bank
	var n: int = N if closed else count
	var L_: float = tr.length
	var heading := func(i: int) -> float: return tr.heading(tr.wrap(i))

	# curvature over +-2 samples
	var kappa: PackedFloat64Array = PackedFloat64Array()
	kappa.resize(count)
	for i in count:
		var a: int = i - 2 if closed else maxi(0, i - 2)
		var b: int = i + 2 if closed else mini(count - 1, i + 2)
		kappa[i] = _ang_diff(heading.call(b), heading.call(a)) / ((b - a) * seg_len)

	# meta
	if not THEMES.has(String(def.theme)):
		issues.append("unknown theme '%s'" % def.theme)
	if not (float(def.difficulty) >= 1 and float(def.difficulty) <= 5):
		issues.append("difficulty must be 1-5")
	if String(def.get("description", "")) == "" or String(def.description).length() > 110:
		issues.append("description missing or longer than 110 characters")

	# closure (turtle end vs start) and spline agreement
	var closure: float = float(f.closure) if closed else 0.0
	if closed and closure > RULES.closure:
		issues.append("does not close: end is %.2f m from the start" % closure)
	var len_err: float = absf(L_ - float(f.length))
	if len_err > 0.002 * L_:
		issues.append("spline length %.1f m differs from the design %.1f m" % [L_, f.length])
	if req.has("minLength") and L_ < float(req.minLength):
		issues.append("too short: %.0f m < %s m" % [L_, req.minLength])
	if req.has("maxLength") and L_ > float(req.maxLength):
		issues.append("too long: %.0f m > %s m" % [L_, req.maxLength])

	# corner radius
	var min_r: float = INF
	var min_margin: float = INF
	var min_r_at: int = 0
	for i in count:
		if not closed and (i < 2 or i > count - 3):
			continue
		var r: float = 1.0 / maxf(1e-9, absf(kappa[i]))
		if r < min_r:
			min_r = r
		if r - hw[i] < min_margin:
			min_margin = r - hw[i]
			min_r_at = i
	if min_margin < RULES.radiusMargin:
		issues.append("corner too tight at %.0f m: radius %.1f m < half width %.1f + %s m" % [min_r_at * seg_len, min_margin + hw[min_r_at], hw[min_r_at], RULES.radiusMargin])

	# separation between different parts of the track
	var min_clear: float = INF
	var clear_at: Array = []
	var cell: float = 40.0
	var grid: Dictionary = {}
	for i in count:
		var key: int = int(floor(px[i] / cell)) * 100003 + int(floor(pz[i] / cell))
		if not grid.has(key):
			grid[key] = PackedInt32Array()
		var lst: PackedInt32Array = grid[key]
		lst.append(i)
		grid[key] = lst
	for i in count:
		var cx: int = int(floor(px[i] / cell))
		var cz: int = int(floor(pz[i] / cell))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var key: int = (cx + dx) * 100003 + (cz + dz)
				if not grid.has(key):
					continue
				for j: int in grid[key]:
					if j <= i:
						continue
					var d: int = j - i
					if closed:
						d = mini(d, N - d)
					var C: float = hw[i] + hw[j] + RULES.clearance
					if d * seg_len < maxf(40.0, 1.6 * C):
						continue
					var dist: float = JsMath.hypot2(px[i] - px[j], pz[i] - pz[j])
					if dist - C < min_clear:
						min_clear = dist - C
						clear_at = [i, j, dist, C]
	if min_clear < 0.0:
		issues.append("parts of the track too close: %.0f m and %.0f m are %.1f m apart (need %.1f m)" % [int(clear_at[0]) * seg_len, int(clear_at[1]) * seg_len, clear_at[2], clear_at[3]])

	# grades, kickers, crests
	var grade := func(i: int) -> float:
		var den: float = (2.0 if closed else float(mini(count - 1, i + 1) - maxi(0, i - 1))) * seg_len
		return (py[tr.wrap(i + 1)] - py[tr.wrap(i - 1)]) / den
	var zone: PackedByteArray = PackedByteArray() # 1 = kicker ramp, 2 = landing slope
	zone.resize(count)
	var kick: Array[Dictionary] = []
	var span := func(a: int, b: int) -> PackedInt32Array:
		var out: PackedInt32Array = PackedInt32Array()
		var i: int = a
		while true:
			out.append(i)
			if i == b or out.size() > count:
				break
			i = tr.wrap(i + 1)
		return out
	for k in tr.kickers:
		var foot: int = k.foot
		var lip: int = k.lip
		var land: int = k.land
		var ramp_span: PackedInt32Array = span.call(foot, lip)
		var land_span: PackedInt32Array = span.call(lip, land)
		for i in ramp_span:
			zone[i] = 1
		for i in land_span:
			if i != lip:
				zone[i] = 2
		var ramp_max: float = -INF
		for i in ramp_span:
			ramp_max = maxf(ramp_max, grade.call(i))
		var land_min: float = INF
		for i in land_span:
			land_min = minf(land_min, grade.call(i))
		var land_len: float = land_span.size() * seg_len
		# straight landing zone: no heading change from the ramp foot to lip + 120 m
		var zone_end: int = lip + int(ceil(RULES.landingZone / seg_len))
		var max_turn: float = 0.0
		for i in range(foot, zone_end + 1):
			max_turn = maxf(max_turn, absf(_ang_diff(heading.call(i), heading.call(lip))))
		if not closed and zone_end > count - 1:
			issues.append("kicker at %.0f m: the track ends inside the landing zone" % (lip * seg_len))
		var at: String = "kicker at %.0f m" % (lip * seg_len)
		if ramp_max > RULES.maxKickerGrade + 1e-3:
			issues.append("%s: ramp grade %.1f %% > %s %%" % [at, ramp_max * 100.0, RULES.maxKickerGrade * 100.0])
		if -land_min > RULES.maxLandingGrade + 1e-3:
			issues.append("%s: landing slope %.1f %% > %s %%" % [at, -land_min * 100.0, RULES.maxLandingGrade * 100.0])
		if land_len > RULES.landingZone:
			issues.append("%s: landing slope (%.0f m) longer than the landing zone" % [at, land_len])
		if max_turn > RULES.straightTol * DEGR:
			issues.append("%s: ramp/landing zone not straight (%.1f° heading change within %s m)" % [at, max_turn / DEGR, RULES.landingZone])
		var hr: Array = req.get("kickerHeight", [2.0, 7.5])
		if float(k.height) < float(hr[0]) - 0.05 or float(k.height) > float(hr[1]) + 0.05:
			issues.append("%s: height %.1f m outside %s-%s m" % [at, k.height, hr[0], hr[1]])
		var kk: Dictionary = k.duplicate()
		kk.rampMax = ramp_max
		kk.landMin = land_min
		kk.s = lip * seg_len
		kick.append(kk)
	if req.has("kickers") and int(req.kickers) > 0 and kick.size() < int(req.kickers):
		issues.append("needs at least %d kickers, has %d" % [req.kickers, kick.size()])
	if req.has("kickers") and int(req.kickers) == 0 and kick.size():
		issues.append("should have no kickers")

	var max_grade: float = 0.0
	var max_grade_at: int = 0
	var min_crest: float = INF
	var crest_at: int = 0
	for i in n:
		if not closed and (i < 1 or i > count - 2):
			continue
		var g: float = grade.call(i)
		if zone[i] == 0 and absf(g) > max_grade:
			max_grade = absf(g)
			max_grade_at = i
		if zone[i] == 2 and g > RULES.maxGrade + 1e-3:
			issues.append("climb of %.1f %% inside the landing at %.0f m" % [g * 100.0, i * seg_len])
		if not closed and (i < 4 or i > count - 5):
			continue
		var near: bool = false
		for k in kick:
			var a: int = int(k.foot) - 8
			var b: int = int(k.land) + 8
			if closed:
				if posmod(i - a, N) <= posmod(b - a, N):
					near = true
			elif i >= a and i <= b:
				near = true
		if near:
			continue
		var ypp: float = (py[tr.wrap(i + 4)] - 2.0 * py[i] + py[tr.wrap(i - 4)]) / pow(4.0 * seg_len, 2.0)
		if ypp < 0.0 and -1.0 / ypp < min_crest:
			min_crest = -1.0 / ypp
			crest_at = i
	var grade_limit: float = float(req.get("maxGrade", RULES.maxGrade))
	if max_grade > grade_limit + 1e-3:
		issues.append("grade %.1f %% at %.0f m > %.0f %%" % [max_grade * 100.0, max_grade_at * seg_len, grade_limit * 100.0])
	if min_crest < RULES.minCrestRadius:
		issues.append("crest at %.0f m too sharp: vertical radius %.0f m < %s m" % [crest_at * seg_len, min_crest, RULES.minCrestRadius])

	# heights (and how well the spline reproduced the designed profile)
	var min_y: float = INF
	var max_y: float = -INF
	var prof: float = 0.0
	for i in count:
		min_y = minf(min_y, py[i])
		max_y = maxf(max_y, py[i])
		prof = maxf(prof, absf(py[i] - turtle.profile_at((i * seg_len * float(f.length)) / L_, closed)))
	if min_y < RULES.minHeight - 0.01 or max_y > RULES.maxHeight + 0.01:
		issues.append("heights %.1f-%.1f m outside %s-%s m" % [min_y, max_y, RULES.minHeight, RULES.maxHeight])
	if prof > 0.15:
		issues.append("built heights differ from the design by up to %.2f m (banking lift or too few points)" % prof)
	if req.has("minClimb") and max_y - min_y < float(req.minClimb):
		issues.append("elevation range %.1f m < %s m" % [max_y - min_y, req.minClimb])

	# width
	var w_min: float = INF
	var w_max: float = 0.0
	var taper: float = 0.0
	for i in count:
		w_min = minf(w_min, 2.0 * hw[i])
		w_max = maxf(w_max, 2.0 * hw[i])
		if closed or i < count - 1:
			taper = maxf(taper, absf(hw[tr.wrap(i + 1)] - hw[i]) / seg_len)
	if req.has("width") and (w_min < float(req.width[0]) - 0.05 or w_max > float(req.width[1]) + 0.05):
		issues.append("width %.1f-%.1f m outside %s-%s m" % [w_min, w_max, req.width[0], req.width[1]])
	if req.has("widthSpread") and w_max - w_min < float(req.widthSpread) - 0.05:
		issues.append("width should vary by >= %s m (is %.1f-%.1f m)" % [req.widthSpread, w_min, w_max])
	if taper > RULES.maxTaper:
		issues.append("road width changes too abruptly (%.2f m per m)" % taper)

	# banking
	var max_bank: float = 0.0
	for i in count:
		max_bank = maxf(max_bank, absf(bank[i]) / DEGR)
	if max_bank > RULES.maxBank + 0.5:
		issues.append("banking %.1f° > %s°" % [max_bank, RULES.maxBank])
	if req.has("bank") and (max_bank < float(req.bank[0]) - 0.5 or max_bank > float(req.bank[1]) + 0.5):
		issues.append("max banking %.1f° outside %s-%s°" % [max_bank, req.bank[0], req.bank[1]])

	# hairpins: >= 150° of heading change within 150 m
	var hairpins: int = 0
	var W: int = JsMath.roundi(150.0 / seg_len)
	var i_h: int = 0
	while i_h < n - (0 if closed else W):
		var turn: float = 0.0
		for k in W:
			turn += _ang_diff(heading.call(i_h + k + 1), heading.call(i_h + k))
		if absf(turn) >= 150.0 * DEGR:
			hairpins += 1
			i_h += W
		i_h += 1
	if req.has("hairpins") and hairpins < int(req.hairpins):
		issues.append("needs >= %d hairpins, has %d" % [req.hairpins, hairpins])

	# checkpoints
	var cps: PackedInt32Array = tr.cp_samples
	var gates: Array[float] = []
	gates.append(0.0 if closed else tr.start_idx * seg_len)
	for c in cps:
		gates.append(c * seg_len)
	gates.append(L_ if closed else tr.finish_idx * seg_len)
	var gaps: Array[float] = []
	for k in range(1, gates.size()):
		var g: float = gates[k] - gates[k - 1]
		gaps.append(g)
		if g < float(RULES.cpGap[0]) or g > float(RULES.cpGap[1]):
			issues.append("gap %d between gates is %.0f m (allowed %s-%s m)" % [k, g, RULES.cpGap[0], RULES.cpGap[1]])
	for c in cps:
		for k in kick:
			var d: float = c - int(k.foot)
			if closed:
				d = fmod(fmod(d, N) + N + N / 2.0, N) - N / 2.0
			if d * seg_len >= -20.0 and d * seg_len <= posmod(int(k.lip) - int(k.foot), N) * seg_len + RULES.landingZone:
				issues.append("checkpoint at %.0f m is on the jump at %.0f m" % [c * seg_len, k.s])

	# start / finish on straights
	var straight_run := func(from: int, dir: int, mx: float) -> float:
		var h0: float = heading.call(from)
		var m: float = 0.0
		var k: int = 1
		while k * seg_len <= mx:
			var i: int = from + dir * k
			if not closed and (i < 0 or i > count - 1):
				break
			if absf(_ang_diff(heading.call(i), h0)) > RULES.straightTol * DEGR:
				break
			m = k * seg_len
			k += 1
		return m
	var start_run: float = straight_run.call(tr.start_idx, 1, 400.0)
	if start_run < RULES.startStraight:
		issues.append("only %.0f m of straight after the start (need %s)" % [start_run, RULES.startStraight])
	var start_flat: float = 0.0
	var i_s: int = tr.start_idx - 6
	while i_s <= tr.start_idx + RULES.startStraight / seg_len:
		start_flat = maxf(start_flat, absf(grade.call(tr.wrap(i_s))))
		i_s += 1
	if start_flat > 0.04:
		issues.append("start area not flat (grade %.1f %%)" % (start_flat * 100.0))
	if closed:
		var back: float = straight_run.call(0, -1, RULES.finishStraight)
		if back < RULES.finishStraight - seg_len:
			issues.append("start/finish line not on a straight (%.0f m straight before it)" % back)
	else:
		var back: float = straight_run.call(tr.finish_idx, -1, RULES.finishStraight)
		if back < RULES.finishStraight - seg_len:
			issues.append("finish not on a straight (%.0f m straight before it)" % back)
		if float(def.startAt) != RUN_IN or float(def.runOff) != RUN_OFF:
			issues.append("sprint needs startAt %s and runOff %s (has %s / %s)" % [RUN_IN, RUN_OFF, def.startAt, def.runOff])
		var run_in: float = straight_run.call(tr.start_idx, -1, RUN_IN)
		if run_in < tr.start_idx * seg_len - seg_len:
			issues.append("road before the start is not straight (%.0f m)" % run_in)
		var run_out: float = straight_run.call(tr.finish_idx, 1, RUN_OFF)
		var run_flat: float = 0.0
		for i in range(tr.finish_idx, count - 1):
			run_flat = maxf(run_flat, absf(grade.call(i)))
		if (count - 1 - tr.finish_idx) * seg_len < RUN_OFF - seg_len:
			issues.append("only %.0f m of road after the finish (need %s)" % [(count - 1 - tr.finish_idx) * seg_len, RUN_OFF])
		if run_out < RUN_OFF - 2.0 * seg_len:
			issues.append("run-off after the finish not straight (%.0f m)" % run_out)
		if run_flat > 0.04:
			issues.append("run-off after the finish not flat (grade %.1f %%)" % (run_flat * 100.0))

	var kick_grade: float = 0.0
	var land_grade: float = 0.0
	for k in kick:
		kick_grade = maxf(kick_grade, k.rampMax)
		land_grade = maxf(land_grade, -float(k.landMin))
	return {
		def = def, tr = tr, issues = issues, kick = kick, gaps = gaps,
		stats = {
			length = L_, race = L_ if closed else (tr.finish_idx - tr.start_idx) * seg_len, laps = def.get("laps", 1) if closed else 1,
			minR = min_r, minMargin = min_margin, minY = min_y, maxY = max_y, maxGrade = max_grade, minClear = min_clear, closure = closure,
			wMin = w_min, wMax = w_max, maxBank = max_bank, hairpins = hairpins, cps = cps.size(), minCrest = min_crest, startRun = start_run,
			prof = prof, kickGrade = kick_grade, landGrade = land_grade, points = (def.points as Array).size(),
		},
	}


# =============================================================================
# Output: data/tracks.json (the same fields and point format as trackData.js)
# =============================================================================

## The definitions as JSON text: one definition per block, four points a line.
static func tracks_json(defs: Array) -> String:
	var out: String = "[\n"
	for di in defs.size():
		var def: Dictionary = defs[di]
		out += "  {\n"
		for k: String in def.keys():
			if k == "points":
				continue
			out += "    %s: %s,\n" % [JSON.stringify(k), _value(def[k])]
		out += "    \"points\": [\n"
		var pts: Array = def.points
		var w: float = float(def.width)
		var i: int = 0
		while i < pts.size():
			var line: PackedStringArray = []
			for p: Array in pts.slice(i, i + 4):
				line.append(_point(p, w))
			out += "      " + ", ".join(line) + ("," if i + 4 < pts.size() else "") + "\n"
			i += 4
		out += "    ]\n  }%s\n" % ("," if di < defs.size() - 1 else "")
	return out + "]\n"


## A point the way trackData.js writes it: [x, z, h], then bank if it isn't 0 or the width differs, then the width if it differs.
static func _point(p: Array, w: float) -> String:
	var v: PackedStringArray = [JsMath.num_to_js(p[0]), JsMath.num_to_js(p[1]), JsMath.num_to_js(p[2])]
	if float(p[3]) != 0.0 or float(p[4]) != w:
		v.append(JsMath.num_to_js(p[3]))
	if float(p[4]) != w:
		v.append(JsMath.num_to_js(p[4]))
	return "[" + ", ".join(v) + "]"


static func _value(v: Variant) -> String:
	if v is String:
		return JSON.stringify(v)
	if v is Array:
		var parts: PackedStringArray = []
		for x: Variant in v:
			parts.append(_value(x))
		return "[" + ",".join(parts) + "]"
	return JsMath.num_to_js(float(v))
