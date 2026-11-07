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
## Every track's signature (Tracks.signature: layout, then the road surfaces). Records, ghosts,
## medals and AI best times are keyed to them, so one changes only when its track is reworked on
## purpose (v6.6.0: Hairpin Valley, Technical Trial, Grand Marathon, Mountain Pass, Canyon Run;
## V65_SIGS has what they were); the three of v6.4 (tools/gen_tracks.gd) follow them in the menu.
const SIGS: Dictionary = {
	"rookie-oval": "1083:2167", "hairpin-valley": "1218:2435|snow492-815", "ramp-rally": "1187:2374|dirt168-730",
	"banked-speedway": "1422:2844", "technical-trial": "1350:2699", "grand-marathon": "3746:7491",
	"coastal-gp": "1448:2895", "mountain-pass": "2463:4925|dirt138-400,snow920-1384", "canyon-run": "1448:2896|dirt487-694",
	"night-highway": "1558:3117", "lighthouse-bay": "1175:2351", "seaside-stunts": "1654:3306",
	"forest-rally": "1272:2544|dirt126-1242", "northern-lights": "1413:2826|snow169-897,snow995-1383",
	"summit-rush": "2335:4668|dirt485-935,snow936-1429,dirt1868-2109",
}
## The tracks v6.6.0 left alone: SHA-256 of their tools/gen_tracks.gd text (tracks_json([def])) and
## of their medal entry in data/medals.json (JSON.stringify, keys sorted) as v6.5 had them.
const V65_KEPT: Dictionary = {
	"rookie-oval": ["f50c587c9beccbbdbcec69238f3333d2db9e803d5fa5e737fc140083ef7b335d", "02233715e6e016b331e9e2b044c7f714c98ea1507396ab29e8887dd7932253e9"],
	"ramp-rally": ["7eae2d8a2966df2b1d1d5e528ea9fbe5cb55f39340404901c9c6f8e52b89a51c", "cecaea67f480cceec76ec059accfb4237c9e89668999f6a257376b2edb1fcfa2"],
	"banked-speedway": ["9516d8e05c1639d2b09b3a5f8a0eac3f69b9dec44971cb074341cc0bf7f0d128", "7610199e2724874ae050a8208f581d4d7344a448e52ee86cdcfc8e65752b6b93"],
	"coastal-gp": ["968b9d669766b98db6c2a7232daeb374fe8bda931867da33db153cde283c6dbf", "41df70c034910a0b6bca7630b1116a95579caa778064439761362fe34533c859"],
	"night-highway": ["0ea91b0a75ffc734c12e370424ab4c5feded1f677e00c4c5ad21ec49e8fd0356", "0efc46cf4755315090d1985a6b5035593d43c911a38d72b6b8ec99cf0d9b5844"],
	"lighthouse-bay": ["f8b6f5bc5c7f77f044b6e68b01c098920926f96134c9832df29da34f4d39a1a5", "9e2bb8d27e50f730bdf2cacae73a11b0084b4de532f6e42e3fc65463013df7a2"],
	"seaside-stunts": ["b0b4428e48f710c1568d621ede78c54de2549e664837ec0dd804a5938acf3540", "6fe1fcff2536ec0c36adb6d299a48de8a5e0fa830091339c3b010a261d597995"],
	"forest-rally": ["a128d68df84c801ff97c441784d3d9dbc507cc3c457611fd2bbef2c736b7abe5", "f4bd360541021a2e344c8b3094982255a1e22fc28f3552ec32e825854d80e45f"],
	"northern-lights": ["ff6a038e32c5b2b6706d29b5332cff97b8b53eb924cda86551571bc3282ce949", "42d401c384448d325c8b7d663ab642c42b575c40ded2414d4dd4ca041dfefa8f"],
	"summit-rush": ["7d18eb5bcd014ca0db9d1718283a01b85b4078cd4ec000224c277d01e3a64e04", "b3b37860f70af09c22c67f93d81f0c59f21928dc01b467ae0bfede270b477b15"],
}
## The tracks v6.6.0 reworked (the tightest corners more forgiving), with what their corners must
## be now, as tools/corners.gd measures them (the curvature over ±2 samples: a 22 m turn reads
## 21.8 m): [the tightest corner's radius, the tightest hairpin's radius (a turn of 150° or more
## tighter than 40 m), the narrowest road in a hairpin] in m.
const V66_REWORKED: Dictionary = {
	"hairpin-valley": [21.5, 23.5, 15.0],
	"technical-trial": [23.5, 23.5, 16.0],
	"grand-marathon": [23.5, 23.5, 17.0],
	"mountain-pass": [23.5, 23.5, 15.0],
	"canyon-run": [23.5, 23.5, 13.0],
}
## Their signatures in v6.3-6.5 (what records, scores, ghosts, medal times and AI opponents made on
## them then carry).
const V65_SIGS: Dictionary = {
	"hairpin-valley": "1209:2417|snow480-812", "technical-trial": "1296:2591", "grand-marathon": "3735:7468",
	"mountain-pass": "2393:4783|dirt139-400,snow885-1349", "canyon-run": "1426:2853|dirt487-688",
}
const Corners = preload("res://tools/corners.gd")
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

