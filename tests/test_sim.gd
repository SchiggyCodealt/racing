extends RefCounted
## test_sim.gd: checks of the simulation (sim/), run by tests/run_tests.gd:
##   godot --headless --path <copy> --script res://tests/run_tests.gd -- sim
## The important checks of the web game's web/tools/selfTest.mjs (v5), ported: tracks,
## the test autopilot on every track (and its times = the web game's), physics invariants
## (no wall bounce, walls cost speed, no sticking, walls never escaped at up to 360 km/h,
## no NaN under random controls), the racer still the v3 car, nitro rules, every car's
## stats, lane keeping, jumps, the style score, ghosts, medal times and the save file.
## About 2 minutes on one core (the physics runs ~15-40x slower in GDScript than in the
## browser); the car stats run on up to 4 threads.

const DT: float = 1.0 / 60.0
const CarStats = preload("res://tools/car_stats.gd")

## The web game's test autopilot (selfTest makeAutopilot, grip 11, braking 7.5) on every
## track: [finish time, wall-contact steps] (node, web v5; tools: /tmp scratch sim_ref.mjs).
const WEB_AUTOPILOT: Dictionary = {
	"rookie-oval": [157.50000000001748, 0],
	"hairpin-valley": [247.03333333342206, 0],
	"ramp-rally": [202.68333333338677, 0],
	"banked-speedway": [177.9000000000337, 0],
	"technical-trial": [257.46666666676117, 0],
	"grand-marathon": [182.93333333337105, 0],
	"coastal-gp": [233.78333333341152, 0],
	"mountain-pass": [128.43333333332768, 0],
	"canyon-run": [303.08333333338635, 0],
	"night-highway": [226.80000000007263, 0],
	"lighthouse-bay": [195.91666666671472, 0],
	"seaside-stunts": [80.24999999999673, 0],
}
## Every track's signature (Tracks.signature: layout, then the road surfaces). The first 12 must
## never change (records, ghosts, medals and AI best times are keyed to them); the three of
## v6.4 (tools/gen_tracks.gd) follow them in the menu.
const SIGS: Dictionary = {
	"rookie-oval": "1083:2167", "hairpin-valley": "1209:2417|snow480-812", "ramp-rally": "1187:2374|dirt168-730",
	"banked-speedway": "1422:2844", "technical-trial": "1296:2591", "grand-marathon": "3735:7468",
	"coastal-gp": "1448:2895", "mountain-pass": "2393:4783|dirt139-400,snow885-1349", "canyon-run": "1426:2853|dirt487-688",
	"night-highway": "1558:3117", "lighthouse-bay": "1175:2351", "seaside-stunts": "1654:3306",
	"forest-rally": "1272:2544|dirt126-1242", "northern-lights": "1413:2826|snow169-897,snow995-1383",
	"summit-rush": "2335:4668|dirt485-935,snow936-1429,dirt1868-2109",
}
## SHA-256 of the medal entries of the first 12 tracks in data/medals.json (JSON.stringify, keys
## sorted, in menu order) as v6.3 made them: adding tracks must leave them alone.
const V63_MEDALS_SHA: String = "015a8f566065d9a0483bf9418fa2c91f4d03f5619236f3b223c041bdc67fc0c2"
## The tracks of v6.4, in menu order (13-15): [surfaces, difficulty, race type]
const V64_TRACKS: Dictionary = {
	"forest-rally": ["Asphalt + dirt", 3, "circuit"],
	"northern-lights": ["Asphalt + packed snow", 4, "circuit"],
	"summit-rush": ["Asphalt + dirt + packed snow", 5, "sprint"],
}
## The web racer (= the v3 car) after every 10 s of a minute of that autopilot:
## x, y, z, yaw, vx, vy, vz, yawRate, pitch, roll, rpm, gear, prog.
const WEB_V3_STATES: Dictionary = {
	"hairpin-valley": [
		[346.59036433124976, 1, 6.724127629176517e-15, 1.5707963267948966, 31.30796902399148, 0, -6.023193604012617e-16, 1.519501522664623e-15, -0.025034293260503014, 1.6791271868059336e-16, 5139.802412534833, 4, 173.33460095548728],
		[325.8632200033879, 2.132752507872641, -109.57443979898932, 4.713765095390851, -33.59974251338158, 1.9249887269999277, 0.04942274382440061, -0.004173428830640731, 0.07441489750958112, -0.0006184850920238864, 6896.458684017143, 3, 286.87094027669394],
		[233.5005020742547, 6, -218.9272177570879, 1.6304022799918017, 22.68718230791394, 0, -1.2967851128745893, -0.17015588234105555, 0.03493744113551365, -0.015619208201911856, 7068.466281455018, 2, 406.7077757635049],
		[400.741262036746, 11, -316.08345447938973, 3.466436617528686, -5.400290359331209, 0, -16.04724752579911, 0.8056343004094995, -0.026970669098365572, 0.036658309261973096, 4567.138480770596, 2, 536.0857439908775],
		[32.86056524934208, 17.395447073087663, -328.7399032889005, 4.71238572412714, -48.161511335702215, -0.6397819638352331, -0.000011541198423581348, -0.000021151887106381437, -0.030024219453750674, -0.00000378199826685811, 6151.6982018067965, 5, 723.3359441080885],
		[-107.16780861183035, 12.553095015385953, -128.6626239850532, 6.283248685585836, 0.00021379175701269663, -0.27100649228270157, 25.751084523606735, -0.005191123964834102, -0.03701407582258984, -0.00009986567392195719, 4266.592277830741, 4, 883.8693961105557],
	],
	"ramp-rally": [
		[0.005142885810310163, 1.999992751423821, 331.60876199731047, 0.0025799219336665414, 0.0763637797686022, -0.000191484608222936, 32.84001910248624, 0.03310479835625079, -0.025279994907078343, 0.0010222175145357787, 5391.1442597876685, 4, 165.83201441890685],
		[254.59637459197313, 2, 345.0779047740978, 1.666156240147371, 31.793390621834842, 0, -3.397751558272796, -0.21151497717986628, 0.009304449097279711, -0.029089664912177796, 5148.174862987711, 4, 318.98251285742606],
		[664.3013658389333, 2.469592296153684, 344.84435970544047, 1.5711689186799807, 35.369335779455156, -1.3808831785901354, -0.010463314591824075, 0.0002695341766617953, -0.06806092354983172, 0.00014440722619846736, 4549.931019646013, 5, 523.8527693875365],
		[736.8230478830616, 2, 70.62459115835836, 3.1453061981781554, -0.12735624702422493, 0, -37.00281164513037, 0.0036043485872099255, 0.0038293937350041994, 0.0005824873985311998, 5966.528095581958, 4, 688.8433846541229],
		[518.2410005696987, 4.293437361966926, -76.78861143523659, 4.713091987047927, -47.356294006415226, -1.3142122752390684, 0.02836017602982386, 0.0008086919200564017, -0.01124071972667875, 0.00013886920087323294, 6036.829572333846, 5, 861.0639882387467],
		[184.10418585058466, 7.2083360027845815, -136.37845323959095, 4.703125531432777, -37.842738829131, -8.26343862582421, 0.314911799755625, -0.013124682141977316, -0.04421355210988713, -0.00031603199404719545, 8199.999999999998, 4, 1035.995292561758],
	],
}

var t: Variant # the runner's Checker: t.check(ok, msg), t.section(title)
var tracks: Array[BuiltTrack] = []
var _seed: int = 0


func run(checker: Variant) -> bool:
	t = checker
	_tracks_and_autopilot()
	_physics()
	_cars_and_nitro()
	_surfaces()
	_score()
	_ghosts()
	_medals()
	_save()
	_career()
	t.section("formatters")
	t.check(RaceState.format_time(119.9996) == "2:00.000" and RaceState.format_time(61.5) == "1:01.500" and RaceState.format_time(INF) == "--:--.---",
		"format_time rounds correctly (119.9996 s -> 2:00.000; no time -> --:--.---)")
	t.check(RaceState.format_delta(-1.25) == "-1.250" and RaceState.format_delta(0.0005) == "+0.001" and \
		ScoreState.format_points(43500) == "43,500" and ScoreState.format_points(-500) == "−500",
		"format_delta and format_points (+0.001, -1.250, 43,500, −500)")
	return true


# ---- helpers ------------------------------------------------------------------------

static func finite(car: Car) -> bool:
	return is_finite(car.x + car.y + car.z + car.vx + car.vy + car.vz + car.yaw + car.yaw_rate + car.pitch + car.roll)


static func wrap_a(a: float) -> float:
	return atan2(sin(a), cos(a))


static func ctrl(steer: float, throttle: float, handbrake: bool = false, nitro: float = 0.0) -> Car.Controls:
	return Car.Controls.new(steer, throttle, handbrake, nitro)


## Car on sample i of a track, `lat` m left of the centre, heading `angle` rad left of the road, at `speed`.
static func launch(track: BuiltTrack, i: int, lat: float, angle: float, speed: float, spec: CarSpec = null) -> Car:
	var car := Car.new(track, i, spec)
	var yaw: float = atan2(track.tx[i], track.tz[i]) + angle
	var x: float = track.px[i] + track.nx[i] * lat
	var z: float = track.pz[i] + track.nz[i] * lat
	car.place(track, i, {x = x, z = z, yaw = yaw, vx = sin(yaw) * speed, vz = cos(yaw) * speed, idx = i, laps = 0})
	return car


## selfTest's random numbers: (seed * 1103515245 + 12345) >>> 0, as JS computes it in doubles.
func rnd() -> float:
	var v: float = float(_seed) * 1103515245.0 + 12345.0
	_seed = int(fmod(v, 4294967296.0))
	return _seed / 4294967296.0


static func straight_road(id: String, n: int, width: float) -> BuiltTrack:
	var pts: Array = []
	for k in n:
		pts.append([0, k * 200, 0])
	return Tracks.build_def({id = id, name = id, type = "sprint", laps = 1, width = width, checkpoints = [], points = pts})


func by_id(id: String) -> BuiltTrack:
	return Tracks.build(id)


## Track `id` as the web game (v5) has it: all asphalt (the road surfaces of v6.3 stripped; the
## same layout and signature as before them). The checks against the web game's numbers use it.
static func asphalt(id: String) -> BuiltTrack:
	return Tracks.build_asphalt(id)


# ---- 1 + 2: build and drive every track; 3: backwards ------------------------------------

func _tracks_and_autopilot() -> void:
	t.section("tracks and the test autopilot")
	var ids: PackedStringArray = Tracks.ids()
	t.check(ids.size() == 15, "%d tracks defined (expected 15)" % ids.size())
	var exact: int = 0
	var plain_time: Dictionary = {} # id -> the test autopilot's time on the all-asphalt track
	for id: String in ids:
		tracks.append(Tracks.build(id))
		var track: BuiltTrack = asphalt(id) # (the web game's track: no dirt or snow)
		var car := Car.new(track)
		var race := RaceState.new(track)
		var pilot := Autopilot.basic(track)
		var steps: int = 0
		var wall: int = 0
		var bad: bool = false
		while not race.finished and steps < 36000:
			car.step(track, pilot.drive(car), DT)
			race.update(car, DT)
			if car.hit_wall:
				wall += 1
			if not finite(car):
				bad = true
				break
			steps += 1
		plain_time[id] = race.finish_time if race.finished else INF
		if not WEB_AUTOPILOT.has(id):
			# (a track of v6.4: the web game never had it)
			t.check(track.cp_samples.size() > 0 and track.length > 1000.0 and race.finished and not bad and wall == 0,
				"%s (all asphalt; new in v6.4): builds (%.2f km%s, %d checkpoints, %s); the test autopilot finishes in %s, wall contact in %d steps" % [
					track.name, track.race_length(1) / 1000.0, "/lap" if track.closed else "", track.cp_samples.size(),
					"%d laps" % track.laps if track.closed else "sprint", RaceState.format_time(race.finish_time), wall])
			continue
		var web: Array = WEB_AUTOPILOT.get(id, [INF, -1])
		var same: bool = race.finished and JsMath.roundi(race.finish_time * 1000.0) == JsMath.roundi(float(web[0]) * 1000.0) and wall == int(web[1])
		if same:
			exact += 1
		t.check(track.cp_samples.size() > 0 and track.length > 1000.0 and race.finished and not bad and absf(race.finish_time - float(web[0])) < 0.1,
			"%s%s: builds (%.2f km%s, %d checkpoints, %s); the test autopilot finishes in %s, wall contact in %d steps (web game: %s, %d)" % [
				track.name, " (all asphalt, as in the web game)" if track != tracks[-1] else "", track.race_length(1) / 1000.0, "/lap" if track.closed else "", track.cp_samples.size(),
				"%d laps" % track.laps if track.closed else "sprint", RaceState.format_time(race.finish_time), wall,
				RaceState.format_time(float(web[0])), int(web[1])])
	t.check(exact == WEB_AUTOPILOT.size(), "the test autopilot drives the web game's times to the millisecond (and its wall steps) on %d of the web game's %d tracks" % [exact, WEB_AUTOPILOT.size()])
	# the tracks with dirt or snow: the test autopilot, told the racer's grip on each surface, finishes them
	for track: BuiltTrack in tracks:
		if not track.has_surfaces():
			continue
		var spec: CarSpec = Cars.default_spec()
		var car := Car.new(track, track.start_idx, spec)
		var race := RaceState.new(track)
		var pilot := Autopilot.basic(track, 11.0, 7.5, 77.0, spec)
		var wall: int = 0
		var bad: bool = false
		while not race.finished and race.time < 600.0:
			car.step(track, pilot.drive(car), DT)
			race.update(car, DT)
			wall += 1 if car.hit_wall else 0
			if not finite(car):
				bad = true
				break
		var plain: float = float(plain_time.get(track.id, INF))
		t.check(race.finished and not bad and race.finish_time > plain,
			"%s (%s): the test autopilot finishes in %s with the racer, slower than on all asphalt (%s), wall contact in %d steps" % [
				track.name, Surfaces.summary(track), RaceState.format_time(race.finish_time), RaceState.format_time(plain), wall])

	_v64_tracks(ids)

	var rookie: BuiltTrack = tracks[0]
	var car := Car.new(rookie)
	car.yaw += PI
	var race := RaceState.new(rookie)
	for k in 60 * 15:
		car.step(rookie, ctrl(0.0, 1.0), DT)
		race.update(car, DT)
	t.check(race.next_gate == 0, "driving backwards over the line scores no checkpoints")


