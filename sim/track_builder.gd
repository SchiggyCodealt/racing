class_name TrackBuilder
extends RefCounted
## track_builder.gd (port of web/src/tracks/trackBuilder.js)
## ------------------------------------------------------------------
## Turns a track definition (data/tracks.json: control points
## [x, z, height, bankDeg?, widthM?]) into a BuiltTrack: a dense list of
## centre-line samples spaced ~SAMPLE_SPACING metres apart, with everything
## physics, AI and rendering need (tangents, normals, per-sample width,
## banking, checkpoints, kickers, wall grid).
##
## How each attribute is made:
##   - plan (x/z): a centripetal Catmull-Rom spline through the control
##     points on the ground plane (the same maths as three.js
##     CatmullRomCurve3, ported below). Samples are evenly spaced in plan
##     distance, so (py[i+1] - py[i]) / seg_len is exactly the road grade.
##   - height: a monotone cubic (PCHIP) through the control-point heights over
##     plan distance: no overshoot, kicker lips stay sharp.
##   - width and bank magnitude: the same monotone cubic (5th element of a
##     point = road width there, falls back to def.width).
##   - bank sign: from the curvature, so a positive bank angle always leans
##     into the corner (+ = left-hand turn, raises the right edge).
##
## Start and finish: on a circuit the start/finish line is at sample 0 and
## the cars start 12 m past it (start_idx 6). A sprint's road runs on beyond
## both lines: def.startAt is where the cars start (metres from the beginning
## of the road, default 6), with the START line 12 m behind them (start_line),
## and def.runOff is the road left after the FINISH line (default 10 m).
##
## Use Tracks.build(id) (sim/tracks.gd) for the built-in tracks; this is the
## builder behind it and works on any definition Dictionary.

const SAMPLE_SPACING: float = 2.0 # metres between centre-line samples
## Road grades (rise/run) steeper than this only appear on kicker ramps and their landings.
const KICKER_GRADE: float = 0.12
const DEG: float = PI / 180.0
const DIV: int = 48 # arc-length table resolution per spline piece


static func _pt(p: Array, k: int, fallback: float) -> float:
	return float(p[k]) if p.size() > k and p[k] != null else fallback


