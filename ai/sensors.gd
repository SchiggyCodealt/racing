class_name Sensors
extends RefCounted
## sensors.gd: a port of web/src/ai/sensors.js.
## ------------------------------------------------------------------
## What the AI "sees", and the glue that turns network outputs into car
## controls. v2 inputs (18, all within -1..1):
##
##   0-8   distance rays fanning out from the car's nose (-90°..+90°),
##         distance / SENSOR_RANGE (1 = no wall within 100 m)
##   9     forward speed / the car's top speed (CarSpec.max_speed: 1 = flat out in any car;
##         the Racer's is 77 m/s, CAR.maxSpeed in the JS, so Racer inputs are unchanged)
##   10    side slip: sideways speed (+ = sliding to the left) / 8 m/s
##   11    yaw rate (+ = turning left) / 1.5 rad/s
##   12    aim near: direction to the point on the centre line
##         L = 10 m + 0.6 s × speed ahead (+ = left) / 90°
##   13    aim far: direction to the centre line 2.5 L ahead / 180°
##   14    road turn: how much the road turns between 25 and 60 m ahead
##         (+ = left), tanh(angle / 1.6 rad)
##   15-17 corner margin: (corner speed - car speed) / 20 m/s for the
##         tightest bend 0-50 m, 50-110 m and 110-200 m ahead, where the
##         corner speed is sqrt(CORNER_GRIP × radius) (~55 km/h for a 16 m
##         hairpin), at most the car's top speed. Negative = faster than that
##         corner allows.
##
## Other cars (v6.2): the speed input and the corner speed cap use the driven
## car's own top speed (CarSpec.max_speed), so a network sees the same range
## of numbers whatever it drives: about 1 is flat out, and on a straight the
## corner margins are (top speed - speed) / 20 m/s, about 0 at top speed. (With
## the Racer's 77 m/s for every car, the Vortex's speed input would reach 1.18
## and its margins would read "too fast for the next corner" on every straight
## above 277 km/h.) CORNER_GRIP stays the same for every car: the cars' cornering
## grip is within 13 % of the Racer's (the Thunder's in slow corners is the
## lowest), which moves a corner speed by at most about 6 % (under 1 m/s in a
## hairpin, about 0.05 of the input's range), and the network learns its own
## braking points anyway. The Racer's top speed is SPEED_SCALE, so its inputs
## are bit for bit what they always were and SENSOR_VERSION stays 2: networks
## saved before (and by the browser version) drive exactly as before.
##
## (The JS header explains why these inputs.) Everything except the rays is O(1)
## per car: the per-track data (headings and a range-maximum table of the road
## curvature) is computed once per track (track_headings).
##
## The driver is left/right symmetric by construction (drive_network): the
## network also sees the mirrored situation and the answers are combined.
##
## Numbers: inputs are stored as 32-bit floats (the JS Float32Arrays), the
## network outputs too, so a network drives the same as in the browser (up to
## the C library's sin/cos/atan2/tanh, which differ from V8's in the last bit
## for some arguments). native/src/fleet_sim.cpp mirrors this file in C++.
##
## Use (one AI car, Watch the AI / the AI ghost):
##   var driver := Sensors.AIDriver.new(net)
##   var ctrl := driver.drive(track, car)      # every physics step, before car.step()
##   driver.rays                               # ray distances (m) for SensorRays

## Ray angles in degrees relative to the car's heading (+ = left).
const SENSOR_ANGLES: PackedFloat64Array = [90, 60, 35, 15, 0, -15, -35, -60, -90]
## metres
const SENSOR_RANGE: float = 100.0
## The Racer's top speed (max_speed, CAR.maxSpeed in the JS): what the speed input divides
## by (and the corner speed cap) for the Racer. Every car uses its own: speed_scale(spec).
const SPEED_SCALE: float = 77.0
## Aim points: near = AIM_BASE + AIM_TIME × speed metres ahead, far = AIM_FAR × that.
const AIM_BASE: float = 10.0
const AIM_TIME: float = 0.6
const AIM_FAR: float = 2.5
## Stretch of road ahead [from, to] in metres whose total turn is an input.
const TURN_WINDOW: PackedFloat64Array = [25, 60]
## rad: input = tanh(turn / TURN_SCALE)
const TURN_SCALE: float = 1.6
## Stretches of road ahead [from, to] in metres: margin to the tightest bend's speed
## (the JS CORNER_WINDOWS [[0, 50], [50, 110], [110, 200]] as two lists: a constant
## Array of PackedFloat64Arrays does not read back reliably in Godot 4.7).
const CORNER_FROM: PackedFloat64Array = [0, 50, 110]
const CORNER_TO: PackedFloat64Array = [50, 110, 200]
## m/s², lateral grip used for the corner speed sqrt(grip × radius)
const CORNER_GRIP: float = 14.5
## m/s
const MARGIN_SCALE: float = 20.0
## samples either side used to measure the road curvature (±6 m)
const CURV_HALF: int = 3
const NR: int = 9

