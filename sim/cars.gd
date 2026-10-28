class_name Cars
extends RefCounted
## cars.gd: the car catalogue (port of web/src/physics/cars.js).
## ------------------------------------------------------------------
## Each car is a physics spec (CarSpec: the racer with a few changes) plus
## what the menu, HUD and car models need. Data-driven: DEFS is the whole
## list; a new car is one more entry (and stats measured by tools/car_stats.gd).
##
##   racer    the v3 car, unchanged (CarSpec.new(); the default)
##   kestrel  light and grippy, quick off the line, lower top speed
##   thunder  heavy and powerful, the highest top speed, less grip, slower turn-in
##   drifter  loose rally car: slides and drifts easily, lands jumps softly
##   dune     open buggy: soft and forgiving, grips well everywhere, lower top speed
##            (keeps the most grip on dirt: dirtGrip, for surfaces that don't exist yet)
##   vortex   hypercar: the most power and top speed, light and twitchy, smallest nitro tank
##
## Use:
##   Cars.ids()            -> ["racer", "kestrel", "thunder", "drifter", "dune", "vortex"] (picker order)
##   Cars.get_car(id)      -> {id, name, description, look {color, accent, shape},
##                             spec: CarSpec, stats {...}, bars {...}}; unknown ids give the racer
##   Cars.spec(id)         -> CarSpec (Car.new(track, idx, Cars.spec(id)))
##   Cars.stat_bars(stats, spec) -> {speed, acceleration, grip, drift, nitro} (0..1)
##
## stats (measured with the real physics by tools/car_stats.gd, = the web game's
## tools/carStats.mjs; tests check they still match):
##   mass kg; accel100 / accel200 s (0-100 / 0-200 km/h); top km/h; accel200n s
##   (0-200 with nitro from a full tank); topNitro km/h; tankTime s; tankDist m;
##   brake100 m (100-0 km/h); grip / gripFast g (30 m / 120 m skidpad); drift s
##   (how long a keyboard driver holds a handbrake-started drift; median of 192 tries).
## Specs are read-only once a car uses them; every car shares the racer's collision
## capsule and wall constants. The AI trains with any car (its sensors scale speed by the
## car's max_speed, so changing a car's max_speed changes what its AI networks see) and never
## uses nitro.

const DEFAULT_CAR: String = "racer"

