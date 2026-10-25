class_name CarSpec
extends RefCounted
## car_spec.gd: a car's physics spec (port of CAR / makeSpec in web/src/physics/car.js).
## ------------------------------------------------------------------
## Every number the car physics uses comes from a spec. CarSpec.new() is the
## default car, 'racer' (the web game's CAR, unchanged since physics v3); the
## other cars are made from it with a few changes (make(), see sim/cars.gd).
## Fields are the JS names in snake_case (cgToFront -> cg_to_front); make() and
## to_dict() take and give the JS names, so specs can live in data.
##
##   CarSpec.make({mass = 950, ...})          -> racer + changes (JS names or snake_case)
##   CarSpec.make(changes, base)              -> base + changes
##   spec.to_dict()                           -> {id, mass, ...} with the JS names
##
## Specs are read-only once a car uses them: the derived constants (wheelbase,
## the tyre's peak slip, ...) are computed by make() / derive(), once.
## Every tuning constant below is identical to web/src/physics/car.js.

const G: float = 9.81

# --- identity --------------------------------------------------------------------
var id: String = "racer"        # the car's id in cars.gd
# --- chassis -----------------------------------------------------------------------
var mass: float = 1250.0          # kg
var inertia: float = 1850.0       # kg m², yaw
var cg_to_front: float = 1.2      # m, centre of gravity to front axle
var cg_to_rear: float = 1.4       # m, centre of gravity to rear axle (front ~54 % of the weight)
var cg_height: float = 0.42       # m, for longitudinal weight transfer
var wheel_radius: float = 0.34    # m
# --- tyres --------------------------------------------------------------------------
var mu: float = 1.6               # peak friction coefficient at the static axle load
var handbrake: float = 0.8        # handbrake rear brake force, fraction of the rear tyres' grip (<= 25 m/s)
var handbrake_fast: float = 0.55  # ... and at >= 55 m/s
var handbrake_rate: float = 6.0   # how fast the handbrake lever comes on (1/s); releases twice as fast
var load_sensitivity: float = 0.08 # grip per load falls 8 % per extra 100 % load
var pac_b: float = 13.0           # magic formula shape (peak at ~8°)
var pac_c: float = 1.9
var pac_e: float = 0.97
# --- aero ---------------------------------------------------------------------------
var drag: float = 0.62            # N per (m/s)²  (½ ρ Cd A)
var downforce: float = 0.65       # N per (m/s)²  (½ ρ Cl A)
var aero_front: float = 0.42      # share of downforce on the front axle
var roll_resist: float = 0.013    # rolling resistance coefficient
# --- engine and gearbox ---------------------------------------------------------------
var idle_rpm: float = 1000.0
var redline: float = 8200.0       # rev limiter
var upshift_rpm: float = 7700.0
var downshift_rpm: float = 4200.0
var launch_rpm: float = 5500.0    # clutch slip rpm at full throttle from standstill
var torque: Array = [[1000, 260], [2500, 380], [4500, 470], [6000, 480], [7000, 455], [7800, 420], [8200, 380]] # [rpm, Nm]
var gears: PackedFloat64Array = PackedFloat64Array([3.55, 2.78, 2.17, 1.70, 1.33, 1.04])
var final_drive: float = 3.4
var reverse_ratio: float = 3.2
var efficiency: float = 0.88
var shift_time: float = 0.12      # s without drive while shifting
var drive_front: float = 0.35     # all-wheel drive split (front share)
var slide_drive: float = 1.2      # rear slip (× peak) above which throttle keeps the rear sliding (power slide); INF = never
var max_reverse: float = 15.0     # m/s
# --- brakes -------------------------------------------------------------------------
var brake_force: float = 13800.0  # N total at full pedal (≈1.12 g)
var brake_front: float = 0.68     # brake bias
# --- steering -----------------------------------------------------------------------
var steer_lock: float = 0.7       # rad, front wheel angle at full lock (low speed, and the countersteer limit)
var steer_rate: float = 7.0       # steering command units per second (lock to lock ≈ 0.3 s)
var steer_ref_accel: float = 18.0 # m/s², lateral acceleration full steer asks for (sets the speed-sensitive lock)
var steer_slip_gain: float = 1.15 # below steer_slow_speed full lock adds 1.15 × the tyre's peak slip angle on top ...
var steer_extra_fast: float = 0.04 # rad, ... fading to only this much above steer_fast_speed
var steer_slow_speed: float = 12.0 # m/s
var steer_fast_speed: float = 35.0 # m/s
var steer_assist: float = 0.65    # countersteer assist in slides: share of the rear slip angle added to the steering
var assist_from: float = 0.12     # rad of rear slip where the assist starts
var assist_full: float = 0.25     # rad of rear slip where it is fully on
# --- stability control (ESC) ----------------------------------------------------------
var esc: float = 1.0              # 0 = off, 1 = on
var esc_gain: float = 8.0         # 1/s, how hard it pulls the yaw rate back towards what the steering asks for
var esc_moment: float = 5000.0    # N m, largest corrective yaw moment (braking single wheels)
var esc_under: float = 0.3        # share of that moment used against understeer
var esc_deadband: float = 0.04    # rad/s of yaw-rate error it ignores
var esc_slow: float = 0.25        # share of the implied single-wheel braking that slows the car
var esc_from: float = 8.0         # m/s, active above this speed
var esc_handbrake_hold: float = 1.5 # s it stays off after the handbrake is released
# --- body / collision ------------------------------------------------------------------
var radius: float = 1.0           # m, capsule radius (half width of the car)
var half_length: float = 2.2      # m, half length of the car (capsule tip to centre)
var wall_restitution: float = 0.05
var max_rebound: float = 1.0      # m/s, cap on the bounce-back speed
var wall_friction: float = 0.5    # a hit takes this much speed along the wall per m/s of speed into it ...
var wall_crush: float = 0.06      # ... plus this much per (m/s)² (s/m)
var wall_slide: float = 5.0       # m/s, below this speed along the wall that friction fades out
var wall_rub: float = 0.15        # 1/s, share of its speed along the wall a car touching the wall loses per second ...
var wall_rub_build: float = 1.0   # s, ... building up over this much contact
var wall_align: float = 1.5       # rad/s, top yaw rate of the alignment with a wall the car is scraping ...
var wall_align_gain: float = 12.0 # 1/s, ... per rad of angle between the heading and the wall
var wall_align_accel: float = 15.0 # rad/s², how quickly that alignment builds up
var wall_yaw_stop: float = 0.4    # share of the into-wall rotation a scraping corner removes per sub-step
var wall_latch: float = 0.12      # m, a scraping car counts as touching while this close to the wall ...
var wall_latch_steps: float = 10.0 # ... for up to this many steps after its last real contact
var wall_height: float = 1.1      # m, barrier height: a car flying higher only stays inside the barrier line
# --- vertical ---------------------------------------------------------------------------
var gravity: float = G
var lift_separation: float = 0.15 # m the car must be predicted to rise above the road before it takes off
var min_flight: float = 0.25      # s of predicted flight needed to take off
var hard_landing: float = 4.0     # m/s vertical impact speed above which landings cost speed ...
var landing_loss: float = 0.012   # ... this share of the speed per m/s above it (at most 15 %)
var air_steer: float = 0.2        # rad/s of yaw rate full steer gives in the air
var air_steer_tau: float = 0.2    # s, how quickly that steering yaw builds up and dies away
var air_yaw_damp: float = 0.6     # 1/s, decay of the yaw rate the car had at take-off
# --- nitro (v4) ---------------------------------------------------------------------------
var nitro_time: float = 5.0       # s a full tank lasts at full nitro
var nitro_force: float = 4500.0   # N, largest extra push (at low speed) ...
var nitro_power: float = 130000.0 # W, ... and at speed: push = min(nitro_force, nitro_power / speed)
var nitro_top: float = 82.3       # m/s, the push fades out over the last ...
var nitro_fade: float = 3.0       # m/s ... below this speed (top speed with nitro ≈ 292 km/h)
# --- simulation ---------------------------------------------------------------------------
var substeps: int = 2
var max_speed: float = 77.0       # m/s: top speed on the flat (≈277 km/h); also normalises the AI speed input

