class_name ScoreState
extends RefCounted
## score.gd: style points for clean driving (v4), a port of web/src/game/score.js.
## ------------------------------------------------------------------
## Reads nothing but the car's plain state and the race's gates, once per
## fixed 60 Hz step, so a run always scores exactly the same.
##
##   var score := ScoreState.new(track)            # nitro = false: score only, no refills
##   ... each step, after car.step() and race.update():
##   var events := score.update(car, race, dt)     # [] or [{kind, points, text, ...}]
##   ... when the player respawns:  score.respawn()
##   score.total, score.multiplier(), score.live() ({} or {kind, points, time}), score.breakdown()
##   ScoreState.format_points(12345) -> "12,345"
##
## Rules (numbers in SCORE, with the JS names; read the JS header for the full text):
##  - Clean checkpoint: a gate reached without a wall contact or respawn since the
##    gate before: cpPoints × the combo multiplier (x1, +1 per clean gate in a row,
##    up to comboMax). A contact or respawn resets it and spoils the section.
##  - Drift: body slip >= driftOn above driftSpeed builds driftRate a second at 30°
##    and 25 m/s (∝ angle and speed, doubling over driftHold s); ends after driftGrace
##    s under driftOff; banked if it lasted driftMin s; lost on a wall or a spin.
##  - Air: airRate a second of flight (airMin s or more), banked after a clean
##    landing (slip under airCrooked, no wall for airSettle s).
##  - Close call: within closeGap m of a wall above closeSpeed without touching:
##    closePoints after closeSettle s clear; then closeWait s of nothing.
##  - Wall: each contact costs wallPoints + wallImpact × impact (m/s) + scrapeRate a
##    second past scrapeAfter s, at most wallMax; touches < wallMerge s apart merge.
##  - Respawn: respawnPoints. Drifts, jumps and close calls score only on new road
##    (no more than replayGap m behind the furthest point reached).
##  - Clean lap: cleanLap; clean run: cleanRun at the finish. Penalties never take
##    the score below zero.
## Nitro: every point banked refills 1 / pointsPerTank of a tank (car.add_nitro);
## respawns and the points banked at the finish refill nothing.
## SCORE_RULES tags stored best scores: bump it when the rules or numbers change.
##
## Events: {kind, points, text} plus kind "cp": mult; "drift" / "air": time;
## "wall": impact; combo_lost on wall and respawn events. Kinds: cp, drift, air,
## close, lap, run (points > 0); wall, respawn (points <= 0); driftLost, airLost (0).

const SCORE_RULES: int = 1
const DEG: float = PI / 180.0

## The rules' numbers (JS names, as web/src/game/score.js SCORE).
const SCORE: Dictionary = {
	cpPoints = 500, # a clean checkpoint, × the combo multiplier
	comboMax = 5, # highest multiplier
	driftOn = 12 * DEG, # body slip angle that starts a drift ...
	driftOff = 8 * DEG, # ... and keeps it going
	driftSpeed = 12, # m/s to start a drift (43 km/h) ...
	driftKeep = 9, # ... and to keep it going
	driftRate = 600, # points a second at 30° and 25 m/s (90 km/h), in proportion to both
	driftMaxAngle = 45 * DEG, # more angle than this scores no more
	driftMaxSpeed = 50, # m/s, nor does more speed
	driftHold = 3, # s: the rate grows to twice this over the first driftHold s of a drift
	driftGrace = 0.3, # s under driftOff before a drift ends
	driftMin = 0.6, # s a drift must last to count
	driftSpin = 100 * DEG, # slip angle that counts as a spin (the drift is lost)
	airRate = 500, # points a second of flight
	airMin = 0.5, # s of flight that count (crest hops don't)
	airCrooked = 25 * DEG, # slip angle at touchdown above which the landing is crooked (no points)
	airSettle = 0.5, # s after touchdown without a wall contact before the jump is banked
	closePoints = 250, # a close call
	closeGap = 0.5, # m between the car's capsule and the wall
	closeSpeed = 30, # m/s (108 km/h)
	closeSettle = 0.3, # s clear of the wall (no contact) before it counts
	closeWait = 2, # s after a close call before the next can count
	wallPoints = 150, # a wall contact ...
	wallImpact = 25, # ... + this per m/s of speed into the wall ...
	scrapeRate = 200, # ... + this a second of contact ...
	scrapeAfter = 0.5, # ... past the first scrapeAfter s ...
	wallMax = 1500, # ... at most
	wallMerge = 0.4, # s: touches closer together than this are one contact
	respawnPoints = 500,
	replayGap = 15, # m behind the furthest point reached that still count as new road
	cleanLap = 2000, # a circuit lap without a wall contact or respawn
	cleanRun = 5000, # the whole race without one
	pointsPerTank = 16000, # points that refill one full nitro tank
}