const INPUT_LABELS: PackedStringArray = [
	"ray left 90°", "ray left 60°", "ray left 35°", "ray left 15°", "ray front",
	"ray right 15°", "ray right 35°", "ray right 60°", "ray right 90°",
	"speed", "side slip", "yaw rate", "aim near", "aim far", "road turn 25-60 m",
	"corner margin 0-50 m", "corner margin 50-110 m", "corner margin 110-200 m",
]
const OUTPUT_LABELS: PackedStringArray = ["steer", "throttle"]
const INPUT_COUNT: int = 18
const OUTPUT_COUNT: int = 2
## Bumped whenever the inputs change meaning, so old network files are rejected clearly.
const SENSOR_VERSION: int = 2
## Inputs that change sign in a mirror image (left <-> right); the rays swap order.
const MIRROR_NEGATE: PackedInt32Array = [NR + 1, NR + 2, NR + 3, NR + 4, NR + 5]

static var _ray_cos: PackedFloat64Array = _ray_table(true)
static var _ray_sin: PackedFloat64Array = _ray_table(false)
static var _head_mutex: Mutex = Mutex.new()


## What the speed input divides by (and the corner speeds' cap) for a car: its top speed on
## the flat (CarSpec.max_speed; the Racer's is SPEED_SCALE, 77 m/s). See the header.
static func speed_scale(spec: CarSpec) -> float:
	return spec.max_speed


static func _ray_table(want_cos: bool) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for a in SENSOR_ANGLES:
		var r: float = (a * PI) / 180.0
		out.append(cos(r) if want_cos else sin(r))
	return out


## Per-track data for the road inputs (JS trackHeadings), computed once and kept on the
## track (meta "ai_head"):
##   theta   unwrapped road heading at every sample (rad, + = left turn)
##   total   total turn over one lap (closed tracks, ±2π)
##   sparse  range-maximum table of the road curvature (1/m) for O(1) queries;
##           closed tracks are laid out twice so a range can run over the line
class Headings:
	var theta: PackedFloat64Array = PackedFloat64Array()
	var total: float = 0.0
	var n: int = 0
	var closed: bool = false
	var sparse: Array[PackedFloat32Array] = []
	var len: int = 0


static func track_headings(track: BuiltTrack) -> Headings:
	_head_mutex.lock()
	if track.has_meta("ai_head"):
		var cached: Headings = track.get_meta("ai_head")
		_head_mutex.unlock()
		return cached
	var count: int = track.count
	var closed: bool = track.closed
	var tx: PackedFloat32Array = track.tx
	var tz: PackedFloat32Array = track.tz
	var seg_len: float = track.seg_len
	var n: int = track.N if closed else count
	var theta := PackedFloat64Array()
	theta.resize(n)
	var prev: float = atan2(tx[0], tz[0])
	theta[0] = prev
	for i in range(1, n):
		var a: float = atan2(tx[i], tz[i])
		theta[i] = theta[i - 1] + wrap_angle(a - prev)
		prev = a
	var total: float = theta[n - 1] + wrap_angle(atan2(tx[0], tz[0]) - prev) - theta[0] if closed else 0.0
	var h := Headings.new()
	h.theta = theta
	h.total = total
	h.n = n
	h.closed = closed
	var len: int = 2 * n if closed else n
	var curv := PackedFloat32Array()
	curv.resize(len)
	for i in len:
		var a: int = i - CURV_HALF if closed else maxi(0, i - CURV_HALF)
		var b: int = i + CURV_HALF if closed else mini(n - 1, i + CURV_HALF)
		curv[i] = absf(heading_at(h, b) - heading_at(h, a)) / ((b - a) * seg_len) if b > a else 0.0
	var levels: Array[PackedFloat32Array] = [curv]
	var w: int = 1
	while 2 * w <= len:
		var p: PackedFloat32Array = levels[levels.size() - 1]
		var q := PackedFloat32Array()
		q.resize(len - 2 * w + 1)
		for i in q.size():
			q[i] = p[i] if p[i] > p[i + w] else p[i + w]
		levels.append(q)
		w *= 2
	h.sparse = levels
	h.len = len
	track.set_meta("ai_head", h)
	_head_mutex.unlock()
	return h