## The tracks of v6.4 (13-15) and the design rules: every track passes tools/gen_tracks.gd's
## rules and data/tracks.json is what it writes; the first 12 tracks are bit for bit those of
## v6.3 (their tracks.json text, signatures and medal times); the new ones follow them in the
## menu with rising difficulty and their own road surfaces and themes.
func _v64_tracks(ids: PackedStringArray) -> void:
	t.section("the tracks of v6.4 and the design rules")
	var gen: Object = load("res://tools/gen_tracks.gd").new()
	gen.call("_define")
	var defs: Array = []
	var issues: PackedStringArray = []
	var stats: PackedStringArray = []
	for d: Dictionary in gen.get("designs"):
		var e: Dictionary = gen.call("_realise", d)
		if e.is_empty():
			issues.append("%s cannot be built" % d.meta.id)
			continue
		var r: Dictionary = gen.call("_validate", e)
		defs.append(r.def)
		for msg: String in r.issues:
			issues.append("%s: %s" % [r.def.id, msg])
		if V64_TRACKS.has(r.def.id):
			var s: Dictionary = r.stats
			var jumps: int = (r.kick as Array).size()
			stats.append("%s %.2f km%s, radius >= %.0f m, %d jump%s, banking <= %.0f°, heights %.0f-%.0f m" % [
				r.def.name, float(s.race) / 1000.0, " a lap" if r.def.type == "circuit" else "", float(s.minR), jumps, "" if jumps == 1 else "s",
				float(s.maxBank), float(s.minY), float(s.maxY)])
	var text: String = gen.call("tracks_json", defs)
	var old12: String = gen.call("tracks_json", defs.slice(0, 12))
	gen.free()
	t.check(issues.is_empty() and defs.size() == ids.size() and text == FileAccess.get_file_as_string(Tracks.DATA_PATH),
		"all %d tracks pass the design rules of tools/gen_tracks.gd (clearance, radius, grades, jumps and landings, crests, heights, banking, checkpoints, surfaces) and data/tracks.json is up to date%s" % [
			defs.size(), "" if issues.is_empty() else ": " + "; ".join(issues)])
	t.check(old12.sha256_text() == "0d78a00fc7d179b2a37b3ebb64f3d53bd6774eac2758f7201883bbe4574f6c8e",
		"the 12 tracks of v6.3 are bit for bit as they were (their tracks.json text hashes as v6.3's whole file did)")
	# signatures: the old ones unchanged (and their layouts = v6.2's), the new ones as made
	var bad_sigs: PackedStringArray = []
	for id: String in ids:
		var tr: BuiltTrack = by_id(id)
		var legacy: String = Tracks.legacy_signature(id)
		if Tracks.signature(id) != String(SIGS.get(id, "?")) or tr.signature() != Tracks.signature(id) or \
				(legacy != "" and tr.layout_signature() != legacy) or (legacy == "") != V64_TRACKS.has(id):
			bad_sigs.append("%s %s" % [id, Tracks.signature(id)])
	t.check(bad_sigs.is_empty() and SIGS.size() == ids.size(),
		"track signatures: the 12 of v6.3 unchanged (layouts = v6.2's), the 3 of v6.4 as made, none of them a v6.2 one%s" % [
			"" if bad_sigs.is_empty() else ": changed " + ", ".join(bad_sigs)])
	# medal times of the old tracks unchanged (data/medals.json), the new ones for every car
	var md: Dictionary = Medals.data().get("tracks", {})
	var old_medals: String = ""
	for i in 12:
		old_medals += JSON.stringify(md.get(ids[i], {}), "", true)
	var new_ok: bool = true
	for id: String in V64_TRACKS:
		for c: String in Cars.ids():
			var m: Dictionary = Medals.medal_times(by_id(id), c)
			new_ok = new_ok and not m.is_empty() and is_equal_approx(float(m.bronze), float(Medals.medal_set(float(m.author)).bronze))
	t.check(old_medals.sha256_text() == V63_MEDALS_SHA and new_ok,
		"medal times: the 12 tracks of v6.3 keep theirs bit for bit; the 3 of v6.4 have them for all %d cars (bronze = %s x the author time, rounded up, as everywhere)" % [
			Cars.ids().size(), JsMath.num_to_js(float(Medals.data().get("factors", {}).get("bronze", 1.5)))])
	# menu order, difficulty, surfaces, race type, themes
	var old_themes: Dictionary = {}
	for i in 12:
		old_themes[by_id(ids[i]).theme] = true
	var meta_ok: bool = ids.size() == 15 and Array(ids.slice(12)) == V64_TRACKS.keys()
	var themes: PackedStringArray = []
	var last_diff: int = 0
	for id: String in V64_TRACKS:
		var tr: BuiltTrack = by_id(id)
		var want: Array = V64_TRACKS[id]
		var diff: int = int(tr.def.get("difficulty", 0))
		meta_ok = meta_ok and Surfaces.summary(tr) == String(want[0]) and diff == int(want[1]) and diff > last_diff and \
			String(tr.def.get("type", "")) == String(want[2]) and not old_themes.has(tr.theme) and not themes.has(tr.theme)
		last_diff = diff
		themes.append(tr.theme)
	t.check(meta_ok, "tracks 13-15 after Seaside Stunts, difficulty 3, 4, 5, each with a theme of its own (%s): %s" % [", ".join(themes), "; ".join(stats)])


# ---- 4: physics -----------------------------------------------------------------------

func _physics() -> void:
	t.section("physics: walls, NaN, the racing line")
	# 4a. no bounce: 30° into the left wall at 50 m/s on a straight, wheels straight; the same hit
	# must cost at least half the speed within 0.5 s
	var worst: float = 0.0
	var kept: float = INF
	var loss: float = INF
	for track: BuiltTrack in tracks:
		var i: int = track.start_idx + 15
		var car: Car = launch(track, i, 0.0, PI / 6.0, 50.0)
		var touched: bool = false
		var reb: float = 0.0
		var tt: float = 0.0
		var before: float = car.speed
		var t_hit: float = 0.0
		var after: float = NAN
		while tt < 1.5:
			var v: float = car.speed
			car.step(track, ctrl(0.0, 0.0), DT)
			tt += DT
			var n: int = car.idx
			var vn: float = car.vx * track.nx[n] + car.vz * track.nz[n] # + = towards the left wall
			if car.hit_wall and not touched:
				touched = true
				before = v
				t_hit = tt
			if touched:
				reb = maxf(reb, -vn)
			if touched and is_nan(after) and tt - t_hit > 0.5 - 1e-6:
				after = car.speed
		worst = maxf(worst, reb)
		kept = minf(kept, car.speed)
		loss = minf(loss, 1.0 - after / before)
		if not touched:
			worst = INF
	t.check(worst <= 1.0 + 1e-3, "no wall bounce: 30° hit at 50 m/s rebounds at most %.2f m/s (limit 1.0), car keeps >= %d km/h" % [worst, JsMath.roundi(kept * 3.6)])
	t.check(loss >= 0.5, "walls cost speed: that 30° hit at 180 km/h takes at least %d %% of the speed within 0.5 s (limit 50 %%)" % JsMath.roundi(loss * 100.0))

	# 4a2. no sticking: pressed nose-in against a wall at 45-85°, the car steers off at full throttle
	var w_stick: float = 0.0
	var where: String = ""
	for track: BuiltTrack in tracks:
		var i: int = track.start_idx + 15
		for deg: float in [45.0, 55.0, 65.0, 75.0, 85.0]:
			var car: Car = launch(track, i, track.hw[i] - 3.5, deg * PI / 180.0, 5.0)
			for k in 60:
				car.step(track, ctrl(0.0, 1.0), DT) # pressed into the left wall
			var free: int = 0
			var k: int = 0
			while k < 600 and free < 30:
				car.step(track, ctrl(-1.0, 1.0), DT)
				free = 0 if car.hit_wall else free + 1
				k += 1
			var secs: float = (k - 30) / 60.0
			if free < 30 or secs > w_stick:
				w_stick = INF if free < 30 else secs
				where = "%s %d°" % [track.name, int(deg)]
	t.check(w_stick <= 3.0, "no sticking: a car pressed nose-in against a wall at 45-85° steers off at full throttle within %.2f s (worst: %s; limit 3 s)" % [w_stick, where])

	# 4b. no tunnelling: shots at 300 and 360 km/h into the walls at many angles and places
	var shots: int = 0
	var escapes: int = 0
	var worst_lat: float = -INF
	for track: BuiltTrack in tracks:
		var f: float = 0.05
		while f < 1.0:
			var i: int = floori(track.count * f)
			for speed: float in [83.3, 100.0]:
				for deg: float in [10.0, 30.0, 50.0, 70.0, 90.0, -20.0, -45.0, -80.0]:
					var car: Car = launch(track, i, 0.0, deg * PI / 180.0, speed)
					var prev_idx: int = car.idx
					for k in 90:
						car.step(track, ctrl(0.0, 1.0), DT)
						var out: float = absf(car.lat) - car._hw
						worst_lat = maxf(worst_lat, out)
						var jump: int = absi(car.idx - prev_idx)
						if track.closed:
							jump = mini(jump, track.N - jump)
						if out > 0.0 or jump > 30 or not finite(car):
							escapes += 1
							break
						prev_idx = car.idx
					shots += 1
			f += 0.15
	t.check(escapes == 0, "no tunnelling: %d wall shots at 300-360 km/h, %d cars left the road (closest centre %.2f m inside the wall line)" % [shots, escapes, -worst_lat])

	# 4c. no NaN: random controls, random respawns, on every track (and never outside the walls)
	var steps: int = 0
	var bad: int = 0
	var below: int = 0
	var outside: int = 0
	_seed = 12345
	for track: BuiltTrack in tracks:
		var car := Car.new(track)
		var c := ctrl(0.0, 0.0)
		for k in 6000:
			if k % 30 == 0:
				c.steer = rnd() * 2.0 - 1.0
				c.throttle = 1.0 if rnd() * 2.4 - 1.2 > 0.0 else rnd() * 2.0 - 1.0
				c.handbrake = rnd() < 0.15
			if k % 900 == 0:
				car.place(track, floori(rnd() * (track.count - 1)))
			car.step(track, c, DT)
			steps += 1
			if not finite(car):
				bad += 1
				car.place(track, track.start_idx)
			if car.grounded and car.y < car.ground_y - 0.05:
				below += 1
			if absf(car.lat) > car._hw:
				outside += 1
	t.check(bad == 0 and below == 0 and outside == 0, "no NaN: %d random-control steps, %d non-finite states, %d steps below the road, %d outside the walls" % [steps, bad, below, outside])

	# 4d. the racing line pays: on Hairpin Valley the clean autopilot beats one that never brakes
	# (the web game's all-asphalt track; on its snow since v6.3: see _surfaces)
	var hairpin: BuiltTrack = asphalt("hairpin-valley")
	var lap := func(grip: float) -> Dictionary:
		var car := Car.new(hairpin)
		var race := RaceState.new(hairpin, 1)
		var pilot := Autopilot.basic(hairpin, grip, 7.5, 77.0)
		var wall: int = 0
		while not race.finished and race.time < 300.0:
			car.step(hairpin, pilot.drive(car), DT)
			race.update(car, DT)
			if car.hit_wall:
				wall += 1
		return {time = race.finish_time if race.finished else INF, wall = wall}
	var clean: Dictionary = lap.call(11.0)
	var rider: Dictionary = lap.call(INF)
	t.check(clean.wall == 0 and clean.time < rider.time, "walls cost time: Hairpin Valley lap, clean autopilot %s (%d wall steps) beats never braking %s (wall contact in %d steps)" % [
		RaceState.format_time(clean.time), clean.wall, RaceState.format_time(rider.time), rider.wall])


# ---- 4f: road surfaces (v6.3) ---------------------------------------------------------------