## 100-0 km/h stopping distances (m) of v6.9.0 on dirt and snow (tools/car_stats.gd --surface):
## v6.10's loose-ground brakes are measured against them.
const V69_BRAKE100: Dictionary = {
	"dirt": {"racer": 33.98, "kestrel": 31.16, "thunder": 42.96, "drifter": 34.75, "dune": 31.25, "vortex": 42.41},
	"snow": {"racer": 42.99, "kestrel": 38.45, "thunder": 55.25, "drifter": 40.54, "dune": 33.75, "vortex": 55.22},
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
	_unlocks()
	_faster_bronze()
	_upgrades()
	_field()
	_cups()
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


## Track `id` as the web game (v5) has it: all asphalt (the road surfaces of v6.3 stripped) and,
## for the tracks v6.6 reworked, the browser's layout (Tracks.build_web). The checks against the
## web game's numbers use it.
static func asphalt(id: String) -> BuiltTrack:
	return Tracks.build_web(id)


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
				track.name, (" (as in the web game: %s)" % ("all asphalt, the layout before v6.6" if V66_REWORKED.has(id) else "all asphalt")) if track != tracks[-1] else "",
				track.race_length(1) / 1000.0, "/lap" if track.closed else "", track.cp_samples.size(),
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
		if Tracks.build_asphalt(track.id) != asphalt(track.id): # (reworked in v6.6: this layout, all asphalt)
			plain = _basic_race(Tracks.build_asphalt(track.id))
		t.check(race.finished and not bad and race.finish_time > plain,
			"%s (%s): the test autopilot finishes in %s with the racer, slower than on all asphalt (%s), wall contact in %d steps" % [
				track.name, Surfaces.summary(track), RaceState.format_time(race.finish_time), RaceState.format_time(plain), wall])

	_v64_tracks(ids)
	_v66_corners()

	var rookie: BuiltTrack = tracks[0]
	var car := Car.new(rookie)
	car.yaw += PI
	var race := RaceState.new(rookie)
	for k in 60 * 15:
		car.step(rookie, ctrl(0.0, 1.0), DT)
		race.update(car, DT)
	t.check(race.next_gate == 0, "driving backwards over the line scores no checkpoints")


## The tracks' designs and versions: every track passes tools/gen_tracks.gd's rules and
## data/tracks.json is what it writes; the tracks v6.6 did not rework are bit for bit those of v6.5
## (their tracks.json text, signatures and medal times; the browser's first 12 = v6.2's layouts),
## the reworked ones are new versions (new signatures, medal times for every car); tracks 13-15
## (v6.4) follow the first 12 in the menu with rising difficulty and their own surfaces and themes.
func _v64_tracks(ids: PackedStringArray) -> void:
	t.section("the tracks: design rules and versions (v6.4, v6.6)")
	var gen: Object = load("res://tools/gen_tracks.gd").new()
	gen.call("_define")
	var defs: Array = []
	var issues: PackedStringArray = []
	var stats: PackedStringArray = []
	var texts: Dictionary = {} # id -> the track's own tracks.json text
	for d: Dictionary in gen.get("designs"):
		var e: Dictionary = gen.call("_realise", d)
		if e.is_empty():
			issues.append("%s cannot be built" % d.meta.id)
			continue
		var r: Dictionary = gen.call("_validate", e)
		defs.append(r.def)
		texts[r.def.id] = gen.call("tracks_json", [r.def])
		for msg: String in r.issues:
			issues.append("%s: %s" % [r.def.id, msg])
		if V64_TRACKS.has(r.def.id):
			var s: Dictionary = r.stats
			var jumps: int = (r.kick as Array).size()
			stats.append("%s %.2f km%s, radius >= %.0f m, %d jump%s, banking <= %.0f°, heights %.0f-%.0f m" % [
				r.def.name, float(s.race) / 1000.0, " a lap" if r.def.type == "circuit" else "", float(s.minR), jumps, "" if jumps == 1 else "s",
				float(s.maxBank), float(s.minY), float(s.maxY)])
	var text: String = gen.call("tracks_json", defs)
	gen.free()
	t.check(issues.is_empty() and defs.size() == ids.size() and text == FileAccess.get_file_as_string(Tracks.DATA_PATH),
		"all %d tracks pass the design rules of tools/gen_tracks.gd (clearance, radius, grades, jumps and landings, crests, heights, banking, checkpoints, surfaces) and data/tracks.json is up to date%s" % [
			defs.size(), "" if issues.is_empty() else ": " + "; ".join(issues)])
	var kept_bad: PackedStringArray = []
	for id: String in ids:
		var same: bool = String(texts.get(id, "")).sha256_text() == String((V65_KEPT.get(id, ["?"]) as Array)[0])
		if same != V65_KEPT.has(id) or V65_KEPT.has(id) == V66_REWORKED.has(id):
			kept_bad.append(id)
	t.check(kept_bad.is_empty() and V65_KEPT.size() + V66_REWORKED.size() == ids.size(),
		"the %d tracks v6.6 did not rework are bit for bit as in v6.5 (their tracks.json text); the %d reworked ones (%s) are not%s" % [
			V65_KEPT.size(), V66_REWORKED.size(), ", ".join(V66_REWORKED.keys()), "" if kept_bad.is_empty() else ": wrong " + ", ".join(kept_bad)])
	# signatures: the kept ones unchanged (the browser's layouts = v6.2's), the reworked ones new
	# (neither v6.5's nor v6.2's, so what was made on the old versions stops counting), v6.4's as made
	var bad_sigs: PackedStringArray = []
	for id: String in ids:
		var tr: BuiltTrack = by_id(id)
		var legacy: String = Tracks.legacy_signature(id)
		var ok: bool = Tracks.signature(id) == String(SIGS.get(id, "?")) and tr.signature() == Tracks.signature(id) and (legacy == "") == V64_TRACKS.has(id)
		if V66_REWORKED.has(id):
			ok = ok and tr.layout_signature() != legacy and tr.signature() != String(V65_SIGS[id]) and \
				Tracks.build_web(id).layout_signature() == legacy
		elif legacy != "":
			ok = ok and tr.layout_signature() == legacy and Tracks.build_web(id) == Tracks.build_asphalt(id)
		if not ok:
			bad_sigs.append("%s %s" % [id, Tracks.signature(id)])
	t.check(bad_sigs.is_empty() and SIGS.size() == ids.size(),
		"track signatures: the kept tracks' unchanged (layouts = v6.2's), the reworked ones' new (not v6.5's or v6.2's; the browser's layout still built for the parity checks), the 3 of v6.4 as made%s" % [
			"" if bad_sigs.is_empty() else ": wrong " + ", ".join(bad_sigs)])
	# medal times: the kept tracks' unchanged (data/medals.json), the reworked and v6.4 ones for every car
	var md: Dictionary = Medals.data().get("tracks", {})
	var kept_ok: bool = true
	var kept_n: int = 0
	for id: String in V65_KEPT:
		# (v6.10 changed the brakes and walls on dirt and snow: those tracks have new medal times,
		# so only the all-asphalt ones are compared)
		if by_id(id).has_surfaces():
			continue
		kept_n += 1
		# (v6.9.0 made bronze 1.3 × the author time: the hash is of v6.5's entry, whose bronze was
		# 1.5 ×, so that bronze is put back first; everything else is compared as it is)
		var entry: Dictionary = (md.get(id, {}) as Dictionary).duplicate(true)
		for c: String in (entry.get("cars", {}) as Dictionary):
			var e: Dictionary = entry.cars[c]
			e.bronze = Medals.medal_set(float(e.author), Medals.WEB_FACTORS).bronze
		kept_ok = kept_ok and JSON.stringify(entry, "", true).sha256_text() == String(V65_KEPT[id][1])
	var new_ok: bool = true
	for id: String in ids:
		for c: String in Cars.ids():
			var m: Dictionary = Medals.medal_times(by_id(id), c)
			new_ok = new_ok and not m.is_empty() and is_equal_approx(float(m.bronze), float(Medals.medal_set(float(m.author)).bronze))
	t.check(kept_ok and new_ok,
		"medal times: the %d kept all-asphalt tracks keep theirs bit for bit (author, gold, silver, the run; bronze as v6.5 had it at 1.5 ×); every track has them for all %d cars on the current version of the track (bronze = %s × the author time, rounded up, as everywhere)" % [
			kept_n, Cars.ids().size(), JsMath.num_to_js(float(Medals.data().get("factors", {}).get("bronze", 0.0)))])
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


## The reworked corners (v6.6.0): on each reworked track no corner is tighter than its new minimum,
## every hairpin is wide and round enough, the track keeps its hairpins (a hairpin is still a
## hairpin) and its dirt and snow stretches (the same surfaces in the same order, each about as
## long as before); the numbers against the browser's (v6.5) layout of the same track.
func _v66_corners() -> void:
	t.section("the reworked corners (v6.6)")
	var lines: PackedStringArray = []
	var ok: bool = true
	for id: String in V66_REWORKED:
		var want: Array = V66_REWORKED[id]
		var now: BuiltTrack = by_id(id)
		var old: BuiltTrack = Tracks.build_web(id)
		var res: Array[Dictionary] = []
		for tr: BuiltTrack in [old, now]:
			var r_min: float = INF
			var pin_r: float = INF
			var pin_w: float = INF
			var pins: int = 0
			for c: Dictionary in Corners.corners(tr, 1e9):
				r_min = minf(r_min, float(c.r))
				if absf(float(c.turn)) >= 150.0 and float(c.r) < 40.0: # (Grand Marathon's two 165° sweepers are 106-110 m)
					pins += 1
					pin_r = minf(pin_r, float(c.r))
					pin_w = minf(pin_w, float(c.min_width))
			res.append({r = r_min, pin_r = pin_r, pin_w = pin_w, pins = pins})
		var a: Dictionary = res[0]
		var b: Dictionary = res[1]
		var good: bool = b.r >= float(want[0]) and b.pin_r >= float(want[1]) and b.pin_w >= float(want[2]) and b.pins == a.pins and \
			b.r > a.r and b.pin_r > a.pin_r and b.pin_w > a.pin_w
		# the road surfaces: the same stretches in the same order, each within 5 % of its old length
		var ra: PackedStringArray = Tracks.build(id).surface_runs()
		var surf_ok: bool = true
		if String(V65_SIGS[id]).contains("|"):
			var was: PackedStringArray = String(V65_SIGS[id]).split("|")[1].split(",")
			surf_ok = ra.size() == was.size()
			for k in mini(ra.size(), was.size()):
				surf_ok = surf_ok and _run_kind(ra[k]) == _run_kind(was[k]) and absf(_run_len(ra[k]) - _run_len(was[k])) <= 0.05 * _run_len(was[k])
		else:
			surf_ok = ra.is_empty()
		ok = ok and good and surf_ok
		lines.append("%s: tightest corner %.1f -> %.1f m, hairpins (%d) %.1f -> %.1f m round and %.0f -> %.0f m wide%s%s" % [
			now.name, a.r, b.r, b.pins, a.pin_r, b.pin_r, a.pin_w, b.pin_w, "" if ra.is_empty() else ", " + " ".join(ra),
			"" if good and surf_ok else " (WRONG)"])
	t.check(ok, "the reworked tracks' corners are more forgiving and keep their hairpins and surfaces: %s" % "; ".join(lines))


static func _run_kind(run: String) -> String:
	return run.rstrip("0123456789-")


static func _run_len(run: String) -> float:
	var nums: PackedStringArray = run.trim_prefix(_run_kind(run)).split("-")
	return float(nums[1]) - float(nums[0]) + 1.0


## The test autopilot's (Autopilot.basic, the Racer) finish time on `track` (INF when it doesn't finish in 10 min).
static func _basic_race(track: BuiltTrack) -> float:
	var car := Car.new(track)
	var race := RaceState.new(track)
	var pilot := Autopilot.basic(track)
	while not race.finished and race.time < 600.0:
		car.step(track, pilot.drive(car), DT)
		race.update(car, DT)
	return race.finish_time if race.finished else INF


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
	# Valley and Mountain Pass; the start grid on asphalt; the layout (and v6.2 signature) unchanged,
	# but for the five tracks v6.6 reworked (V66_REWORKED: a new layout, see _v64_tracks).
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
		var sig_ok: bool = ((tr.layout_signature() == legacy) != V66_REWORKED.has(tr.id) or (legacy == "" and V64_TRACKS.has(tr.id))) and \
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
	t.check(ok, "surfaces on %d tracks (4 of v6.3, 3 of v6.4), the other %d all asphalt; the layouts of v6.2 but for the five reworked in v6.6; blend weights add up to 1 and change at most 1/%d a sample (about %d m from one surface to the next); the start grid on asphalt; %s" % [
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
	# (v6.10: the loose-ground brakes and the dirt's rolling drag stop the Racer about as short on
	# dirt as on asphalt; snow is still longer)
	ok = brake["racer dirt"] > brake["racer asphalt"] * 0.95 and brake["racer snow"] > brake["racer dirt"] and \
		brake["vortex snow"] / brake["vortex asphalt"] > brake["dune snow"] / brake["dune asphalt"] and \
		brake["vortex dirt"] / brake["vortex asphalt"] > brake["dune dirt"] / brake["dune asphalt"] and \
		turn["dune dirt"] > turn["vortex dirt"] + 0.4 and absf(float(Cars.get_car("dune").stats.grip) - float(Cars.get_car("vortex").stats.grip)) < 0.1 and \
		absf(brake["racer asphalt"] - float(rs.brake100)) < 0.06
	t.check(ok, "100-0 km/h: the racer stops in %.1f m on asphalt, %.1f on dirt, %.1f on snow; the Dune %.1f / %.1f / %.1f, the Vortex %.1f / %.1f / %.1f. Fastest 30 m turn on dirt: Dune %.2f g, Vortex %.2f g (on asphalt both about %.2f g)" % [
		brake["racer asphalt"], brake["racer dirt"], brake["racer snow"], brake["dune asphalt"], brake["dune dirt"], brake["dune snow"],
		brake["vortex asphalt"], brake["vortex dirt"], brake["vortex snow"], turn["dune dirt"], turn["vortex dirt"], float(rs.grip)])

	# (v6.10) better brakes on loose ground: every car stops 10-20 % shorter from 100 km/h on dirt
	# and snow than in v6.9.0 (V69_BRAKE100), the cars keep their order (the Dune best on snow, as
	# good as the best on dirt, the Thunder and the Vortex last), and braking hard in a 120 m curve
	# from 0.45 g no longer spins a car (a little sideslip at most)
	var lines_b: PackedStringArray = []
	var curve_b: PackedStringArray = []
	ok = true
	for sid: String in ["dirt", "snow"]:
		CarStats.surface = sid
		var d: Dictionary = {}
		var worst_beta: float = 0.0
		for id: String in Cars.ids():
			d[id] = CarStats.brake100(Cars.spec(id))
			var old: float = float(V69_BRAKE100[sid][id])
			var cut: float = 1.0 - float(d[id]) / old
			ok = ok and cut >= 0.1 and cut <= 0.2
			lines_b.append("%s %s %.1f m (%.1f, -%d %%)" % [id, sid, d[id], old, roundi(cut * 100.0)])
			var cb: Dictionary = _curve_brake(Cars.spec(id), 120.0, 4.5)
			ok = ok and not cb.spun and cb.beta < 5.0 and cb.wall == 0
			worst_beta = maxf(worst_beta, cb.beta)
		var order: Array = Cars.ids().duplicate()
		order.sort_custom(func(x: String, y: String) -> bool: return float(d[x]) < float(d[y]))
		var best: float = float(d[order[0]])
		ok = ok and float(d.dune) <= best + 0.2 and order.slice(4).has("thunder") and order.slice(4).has("vortex")
		if sid == "snow":
			ok = ok and order[0] == "dune"
		curve_b.append("%s at most %.1f°" % [sid, worst_beta])
	CarStats.surface = "asphalt"
	t.check(ok, "v6.10 brakes on loose ground: %s; braking hard in a 120 m curve from 0.45 g, no car spins (sideslip %s)" % [
		", ".join(lines_b), ", ".join(curve_b)])

	# (v6.10) slidier walls on loose ground: the Racer coasting at 108 km/h into a wall at 11°
	# (the stats road) loses less speed along it on dirt and less again on snow; asphalt as before
	var lost: Dictionary = {}
	for sid: String in ["asphalt", "dirt", "snow"]:
		CarStats.surface = sid
		lost[sid] = _scrape(Cars.default_spec(), 30.0, 0.2)
	CarStats.surface = "asphalt"
	t.check(lost.snow.x < lost.dirt.x and lost.dirt.x < lost.asphalt.x * 0.8 and lost.asphalt.y > 0 and lost.dirt.y > 0 and lost.snow.y > 0,
		"the wall along loose ground is slidier: the Racer scraping a wall loses %.1f m/s in 2 s on asphalt, %.1f on dirt, %.1f on snow (wall friction × %.2f / %.2f)" % [
			lost.asphalt.x, lost.dirt.x, lost.snow.x, float(Surfaces.def(dirt).wall), float(Surfaces.def(snow).wall)])

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


## (v6.10) Brake fully in a steady curve of radius R (CarStats.circle, the current
## CarStats.surface) entered at a_lat m/s²: {beta: the largest sideslip (°) while braking above
## 3 m/s, spun, wall: steps touching a wall}.
func _curve_brake(spec: CarSpec, R: float, a_lat: float) -> Dictionary:
	var tr: BuiltTrack = CarStats.circle(R)
	var v0: float = sqrt(a_lat * R)
	var car := Car.new(tr, 0, spec)
	car.place(tr, 0, {x = tr.px[0], z = tr.pz[0], yaw = atan2(tr.tx[0], tr.tz[0]), vx = tr.tx[0] * v0, vz = tr.tz[0] * v0, idx = 0, laps = 0})
	var ctrl := Car.Controls.new()
	var out: Dictionary = {beta = 0.0, wall = 0, spun = false}
	for s in 60 * 14:
		var look: int = maxi(2, JsMath.roundi((4.0 + car.speed * 0.3) / tr.seg_len))
		var i: int = (car.idx + look) % tr.N
		var gx: float = tr.px[i] - car.x
		var gz: float = tr.pz[i] - car.z
		var fx: float = sin(car.yaw)
		var fz: float = cos(car.yaw)
		ctrl.steer = clampf(3.0 * atan2(gx * fz - gz * fx, gx * fx + gz * fz), -1.0, 1.0)
		ctrl.throttle = clampf((v0 - car.forward_speed) * 0.8, -1.0, 1.0) if s < 60 * 4 else -1.0
		car.step(tr, ctrl, DT)
		if s >= 60 * 4:
			var beta: float = absf(atan2(car.side_speed, maxf(0.5, absf(car.forward_speed)))) * 180.0 / PI
			if car.speed > 3.0:
				out.beta = maxf(out.beta, beta)
				out.spun = out.spun or beta > 60.0
			if car.hit_wall:
				out.wall += 1
			if car.speed < 0.3:
				break
	return out


## (v6.10) Coast at v m/s into the left wall of the stats road (CarStats.road, the current
## CarStats.surface) at `ang` rad: Vector2(speed lost in the 2 s after the first touch, steps touching).
func _scrape(spec: CarSpec, v: float, ang: float) -> Vector2:
	var tr: BuiltTrack = CarStats.road()
	var i: int = 20
	var hw: float = tr.hw[i]
	var head: float = atan2(tr.tx[i], tr.tz[i])
	var yaw: float = head + ang * (1.0 if tr.nx[i] * cos(head) - tr.nz[i] * sin(head) > 0.0 else -1.0)
	var car := Car.new(tr, i, spec)
	car.place(tr, i, {x = tr.px[i] + tr.nx[i] * (hw - 4.0), z = tr.pz[i] + tr.nz[i] * (hw - 4.0), yaw = yaw,
		vx = sin(yaw) * v, vz = cos(yaw) * v, idx = i, laps = 0})
	var ctrl := Car.Controls.new(0.0, 0.0, false)
	var touch: int = 0
	var first: int = -1
	var v_first: float = 0.0
	for s in 60 * 4:
		car.step(tr, ctrl, DT)
		if car.hit_wall:
			touch += 1
			if first < 0:
				first = s
				v_first = car.speed
		if first >= 0 and s - first >= 120:
			break
	return Vector2(v_first - car.speed if first >= 0 else 0.0, touch)


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
func _lane_keeping(ids: PackedStringArray, lv: PackedInt32Array = PackedInt32Array()) -> void:
	var res: PackedStringArray = []
	var fails: int = 0
	var up: bool = not Upgrades.is_stock(lv)
	for id: String in ids:
		var r: Dictionary = _lane_runs(Upgrades.spec(id, lv))
		if not up:
			fails += int(r.fish)
			res.append("%s %d/36" % [id, int(r.fish)])
			continue
		# (v6.11) an upgraded car against the stock one on the same 36 drives: no slide, and no more
		# weave than the stock car's (more tyre grip answers the keys a little more sharply: the
		# Racer's tyres 3 weave 5.0° instead of 4.9° at 120 km/h with a 20 m look, sliding 2°)
		var r0: Dictionary = _lane_runs(Cars.spec(id))
		var worse: bool = float(r.slip) > 10.0 or float(r.slip) > float(r0.slip) + 0.5 or float(r.late) > float(r0.late) + 0.5
		fails += 1 if worse else 0
		res.append("%s slip %.1f° (stock %.1f°), weave %.1f° (%.1f°)" % [id, float(r.slip), float(r0.slip), float(r.late), float(r0.late)])
	if up:
		t.check(fails == 0, "keyboard lane keeping at 120-240 km/h (upgrades %s): no car slides, none weaves more than 0.5° beyond its stock self: %s" % [Upgrades.code(lv), ", ".join(res)])
	else:
		t.check(fails == 0, "keyboard lane keeping at 120-240 km/h, no fishtail with any car: %s" % ", ".join(res))


## The keyboard lane keeper's 36 drives (4 speeds x 3 dead bands x 3 look distances) with `spec`:
## {fish (drives that slid over 10° or weaved over 5° after 10 s), slip (the most sideslip, °),
## late (the most yaw after 10 s, °)}.
func _lane_runs(spec: CarSpec) -> Dictionary:
	var lane: BuiltTrack = straight_road("lane", 41, 40.0)
	var fish: int = 0
	var worst_slip: float = 0.0
	var worst_late: float = 0.0
	for kmh: float in [120.0, 160.0, 200.0, 240.0]:
		for dead: float in [0.02, 0.04, 0.08]:
			for look: float in [20.0, 35.0, 50.0]:
				var v: float = kmh / 3.6
				var i0: int = 20
				var car := Car.new(lane, i0, spec)
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
				worst_slip = maxf(worst_slip, max_slip)
				worst_late = maxf(worst_late, late)
	return {fish = fish, slip = worst_slip, late = worst_late}


## Jumps, every car: the test autopilot over every kicker (a steer key held through some flights):
## no bounce, no spin.
func _jumps(ids: PackedStringArray, lv: PackedInt32Array = PackedInt32Array()) -> void:
	var jumps: int = 0
	var bounces: int = 0
	var spins: int = 0
	var max_air: float = 0.0
	for id: String in ids:
		for track: BuiltTrack in tracks:
			if track.kickers.is_empty():
				continue
			for hold: int in [0, 1]:
				var car := Car.new(track, track.start_idx, Upgrades.spec(id, lv))
				# (v6.10: on a track with dirt or snow the driver knows the car's grip there; one that
				# didn't drove the Vortex into Forest Rally's last jump sideways off a wall)
				var pilot := Autopilot.basic(track, 13.0, 7.5, 77.0, Upgrades.spec(id, lv) if track.has_surfaces() else null)
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
		"jumps, every car%s: %d jumps, %d bounces, %d spins; holding a steer key through a whole flight turns the car at most %.1f° (limit 35°)" % [
			"" if Upgrades.is_stock(lv) else " (upgrades %s)" % Upgrades.code(lv), jumps, bounces, spins, max_air])


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

## v6.8.0: the tracks open one at a time (sim/unlocks.gd): the rule, opened tracks staying open
## when a medal gets harder or a track changes, the one-time upgrade of older saves (current and
## archived best times), junk, the terminal's flag and the career reset.
func _unlocks() -> void:
	t.section("tracks open one at a time (v6.8.0, sim/unlocks.gd)")
	var path: String = "user://test_unlock_save.json"
	var write := func(d: Dictionary) -> void:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(d))
		f.close()
		SaveData.use_file(path)
	var clean := func() -> void:
		for f: String in [path, path + ".bad", path + ".tmp"]:
			if FileAccess.file_exists(f):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var open_ids := func() -> PackedStringArray:
		var out: PackedStringArray = []
		for id: String in Tracks.ids():
			if Unlocks.is_open(id):
				out.append(id)
		return out
	var ids: PackedStringArray = Tracks.ids()
	var pv: int = Car.PHYSICS_VERSION
	var rec := func(time: float, sig: String) -> Dictionary: return {time = time, splits = [], physics = pv, sig = sig, date = "x"}
	var ro: BuiltTrack = Tracks.build("rookie-oval")
	var mro: Dictionary = Medals.medal_times(ro, "racer")

	# the rule
	clean.call()
	SaveData.use_file(path)
	var ok: bool = open_ids.call() == PackedStringArray(["rookie-oval"]) and Unlocks.open_count() == 1 and Unlocks.is_open("no-such-track") and \
		Unlocks.lock_text("hairpin-valley") == "Bronze on Rookie Oval to unlock" and Unlocks.lock_text("rookie-oval") == "" and \
		Unlocks.previous("hairpin-valley") == "rookie-oval" and Unlocks.previous("rookie-oval") == "" and Unlocks.next(ids[ids.size() - 1]) == "" and \
		Unlocks.earns("author") and Unlocks.earns("gold") and Unlocks.earns("silver") and Unlocks.earns("bronze") and not Unlocks.earns("") and not Unlocks.earns("tin")
	var c0: String = Unlocks.claim("rookie-oval", "")
	var c1: String = Unlocks.claim("rookie-oval", "bronze")
	var c2: String = Unlocks.claim("rookie-oval", "author")
	var c3: String = Unlocks.claim("ramp-rally", "gold") # (locked: no)
	var c4: String = Unlocks.claim("hairpin-valley", "silver")
	SaveData.use_file(path) # read back from the file
	var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	ok = ok and c0 == "" and c1 == "hairpin-valley" and c2 == "" and c3 == "" and c4 == "ramp-rally" and \
		open_ids.call() == PackedStringArray(["rookie-oval", "hairpin-valley", "ramp-rally"]) and Unlocks.lock_text("banked-speedway") == "Bronze on Ramp Rally to unlock" and \
		disk is Dictionary and JsMath.same(disk.get("version"), SaveData.VERSION) and disk.career.get("tracks_open") == ["hairpin-valley", "ramp-rally"]
	SaveData.open_track(ids[ids.size() - 2])
	ok = ok and Unlocks.claim(ids[ids.size() - 2], "bronze") == ids[ids.size() - 1] and Unlocks.claim(ids[ids.size() - 1], "author") == ""
	t.check(ok, "a new career: only Rookie Oval open; no medal opens nothing; bronze (or better) opens the next track once (announced once); a locked track's medal opens nothing; in the file's career.tracks_open (the version stays the current one); the last track opens nothing")

	# sticky: a bronze on Rookie Oval opened Hairpin Valley; a later version makes bronze faster than
	# that time (or changes the track, archiving the time): Hairpin Valley stays open
	write.call({version = 4, records = {"rookie-oval": {racer = rec.call(float(mro.bronze), ro.signature())}},
		career = {money = 0, points = 0, cars = ["racer"], paid = {}}})
	var first: bool = Unlocks.is_open("hairpin-valley") and not Unlocks.is_open("ramp-rally")
	SaveData.add_points(0) # (writes the file)
	var cars_m: Dictionary = Medals.data().tracks["rookie-oval"].cars.racer
	var bronze0: float = float(cars_m.bronze)
	cars_m.bronze = bronze0 - 30.0
	SaveData.use_file(path)
	var harder: String = Medals.medal_for(Medals.medal_times(ro, "racer"), bronze0) # (mro is that same Dictionary: its bronze changed too)
	var still: bool = Unlocks.is_open("hairpin-valley")
	Medals._loaded = false # (medals.json again)
	write.call({version = 4, records = {"rookie-oval": {racer = rec.call(bronze0, "1:2")}},
		career = {money = 0, points = 0, cars = ["racer"], paid = {}, tracks_open = ["hairpin-valley"]}})
	var moved: bool = SaveData.get_record("rookie-oval", "racer").is_empty() and SaveData.get_archived("records", "rookie-oval", "racer").has("1:2")
	t.check(first and harder == "" and still and moved and Unlocks.is_open("hairpin-valley") and float(Medals.medal_times(ro, "racer").bronze) == bronze0,
		"sticky: the bronze that opened Hairpin Valley earns no medal once bronze is 30 s faster, and the track stays open; also when the record moves to the archive (a changed track)")

	# the upgrade of a save from v6.7.0 or older (no career.tracks_open; every track was open): every
	# track with a best time (current or archived, any car) and the track after every bronze or
	# better (current or archived: archived times against today's bronze)
	var hv: BuiltTrack = Tracks.build("hairpin-valley")
	var rr: BuiltTrack = Tracks.build("ramp-rally")
	var tt: BuiltTrack = Tracks.build("technical-trial")
	var cr: BuiltTrack = Tracks.build("canyon-run")
	var m_hv: Dictionary = Medals.medal_times(hv, "racer")
	var m_rr: Dictionary = Medals.medal_times(rr, "racer")
	var m_tt: Dictionary = Medals.medal_times(tt, "racer")
	var m_cr: Dictionary = Medals.medal_times(cr, "kestrel")
	write.call({version = 4, records = {
		"rookie-oval": {racer = rec.call(float(mro.bronze), ro.signature())},          # bronze: opens Hairpin Valley
		"hairpin-valley": {racer = rec.call(float(m_hv.bronze) + 9.0, hv.signature())}, # driven, no medal: open, Ramp Rally not by it
		"ramp-rally": {racer = rec.call(float(m_rr.bronze) - 5.0, "1:2")},              # an old version's bronze (archived): Banked Speedway
		"technical-trial": {racer = rec.call(float(m_tt.bronze) + 5.0, String(V65_SIGS["technical-trial"]))}, # archived, no medal
		"coastal-gp": {bus = rec.call(1.0, Tracks.signature("coastal-gp"))},            # an unknown car: driven, no medal
		"canyon-run": {kestrel = rec.call(float(m_cr.bronze), cr.signature())},         # the Kestrel's bronze: Night Highway
		"lighthouse-bay": 5, "seaside-stunts": {racer = {time = "x"}}},
		archive = {records = {"forest-rally": {racer = {"9:9": {time = -3.0}}}}},
		career = {money = 10, points = 1, cars = ["racer"], paid = {}}})
	var want: PackedStringArray = ["hairpin-valley", "ramp-rally", "banked-speedway", "technical-trial", "coastal-gp", "canyon-run", "night-highway"]
	ok = SaveData.opened_tracks() == want and Unlocks.open_count() == 8 and not Unlocks.is_open("grand-marathon") and not Unlocks.is_open("mountain-pass") and \
		not Unlocks.is_open("lighthouse-bay") and not Unlocks.is_open("seaside-stunts") and not Unlocks.is_open("forest-rally") and SaveData.get_money() == 10
	SaveData.add_points(0)
	SaveData.use_file(path)
	disk = JSON.parse_string(FileAccess.get_file_as_string(path))
	ok = ok and disk is Dictionary and disk.career.get("tracks_open") == Array(want) and SaveData.opened_tracks() == want
	# version 3 (no career at all) the same way; a new player: none; with the terminal's flag: all open
	write.call({version = 3, records = {"rookie-oval": {racer = rec.call(float(mro.author), ro.signature())}}})
	var v3: bool = SaveData.opened_tracks() == PackedStringArray(["hairpin-valley"]) and int(SaveData.take_welcome().get("medals", 0)) == 4
	write.call({version = 4, career = {money = 0, points = 0, cars = ["racer"], paid = {}, tracks_unlocked = true}})
	var flag: bool = SaveData.opened_tracks().is_empty() and Unlocks.open_count() == ids.size() and Unlocks.lock_text("summit-rush") == ""
	t.check(ok and v3 and flag, "a save from v6.7.0: opens the tracks driven (Hairpin Valley, Ramp Rally, Technical Trial, Coastal GP, Canyon Run) and the ones after a bronze (Hairpin Valley, Banked Speedway after an archived Ramp Rally time under today's bronze, Night Highway after the Kestrel's): 8 open, in the file; junk ignored; a version 3 save the same way; with the terminal's flag every track is open")

	# junk in career.tracks_open: not a list is worked out again; a list is cleaned (unknown ids kept)
	var j_ok: int = 0
	for junk: Variant in ["x", 5, {}, null, true]:
		write.call({version = 4, records = {"rookie-oval": {racer = rec.call(float(mro.bronze), ro.signature())}},
			career = {money = 0, points = 0, cars = ["racer"], paid = {}, tracks_open = junk}})
		if SaveData.opened_tracks() == PackedStringArray(["hairpin-valley"]):
			j_ok += 1
	write.call({version = 4, career = {money = 0, points = 0, cars = ["racer"], paid = {}, tracks_open = ["ramp-rally", 3, "", "ramp-rally", "future-track", {}]}})
	t.check(j_ok == 5 and SaveData.opened_tracks() == PackedStringArray(["ramp-rally", "future-track"]) and Unlocks.is_open("ramp-rally") and not Unlocks.is_open("hairpin-valley"),
		"junk: %d of 5 non-lists are worked out again from the best times; a list keeps its track ids once each (an id from a newer version too)" % j_ok)

	# the terminal: unlock tracks opens everything; reset career turns it off, the tracks medals
	# opened stay open (a medal won while the flag was on counts too)
	write.call({version = 4, career = {money = 50, points = 5, cars = ["racer"], paid = {}, tracks_open = ["hairpin-valley"]}})
	SaveData.unlock_tracks(true)
	var all_open: bool = Unlocks.open_count() == ids.size()
	var quiet: String = Unlocks.claim("canyon-run", "gold") # (open by the flag: Night Highway opens for good, nothing to announce)
	SaveData.reset_career()
	SaveData.use_file(path)
	t.check(all_open and quiet == "" and not SaveData.tracks_unlocked() and open_ids.call() == PackedStringArray(["rookie-oval", "hairpin-valley", "night-highway"]) and
		SaveData.get_money() == 0, "unlock tracks opens all 15; reset career turns the flag off but keeps what medals opened (Hairpin Valley, and Night Highway from a gold while the flag was on)")
	SaveData.use_file(SaveData.DEFAULT_PATH)
	clean.call()


## v6.9.0: bronze is 1.3 × the author time (it was 1.5 ×, as in the browser version). The medal
## times and tools/medals.gd; and a player whose best time was a bronze under 1.5 × but isn't one
## now: the medal is gone from the menu (worked out from the best time), the track it opened stays
## open, what was paid stays paid and doesn't pay again.
func _faster_bronze() -> void:
	t.section("a faster bronze medal: 1.3 × the author time (v6.9.0)")
	var d: Dictionary = Medals.data()
	var tool: GDScript = load("res://tools/medals.gd")
	var ro: BuiltTrack = Tracks.build("rookie-oval")
	var mro: Dictionary = Medals.medal_times(ro, "racer")
	var faster: int = 0
	var pairs: int = 0
	var gap_min: float = INF
	var gap_max: float = 0.0
	for id: String in Tracks.ids():
		var tr: BuiltTrack = Tracks.build(id)
		for c: String in Cars.ids():
			var m: Dictionary = Medals.medal_times(tr, c)
			pairs += 1
			if m.is_empty():
				continue
			var was: float = float(Medals.medal_set(float(m.author), Medals.WEB_FACTORS).bronze)
			if float(m.bronze) < was and float(m.bronze) > float(m.silver):
				faster += 1
			gap_min = minf(gap_min, was - float(m.bronze))
			gap_max = maxf(gap_max, was - float(m.bronze))
	var ok: bool = is_equal_approx(float(Medals.FACTORS.bronze), 1.3) and is_equal_approx(float(Medals.FACTORS.gold), 1.06) and \
		is_equal_approx(float(Medals.FACTORS.silver), 1.2) and is_equal_approx(float(Medals.WEB_FACTORS.bronze), 1.5) and \
		JsMath.same((d.get("factors", {}) as Dictionary).get("bronze"), 1.3) and str(d.get("method", "")).contains("gold/silver/bronze = author × 1.06/1.2/1.3") and \
		str(tool.call("method_text")) == str(d.get("method", "")) and \
		JsMath.same(mro.author, 121.867) and JsMath.same(mro.gold, 130) and JsMath.same(mro.silver, 147) and JsMath.same(mro.bronze, 159) and \
		faster == pairs and tool.call("compared_medals") == ["author", "gold", "silver"]
	t.check(ok, "bronze = 1.3 × the author time, rounded up (it was 1.5 ×): Rookie Oval with the Racer %s / %s / %s / %s (bronze was 3:03); all %d of %d bronzes faster, by %d-%d s, and still slower than silver; medals.json's factors and method say 1.3; the browser comparison (tools/medals.gd --js) checks author, gold and silver, not bronze (1.5 × there)" % [
		RaceState.format_time(float(mro.author)), RaceState.format_time(float(mro.gold)), RaceState.format_time(float(mro.silver)), RaceState.format_time(float(mro.bronze)),
		faster, pairs, int(gap_min), int(gap_max)])

	# a v6.8.0 player: 3:03.000 on Rookie Oval was bronze there, paid $300 and 10 points, and opened
	# Hairpin Valley
	var path: String = "user://test_bronze_save.json"
	var clean := func() -> void:
		for f: String in [path, path + ".bad", path + ".tmp"]:
			if FileAccess.file_exists(f):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var write := func(data: Dictionary) -> void:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(data))
		f.close()
		SaveData.use_file(path)
	var rec := func(time: float) -> Dictionary: return {time = time, splits = [], physics = Car.PHYSICS_VERSION, sig = ro.signature(), date = "x"}
	var old_bronze: float = float(Medals.medal_set(float(mro.author), Medals.WEB_FACTORS).bronze)
	clean.call()
	write.call({version = 4, records = {"rookie-oval": {racer = rec.call(old_bronze)}},
		career = {money = 300, points = 10, cars = ["racer"], paid = {"rookie-oval": {racer = ["bronze"]}}, tracks_open = ["hairpin-valley"]}})
	var best: float = float(SaveData.get_record("rookie-oval", "racer").time)
	var now: String = Medals.medal_for(mro, best)
	var aim: Dictionary = Medals.next_medal(mro, best)
	ok = old_bronze == 183.0 and now == "" and aim.get("medal") == "bronze" and JsMath.same(aim.get("time"), 159) and \
		Unlocks.is_open("hairpin-valley") and not Unlocks.is_open("ramp-rally") and \
		SaveData.paid_rewards("rookie-oval", "racer") == PackedStringArray(["bronze"]) and SaveData.get_money() == 300 and SaveData.get_points() == 10
	# the same time again: no medal, nothing paid, nothing opened
	var same: Dictionary = Economy.claim("rookie-oval", "racer", now, "")
	var opened: String = Unlocks.claim("rookie-oval", now)
	# the new bronze (2:39): the medal is back, but it was paid: nothing new; then silver pays silver only
	var b2: Dictionary = Economy.claim("rookie-oval", "racer", Medals.medal_for(mro, float(mro.bronze)), "")
	var s2: Dictionary = Economy.claim("rookie-oval", "racer", Medals.medal_for(mro, float(mro.silver)), "")
	SaveData.use_file(path) # (read back)
	ok = ok and int(same.money) == 0 and opened == "" and int(b2.money) == 0 and Array(b2.repeat) == ["bronze"] and \
		int(s2.money) == 500 and SaveData.get_money() == 800 and SaveData.paid_rewards("rookie-oval", "racer") == PackedStringArray(["bronze", "silver"]) and \
		SaveData.opened_tracks() == PackedStringArray(["hairpin-valley"])
	t.check(ok, "a v6.8.0 player with 3:03.000 on Rookie Oval (bronze at 1.5 ×): no medal now (the next one to aim for is bronze, 2:39), but Hairpin Valley stays open and the $300 / 10 pts stay paid; that time again pays and opens nothing; a 2:39 bronze pays nothing new (paid before), a silver then pays only silver")
	# a save from v6.7.0 or older (no tracks_open yet) is upgraded against today's bronze: the same
	# 3:03 opens nothing after it (Rookie Oval is open anyway); a track driven stays open
	write.call({version = 4, records = {"rookie-oval": {racer = rec.call(old_bronze)}, "ramp-rally": {racer = {time = 999.0, splits = [], physics = Car.PHYSICS_VERSION, sig = Tracks.signature("ramp-rally"), date = "x"}}},
		career = {money = 0, points = 0, cars = ["racer"], paid = {}}})
	t.check(SaveData.opened_tracks() == PackedStringArray(["ramp-rally"]) and not Unlocks.is_open("hairpin-valley"),
		"a save from v6.7.0 or older (every track was open then) is upgraded against today's bronze: a 3:03 on Rookie Oval opens nothing after it; a track with a best time stays open (Ramp Rally)")
	SaveData.use_file(SaveData.DEFAULT_PATH)
	clean.call()


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
	# the upgrade is paid once: the file is the current version now (5 since v6.11.0) (a later load pays nothing more); a medal held is not paid again by a race
	SaveData.add_points(0) # (writes the file)
	SaveData.use_file(path)
	var on_disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	ok = ok and SaveData.get_money() == want and SaveData.take_welcome().is_empty() and on_disk is Dictionary and JsMath.same(on_disk.get("version"), SaveData.VERSION) and \
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

	# v6.6 reworked five tracks: a version 4 save from v6.5 keeps its career, its records, scores and
	# ghosts on the old Hairpin Valley move to the archive (their signature is v6.5's), those on
	# Rookie Oval stay; the rewards already paid on Hairpin Valley stay paid (they are kept by track
	# id): the new version's medal times pay only the medals and AI wins not paid before
	var hv_old: String = V65_SIGS["hairpin-valley"]
	var g_old: Dictionary = {format = Replay.GHOST_FORMAT, physics = pv, track = "hairpin-valley", sig = hv_old, laps = 3, car = "racer",
		time = 250.0, steps = 15000, every = 2, date = "x", n = 1, data = ""}
	write.call(JSON.stringify({version = 4,
		records = {"hairpin-valley": {racer = rec.call(250.0, hv_old)}, "rookie-oval": {racer = rec.call(float(mro.gold), ro.signature())}},
		scores = {"hairpin-valley": {racer = {score = 41000, date = "x", rules = ScoreState.SCORE_RULES, physics = pv, sig = hv_old}}},
		ghosts = {"hairpin-valley": {racer = g_old}},
		career = {money = 5000, points = 300, cars = ["racer"], paid = {"hairpin-valley": {racer = ["bronze", "silver", "gold", "ai-rookie"]},
			"rookie-oval": {racer = ["bronze", "silver", "gold"]}}}}))
	SaveData.use_file(path)
	var arch_ok: bool = SaveData.get_record("hairpin-valley", "racer").is_empty() and SaveData.get_best_score("hairpin-valley", "racer").is_empty() and \
		SaveData.load_ghost("hairpin-valley", "racer") == null and SaveData.get_archived("records", "hairpin-valley", "racer").has(hv_old) and \
		SaveData.get_archived("scores", "hairpin-valley", "racer").has(hv_old) and SaveData.get_archived("ghosts", "hairpin-valley", "racer").has(hv_old) and \
		not SaveData.get_record("rookie-oval", "racer").is_empty()
	var kept: bool = SaveData.get_money() == 5000 and SaveData.get_points() == 300 and SaveData.take_welcome().is_empty() and \
		SaveData.paid_rewards("hairpin-valley", "racer") == PackedStringArray(["bronze", "silver", "gold", "ai-rookie"])
	# a slower run (255 s against the archived 250 s) on the new Hairpin Valley is a new best there; a gold and a Rookie win pay nothing, author and an Amateur win pay
	var mnew: Dictionary = Medals.medal_times(hv, "racer")
	var best_new: bool = SaveData.submit_record("hairpin-valley", "racer", 255.0, PackedFloat64Array([85.0, 170.0, 255.0]))
	var again: Dictionary = Economy.claim("hairpin-valley", "racer", "gold", "rookie")
	var more: Dictionary = Economy.claim("hairpin-valley", "racer", "author", "amateur")
	var want_more: int = int(Economy.reward("hairpin-valley", "author").money) + int(Economy.reward("hairpin-valley", "ai-amateur").money)
	SaveData.use_file(path) # read back from the file
	var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	t.check(arch_ok and kept and best_new and int(again.money) == 0 and (again.repeat as PackedStringArray).size() == 4 and int(more.money) == want_more and \
		SaveData.get_money() == 5000 + want_more and not mnew.is_empty() and disk is Dictionary and JsMath.same(disk.get("version"), SaveData.VERSION) and \
		(((disk.get("archive", {}) as Dictionary).get("records", {}) as Dictionary).get("hairpin-valley", {}) as Dictionary).has("racer"),
		"a version 4 save from v6.5: its record, score and ghost on the old Hairpin Valley (%s) move to the archive, Rookie Oval's stay; nothing is paid or taken on loading; the rewards paid there stay paid: a gold and a Rookie win on the new version (%s) pay $0, author and an Amateur win $%s" % [
			hv_old, hv.signature(), UiFormat.points(want_more)])

	# v6.7.0, the terminal: the "tracks unlocked" flag and the career reset (save version 4 kept)
	write.call(JSON.stringify({version = 4, records = {"rookie-oval": {racer = rec.call(float(mro.gold), ro.signature())}},
		career = {money = 700, points = 30, cars = ["racer", "dune"], paid = {"rookie-oval": {racer = ["bronze", "silver", "gold"]}}}}))
	SaveData.use_file(path)
	ok = not SaveData.tracks_unlocked() and SaveData.unlock_tracks(true) and SaveData.tracks_unlocked() and not SaveData.unlock_tracks(true)
	SaveData.use_file(path) # read back from the file
	disk = JSON.parse_string(FileAccess.get_file_as_string(path))
	ok = ok and SaveData.tracks_unlocked() and disk is Dictionary and JsMath.same(disk.get("version"), SaveData.VERSION) and disk.career.get("tracks_unlocked") == true and \
		SaveData.get_money() == 700 and SaveData.owned_cars() == PackedStringArray(["racer", "dune"])
	ok = ok and SaveData.unlock_tracks(false) and not SaveData.tracks_unlocked() and not SaveData.unlock_tracks(false)
	SaveData.use_file(path)
	disk = JSON.parse_string(FileAccess.get_file_as_string(path))
	ok = ok and not SaveData.tracks_unlocked() and not (disk.career as Dictionary).has("tracks_unlocked")
	var junk_ok: int = 0
	for v: String in ["\"yes\"", "1", "false", "null", "{}"]:
		write.call("{\"version\": 4, \"career\": {\"money\": 5, \"tracks_unlocked\": %s}}" % v)
		SaveData.use_file(path)
		if not SaveData.tracks_unlocked() and SaveData.get_money() == 5:
			junk_ok += 1
	t.check(ok and junk_ok == 5, "the tracks flag (v6.7.0): off in a v6.6 file; unlock_tracks turns it on once (true when it changed), it is in the file's career (the file's version stays the current one) and read back; off again removes the key; %d of 5 junk values read as off" % junk_ok)
	write.call(JSON.stringify({version = 4, records = {"rookie-oval": {racer = rec.call(float(mro.gold), ro.signature())}},
		settings = {car = "dune", ghost = false}, networks = {racer = {best = {network = {layers = [1]}}}},
		career = {money = 700, points = 30, cars = ["racer", "dune"], tracks_unlocked = true, paid = {"rookie-oval": {racer = ["bronze", "silver", "gold"]}}}}))
	SaveData.use_file(path)
	SaveData.reset_career()
	SaveData.use_file(path)
	ok = SaveData.get_money() == 0 and SaveData.get_points() == 0 and SaveData.owned_cars() == PackedStringArray(["racer"]) and not SaveData.tracks_unlocked() and \
		SaveData.paid_rewards("rookie-oval", "racer").is_empty() and not SaveData.get_record("rookie-oval", "racer").is_empty() and \
		SaveData.get_setting("car") == "dune" and SaveData.get_setting("ghost") == false and SaveData.load_network("racer") is Dictionary and SaveData.take_welcome().is_empty()
	var again_paid: int = int(Economy.claim("rookie-oval", "racer", "gold", "").money)
	t.check(ok and again_paid == 300 + 500 + 800, "reset_career: $0, 0 points, only the Racer, the tracks flag off, nothing paid (a gold pays $1,600 again); the record, settings and network stay; no welcome note")
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


