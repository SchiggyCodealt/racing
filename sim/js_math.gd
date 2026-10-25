class_name JsMath
extends RefCounted
## js_math.gd
## ------------------------------------------------------------------
## The few JavaScript Math functions whose exact results differ from the
## obvious GDScript spelling, so the port computes the same numbers as the
## browser game (web/src):
##   - round(x): JS Math.round rounds halves up (towards +infinity), so
##     round(-2.5) = -2; GDScript's round() goes away from zero (-3).
##   - hypot2 / hypot3: V8's Math.hypot (scaled, Kahan-summed). It differs
##     from sqrt(x*x + y*y) in the last bit for about 40 % of inputs.
## sin, cos, atan, exp and friends come from the C library in Godot and from
## fdlibm in V8; they agree to the last bit for about 90 % of arguments and
## differ by one unit in the last place otherwise (see tools/parity notes in
## the core report). Nothing here tries to emulate that.


## JS Math.round: the nearest integer, halves rounded up (towards +infinity).
static func round(x: float) -> float:
	var f: float = floor(x)
	return f + 1.0 if x - f >= 0.5 else f


## JS Math.round as an int.
static func roundi(x: float) -> int:
	var f: float = floor(x)
	return int(f + 1.0 if x - f >= 0.5 else f)


## V8's Math.hypot(a, b), bit for bit.
static func hypot2(a: float, b: float) -> float:
	var aa: float = absf(a)
	var ab: float = absf(b)
	if is_nan(a) or is_nan(b):
		return INF if (is_inf(a) or is_inf(b)) else NAN
	var mx: float = aa if aa > ab else ab
	if mx == INF:
		return INF
	if mx == 0.0:
		return 0.0
	# Kahan summation of the squares, normalised by the largest value
	var sum: float = 0.0
	var comp: float = 0.0
	var n: float = aa / mx
	var summand: float = n * n - comp
	var pre: float = sum + summand
	comp = (pre - sum) - summand
	sum = pre
	n = ab / mx
	summand = n * n - comp
	pre = sum + summand
	sum = pre
	return sqrt(sum) * mx


## V8's Math.hypot(a, b, c), bit for bit.
static func hypot3(a: float, b: float, c: float) -> float:
	var vals: Array[float] = [absf(a), absf(b), absf(c)]
	var mx: float = 0.0
	for v in vals:
		if is_nan(v):
			return NAN
		if v > mx:
			mx = v
	if mx == INF:
		return INF
	if mx == 0.0:
		return 0.0
	var sum: float = 0.0
	var comp: float = 0.0
	for v in vals:
		var n: float = v / mx
		var summand: float = n * n - comp
		var pre: float = sum + summand
		comp = (pre - sum) - summand
		sum = pre
	return sqrt(sum) * mx


## JS Math.sign for finite numbers (0 stays 0).
static func sign(x: float) -> float:
	return 1.0 if x > 0.0 else (-1.0 if x < 0.0 else 0.0)


## JS Number.prototype.toFixed(digits) for finite numbers below 1e21: like "%.*f", except
## that an exact tie (x * 2^(digits + 1) an odd integer, e.g. 0.0625 with 3 digits) rounds
## away from zero as in JS, where printf rounds it to even ("0.063" vs "0.062").
static func to_fixed(x: float, digits: int) -> String:
	var ax: float = absf(x)
	var q: float = ax * pow(2.0, digits + 1)
	if q == floorf(q) and fmod(q, 2.0) == 1.0:
		ax += 0.5 * pow(10.0, -digits) * 0.5 # nudge the tie up; the result is exact to `digits`
	var s: String = ("%." + str(digits) + "f") % ax
	return ("-" + s) if x < 0.0 else s # (JS: (-0.0001).toFixed(3) = "-0.000")


## Number -> text the way JavaScript's String(number) writes it for the values
## the tools print (shortest digits that read back to the same double).
static func num_to_js(v: float) -> String:
	if v == 0.0:
		return "0"
	if v == floor(v) and absf(v) < 1e15:
		return str(int(v))
	for digits in range(1, 18):
		var s: String = String.num(v, digits)
		if s.to_float() == v:
			return _trim(s)
	return String.num_scientific(v)


static func _trim(s: String) -> String:
	if s.find(".") < 0:
		return s
	while s.ends_with("0"):
		s = s.substr(0, s.length() - 1)
	if s.ends_with("."):
		s = s.substr(0, s.length() - 1)
	return s