## Category keys of the breakdown, in the order the finish panel lists them.
const CATEGORIES: PackedStringArray = ["checkpoints", "drift", "air", "close", "laps", "run", "walls", "respawns"]


class Drift:
	var t: float = 0.0
	var points: float = 0.0
	var grace: float = 0.0


class Flight:
	var t: float = 0.0
	var lost: bool = false


class Landing:
	var t: float = 0.0
	var points: float = 0.0
	var settle: float = 0.0


class WallContact:
	var t: float = 0.0
	var impact: float = 0.0
	var off: float = 0.0


var track: BuiltTrack
## banked points refill the car's nitro tank
var refill: bool = true
var total: float = 0.0
## clean gates in a row
var combo: int = 0
## per category (penalties negative)
var points: Dictionary = {}
var counts: Dictionary = {}
## tanks the banked points refilled (what actually went in: the tank holds 1)
var nitro: float = 0.0
## tanks the points banked before the finish were worth
var nitro_earned: float = 0.0
## the race's next gate as of the last update
var gate: int = 0
## no wall contact or respawn since the last gate / this lap / this race
var section: bool = true
var lap: bool = true
var run: bool = true
var finished: bool = false
## the furthest car.prog of this run (samples): new road starts replayGap m behind it
var reach: float = -INF
var drift: Drift = null
var flight: Flight = null
var landing: Landing = null
var wall: WallContact = null
## after passing close to a wall: seconds since
var near: float = -1.0
var close_cool: float = 0.0
var wall_combo_lost: bool = false
var _out: Array[Dictionary] = []
var _car: Car = null


func _init(t: BuiltTrack, nitro_refill: bool = true) -> void:
	track = t
	refill = nitro_refill
	reset()


func reset() -> void:
	total = 0.0
	combo = 0
	points = {}
	for k: String in CATEGORIES:
		points[k] = 0.0
	counts = {
		gates = 0, clean_gates = 0, best_mult = 1, laps = 0, clean_laps = 0, drifts = 0, best_drift = 0.0,
		airs = 0, best_air = 0.0, close_calls = 0, wall_hits = 0, respawns = 0,
	}
	nitro = 0.0
	nitro_earned = 0.0
	gate = 0
	section = true
	lap = true
	run = true
	finished = false
	reach = -INF
	drift = null
	flight = null
	landing = null
	wall = null
	near = -1.0
	close_cool = 0.0
	wall_combo_lost = false
	_out = []


## The multiplier the next clean checkpoint gets (x1 .. x comboMax).
func multiplier() -> int:
	return mini(int(SCORE.comboMax), combo + 1)


## What is building up right now, for the HUD ({}: nothing): a wall contact
## {kind = "wall", points (negative), time}, a jump {kind = "air", points, time}
## (from airMin s of flight until it is banked) or a drift {kind = "drift", points, time}
## (from a quarter second).
func live() -> Dictionary:
	if wall != null:
		var p: float = -minf(total, _wall_penalty())
		return {kind = "wall", points = 0.0 if p == 0.0 else p, time = wall.t}
	if landing != null:
		return {kind = "air", points = landing.points, time = landing.t}
	if flight != null and not flight.lost and flight.t >= SCORE.airMin:
		return {kind = "air", points = _round10(flight.t * SCORE.airRate), time = flight.t}
	if drift != null and drift.t >= 0.25:
		return {kind = "drift", points = _round10(drift.points), time = drift.t}
	return {}