# ---- v6.11.0: car upgrades (sim/upgrades.gd) ------------------------------------------------

func _upgrades() -> void:
	t.section("car upgrades (v6.11.0): parts, specs, prices, buying, the save file, ghosts")
	var ids: PackedStringArray = Cars.ids()
	var stock: PackedInt32Array = Upgrades.stock()
	var all3 := PackedInt32Array([3, 3, 3, 3])
	# the table
	var ok: bool = Upgrades.ids() == PackedStringArray(["engine", "tyres", "nitro", "loose"]) and Upgrades.MAX_LEVEL == 3 and \
		Upgrades.part_id("Tires") == "tyres" and Upgrades.part_id("LOOSE GRIP") == "loose" and Upgrades.part_id("dirt") == "loose" and \
		Upgrades.part_id("Engine") == "engine" and Upgrades.part_id("nos") == "" and Upgrades.part_id("") == "" and \
		Upgrades.clean([9, -2, "x", 1.7, 5]) == PackedInt32Array([3, 0, 0, 1]) and Upgrades.clean("junk") == stock and Upgrades.clean(null) == stock and \
		Upgrades.clean([1, 2]) == PackedInt32Array([1, 2, 0, 0]) and Upgrades.clean([INF, NAN, 2, 2]) == PackedInt32Array([0, 0, 2, 2]) and \
		Upgrades.code(PackedInt32Array([2, 1, 0, 3])) == "E2 T1 N0 L3" and Upgrades.text(stock) == "stock" and \
		Upgrades.effect("engine", 2) == "+10 % power" and Upgrades.effect("tyres", 0) == "stock"
	for id: String in ids:
		ok = ok and Upgrades.spec(id, stock) == Cars.spec(id) and Upgrades.spec(id) == Cars.spec(id) and \
			Upgrades.spec(id, all3) == Upgrades.spec(id, all3) and Upgrades.spec(id, all3) != Cars.spec(id) and Upgrades.spec(id, all3).id == id
	t.check(ok, "the parts: engine, tyres, nitro, loose grip, three levels each; names and aliases (tires, loose grip, dirt); junk levels clamp to 0..3; level 0 everywhere is the stock spec itself (the same object), an upgraded spec is made once")

	# each part changes only its own numbers, by step x level of the stock value; max_speed (the
	# AI's speed scale), the mass, the brakes and the steering never change
	var bad: PackedStringArray = []
	var want_keys: Dictionary = {engine = ["torque"], tyres = ["mu", "dirtGrip", "snowGrip"], nitro = ["nitroTime", "nitroRefill"], loose = ["dirtGrip", "snowGrip"]}
	for id: String in ids:
		var st: CarSpec = Cars.spec(id)
		var sd: Dictionary = st.to_dict()
		for i in 4:
			var pid: String = Upgrades.ids()[i]
			for k in range(1, 4):
				var lv: PackedInt32Array = stock.duplicate()
				lv[i] = k
				var up: CarSpec = Upgrades.spec(id, lv)
				var d: Dictionary = up.to_dict()
				var g: float = float(Upgrades.PARTS[i].step) * k
				var changed: Array = []
				for key: String in d:
					if not JsMath.same(var_to_str(d[key]), var_to_str(sd[key])):
						changed.append(key)
				var expect: Array = want_keys[pid].duplicate()
				if pid == "loose" and st.dirt_grip * (1.0 + g) >= 1.0 and st.dirt_grip >= 1.0:
					expect.erase("dirtGrip")
				var right: bool = changed == expect
				match pid:
					"engine":
						for q in st.torque_nm.size():
							right = right and up.torque_nm[q] == st.torque_nm[q] * (1.0 + g) and up.torque_rpm[q] == st.torque_rpm[q]
					"tyres":
						right = right and up.mu == st.mu * (1.0 + g) and absf(up.mu * up.dirt_grip - st.mu * st.dirt_grip) < 1e-12 and \
							absf(up.mu * up.snow_grip - st.mu * st.snow_grip) < 1e-12
					"nitro":
						right = right and up.nitro_time == st.nitro_time * (1.0 + g) and up.nitro_refill == 1.0 + g
					"loose":
						right = right and up.mu == st.mu and up.dirt_grip == minf(1.0, st.dirt_grip * (1.0 + g)) and up.snow_grip == minf(1.0, st.snow_grip * (1.0 + g)) and \
							up.surface_grip[1] == up.dirt_grip and up.surface_grip[2] == up.snow_grip
				right = right and up.max_speed == st.max_speed and up.mass == st.mass and up.brake_force == st.brake_force
				if not right:
					bad.append("%s %s %d (changed %s)" % [id, pid, k, ",".join(PackedStringArray(changed))])
	# tyres and loose grip together: the grip on dirt and snow is the loose part's alone
	var both_ok: bool = true
	for id: String in ids:
		var st: CarSpec = Cars.spec(id)
		var a: CarSpec = Upgrades.spec(id, PackedInt32Array([0, 3, 0, 2]))
		var b: CarSpec = Upgrades.spec(id, PackedInt32Array([0, 0, 0, 2]))
		both_ok = both_ok and absf(a.mu * a.dirt_grip - b.mu * b.dirt_grip) < 1e-12 and absf(a.mu * a.snow_grip - b.mu * b.snow_grip) < 1e-12 and \
			b.mu * b.dirt_grip <= st.mu + 1e-12
	t.check(bad.is_empty() and both_ok, "every part, every level, every car: only its own numbers change (engine: the torque curve x 1 + 5 %% a level; tyres: the asphalt grip x 1 + 4 %%, the grip on dirt and snow kept; nitro: the tank and the refill x 1 + 10 %%; loose grip: the dirt and snow shares x 1 + 5 %%, never above the asphalt grip); the AI's speed scale, mass and brakes never; tyres + loose grip on dirt = loose grip alone%s" % [
		"" if bad.is_empty() else "; WRONG: " + ", ".join(bad)])

	# what the levels do, measured (Upgrades.MEASURED, from tools/upgrades.gd; car_stats' tolerance):
	# every engine level is quicker to 200 km/h and at least as fast at the top, every tyre level
	# grips more on both skidpads (the engine by about 5 % a level to 200 km/h, the tyres about 4 %)
	var lines: PackedStringArray = []
	ok = Upgrades.MEASURED.size() == ids.size()
	for id: String in ids:
		var base: Dictionary = Cars.get_car(id).stats
		var m: Dictionary = Upgrades.MEASURED.get(id, {})
		if not (m.get("engine") is Array and m.get("tyres") is Array and (m.engine as Array).size() == 3 and (m.tyres as Array).size() == 3):
			ok = false
			continue
		var prev: Dictionary = base
		var steps: PackedStringArray = []
		for k in 3:
			var e: Dictionary = m.engine[k]
			var a200: float = 1.0 - float(e.accel200) / float(prev.accel200)
			var top: float = float(e.top) / float(prev.top) - 1.0
			ok = ok and a200 > 0.02 and a200 < 0.09 and top >= 0.0 and top < 0.03 and float(e.accel100) <= float(prev.accel100)
			prev = e
		var prev_t: Dictionary = base
		for k in 3:
			var ty: Dictionary = m.tyres[k]
			var g: float = (float(ty.grip) + float(ty.gripFast)) / (float(prev_t.grip) + float(prev_t.gripFast)) - 1.0
			ok = ok and g > 0.01 and g < 0.06
			prev_t = ty
		var e3: Dictionary = m.engine[2]
		var t3: Dictionary = m.tyres[2]
		lines.append("%s 0-200 %.2f -> %.2f s, top %d -> %d km/h, grip %.2f/%.2f -> %.2f/%.2f g" % [id, float(base.accel200), float(e3.accel200),
			roundi(float(base.top)), roundi(float(e3.top)), float(base.grip), float(base.gripFast), float(t3.grip), float(t3.gripFast)])
		# the picker's bars: never below the stock car's, more speed / acceleration / grip / nitro at level 3 (unless already full)
		var b0: Dictionary = Cars.get_car(id).bars
		var b3: Dictionary = Upgrades.bars(id, all3)
		for k: String in ["speed", "acceleration", "grip", "nitro"]:
			ok = ok and float(b3[k]) >= float(b0[k]) and (float(b3[k]) > float(b0[k]) or float(b0[k]) >= 1.0)
		ok = ok and float(b3.drift) == float(b0.drift) and Upgrades.bars(id, stock) == b0
	t.check(ok, "measured (level 3 against stock): %s; each engine level 2-9 %% quicker to 200 km/h and 0-3 %% faster at the top, each tyre level 1-6 %% more grip; the picker's bars grow" % "; ".join(lines))

	# loose grip changes nothing on asphalt (bit for bit) and the nitro part refills more per point
	var ro: BuiltTrack = by_id("rookie-oval")
	var a_run: Dictionary = scored_race(ro, Autopilot.medal(ro, 18.0, 0.75), Cars.spec("dune"))
	var l_run: Dictionary = scored_race(ro, Autopilot.medal(ro, 18.0, 0.75), Upgrades.spec("dune", PackedInt32Array([0, 0, 0, 3])))
	var n_run: Dictionary = scored_race(ro, Autopilot.medal(ro, 18.0, 0.75), Upgrades.spec("dune", PackedInt32Array([0, 0, 3, 0])))
	var same: bool = (a_run.race as RaceState).finish_time == (l_run.race as RaceState).finish_time and (a_run.car as Car).x == (l_run.car as Car).x
	var refill: float = (n_run.score as ScoreState).nitro_earned / (a_run.score as ScoreState).nitro_earned
	t.check(same and (a_run.race as RaceState).finish_time == (n_run.race as RaceState).finish_time and absf(refill - 1.3) < 1e-9 and \
		(a_run.score as ScoreState).total == (n_run.score as ScoreState).total,
		"on all-asphalt Rookie Oval the loose grip part changes nothing (the Dune's race %s, bit for bit); nitro level 3 refills %.2f x as much of the tank for the same points (no nitro used: the same race)" % [
			RaceState.format_time((a_run.race as RaceState).finish_time), refill])

	# an upgraded car is faster on a lap and no less stable: everything at level 3 against stock,
	# the medal autopilot at one setting on Rookie Oval (asphalt) and Ramp Rally (dirt)
	var laps: PackedStringArray = []
	ok = true
	for tid: String in ["rookie-oval", "ramp-rally"]:
		var tr: BuiltTrack = by_id(tid)
		for id: String in ["racer", "thunder", "dune"]:
			var r0: Dictionary = Autopilot.drive_race(tr, 20.0, 0.75, id, true)
			var r3: Dictionary = Autopilot.drive_race(tr, 20.0, 0.75, id, true, Upgrades.spec(id, all3))
			ok = ok and r0.finished and r3.finished and float(r3.time) < float(r0.time) * 0.99
			laps.append("%s %s %s -> %s" % [tr.name, id, RaceState.format_time(float(r0.time)), RaceState.format_time(float(r3.time))])
	t.check(ok, "everything at level 3 is faster (the medal autopilot, 20 m/s², nitro): %s" % ", ".join(laps))
	_jumps(ids, all3)
	_lane_keeping(ids, all3)
	var spins: PackedStringArray = []
	ok = true
	for sid: String in ["asphalt", "dirt", "snow"]:
		CarStats.surface = sid
		var worst_beta: float = 0.0
		for id: String in ids:
			var cb: Dictionary = _curve_brake(Upgrades.spec(id, all3), 120.0, 4.5)
			ok = ok and not cb.spun and cb.beta < 5.0 and cb.wall == 0
			worst_beta = maxf(worst_beta, cb.beta)
		spins.append("%s at most %.1f°" % [sid, worst_beta])
	CarStats.surface = "asphalt"
	t.check(ok, "everything at level 3: braking hard in a 120 m curve from 0.45 g, no car spins (sideslip %s)" % ", ".join(spins))

	# prices: they rise with every level, scale with the car's price (the Racer counts as $12,000),
	# and every part of every car costs well over the cars themselves
	ok = Upgrades.base_price("racer") == Upgrades.FREE_CAR_BASE and Upgrades.base_price("vortex") == Economy.price("vortex")
	var cars_total: int = 0
	var rows: PackedStringArray = []
	for id: String in ids:
		cars_total += Economy.price(id)
		for pid: String in Upgrades.ids():
			var p1: int = Upgrades.price(id, pid, 1)
			var p2: int = Upgrades.price(id, pid, 2)
			var p3: int = Upgrades.price(id, pid, 3)
			ok = ok and p1 > 0 and p2 > p1 and p3 > p2 and p1 % Upgrades.ROUND == 0 and p3 % Upgrades.ROUND == 0 and \
				Upgrades.price(id, pid, 0) == 0 and Upgrades.price(id, pid, 4) == 0
		rows.append("%s %s" % [id, UiFormat.money(Upgrades.car_total(id))])
	ok = ok and Upgrades.price("vortex", "engine", 3) > Upgrades.price("kestrel", "engine", 3) * 2.9 and Upgrades.price("bus", "engine", 1) == 0 and \
		Upgrades.price("racer", "turbo", 1) == 0
	var total: int = Upgrades.total_all()
	var good: PackedInt32Array = Economy.career({medal = "gold", ai = "expert"})
	var best: PackedInt32Array = Economy.career({medal = "author", ai = "elite"})
	var one_good: int = good[good.size() - 1]
	var one_best: int = best[best.size() - 1]
	ok = ok and total > cars_total * 2 and total + cars_total > one_good * 3 and total + cars_total < one_good * ids.size() and total + cars_total < one_best * 3
	t.check(ok, "prices rise every level and follow the car's price: every part of every car costs %s (%s) against %s for the cars; a gold + Expert career with one car earns %s (author + Elite %s): the cars and every upgrade take %.1f gold careers (%.1f author careers) of the six" % [
		UiFormat.money(total), ", ".join(rows), UiFormat.money(cars_total), UiFormat.money(one_good), UiFormat.money(one_best),
		float(total + cars_total) / one_good, float(total + cars_total) / one_best])

	# buying, in the save file: only an owned car, one level at a time, in order, not past the top,
	# not without the money; read back from the file; the career reset takes them away
	var path: String = "user://test_upgrades_save.json"
	var write := func(text: String) -> void:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(text)
		f.close()
	var clean_up := func() -> void:
		for f: String in [path, path + ".bad", path + ".tmp"]:
			if FileAccess.file_exists(f):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	clean_up.call()
	SaveData.use_file(path)
	var e1: int = Upgrades.price("racer", "engine", 1)
	var e2: int = Upgrades.price("racer", "engine", 2)
	var e3: int = Upgrades.price("racer", "engine", 3)
	var u0: Dictionary = Economy.buy_upgrade("racer", "engine")
	SaveData.add_money(e1 + e2 + e3 + 500)
	var u1: Dictionary = Economy.buy_upgrade("racer", "engine")
	var skip: String = SaveData.purchase_upgrade("racer", "engine", 3, 0)
	var u2: Dictionary = Economy.buy_upgrade("racer", "engine")
	var u3: Dictionary = Economy.buy_upgrade("racer", "engine")
	var u4: Dictionary = Economy.buy_upgrade("racer", "engine")
	var lk: Dictionary = Economy.buy_upgrade("kestrel", "tyres")
	var un: Dictionary = Economy.buy_upgrade("racer", "turbo")
	var ub: Dictionary = Economy.buy_upgrade("bus", "engine")
	ok = not u0.ok and u0.error == "money" and int(u0.short) == e1 and int(u0.level) == 0 and u1.ok and int(u1.level) == 1 and int(u1.price) == e1 and \
		skip == "order" and u2.ok and int(u2.price) == e2 and u3.ok and int(u3.level) == 3 and not u4.ok and u4.error == "max" and \
		Economy.upgrade_price("racer", "engine") == 0 and not lk.ok and lk.error == "locked" and un.error == "unknown" and ub.error == "unknown" and \
		SaveData.get_money() == 500 and SaveData.get_upgrades("racer") == PackedInt32Array([3, 0, 0, 0])
	SaveData.add_money(Upgrades.price("racer", "nitro", 1) - 500 - 1)
	var short: Dictionary = Economy.buy_upgrade("racer", "nitro")
	ok = ok and not short.ok and short.error == "money" and int(short.short) == 1 and SaveData.get_upgrades("racer")[2] == 0
	SaveData.give_car("kestrel")
	SaveData.add_money(100000)
	ok = ok and Economy.buy_upgrade("kestrel", "loose").ok and Economy.upgrade_price("kestrel", "loose") == Upgrades.price("kestrel", "loose", 2)
	var money_before: int = SaveData.get_money()
	SaveData.use_file(path) # read back from the file
	var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	ok = ok and SaveData.get_upgrades("racer") == PackedInt32Array([3, 0, 0, 0]) and SaveData.get_upgrades("kestrel") == PackedInt32Array([0, 0, 0, 1]) and \
		SaveData.get_upgrades("vortex") == stock and SaveData.get_money() == money_before and disk is Dictionary and \
		JsMath.same(disk.get("version"), 5) and SaveData.VERSION == 5 and Upgrades.clean(disk.career.upgrades.racer) == PackedInt32Array([3, 0, 0, 0])
	ok = ok and not SaveData.set_upgrades("vortex", all3) and SaveData.set_upgrades("kestrel", PackedInt32Array([1, 9, -1, 2])) and \
		SaveData.get_upgrades("kestrel") == PackedInt32Array([1, 3, 0, 2]) and Upgrades.player_spec("kestrel") == Upgrades.spec("kestrel", PackedInt32Array([1, 3, 0, 2])) and \
		Upgrades.player_spec("vortex") == Cars.spec("vortex")
	SaveData.reset_career()
	ok = ok and SaveData.get_upgrades("racer") == stock and SaveData.get_upgrades("kestrel") == stock
	t.check(ok, "buying: $0 can't buy the Racer's engine 1 (%s short); then 1, 2, 3 in order (%s, %s, %s; level 3 can't be bought before 2), not a fourth, not for a car not owned, not an unknown part; $1 short buys nothing; read back from the file (version 5, career.upgrades); the terminal's set clamps and only for owned cars; the career reset makes every car stock again" % [
		UiFormat.money(e1), UiFormat.money(e1), UiFormat.money(e2), UiFormat.money(e3)])

	# the save file's migration: older files start with every part at level 0; junk is cleaned
	write.call(JSON.stringify({version = 4, settings = {car = "dune"}, career = {money = 1234, points = 5, cars = ["racer", "dune"], paid = {}, tracks_open = []}}))
	SaveData.use_file(path)
	ok = SaveData.get_upgrades("racer") == stock and SaveData.get_upgrades("dune") == stock and SaveData.get_money() == 1234 and Upgrades.player_spec("dune") == Cars.spec("dune")
	SaveData.add_money(0)
	disk = JSON.parse_string(FileAccess.get_file_as_string(path))
	ok = ok and disk is Dictionary and JsMath.same(disk.get("version"), 5) and disk.career.get("upgrades") == {} and disk.career.money == 1234
	write.call(JSON.stringify({version = 3, records = {}}))
	SaveData.use_file(path)
	SaveData.add_money(0)
	disk = JSON.parse_string(FileAccess.get_file_as_string(path))
	ok = ok and SaveData.get_upgrades("racer") == stock and disk.career.get("upgrades") == {}
	write.call("{\"version\": 5, \"career\": {\"money\": 9, \"cars\": [\"racer\", \"dune\"], \"upgrades\": {\"racer\": [9, \"x\", -1, 2, 7], \"dune\": [0, 0, 0, 0], \"kestrel\": [1, 1, 1, 1], \"bus\": [3, 3, 3, 3]}}}")
	SaveData.use_file(path)
	ok = ok and SaveData.get_upgrades("racer") == PackedInt32Array([3, 0, 0, 2]) and SaveData.get_upgrades("kestrel") == stock and SaveData.get_upgrades("dune") == stock
	var junk_ok: int = 0
	for j: String in ["5", "[]", "\"x\"", "{\"racer\": \"max\"}", "{\"racer\": {\"engine\": 3}}"]:
		write.call("{\"version\": 5, \"career\": {\"money\": 9, \"cars\": [\"racer\"], \"upgrades\": %s}}" % j)
		SaveData.use_file(path)
		if SaveData.get_upgrades("racer") == stock and SaveData.get_money() == 9:
			junk_ok += 1
	t.check(ok and junk_ok == 5, "the save file: a version 4 file (v6.10.0) keeps its career and starts with every part at level 0, written back as version 5 with an empty career.upgrades; a version 3 one too; a hand-edited list is clamped (racer [3, 0, 0, 2]), cars not owned or unknown dropped; %d of 5 kinds of junk read as stock" % junk_ok)

	# records and ghosts keep the levels of the run; an upgraded run's ghost replays exactly (ghosts
	# are poses: what the car has now doesn't matter); older records and ghosts read as stock
	write.call(JSON.stringify({version = 5, career = {money = 0, cars = ["racer"]}}))
	SaveData.use_file(path)
	var rr: BuiltTrack = by_id("ramp-rally")
	var spec3: CarSpec = Upgrades.spec("racer", all3)
	var car := Car.new(rr, rr.start_idx, spec3)
	var race := RaceState.new(rr)
	var score := ScoreState.new(rr, true)
	var pilot := Autopilot.medal(rr, 20.0, 0.75, true, Autopilot.DECEL, spec3)
	var rec := Replay.GhostRecorder.new()
	rec.add(0, car, true)
	var truth: Array[PackedFloat64Array] = [PackedFloat64Array([0, car.x, car.y, car.z, car.yaw])]
	var step: int = 0
	while not race.finished and step < 60 * 600:
		car.step(rr, pilot.drive(car), DT)
		step += 1
		race.update(car, DT)
		score.update(car, race, DT)
		rec.add(step, car, race.finished)
		truth.append(PackedFloat64Array([step, car.x, car.y, car.z, car.yaw]))
	var lv_run := PackedInt32Array([3, 3, 3, 3])
	var is_best: bool = SaveData.submit_record("ramp-rally", "racer", race.finish_time, race.splits, lv_run)
	ok = is_best and SaveData.save_ghost("ramp-rally", "racer", Replay.pack_ghost(rec, {track = rr, laps = race.laps, time = race.finish_time, car = "racer", up = lv_run}))
	SaveData.set_upgrades("racer", stock) # (what the car has now changes nothing in the replay)
	SaveData.use_file(path)
	var ghost: Dictionary = Replay.unpack_ghost(SaveData.load_ghost("ramp-rally", "racer"), rr, race.laps, "racer")
	var worst: float = 0.0
	var played: bool = not ghost.is_empty()
	if played:
		var play := Replay.GhostPlayer.new(ghost)
		for row: PackedFloat64Array in truth:
			if not play.pose(row[0]):
				played = false
				break
			worst = maxf(worst, JsMath.hypot3(play.car.x - row[1], play.car.y - row[2], play.car.z - row[3]))
	var stock_run: Dictionary = Autopilot.drive_race(rr, 20.0, 0.75, "racer", true)
	disk = JSON.parse_string(FileAccess.get_file_as_string(path))
	var r_saved: Dictionary = SaveData.get_record("ramp-rally", "racer")
	ok = ok and played and worst < 0.03 and ghost.up == lv_run and r_saved.up == lv_run and Upgrades.clean(disk.records["ramp-rally"].racer.up) == lv_run and \
		Upgrades.clean(disk.ghosts["ramp-rally"].racer.up) == lv_run and ghost.end == step and race.finish_time < float(stock_run.time)
	# a stock run keeps no tag; an older record and ghost without one read as stock
	SaveData.submit_record("rookie-oval", "racer", 500.0, [])
	var g_old: Dictionary = Replay.pack_ghost(rec, {track = rr, laps = race.laps, time = race.finish_time, car = "racer"})
	ok = ok and SaveData.get_record("rookie-oval", "racer").up == stock and not (JSON.parse_string(FileAccess.get_file_as_string(path)).records["rookie-oval"].racer as Dictionary).has("up") and \
		not g_old.has("up") and Replay.unpack_ghost(g_old, rr, race.laps, "racer").up == stock
	t.check(ok, "an upgraded run (the Racer, everything at level 3, Ramp Rally: %s against %s stock) is saved with its levels (record and ghost: [3, 3, 3, 3]); its ghost replays it within %.1f cm at every physics step after the car went back to stock; stock runs and older ones carry no levels and read as stock" % [
		RaceState.format_time(race.finish_time), RaceState.format_time(float(stock_run.time)), worst * 100.0])
	SaveData.use_file(SaveData.DEFAULT_PATH)
	clean_up.call()


