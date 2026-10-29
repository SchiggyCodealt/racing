class_name Turtle
extends RefCounted
## turtle.gd: helper for designing tracks (port of web/tools/turtle.mjs, v2).
## ------------------------------------------------------------------
## Writing control points by hand works for simple shapes, but it is much
## easier to "drive" a turtle around and let it write the points:
##
##   var t := Turtle.new({width = 14, y = 2})  # start at (0, 0), heading +z, 2 m up
##   t.S(200)                       # straight 200 m
##   t.L(90, 40, {bank = 12})       # left turn: 90°, radius 40 m, 12° banking
##   t.S(150, {y = 8})              # straight, climbing smoothly to 8 m
##   t.hairpin("R", 16)             # right 180° switchback, radius 16 m
##   t.width(10, 40)                # narrow the road to 10 m over the next 40 m
##   t.hill(240, 5)                 # a smooth 5 m crest over 240 m of straight
##   t.kicker({h = 5})              # kicker jump with a straight landing zone
##   var f := t.finish({closed = true})   # {points, checkpoints, ...}
##
## Every command returns the turtle, so programs chain like the JS ones:
## Turtle.new({...}).S(a, {y = 2}).width(20, 60).L(110, 100, {bank = 6}) ...
##
## Plan (x/z):
##   S(len, o)              straight of len metres.
##   L(deg, r, o) / R(...)  left / right turn of `deg` degrees, tightest radius
##                          r, with clothoid (spiral) entries and exits: the
##                          curvature ramps up over o.lt metres (default 0.8 r,
##                          clamped to 8-50 m). o.lt = 0 gives a plain arc.
##                          o.bank = banking in degrees (leans into the turn).
##   SL / SR(deg, r, o, gap) S-bend left-then-right / right-then-left.
##   hairpin(dir, r, o)     180° switchback, dir = "L" or "R".
## Height (y): keyframes along the distance driven, joined by a smooth
##   monotone curve (PCHIP, no overshoot). Every plan command accepts o.y =
##   height at its end. y(h), climb(len, y1), hill(len, dh) and
##   kicker({h, ramp, land, run, lead, drop}) as in the JS (see turtle.mjs).
## Width: width(w, len) changes the road width smoothly over len metres;
##   every plan command also accepts o.w (and o.wLen).
## Checkpoints: cp() at the current position; without any, finish() spaces
##   them evenly (cpSpacing, default 400 m), never on a jump.
## Surfaces (v6.3): surface("dirt") makes the road from here on dirt (any id of
##   sim/surfaces.gd), surface("asphalt") goes back; the road starts as asphalt.
##   finish() gives the stretches as [id, from, to] in control-point indices with
##   a fraction (the track definition's "surfaces"); they never move a point.
## Output: finish({closed, cpSpacing, startAt, runOff}) -> {points,
##   checkpoints, surfaces, length, closure, kickers, cpDistances, state} plus
##   profile_at(s) on the turtle for the designed height. points are
##   [x, z, height, bankDeg, widthM] (rounded like the JS: 1 cm, 0.1°, 0.1 m).
## close_loop(make, opts) solves two straight lengths so a circuit closes.
##
## Coordinates: forward(yaw) = (sin yaw, cos yaw), positive yaw = left turn.
## Arithmetic is the JS one step for step (same order of operations), so the
## generated points match web/src/tracks/trackData.js.

const DEG: float = PI / 180.0
const DS: float = 0.25 # integration step (m)

## current state: x, z, yaw, s (distance driven), y (height), width
var st: Dictionary = {}
var start: Dictionary = {}
# dense path every ~DS metres: distance, position, heading, curvature, bank magnitude
var P_s: PackedFloat64Array = PackedFloat64Array()
var P_x: PackedFloat64Array = PackedFloat64Array()
var P_z: PackedFloat64Array = PackedFloat64Array()
var P_yaw: PackedFloat64Array = PackedFloat64Array()
var P_k: PackedFloat64Array = PackedFloat64Array()
var P_b: PackedFloat64Array = PackedFloat64Array()
var h_keys: Array[Dictionary] = [] # {s, h, flat}
var kickers: Array[Dictionary] = [] # {s0, s1, foot, lip, landEnd, h, grade, landGrade, y0, drop, T1, T2}
var w_keys: Array[Dictionary] = [] # {s0, s1, w0, w1}
var cps: PackedFloat64Array = PackedFloat64Array()
var surf_keys: Array[Dictionary] = [] # {s, kind}: the road is `kind` from s on
var _height_closed: int = -1 # cached height function: -1 none, 0 open, 1 closed
var _base: _PchipKeys = null