## Build a track. Pure data.
static func build_track(def: Dictionary) -> BuiltTrack:
	var closed: bool = String(def.get("type", "circuit")) != "sprint"
	var pts: Array = def.points
	var n: int = pts.size()
	var n_seg: int = n if closed else n - 1 # spline pieces between control points
	var width: float = float(def.get("width", 14.0))

	# ---- plan: Catmull-Rom on the ground plane -----------------------------
	var cx: PackedFloat64Array = PackedFloat64Array()
	var cz: PackedFloat64Array = PackedFloat64Array()
	for p in pts:
		cx.append(float(p[0]))
		cz.append(float(p[1]))
	var curve := _CatmullRom.new(cx, cz, closed)
	var lengths: PackedFloat64Array = curve.get_lengths(n_seg * DIV) # cumulative plan length at t = j / (n_seg * DIV)
	var length: float = lengths[lengths.size() - 1]
	# plan distance of every control point (closed: s_ctrl[n] = length = point 0 again)
	var s_ctrl: PackedFloat64Array = PackedFloat64Array()
	s_ctrl.resize(n_seg + 1)
	for k in n_seg + 1:
		s_ctrl[k] = lengths[k * DIV]

	var N: int = maxi(16, JsMath.roundi(length / SAMPLE_SPACING)) # segments along the spline
	var count: int = N if closed else N + 1 # samples (closed: sample N == sample 0)
	var seg_len: float = length / N

	var t := BuiltTrack.new()
	for a: PackedFloat32Array in [t.px, t.py, t.pz, t.tx, t.tz, t.nx, t.nz, t.hw, t.bank]:
		a.resize(count)
	var px: PackedFloat32Array = t.px
	var py: PackedFloat32Array = t.py
	var pz: PackedFloat32Array = t.pz
	var hw: PackedFloat32Array = t.hw
	var bank_mag: PackedFloat32Array = PackedFloat32Array()
	bank_mag.resize(count)

	# height, bank magnitude and width: smooth monotone curves over plan distance
	var ys: PackedFloat64Array = PackedFloat64Array()
	var bs: PackedFloat64Array = PackedFloat64Array()
	var ws: PackedFloat64Array = PackedFloat64Array()
	for p in pts:
		ys.append(_pt(p, 2, 0.0))
		bs.append(absf(_pt(p, 3, 0.0)))
		ws.append(_pt(p, 4, width))
	var height := _Pchip.new(s_ctrl, ys, closed, length)
	var bank_at := _Pchip.new(s_ctrl, bs, closed, length)
	var width_at := _Pchip.new(s_ctrl, ws, closed, length)
	for i in count:
		var s: float = minf(i * seg_len, length)
		var u: float = curve.get_u_to_t_mapping(s / length)
		var v: PackedFloat64Array = curve.get_point(u)
		px[i] = v[0]
		pz[i] = v[1]
		py[i] = height.eval(s)
		bank_mag[i] = bank_at.eval(s) * DEG
		hw[i] = width_at.eval(s) / 2.0

	# Tangents (central difference) and left normals.
	var tx: PackedFloat32Array = t.tx
	var tz: PackedFloat32Array = t.tz
	var nx: PackedFloat32Array = t.nx
	var nz: PackedFloat32Array = t.nz
	for i in count:
		var a: int = posmod(i - 1, N) if closed else clampi(i - 1, 0, count - 1)
		var b: int = posmod(i + 1, N) if closed else clampi(i + 1, 0, count - 1)
		var dx: float = px[b] - px[a]
		var dz: float = pz[b] - pz[a]
		var l: float = JsMath.hypot2(dx, dz)
		if l == 0.0:
			l = 1.0
		tx[i] = dx / l
		tz[i] = dz / l
		nx[i] = tz[i]
		nz[i] = -tx[i]

	# Signed curvature (+ = left turn) -> the bank leans into the corner.
	# Corners tighter than ~400 m radius get the full bank angle given in the
	# data; it fades out towards straights.
	var bank: PackedFloat32Array = t.bank
	var w: int = 3
	for i in count:
		var a: int = i - w if closed else maxi(0, i - w)
		var b: int = i + w if closed else mini(count - 1, i + w)
		var wa: int = posmod(a, N) if closed else clampi(a, 0, count - 1)
		var wb: int = posmod(b, N) if closed else clampi(b, 0, count - 1)
		var d: float = atan2(tx[wb], tz[wb]) - atan2(tx[wa], tz[wa])
		d = atan2(sin(d), cos(d))
		var curvature: float = d / ((b - a) * seg_len) if b > a else 0.0
		bank[i] = bank_mag[i] * maxf(-1.0, minf(1.0, curvature * 400.0))
	_smooth(bank, 3, closed)

	# Lift the road where banking would push the low edge under the ground.
	# (The built-in tracks are designed so this is a no-op; it protects
	# hand-written tracks.)
	var deficit: PackedFloat32Array = PackedFloat32Array()
	deficit.resize(count)
	for i in count:
		deficit[i] = maxf(0.0, hw[i] * tan(absf(bank[i])) - py[i])
	_dilate(deficit, 20, closed)
	_smooth(deficit, 20, closed)
	for i in count:
		py[i] = py[i] + deficit[i]

	# Checkpoints are given as control-point indices; find the matching sample.
	var cps: Array[int] = []
	for c in def.get("checkpoints", []):
		var i: int = JsMath.roundi(s_ctrl[clampi(int(c), 0, n_seg)] / seg_len)
		cps.append(i % N if closed else clampi(i, 0, count - 1))
	cps.sort()

	t.def = def
	t.id = String(def.get("id", ""))
	t.name = String(def.get("name", ""))
	t.theme = String(def.get("theme", "meadow"))
	t.closed = closed
	t.laps = int(def.get("laps", 3)) if closed else 1
	t.N = N
	t.count = count
	t.seg_len = seg_len
	t.length = length
	t.seg_count = N if closed else count - 1
	t.cp_samples = PackedInt32Array(cps)
	# see "Start and finish" above
	t.start_idx = 6 if closed else maxi(3, JsMath.roundi(float(def.get("startAt", 6.0)) / seg_len))
	t.finish_idx = 0 if closed else mini(count - 6, count - 1 - JsMath.roundi(float(def.get("runOff", 10.0)) / seg_len))
	t.start_line = 0 if closed else maxi(0, t.start_idx - 6)
	t.kickers = find_kickers(t)
	t.grid = Collision.build_wall_grid(t)
	return t