func _surfaces() -> void:
	t.section("road surfaces: dirt and packed snow")
	# the table: asphalt first and neutral; every car has a grip share on every surface
	var a: Dictionary = Surfaces.def(Surfaces.ASPHALT)
	var ok: bool = Surfaces.id(0) == "asphalt" and Surfaces.index_of("dirt") > 0 and Surfaces.index_of("snow") > 0 and Surfaces.index_of("mud") == -1 and \
		float(a.grip) == 1.0 and float(a.roll) == 1.0 and float(a.stiffness) == 1.0 and float(a.esc) == 1.0
	var dirt: int = Surfaces.index_of("dirt")
	var snow: int = Surfaces.index_of("snow")
	var best_dirt: String = ""
	var worst_dirt: String = ""
	var best_snow: String = ""
	var worst_snow: String = ""
	var grips: PackedStringArray = []
	for id: String in Cars.ids():
		var g: PackedFloat64Array = Cars.spec(id).surface_grip
		ok = ok and g.size() == Surfaces.count() and g[0] == 1.0 and g[snow] < g[dirt] and g[dirt] < 1.0
		if best_dirt == "" or g[dirt] > Cars.spec(best_dirt).surface_grip[dirt]:
			best_dirt = id
		if worst_dirt == "" or g[dirt] < Cars.spec(worst_dirt).surface_grip[dirt]:
			worst_dirt = id
		if best_snow == "" or g[snow] > Cars.spec(best_snow).surface_grip[snow]:
			best_snow = id
		if worst_snow == "" or g[snow] < Cars.spec(worst_snow).surface_grip[snow]:
			worst_snow = id
		grips.append("%s %d%%/%d%%" % [id, roundi(g[dirt] * 100.0), roundi(g[snow] * 100.0)])
	t.check(ok and best_dirt == "dune" and best_snow == "dune" and worst_dirt == "vortex" and worst_snow == "vortex",
		"the surface table: asphalt neutral; every car keeps less grip on dirt and less again on packed snow, the Dune the most and the Vortex the least (%s)" % ", ".join(grips))

	# the tracks: dirt on Ramp Rally, Mountain Pass and Canyon Run, packed snow on the alpine Hairpin
	# Valley and Mountain Pass; the start grid on asphalt; the layout (and v6.2 signature) unchanged.
	# v6.4: Forest Rally mostly dirt, Northern Lights mostly snow, Summit Rush all three
	var want: Dictionary = {"ramp-rally": "Asphalt + dirt", "canyon-run": "Asphalt + dirt", "hairpin-valley": "Asphalt + packed snow",
		"mountain-pass": "Asphalt + dirt + packed snow"}
	for id: String in V64_TRACKS:
		want[id] = V64_TRACKS[id][0]
	var lines: PackedStringArray = []
	ok = true
	for tr: BuiltTrack in tracks:
		var summary: String = Surfaces.summary(tr)
		var legacy: String = Tracks.legacy_signature(tr.id)
		var sig_ok: bool = (tr.layout_signature() == legacy or (legacy == "" and V64_TRACKS.has(tr.id))) and \
			(tr.signature() == tr.layout_signature()) == (not tr.has_surfaces()) and Tracks.signature(tr.id) == tr.signature()
		ok = ok and summary == String(want.get(tr.id, "Asphalt")) and sig_ok
		if tr.has_surfaces():
			var n: int = tr.N if tr.closed else tr.count
			var sums_ok: bool = tr.surf_w.size() == tr.count * tr.surf_n and tr.surface.size() == tr.count
			var step_max: float = 0.0
			for i in tr.count:
				var sum: float = 0.0
				for k in tr.surf_n:
					sum += tr.surf_w[i * tr.surf_n + k]
					if i > 0:
						step_max = maxf(step_max, absf(tr.surf_w[i * tr.surf_n + k] - tr.surf_w[(i - 1) * tr.surf_n + k]))
				sums_ok = sums_ok and absf(sum - 1.0) < 1e-5
			var grid_ok: bool = true
			for i in range(tr.start_idx - 6, tr.start_idx + 6):
				grid_ok = grid_ok and tr.surface[tr.wrap(i)] == Surfaces.ASPHALT
			var shares: Dictionary = Surfaces.shares(tr)
			var parts: PackedStringArray = []
			for k: int in shares:
				parts.append("%s %d%%" % [Surfaces.id(k), roundi(float(shares[k]) * 100.0)])
			ok = ok and sums_ok and step_max <= 1.0 / (2 * Surfaces.BLEND + 1) + 1e-5 and grid_ok
			lines.append("%s: %s (%s)" % [tr.name, ", ".join(parts), tr.signature().get_slice("|", 1)])
	t.check(ok, "surfaces on %d tracks (4 of v6.3, 3 of v6.4), the other %d all asphalt with their v6.2 signatures; blend weights add up to 1 and change at most 1/%d a sample (about %d m from one surface to the next); the start grid on asphalt; %s" % [
		lines.size(), tracks.size() - lines.size(), 2 * Surfaces.BLEND + 1, roundi((2 * Surfaces.BLEND + 1) * 2.0), "; ".join(lines)])

	# asphalt is the old physics: on Ramp Rally the racer drives bit for bit as on the all-asphalt
	# Ramp Rally until an axle reaches the dirt; then the surface counts
	var rr: BuiltTrack = by_id("ramp-rally")
	var plain: BuiltTrack = asphalt("ramp-rally")
	var c1 := Car.new(rr)
	var c2 := Car.new(plain)
	var p1 := Autopilot.basic(rr)
	var p2 := Autopilot.basic(plain)
	var same_steps: int = 0
	var same: bool = true
	while not c1._env_loose and same_steps < 60 * 120:
		c1.step(rr, p1.drive(c1), DT)
		c2.step(plain, p2.drive(c2), DT)
		if c1._env_loose:
			break
		same = same and var_to_bytes(c1.to_state()) == var_to_bytes(c2.to_state())
		same_steps += 1
	for k in 600:
		c1.step(rr, p1.drive(c1), DT)
		c2.step(plain, p2.drive(c2), DT)
	t.check(same and same_steps > 300 and c1.prog < c2.prog - 1.0,
		"asphalt runs the v6.2 physics: on Ramp Rally the racer drives bit for bit as on the all-asphalt track for %.1f s, until the front axle reaches the dirt; 10 s later it is %.0f m behind" % [
			same_steps * DT, (c2.prog - c1.prog) * rr.seg_len])

	# the change of grip is smooth: across the border onto the dirt at 25 m/s the front axle's grip
	# share slides from 1 to the car's dirt grip over several metres, never in one jump
	var i0: int = 0
	for i in range(1, rr.count):
		if rr.surface[i] == dirt and rr.surface[i - 1] == Surfaces.ASPHALT:
			i0 = i
			break
	var car := Car.new(rr, rr.wrap(i0 - 20))
	var y0: float = car.yaw
	car.place(rr, car.idx, {x = car.x, z = car.z, yaw = y0, vx = sin(y0) * 25.0, vz = cos(y0) * 25.0, idx = car.idx, laps = 0})
	var pilot := Autopilot.basic(rr)
	var gfs: PackedFloat64Array = []
	for k in 150:
		var cc := pilot.drive(car)
		cc.throttle = clampf((25.0 - car.forward_speed) * 0.5, -1.0, 1.0)
		car.step(rr, cc, DT)
		gfs.append(car._env_gf)
	var target: float = Cars.default_spec().surface_grip[dirt]
	var jump: float = 0.0
	var ramp: int = 0
	for k in range(1, gfs.size()):
		jump = maxf(jump, absf(gfs[k] - gfs[k - 1]))
		if gfs[k] < 1.0 and gfs[k] > target:
			ramp += 1
	t.check(gfs[0] == 1.0 and absf(gfs[-1] - target) < 1e-9 and ramp * DT * 25.0 >= 6.0 and jump < 0.05,
		"onto the dirt at 90 km/h: the front grip share goes from 1 to %.2f over %.1f m (%d steps), at most %.3f a step" % [target, ramp * DT * 25.0, ramp, jump])

	# what each surface does to a car: braking from 100 km/h and the fastest steady turn (30 m
	# radius) on synthetic roads of dirt and snow (tools/car_stats.gd): the Dune loses the least
	var brake: Dictionary = {}
	var turn: Dictionary = {}
	for sid: String in ["asphalt", "dirt", "snow"]:
		CarStats.surface = sid
		for id: String in ["racer", "dune", "vortex"]:
			brake["%s %s" % [id, sid]] = CarStats.brake100(Cars.spec(id))
	for sid: String in ["dirt"]:
		CarStats.surface = sid
		for id: String in ["dune", "vortex"]:
			turn["%s %s" % [id, sid]] = CarStats.skidpad(Cars.spec(id), 30.0)
	CarStats.surface = "asphalt"
	var rs: Dictionary = Cars.get_car("racer").stats
	ok = brake["racer dirt"] > brake["racer asphalt"] and brake["racer snow"] > brake["racer dirt"] and \
		brake["vortex snow"] / brake["vortex asphalt"] > brake["dune snow"] / brake["dune asphalt"] and \
		brake["vortex dirt"] / brake["vortex asphalt"] > brake["dune dirt"] / brake["dune asphalt"] and \
		turn["dune dirt"] > turn["vortex dirt"] + 0.4 and absf(float(Cars.get_car("dune").stats.grip) - float(Cars.get_car("vortex").stats.grip)) < 0.1 and \
		absf(brake["racer asphalt"] - float(rs.brake100)) < 0.06
	t.check(ok, "100-0 km/h: the racer stops in %.1f m on asphalt, %.1f on dirt, %.1f on snow; the Dune %.1f / %.1f / %.1f, the Vortex %.1f / %.1f / %.1f. Fastest 30 m turn on dirt: Dune %.2f g, Vortex %.2f g (on asphalt both about %.2f g)" % [
		brake["racer asphalt"], brake["racer dirt"], brake["racer snow"], brake["dune asphalt"], brake["dune dirt"], brake["dune snow"],
		brake["vortex asphalt"], brake["vortex dirt"], brake["vortex snow"], turn["dune dirt"], turn["vortex dirt"], float(rs.grip)])

	# walls still cost time where the road is loose (weak brakes make a wall a better brake than
	# on asphalt): one lap with the Racer, the medal autopilot (no nitro) at the sweep's usual
	# settings against the same autopilot never braking. (The banked snow bowls of Northern
	# Lights take more than the usual 18-22 m/s² of planned grip: the best of the sweep's range
	# up to 40 counts, as it does for the medal times.)
	var gaps: PackedStringArray = []
	ok = true
	for id: String in ["hairpin-valley", "ramp-rally", "mountain-pass", "canyon-run", "forest-rally", "northern-lights", "summit-rush"]:
		var tr: BuiltTrack = by_id(id)
		var clean: float = INF
		for a_lat: float in ([18.0, 22.0] if Tracks.legacy_signature(id) != "" else [18.0, 22.0, 28.0, 32.0, 40.0]):
			clean = minf(clean, _medal_lap(tr, a_lat).x)
		var ride: Vector2 = _medal_lap(tr, 1000.0)
		ok = ok and clean < ride.x
		gaps.append("%s %s against %s (%d wall steps)" % [tr.name, RaceState.format_time(clean), RaceState.format_time(ride.x), int(ride.y)])
	t.check(ok, "walls cost time on dirt and snow too: the medal autopilot's lap beats never braking on %s" % ", ".join(gaps))


## One lap of `tr` with the Racer and the medal autopilot (a_lat, look 0.75, no nitro):
## Vector2(time, wall steps).
func _medal_lap(tr: BuiltTrack, a_lat: float) -> Vector2:
	var car := Car.new(tr)
	var race := RaceState.new(tr, 1)
	var pilot := Autopilot.medal(tr, a_lat, 0.75, false, Autopilot.DECEL, Cars.default_spec())
	var wall: int = 0
	while not race.finished and race.time < 300.0:
		car.step(tr, pilot.drive(car), DT)
		race.update(car, DT)
		if car.hit_wall:
			wall += 1
	return Vector2(race.finish_time if race.finished else INF, wall)


# ---- 4e: cars and nitro ------------------------------------------------------------------

func _cars_and_nitro() -> void:
	t.section("cars and nitro")
	var ids: PackedStringArray = Cars.ids()
	var rookie: BuiltTrack = tracks[0]

	# the racer: the default car, and nitro off, 0 or with an empty tank changes nothing
	var lap_state := func(mode: int) -> Dictionary:
		var car := Car.new(rookie)
		var pilot := Autopilot.basic(rookie)
		for k in 60 * 60:
			var c: Car.Controls = pilot.drive(car)
			if mode == 1:
				c.nitro = 0.0
			elif mode == 2:
				if k == 0:
					car.nitro = 0.0
				c.nitro = 1.0
			car.step(rookie, c, DT)
		var s: Dictionary = car.to_state()
		s.erase("nitro")
		return s
	var plain: Dictionary = lap_state.call(0)
	var same: bool = plain == lap_state.call(1) and plain == lap_state.call(2)
	var ids_ok: bool = ids.size() == 6
	for id: String in ids:
		ids_ok = ids_ok and Cars.spec(id).id == id
	t.check(Cars.get_car("nope").id == "racer" and Car.new().spec == Cars.default_spec() and Cars.spec("racer") == Cars.default_spec() and \
		Car.PHYSICS_VERSION == 3 and same and ids_ok and not Car.new(rookie).to_state().has("spec"),
		"cars: %s; the racer is the default, physics v%d; with nitro off or an empty tank it drives a minute of Rookie Oval bit for bit as without; no spec in car states" % [
			", ".join(ids), Car.PHYSICS_VERSION])

	# the racer is still the v3 car: its state every 10 s of a minute of the test autopilot on Hairpin
	# Valley and Ramp Rally (jumps) = the web game's (which pins it to the v3 code with a hash)
	var diff: float = 0.0
	var air: int = 0
	for id: String in ["hairpin-valley", "ramp-rally"]:
		var track: BuiltTrack = asphalt(id) # (the web game's track: no dirt or snow)
		var car := Car.new(track)
		var pilot := Autopilot.basic(track)
		var rows: Array = WEB_V3_STATES[id]
		for k in range(1, 3601):
			car.step(track, pilot.drive(car), DT)
			if not car.grounded:
				air += 1
			if k % 600 == 0:
				var mine: Array = [car.x, car.y, car.z, car.yaw, car.vx, car.vy, car.vz, car.yaw_rate, car.pitch, car.roll, car.rpm, car.gear, car.prog]
				var web: Array = rows[k / 600 - 1]
				for j in mine.size():
					diff = maxf(diff, absf(float(mine[j]) - float(web[j])))
	t.check(diff < 1e-6, "the racer is still the v3 car: x, y, z, yaw, velocity, yaw rate, pitch, roll, rpm, gear and progress every 10 s of 2 autopilot minutes (%d airborne steps) = the web game's within %s (limit 1e-6)" % [
		air, JsMath.num_to_js(diff)])

	# stats on the car picker = the physics (tools/car_stats.gd; one thread per car)
	var measured: Dictionary = _measure_cars(ids)
	var off: PackedStringArray = []
	var tops: PackedStringArray = []
	var nitro_tops: PackedStringArray = []
	for id: String in ids:
		var stats: Dictionary = Cars.get_car(id).stats
		tops.append("%s %s" % [id, JsMath.num_to_js(float(stats.top))])
		nitro_tops.append(JsMath.num_to_js(float(stats.topNitro)))
		for o: Dictionary in CarStats.stats_mismatch(stats, measured[id]):
			off.append("%s %s %s -> %s" % [id, o.key, o.stored, JsMath.num_to_js(float(o.measured))])
	t.check(off.is_empty(), "car stats match the physics (top speed %s km/h; with nitro %s)%s" % [", ".join(tops), ", ".join(nitro_tops),
		"" if off.is_empty() else "; OFF: %s (run tools/car_stats.gd)" % ", ".join(off)])

	# walls, every car: no bounce (30° at 50 m/s) and no tunnelling at its top speed with nitro + 10 %, nitro held
	var worst: float = 0.0
	var shots: int = 0
	var escapes: int = 0
	var where: String = ""
	var fastest: float = 0.0
	for id: String in ids:
		var spec: CarSpec = Cars.spec(id)
		fastest = maxf(fastest, float(Cars.get_car(id).stats.topNitro))
		var v_top: float = (float(Cars.get_car(id).stats.topNitro) / 3.6) * 1.1
		for track: BuiltTrack in tracks:
			var i: int = track.start_idx + 15
			var car: Car = launch(track, i, 0.0, PI / 6.0, 50.0, spec)
			var touched: bool = false
			var reb: float = 0.0
			for k in 90:
				car.step(track, ctrl(0.0, 0.0), DT)
				var vn: float = car.vx * track.nx[car.idx] + car.vz * track.nz[car.idx]
				if car.hit_wall:
					touched = true
				if touched:
					reb = maxf(reb, -vn)
			if not touched:
				reb = INF
			if reb > worst:
				worst = reb
				where = "%s on %s" % [id, track.name]
			for f: float in [0.2, 0.55, 0.85]:
				var j: int = floori(track.count * f)
				for deg: float in [10.0, 30.0, 60.0, 90.0, -25.0, -60.0]:
					var c: Car = launch(track, j, 0.0, deg * PI / 180.0, v_top, spec)
					var prev_idx: int = c.idx
					for k in 90:
						c.add_nitro(1.0)
						c.step(track, ctrl(0.0, 1.0, false, 1.0), DT)
						var jump: int = absi(c.idx - prev_idx)
						if track.closed:
							jump = mini(jump, track.N - jump)
						if absf(c.lat) > c._hw or jump > 30 or not finite(c):
							escapes += 1
							break
						prev_idx = c.idx
					shots += 1
	t.check(worst <= 1.0 + 1e-3 and escapes == 0, "walls, every car: a 30° hit at 50 m/s rebounds at most %.2f m/s (%s; limit 1.0); %d wall shots at each car's top speed with nitro + 10 %% (up to %d km/h), %d left the road" % [
		worst, where, shots, JsMath.roundi(fastest * 1.1), escapes])

	# no NaN, every car: random controls with nitro (on/off/analogue, refills), handbrake and respawns
	var steps: int = 0
	var bad: int = 0
	var below: int = 0
	var boosted: int = 0
	_seed = 4242
	for id: String in ids:
		for track: BuiltTrack in tracks:
			var car := Car.new(track, track.start_idx, Cars.spec(id))
			var c := ctrl(0.0, 0.0)
			for k in 1500:
				if k % 30 == 0:
					c.steer = rnd() * 2.0 - 1.0
					c.throttle = 1.0 if rnd() * 2.4 - 1.2 > 0.0 else rnd() * 2.0 - 1.0
					c.handbrake = rnd() < 0.15
					var n: float = rnd()
					c.nitro = 0.0 if n < 0.4 else (1.0 if n < 0.8 else rnd())
					if rnd() < 0.3:
						car.add_nitro(rnd())
				if k % 500 == 0:
					car.place(track, floori(rnd() * (track.count - 1)))
				car.step(track, c, DT)
				steps += 1
				if car.boosting:
					boosted += 1
				if not finite(car) or not (car.nitro >= 0.0 and car.nitro <= 1.0):
					bad += 1
					car.place(track, track.start_idx)
				if car.grounded and car.y < car.ground_y - 0.05:
					below += 1
	t.check(bad == 0 and below == 0 and boosted > steps / 10.0, "no NaN, every car: %d random-control steps with nitro (boosting in %d), %d non-finite states or tanks out of 0..1, %d steps below the road" % [
		steps, boosted, bad, below])

	_every_car_finishes(ids)
	_nitro_rules(ids)
	_lane_keeping(ids)
	_jumps(ids)