func _init(opts: Dictionary = {}) -> void:
	st = {
		x = float(opts.get("x", 0.0)), z = float(opts.get("z", 0.0)), yaw = float(opts.get("yaw", 0.0)),
		s = 0.0, y = float(opts.get("y", 0.0)), width = float(opts.get("width", 14.0)),
	}
	start = st.duplicate()
	P_s.append(0.0); P_x.append(st.x); P_z.append(st.z); P_yaw.append(st.yaw); P_k.append(0.0); P_b.append(0.0)
	h_keys.append({s = 0.0, h = float(st.y), flat = false})


static func _clamp(v: float, a: float, b: float) -> float:
	return a if v < a else (b if v > b else v)


static func _smoothstep(f: float) -> float:
	f = _clamp(f, 0.0, 1.0)
	return f * f * (3.0 - 2.0 * f)


func _add_seg(len: float, k0: float, k1: float, b0: float, b1: float) -> void:
	if not (len > 1e-6):
		return
	_height_closed = -1
	var steps: int = maxi(1, int(ceil(len / DS)))
	var ds: float = len / steps
	var x: float = st.x
	var z: float = st.z
	var yaw: float = st.yaw
	var s: float = st.s
	for i in steps:
		var ka: float = k0 + ((k1 - k0) * i) / steps
		var kb: float = k0 + ((k1 - k0) * (i + 1)) / steps
		var dyaw: float = ((ka + kb) / 2.0) * ds
		var ym: float = yaw + dyaw / 2.0
		x += sin(ym) * ds
		z += cos(ym) * ds
		yaw += dyaw
		s += ds
		P_s.append(s); P_x.append(x); P_z.append(z); P_yaw.append(yaw)
		P_k.append((ka + kb) / 2.0); P_b.append(b0 + ((b1 - b0) * (i + 1)) / steps)
	st.x = x; st.z = z; st.yaw = yaw; st.s = s


func _key(h: float, flat: bool = false) -> void:
	_height_closed = -1
	var last: Dictionary = h_keys[h_keys.size() - 1]
	if absf(float(last.s) - float(st.s)) < 1e-6:
		last.h = h
		last.flat = bool(last.flat) or flat
	else:
		h_keys.append({s = float(st.s), h = h, flat = flat})
	st.y = h


func _after(o: Variant) -> Turtle:
	if o is Dictionary:
		var d: Dictionary = o
		if d.has("y") and d.y != null:
			_key(float(d.y))
		if d.has("w") and d.w != null:
			width(float(d.w), float(d.get("wLen", 40.0)))
	return self


func _turn(dir: float, deg: float, r: float, o: Variant) -> Turtle:
	var d: Dictionary = o if o is Dictionary else {}
	var rad: float = deg * DEG
	var k: float = dir / r
	var lt: float = float(d.lt) if d.has("lt") else _clamp(0.8 * r, 8.0, 50.0)
	lt = minf(lt, r * rad)
	var bank: float = float(d.get("bank", 0.0))
	_add_seg(lt, 0.0, k, 0.0, bank)
	_add_seg(r * rad - lt, k, k, bank, bank)
	_add_seg(lt, k, 0.0, bank, 0.0)
	return _after(d)


## Straight of `len` metres. o = {y, w}.
func S(len: float, o: Variant = null) -> Turtle:
	_add_seg(len, 0.0, 0.0, 0.0, 0.0)
	return _after(o)


## Left turn: `deg` degrees, tightest radius r. o = {bank, y, lt, w}.
func L(deg: float, r: float, o: Variant = null) -> Turtle:
	return _turn(1.0, deg, r, o)


## Right turn.
func R(deg: float, r: float, o: Variant = null) -> Turtle:
	return _turn(-1.0, deg, r, o)


## The options of the first half of an S-bend: o without its end height and width.
static func _first_half(o: Dictionary) -> Dictionary:
	var d: Dictionary = o.duplicate()
	d.erase("y")
	d.erase("w")
	return d