## Gates are every line the car must cross, in order, for a whole race: each
## checkpoint of each lap, then the finish line. Positions are given in
## "unwrapped progress" (sample units that keep counting up across laps).
## Each gate: {prog, sample, kind ("cp" | "lap" | "finish"), lap, cp}.
static func get_gates(track: BuiltTrack, laps: int) -> Array[Dictionary]:
	if track.gate_cache.has(laps):
		return track.gate_cache[laps]
	var gates: Array[Dictionary] = []
	var ncp: int = track.cp_samples.size()
	if track.closed:
		for lap in laps:
			for k in ncp:
				var s: int = track.cp_samples[k]
				gates.append({prog = lap * track.N + s, sample = s, kind = "cp", lap = lap, cp = k})
			gates.append({prog = (lap + 1) * track.N, sample = 0, kind = "finish" if lap == laps - 1 else "lap", lap = lap, cp = ncp})
	else:
		for k in ncp:
			var s: int = track.cp_samples[k]
			gates.append({prog = s, sample = s, kind = "cp", lap = 0, cp = k})
		gates.append({prog = track.finish_idx, sample = track.finish_idx, kind = "finish", lap = 0, cp = ncp})
	track.gate_cache[laps] = gates
	return gates


## Race distance in metres for a given number of laps.
static func race_length(track: BuiltTrack, laps: int) -> float:
	return laps * track.length if track.closed else (track.finish_idx - track.start_idx) * track.seg_len


## Find kicker ramps: runs of samples climbing steeper than KICKER_GRADE.
## Returns [{foot, lip, land, height}] (sample indices, in track order):
##   foot    where the ramp starts to rise
##   lip     the crest the car takes off from
##   land    the bottom of the landing slope after the lip
##   height  lip height above the foot (m)
static func find_kickers(track: BuiltTrack) -> Array[Dictionary]:
	var closed: bool = track.closed
	var count: int = track.count
	var N: int = track.N
	var py: PackedFloat32Array = track.py
	var seg_len: float = track.seg_len
	var n: int = N if closed else count
	var norm := func(j: int) -> int: return posmod(j, N) if closed else clampi(j, 0, count - 1)
	var at := func(i: int) -> float: return py[norm.call(i)]
	var grade := func(i: int) -> float: return (float(at.call(i + 1)) - float(at.call(i - 1))) / (2.0 * seg_len)
	# start scanning at a sample that is not on a ramp (closed tracks wrap)
	var i0: int = 0
	if closed:
		while i0 < n and float(grade.call(i0)) > KICKER_GRADE:
			i0 += 1
	var out: Array[Dictionary] = []
	var k: int = 0
	while k < n:
		var i: int = i0 + k
		if float(grade.call(i)) <= KICKER_GRADE or (k > 0 and float(grade.call(i - 1)) > KICKER_GRADE):
			k += 1
			continue
		var foot: int = i
		while foot > i - 200 and (closed or foot > 0) and float(grade.call(foot - 1)) > 0.005:
			foot -= 1
		var lip: int = i
		while lip < i + 400 and (closed or lip < count - 1) and float(at.call(lip + 1)) > float(at.call(lip)):
			lip += 1
		var land: int = lip
		while land < lip + 400 and (closed or land < count - 1) and float(at.call(land + 1)) < float(at.call(land)) - 1e-4:
			land += 1
		out.append({foot = norm.call(foot), lip = norm.call(lip), land = norm.call(land), height = float(at.call(lip)) - float(at.call(foot))})
		k += maxi(0, lip - i)
		k += 1
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.lip) < int(b.lip))
	return out


# ---- helpers -------------------------------------------------------------------