## One physics step, after car.step() and race.update(). Returns this step's events, in order.
func update(car: Car, race: RaceState, dt: float) -> Array[Dictionary]:
	if finished:
		return []
	_out = []
	_car = car
	var P: Dictionary = SCORE
	var slip: float = _slip_angle(car)
	# new road: not more than replayGap m behind the furthest point of this run
	if car.prog > reach:
		reach = car.prog
	var fresh: bool = car.prog >= reach - P.replayGap / track.seg_len

	# --- walls: a contact spoils the section, the lap, the run and anything building up
	if car.hit_wall:
		if wall == null:
			wall = WallContact.new()
			counts.wall_hits += 1
			wall_combo_lost = _spoil()
		elif section and _spoil():
			# a touch merged into a contact from before the last gate spoils this section too
			wall_combo_lost = true
		wall.t += dt
		wall.off = 0.0
		wall.impact += car.wall_impact
	elif wall != null:
		wall.off += dt
		if wall.off >= P.wallMerge:
			_end_wall()

	# --- air: banked after a clean landing (a take-off from road already driven scores nothing)
	if not car.grounded:
		if flight == null:
			flight = Flight.new()
			flight.lost = not fresh
		flight.t += dt
	elif flight != null:
		var f: Flight = flight
		flight = null
		if not f.lost and f.t >= P.airMin:
			if slip > P.airCrooked:
				_emit({kind = "airLost", points = 0, text = "Crooked landing"})
			else:
				landing = Landing.new()
				landing.t = f.t
				landing.points = _round10(f.t * P.airRate)
	if landing != null:
		landing.settle += dt
		if landing.settle >= P.airSettle:
			_bank_air()

	# --- drift: builds up while sliding on the ground, banked when it ends cleanly
	var d: Drift = drift
	if d == null:
		if fresh and car.grounded and wall == null and car.speed >= P.driftSpeed and slip >= P.driftOn and slip < P.driftSpin:
			drift = Drift.new()
			_drift_step(car, slip, dt)
	elif slip >= P.driftSpin:
		drift = null
		if d.t >= P.driftMin:
			_emit({kind = "driftLost", points = 0, text = "Spin: drift lost"})
	elif car.grounded:
		if slip >= P.driftOff and car.speed >= P.driftKeep:
			d.grace = 0.0
			_drift_step(car, slip, dt)
		else:
			d.grace += dt
			if d.grace >= P.driftGrace:
				_end_drift()

	# --- close calls: near a wall at speed without touching it
	if close_cool > 0.0:
		close_cool -= dt
	if fresh and car.grounded and wall == null and car.speed >= P.closeSpeed and close_cool <= 0.0 and _clearance(car) < P.closeGap:
		near = 0.0
	elif near >= 0.0:
		near += dt
		if near >= P.closeSettle:
			near = -1.0
			close_cool = P.closeWait
			counts.close_calls += 1
			_bank("close", P.closePoints, {kind = "close", text = "Close call"})

	# --- gates
	while gate < race.next_gate:
		gate += 1
		_on_gate(race.gates[gate - 1])
	var out: Array[Dictionary] = _out
	_out = []
	return out


## The player went back to the last checkpoint: a penalty, and the combo, the section
## and anything building up are lost. Returns the events.
func respawn() -> Array[Dictionary]:
	if finished:
		return []
	_out = []
	if wall != null:
		_end_wall()
	counts.respawns += 1
	var combo_lost: bool = _spoil()
	flight = null # the car is back on the road
	_penalty("respawns", SCORE.respawnPoints, {kind = "respawn", text = "Respawn", combo_lost = combo_lost})
	var out: Array[Dictionary] = _out
	_out = []
	return out


## The finish panel's lines: [{key, label, points, note}] for every category that
## scored something, plus the checkpoints always and walls and respawns whenever there were any.
func breakdown() -> Array[Dictionary]:
	var c: Dictionary = counts
	var rows: Array = [
		["checkpoints", "Clean checkpoints", "%d of %d · best x%d" % [c.clean_gates, c.gates, c.best_mult]],
		["drift", "Drifts", ("%d · best %s" % [c.drifts, format_points(c.best_drift)]) if c.drifts else ""],
		["air", "Air", ("%d · longest %s s" % [c.airs, JsMath.to_fixed(c.best_air, 1)]) if c.airs else ""],
		["close", "Close calls", str(c.close_calls) if c.close_calls else ""],
		["laps", "Clean laps", ("%d of %d" % [c.clean_laps, c.laps]) if c.laps else ""],
		["run", "Clean run", ""],
		["walls", "Walls", "%d %s" % [c.wall_hits, "contact" if c.wall_hits == 1 else "contacts"]],
		["respawns", "Respawns", str(c.respawns)],
	]
	var out: Array[Dictionary] = []
	for row: Array in rows:
		var k: String = row[0]
		if points[k] != 0.0 or k == "checkpoints" or (k == "walls" and c.wall_hits > 0) or (k == "respawns" and c.respawns > 0):
			out.append({key = k, label = row[1], points = points[k], note = row[2]})
	return out


## 12345 -> "12,345" (whole points; a minus sign "−" for negatives).
static func format_points(n: float) -> String:
	var v: int = JsMath.roundi(n)
	var digits: String = str(absi(v))
	var s: String = ""
	var k: int = digits.length()
	while k > 3:
		s = "," + digits.substr(k - 3, 3) + s
		k -= 3
	s = digits.substr(0, k) + s
	return ("−" if v < 0 else "") + s


static func _round10(x: float) -> float:
	return JsMath.round(x / 10.0) * 10.0


## Body slip angle (rad): between the car's heading and where it is going; over 90° it moves backwards.
static func _slip_angle(car: Car) -> float:
	return atan2(absf(car.side_speed), car.forward_speed)


## The flight label for `t` s of air.
static func _air_text(t: float) -> String:
	return "Huge air" if t >= 2.5 else ("Big air" if t >= 1.5 else "Air")


# ---------------------------------------------------------------- internals

func _emit(ev: Dictionary) -> void:
	_out.append(ev)