## Every car, in picker order. `changes`: CarSpec.make() overrides of the racer (JS names).
const DEFS: Array[Dictionary] = [
	{
		id = "racer", name = "Racer",
		description = "The all-rounder: quick, grippy and stable, never far off the pace anywhere.",
		look = {color = "#d7263d", accent = "#1b1b1e", shape = "the v3 sports car as it is (low wedge, rear wing)"},
		changes = {},
		stats = {mass = 1250, accel100 = 2.7, accel200 = 9.78, top = 277.7, accel200n = 7.57, topNitro = 291.8, tankTime = 5, tankDist = 145, brake100 = 30.7, grip = 1.68, gripFast = 1.58, drift = 0.83},
	},
	{
		id = "kestrel", name = "Kestrel",
		description = "Light and nimble: the most grip in slow corners, the shortest braking and the quickest launch, but a low top speed.",
		look = {color = "#f2c14e", accent = "#2b2d42", shape = "small, short, low roadster or hot hatch; narrow track look, small lip spoiler, no big wing"},
		changes = {
			id = "kestrel",
			mass = 950, inertia = 1250, cgToFront = 1.12, cgToRear = 1.33, cgHeight = 0.38, wheelRadius = 0.32,
			mu = 1.72, loadSensitivity = 0.08, dirtGrip = 0.72,
			drag = 0.75, downforce = 0, aeroFront = 0.44,
			idleRpm = 1100, redline = 9400, upshiftRpm = 9000, downshiftRpm = 5200, launchRpm = 6200,
			torque = [[1000, 220], [3000, 300], [5000, 335], [6500, 340], [8000, 300], [9000, 240], [9400, 210]],
			gears = [3.6, 2.55, 2.0, 1.6, 1.32, 1.1], finalDrive = 4.2, reverseRatio = 3.3, shiftTime = 0.08,
			driveFront = 0.4,
			brakeForce = 11600, brakeFront = 0.66,
			steerRate = 8, steerRefAccel = 19, airSteer = 0.17,
			nitroTime = 4, nitroForce = 3500, nitroPower = 90000, nitroTop = 67.9, nitroFade = 3,
			maxSpeed = 63.9,
		},
		stats = {mass = 950, accel100 = 2.43, accel200 = 11.28, top = 230.2, accel200n = 9.78, topNitro = 239.8, tankTime = 4, tankDist = 102, brake100 = 27.7, grip = 1.78, gripFast = 1.59, drift = 0.75},
	},
	{
		id = "thunder", name = "Thunder",
		description = "Heavy and brutal: huge power, a high top speed and the biggest nitro tank. Grips more the faster it goes; slow in tight turns.",
		look = {color = "#3a86ff", accent = "#0b0c10", shape = "long, wide grand tourer: long bonnet, fat rear tyres, big rear wing and splitter"},
		changes = {
			id = "thunder",
			mass = 1650, inertia = 3000, cgToFront = 1.35, cgToRear = 1.55, cgHeight = 0.45, wheelRadius = 0.35,
			mu = 1.37, loadSensitivity = 0.09, dirtGrip = 0.62,
			drag = 0.66, downforce = 2.2, aeroFront = 0.5,
			idleRpm = 900, redline = 7500, upshiftRpm = 7100, downshiftRpm = 3800, launchRpm = 4800,
			torque = [[1000, 450], [2500, 640], [4000, 760], [5500, 790], [6500, 760], [7200, 715], [7500, 670]],
			gears = [3.2, 2.35, 1.8, 1.45, 1.18, 0.985], finalDrive = 3.0, reverseRatio = 3.0,
			driveFront = 0.3,
			brakeForce = 17000, brakeFront = 0.66,
			steerRefAccel = 15.5, steerLock = 0.62,
			escMoment = 7800,
			nitroTime = 6, nitroForce = 6000, nitroPower = 170000, nitroTop = 92.7, nitroFade = 3,
			maxSpeed = 86.9,
		},
		stats = {mass = 1650, accel100 = 2.68, accel200 = 8.2, top = 312.7, accel200n = 6.08, topNitro = 328.9, tankTime = 6, tankDist = 194, brake100 = 33.8, grip = 1.47, gripFast = 1.56, drift = 1.07},
	},
	{
		id = "drifter", name = "Drifter",
		description = "Loose rally car: slides on demand, holds long drifts and lands jumps without losing speed.",
		look = {color = "#2ec4b6", accent = "#ff9f1c", shape = "tall rally hatchback: roof scoop, mud flaps, light pod on the bonnet, raised ride height"},
		changes = {
			id = "drifter",
			mass = 1150, inertia = 1500, cgToFront = 1.15, cgToRear = 1.35, cgHeight = 0.5, wheelRadius = 0.33,
			mu = 1.57, pacB = 12, pacC = 2.0, pacE = 0.95, loadSensitivity = 0.07, dirtGrip = 0.9,
			handbrake = 0.95, handbrakeFast = 0.7,
			drag = 0.7, downforce = 0.35, aeroFront = 0.45,
			idleRpm = 1000, redline = 7600, upshiftRpm = 7200, downshiftRpm = 4000, launchRpm = 5000,
			torque = [[1000, 308], [2500, 506], [4000, 550], [5500, 534], [6500, 484], [7200, 435], [7600, 396]],
			gears = [3.1, 2.3, 1.8, 1.45, 1.18, 0.92], finalDrive = 3.6, reverseRatio = 3.2,
			driveFront = 0.2, slideDrive = 0.6,
			brakeForce = 13000, brakeFront = 0.64,
			steerRate = 7.5, steerLock = 0.8, steerAssist = 0.5, assistFrom = 0.1,
			escHandbrakeHold = 2,
			hardLanding = 10, landingLoss = 0.003, airYawDamp = 1.5,
			nitroTime = 5, nitroForce = 4500, nitroPower = 110000, nitroTop = 79, nitroFade = 3,
			maxSpeed = 73.4,
		},
		stats = {mass = 1150, accel100 = 2.5, accel200 = 9.23, top = 264.3, accel200n = 7.57, topNitro = 278.9, tankTime = 5, tankDist = 142, brake100 = 33.1, grip = 1.59, gripFast = 1.52, drift = 1.63},
	},
	{
		id = "dune", name = "Dune",
		description = "Soft, forgiving buggy: big tyres, all-wheel traction and gentle slides, but the lowest top speed. Made for loose ground.",
		look = {color = "#8cc63f", accent = "#2b2e33", shape = "open dune buggy: tube roll cage, short nose, high ride on big tyres, exposed suspension, engine at the back"},
		changes = {
			id = "dune",
			mass = 1100, inertia = 1500, cgToFront = 1.25, cgToRear = 1.35, cgHeight = 0.55, wheelRadius = 0.4,
			mu = 1.68, pacB = 10, pacC = 1.75, pacE = 0.9, loadSensitivity = 0.06, dirtGrip = 0.97,
			handbrake = 0.85, handbrakeFast = 0.6,
			drag = 1.05, downforce = 0.1, aeroFront = 0.45,
			idleRpm = 900, redline = 6800, upshiftRpm = 6400, downshiftRpm = 3600, launchRpm = 4400,
			torque = [[1000, 360], [2500, 510], [4000, 545], [5000, 530], [6000, 470], [6500, 425], [6800, 390]],
			gears = [3.4, 2.4, 1.85, 1.48, 1.2, 1.0], finalDrive = 4.3, reverseRatio = 3.4,
			driveFront = 0.5,
			brakeForce = 12500, brakeFront = 0.62,
			steerLock = 0.75, steerRate = 7.5, steerRefAccel = 16, steerAssist = 0.8, assistFrom = 0.1,
			escGain = 9, escMoment = 5500,
			hardLanding = 9, landingLoss = 0.004, airYawDamp = 1.2,
			nitroTime = 5, nitroForce = 4200, nitroPower = 100000, nitroTop = 66, nitroFade = 3,
			maxSpeed = 61,
		},
		stats = {mass = 1100, accel100 = 2.87, accel200 = 12.68, top = 222.4, accel200n = 10.88, topNitro = 232.9, tankTime = 5, tankDist = 134, brake100 = 31.7, grip = 1.71, gripFast = 1.43, drift = 0.6},
	},
	{
		id = "vortex", name = "Vortex",
		description = "Hypercar: the most power and the highest top speed, light and twitchy, with the smallest nitro tank. Grips hard once it is fast.",
		look = {color = "#ff6b1a", accent = "#111216", shape = "very low, wide mid-engine hypercar: cab-forward bubble, roof scoop, long tail, big diffuser and an active rear wing"},
		changes = {
			id = "vortex",
			mass = 1150, inertia = 1500, cgToFront = 1.3, cgToRear = 1.4, cgHeight = 0.36, wheelRadius = 0.35,
			mu = 1.55, loadSensitivity = 0.08, dirtGrip = 0.6,
			drag = 0.6, downforce = 1.6, aeroFront = 0.45,
			idleRpm = 1100, redline = 9200, upshiftRpm = 8800, downshiftRpm = 5000, launchRpm = 4400,
			torque = [[1000, 380], [3000, 560], [5000, 660], [6500, 690], [8000, 650], [8800, 600], [9200, 550]],
			gears = [2.75, 2.2, 1.8, 1.5, 1.25, 1.05], finalDrive = 2.9, reverseRatio = 3.0,
			driveFront = 0.25, slideDrive = 1.0,
			brakeForce = 13600, brakeFront = 0.66,
			steerLock = 0.66, steerRate = 9, steerRefAccel = 20, steerAssist = 0.5,
			escGain = 7, escMoment = 4500,
			nitroTime = 3, nitroForce = 5500, nitroPower = 160000, nitroTop = 95, nitroFade = 3,
			maxSpeed = 91,
		},
		stats = {mass = 1150, accel100 = 2.57, accel200 = 6.22, top = 321.4, accel200n = 5.47, topNitro = 338.1, tankTime = 3, tankDist = 60, brake100 = 28.8, grip = 1.68, gripFast = 1.75, drift = 1.22},
	},
]