## Box filter of radius r (src copied first, as float32 like the JS Float32Array.from).
static func _smooth(a: PackedFloat32Array, r: int, closed: bool) -> void:
	var n: int = a.size()
	var src: PackedFloat32Array = a.duplicate()
	for i in n:
		var s: float = 0.0
		var c: int = 0
		for k in range(-r, r + 1):
			var j: int = i + k
			if closed:
				j = posmod(j, n)
			elif j < 0 or j >= n:
				continue
			s += src[j]
			c += 1
		a[i] = s / c


static func _dilate(a: PackedFloat32Array, r: int, closed: bool) -> void:
	var n: int = a.size()
	var src: PackedFloat32Array = a.duplicate()
	for i in n:
		var mx: float = 0.0
		for k in range(-r, r + 1):
			var j: int = i + k
			if closed:
				j = posmod(j, n)
			elif j < 0 or j >= n:
				continue
			if src[j] > mx:
				mx = src[j]
		a[i] = mx


## Monotone piecewise-cubic interpolation (PCHIP, Fritsch-Carlson) of ys over
## the knots xs. closed: periodic, the knot after the last one is the first
## one again at x + period. Fastest when evaluated with increasing x.
class _Pchip:
	var xs: PackedFloat64Array
	var ys: PackedFloat64Array
	var closed: bool
	var period: float
	var n: int
	var m: PackedFloat64Array = PackedFloat64Array()
	var pieces: int
	var k: int = 0

	func _init(xs_: PackedFloat64Array, ys_: PackedFloat64Array, closed_: bool, period_: float) -> void:
		xs = xs_
		ys = ys_
		closed = closed_
		period = period_
		n = ys.size()
		m.resize(n)
		for j in n:
			if not closed and (j == 0 or j == n - 1):
				m[j] = 0.0 if n < 2 else (_secant(0) if j == 0 else _secant(n - 2))
				continue
			var d0: float = _secant(j - 1)
			var d1: float = _secant(j)
			if d0 * d1 <= 0.0:
				m[j] = 0.0
				continue
			var h0: float = X(j) - X(j - 1)
			var h1: float = X(j + 1) - X(j)
			var w1: float = 2.0 * h1 + h0
			var w2: float = h1 + 2.0 * h0
			m[j] = (w1 + w2) / (w1 / d0 + w2 / d1)
		pieces = n if closed else n - 1

	func X(j: int) -> float:
		if closed:
			return xs[posmod(j, n)] + floorf(float(j) / n) * period
		return xs[clampi(j, 0, n - 1)]

	func Y(j: int) -> float:
		if closed:
			return ys[posmod(j, n)]
		return ys[clampi(j, 0, n - 1)]

	func _secant(j: int) -> float:
		var h: float = X(j + 1) - X(j)
		return (Y(j + 1) - Y(j)) / h if h > 1e-9 else 0.0

	func eval(x: float) -> float:
		if pieces < 1:
			return Y(0)
		if x < X(k):
			k = 0
		while k < pieces - 1 and x >= X(k + 1):
			k += 1
		var x0: float = X(k)
		var h: float = X(k + 1) - x0
		if h <= 1e-9:
			return Y(k)
		var t: float = maxf(0.0, minf(1.0, (x - x0) / h))
		var t2: float = t * t
		var t3: float = t2 * t
		return (2.0 * t3 - 3.0 * t2 + 1.0) * Y(k) + (t3 - 2.0 * t2 + t) * h * m[k % n] + \
			(-2.0 * t3 + 3.0 * t2) * Y(k + 1) + (t3 - t2) * h * m[(k + 1) % n]