# ---- Race the field (v6.13.0) ------------------------------------------------------------

## A car off any track at (x, z) heading `yaw` at `speed` along it (contact maths only).
static func free_car(x: float, z: float, yaw: float, speed: float, car_id: String = "racer") -> Car:
	var c := Car.new(null, -1, Cars.spec(car_id))
	c.x = x
	c.z = z
	c.yaw = yaw
	c.vx = sin(yaw) * speed
	c.vz = cos(yaw) * speed
	c.speed = speed
	return c


static func car_state(c: Car) -> PackedFloat64Array:
	return PackedFloat64Array([c.x, c.y, c.z, c.vx, c.vy, c.vz, c.yaw, c.yaw_rate, c.speed])


## Drive two cars straight (x += v dt, no physics) and collide them every step for `n` steps.
## Returns the largest overlap still there after two steps' contact passes in a row (m): what the push's
## limit (CarContact.MAX_PUSH) leaves after a deep first step must be gone the step after.
static func kinematic(a: Car, b: Car, n: int) -> float:
	var worst := 0.0
	var prev := 0.0
	for k in n:
		for c: Car in [a, b]:
			c.x += c.vx * DT
			c.z += c.vz * DT
			c.yaw += c.yaw_rate * DT
		CarContact.collide(a, b)
		var o := CarContact.overlap(a, b)
		if prev > 0.0:
			worst = maxf(worst, o)
		prev = o
	return worst