## Add points to a category and the total; they refill the car's nitro tank (not at the finish: the race is over).
func _bank(cat: String, pts: float, ev: Dictionary) -> void:
	if pts <= 0.0:
		return
	total += pts
	points[cat] += pts
	if not finished:
		var tanks: float = pts / SCORE.pointsPerTank
		nitro_earned += tanks
		if refill and _car != null:
			var before: float = _car.nitro
			_car.add_nitro(tanks)
			nitro += _car.nitro - before
	var e: Dictionary = ev.duplicate()
	e.points = pts
	_emit(e)


## Take up to `pts` points (never below zero).
func _penalty(cat: String, pts: float, ev: Dictionary) -> void:
	var took: float = minf(total, maxf(0.0, pts))
	total -= took
	points[cat] -= took
	var e: Dictionary = ev.duplicate()
	e.points = -took if took != 0.0 else 0.0
	_emit(e)


## A wall contact or respawn: the combo, the section, the lap and the run are no longer
## clean; drift and jump are lost. Returns whether a combo was lost.
func _spoil() -> bool:
	var combo_lost: bool = combo > 0
	combo = 0
	section = false
	lap = false
	run = false
	if drift != null:
		if drift.t >= SCORE.driftMin:
			_emit({kind = "driftLost", points = 0, text = "Drift lost"})
		drift = null
	if landing != null or (flight != null and not flight.lost and flight.t >= SCORE.airMin):
		_emit({kind = "airLost", points = 0, text = "Air lost"})
	landing = null
	if flight != null:
		flight.lost = true
	near = -1.0
	return combo_lost


func _wall_penalty() -> float:
	var P: Dictionary = SCORE
	return _round10(minf(P.wallMax, P.wallPoints + P.wallImpact * wall.impact + P.scrapeRate * maxf(0.0, wall.t - P.scrapeAfter)))


func _end_wall() -> void:
	var pts: float = _wall_penalty()
	var impact: float = wall.impact
	wall = null
	_penalty("walls", pts, {kind = "wall", text = "Wall", impact = impact, combo_lost = wall_combo_lost})


func _drift_step(car: Car, slip: float, dt: float) -> void:
	var d: Drift = drift
	var P: Dictionary = SCORE
	d.t += dt
	var angle: float = minf(slip, P.driftMaxAngle) / (30 * DEG)
	var spd: float = minf(car.speed, P.driftMaxSpeed) / 25.0
	d.points += P.driftRate * angle * spd * (1.0 + minf(d.t, P.driftHold) / P.driftHold) * dt


func _end_drift() -> void:
	var d: Drift = drift
	drift = null
	var pts: float = _round10(d.points)
	if d.t < SCORE.driftMin or pts <= 0.0:
		return
	counts.drifts += 1
	counts.best_drift = maxf(counts.best_drift, pts)
	_bank("drift", pts, {kind = "drift", text = "Drift", time = d.t})


func _bank_air() -> void:
	var l: Landing = landing
	landing = null
	counts.airs += 1
	counts.best_air = maxf(counts.best_air, l.t)
	_bank("air", l.points, {kind = "air", text = _air_text(l.t), time = l.t})


## Gap (m) between the car's capsule and the nearer wall (walls run at ±hw from the centre line).
func _clearance(car: Car) -> float:
	var i: int = car.idx
	var S: CarSpec = car.spec
	var fn: float = sin(car.yaw) * track.nx[i] + cos(car.yaw) * track.nz[i] # heading across the road
	var r: float = absf(car.lat) + absf(fn) * (S.half_length - S.radius) + S.radius
	return track.hw[i] - r


func _on_gate(g: Dictionary) -> void:
	var P: Dictionary = SCORE
	var c: Dictionary = counts
	c.gates += 1
	if g.kind == "finish":
		finished = true # the race is over: its last points refill no nitro
	if section:
		var mult: int = multiplier()
		combo += 1
		c.clean_gates += 1
		c.best_mult = maxi(c.best_mult, mult)
		_bank("checkpoints", P.cpPoints * mult, {kind = "cp", text = "Clean finish" if g.kind == "finish" else "Clean checkpoint", mult = mult})
	# a car touching the wall right at the gate spoils the next section too (a touch that has
	# already ended doesn't, though its penalty is still waiting out the merge window)
	var touching: bool = wall != null and wall.off == 0.0
	section = not touching
	if track.closed and (g.kind == "lap" or g.kind == "finish"):
		c.laps += 1
		if lap:
			c.clean_laps += 1
			_bank("laps", P.cleanLap, {kind = "lap", text = "Clean lap"})
		lap = not touching
	if g.kind != "finish":
		return
	# the finish: bank what was building up cleanly, then the clean run
	if wall != null:
		_end_wall()
	if drift != null:
		_end_drift()
	if landing != null:
		_bank_air()
	flight = null
	near = -1.0
	if run:
		_bank("run", P.cleanRun, {kind = "run", text = "Clean run"})