# --- derived (derive(); JS derived()) -------------------------------------------------------
var wheelbase: float = 0.0        # L
var core: float = 0.0             # half length of the capsule's core segment
var peak_slip: float = 0.0        # slip (tan of the slip angle) where the magic formula peaks
var pac_slope0: float = 0.0       # d(force ratio)/d(slip) at zero slip
var peak_steer: float = 0.0       # front slip angle full steer adds at speed
var torque_rpm: PackedFloat64Array = PackedFloat64Array()
var torque_nm: PackedFloat64Array = PackedFloat64Array()
var derived: bool = false

## The JS names of the spec fields, in CAR's order (to_dict / make).
const KEYS: PackedStringArray = [
	"id", "mass", "inertia", "cgToFront", "cgToRear", "cgHeight", "wheelRadius",
	"mu", "handbrake", "handbrakeFast", "handbrakeRate", "loadSensitivity", "pacB", "pacC", "pacE",
	"drag", "downforce", "aeroFront", "rollResist",
	"idleRpm", "redline", "upshiftRpm", "downshiftRpm", "launchRpm", "torque", "gears", "finalDrive", "reverseRatio",
	"efficiency", "shiftTime", "driveFront", "slideDrive", "maxReverse",
	"brakeForce", "brakeFront",
	"steerLock", "steerRate", "steerRefAccel", "steerSlipGain", "steerExtraFast", "steerSlowSpeed", "steerFastSpeed",
	"steerAssist", "assistFrom", "assistFull",
	"esc", "escGain", "escMoment", "escUnder", "escDeadband", "escSlow", "escFrom", "escHandbrakeHold",
	"radius", "halfLength", "wallRestitution", "maxRebound", "wallFriction", "wallCrush", "wallSlide", "wallRub",
	"wallRubBuild", "wallAlign", "wallAlignGain", "wallAlignAccel", "wallYawStop", "wallLatch", "wallLatchSteps", "wallHeight",
	"gravity", "liftSeparation", "minFlight", "hardLanding", "landingLoss", "airSteer", "airSteerTau", "airYawDamp",
	"nitroTime", "nitroForce", "nitroPower", "nitroTop", "nitroFade",
	"substeps", "maxSpeed",
]