## three.js CatmullRomCurve3 ('centripetal') on the x/z plane, with its
## arc-length table (Curve.getLengths / getUtoTmapping), step for step.
class _CatmullRom:
	var x: PackedFloat64Array
	var z: PackedFloat64Array
	var closed: bool
	var lengths: PackedFloat64Array = PackedFloat64Array()

	func _init(x_: PackedFloat64Array, z_: PackedFloat64Array, closed_: bool) -> void:
		x = x_
		z = z_
		closed = closed_

	## The point at curve parameter t (0..1): [x, z].
	func get_point(t: float) -> PackedFloat64Array:
		var r: int = x.size()
		var s: float = (r - (0 if closed else 1)) * t
		var l: int = int(floor(s))
		var c: float = s - l
		if closed:
			l += 0 if l > 0 else (int(floor(absf(l) / r)) + 1) * r
		elif c == 0.0 and l == r - 1:
			l = r - 2
			c = 1.0
		var ax: float
		var az: float
		if closed or l > 0:
			ax = x[(l - 1) % r]
			az = z[(l - 1) % r]
		else:
			ax = (x[0] - x[1]) + x[0]
			az = (z[0] - z[1]) + z[0]
		var hx: float = x[l % r]
		var hz: float = z[l % r]
		var ux: float = x[(l + 1) % r]
		var uz: float = z[(l + 1) % r]
		var ox: float
		var oz: float
		if closed or l + 2 < r:
			ox = x[(l + 2) % r]
			oz = z[(l + 2) % r]
		else:
			ox = (x[r - 1] - x[r - 2]) + x[r - 1]
			oz = (z[r - 1] - z[r - 2]) + z[r - 1]
		# centripetal: knot spacing = distance^0.5 (pow of the squared distance, 0.25)
		var dt0: float = pow(_d2(ax, az, hx, hz), 0.25)
		var dt1: float = pow(_d2(hx, hz, ux, uz), 0.25)
		var dt2: float = pow(_d2(ux, uz, ox, oz), 0.25)
		if dt1 < 1e-4:
			dt1 = 1.0
		if dt0 < 1e-4:
			dt0 = dt1
		if dt2 < 1e-4:
			dt2 = dt1
		return PackedFloat64Array([_calc(ax, hx, ux, ox, dt0, dt1, dt2, c), _calc(az, hz, uz, oz, dt0, dt1, dt2, c)])

	## (x, 0, z) distance squared, as Vector3.distanceToSquared adds it up
	static func _d2(ax: float, az: float, bx: float, bz: float) -> float:
		var e: float = ax - bx
		var i: float = az - bz
		return e * e + 0.0 + i * i

	## CubicPoly.initNonuniformCatmullRom + calc
	static func _calc(x0: float, x1: float, x2: float, x3: float, dt0: float, dt1: float, dt2: float, t: float) -> float:
		var t1: float = (x1 - x0) / dt0 - (x2 - x0) / (dt0 + dt1) + (x2 - x1) / dt1
		var t2: float = (x2 - x1) / dt1 - (x3 - x1) / (dt1 + dt2) + (x3 - x2) / dt2
		t1 *= dt1
		t2 *= dt1
		var c0: float = x1
		var c1: float = t1
		var c2: float = -3.0 * x1 + 3.0 * x2 - 2.0 * t1 - t2
		var c3: float = 2.0 * x1 - 2.0 * x2 + t1 + t2
		var tt: float = t * t
		return c0 + c1 * t + c2 * tt + c3 * (tt * t)

	## Cumulative arc lengths at t = j / divisions.
	func get_lengths(divisions: int) -> PackedFloat64Array:
		lengths = PackedFloat64Array()
		lengths.resize(divisions + 1)
		var last: PackedFloat64Array = get_point(0.0)
		var sum: float = 0.0
		lengths[0] = 0.0
		for j in range(1, divisions + 1):
			var p: PackedFloat64Array = get_point(float(j) / divisions)
			var e: float = p[0] - last[0]
			var i: float = p[1] - last[1]
			sum += sqrt(e * e + 0.0 + i * i)
			lengths[j] = sum
			last = p
		return lengths

	## Curve parameter t at arc-length fraction u (Curve.getUtoTmapping).
	func get_u_to_t_mapping(u: float) -> float:
		var n: PackedFloat64Array = lengths
		var r: int = n.size()
		var target: float = u * n[r - 1]
		var lo: int = 0
		var hi: int = r - 1
		var i: int = 0
		while lo <= hi:
			i = lo + (hi - lo) / 2
			var cmp: float = n[i] - target
			if cmp < 0.0:
				lo = i + 1
			elif cmp > 0.0:
				hi = i - 1
			else:
				hi = i
				break
		i = hi
		if n[i] == target:
			return float(i) / (r - 1)
		var before: float = n[i]
		return (i + (target - before) / (n[i + 1] - before)) / (r - 1)