## S-bend left then right (each `deg`), with `gap` m of straight between.
func SL(deg: float, r: float, o: Dictionary = {}, gap: float = 0.0) -> Turtle:
	_turn(1.0, deg, r, _first_half(o))
	if gap != 0.0:
		_add_seg(gap, 0.0, 0.0, 0.0, 0.0)
	return _turn(-1.0, deg, r, o)


## S-bend right then left.
func SR(deg: float, r: float, o: Dictionary = {}, gap: float = 0.0) -> Turtle:
	_turn(-1.0, deg, r, _first_half(o))
	if gap != 0.0:
		_add_seg(gap, 0.0, 0.0, 0.0, 0.0)
	return _turn(1.0, deg, r, o)


## 180° switchback, dir "L" or "R".
func hairpin(dir: String, r: float, o: Dictionary = {}) -> Turtle:
	return _turn(1.0 if dir == "L" else -1.0, 180.0, r, o)


## Height keyframe at the current position (no argument: hold the current height up to here).
func y(h: Variant = null) -> Turtle:
	_key(float(st.y) if h == null else float(h))
	return self


## Straight whose height changes smoothly from the current height to y1 (flat before and after).
func climb(len: float, y1: float, o: Dictionary = {}) -> Turtle:
	_key(float(st.y))
	_add_seg(len, 0.0, 0.0, 0.0, 0.0)
	_key(y1)
	var d: Dictionary = o.duplicate()
	d.erase("y")
	return _after(d)


## Straight with a smooth crest (dh > 0) or dip (dh < 0) in the middle; o.y = end height.
func hill(len: float, dh: float, o: Dictionary = {}) -> Turtle:
	var y0: float = st.y
	_key(y0)
	_add_seg(len / 2.0, 0.0, 0.0, 0.0, 0.0)
	_key(y0 + dh)
	_add_seg(len / 2.0, 0.0, 0.0, 0.0, 0.0)
	_key(float(o.get("y", y0)))
	return self


## Kicker jump on a straight (see the header).
func kicker(o: Dictionary = {}) -> Turtle:
	var h: float = float(o.get("h", 5.0))
	var ramp: float = float(o.get("ramp", 26.0))
	var land: float = float(o.get("land", 45.0))
	var run: float = float(o.get("run", 125.0))
	var lead: float = float(o.get("lead", 20.0))
	var drop: float = float(o.get("drop", 0.0))
	var y0: float = st.y
	_key(y0, true)
	var s0: float = st.s
	var T1: float = 10.0 # curved foot of the ramp
	var T2: float = 14.0 # bottom of the landing
	ramp = maxf(ramp, h / 0.22 + T1 / 2.0) # ramp grade <= 22 %
	land = maxf(land, (h + drop) / 0.13 + T2 / 2.0) # landing slope <= 13 %
	run = maxf(run, 170.0 - land) # >= 170 m of straight after the lip
	var g: float = h / (ramp - T1 / 2.0) # ramp grade
	var gd: float = (h + drop) / (land - T2 / 2.0) # landing grade
	var foot: float = s0 + lead
	var lip: float = foot + ramp
	var land_end: float = lip + land
	var s1: float = land_end + run
	_add_seg(s1 - s0, 0.0, 0.0, 0.0, 0.0)
	kickers.append({s0 = s0, s1 = s1, foot = foot, lip = lip, landEnd = land_end, h = h, grade = g, landGrade = gd,
		y0 = y0, drop = drop, T1 = T1, T2 = T2})
	_key(y0 - drop, true)
	return self


## A kicker's height profile at s (the JS closure `fn`).
static func _kicker_fn(k: Dictionary, s: float) -> float:
	var y0: float = k.y0
	var foot: float = k.foot
	var lip: float = k.lip
	var land_end: float = k.landEnd
	var g: float = k.grade
	var gd: float = k.landGrade
	var T1: float = k.T1
	var T2: float = k.T2
	if s <= foot:
		return y0
	if s <= foot + T1:
		var x: float = s - foot
		return y0 + (g * x * x) / (2.0 * T1)
	if s <= lip:
		return y0 + (g * T1) / 2.0 + g * (s - foot - T1)
	if s <= land_end - T2:
		return y0 + float(k.h) - gd * (s - lip)
	if s <= land_end:
		var x2: float = land_end - s
		return y0 - float(k.drop) + (gd * x2 * x2) / (2.0 * T2)
	return y0 - float(k.drop)