## A scripted field driver: an autopilot (sim/autopilot.gd) behind FieldRace's drive(track, car, race).
class PilotDriver:
	var pilot: Autopilot
	func _init(p: Autopilot) -> void:
		pilot = p
	func drive(_t: BuiltTrack, car: Car, _r: Variant) -> Car.Controls:
		return pilot.drive(car)


func _field() -> void:
	t.section("Race the field: solid cars (v6.13.0, sim/car_contact.gd)")
	# side by side, overlapping by 0.3 m, the left one drifting into the right one
	var a := free_car(0.0, 0.0, 0.0, 30.0)
	var b := free_car(-1.7, 0.4, 0.0, 30.0, "thunder")
	a.vx = -2.0
	var h := CarContact.Hit.new()
	var p0x := a.vx * a.spec.mass + b.vx * b.spec.mass
	var e0 := a.spec.mass * (a.vx * a.vx + a.vz * a.vz) + b.spec.mass * (b.vx * b.vx + b.vz * b.vz)
	var hit := CarContact.collide(a, b, h)
	var p1x := a.vx * a.spec.mass + b.vx * b.spec.mass
	var e1 := a.spec.mass * (a.vx * a.vx + a.vz * a.vz) + b.spec.mass * (b.vx * b.vx + b.vz * b.vz)
	t.check(hit and is_equal_approx(h.depth, 0.3) and absf(CarContact.overlap(a, b)) < 1e-9 and h.speed > 1.9 and a.vx > -2.0 and b.vx < 0.0 and
		absf(a.x - 0.0) > absf(b.x + 1.7) and e1 < e0 and absf(p1x) <= absf(p0x) + 1e-6,
		"two cars side by side 0.3 m into each other: pushed apart exactly (the light Racer moves %.3f m, the Thunder %.3f m), the closing speed %.1f m/s mostly gone (left car %.2f m/s, right car %.2f m/s), no energy made" % [
		absf(a.x), absf(b.x + 1.7), h.speed, a.vx, b.vx])
	t.check(a.vy == 0.0 and b.vy == 0.0 and a.y == 0.0 and b.y == 0.0, "nothing is launched: the contact is flat (no vertical speed, no height change)")
	t.check(not CarContact.collide(a, b), "once apart and moving apart: nothing more happens (no sticking)")
	var air := free_car(0.0, 0.0, 0.0, 30.0)
	var under := free_car(0.5, 0.5, 0.0, 10.0)
	air.y = CarContact.SKIP_DY + 0.1
	t.check(not CarContact.collide(air, under) and air.x == 0.0, "a car %.1f m higher (over a kicker) flies over the other" % (CarContact.SKIP_DY + 0.1))
	# symmetric and deterministic, bit for bit: a glancing rear corner hit with spin
	var same := true
	var sym := true
	for k in 20:
		var ang := 0.37 * k
		var mk := func(swap: bool) -> Array:
			var c1 := free_car(1.0 + 0.1 * k, 2.0, ang, 25.0 + k, "vortex")
			var c2 := free_car(1.0 + 0.1 * k + 1.2 * cos(ang), 2.0 + 3.1 * sin(ang + 0.4), ang + 0.6, 18.0, "dune")
			c1.yaw_rate = 0.3
			if swap:
				CarContact.collide(c2, c1)
			else:
				CarContact.collide(c1, c2)
			return [car_state(c1), car_state(c2)]
		var r1: Array = mk.call(false)
		var r2: Array = mk.call(true)
		var r3: Array = mk.call(false)
		sym = sym and r1[0] == r2[0] and r1[1] == r2[1]
		same = same and r1[0] == r3[0] and r1[1] == r3[1]
	t.check(sym and same, "collide(a, b) and collide(b, a) give exactly the same cars (20 glancing hits at different angles, bit for bit), and the same again on a re-run")
	# no tunnelling at top speed: a rear-end at 92 m/s into a standing car, a head-on of two at 92 m/s,
	# a T-bone at 92 m/s; the cars always end on the side they came from
	var rear_a := free_car(0.0, 0.0, 0.0, 92.0, "vortex")
	var rear_b := free_car(0.0, 20.0, 0.0, 0.0, "kestrel")
	var w1 := kinematic(rear_a, rear_b, 30)
	var head_a := free_car(0.3, 0.0, 0.0, 92.0, "vortex")
	var head_b := free_car(0.0, 25.0, PI, 92.0, "vortex")
	var w2 := kinematic(head_a, head_b, 20)
	var t_a := free_car(-12.0, 0.0, PI / 2.0, 92.0, "vortex")
	var t_b := free_car(0.0, 0.0, 0.0, 0.0, "racer")
	var w3 := kinematic(t_a, t_b, 20)
	var top := Cars.spec("vortex").max_speed
	t.check(top <= 92.0 and rear_a.z < rear_b.z and head_a.z < head_b.z and t_a.x < t_b.x and w1 < 1e-6 and w2 < 1e-6 and w3 < 1e-6 and
		rear_b.vz > 30.0 and rear_a.vz < 92.0,
		"no tunnelling at top speed (the fastest car's %.0f m/s): a rear-end at 92 m/s into a standing car, a head-on of two at 92 m/s and a T-bone at 92 m/s all stay on their side, what the push's limit leaves after the first step gone the step after (the standing car is shunted to %.0f m/s)" % [
		top, rear_b.vz])
	var m_sum := 0.0
	var e_ok := true
	for k in 30: # random hits: energy never grows, the yaw kick is bounded
		var q1 := free_car(rnd() * 2.0, rnd() * 2.0, rnd() * TAU, rnd() * 80.0, Cars.ids()[k % 6])
		var q2 := free_car(rnd() * 2.0, rnd() * 2.0, rnd() * TAU, rnd() * 80.0, Cars.ids()[(k + 3) % 6])
		var ke0: float = q1.spec.mass * q1.speed * q1.speed + q2.spec.mass * q2.speed * q2.speed
		var w0a := q1.yaw_rate
		var w0b := q2.yaw_rate
		CarContact.collide(q1, q2)
		var ke1: float = q1.spec.mass * q1.speed * q1.speed + q2.spec.mass * q2.speed * q2.speed
		e_ok = e_ok and ke1 <= ke0 * (1.0 + 1e-9) and finite(q1) and finite(q2) and absf(q1.yaw_rate - w0a) <= CarContact.MAX_SPIN + 1e-9 and \
			absf(q2.yaw_rate - w0b) <= CarContact.MAX_SPIN + 1e-9
		m_sum += absf(q1.yaw_rate) + absf(q2.yaw_rate)
	t.check(e_ok, "30 random hits between all six cars: never more kinetic energy after, every number finite, each yaw kick at most %.1f rad/s" % CarContact.MAX_SPIN)

	t.section("Race the field: the grid on every track (sim/field.gd)")
	var bad: PackedStringArray = []
	var widest := 0.0
	for id: String in Cars.ids():
		widest = maxf(widest, Cars.spec(id).radius)
	for id: String in Tracks.ids():
		var tr: BuiltTrack = Tracks.build(id)
		var g := Field.grid(tr, Field.AI_COUNT + 1)
		var issues: PackedStringArray = []
		var last: Dictionary = g[g.size() - 1]
		if int(last.idx) != tr.start_idx or float(last.lat) >= 0.0:
			issues.append("the player is not on the start spot's right")
		var first_cp: int = tr.cp_samples[0] if tr.cp_samples.size() > 0 else tr.finish_idx
		var cars: Array = []
		for k in g.size():
			var s: Dictionary = g[k]
			var i: int = s.idx
			if absf(float(s.lat)) + widest + 1.0 > tr.hw[i]:
				issues.append("slot %d is %.1f m from the wall" % [k + 1, tr.hw[i] - absf(float(s.lat)) - widest])
			if i >= first_cp - 10:
				issues.append("slot %d is at the first checkpoint" % (k + 1))
			if not tr.surface.is_empty() and tr.surface[i] != Surfaces.ASPHALT:
				issues.append("slot %d is not on asphalt" % (k + 1))
			if k > 0 and signf(float(s.lat)) == signf(float(g[k - 1].lat)):
				issues.append("slots %d and %d are on one side" % [k, k + 1])
			if k > 0 and int(g[k - 1].idx) - i != roundi(Field.SLOT_GAP / tr.seg_len):
				issues.append("slot %d is not %.0f m behind the one before" % [k + 1, Field.SLOT_GAP])
			var c := Car.new(tr, i, Cars.spec("thunder"))
			c.place(tr, i, {x = s.x, z = s.z, yaw = s.yaw, vx = 0.0, vz = 0.0, idx = i, laps = 0})
			if absf(c.lat - float(s.lat)) > 0.05 or c.idx != i and c.idx != i - 1:
				issues.append("slot %d does not locate back to itself" % (k + 1))
			cars.append(c)
		for i in cars.size():
			for j in range(i + 1, cars.size()):
				if CarContact.overlap(cars[i], cars[j], 2.0) > 0.0:
					issues.append("slots %d and %d are closer than 2 m" % [i + 1, j + 1])
		# the first corner: the road stays straight-ish over the grid
		var turn := 0.0
		for k in range(tr.start_idx, int(g[0].idx)):
			turn = maxf(turn, absf(wrap_a(atan2(tr.tx[k], tr.tz[k]) - atan2(tr.tx[tr.start_idx], tr.tz[tr.start_idx]))))
		if turn > deg_to_rad(20.0):
			issues.append("the grid turns %.0f°" % rad_to_deg(turn))
		if not issues.is_empty():
			bad.append("%s: %s" % [id, ", ".join(issues)])
	t.check(bad.is_empty(), "every track's grid (6 cars, %d m apart, two wide): the player on the start spot (right lane), the AI ahead alternating sides, all on the road with 1 m to spare beside the widest car, on asphalt, before the first checkpoint, at least 2 m apart, on a straight%s" % [
		int(Field.SLOT_GAP), "" if bad.is_empty() else ": " + "; ".join(bad)])

	t.section("Race the field: the lineup, positions and gaps (sim/field.gd, sim/field_race.gd)")
	var lu := Field.lineup("rookie-oval", "pro", "racer")
	var base := Opponents.time_of("rookie-oval", "racer", "pro")
	var names: Dictionary = {}
	var paces_ok := lu.size() == Field.AI_COUNT
	for k in lu.size():
		var e: Dictionary = lu[k]
		names[e.id] = true
		paces_ok = paces_ok and is_equal_approx(float(e.target), Field.PACE[k] * base) and float(e.cap) > 0.0 and Cars.has_car(String(e.car))
		if k > 0:
			paces_ok = paces_ok and float(e.target) < float(lu[k - 1].target)
	t.check(paces_ok and names.size() == Field.AI_COUNT and lu == Field.lineup("rookie-oval", "pro", "racer") and lu != Field.lineup("coastal-gp", "pro", "racer"),
		"a Pro field on Rookie Oval: five different drivers, the pole sitter the slowest (%.0f s) to the fastest (%.0f s, the Pro AI's time with your car), each with a speed cap; the same field every time, another one on another track" % [
		float(lu[0].target), float(lu[Field.AI_COUNT - 1].target)])
	var vs := Field.lineup("banked-speedway", "elite", "vortex")
	var swapped := 0
	for e: Dictionary in vs:
		if String(e.car) == "vortex":
			swapped += 1
		paces_ok = paces_ok and Opponents.time_of("banked-speedway", String(e.car), "elite") <= float(e.target) * 1.0001
	t.check(paces_ok and swapped >= 1, "an Elite field against the Vortex on Banked Speedway: a car that can't keep up there is swapped for your Vortex (%d of 5 drive it)" % swapped)
	var capo := Field.cap_for("rookie-oval", "racer", Opponents.time_of("rookie-oval", "racer", "amateur"))
	t.check(is_equal_approx(capo, Opponents.cap_of("rookie-oval", "racer", "amateur")) and Field.cap_for("rookie-oval", "racer", 1.0) == Opponents.cap_of("rookie-oval", "racer", "elite") and
		Field.cap_for("rookie-oval", "racer", 1000.0) < Opponents.cap_of("rookie-oval", "racer", "rookie") and Field.cap_for("nope", "racer", 100.0) == -1.0 and
		Field.place_name(1) == "1st" and Field.place_name(2) == "2nd" and Field.place_name(3) == "3rd" and Field.place_name(6) == "6th" and Field.place_name(11) == "11th",
		"cap_for: a level's own time gives its cap, faster than Elite the Elite's, slower than Rookie less than the Rookie's; place names 1st, 2nd, 3rd, 6th, 11th")
	# five identical autopilots from the grid: the pole leads, each car a slot behind is about 10 m
	# behind at the same speed (0.25 s at 40 m/s); the player standing on its slot is last
	var oval: BuiltTrack = Tracks.build("rookie-oval")
	var drivers: Array = []
	var fake: Array = []
	for k in Field.AI_COUNT:
		drivers.append(PilotDriver.new(Autopilot.basic(oval, 11.0, 7.5, 40.0)))
		fake.append({name = "Car %d" % k, code = "C%d" % k, car = "racer", color = "#ffffff", cap = INF, pace = 100.0 + k, slot = k})
	var pcar := Car.new(oval, oval.start_idx)
	var prace := RaceState.new(oval)
	var f := FieldRace.new(oval, fake, drivers, pcar, prace)
	var stand := Car.Controls.new()
	for k in 60 * 25:
		f.step(DT, stand)
	var order := f.standings()
	var gaps_ok := true
	for k in Field.AI_COUNT - 1:
		var g1 := f.gap(k, k + 1)
		gaps_ok = gaps_ok and absf(g1 - Field.SLOT_GAP / 40.0) < 0.05
	var bd := f.board(f.player_index)
	t.check(order == PackedInt32Array([0, 1, 2, 3, 4, 5]) and f.position(f.player_index) == 6 and gaps_ok and int(bd.pos) == 6 and int(bd.of) == 6 and
		String(bd.ahead.code) == "C4" and bd.behind.is_empty() and is_equal_approx(float(bd.ahead.gap), f.gap(4, 5)) and float(bd.rows[0].gap) < 0.0 and bd.rows[5].gap == null and
		f.ai_contacts == 0,
		"five identical autopilots for 25 s: in grid order, each %.2f s behind the one ahead (10 m at 40 m/s; %.3f, %.3f ...), you standing on the grid are P6/6, %s ahead by %.1f s; no contacts" % [
		Field.SLOT_GAP / 40.0, f.gap(0, 1), f.gap(1, 2), String(bd.ahead.code), float(bd.ahead.gap)])
	# finished cars by their times, then by progress, an out car last
	f.racers[3].race.finished = true
	f.racers[3].race.finish_time = 90.0
	f.racers[1].race.finished = true
	f.racers[1].race.finish_time = 91.0
	f.racers[0].dnf = true
	var rs := f.results()
	t.check(f.standings() == PackedInt32Array([3, 1, 2, 4, 5, 0]) and int(rs[0].i) == 3 and is_equal_approx(float(rs[1].gap), 1.0) and is_equal_approx(f.gap(3, 1), 1.0) and
		not is_finite(float(rs[2].time)) and bool(rs[5].dnf) and bool(rs[4].me),
		"standings: the finished by their times (1.0 s apart), then by progress, an out car last; the finish panel's rows say so")
	# the traffic layer: a fast car closing on a slow one in its lane eases off and steers round it
	var f2 := FieldRace.new(oval, fake, drivers, Car.new(oval, oval.start_idx), RaceState.new(oval))
	var slow: Car = f2.racers[0].car
	var fast: Car = f2.racers[1].car
	slow.place(oval, 120, {x = oval.px[120], z = oval.pz[120], yaw = atan2(oval.tx[120], oval.tz[120]), vx = oval.tx[120] * 20.0, vz = oval.tz[120] * 20.0, idx = 120, laps = 0})
	fast.place(oval, 112, {x = oval.px[112] + oval.nx[112] * 0.5, z = oval.pz[112] + oval.nz[112] * 0.5, yaw = atan2(oval.tx[112], oval.tz[112]),
		vx = oval.tx[112] * 40.0, vz = oval.tz[112] * 40.0, idx = 112, laps = 0})
	for r: FieldRace.Racer in f2.racers:
		if r.car != slow and r.car != fast:
			r.solid = false
	var c := Car.Controls.new(0.0, 1.0)
	f2.traffic(f2.racers[1], c)
	t.check(c.throttle < 0.0 and c.steer > 0.05, "the traffic layer: closing at 20 m/s on a car 16 m ahead in its lane, an AI brakes (throttle %.2f) and steers to the side with more room (%.2f, left: it was 0.5 m left of the other)" % [c.throttle, c.steer])

	t.section("Race the field: pay by place (sim/economy.gd)")
	var path := "user://test_sim_field.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	SaveData.use_file(path)
	var tid: String = Tracks.ids()[0]
	var third := Economy.claim(tid, "racer", "", "", "pro", 3)
	var again := Economy.claim(tid, "racer", "", "", "pro", 3)
	var win := Economy.claim(tid, "racer", "", "", "pro", 1)
	var full := Economy.payout(tid, "", "", PackedStringArray(), "pro", 1)
	var ids3: PackedStringArray = []
	for it: Dictionary in third.items:
		ids3.append(String(it.id))
	var ids1: PackedStringArray = []
	for it: Dictionary in win.items:
		ids1.append(String(it.id))
	t.check(ids3 == PackedStringArray(["field-pro-5", "field-pro-4", "field-pro-3"]) and int(third.money) == 460 and again.items.is_empty() and again.repeat.size() == 3 and
		ids1 == PackedStringArray(["field-pro-2", "field-pro-1"]) and int(win.money) == 1060 and int(full.money) == int(third.money) + int(win.money) and
		int(full.money) == 1520 and int(full.points) == 46 and SaveData.get_money() == 1520 and SaveData.get_points() == 46,
		"3rd in a Pro field on Rookie Oval pays 5th, 4th and 3rd ($%d); the same again nothing; 1st later pays only the difference (2nd and 1st, $%d): $%d and %d points in all, as a win straight away" % [
		int(third.money), int(win.money), int(full.money), int(full.points)])
	var other := Economy.payout(tid, "gold", "", SaveData.paid_rewards(tid, "racer"), "expert", 2)
	var more := true
	var lv: PackedStringArray = Opponents.ids()
	for k in range(1, lv.size()):
		more = more and int(Economy.payout(tid, "", "", PackedStringArray(), lv[k], 1).money) > int(Economy.payout(tid, "", "", PackedStringArray(), lv[k - 1], 1).money)
	t.check(other.items.size() == 7 and String(other.items[0].kind) == "medal" and String(other.items[6].kind) == "field" and Economy.label("field-expert-2") == "Expert field: 2nd" and
		Economy.payout(tid, "", "", PackedStringArray(), "pro", 6).items.is_empty() and Economy.field_ids("nope", 1).is_empty() and Economy.reward(tid, "field-pro-9").is_empty() and
		Economy.reward(tid, "field-x-1").is_empty() and more and Economy.payout(Tracks.ids()[14], "", "", PackedStringArray(), "pro", 1).money > full.money and
		SaveData.paid_rewards(tid, "kestrel").is_empty(),
		"another level pays on its own (gold + Expert 2nd: the medal's 3 rewards and 4 places, labelled \"Expert field: 2nd\"); last place pays nothing; harder fields and later tracks pay more; another car has its own list")