## Every car finishes every track with the test autopilot planned for that car (its skidpad grip and
## braking against the racer's, its top speed; as the web game's self test), on threads. A car drives
## clean (no wall contact) on every track where the four original cars all do.
func _every_car_finishes(ids: PackedStringArray) -> void:
	var r: Dictionary = Cars.get_car("racer").stats
	var res: Dictionary = {}
	var mutex := Mutex.new()
	var jobs: Array = []
	for id: String in ids:
		for track: BuiltTrack in tracks:
			jobs.append([id, track])
	var next: Array[int] = [0]
	var work := func() -> void:
		while true:
			mutex.lock()
			var j: int = next[0]
			next[0] += 1
			mutex.unlock()
			if j >= jobs.size():
				return
			var id: String = jobs[j][0]
			var track: BuiltTrack = jobs[j][1]
			var def: Dictionary = Cars.get_car(id)
			var spec: CarSpec = def.spec
			var grip: float = 11.0 * (float(def.stats.grip) / float(r.grip))
			var brake: float = 7.5 * (float(r.brake100) / float(def.stats.brake100))
			var car := Car.new(track, track.start_idx, spec)
			var race := RaceState.new(track)
			var pilot := Autopilot.basic(track, grip, brake, spec.max_speed, spec)
			var wall: int = 0
			var bad: bool = false
			while not race.finished and race.time < 600.0:
				car.step(track, pilot.drive(car), DT)
				race.update(car, DT)
				if car.hit_wall:
					wall += 1
				if not finite(car):
					bad = true
					break
			mutex.lock()
			res["%s|%s" % [id, track.id]] = {done = race.finished and not bad, time = race.finish_time, wall = wall}
			mutex.unlock()
	var pool: Array[Thread] = []
	for k in mini(4, OS.get_processor_count()):
		var th := Thread.new()
		th.start(work)
		pool.append(th)
	for th in pool:
		th.wait_to_finish()
	var lines: PackedStringArray = []
	var all_done: bool = true
	var clean_ok: bool = true
	for id: String in ids:
		var done: int = 0
		var total: float = 0.0
		var walls: int = 0
		var dirty: PackedStringArray = []
		for track: BuiltTrack in tracks:
			var e: Dictionary = res["%s|%s" % [id, track.id]]
			if e.done:
				done += 1
				total += float(e.time)
			walls += int(e.wall)
			var others_clean: bool = true
			for o: String in ["racer", "kestrel", "thunder", "drifter"]:
				others_clean = others_clean and int(res["%s|%s" % [o, track.id]].wall) == 0
			if others_clean and int(e.wall) > 0:
				dirty.append(track.name)
		all_done = all_done and done == tracks.size()
		clean_ok = clean_ok and dirty.is_empty()
		lines.append("%s %d/%d in %s (wall contact in %d steps%s)" % [id, done, tracks.size(), RaceState.format_time(total), walls,
			"" if dirty.is_empty() else "; NOT CLEAN: " + ", ".join(dirty)])
	t.check(all_done and clean_ok, "every car finishes every track with the test autopilot planned for its grip and braking, clean wherever the four original cars are: %s" % "; ".join(lines))


## Every car's stats, measured on threads (one per car, at most 4).
func _measure_cars(ids: PackedStringArray) -> Dictionary:
	CarStats.prepare()
	var out: Dictionary = {}
	var mutex := Mutex.new()
	var pool: Array[Thread] = []
	var n_threads: int = mini(mini(4, OS.get_processor_count()), ids.size())
	var next: Array[int] = [0]
	var work := func() -> void:
		while true:
			mutex.lock()
			var j: int = next[0]
			next[0] += 1
			mutex.unlock()
			if j >= ids.size():
				return
			var m: Dictionary = CarStats.measure_car(Cars.spec(ids[j]))
			mutex.lock()
			out[ids[j]] = m
			mutex.unlock()
	for k in n_threads:
		var th := Thread.new()
		th.start(work)
		pool.append(th)
	for th in pool:
		th.wait_to_finish()
	return out


## Nitro: a full tank at the start, kept on respawn; burns nitroTime s at full nitro (half rate at 0.5)
## on the ground in a forward gear; no push or burn in the air, in reverse, braking or with the handbrake;
## it makes every car faster.
func _nitro_rules(ids: PackedStringArray) -> void:
	var straight: BuiltTrack = straight_road("nitro-straight", 31, 30.0)
	var ok: PackedStringArray = []
	for id: String in ids:
		var spec: CarSpec = Cars.spec(id)
		var car := Car.new(straight, 5, spec)
		var rules: bool = car.nitro == 1.0
		car.nitro = 0.4
		car.place(straight, 20)
		rules = rules and car.nitro == 0.4
		rules = rules and car.add_nitro(5.0) == 1.0 and car.add_nitro(-7.0) == 0.0 and car.add_nitro(0.25) == 0.25
		# full tank, full nitro from a standstill: lasts nitroTime (to the step), boosting all along
		var a := Car.new(straight, 5, spec)
		var steps: int = 0
		var k: int = 0
		while k < 6000 and a.nitro > 0.0:
			a.step(straight, ctrl(0.0, 0.0, false, 1.0), DT)
			if a.boosting:
				steps += 1
			k += 1
		rules = rules and absf(steps * DT - spec.nitro_time) < DT + 1e-9
		# half nitro burns at half rate
		var b := Car.new(straight, 5, spec)
		for s in 60:
			b.step(straight, ctrl(0.0, 1.0, false, 0.5), DT)
		rules = rules and absf(1.0 - b.nitro - (0.5 * 60.0 * DT) / spec.nitro_time) < 1e-9 and b.boost == 0.5
		# braking from 108 km/h, then reversing: no boost, no burn
		var c := Car.new(straight, 100, spec)
		c.place(straight, 100, {x = straight.px[100], z = straight.pz[100], yaw = 0.0, vx = 0.0, vz = 30.0, idx = 100, laps = 0})
		var pushed: int = 0
		for s in 60 * 6:
			c.step(straight, ctrl(0.0, -1.0, false, 1.0), DT)
			if c.boosting:
				pushed += 1
		rules = rules and c.nitro == 1.0 and pushed == 0 and c.forward_speed < -1.0
		# handbrake held: no boost and no burn, standing for 2 s or at 100 km/h with the throttle open
		var h := Car.new(straight, 100, spec)
		var hf := Car.new(straight, 100, spec)
		for s in 120:
			h.step(straight, ctrl(0.0, 0.0, true, 1.0), DT)
			if h.boosting:
				pushed += 1
		hf.place(straight, 100, {x = straight.px[100], z = straight.pz[100], yaw = 0.0, vx = 0.0, vz = 100.0 / 3.6, idx = 100, laps = 0})
		for s in 60:
			hf.step(straight, ctrl(0.0, 1.0, true, 1.0), DT)
			if hf.boosting:
				pushed += 1
		rules = rules and pushed == 0 and h.nitro == 1.0 and hf.nitro == 1.0 and JsMath.hypot2(h.x - straight.px[100], h.z - straight.pz[100]) < 0.05
		ok.append(id if rules else "%s FAILED" % id)
	# airborne: holding nitro over a jump burns nothing while in the air
	var air_steps: int = 0
	var air_burn: int = 0
	for track: BuiltTrack in tracks:
		if track.kickers.is_empty():
			continue
		var car := Car.new(track, track.start_idx, Cars.spec("racer"))
		var pilot := Autopilot.basic(track, 14.0)
		var k: int = 0
		while k < 60 * 120 and air_steps < 200:
			var c: Car.Controls = pilot.drive(car)
			if not car.grounded:
				car.add_nitro(1.0) # nitro held with a full tank through the whole flight
				car.step(track, ctrl(c.steer, 1.0, c.handbrake, 1.0), DT)
				air_steps += 1
				if car.nitro != 1.0 or car.boosting:
					air_burn += 1
			else:
				car.step(track, c, DT)
			k += 1
	var faster: bool = true
	var times: PackedStringArray = []
	var lasts: PackedStringArray = []
	for id: String in ids:
		var s: Dictionary = Cars.get_car(id).stats
		faster = faster and float(s.accel200n) < float(s.accel200) - 0.5 and float(s.topNitro) > float(s.top) + 5.0
		times.append("%s s (%s)" % [JsMath.num_to_js(float(s.accel200n)), JsMath.num_to_js(float(s.accel200))])
		lasts.append("%s s" % JsMath.num_to_js(Cars.spec(id).nitro_time))
	var all_ok: bool = true
	for s: String in ok:
		all_ok = all_ok and not s.contains("FAILED")
	t.check(all_ok and air_steps > 100 and air_burn == 0 and faster,
		"nitro: full tank at the start and kept on respawn, lasts its nitroTime (%s), half nitro burns half as fast, nothing in reverse, braking, with the handbrake or in the air (%d airborne steps); 0-200 km/h with nitro %s [%s]" % [
			" / ".join(lasts), air_steps, ", ".join(times), ", ".join(ok)])


## Keyboard lane keeping, every car: a digital-steering driver holding speed on a straight never
## builds a fishtail (4 speeds × 3 dead bands × 3 aim distances, the keyboard steering ramp).
func _lane_keeping(ids: PackedStringArray) -> void:
	var lane: BuiltTrack = straight_road("lane", 41, 40.0)
	var res: PackedStringArray = []
	var fails: int = 0
	for id: String in ids:
		var fish: int = 0
		for kmh: float in [120.0, 160.0, 200.0, 240.0]:
			for dead: float in [0.02, 0.04, 0.08]:
				for look: float in [20.0, 35.0, 50.0]:
					var v: float = kmh / 3.6
					var i0: int = 20
					var car := Car.new(lane, i0, Cars.spec(id))
					car.place(lane, i0, {x = lane.px[i0] + 2.0, z = lane.pz[i0], yaw = 0.0, vx = 0.0, vz = v, idx = i0, laps = 0})
					var steer: float = 0.0
					var max_slip: float = 0.0
					var late: float = 0.0
					var c := ctrl(0.0, 0.0)
					for s in 60 * 15:
						var gx: float = -car.x
						var gz: float = look
						var fx: float = sin(car.yaw)
						var fz: float = cos(car.yaw)
						var ang: float = atan2(gx * fz - gz * fx, gx * fx + gz * fz)
						var target: float = 1.0 if ang > dead else (-1.0 if ang < -dead else 0.0)
						var rate: float = 10.0 if target == 0.0 or target * steer < 0.0 else 7.0 + (3.2 - 7.0) * minf(1.0, car.speed / 50.0)
						steer += JsMath.sign(target - steer) * minf(absf(target - steer), rate * DT)
						c.steer = steer
						c.throttle = 1.0 if car.forward_speed < v else 0.0
						car.step(lane, c, DT)
						max_slip = maxf(max_slip, absf(atan2(car.side_speed, car.forward_speed)) * 57.3)
						if s > 600:
							late = maxf(late, absf(wrap_a(car.yaw)) * 57.3)
					if late > 5.0 or max_slip > 10.0:
						fish += 1
		fails += fish
		res.append("%s %d/36" % [id, fish])
	t.check(fails == 0, "keyboard lane keeping at 120-240 km/h, no fishtail with any car: %s" % ", ".join(res))


## Jumps, every car: the test autopilot over every kicker (a steer key held through some flights):
## no bounce, no spin.
func _jumps(ids: PackedStringArray) -> void:
	var jumps: int = 0
	var bounces: int = 0
	var spins: int = 0
	var max_air: float = 0.0
	for id: String in ids:
		for track: BuiltTrack in tracks:
			if track.kickers.is_empty():
				continue
			for hold: int in [0, 1]:
				var car := Car.new(track, track.start_idx, Cars.spec(id))
				var pilot := Autopilot.basic(track, 13.0)
				var goal: float = car.prog + track.N if track.closed else float(track.count - 12)
				var yaw0: float = 0.0
				var landed: int = -1000000000
				var watch: int = 0
				var k: int = 0
				while k < 60 * 300 and car.prog < goal:
					var c: Car.Controls = pilot.drive(car)
					if not car.grounded and hold:
						c.steer = 1.0
					var g0: bool = car.grounded
					car.step(track, c, DT)
					if g0 and not car.grounded:
						jumps += 1
						if k - landed < 30:
							bounces += 1
						yaw0 = car.yaw
					if not g0 and car.grounded:
						max_air = maxf(max_air, absf(wrap_a(car.yaw - yaw0)) * 57.3)
						landed = k
						watch = 120
					if watch > 0:
						watch -= 1
						if absf(wrap_a(car.yaw - atan2(track.tx[car.idx], track.tz[car.idx]))) > PI / 2.0:
							spins += 1
							watch = 0
					k += 1
	t.check(jumps >= 40 and bounces == 0 and spins == 0 and max_air < 35.0,
		"jumps, every car: %d jumps, %d bounces, %d spins; holding a steer key through a whole flight turns the car at most %.1f° (limit 35°)" % [jumps, bounces, spins, max_air])


# ---- 12: the style score ------------------------------------------------------------------