## Change the road width to w metres over the next len metres.
func width(w: float, len: float = 40.0) -> Turtle:
	w_keys.append({s0 = float(st.s), s1 = float(st.s) + len, w0 = float(st.width), w1 = w})
	st.width = w
	return self


## Checkpoint at the current position.
func cp() -> Turtle:
	cps.append(float(st.s))
	return self


## The road surface from the current position on (an id of sim/surfaces.gd: "asphalt", "dirt", "snow").
func surface(kind: String) -> Turtle:
	if not surf_keys.is_empty() and absf(float(surf_keys[surf_keys.size() - 1].s) - float(st.s)) < 1e-6:
		surf_keys[surf_keys.size() - 1].kind = kind
	else:
		surf_keys.append({s = float(st.s), kind = kind})
	return self


## Height of the designed profile at distance s (closed: as a circuit).
func profile_at(s: float, closed: bool) -> float:
	_prepare_height(closed)
	for k in kickers:
		if s >= float(k.s0) and s <= float(k.s1):
			return _kicker_fn(k, s)
	return _base.eval(s)


func _prepare_height(closed: bool) -> void:
	var c: int = 1 if closed else 0
	if _height_closed == c:
		return
	var keys: Array[Dictionary] = h_keys.duplicate()
	if closed and keys.size() > 1 and absf(float(keys[keys.size() - 1].s) - float(st.s)) < 1e-6:
		keys.pop_back()
	_base = _PchipKeys.new(keys, closed, st.s)
	_height_closed = c


func finish(opts: Dictionary = {}) -> Dictionary:
	var closed: bool = opts.get("closed", true)
	var cp_spacing: float = float(opts.get("cpSpacing", 400.0))
	var start_at: float = float(opts.get("startAt", 6.0))
	var run_off: float = float(opts.get("runOff", 12.0))
	var L_: float = st.s
	var closure: float = JsMath.hypot2(float(st.x) - float(start.x), float(st.z) - float(start.z))
	var last_key: Dictionary = h_keys[h_keys.size() - 1]
	if closed and absf(float(last_key.s) - L_) < 1e-6 and absf(float(last_key.h) - float(h_keys[0].h)) > 0.01:
		push_error("turtle: a circuit must end at its start height (%s m), the last height key is %s m" % [h_keys[0].h, last_key.h])
		return {}
	if closed and absf(float(st.width) - float(start.width)) > 0.01:
		push_error("turtle: a circuit must end with its start width (%s m), not %s m" % [start.width, st.width])
		return {}
	_prepare_height(closed)
	var cp_s: PackedFloat64Array = cps.duplicate()
	if cp_s.is_empty():
		cp_s = _auto_checkpoints(L_, closed, cp_spacing, start_at, run_off)
		if cp_s.is_empty():
			return {}

	# control points: a graded mesh. Every metre gets a largest allowed spacing
	# (fine in tight turns and where height, width or banking bend, up to 40 m
	# on plain straights), smoothed so neighbouring pieces differ by at most
	# ~25 % (the spline stays accurate). Only kicker lips are fixed points;
	# checkpoints snap to the nearest point.
	var M: int = int(ceil(L_)) + 1
	var hs: PackedFloat64Array = PackedFloat64Array()
	hs.resize(M)
	for j in M:
		var sj: float = minf(float(j), L_)
		var k: float = absf(_curv_at(sj))
		var h: float = minf(8.0, 0.15 / k) if k > 1e-6 else 40.0
		h = minf(h, minf(_bend(0, sj, 0.03, L_, closed), minf(_bend(1, sj, 0.05, L_, closed), _bend(2, sj, 0.3, L_, closed))))
		hs[j] = maxf(1.0, h)
	for j in range(1, M):
		hs[j] = minf(hs[j], hs[j - 1] + 0.25)
	for j in range(M - 2, -1, -1):
		hs[j] = minf(hs[j], hs[j + 1] + 0.25)
	var hard: Array[float] = []
	for kk in kickers:
		hard.append_array([float(kk.foot), float(kk.lip) - 1.0, float(kk.lip), float(kk.lip) + 1.0, float(kk.landEnd)])
	var uniq: Array[float] = []
	for b in hard:
		var r3: float = JsMath.round(b * 1000.0) / 1000.0
		if not uniq.has(r3):
			uniq.append(r3)
	var mid: Array[float] = []
	for b in uniq:
		if b > 0.01 and b < L_ - 0.01:
			mid.append(b)
	mid.sort()
	var must: Array[float] = [0.0]
	must.append_array(mid)
	must.append(L_)
	var s_list: PackedFloat64Array = PackedFloat64Array()
	for m in must.size() - 1:
		var a: float = must[m]
		var b2: float = must[m + 1]
		var p: float = a
		s_list.append(a)
		while true:
			var step: float = _h_at(hs, M, p)
			var x: float = p
			while x < p + step:
				step = minf(step, _h_at(hs, M, x) + (x - p) * 0.25)
				x += 1.0
			var rest: float = b2 - p
			if rest <= step * 1.05:
				break
			if rest <= step * 2.0:
				p += rest / 2.0
				s_list.append(p)
				break
			p += step
			s_list.append(p)
	if not closed:
		s_list.append(L_)
	var points: Array = []
	for s in s_list:
		var pos: PackedFloat64Array = _pos_at(s)
		points.append([_r2(pos[0]), _r2(pos[1]), _r2(profile_at(s, closed)), _r1(_bank_at(s)), _r1(_width_at(s))])
	var checkpoints: Array[int] = []
	for c in cp_s:
		var best: int = 0
		var bd: float = INF
		for i in s_list.size():
			var dd: float = absf(s_list[i] - c)
			if dd < bd:
				bd = dd
				best = i
		checkpoints.append(best)
	checkpoints.sort()
	var surf_out: Array = []
	for k in surf_keys.size():
		var key: Dictionary = surf_keys[k]
		var s0: float = key.s
		var s1: float = float(surf_keys[k + 1].s) if k + 1 < surf_keys.size() else L_
		if String(key.kind) == "asphalt" or s1 - s0 < 1e-6:
			continue
		surf_out.append([String(key.kind), _ctrl_index(s_list, s0, L_, closed), _ctrl_index(s_list, s1, L_, closed)])
	var kick_out: Array = []
	for kk in kickers:
		kick_out.append({s0 = kk.s0, s1 = kk.s1, foot = kk.foot, lip = kk.lip, landEnd = kk.landEnd, h = kk.h, grade = kk.grade, landGrade = kk.landGrade})
	return {
		points = points, checkpoints = checkpoints, surfaces = surf_out, length = L_, closure = closure, state = st.duplicate(),
		kickers = kick_out, cpDistances = cp_s, closed = closed,
	}