## Unwrapped road heading at a fractional sample position s (may run past the lap end).
static func heading_at(h: Headings, s: float) -> float:
	var theta: PackedFloat64Array = h.theta
	var n: int = h.n
	if h.closed:
		var lap: float = floor(s / n)
		var r: float = s - lap * n
		var i: int = mini(n - 1, int(floor(r)))
		var t: float = r - i
		var a: float = theta[i]
		var b: float = theta[i + 1] if i + 1 < n else theta[0] + h.total
		return a + (b - a) * t + lap * h.total
	if s <= 0.0:
		return theta[0]
	if s >= n - 1:
		return theta[n - 1]
	var i2: int = int(floor(s))
	var t2: float = s - i2
	return theta[i2] + (theta[i2 + 1] - theta[i2]) * t2


## Largest road curvature between samples l and r (integers, r >= l; may run past the lap end on closed tracks).
static func sharpest(h: Headings, l: int, r: int) -> float:
	if h.closed:
		var span: int = mini(r - l, h.n - 1)
		l = posmod(l, h.n)
		r = l + span
	else:
		if l < 0:
			l = 0
		if r > h.len - 1:
			r = h.len - 1
		if r < l:
			return 0.0
	# k = floor(log2(r - l + 1)) (JS 31 - Math.clz32(r - l + 1))
	var k: int = 0
	var v: int = r - l + 1
	while v > 1:
		v >>= 1
		k += 1
	var t: PackedFloat32Array = h.sparse[k]
	var a: float = t[l]
	var b: float = t[r - (1 << k) + 1]
	return a if a > b else b


## Angle (rad, + = left) from the car's heading to the centre line at sample position s.
static func bearing(track: BuiltTrack, car: Car, s: float, fx: float, fz: float) -> float:
	var i: int
	var t: float
	if track.closed:
		var n: int = track.N
		s = fposmod_js(s, n)
		i = mini(n - 1, int(floor(s)))
		t = s - i
	elif s >= track.count - 1:
		i = track.count - 2
		t = 1.0
	elif s <= 0.0:
		i = 0
		t = 0.0
	else:
		i = int(floor(s))
		t = s - i
	var j: int = (i + 1) % track.N if track.closed else i + 1
	var px: PackedFloat32Array = track.px
	var pz: PackedFloat32Array = track.pz
	var x: float = px[i] + (px[j] - px[i]) * t - car.x
	var z: float = pz[i] + (pz[j] - pz[i]) * t - car.z
	return atan2(x * fz - z * fx, x * fx + z * fz)


## JS ((s % n) + n) % n for a float s and an int n (fmod keeps the sign like JS %).
static func fposmod_js(s: float, n: int) -> float:
	return fmod(fmod(s, n) + n, n)


## Fill `inputs` (INPUT_COUNT 32-bit floats) for this car; `rays` (when not null, 9 floats)
## receives the raw ray distances in metres. (The JS also takes the race; v2 ignores it.)
static func sense(track: BuiltTrack, car: Car, inputs: PackedFloat32Array, rays: Variant = null) -> PackedFloat32Array:
	var fx: float = sin(car.yaw)
	var fz: float = cos(car.yaw)
	var lx: float = fz
	var lz: float = -fx
	var ox: float = car.x + fx * 1.5
	var oz: float = car.z + fz * 1.5
	var grid: Collision.WallGrid = track.grid
	var ray_out: PackedFloat32Array = rays if rays != null else PackedFloat32Array()
	if rays != null:
		ray_out.resize(NR)
	for k in NR:
		var c: float = _ray_cos[k]
		var s: float = _ray_sin[k]
		var d: float = Collision.raycast(grid, ox, oz, fx * c + lx * s, fz * c + lz * s, SENSOR_RANGE)
		inputs[k] = d / SENSOR_RANGE
		if rays != null:
			ray_out[k] = d
	var u: float = car.forward_speed
	var top: float = car.spec.max_speed # speed_scale(car.spec), inlined
	inputs[NR] = u / top
	inputs[NR + 1] = clamp1(car.side_speed / 8.0) # side_speed: + = moving to the car's left
	inputs[NR + 2] = clamp1(car.yaw_rate / 1.5)

	# Where the road goes, and how fast the next corners can be taken.
	var h: Headings = track_headings(track)
	var s0: float = car.prog - car.laps * track.N if track.closed else car.prog # progress within the lap, samples
	var inv: float = 1.0 / track.seg_len
	var L: float = (AIM_BASE + AIM_TIME * (u if u > 0.0 else 0.0)) * inv
	inputs[NR + 3] = clamp1(bearing(track, car, s0 + L, fx, fz) / (PI / 2.0))
	inputs[NR + 4] = clamp1(bearing(track, car, s0 + AIM_FAR * L, fx, fz) / PI)
	var turn: float = heading_at(h, s0 + TURN_WINDOW[1] * inv) - heading_at(h, s0 + TURN_WINDOW[0] * inv)
	inputs[NR + 5] = tanh(turn / TURN_SCALE)
	var i0: int = JsMath.roundi(s0)
	for w in CORNER_FROM.size():
		var kappa: float = sharpest(h, i0 + JsMath.roundi(CORNER_FROM[w] * inv), i0 + JsMath.roundi(CORNER_TO[w] * inv))
		var vc: float = sqrt(CORNER_GRIP / kappa) if kappa > 1e-6 else top
		if vc > top:
			vc = top
		inputs[NR + 6 + w] = clamp1((vc - u) / MARGIN_SCALE)
	return inputs