## One scored Drive race: driver.drive(car) gives the controls (an Autopilot or a DriftDriver);
## nitro: use it at full throttle on straights.
func scored_race(track: BuiltTrack, driver: Variant, spec: CarSpec = null, nitro: bool = false, refill: bool = true) -> Dictionary:
	var car := Car.new(track, track.start_idx, spec)
	var race := RaceState.new(track)
	var score := ScoreState.new(track, refill)
	var events: Array[Dictionary] = []
	var steps: int = 0
	while not race.finished and steps < 60 * 900:
		var c: Car.Controls = driver.drive(car)
		c.nitro = 1.0 if nitro and c.throttle == 1.0 and absf(c.steer) < 0.25 else 0.0
		car.step(track, c, DT)
		race.update(car, DT)
		events.append_array(score.update(car, race, DT))
		steps += 1
	return {race = race, score = score, events = events, car = car}


static func sig(r: Dictionary) -> String:
	var parts: PackedStringArray = []
	for e: Dictionary in r.events:
		parts.append("%s%s" % [e.kind, JsMath.num_to_js(float(e.points))])
	return ",".join(parts)


## A "player" who pulls the handbrake into the bends, then countersteers towards where the car goes.
class DriftDriver:
	var track: BuiltTrack
	var base: Autopilot
	var pull: float = 0.0
	var wait: float = 0.0

	func _init(t: BuiltTrack) -> void:
		track = t
		base = Autopilot.medal(t, 14.0, 0.55)

	func turn(i: int) -> float:
		var n: int = track.count
		var p: int = (i - 3 + n) % n
		var q: int = (i + 3) % n
		var a: float = atan2(track.tx[q], track.tz[q]) - atan2(track.tx[p], track.tz[p])
		return atan2(sin(a), cos(a))

	func drive(car: Car) -> Car.Controls:
		var c: Car.Controls = base.drive(car)
		c.handbrake = false
		wait -= 1.0 / 60.0
		var ahead: int = (car.idx + JsMath.roundi((8.0 + car.speed * 0.4) / track.seg_len)) % track.count
		if pull <= 0.0 and wait <= 0.0 and absf(turn(ahead)) > 0.12 and car.speed > 16.0 and car.grounded:
			pull = 0.35
			wait = 3.0
		if pull > 0.0:
			pull -= 1.0 / 60.0
			c.handbrake = true
			c.steer = JsMath.sign(turn(ahead))
			c.throttle = 0.0
		else:
			var a: float = atan2(car.vx, car.vz) - car.yaw
			var slip: float = atan2(sin(a), cos(a))
			if absf(slip) > 0.15:
				c.steer = maxf(-1.0, minf(1.0, c.steer * 0.5 + slip * 1.5))
				c.throttle = maxf(c.throttle, 0.5)
		return c


func _score() -> void:
	t.section("style score")
	var S: Dictionary = ScoreState.SCORE
	# 12a. deterministic, and a clean race scores exactly what the rules say (= the web game's 43,500, 19 events)
	var rookie: BuiltTrack = by_id("rookie-oval")
	var a: Dictionary = scored_race(rookie, Autopilot.basic(rookie))
	var b: Dictionary = scored_race(rookie, Autopilot.basic(rookie))
	var sa: ScoreState = a.score
	var gates: int = (a.race as RaceState).gates.size()
	var cps: float = 0.0
	for i in gates:
		cps += float(S.cpPoints) * mini(int(S.comboMax), i + 1)
	var expect: float = cps + float(S.cleanLap) * (a.race as RaceState).laps + float(S.cleanRun)
	t.check(sa.total == (b.score as ScoreState).total and sig(a) == sig(b) and sa.counts.wall_hits == 0 and sa.total == expect and \
		sa.total == 43500.0 and a.events.size() == 19,
		"score: the clean autopilot on %s scores %s twice in a row with the same %d events (%d clean gates up to x%d, %d clean laps, clean run: %s expected; web game: 43,500, 19 events)" % [
			rookie.name, ScoreState.format_points(sa.total), a.events.size(), gates, int(S.comboMax), (a.race as RaceState).laps, ScoreState.format_points(expect)])

	# 12b. clean driving pays: on Hairpin Valley the clean autopilot outscores a corner-cutting one that hits the walls
	var hairpin: BuiltTrack = by_id("hairpin-valley")
	var clean: Dictionary = scored_race(hairpin, Autopilot.basic(hairpin, 11.0, 7.5, 77.0, Cars.default_spec())) # (it knows the snow)
	var rough: Dictionary = scored_race(hairpin, Autopilot.basic(hairpin, 21.0))
	var rc: Dictionary = (rough.score as ScoreState).counts
	t.check((clean.score as ScoreState).counts.wall_hits == 0 and rc.wall_hits > 0 and rc.clean_gates < rc.gates and \
		(clean.score as ScoreState).total > (rough.score as ScoreState).total + 10000.0,
		"score: clean driving pays on %s: clean %s vs %s for a wall-hitting run (%d wall contacts, %d of %d clean checkpoints)" % [
			hairpin.name, ScoreState.format_points((clean.score as ScoreState).total), ScoreState.format_points((rough.score as ScoreState).total),
			rc.wall_hits, rc.clean_gates, rc.gates])

	# 12c. a handbrake slide scores a drift (Lighthouse Bay)
	var bay: BuiltTrack = by_id("lighthouse-bay")
	var drift: Dictionary = scored_race(bay, DriftDriver.new(bay))
	var plain: Dictionary = scored_race(bay, Autopilot.medal(bay, 14.0, 0.55))
	var ds: ScoreState = drift.score
	var drifts: Array[Dictionary] = []
	var drifts_ok: bool = true
	for e: Dictionary in drift.events:
		if e.kind == "drift":
			drifts.append(e)
			drifts_ok = drifts_ok and float(e.points) > 0.0 and float(e.time) >= float(S.driftMin)
	t.check(drifts.size() >= 10 and drifts_ok and (plain.score as ScoreState).counts.drifts == 0 and (drift.race as RaceState).finished and \
		ds.total > (plain.score as ScoreState).total and ds.counts.wall_hits == 0,
		"score: handbrake slides score drifts: %d drifts on %s (%s, best %s, no wall contact); total %s vs %s driving it without drifts" % [
			drifts.size(), bay.name, ScoreState.format_points(ds.points.drift), ScoreState.format_points(ds.counts.best_drift),
			ScoreState.format_points(ds.total), ScoreState.format_points((plain.score as ScoreState).total)])

	# 12d. jumps score air: every kicker of Seaside Stunts, landed cleanly (web game: 7,120)
	var stunts: BuiltTrack = by_id("seaside-stunts")
	var jumps: Dictionary = scored_race(stunts, Autopilot.basic(stunts))
	var airs: PackedStringArray = []
	var airs_ok: bool = true
	for e: Dictionary in jumps.events:
		if e.kind == "air":
			airs.append("%.1f s" % float(e.time))
			airs_ok = airs_ok and float(e.time) >= float(S.airMin) and float(e.points) > 0.0
		elif e.kind == "airLost":
			airs_ok = false
	var js: ScoreState = jumps.score
	t.check(airs.size() == 6 and airs_ok and js.points.air == 7120.0, "score: jumps score air: %d of 6 kickers on %s (%s; %s, web game 7,120)" % [
		airs.size(), stunts.name, ", ".join(airs), ScoreState.format_points(js.points.air)])

	# 12e. banked points refill the tank, so a nitro autopilot gets faster with the refills; respawns cost
	# points, lose the combo and refill nothing; the score never goes below zero
	var night: BuiltTrack = by_id("night-highway")
	var one: Dictionary = scored_race(night, Autopilot.basic(night), null, true, false)
	var refilled: Dictionary = scored_race(night, Autopilot.basic(night), null, true)
	var kestrel: Dictionary = scored_race(night, Autopilot.basic(night), Cars.spec("kestrel"), true)
	var sc := ScoreState.new(rookie)
	var car := Car.new(rookie)
	car.add_nitro(-0.5)
	var race := RaceState.new(rookie)
	var resp: Dictionary = {}
	var s: int = 0
	while s < 60 * 40 and resp.is_empty():
		car.step(rookie, ctrl(0.0, 1.0), DT)
		race.update(car, DT)
		sc.update(car, race, DT)
		if sc.combo >= 1 and sc.total >= float(S.cpPoints):
			var before: float = sc.total
			resp = {before = before, nitro = car.nitro, ev = sc.respawn()}
		s += 1
	var zero: Array[Dictionary] = ScoreState.new(rookie).respawn() # nothing to take yet
	var rs: ScoreState = refilled.score
	var t_one: float = (one.race as RaceState).finish_time
	var t_ref: float = (refilled.race as RaceState).finish_time
	t.check(rs.nitro > 2.0 and t_ref < t_one - 1.0 and (kestrel.score as ScoreState).nitro > 2.0 and not resp.is_empty() and \
		sc.total == float(resp.before) - float(S.respawnPoints) and sc.multiplier() == 1 and car.nitro == resp.nitro and \
		(resp.ev as Array)[0].kind == "respawn" and float(zero[0].points) == 0.0,
		"score: points refill nitro: on %s the nitro autopilot gets %.2f tanks back (%.2f s faster than with one tank, %s; kestrel %.2f tanks); a respawn costs %d, resets the combo, refills nothing; the score never goes below 0" % [
			night.name, rs.nitro, t_one - t_ref, RaceState.format_time(t_ref), (kestrel.score as ScoreState).nitro, int(S.respawnPoints)])

	# 12g. no farming on Seaside Stunts; a wall touch ending just before a gate spoils only its own section
	var clean_air: float = js.points.air
	var clean_tanks: float = js.nitro_earned
	var fr: Dictionary = _farm(stunts, "respawn")
	var fb: Dictionary = _farm(stunts, "back")
	var ended: int = _gate_test(rookie, [10, 11, 12, 13])
	var merged: int = _gate_test(rookie, [10, 11, 12, 13, 26])
	var at_gate: int = _gate_test(rookie, [10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20])
	t.check(fr.loops >= 5 and fb.loops >= 5 and fr.done and fb.done and fr.air <= clean_air and fb.air <= clean_air + 100.0 and \
		fr.tanks <= clean_tanks and fb.tanks <= clean_tanks + 0.01 and ended == 1 and merged == 0 and at_gate == 0,
		"score: no farming on %s: %d respawns before kickers bank %s air, %d re-jumps from 150 m back %s (clean run %s; nitro %.2f / %.2f / %.2f tanks); a touch ending 0.12 s before a gate leaves the next section clean, one more touch after it doesn't" % [
			stunts.name, fr.loops, ScoreState.format_points(fr.air), fb.loops, ScoreState.format_points(fb.air), ScoreState.format_points(clean_air),
			fr.tanks, fb.tanks, clean_tanks])


## Respawn to the checkpoint before a kicker after every landing ("respawn", speed kept as in Drive),
## or go back 150 m before the kicker to jump it again ("back").
func _farm(stunts: BuiltTrack, mode: String) -> Dictionary:
	var car := Car.new(stunts)
	var race := RaceState.new(stunts)
	var score := ScoreState.new(stunts)
	var pilot := Autopilot.basic(stunts)
	var loops: int = 0
	var flight: float = 0.0
	var wait: float = 0.0
	var kick: Dictionary = {}
	var air: float = 0.0
	while not race.finished and race.time < 600.0:
		car.step(stunts, pilot.drive(car), DT)
		race.update(car, DT)
		for e: Dictionary in score.update(car, race, DT):
			if e.kind == "air":
				air += float(e.points)
		if not car.grounded:
			flight += DT
			if flight > 0.2 and kick.is_empty():
				kick = stunts.kickers[0]
				for k: Dictionary in stunts.kickers:
					if absi(int(k.lip) - car.idx) < absi(int(kick.lip) - car.idx):
						kick = k
			continue
		if flight >= float(ScoreState.SCORE.airMin):
			wait = 0.6
		flight = 0.0
		if wait > 0.0:
			wait -= DT
			if wait <= 0.0 and not kick.is_empty() and loops < 30 and (mode == "back" or not race.respawn.is_empty()):
				var r: Dictionary = race.respawn
				var i: int = mini(int(r.idx) + 6, stunts.finish_idx - 1) if mode == "respawn" else maxi(1, int(kick.lip) - JsMath.roundi(150.0 / stunts.seg_len))
				var yaw: float = atan2(stunts.tx[i], stunts.tz[i])
				var v: float = JsMath.hypot2(float(r.vx), float(r.vz)) if mode == "respawn" else car.speed
				if mode == "respawn":
					score.respawn()
				car.place(stunts, i, {x = stunts.px[i], z = stunts.pz[i], yaw = yaw, vx = sin(yaw) * v, vz = cos(yaw) * v, idx = i, laps = 0})
				loops += 1
				kick = {}
	return {loops = loops, air = air, tanks = score.nitro_earned, done = race.finished}


## A scripted wall touch on a car standing still, two gates passed by hand: the clean gates.
func _gate_test(rookie: BuiltTrack, touch: Array) -> int:
	var sc := ScoreState.new(rookie, false)
	var race := RaceState.new(rookie)
	var gates: Array[Dictionary] = [{kind = "cp"}, {kind = "cp"}]
	race.gates = gates
	var car := Car.new()
	car.grounded = true
	for k in 120:
		car.hit_wall = touch.has(k)
		if k == 20 or k == 100:
			race.next_gate += 1
		sc.update(car, race, DT)
	return int(sc.counts.clean_gates)


# ---- 9 + 13: ghosts -------------------------------------------------------------------------