## Distance s as a control-point index with a fraction (2 decimals): between the points at
## s_list[i] and the next one (a circuit's last point is followed by point 0 again at L_).
static func _ctrl_index(s_list: PackedFloat64Array, s: float, L_: float, closed: bool) -> float:
	var n: int = s_list.size()
	var i: int = 0
	while i + 1 < n and s_list[i + 1] <= s:
		i += 1
	var nxt: float = s_list[i + 1] if i + 1 < n else (L_ if closed else s_list[i])
	var f: float = (s - s_list[i]) / (nxt - s_list[i]) if nxt > s_list[i] else 0.0
	return JsMath.round((i + f) * 100.0) / 100.0


static func _h_at(hs: PackedFloat64Array, M: int, x: float) -> float:
	return hs[maxi(0, mini(M - 1, JsMath.roundi(x)))]


## Largest spacing that keeps the chord error of function `which` (0 height, 1 width, 2 bank) below tol.
func _bend(which: int, s: float, tol: float, L_: float, closed: bool) -> float:
	var d2: float = absf(_fn(which, minf(L_, s + 2.0), closed) - 2.0 * _fn(which, s, closed) + _fn(which, maxf(0.0, s - 2.0), closed)) / 4.0
	return sqrt((8.0 * tol) / d2) if d2 > 1e-9 else INF


func _fn(which: int, s: float, closed: bool) -> float:
	if which == 0:
		return profile_at(s, closed)
	if which == 1:
		return _width_at(s)
	return _bank_at(s)


static func _r1(v: float) -> float:
	return JsMath.round(v * 10.0) / 10.0 + 0.0


static func _r2(v: float) -> float:
	return JsMath.round(v * 100.0) / 100.0 + 0.0


# ---- path lookups ----------------------------------------------------------------