static func clamp1(v: float) -> float:
	return 1.0 if v > 1.0 else (-1.0 if v < -1.0 else v)


static func wrap_angle(a: float) -> float:
	return atan2(sin(a), cos(a))


## The same situation seen in a mirror (left and right swapped): rays in reverse order,
## sideways quantities and directions negated, speeds and corner margins unchanged.
static func mirror_inputs(src: PackedFloat32Array, dst: PackedFloat32Array) -> PackedFloat32Array:
	for k in NR:
		dst[k] = src[NR - 1 - k]
	for k in range(NR, INPUT_COUNT):
		dst[k] = src[k]
	for k in MIRROR_NEGATE:
		dst[k] = -src[k]
	return dst


## Run a driver network and fill the car controls (JS driveNetwork). The network is
## evaluated on the inputs and on their mirror image, and the two answers are combined so
## the driver is exactly left/right symmetric: steer = (s - s') / 2, throttle = (t + t') / 2.
## The real (unmirrored) pass runs last, so net.acts holds its activations for the network
## diagram, with the combined controls written into the output layer (as 32-bit floats).
static func drive_network(net: NeuralNetwork, inputs: PackedFloat32Array, mirrored: PackedFloat32Array, ctrl: Car.Controls) -> Car.Controls:
	mirror_inputs(inputs, mirrored)
	var m: PackedFloat32Array = net.forward(mirrored)
	var ms: float = m[0]
	var mt: float = m[1]
	var out: PackedFloat32Array = net.forward(inputs)
	out[0] = 0.5 * (out[0] - ms)
	out[1] = 0.5 * (out[1] + mt)
	net.acts[net.acts.size() - 1] = out
	# outputsToControls: steer, throttle, no handbrake, no nitro (the AI never uses it)
	ctrl.steer = out[0]
	ctrl.throttle = out[1]
	ctrl.handbrake = false
	ctrl.nitro = 0.0
	return ctrl


## The speed governor of a slowed-down AI opponent (v6.5: the levels below Elite, see
## sim/opponents.gd): throttle at most CAP_GAIN × (cap - speed), so the car settles just under
## its cap on the straights and brakes gently when a downhill takes it over; harder braking
## from the network itself (a corner ahead) is kept.
const CAP_GAIN: float = 0.5


## Driver for a single AI car (Watch the AI, the AI ghost, the AI opponents).
## Call drive() once per physics step before car.step().
class AIDriver:
	var net: NeuralNetwork
	var inputs := PackedFloat32Array()
	var mirrored := PackedFloat32Array()
	## ray distances (m) of the last drive()
	var rays := PackedFloat32Array()
	var ctrl := Car.Controls.new()
	## Top speed (m/s) the driver keeps to (INF: none, the network as it is). Training never
	## sets it: only the AI opponents' skill levels (sim/opponents.gd) do.
	var speed_cap: float = INF

	func _init(p_net: NeuralNetwork, p_speed_cap: float = INF) -> void:
		net = p_net
		speed_cap = p_speed_cap
		inputs.resize(INPUT_COUNT)
		mirrored.resize(INPUT_COUNT)
		rays.resize(NR)

	func drive(track: BuiltTrack, car: Car, _race: Variant = null) -> Car.Controls:
		Sensors.sense(track, car, inputs, rays)
		Sensors.drive_network(net, inputs, mirrored, ctrl)
		if speed_cap < INF:
			ctrl.throttle = minf(ctrl.throttle, clampf((speed_cap - car.speed) * CAP_GAIN, -1.0, 1.0))
		return ctrl