## v6.14.0: championships (sim/cups.gd, sim/cup_run.gd, sim/field.gd's grid by the standings,
## sim/economy.gd's cup payouts, the save file's cups section).
func _cups() -> void:
	t.section("Championships: the cups (sim/cups.gd)")
	var seen: Dictionary = {}
	var data_ok := Cups.ids().size() >= 4
	var means: PackedFloat64Array = []
	var opens_at: PackedInt32Array = []
	for id: String in Cups.ids():
		var tr := Cups.tracks_of(id)
		data_ok = data_ok and tr.size() >= 3 and tr.size() <= 4 and Cups.name_of(id) != id and String(Cups.cup(id).get("blurb", "")) != ""
		var sum := 0.0
		var last := -1
		for tid: String in tr:
			data_ok = data_ok and Tracks.index_of(tid) >= 0
			seen[tid] = int(seen.get(tid, 0)) + 1
			sum += float(Tracks.def(tid).get("difficulty", 0))
			last = maxi(last, Tracks.index_of(tid))
		means.append(sum / maxf(1.0, tr.size()))
		opens_at.append(last + 1)
	var once := seen.size() == Tracks.ids().size()
	for tid: String in Tracks.ids():
		once = once and int(seen.get(tid, 0)) == 1
	var rising := true
	for k in range(1, means.size()):
		rising = rising and means[k] >= means[k - 1] and opens_at[k] >= opens_at[k - 1]
	t.check(data_ok and once and rising and Cups.cup("nope").is_empty() and Cups.tracks_of("nope").is_empty(),
		"%d cups of 3-4 tracks, every one a real track, every track in exactly one cup; rising in difficulty (mean %s) and opening in order (with track %s)" % [
		Cups.ids().size(), ", ".join(Array(means).map(func(x: float) -> String: return "%.1f" % x)), ", ".join(Array(opens_at).map(func(x: int) -> String: return str(x)))])
	var path := "user://test_sim_cups.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	SaveData.use_file(path)
	var none_open := true
	for id: String in Cups.ids():
		none_open = none_open and not Cups.is_open(id)
	var miss := Cups.missing("rookie")
	SaveData.open_track("hairpin-valley")
	var one_short := not Cups.is_open("rookie")
	SaveData.open_track("ramp-rally")
	var rookie_open := Cups.is_open("rookie") and not Cups.is_open("asphalt") and Cups.missing("rookie").is_empty()
	SaveData.unlock_tracks(true)
	var all_open := true
	for id: String in Cups.ids():
		all_open = all_open and Cups.is_open(id)
	SaveData.unlock_tracks(false)
	t.check(none_open and miss == PackedStringArray(["hairpin-valley", "ramp-rally"]) and one_short and rookie_open and all_open and not Cups.is_open("asphalt") and not Cups.is_open("nope"),
		"a new career: no cup open (the Rookie Cup misses Hairpin Valley and Ramp Rally); it opens when its last track opens, the Asphalt Cup not yet; `unlock tracks` opens every cup")

	t.section("Championships: points and standings (sim/cups.gd)")
	var pts_ok := Cups.points_for(1) == 10 and Cups.points_for(2) == 8 and Cups.points_for(3) == 6 and Cups.points_for(4) == 5 and Cups.points_for(5) == 4 and \
		Cups.points_for(6) == 3 and Cups.points_for(7) == 0 and Cups.points_for(1, true) == 0 and Cups.points_for(0) == 0 and \
		Cups.trophy(1) == "gold" and Cups.trophy(2) == "silver" and Cups.trophy(3) == "bronze" and Cups.trophy(4) == ""
	var ent := PackedStringArray(["a", "b", "c", "d", "e", "you"])
	var race := func(order: Array, out: Array = []) -> Dictionary:
		var d: Dictionary = {}
		for k in order.size():
			d[order[k]] = {place = k + 1, dnf = out.has(order[k])}
		return d
	var races: Array = [race.call(["a", "b", "c", "d", "e", "you"]), race.call(["you", "c", "a", "b", "d", "e"]), race.call(["b", "you", "a", "c", "e", "d"], ["d"])]
	var tb := Cups.table(ent, races)
	var order: PackedStringArray = []
	var pts: PackedInt32Array = []
	for r: Dictionary in tb:
		order.append(String(r.id))
		pts.append(int(r.points))
	# a 10+6+6 = 22, b 8+5+10 = 23, c 6+8+5 = 19, you 3+10+8 = 21, d 5+4+0 (out) = 9, e 4+3+4 = 11
	t.check(pts_ok and order == PackedStringArray(["b", "a", "you", "c", "e", "d"]) and pts == PackedInt32Array([23, 22, 21, 19, 11, 9]) and int(tb[0].pos) == 1 and
		int(tb[5].dnf) == 1 and PackedInt32Array(tb[2].places) == PackedInt32Array([6, 1, 2]) and int(tb[2].best) == 1 and int(tb[2].last) == 2,
		"points 10-8-6-5-4-3 (none for 7th or an out car); three races: %s with %s points (d out in the last race scores 0 there)" % [", ".join(order), ", ".join(Array(pts).map(func(x: int) -> String: return str(x)))])
	# ties: equal points, the better best place first; equal best places too, the better last race
	var tie1 := Cups.table(PackedStringArray(["x", "y"]), [{x = {place = 1}, y = {place = 2}}, {x = {place = 6}, y = {place = 5}}, {x = {place = 6}, y = {place = 5}}])
	var tie2 := Cups.table(PackedStringArray(["x", "y"]), [{x = {place = 1}, y = {place = 1}}, {x = {place = 5}, y = {place = 6}}, {x = {place = 6}, y = {place = 5}}])
	var tie3 := Cups.table(PackedStringArray(["x", "y"]), [{x = {place = 3}, y = {place = 2}}, {x = {place = 2}, y = {place = 3}}])
	var tie4 := Cups.table(PackedStringArray(["x", "y", "z"]), [{x = {place = 1}, y = {place = 2}, z = {place = 3}}, {x = {place = 5}, y = {place = 3}, z = {place = 1}}])
	t.check(int(tie1[0].points) == 16 and int(tie1[1].points) == 16 and String(tie1[0].id) == "x" and int(tie2[0].points) == int(tie2[1].points) and String(tie2[0].id) == "y" and
		String(tie3[0].id) == "x" and String(tie4[0].id) == "z" and String(tie4[1].id) == "x" and int(tie4[1].points) == int(tie4[2].points),
		"ties: on equal points (16 each) the better best place leads (1st, 6th, 6th beats 2nd, 5th, 5th); with the same best place too, the better place in the last race (5th beats 6th; 2nd beats 3rd)")
	t.check(Cups.grid_order(ent, []) == ent and Cups.grid_order(ent, races) == order and Cups.table(ent, []).size() == 6 and int(Cups.table(ent, [])[5].points) == 0 and
		String(Cups.table(ent, [])[5].id) == "you",
		"the grid: before the first race the entrants as given (the field's grid: you last), after it the standings, the leader on pole (%s)" % ", ".join(order))

	t.section("Championships: a cup in progress (sim/cup_run.gd)")
	var run := CupRun.start("rookie", "pro", "racer")
	var drv := Field.cup_drivers("rookie", "pro")
	var same_drivers := run.drivers == drv and drv.size() == Field.AI_COUNT and drv == Field.cup_drivers("rookie", "pro") and drv != Field.cup_drivers("rookie", "elite")
	var f1: Dictionary = run.field("rookie-oval")
	var lu1: Array = f1.lineup
	var base := Opponents.time_of("rookie-oval", "racer", "pro")
	var paced := lu1.size() == Field.AI_COUNT and int(f1.player_slot) == Field.AI_COUNT
	for k in lu1.size():
		paced = paced and String(lu1[k].id) == drv[k] and is_equal_approx(float(lu1[k].target), Field.PACE[k] * base)
	t.check(run != null and same_drivers and paced and run.race_count() == 3 and run.next_track() == "rookie-oval" and run.entrants().size() == 6 and
		CupRun.start("nope", "pro", "racer") == null and CupRun.start("rookie", "nope", "racer") == null and CupRun.start("rookie", "pro", "nope") == null,
		"a Pro Rookie Cup: five drivers picked by the cup and level (%s), the same in every race; race 1 on Rookie Oval: the field's grid, the slowest at the front, you last" % ", ".join(drv))
	# race 1: you win; the grid of race 2 follows the standings (you on pole), the drivers keep their pace
	var rows1: Array = [{id = "you", place = 1}]
	for k in Field.AI_COUNT:
		rows1.append({id = drv[Field.AI_COUNT - 1 - k], place = k + 2})
	var bad_rows: Array = rows1.slice(0, 5)
	var added := run.add(rows1)
	var f2: Dictionary = run.field("hairpin-valley")
	var lu2: Array = f2.lineup
	var base2 := Opponents.time_of("hairpin-valley", "racer", "pro")
	var paced2 := lu2.size() == Field.AI_COUNT and int(f2.player_slot) == 0
	for k in lu2.size():
		var pace_rank := drv.find(String(lu2[k].id))
		paced2 = paced2 and String(lu2[k].id) == drv[Field.AI_COUNT - 1 - k] and is_equal_approx(float(lu2[k].target), Field.PACE[pace_rank] * base2)
	t.check(not CupRun.start("rookie", "pro", "racer").add(bad_rows) and added and run.races_done() == 1 and run.place() == 1 and run.next_track() == "hairpin-valley" and paced2 and
		run.grid()[0] == "you",
		"results that miss a driver are refused; after a win in race 1 you lead (10 points) and start race 2 on pole, the AI behind you in standings order, each keeping its own pace")
	var d := run.to_dict()
	var back := CupRun.from_dict(JSON.parse_string(JSON.stringify(d)))
	var junk_ok := CupRun.from_dict({}) == null and CupRun.from_dict({cup = "rookie", level = "pro", car = "racer", drivers = ["fox"], races = []}) == null and \
		CupRun.from_dict({cup = "rookie", level = "pro", car = "racer", races = [{}]}) == null and CupRun.from_dict("x") == null and \
		CupRun.from_dict({cup = "rookie", level = "pro", car = "racer", races = [rows1, rows1, rows1, rows1]}) == null
	t.check(back != null and back.to_dict() == run.to_dict() and back.place() == 1 and back.next_track() == "hairpin-valley" and junk_ok,
		"a cup in progress round-trips through JSON (the save file); a damaged one (another roster, a result missing drivers, more races than tracks) is dropped")
	var r2: Array = [{id = "you", place = 6}]
	var r3: Array = [{id = "you", place = 6}]
	for k in Field.AI_COUNT:
		r2.append({id = drv[k], place = k + 1})
		r3.append({id = drv[k], place = k + 1})
	run.add(r2)
	run.add(r3)
	var fin_tb := run.table()
	t.check(run.finished() and run.next_track() == "" and not run.add(r3) and run.place() == 4 and int(fin_tb[3].points) == 16 and int(fin_tb[4].points) == 16 and
		String(fin_tb[0].id) == drv[0] and int(fin_tb[0].points) == 23,
		"three races (you 1st, 6th, 6th: 16 points): the cup is over, %s leads with 23; you are 4th, ahead of two drivers on 16 points by your win" % String(fin_tb[0].id))

	t.section("Championships: the grid by the standings on every track (sim/field.gd, sim/field_race.gd)")
	var widest := 0.0
	for id: String in Cars.ids():
		widest = maxf(widest, Cars.spec(id).radius)
	var bad: PackedStringArray = []
	for id: String in Tracks.ids():
		var tr: BuiltTrack = Tracks.build(id)
		var first_cp: int = tr.cp_samples[0] if tr.cp_samples.size() > 0 else tr.finish_idx
		for anchor in range(Field.AI_COUNT):
			var g := Field.grid(tr, Field.AI_COUNT + 1, anchor)
			var issues: PackedStringArray = []
			var me: Dictionary = g[anchor]
			if int(me.idx) != tr.start_idx or float(me.lat) >= 0.0 or int(me.laps) != 0:
				issues.append("you are not on the start spot's right")
			var cars: Array = []
			var turn := 0.0
			for k in g.size():
				var s: Dictionary = g[k]
				var i: int = s.idx
				if absf(float(s.lat)) + widest + 1.0 > tr.hw[i]:
					issues.append("slot %d is %.1f m from the wall" % [k + 1, tr.hw[i] - absf(float(s.lat)) - widest])
				if k < anchor and i >= first_cp - 10:
					issues.append("slot %d is at the first checkpoint" % (k + 1))
				if not tr.surface.is_empty() and tr.surface[i] != Surfaces.ASPHALT:
					issues.append("slot %d is not on asphalt" % (k + 1))
				if k > 0 and signf(float(s.lat)) == signf(float(g[k - 1].lat)):
					issues.append("slots %d and %d are on one side" % [k, k + 1])
				if not tr.closed and i < Field.BACK_MIN:
					issues.append("slot %d is off the road's start" % (k + 1))
				turn = maxf(turn, absf(wrap_a(atan2(tr.tx[i], tr.tz[i]) - atan2(tr.tx[tr.start_idx], tr.tz[tr.start_idx]))))
				var c := Car.new(tr, i, Cars.spec("thunder"))
				c.place(tr, i, {x = s.x, z = s.z, yaw = s.yaw, vx = 0.0, vz = 0.0, idx = i, laps = int(s.laps)})
				var p_want: float = float(tr.start_idx) + (float(i) - float(tr.start_idx)) if int(s.laps) == 0 else float(i - tr.N)
				if absf(c.lat - float(s.lat)) > 0.05 or absf(c.prog - p_want) > 1.5:
					issues.append("slot %d does not locate back to itself" % (k + 1))
				if k > 0 and c.prog >= (cars[k - 1] as Car).prog:
					issues.append("slot %d is not behind slot %d" % [k + 1, k])
				cars.append(c)
			for i in cars.size():
				for j in range(i + 1, cars.size()):
					if CarContact.overlap(cars[i], cars[j], 2.0) > 0.0:
						issues.append("slots %d and %d are closer than 2 m" % [i + 1, j + 1])
			if turn > deg_to_rad(20.0):
				issues.append("the grid turns %.0f°" % rad_to_deg(turn))
			if not issues.is_empty():
				bad.append("%s (you %s): %s" % [id, Field.place_name(anchor + 1), ", ".join(issues)])
	t.check(bad.is_empty(), "every track, you anywhere from pole to 5th: you on the usual start spot (right lane), the cars the standings put ahead of you ahead, the rest behind it (behind the line on a circuit, closer together on a sprint's short road), alternating sides, on asphalt with 1 m to spare, at least 2 m apart, on a straight%s" % [
		"" if bad.is_empty() else ": " + "; ".join(bad)])
	# a race from pole on Rookie Oval: five identical autopilots behind you, three of them behind the line
	var oval: BuiltTrack = Tracks.build("rookie-oval")
	var drivers: Array = []
	var fake: Array = []
	for k in Field.AI_COUNT:
		drivers.append(PilotDriver.new(Autopilot.basic(oval, 11.0, 7.5, 40.0)))
		fake.append({id = "c%d" % k, name = "Car %d" % k, code = "C%d" % k, car = "racer", color = "#ffffff", cap = INF, pace = 100.0, slot = k})
	var pcar := Car.new(oval, oval.start_idx)
	var prace := RaceState.new(oval)
	var f := FieldRace.new(oval, fake, drivers, pcar, prace, {"id": "you", "name": "You", "code": "YOU"}, 0)
	var behind_line := 0
	for k in Field.AI_COUNT:
		if f.racers[k].car.prog < 0.0:
			behind_line += 1
	var start_ok := absf(pcar.prog - oval.start_idx) < 0.05 and f.racers[f.player_index].slot == 0 and f.position(f.player_index) == 1 and f.racers[0].slot == 1
	var stand := Car.Controls.new()
	for k in 60 * 25:
		f.step(DT, stand)
	var no_lap := true
	var gates_ok := true
	for k in Field.AI_COUNT:
		var rr: RaceState = f.racers[k].race
		no_lap = no_lap and rr.lap_times.is_empty() and rr.lap() == 1
		gates_ok = gates_ok and rr.next_gate >= 1
	var res := f.results()
	t.check(start_ok and behind_line >= 2 and no_lap and gates_ok and f.standings() == PackedInt32Array([0, 1, 2, 3, 4, 5]) and String(res[0].id) == "c0" and String(res[5].id) == "you",
		"a race with you on pole (standing): the five AI start behind you, %d behind the start line on Rookie Oval; 25 s later they have crossed it without a lap counted, passed checkpoints, and lead in grid order; the results carry the drivers' ids" % behind_line)

	t.section("Championships: the cup's pay, paid once (sim/economy.gd)")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	SaveData.use_file(path)
	var third := Economy.claim_cup("rookie", "pro", 3)
	var again := Economy.claim_cup("rookie", "pro", 3)
	var won := Economy.claim_cup("rookie", "pro", 1)
	var full := Economy.cup_payout("rookie", "pro", 1, PackedStringArray())
	var ids3: PackedStringArray = []
	for it: Dictionary in third.items:
		ids3.append(String(it.id))
	var ids1: PackedStringArray = []
	for it: Dictionary in won.items:
		ids1.append(String(it.id))
	t.check(ids3 == PackedStringArray(["cup-rookie-pro-4", "cup-rookie-pro-3"]) and int(third.money) == 1500 and again.items.is_empty() and again.repeat.size() == 2 and
		ids1 == PackedStringArray(["cup-rookie-pro-2", "cup-rookie-pro-1"]) and int(won.money) == 4800 and int(full.money) == 6300 and int(full.points) == 166 and
		SaveData.get_money() == 6300 and SaveData.get_points() == 166 and String(third.items[0].kind) == "cup",
		"3rd in a Pro Rookie Cup pays 4th and 3rd ($%d); the same again nothing; a win later only the difference (2nd and 1st, $%d): $%d and %d points in all, as a win straight away" % [
		int(third.money), int(won.money), int(full.money), int(full.points)])
	var lvls: PackedStringArray = Opponents.ids()
	var more := true
	for k in range(1, lvls.size()):
		more = more and int(Economy.cup_payout("rookie", lvls[k], 1, PackedStringArray()).money) > int(Economy.cup_payout("rookie", lvls[k - 1], 1, PackedStringArray()).money)
	for k in range(1, Cups.ids().size()):
		more = more and int(Economy.cup_payout(Cups.ids()[k], "pro", 1, PackedStringArray()).money) > int(Economy.cup_payout(Cups.ids()[k - 1], "pro", 1, PackedStringArray()).money)
	var fin := Economy.cup_payout("finale", "elite", 1, PackedStringArray())
	var rk := Economy.cup_payout("rookie", "rookie", 1, PackedStringArray())
	t.check(more and Economy.cup_payout("rookie", "pro", 5, PackedStringArray()).items.is_empty() and Economy.cup_ids("nope", "pro", 1).is_empty() and Economy.cup_ids("rookie", "x", 1).is_empty() and
		Economy.cup_reward("cup-dirt-snow-elite-1") == {money = 10500, points = 315} and Economy.cup_reward("cup-rookie-pro-6").is_empty() and Economy.cup_reward("cup-nope-pro-1").is_empty() and
		Economy.label("cup-dirt-snow-expert-2") == "Dirt and Snow Cup (Expert): 2nd" and Economy.cup_payout("asphalt", "pro", 1, SaveData.cup_paid()).items.size() == 4,
		"harder levels and later cups pay more (a Rookie win in the Rookie Cup %s, an Elite win in the Grand Finale %s); 5th and 6th pay nothing; cup ids with a dash read back (\"Dirt and Snow Cup (Expert): 2nd\"); another cup has its own rewards" % [
		UiFormat.money(int(rk.money)), UiFormat.money(int(fin.money))])

	t.section("Championships: the trophy cabinet and quitting (sim/save.gd)")
	var tro := SaveData.cup_trophies()
	Economy.claim_cup("rookie", "pro", 2) # (worse than the win: the gold stays)
	Economy.claim_cup("rookie", "elite", 3)
	var tro2 := SaveData.cup_trophies()
	t.check(tro == {"rookie": {"pro": 1}} and tro2 == {"rookie": {"pro": 1, "elite": 3}} and SaveData.cup_place("rookie", "elite") == 3 and SaveData.cup_place("asphalt", "pro") == 0,
		"the cabinet keeps each cup's best place per level: the Pro win stays gold after a 2nd, an Elite 3rd adds a bronze (%s)" % JSON.stringify(tro2))
	# a cup in progress: kept in the save file, read back after a restart; quitting drops it and pays nothing
	var run2 := CupRun.start("asphalt", "rookie", "racer")
	var rows_a: Array = [{id = "you", place = 1}]
	for k in Field.AI_COUNT:
		rows_a.append({id = run2.drivers[k], place = k + 2})
	run2.add(rows_a)
	SaveData.set_cup_run(run2.to_dict())
	var money_q := SaveData.get_money()
	var paid_q := SaveData.cup_paid()
	SaveData.use_file(path) # (read the file again, as after a restart)
	var kept := CupRun.from_dict(SaveData.get_cup_run())
	SaveData.clear_cup_run()
	SaveData.use_file(path)
	t.check(kept != null and kept.cup == "asphalt" and kept.races_done() == 1 and kept.place() == 1 and SaveData.get_cup_run().is_empty() and SaveData.get_money() == money_q and
		SaveData.cup_paid() == paid_q and SaveData.cup_trophies() == tro2,
		"a cup in progress is in the save file after a restart (the Asphalt Cup after race 1); quitting it drops it, pays nothing and leaves the cabinet as it was")
	# the end of a cup clears the cup in progress; the terminal's award and clear; reset; a damaged file
	SaveData.set_cup_run(run2.to_dict())
	Economy.claim_cup("asphalt", "rookie", 4)
	var ended := SaveData.get_cup_run().is_empty() and SaveData.cup_place("asphalt", "rookie") == 4
	SaveData.set_cup_place("finale", "elite", 1)
	SaveData.set_cup_place("rookie", "elite", 0)
	var award_ok := SaveData.cup_place("finale", "elite") == 1 and SaveData.cup_place("rookie", "elite") == 0 and SaveData.cup_place("rookie", "pro") == 1
	SaveData.set_cup_run(run2.to_dict())
	SaveData.reset_career()
	var reset_ok := SaveData.cup_place("rookie", "pro") == 1 and SaveData.cup_paid().is_empty() and SaveData.get_cup_run().is_empty()
	SaveData.clear_cup_trophies()
	var cleared := SaveData.cup_trophies().is_empty()
	var f2p := FileAccess.open(path, FileAccess.WRITE)
	f2p.store_string(JSON.stringify({version = 5, career = {money = 5, points = 1, cars = ["racer"], paid = {}, tracks_open = [],
		cups = {paid = ["cup-rookie-pro-4", 7, "cup-rookie-pro-4"], trophies = {rookie = {pro = 2, elite = "x", amateur = 9}, asphalt = "y"}, run = 3}}}))
	f2p.close()
	SaveData.use_file(path)
	var repaired := SaveData.cup_paid() == PackedStringArray(["cup-rookie-pro-4"]) and SaveData.cup_trophies() == {"rookie": {"pro": 2}} and SaveData.get_cup_run().is_empty()
	SaveData.use_file(path + ".none")
	var fresh := SaveData.cup_trophies().is_empty() and SaveData.cup_paid().is_empty() and SaveData.get_cup_run().is_empty()
	t.check(ended and award_ok and reset_ok and cleared and repaired and fresh,
		"the end of a cup clears the cup in progress; places set and cleared without paying (the terminal); a reset career keeps the trophies but not the cup payouts or a cup in progress; clearing the trophies; a damaged cups section is cleaned up; an old save (no cups section) has none")
	SaveData.use_file(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