func _ghosts() -> void:
	t.section("ghosts")
	var worst: float = 0.0
	var worst_at: String = ""
	var worst_yaw: float = 0.0
	var at_samples: float = 0.0
	var chars: int = 0
	var minutes: float = 0.0
	var wall_steps: int = 0
	var synced: bool = true
	# Hairpin Valley with a corner-cutting autopilot that hits the walls; Ramp Rally (jumps) driven clean
	for pair: Array in [["hairpin-valley", 21.0], ["ramp-rally", 11.0]]:
		var track: BuiltTrack = by_id(pair[0])
		var car := Car.new(track)
		var race := RaceState.new(track)
		var pilot := Autopilot.basic(track, float(pair[1]))
		var rec := Replay.GhostRecorder.new()
		var truth: Array[PackedFloat64Array] = [] # [step, x, y, z, yaw] after each step (after the jump at the respawn step)
		rec.add(0, car, true)
		truth.append(PackedFloat64Array([0, car.x, car.y, car.z, car.yaw]))
		var step: int = 0
		var jumped: bool = false
		while not race.finished and step < 60 * 600:
			car.step(track, pilot.drive(car), DT)
			step += 1
			race.update(car, DT)
			if car.hit_wall:
				wall_steps += 1
			rec.add(step, car, race.finished)
			if not jumped and race.next_gate == 3 and step % 2: # respawn at the last checkpoint, off the 30 Hz grid
				jumped = true
				rec.before_jump(step, car)
				var r: Dictionary = race.respawn.duplicate()
				var j: int = int(r.idx) + 6
				r.idx = j
				r.x = track.px[j]
				r.z = track.pz[j]
				car.place(track, j, r)
				rec.after_jump(step, car)
			truth.append(PackedFloat64Array([step, car.x, car.y, car.z, car.yaw]))
		var text: String = JSON.stringify(Replay.pack_ghost(rec, {track = track, laps = race.laps, time = race.finish_time}))
		var ghost: Dictionary = Replay.unpack_ghost(JSON.parse_string(text), track, race.laps)
		if ghost.is_empty():
			synced = false
			continue
		var play := Replay.GhostPlayer.new(ghost)
		var sampled: Dictionary = {}
		for s: int in rec.steps:
			sampled[s] = true
		for row: PackedFloat64Array in truth:
			if not play.pose(row[0]):
				synced = false
				break
			var e: float = JsMath.hypot3(play.car.x - row[1], play.car.y - row[2], play.car.z - row[3])
			if e > worst:
				worst = e
				worst_at = "%s step %d" % [track.name, int(row[0])]
			if sampled.has(int(row[0])):
				at_samples = maxf(at_samples, e)
			worst_yaw = maxf(worst_yaw, absf(wrap_a(play.car.yaw - row[4])))
		synced = synced and jumped and ghost.end == step and absf(ghost.end * DT - race.finish_time) < 1e-6 and not play.pose(step + 0.01)
		chars += text.length()
		minutes += race.finish_time / 60.0
	var per_min: float = chars / 1024.0 / minutes
	var bronze_min: float = 0.0
	var n_ghosts: int = 0
	var md: Dictionary = Medals.data()
	for id: String in (md.get("tracks", {}) as Dictionary):
		for c: String in (md.tracks[id].cars as Dictionary):
			bronze_min += float(md.tracks[id].cars[c].bronze) / 60.0
			n_ghosts += 1
	t.check(synced and worst < 0.03 and at_samples < 0.01 and worst_yaw < 0.005 and per_min < 80.0,
		"ghost replay: 2 recorded autopilot runs (one respawn each, %d wall-contact steps) replay within %.1f cm at every physics step (worst: %s; %.2f cm at the samples, yaw %.1f mrad), on the race clock; packed %.1f K characters per minute (base64; %d ghosts, one per track and car, at their bronze times: %.2f M characters)" % [
			wall_steps, worst * 100.0, worst_at, at_samples * 100.0, worst_yaw * 1000.0, per_min, n_ghosts, per_min * bronze_min / 1024.0])

	# bad saved data: anything foreign or broken is ignored without a script error
	var t0: BuiltTrack = tracks[0]
	var rec0 := Replay.GhostRecorder.new()
	var car0 := Car.new(t0)
	for s in 121:
		if s:
			car0.step(t0, ctrl(0.0, 1.0), DT)
		rec0.add(s, car0, s == 120)
	var good: Dictionary = Replay.pack_ghost(rec0, {track = t0, laps = 3, time = 2.0})
	var with := func(k: String, v: Variant) -> Dictionary:
		var d: Dictionary = good.duplicate()
		d[k] = v
		return d
	var data: String = good.data
	var bad: Array = [null, "ghost", 42, [], {}, with.call("format", 2), with.call("format", 1), with.call("format", "3"), with.call("physics", 2),
		with.call("track", "hairpin-valley"), with.call("track", 7), with.call("laps", 1), with.call("laps", "3"), with.call("sig", "1:1"), with.call("sig", 5),
		with.call("time", NAN), with.call("time", 9), with.call("time", "2"), with.call("n", int(good.n) + 1), with.call("n", 1e9), with.call("n", "x"),
		with.call("steps", 118), with.call("data", data.substr(0, data.length() - 8)), with.call("data", data + "AAAA"),
		with.call("data", "%%%not base64%%%"), with.call("data", null), with.call("data", 5),
		with.call("car", "bus"), with.call("car", 42), with.call("car", null), with.call("car", "__proto__"),
		with.call("boost", 5), with.call("boost", null), with.call("boost", "%%%"), with.call("boost", ""),
		with.call("boost", Marshalls.raw_to_base64(PackedByteArray([5, 10, 196, 6, 0]))), # a change after the finish (step 901)
		with.call("boost", Marshalls.raw_to_base64(PackedByteArray([5, 11]))), with.call("boost", Marshalls.raw_to_base64(PackedByteArray([5, 10, 0, 0])))]
	var ignored: int = 0
	for b: Variant in bad:
		if Replay.unpack_ghost(b, t0, 3).is_empty() and Replay.unpack_ghost(b, t0, 3, "racer").is_empty():
			ignored += 1
	t.check(ignored == bad.size() and not Replay.unpack_ghost(good, t0, 3).is_empty(),
		"ghost data: %d of %d foreign or broken saved ghosts ignored (other format, physics, track, layout, laps, car, time, sample count, bad base64, bad nitro data, wrong types)" % [ignored, bad.size()])

	# a ghost keeps its car and its nitro: a Kestrel run that burns nitro in bursts (no refills)
	var kspec: CarSpec = Cars.spec("kestrel")
	var car := Car.new(t0, t0.start_idx, kspec)
	var race := RaceState.new(t0)
	var pilot := Autopilot.basic(t0)
	var recd := Replay.GhostRecorder.new()
	var boosts: PackedFloat64Array = [0.0]
	recd.add(0, car, true)
	for step in range(1, 901):
		var c: Car.Controls = pilot.drive(car)
		c.nitro = 1.0 if step % 150 < 70 else 0.0 # on and off
		car.step(t0, c, DT)
		race.update(car, DT)
		recd.add(step, car, step == 900)
		boosts.append(car.boost)
	var saved: Variant = JSON.parse_string(JSON.stringify(Replay.pack_ghost(recd, {track = t0, laps = 3, time = 15.0, car = "kestrel"})))
	var g: Dictionary = Replay.unpack_ghost(saved, t0, 3, "kestrel")
	var boost_ok: bool = not g.is_empty()
	var burned: int = 0
	if boost_ok:
		var play := Replay.GhostPlayer.new(g)
		for st in 901:
			play.pose(st)
			boost_ok = boost_ok and play.car.boost == float(boosts[st]) and play.car.boosting == (boosts[st] > 0.0)
			if boosts[st] > 0.0:
				burned += 1
		play.pose(450.5) # between steps: the step before
		boost_ok = boost_ok and play.car.boost == float(boosts[450])
		play.pose(10) # and back in time
		boost_ok = boost_ok and play.car.boost == float(boosts[10])
	var car_ok: bool = saved is Dictionary and saved.car == "kestrel" and g.get("car") == "kestrel" and \
		Replay.unpack_ghost(saved, t0, 3).get("car") == "kestrel" and Replay.unpack_ghost(saved, t0, 3, "racer").is_empty() and \
		not Replay.ghost_fits(saved, t0, 3, "thunder") and Replay.ghost_fits(saved, t0, 3, "kestrel") and \
		Replay.unpack_ghost(Replay.pack_ghost(recd, {track = t0, laps = 3, time = 15.0}), t0, 3, "racer").get("car") == "racer"
	t.check(boost_ok and burned > 100 and car_ok, "ghost car and nitro: a Kestrel ghost (%d nitro changes) replays as the Kestrel with its nitro exactly at every physics step (%d steps burning) and only for the Kestrel; no car tag: the racer" % [
		recd.boost_steps.size(), burned])


# ---- 10: medal times -----------------------------------------------------------------------

func _medals() -> void:
	t.section("medal times (data/medals.json)")
	var d: Dictionary = Medals.data()
	var covered: int = 0
	var ordered: int = 0
	var ids: PackedStringArray = Cars.ids()
	for track: BuiltTrack in tracks:
		for c: String in ids:
			var m: Dictionary = Medals.medal_times(track, c)
			if m.is_empty():
				continue
			covered += 1
			var tidy: Dictionary = Medals.medal_set(float(m.author))
			if m.author < m.gold and m.gold < m.silver and m.silver < m.bronze and tidy.gold == m.gold and tidy.silver == m.silver and tidy.bronze == m.bronze:
				ordered += 1
	var pairs: int = tracks.size() * ids.size()
	var t0: BuiltTrack = tracks[0]
	var none: bool = Medals.medal_times(t0, "bus").is_empty() and Medals.medal_times(t0, "__proto__").is_empty() and \
		Medals.medal_times(t0, "racer", t0.laps + 1).is_empty() and Medals.medal_times(t0) == Medals.medal_times(t0, "racer")
	t.check(JsMath.same(d.get("physics"), Car.PHYSICS_VERSION) and JsMath.same(d.get("scoreRules"), ScoreState.SCORE_RULES) and covered == pairs and ordered == pairs and \
		(d.get("tracks", {}) as Dictionary).size() == tracks.size() and none,
		"medal times: %d of %d tracks × cars have them for their Drive race under physics v%s and scoring rules v%s (sim: v%d, v%d); author < gold < silver < bronze on %d; none for an unknown car or another lap count" % [
			covered, pairs, d.get("physics"), d.get("scoreRules"), Car.PHYSICS_VERSION, ScoreState.SCORE_RULES, ordered])

	# the shortest race whose racer author run touched a wall, driven again with every car
	var best: BuiltTrack = null
	var best_key: float = INF
	for track: BuiltTrack in tracks:
		var m: Dictionary = Medals.medal_times(track, "racer")
		if m.is_empty() or not (m.get("run") is Dictionary):
			continue
		var key: float = (0.0 if float(m.run.wallSteps) > 0.0 else 1e6) + float(m.author)
		if key < best_key:
			best_key = key
			best = track
	if best == null:
		t.check(false, "medal author runs: data/medals.json has no runs")
		return
	var res: PackedStringArray = []
	var all_same: bool = true
	var racer_run: Dictionary = {}
	for c: String in ids:
		var m: Dictionary = Medals.medal_times(best, c)
		var r: Dictionary = Autopilot.drive_race(best, float(m.run.aLat), float(m.run.lookK), c)
		var same: bool = r.finished and r.steps == int(m.run.steps) and JsMath.roundi(r.time * 1000.0) == JsMath.roundi(float(m.author) * 1000.0)
		all_same = all_same and same
		if c == "racer":
			racer_run = r
		res.append("%s %s (aLat %s, lookK %s, %d steps%s)" % [c, RaceState.format_time(r.time), JsMath.num_to_js(float(m.run.aLat)), JsMath.num_to_js(float(m.run.lookK)), r.steps,
			"" if same else "; medals.json: %s, %d steps" % [RaceState.format_time(float(m.author)), int(m.run.steps)]])
	var mr: Dictionary = Medals.medal_times(best, "racer")
	var rules: bool = Medals.medal_for(mr, racer_run.time) == "author" and Medals.medal_for(mr, float(mr.author) + 0.001) == "gold" and \
		Medals.medal_for(mr, float(mr.bronze) + 0.001) == "" and Medals.medal_for(mr, INF) == "" and Medals.next_medal(mr, INF).get("medal") == "bronze" and \
		Medals.next_medal(mr, float(mr.gold)).get("medal") == "author" and Medals.next_medal(mr, racer_run.time).is_empty()
	t.check(all_same and rules, "medal author runs: on %s the sweep's autopilot (nitro on the straights, the score's refills) drives %s, as in medals.json; medals are awarded to the millisecond" % [
		best.name, ", ".join(res)])


# ---- the save file (sim/save.gd) ---------------------------------------------------------------