## [segment index, fraction] of distance s on the dense path.
func _idx_at(s: float) -> Array:
	var lo: int = 0
	var hi: int = P_s.size() - 1
	if s <= 0.0:
		return [0, 0.0]
	if s >= P_s[hi]:
		return [hi - 1, 1.0]
	while hi - lo > 1:
		var m: int = (lo + hi) >> 1
		if P_s[m] <= s:
			lo = m
		else:
			hi = m
	return [lo, (s - P_s[lo]) / (P_s[lo + 1] - P_s[lo])]


func _pos_at(s: float) -> PackedFloat64Array:
	var r: Array = _idx_at(s)
	var i: int = r[0]
	var f: float = r[1]
	var j: int = mini(i + 1, P_s.size() - 1)
	return PackedFloat64Array([P_x[i] + (P_x[j] - P_x[i]) * f, P_z[i] + (P_z[j] - P_z[i]) * f, P_yaw[i] + (P_yaw[j] - P_yaw[i]) * f])


func _curv_at(s: float) -> float:
	var r: Array = _idx_at(s)
	var i: int = r[0]
	return P_k[mini(i + 1, P_k.size() - 1)]


func _bank_at(s: float) -> float:
	var r: Array = _idx_at(s)
	var i: int = r[0]
	var f: float = r[1]
	var j: int = mini(i + 1, P_s.size() - 1)
	return P_b[i] + (P_b[j] - P_b[i]) * f


func _width_at(s: float) -> float:
	var w: float = start.width
	for k in w_keys:
		if s >= float(k.s1):
			w = k.w1
		elif s > float(k.s0):
			w = float(k.w0) + (float(k.w1) - float(k.w0)) * _smoothstep((s - float(k.s0)) / (float(k.s1) - float(k.s0)))
			break
		else:
			break
	return w


## The dense path so far: {s, x, z, yaw} arrays every ~0.25 m.
func path() -> Dictionary:
	return {s = P_s, x = P_x, z = P_z, yaw = P_yaw}


func _on_kicker(s: float) -> bool:
	for k in kickers:
		if s > float(k.foot) - 30.0 and s < float(k.s1) + 10.0:
			return true
	return false


func _auto_checkpoints(L_: float, closed: bool, spacing: float, start_at: float, run_off: float) -> PackedFloat64Array:
	var s0: float = 0.0 if closed else start_at
	var s1: float = L_ if closed else L_ - run_off
	var first: int = maxi(2, JsMath.roundi((s1 - s0) / spacing))
	# evenly spaced targets, each moved to the nearest good spot (not on a
	# jump, preferably not in a tight turn); add a gate if a gap gets too long
	for gaps in range(first, first + 4):
		var step: float = (s1 - s0) / gaps
		var out: PackedFloat64Array = PackedFloat64Array()
		for g in range(1, gaps):
			var target: float = s0 + g * step
			var best: float = NAN
			var bc: float = INF
			for d in range(-150, 151):
				var s: float = target + d
				if s <= s0 + 200.0 or s >= s1 - 200.0 or _on_kicker(s):
					continue
				var cost: float = absf(float(d)) + (25.0 if absf(_curv_at(s)) > 1.0 / 80.0 else 0.0)
				if cost < bc:
					bc = cost
					best = s
			if not is_nan(best):
				out.append(best)
		var all_: PackedFloat64Array = PackedFloat64Array([s0])
		all_.append_array(out)
		all_.append(s1)
		var ok: bool = out.size() == gaps - 1
		for k in range(1, all_.size()):
			var gap: float = all_[k] - all_[k - 1]
			if not (gap >= 260.0 and gap <= 490.0):
				ok = false
		if ok:
			return out
	push_error("turtle: could not place checkpoints 260-490 m apart off the jumps")
	return PackedFloat64Array()