func _init() -> void:
	derive()


## A new spec: `base` (default: the racer) with `changes` on top (JS or snake_case names).
static func make(changes: Dictionary = {}, base: CarSpec = null) -> CarSpec:
	var s := CarSpec.new()
	if base != null:
		s.apply(base.to_dict())
	s.apply(changes)
	return s


## Sets fields from a dictionary (JS or snake_case names) and recomputes the derived constants.
func apply(changes: Dictionary) -> void:
	for k: Variant in changes:
		var key: String = String(k).to_snake_case()
		var v: Variant = changes[k]
		match key:
			"id":
				id = String(v)
			"gears":
				gears = PackedFloat64Array(v)
			"torque":
				torque = (v as Array).duplicate(true)
			"substeps":
				substeps = int(v)
			_:
				if not (key in self):
					push_error("CarSpec: unknown field %s" % k)
					continue
				set(key, float(v))
	derive()


## The spec as a dictionary with the JS names (for data files and comparisons).
func to_dict() -> Dictionary:
	var d: Dictionary = {}
	for k: String in KEYS:
		var v: Variant = get(k.to_snake_case())
		if k == "gears":
			v = Array(gears)
		elif k == "torque":
			v = torque.duplicate(true)
		d[k] = v
	return d


## The constants derived from the spec (JS derived()).
func derive() -> void:
	# slip (tan of the slip angle) where the magic formula peaks: the same search as the JS,
	# with the same accumulating step (so it lands on the same grid point)
	var best: float = 0.0
	var bx: float = 0.0
	var x: float = 0.001
	while x < 0.6:
		var f: float = pacejka(x)
		if f > best:
			best = f
			bx = x
		x += 0.0005
	wheelbase = cg_to_front + cg_to_rear
	core = half_length - radius
	peak_slip = bx
	pac_slope0 = pac_b * pac_c
	peak_steer = atan(bx * steer_slip_gain)
	torque_rpm.resize(torque.size())
	torque_nm.resize(torque.size())
	for k in torque.size():
		var p: Array = torque[k]
		torque_rpm[k] = float(p[0])
		torque_nm[k] = float(p[1])
	derived = true


## Magic formula force ratio at slip x.
func pacejka(x: float) -> float:
	var b: float = pac_b * x
	return sin(pac_c * atan(b - pac_e * (b - atan(b))))


## Engine torque (N m) at `rpm` from the torque curve.
func engine_torque(rpm: float) -> float:
	var n: int = torque_rpm.size()
	if rpm <= torque_rpm[0]:
		return torque_nm[0]
	for k in range(1, n):
		if rpm <= torque_rpm[k]:
			var a0: float = torque_rpm[k - 1]
			var a1: float = torque_nm[k - 1]
			return a1 + ((torque_nm[k] - a1) * (rpm - a0)) / (torque_rpm[k] - a0)
	return torque_nm[n - 1]