func _save() -> void:
	t.section("save file (user://, sim/save.gd)")
	var p: String = "user://test_sim_save.json"
	var write := func(text: String) -> void:
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_string(text)
		f.close()
	for f: String in [p, p + ".bad", p + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var pv: int = Car.PHYSICS_VERSION
	var sr: int = ScoreState.SCORE_RULES

	# no file: defaults
	SaveData.use_file(p)
	var ok: bool = SaveData.get_record("rookie-oval").is_empty() and SaveData.get_setting("ghost") == true and SaveData.get_setting("car") == "racer" and \
		SaveData.get_setting("quality") == "auto" and SaveData.load_ghost("rookie-oval") == null and SaveData.get_best_score("rookie-oval", "racer").is_empty() and \
		SaveData.load_network() == null
	t.check(ok, "no save file: no records, ghosts, scores or network; default settings (ghost on, racer, quality auto)")

	# records: per track and car; slower, unknown cars and bad times not saved; kept in the file
	ok = SaveData.submit_record("rookie-oval", "racer", 125.5, [40.0, 80.0, 125.5]) and not SaveData.submit_record("rookie-oval", "racer", 126.0, []) and \
		SaveData.submit_record("rookie-oval", "kestrel", 130.0, [45.0, 90.0, 130.0]) and not SaveData.submit_record("ramp-rally", "bus", 100.0, []) and \
		not SaveData.submit_record("ramp-rally", "racer", NAN, []) and not SaveData.submit_record("ramp-rally", "racer", -1.0, []) and \
		SaveData.submit_record("ramp-rally", "racer", 170.123456789012, [60.0, 120.0, 170.123456789012])
	SaveData.use_file(p) # read back from the file
	var r: Dictionary = SaveData.get_record("rookie-oval")
	ok = ok and r.get("time") == 125.5 and str(r.get("splits")) == str([40.0, 80.0, 125.5]) and SaveData.get_record("rookie-oval", "kestrel").get("time") == 130.0 and \
		SaveData.get_record("rookie-oval", "thunder").is_empty() and absf(float(SaveData.get_record("ramp-rally").get("time", 0.0)) - 170.123456789012) < 1e-12 and \
		SaveData.submit_record("rookie-oval", "racer", 124.0, []) and SaveData.get_record("rookie-oval").time == 124.0 and SaveData.get_record("rookie-oval", "kestrel").time == 130.0
	t.check(ok, "best times per track and car: a faster time replaces the record, slower ones, unknown cars and bad times are not saved; read back from the file (17 digits)")

	# junk in the file: read as none, never a script error; the next save replaces it
	var rec := func(e: Variant) -> String: return JSON.stringify({version = 1, records = {"rookie-oval": {racer = e}}})
	var junk: Array[String] = ["", "null", "[]", "7", "\"x\"", "{oops", "{\"records\": 5}", "{\"records\": []}", "{\"records\": {\"rookie-oval\": 5}}",
		"{\"records\": {\"rookie-oval\": []}}", "{\"records\": {\"rookie-oval\": {\"racer\": 3}}}", "{\"records\": {\"rookie-oval\": {\"racer\": []}}}",
		rec.call({time = "x", physics = pv}), rec.call({time = -1, physics = pv}), rec.call({time = 0, physics = pv}), rec.call({time = 60}),
		rec.call({time = 60, physics = pv - 1}), rec.call({time = 60, physics = str(pv)}), rec.call({time = 60, physics = [pv]}), "{\"records\": {\"rookie-oval\": {\"racer\": {\"time\": 1e999, \"physics\": %d}}}}" % pv]
	var junk_ok: int = 0
	for j: String in junk:
		write.call(j)
		SaveData.use_file(p)
		if SaveData.get_record("rookie-oval").is_empty() and SaveData.get_record("rookie-oval", "kestrel").is_empty() and \
				SaveData.submit_record("rookie-oval", "kestrel", 99.0, []) and SaveData.get_record("rookie-oval", "kestrel").time == 99.0:
			junk_ok += 1
	write.call(rec.call({time = 60, physics = pv, splits = ["x", 20, null]}))
	SaveData.use_file(p)
	var splits_ok: bool = str(SaveData.get_record("rookie-oval").get("splits")) == str([null, 20.0, null])
	write.call("{oops")
	SaveData.use_file(p)
	SaveData.get_record("rookie-oval")
	var kept_bad: bool = FileAccess.file_exists(p + ".bad") and FileAccess.get_file_as_string(p + ".bad") == "{oops"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p + ".bad"))
	t.check(junk_ok == junk.size() and splits_ok and kept_bad, "a broken save file: %d of %d kinds of junk read as no record and are replaced by the next save; broken splits read as none; an unreadable file is kept as .bad" % [junk_ok, junk.size()])

	# settings: remembered; a stored value of the wrong type reads as the default
	write.call("{\"settings\": {\"ghost\": \"x\", \"car\": 5, \"quality\": null, \"volume\": 0.5}}")
	SaveData.use_file(p)
	ok = SaveData.get_setting("ghost") == true and SaveData.get_setting("car") == "racer" and SaveData.get_setting("quality") == "auto" and \
		SaveData.get_setting("volume") == 0.5 and SaveData.get_setting("nope", 3) == 3
	SaveData.set_setting("ghost", false)
	SaveData.set_setting("car", "thunder")
	SaveData.set_setting("weird", INF) # (JSON has no inf: it must not make the file unreadable)
	SaveData.submit_record("hairpin-valley", "racer", 200.0, PackedFloat64Array([60.0, 130.0, 200.0])) # race.splits as they are
	SaveData.use_file(p)
	ok = ok and SaveData.get_setting("ghost") == false and SaveData.get_setting("car") == "thunder" and SaveData.get_setting("weird") == null and \
		str(SaveData.get_record("hairpin-valley").get("splits")) == str([60.0, 130.0, 200.0]) and not FileAccess.file_exists(p + ".bad")
	t.check(ok, "settings: remembered in the file; junk values read as the defaults; an infinite value or a race's packed splits don't break the file")

	# best scores: per track and car; junk, negative, infinite and other-rules / other-physics entries ignored
	var entry := func(e: Variant) -> String: return JSON.stringify({scores = {"rookie-oval": {racer = e}}})
	var sjunk: Array[String] = ["null", "[]", "7", "\"x\"", "{oops", "{\"scores\": {\"rookie-oval\": 5}}", "{\"scores\": {\"rookie-oval\": []}}",
		"{\"scores\": {\"rookie-oval\": {\"racer\": 3}}}", entry.call({score = "x", rules = sr, physics = pv}), entry.call({score = -5, rules = sr, physics = pv}),
		"{\"scores\": {\"rookie-oval\": {\"racer\": {\"score\": 1e999, \"rules\": %d, \"physics\": %d}}}}" % [sr, pv], entry.call({score = 500, physics = pv}),
		entry.call({score = 500, rules = sr + 1, physics = pv}), entry.call({score = 500, rules = sr, physics = pv - 1}), entry.call({score = 500, rules = str(sr), physics = pv})]
	var s_ok: int = 0
	for j: String in sjunk:
		write.call(j)
		SaveData.use_file(p)
		if SaveData.get_best_score("rookie-oval", "racer").is_empty() and SaveData.submit_score("rookie-oval", "racer", 1200.0) and \
				SaveData.get_best_score("rookie-oval", "racer").score == 1200.0:
			s_ok += 1
	write.call("{}")
	SaveData.use_file(p)
	ok = SaveData.submit_score("rookie-oval", "racer", 5000.0) and not SaveData.submit_score("rookie-oval", "racer", 4000.0) and \
		SaveData.submit_score("rookie-oval", "kestrel", 3000.0) and not SaveData.submit_score("rookie-oval", "thunder", 0.0) and \
		not SaveData.submit_score("rookie-oval", "thunder", INF)
	SaveData.use_file(p)
	ok = ok and SaveData.get_best_score("rookie-oval", "racer").score == 5000.0 and SaveData.get_best_score("rookie-oval", "kestrel").score == 3000.0 and \
		SaveData.get_best_score("rookie-oval", "thunder").is_empty() and SaveData.get_best_score("hairpin-valley", "racer").is_empty()
	t.check(ok and s_ok == sjunk.size(), "best scores: stored per track and car; %d of %d kinds of junk, negative, infinite and other-rules / other-physics entries ignored" % [s_ok, sjunk.size()])

	# ghosts and the network round-trip through the file
	var t0: BuiltTrack = tracks[0]
	var rec0 := Replay.GhostRecorder.new()
	var car0 := Car.new(t0)
	for s in 121:
		if s:
			car0.step(t0, ctrl(0.0, 1.0), DT)
		rec0.add(s, car0, s == 120)
	var ghost: Dictionary = Replay.pack_ghost(rec0, {track = t0, laps = 3, time = 2.0, car = "kestrel"})
	ok = SaveData.save_ghost("rookie-oval", "kestrel", ghost) and SaveData.save_network({version = 2, layers = [1, 2, 3]})
	SaveData.use_file(p)
	var back: Dictionary = Replay.unpack_ghost(SaveData.load_ghost("rookie-oval", "kestrel"), t0, 3, "kestrel")
	ok = ok and back.get("end") == 120 and SaveData.load_ghost("rookie-oval", "racer") == null and Replay.unpack_ghost(SaveData.load_ghost("rookie-oval", "racer"), t0, 3).is_empty() and \
		(SaveData.load_network() as Dictionary).get("layers") == [1.0, 2.0, 3.0]
	var on_disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	ok = ok and on_disk is Dictionary and JsMath.same(on_disk.get("version"), SaveData.VERSION) and not FileAccess.file_exists(p + ".tmp")
	t.check(ok, "ghosts (one per track and car) and the AI network round-trip through the file; writes leave no .tmp behind")

	# AI networks per car (version 2): one per car; a version 1 file's single network was the Racer's
	var net := func(gen: int) -> Dictionary: return {format = "trackmania-lite-network", generation = gen, network = {layers = [1, 2, 3]}}
	write.call(JSON.stringify({version = 1, records = {"rookie-oval": {racer = {time = 60.0, splits = [], physics = pv}}}, network = net.call(7)}))
	SaveData.use_file(p)
	var racer_net: Variant = SaveData.load_network("racer")
	ok = racer_net is Dictionary and int((racer_net as Dictionary).get("generation")) == 7 and SaveData.load_network() == racer_net and \
		SaveData.load_network("kestrel") == null and SaveData.network_cars() == PackedStringArray(["racer"]) and SaveData.get_record("rookie-oval").get("time") == 60.0
	ok = ok and SaveData.save_network(net.call(3), "kestrel") and SaveData.save_network(net.call(9), "vortex") and not SaveData.save_network(net.call(1), "bus")
	SaveData.use_file(p)
	on_disk = JSON.parse_string(FileAccess.get_file_as_string(p))
	ok = ok and int(SaveData.load_network("racer").generation) == 7 and int(SaveData.load_network("kestrel").generation) == 3 and \
		int(SaveData.load_network("vortex").generation) == 9 and SaveData.load_network("thunder") == null and SaveData.load_network("bus") == null and \
		SaveData.network_cars() == PackedStringArray(["racer", "kestrel", "vortex"]) and on_disk is Dictionary and not (on_disk as Dictionary).has("network") and \
		JsMath.same(on_disk.get("version"), SaveData.VERSION) and int(on_disk.networks.racer.best.generation) == 7 and int(on_disk.networks.kestrel.best.generation) == 3
	t.check(ok, "AI networks per car: a version 1 file's network becomes the Racer's (networks.racer.best); each car keeps its own, read back from the file; an unknown car is refused")
	# a file with both (a version 1 game wrote the old key into a version 2 file): the newer per-car one stays
	write.call(JSON.stringify({version = 1, network = net.call(1), networks = {racer = {best = net.call(5)}}}))
	SaveData.use_file(p)
	ok = int(SaveData.load_network("racer").generation) == 5
	var njunk: Array[String] = ["{\"networks\": 5}", "{\"networks\": []}", "{\"networks\": {\"racer\": 5}}", "{\"networks\": {\"racer\": {\"best\": \"x\"}}}",
		"{\"network\": 5}", "{\"network\": [1]}", "{\"network\": null, \"networks\": {\"racer\": []}}"]
	var n_ok: int = 0
	for j: String in njunk:
		write.call(j)
		SaveData.use_file(p)
		if SaveData.load_network("racer") == null and SaveData.network_cars().is_empty() and SaveData.save_network(net.call(2), "racer") and \
				int(SaveData.load_network().generation) == 2:
			n_ok += 1
	t.check(ok and n_ok == njunk.size(), "AI networks: a newer per-car network is not replaced by an old single one; %d of %d kinds of junk read as no network and are replaced by the next save" % [n_ok, njunk.size()])

	# track versions (v6.3): what was made on an older version of a track (v6.2's Ramp Rally, all
	# asphalt) moves to the archive and is never compared with new runs; unchanged tracks keep theirs
	var rr_old: String = Tracks.legacy_signature("ramp-rally")
	var old_ghost: Dictionary = ghost.duplicate(true)
	old_ghost.track = "ramp-rally"
	old_ghost.sig = rr_old
	write.call(JSON.stringify({version = 2,
		records = {"rookie-oval": {racer = {time = 120.0, splits = [], physics = pv}}, "ramp-rally": {racer = {time = 170.0, splits = [], physics = pv}, dune = {time = 180.0, splits = [], physics = pv}}},
		scores = {"ramp-rally": {racer = {score = 9000, rules = sr, physics = pv}}, "rookie-oval": {racer = {score = 800, rules = sr, physics = pv}}},
		ghosts = {"ramp-rally": {racer = old_ghost}}}))
	SaveData.use_file(p)
	var arch_rec: Dictionary = SaveData.get_archived("records", "ramp-rally", "racer")
	ok = Tracks.signature("ramp-rally") != rr_old and Tracks.signature("rookie-oval") == Tracks.legacy_signature("rookie-oval") and \
		SaveData.get_record("rookie-oval").get("time") == 120.0 and SaveData.get_best_score("rookie-oval", "racer").get("score") == 800.0 and \
		SaveData.get_record("ramp-rally").is_empty() and SaveData.get_record("ramp-rally", "dune").is_empty() and \
		SaveData.get_best_score("ramp-rally", "racer").is_empty() and SaveData.load_ghost("ramp-rally", "racer") == null and \
		arch_rec.keys() == [rr_old] and float(arch_rec[rr_old].time) == 170.0 and \
		float(SaveData.get_archived("records", "ramp-rally", "dune")[rr_old].time) == 180.0 and \
		float(SaveData.get_archived("scores", "ramp-rally", "racer")[rr_old].score) == 9000.0 and \
		SaveData.get_archived("ghosts", "ramp-rally", "racer")[rr_old].sig == rr_old and SaveData.get_archived("records", "rookie-oval", "racer").is_empty()
	# a slower time and a lower score than the old version's are new bests on the new version
	ok = ok and SaveData.submit_record("ramp-rally", "racer", 190.0, []) and SaveData.submit_score("ramp-rally", "racer", 5000.0) and \
		SaveData.get_record("ramp-rally").time == 190.0 and SaveData.get_best_score("ramp-rally", "racer").score == 5000.0
	SaveData.use_file(p)
	on_disk = JSON.parse_string(FileAccess.get_file_as_string(p))
	ok = ok and on_disk is Dictionary and JsMath.same(on_disk.get("version"), SaveData.VERSION) and on_disk.records["ramp-rally"].racer.sig == Tracks.signature("ramp-rally") and \
		float(on_disk.archive.records["ramp-rally"].racer[rr_old].time) == 170.0 and SaveData.get_record("ramp-rally").time == 190.0 and \
		float(SaveData.get_archived("records", "ramp-rally", "racer")[rr_old].time) == 170.0
	t.check(ok, "track versions: a version 2 save's records, scores and ghosts on a changed track (Ramp Rally, now with dirt) move to the archive (kept, by old signature); slower runs on the new version are new bests; unchanged tracks keep theirs")
	# a version 3 entry on a version of a track that is gone (another signature) is archived too; unknown tracks are left alone
	write.call(JSON.stringify({version = 3, records = {"rookie-oval": {racer = {time = 100.0, splits = [], physics = pv, sig = "1:2"}},
		"no-such-track": {racer = {time = 50.0, splits = [], physics = pv, sig = "1:2"}}}}))
	SaveData.use_file(p)
	ok = SaveData.get_record("rookie-oval").is_empty() and float(SaveData.get_archived("records", "rookie-oval", "racer")["1:2"].time) == 100.0 and \
		SaveData.get_record("no-such-track").get("time") == 50.0
	t.check(ok, "an entry made on a version of a track that no longer exists is archived; entries of unknown tracks stay as they are")

	# a save file that can't be written: nothing fails, the session keeps what was saved
	SaveData.use_file("user://no_such_folder/save.json")
	ok = SaveData.submit_record("rookie-oval", "racer", 50.0, []) and SaveData.get_record("rookie-oval").time == 50.0 and \
		not SaveData.save_ghost("rookie-oval", "racer", ghost) and SaveData.submit_score("rookie-oval", "racer", 100.0) and \
		not SaveData.set_setting("ghost", false) and SaveData.get_setting("ghost") == false
	t.check(ok, "a save file that can't be written: records, scores and settings still count for the session, nothing fails")

	SaveData.use_file(SaveData.DEFAULT_PATH)
	for f: String in [p, p + ".bad", p + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


# ---- money and points (v6.5.0: sim/economy.gd, the career in sim/save.gd) ------------------

func _career() -> void:
	t.section("money and points: the reward table, payouts, the shop, the save file's career (v6.5.0)")
	var ids: PackedStringArray = Tracks.ids()
	# the reward table: every medal and every AI level has a reward; harder ones pay more money and
	# more points; every track pays more than the one before it
	var medals: Array = []
	medals.append_array(Economy.MEDALS_UP)
	var keys: Array = medals.duplicate()
	for l: String in Opponents.ids():
		keys.append(Economy.AI_PREFIX + l)
	var ok: bool = Economy.REWARDS.size() == keys.size()
	for k: String in keys:
		ok = ok and Economy.REWARDS.has(k)
	for group: Array in [medals, keys.slice(medals.size())]:
		for k in range(1, group.size()):
			var a: Dictionary = Economy.reward(ids[0], group[k - 1])
			var b: Dictionary = Economy.reward(ids[0], group[k])
			ok = ok and int(b.money) > int(a.money) and int(b.points) > int(a.points)
	var later: bool = true
	for k: String in keys:
		for i in range(1, ids.size()):
			var a: Dictionary = Economy.reward(ids[i - 1], k)
			var b: Dictionary = Economy.reward(ids[i], k)
			later = later and int(b.money) > int(a.money) and int(b.points) >= int(a.points) and int(b.money) % 10 == 0
	var last: String = ids[ids.size() - 1]
	t.check(ok and later and Medals.ORDER.size() == Economy.MEDALS_UP.size() and Economy.reward(ids[0], "gold") == {money = 800, points = 40} and
		Economy.reward(last, "gold") == {money = 1920, points = 96} and Economy.reward(ids[0], "ai-elite") == {money = 1600, points = 80} and
		Economy.reward(ids[0], "nope").is_empty(),
		"reward table: %d rewards (4 medals, %d AI levels), each harder one pays more money and points, every track more than the one before (gold: $800 / 40 pts on track 1, $1,920 / 96 pts on track %d)" % [
		keys.size(), Opponents.ids().size(), ids.size()])
	# payouts: a medal pays the medals below it, an AI level the levels below it; paid ones are skipped
	var p: Dictionary = Economy.payout("rookie-oval", "gold", "pro", PackedStringArray())
	var got: Array = p.items.map(func(it: Dictionary) -> String: return String(it.id))
	var sum: int = 0
	for it: Dictionary in p.items:
		sum += int(it.money)
	ok = got == ["bronze", "silver", "gold", "ai-rookie", "ai-amateur", "ai-pro"] and int(p.money) == sum and sum == 300 + 500 + 800 + 200 + 400 + 700 and \
		int(p.points) == 10 + 20 + 40 + 5 + 10 + 20 and p.repeat.is_empty() and p.items[2].label == "Gold medal" and p.items[5].label == "Beat the Pro AI" and \
		p.items[0].kind == "medal" and p.items[3].kind == "ai"
	var p2: Dictionary = Economy.payout("rookie-oval", "gold", "pro", PackedStringArray(["bronze", "silver", "ai-rookie"]))
	ok = ok and p2.items.map(func(it: Dictionary) -> String: return String(it.id)) == ["gold", "ai-amateur", "ai-pro"] and \
		Array(p2.repeat) == ["bronze", "silver", "ai-rookie"] and int(p2.money) == 800 + 400 + 700
	var p3: Dictionary = Economy.payout("rookie-oval", "", "", PackedStringArray())
	ok = ok and p3.items.is_empty() and int(p3.money) == 0 and int(p3.points) == 0
	t.check(ok, "payout: gold + beating the Pro pays bronze, silver, gold, Rookie, Amateur, Pro ($2,900, 105 pts on track 1); what was paid before is skipped and listed; no medal and no win pays nothing")

	# the save file's career: a new player has $0, 0 points and only the Racer
	var path: String = "user://test_career_save.json"
	var write := func(text: String) -> void:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(text)
		f.close()
	var clean := func() -> void:
		for f: String in [path, path + ".bad", path + ".tmp"]:
			if FileAccess.file_exists(f):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	clean.call()
	SaveData.use_file(path)
	t.check(SaveData.get_money() == 0 and SaveData.get_points() == 0 and SaveData.owned_cars() == PackedStringArray(["racer"]) and
		SaveData.owns_car("racer") and not SaveData.owns_car("vortex") and SaveData.take_welcome().is_empty() and
		Economy.price("racer") == 0 and Economy.price("kestrel") > 0, "a new career: $0, 0 points, only the Racer (the cars that cost nothing); no welcome note")

	# paid once per track, car and reward
	var c1: Dictionary = Economy.claim("rookie-oval", "racer", "silver", "")
	var c2: Dictionary = Economy.claim("rookie-oval", "racer", "silver", "")
	var c3: Dictionary = Economy.claim("rookie-oval", "racer", "author", "rookie")
	var c4: Dictionary = Economy.claim("rookie-oval", "kestrel", "bronze", "")
	var c5: Dictionary = Economy.claim("hairpin-valley", "racer", "bronze", "")
	var c6: Dictionary = Economy.claim("rookie-oval", "racer", "gold", "amateur")
	var m_after: int = 800 + 2000 + 200 + 300 + 330 + 400
	ok = int(c1.money) == 800 and int(c2.money) == 0 and Array(c2.repeat) == ["bronze", "silver"] and int(c3.money) == 800 + 1200 + 200 and \
		int(c4.money) == 300 and int(c5.money) == 330 and int(c6.money) == 400 and Array(c6.repeat) == ["bronze", "silver", "gold", "ai-rookie"] and \
		int(c6.money_total) == m_after and SaveData.get_money() == m_after
	SaveData.use_file(path) # read back from the file
	var paid: PackedStringArray = SaveData.paid_rewards("rookie-oval", "racer")
	ok = ok and SaveData.get_money() == m_after and SaveData.get_points() == int(c1.points) + int(c3.points) + int(c4.points) + int(c5.points) + int(c6.points) and \
		paid == PackedStringArray(["bronze", "silver", "gold", "author", "ai-rookie", "ai-amateur"]) and \
		SaveData.paid_rewards("rookie-oval", "kestrel") == PackedStringArray(["bronze"]) and int(Economy.claim("rookie-oval", "racer", "author", "amateur").money) == 0
	t.check(ok, "paid once: silver pays $800, the same again $0; author + Rookie then pay only what is new ($2,200); another car (Kestrel) and another track pay on their own; read back from the file, the paid rewards stay paid")

	# the shop
	write.call(JSON.stringify({version = 4, career = {money = 9000, points = 3, cars = ["racer"], paid = {}}}))
	SaveData.use_file(path)
	var b1: Dictionary = Economy.buy("kestrel")
	var m1: int = SaveData.get_money()
	SaveData.add_money(1000)
	var b2: Dictionary = Economy.buy("kestrel")
	var b3: Dictionary = Economy.buy("kestrel")
	var b4: Dictionary = Economy.buy("racer")
	var b5: Dictionary = Economy.buy("bus")
	SaveData.use_file(path)
	ok = not b1.ok and b1.error == "money" and int(b1.short) == 1000 and m1 == 9000 and not SaveData.owns_car("thunder") and \
		b2.ok and b2.error == "" and int(b2.price) == 10000 and not b3.ok and b3.error == "owned" and not b4.ok and b4.error == "owned" and \
		not b5.ok and b5.error == "unknown" and SaveData.get_money() == 0 and SaveData.owned_cars() == PackedStringArray(["racer", "kestrel"]) and SaveData.get_points() == 3
	ok = ok and SaveData.give_car("vortex") and not SaveData.give_car("vortex") and not SaveData.give_car("bus") and \
		SaveData.owned_cars() == PackedStringArray(["racer", "kestrel", "vortex"]) and SaveData.add_money(-50) == 0 and SaveData.add_points(-10) == 0 and \
		SaveData.add_money(5000) == 5000 and SaveData.add_points(25) == 25
	t.check(ok, "the shop: $9,000 can't buy the $10,000 Kestrel ($1,000 short, nothing taken); with $10,000 it can (money $0, owned, in the file); an owned car and an unknown one can't be bought; give_car owns one without paying (in picker order); money and points never go below 0")

	# version 3 (and older) saves: a career starts, paid once for the medals the best times hold
	var pv: int = Car.PHYSICS_VERSION
	var ro: BuiltTrack = Tracks.build("rookie-oval")
	var hv: BuiltTrack = Tracks.build("hairpin-valley")
	var mro: Dictionary = Medals.medal_times(ro, "racer")
	var mrk: Dictionary = Medals.medal_times(ro, "kestrel")
	var mhv: Dictionary = Medals.medal_times(hv, "racer")
	var rec := func(time: float, sig: String, physics: int = pv) -> Dictionary: return {time = time, splits = [], physics = physics, sig = sig, date = "x"}
	var v3: Dictionary = {version = 3, settings = {car = "vortex"}, records = {
		"rookie-oval": {racer = rec.call(float(mro.gold) - 0.5, ro.signature()), kestrel = rec.call(float(mrk.bronze), ro.signature()),
			bus = rec.call(100.0, ro.signature())},
		"hairpin-valley": {racer = rec.call(float(mhv.bronze) + 5.0, hv.signature()), dune = rec.call(float(mhv.author), "1:2"),
			vortex = rec.call(10.0, hv.signature(), pv - 1)},
		"no-such-track": {racer = rec.call(1.0, "1:2")}}}
	write.call(JSON.stringify(v3))
	SaveData.use_file(path)
	var want: int = 300 + 500 + 800 + 300 # racer gold (bronze, silver, gold) and kestrel bronze on Rookie Oval
	var want_pts: int = 10 + 20 + 40 + 10
	var w: Dictionary = SaveData.take_welcome()
	ok = SaveData.get_money() == want and SaveData.get_points() == want_pts and SaveData.owned_cars() == PackedStringArray(["racer"]) and \
		SaveData.paid_rewards("rookie-oval", "racer") == PackedStringArray(["bronze", "silver", "gold"]) and \
		SaveData.paid_rewards("rookie-oval", "kestrel") == PackedStringArray(["bronze"]) and SaveData.paid_rewards("hairpin-valley", "racer").is_empty() and \
		SaveData.paid_rewards("hairpin-valley", "dune").is_empty() and SaveData.paid_rewards("hairpin-valley", "vortex").is_empty() and \
		w == {money = want, points = want_pts, medals = 4} and SaveData.take_welcome().is_empty() and SaveData.get_setting("car") == "vortex"
	# the upgrade is paid once: the file is version 4 now (a later load pays nothing more); a medal held is not paid again by a race
	SaveData.add_points(0) # (writes the file)
	SaveData.use_file(path)
	var on_disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	ok = ok and SaveData.get_money() == want and SaveData.take_welcome().is_empty() and on_disk is Dictionary and JsMath.same(on_disk.get("version"), 4) and \
		int(Economy.claim("rookie-oval", "racer", "gold", "").money) == 0 and int(Economy.claim("rookie-oval", "racer", "author", "").money) == 1200
	t.check(ok, "a version 3 save: paid once for its 4 medals ($%s, %d pts: the Racer's gold and the Kestrel's bronze on Rookie Oval; not a time without a medal, one on an older version of a track, under other physics, an unknown car or track); only the Racer owned (the picked Vortex stays picked, locked); a one-time welcome note; loaded again, nothing is paid twice" % [
		UiFormat.points(want), want_pts])
	# version 2 (records without track signatures, v6.2) and version 1 saves are upgraded the same way
	write.call(JSON.stringify({version = 2, records = {"rookie-oval": {racer = {time = float(mro.bronze), splits = [], physics = pv}},
		"ramp-rally": {racer = {time = 1.0, splits = [], physics = pv}}}}))
	SaveData.use_file(path)
	ok = SaveData.get_money() == 300 and SaveData.paid_rewards("rookie-oval", "racer") == PackedStringArray(["bronze"]) and \
		SaveData.paid_rewards("ramp-rally", "racer").is_empty() and SaveData.get_record("ramp-rally").is_empty()
	write.call(JSON.stringify({version = 1, records = {"rookie-oval": {racer = {time = float(mro.author), splits = [], physics = pv}}}, network = {network = {layers = [1]}}}))
	SaveData.use_file(path)
	ok = ok and SaveData.get_money() == 300 + 500 + 800 + 1200 and SaveData.get_points() == 150 and SaveData.load_network("racer") is Dictionary and \
		int(SaveData.take_welcome().get("medals", 0)) == 4
	t.check(ok, "version 2 and 1 saves: upgraded the same way (a version 2 record on v6.2's Ramp Rally is archived, so not paid; a version 1 author time pays all four medals, $2,800)")
	# junk in the career section is repaired, never a script error
	var cjunk: Array[String] = ["{\"career\": 5}", "{\"career\": []}", "{\"career\": {\"money\": \"x\", \"points\": -4, \"cars\": 3, \"paid\": []}}",
		"{\"version\": 4, \"career\": {\"money\": 1e999, \"cars\": [\"bus\", 7], \"paid\": {\"rookie-oval\": 3, \"x\": {\"racer\": [1, \"gold\", \"gold\"]}}}}"]
	var j_ok: int = 0
	for j: String in cjunk:
		write.call(j)
		SaveData.use_file(path)
		if SaveData.get_money() == 0 and SaveData.get_points() == 0 and SaveData.owned_cars() == PackedStringArray(["racer"]) and \
				SaveData.paid_rewards("rookie-oval", "racer").is_empty() and int(Economy.claim("rookie-oval", "racer", "bronze", "").money) == 300:
			j_ok += 1
	write.call("{\"version\": 4, \"career\": {\"money\": 70, \"points\": 2.6, \"cars\": [\"vortex\", \"racer\", \"vortex\"], \"paid\": {\"x\": {\"racer\": [1, \"gold\", \"gold\"]}}}}")
	SaveData.use_file(path)
	ok = SaveData.get_money() == 70 and SaveData.get_points() == 2 and SaveData.owned_cars() == PackedStringArray(["racer", "vortex"]) and \
		SaveData.paid_rewards("x", "racer") == PackedStringArray(["gold"])
	t.check(ok and j_ok == cjunk.size(), "a damaged career section: %d of %d kinds of junk read as a new career; a hand-edited one is cleaned (whole numbers, known cars once each, the Racer always)" % [j_ok, cjunk.size()])
	SaveData.use_file(SaveData.DEFAULT_PATH)
	clean.call()

	# the prices: a player who drives well (gold medals, which also beat the Expert AI at 1.13 x the
	# author time) can buy a second car after three tracks and all five by the end of the career
	var prices: Array = []
	var total: int = 0
	for id: String in Cars.ids():
		if Economy.price(id) > 0:
			prices.append(Economy.price(id))
			total += Economy.price(id)
	prices.sort()
	var good: PackedInt32Array = Economy.career({medal = "gold", ai = "expert"})
	var fair: PackedInt32Array = Economy.career({medal = "silver", ai = "pro"})
	var n: int = good.size()
	ok = prices.size() == Cars.ids().size() - 1 and good[1] < prices[0] and good[2] >= prices[0] and good[n - 2] < total and good[n - 1] >= total and \
		fair[3] < prices[0] and fair[4] >= prices[0]
	t.check(ok, "prices (%s, all five $%s): gold + Expert on each track earns $%s after 2 tracks, $%s after 3 (the second car), $%s after %d and $%s after %d (all five); silver + Pro: the second car after 5 tracks ($%s), $%s in all" % [
		", ".join(PackedStringArray(prices.map(func(v: int) -> String: return UiFormat.money(v)))), UiFormat.points(total), UiFormat.points(good[1]),
		UiFormat.points(good[2]), UiFormat.points(good[n - 2]), n - 1, UiFormat.points(good[n - 1]), n, UiFormat.points(fair[4]), UiFormat.points(fair[n - 1])])