static var _cars: Dictionary = _build()
static var _ids: PackedStringArray = _list_ids()


static func _build() -> Dictionary:
	var out: Dictionary = {}
	for d: Dictionary in DEFS:
		var car: Dictionary = d.duplicate(true)
		car.erase("changes")
		car.spec = CarSpec.make(d.changes)
		car.bars = stat_bars(d.stats, car.spec)
		out[d.id] = car
	return out


static func _list_ids() -> PackedStringArray:
	var out: PackedStringArray = []
	for d: Dictionary in DEFS:
		out.append(String(d.id))
	return out


## Car ids in picker order.
static func ids() -> PackedStringArray:
	return _ids


## The definition of car `id` (unknown or missing ids give the racer).
static func get_car(id: String) -> Dictionary:
	return _cars.get(id, _cars[DEFAULT_CAR])


static func has_car(id: String) -> bool:
	return _cars.has(id)


## The physics spec of car `id` (unknown ids give the racer's).
static func spec(id: String) -> CarSpec:
	return get_car(id).spec


## The racer's spec (Car.new's default).
static func default_spec() -> CarSpec:
	return _cars[DEFAULT_CAR].spec


## 0..1 bars for the car picker, from a car's measured stats (fixed scales, so the cars compare).
static func stat_bars(stats: Dictionary, car_spec: CarSpec) -> Dictionary:
	var top: float = stats.top
	var accel100: float = stats.accel100
	var accel200: float = stats.accel200
	var grip: float = stats.grip
	var grip_fast: float = stats.gripFast
	var drift: float = stats.drift
	return {
		speed = _bar((top - 200.0) / 130.0), # top speed 200 -> 0, 330 km/h -> 1
		acceleration = _bar((0.6 * (3.2 - accel100)) / 1.0 + (0.4 * (13.0 - accel200)) / 6.0), # 0-100 3.2 s -> 0, 2.2 s -> 1 (60 %); 0-200 13 s -> 0, 7 s -> 1 (40 %)
		grip = _bar(((grip + grip_fast) / 2.0 - 1.3) / 0.6), # average of the two skidpads, 1.3 -> 0, 1.9 g -> 1
		drift = _bar(drift / 2.0), # keyboard drift held 0 -> 0, 2 s -> 1
		nitro = _bar((car_spec.nitro_power * car_spec.nitro_time) / car_spec.mass / 700.0), # boost energy per tank per kg, 0 -> 0, 700 J/kg -> 1
	}


static func _bar(v: float) -> float:
	return JsMath.round(maxf(0.05, minf(1.0, v)) * 100.0) / 100.0