## Close a circuit. make(a, b) runs a turtle program (returns the Turtle) in
## which a and b are the lengths of two straights that point in different
## directions; close_loop finds a and b so the turtle ends exactly where it
## started (the turns must add up to ±360°). Returns {t, a, b, error} or {}
## (with an error printed) when it can't.
static func close_loop(make: Callable, opts: Dictionary = {}) -> Dictionary:
	var a0: float = float(opts.get("a0", 100.0))
	var b0: float = float(opts.get("b0", 100.0))
	var min_a: float = float(opts.get("minA", 0.0))
	var min_b: float = float(opts.get("minB", 0.0))
	var e0: Array = _end(make, a0, b0)
	var ea: Array = _end(make, a0 + 10.0, b0)
	var eb: Array = _end(make, a0, b0 + 10.0)
	var x0: float = e0[0]
	var z0: float = e0[1]
	var ja: Array[float] = [(float(ea[0]) - x0) / 10.0, (float(ea[1]) - z0) / 10.0]
	var jb: Array[float] = [(float(eb[0]) - x0) / 10.0, (float(eb[1]) - z0) / 10.0]
	var det: float = ja[0] * jb[1] - ja[1] * jb[0]
	if absf(det) < 1e-6:
		push_error("closeLoop: the two straights are parallel")
		return {}
	var da: float = (-x0 * jb[1] + z0 * jb[0]) / det
	var db: float = (-z0 * ja[0] + x0 * ja[1]) / det
	var a: float = a0 + da
	var b: float = b0 + db
	var ef: Array = _end(make, a, b)
	var turns: float = float(ef[2]) / (2.0 * PI)
	if absf(absf(turns) - 1.0) > 1e-6:
		push_error("closeLoop: the turns add up to %.2f°, not ±360°" % (turns * 360.0))
		return {}
	if a < min_a or b < min_b:
		push_error("closeLoop: straights would be %.1f m and %.1f m (minimum %s / %s)" % [a, b, min_a, min_b])
		return {}
	return {t = ef[3], a = a, b = b, error = JsMath.hypot2(float(ef[0]), float(ef[1]))}


static func _end(make: Callable, a: float, b: float) -> Array:
	var t: Turtle = make.call(a, b)
	return [float(t.st.x) - t.P_x[0], float(t.st.z) - t.P_z[0], float(t.st.yaw) - t.P_yaw[0], t]


## Monotone cubic through height keyframes {s, h, flat}; flat keys get a zero slope (turtle.mjs pchipKeys).
class _PchipKeys:
	var keys: Array[Dictionary]
	var closed: bool
	var L_: float
	var n: int
	var m: PackedFloat64Array = PackedFloat64Array()

	func _init(keys_: Array[Dictionary], closed_: bool, length: float) -> void:
		keys = keys_
		closed = closed_
		L_ = length
		n = keys.size()
		m.resize(n)
		for k in n:
			var key: Dictionary = keys[k]
			if bool(key.flat):
				m[k] = 0.0
				continue
			if not closed and (k == 0 or k == n - 1):
				m[k] = 0.0
				continue
			var d0: float = _sec(k - 1)
			var d1: float = _sec(k)
			if d0 * d1 <= 0.0:
				m[k] = 0.0
				continue
			var h0: float = X(k) - X(k - 1)
			var h1: float = X(k + 1) - X(k)
			var w1: float = 2.0 * h1 + h0
			var w2: float = h1 + 2.0 * h0
			m[k] = (w1 + w2) / (w1 / d0 + w2 / d1)

	func X(k: int) -> float:
		if closed:
			return float(keys[posmod(k, n)].s) + floorf(float(k) / n) * L_
		return float(keys[clampi(k, 0, n - 1)].s)

	func Y(k: int) -> float:
		if closed:
			return float(keys[posmod(k, n)].h)
		return float(keys[clampi(k, 0, n - 1)].h)

	func _sec(k: int) -> float:
		var h: float = X(k + 1) - X(k)
		return (Y(k + 1) - Y(k)) / h if h > 1e-9 else 0.0

	func eval(s: float) -> float:
		if n == 1:
			return float(keys[0].h)
		var k: int
		if closed:
			s = fmod(fmod(s, L_) + L_, L_)
			k = n - 1
			for j in range(1, n):
				if float(keys[j].s) > s:
					k = j - 1
					break
		else:
			if s <= float(keys[0].s):
				return float(keys[0].h)
			if s >= float(keys[n - 1].s):
				return float(keys[n - 1].h)
			k = 0
			while k < n - 2 and s >= float(keys[k + 1].s):
				k += 1
		var x0: float = X(k)
		var h: float = X(k + 1) - x0
		if h <= 1e-9:
			return Y(k)
		var t: float = Turtle._clamp((s - x0) / h, 0.0, 1.0)
		var t2: float = t * t
		var t3: float = t2 * t
		return (2.0 * t3 - 3.0 * t2 + 1.0) * Y(k) + (t3 - 2.0 * t2 + t) * h * m[k % n] + (-2.0 * t3 + 3.0 * t2) * Y(k + 1) + (t3 - t2) * h * m[(k + 1) % n]
