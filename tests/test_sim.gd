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
	_score()
	_ghosts()
	_medals()
	_save()
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


# ---- 1 + 2: build and drive every track; 3: backwards ------------------------------------

func _tracks_and_autopilot() -> void:
	t.section("tracks and the test autopilot")
	var ids: PackedStringArray = Tracks.ids()
	t.check(ids.size() == 12, "%d tracks defined (expected 12)" % ids.size())
	var exact: int = 0
	for id: String in ids:
		var track: BuiltTrack = Tracks.build(id)
		tracks.append(track)
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
		var web: Array = WEB_AUTOPILOT.get(id, [INF, -1])
		var same: bool = race.finished and JsMath.roundi(race.finish_time * 1000.0) == JsMath.roundi(float(web[0]) * 1000.0) and wall == int(web[1])
		if same:
			exact += 1
		t.check(track.cp_samples.size() > 0 and track.length > 1000.0 and race.finished and not bad and absf(race.finish_time - float(web[0])) < 0.1,
			"%s: builds (%.2f km%s, %d checkpoints, %s); the test autopilot finishes in %s, wall contact in %d steps (web game: %s, %d)" % [
				track.name, track.race_length(1) / 1000.0, "/lap" if track.closed else "", track.cp_samples.size(),
				"%d laps" % track.laps if track.closed else "sprint", RaceState.format_time(race.finish_time), wall,
				RaceState.format_time(float(web[0])), int(web[1])])
	t.check(exact == ids.size(), "the test autopilot drives the web game's times to the millisecond (and its wall steps) on %d of %d tracks" % [exact, ids.size()])

	var rookie: BuiltTrack = tracks[0]
	var car := Car.new(rookie)
	car.yaw += PI
	var race := RaceState.new(rookie)
	for k in 60 * 15:
		car.step(rookie, ctrl(0.0, 1.0), DT)
		race.update(car, DT)
	t.check(race.next_gate == 0, "driving backwards over the line scores no checkpoints")


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
	var hairpin: BuiltTrack = by_id("hairpin-valley")
	var lap := func(grip: float) -> Dictionary:
		var car := Car.new(hairpin)
		var race := RaceState.new(hairpin, 1)
		var pilot := Autopilot.basic(hairpin, grip)
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
		var track: BuiltTrack = by_id(id)
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
			var pilot := Autopilot.basic(track, grip, brake, spec.max_speed)
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
	var clean: Dictionary = scored_race(hairpin, Autopilot.basic(hairpin))
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
