class_name FieldRace
extends RefCounted
## field_race.gd (v6.13.0): Race the field, the race: the player and AI_COUNT AI cars on one track,
## with solid cars, positions and gaps.
## ------------------------------------------------------------------
## modes/field_mode.gd runs one in the game; tools/field.gd and the tests run them without it (there the
## "player" can be driven by a driver object too). Every 60 Hz step:
##   1. each AI's controls: its network (ai/sensors.gd AIDriver, the car's AI opponent network with the
##      driver's speed cap, sim/field.gd) and on top of it a light rule-based layer for traffic, since the
##      networks only see walls (traffic()): a car close ahead in its lane that it is closing on makes it
##      ease off towards that car's speed and steer a little to the side with more room to pass; a car
##      alongside makes it keep a little apart. A finished car rolls out (PlayMode.roll_out);
##   2. every car steps (the player's with the controls given);
##   3. the solid cars collide (sim/car_contact.gd). Not solid: a finished car, and a car that was just
##      put back on the road, until it has been clear of every other car for CLEAR_TIME;
##   4. every race updates (checkpoints, laps, the finish); each car's progress marks are noted (the
##      gaps); an AI car that is stuck (no progress for PlayMode.STUCK_TIME, as in Race the AI) or faces
##      the wrong way for WRONG_WAY_TIME is put back at its last checkpoint, standing, as the player's
##      respawn would; after the player's finish an AI that hasn't finished within FINISH_WAIT s is out
##      (DNF).
## Deterministic: the same field, inputs and track give the same race.
##
##   var f := FieldRace.new(track, lineup, drivers, player_car, player_race)   # places every car on the grid
##   var events := f.step(dt, player_controls)    # the player's race events of this step
##   f.standings() -> racer indices, leader first;  f.position(i) -> 1-based
##   f.gap(ahead, behind) -> s;  f.board(i) -> the HUD's {pos, of, rows, ahead, behind}
##   f.results() -> the finish panel's rows;  f.respawned(i) after the mode put car i back (the player)
## Racer indices: 0 .. AI_COUNT - 1 the AI in grid order (0 = pole), the player last (player_index).

const PlayMode := preload("res://modes/play_mode.gd")

const WRONG_WAY_TIME: float = 2.5
## Facing the road's direction less than this (cos of the angle) counts as the wrong way.
const WRONG_WAY_DOT: float = -0.25
## s a respawned car must be clear of every other car (by CLEAR_MARGIN m) before it is solid again
const CLEAR_TIME: float = 1.0
const CLEAR_MARGIN: float = 0.5
## Progress samples per gap mark (10 m).
const MARK: int = 5
const FINISH_WAIT: float = 90.0
## the traffic layer: how far it looks ahead (m + s × speed), how soon it reacts (s to contact), the
## lane (m besides the two half widths), how it follows (m/s per m of gap), how hard it steers
## round a car ahead and away from one alongside, and the room it wants on the side it passes (m)
const LOOK_BASE: float = 8.0
const LOOK_TIME: float = 1.1
const REACT_TIME: float = 1.6
const LANE_GAP: float = 0.6
const FOLLOW_K: float = 0.4
const PASS_STEER: float = 0.35
const SIDE_STEER: float = 0.12
const PASS_ROOM: float = 2.2


## One car of the field.
class Racer:
	var car: Car
	var race: RaceState
	## drive(track, car, race) -> Car.Controls (the AI; null: the player, driven by step()'s controls)
	var driver: Object = null
	## the lineup entry (sim/field.gd: name, code, car, color, cap, pace, slot) or the player's
	var info: Dictionary = {}
	var player: bool = false
	var slot: int = 0
	var watch: Dictionary = {}
	var wrong: float = 0.0
	## s left before a respawned car is solid again (0: solid)
	var ghost: float = 0.0
	var solid: bool = true
	var respawns: int = 0
	var contacts: int = 0
	var dnf: bool = false
	## the step it was last put back (the game snaps its drawing there)
	var respawn_step: int = -1
	## race time when the car last reached each progress mark (-1 not yet)
	var marks: PackedFloat32Array = PackedFloat32Array()
	var mark_k: int = -1
	var ctrl: Car.Controls = Car.Controls.new()
	var _now: Car.Controls = null


var track: BuiltTrack
var racers: Array[Racer] = []
var player_index: int = 0
var steps: int = 0
## race time (s since GO)
var time: float = 0.0
## new contacts (a pair that starts touching): between two AI cars, and with the player's car
var ai_contacts: int = 0
var player_contacts: int = 0
## this step's contacts (CarContact.Hit, indices are racer indices)
var hits: Array = []
## race time of the player's finish (-1 before)
var player_finished_at: float = -1.0

var _cars: Array = []
var _solid: Array = []
var _touching: Dictionary = {}


## `lineup`: sim/field.gd's entries (pole first); `drivers`: one driver object per entry; the player's
## car and race (made by the caller: its spec, nitro and recorder are the game's). Every car is placed
## on its grid slot; the player's last.
func _init(t: BuiltTrack, lineup: Array, drivers: Array, player_car: Car, player_race: RaceState, player_info: Dictionary = {}) -> void:
	track = t
	for k in lineup.size():
		var r := Racer.new()
		var e: Dictionary = lineup[k]
		r.info = e
		r.slot = k
		r.driver = drivers[k]
		r.car = Car.new(t, t.start_idx, Cars.spec(String(e.car)))
		r.race = RaceState.new(t)
		racers.append(r)
	var p := Racer.new()
	p.player = true
	p.slot = lineup.size()
	p.car = player_car
	p.race = player_race
	p.info = player_info
	racers.append(p)
	player_index = racers.size() - 1
	for r in racers:
		_cars.append(r.car)
		_solid.append(true)
	place_on_grid()


## Every car on its grid slot, standing; the race starts over (the player's car and race are reset
## by the caller first: the car's place here, its race untouched).
func place_on_grid() -> void:
	var g: Array[Dictionary] = Field.grid(track, racers.size())
	var size: int = int(ceil(float(track.N * (racers[0].race.laps + 1) + track.count) / MARK)) + 2
	for k in racers.size():
		var r := racers[k]
		var s: Dictionary = g[k]
		r.car.place(track, int(s.idx), {x = s.x, z = s.z, yaw = s.yaw, vx = 0.0, vz = 0.0, idx = s.idx, laps = 0})
		if not r.player:
			r.race.reset()
		r.watch = PlayMode._new_watch(r.car, 0.0)
		r.wrong = 0.0
		r.ghost = 0.0
		r.solid = true
		r.respawns = 0
		r.contacts = 0
		r.dnf = false
		r.respawn_step = -1
		r.marks = PackedFloat32Array()
		r.marks.resize(size)
		r.marks.fill(-1.0)
		r.mark_k = -1
		_mark(r)
	steps = 0
	time = 0.0
	ai_contacts = 0
	player_contacts = 0
	hits = []
	player_finished_at = -1.0
	_touching = {}


## One 60 Hz step of the whole field. Returns the player's race events (RaceState.update's).
func step(dt: float, player_ctrl: Car.Controls) -> Array[Dictionary]:
	steps += 1
	time += dt
	# 1. the AI's controls
	for r in racers:
		if r.player:
			r._now = player_ctrl
		elif r.race.finished or r.dnf:
			r._now = PlayMode.roll_out(r.car, track, r.ctrl)
		else:
			var c: Car.Controls = r.driver.call("drive", track, r.car, r.race)
			traffic(r, c)
			r._now = c
	# 2. every car
	for r in racers:
		r.car.step(track, r._now, dt)
	# 3. solid cars collide
	for k in racers.size():
		var r := racers[k]
		r.solid = not r.race.finished and not r.dnf and r.ghost <= 0.0
		_solid[k] = r.solid
	hits = []
	CarContact.resolve(_cars, _solid, hits)
	var now: Dictionary = {}
	for h: CarContact.Hit in hits:
		var i: int = mini(h.a, h.b)
		var j: int = maxi(h.a, h.b)
		var key: int = i * 64 + j
		now[key] = true
		if not _touching.has(key):
			racers[i].contacts += 1
			racers[j].contacts += 1
			if racers[i].player or racers[j].player:
				player_contacts += 1
			else:
				ai_contacts += 1
	_touching = now
	# 4. the races, the marks, the watchdog
	var events: Array[Dictionary] = []
	for r in racers:
		var ev: Array[Dictionary] = r.race.update(r.car, dt)
		if r.player:
			events = ev
		_mark(r)
		if not r.player and not r.race.finished and not r.dnf:
			_watchdog(r, dt)
		if r.ghost > 0.0:
			r.ghost = CLEAR_TIME if _overlaps_any(r) else r.ghost - dt
	var me := racers[player_index]
	if me.race.finished:
		if player_finished_at < 0.0:
			player_finished_at = time
		elif time - player_finished_at > FINISH_WAIT:
			for r in racers:
				if not r.race.finished:
					r.dnf = true
	return events


## True when every AI car has finished (or is out).
func all_done() -> bool:
	for r in racers:
		if not r.race.finished and not r.dnf:
			return false
	return true


## The car of racer `i` was put back on the road (the player's respawn): not solid until it is clear.
func respawned(i: int) -> void:
	var r := racers[i]
	r.ghost = CLEAR_TIME
	r.watch = PlayMode._new_watch(r.car, r.race.time)
	r.wrong = 0.0
	r.respawn_step = steps
	r.mark_k = -1
	_mark(r)


## Note the race time at the progress marks the car has reached since the last step (the latest pass
## of each mark counts: a car put back drives over its marks again).
func _mark(r: Racer) -> void:
	var k: int = clampi(int(floor(r.car.prog / MARK)), 0, r.marks.size() - 1)
	if r.mark_k < 0:
		r.marks[k] = time
	else:
		for m in range(r.mark_k + 1, k + 1):
			r.marks[m] = time
	r.mark_k = k


## An AI car that is stuck or faces the wrong way goes back to its last checkpoint (standing).
func _watchdog(r: Racer, dt: float) -> void:
	var c := r.car
	var i: int = clampi(c.idx, 0, track.count - 1)
	var dot: float = sin(c.yaw) * track.tx[i] + cos(c.yaw) * track.tz[i]
	r.wrong = r.wrong + dt if dot < WRONG_WAY_DOT else 0.0
	if PlayMode.is_stuck(r.watch, c, r.race) or r.wrong > WRONG_WAY_TIME:
		PlayMode.respawn_car(c, r.race, track, false)
		r.respawns += 1
		r.ghost = CLEAR_TIME
		r.watch = PlayMode._new_watch(c, r.race.time)
		r.wrong = 0.0
		r.respawn_step = steps
		r.mark_k = -1
		_mark(r)


func _overlaps_any(r: Racer) -> bool:
	for o in racers:
		if o != r and not o.race.finished and not o.dnf and CarContact.overlap(r.car, o.car, CLEAR_MARGIN) > 0.0:
			return true
	return false


## The traffic layer on top of an AI's network (see the header): changes `c` in place.
func traffic(r: Racer, c: Car.Controls) -> void:
	var me := r.car
	var fx: float = sin(me.yaw)
	var fz: float = cos(me.yaw)
	var lx: float = fz
	var lz: float = -fx
	var v: float = me.forward_speed
	var look: float = LOOK_BASE + maxf(0.0, v) * LOOK_TIME
	var want: float = INF
	var steer: float = 0.0
	var room_l: float = me._hw - me.lat - me.spec.radius
	var room_r: float = me._hw + me.lat - me.spec.radius
	for o in racers:
		if o == r or not o.solid:
			continue
		var oc := o.car
		var dx: float = oc.x - me.x
		var dz: float = oc.z - me.z
		var along: float = dx * fx + dz * fz
		var side: float = dx * lx + dz * lz
		var reach: float = me.spec.half_length + oc.spec.half_length
		var wide: float = me.spec.radius + oc.spec.radius + LANE_GAP
		if along < -reach or along > look + reach or absf(side) > wide + 2.0:
			continue
		if along > reach * 0.5 and absf(side) < wide:
			# in my lane ahead: ease off towards its speed, and pass where there is room
			var ov: float = oc.vx * fx + oc.vz * fz
			var gap: float = maxf(0.0, along - reach)
			var closing: float = v - ov
			var react: float = closing * REACT_TIME + 2.0
			if closing > 0.0 and gap < react:
				want = minf(want, ov + gap * FOLLOW_K)
				var go: float = -1.0 if side > 0.0 else 1.0
				if absf(side) < 0.4:
					go = 1.0 if room_l > room_r else -1.0
				if (room_l if go > 0.0 else room_r) < PASS_ROOM:
					go = -go
				if (room_l if go > 0.0 else room_r) >= PASS_ROOM:
					steer += go * PASS_STEER * (1.0 - gap / react)
		elif absf(along) <= reach and absf(side) < wide + 0.6:
			# alongside: keep a little apart
			steer += (-1.0 if side > 0.0 else 1.0) * SIDE_STEER
	if want < INF:
		c.throttle = minf(c.throttle, clampf((want - v) * 0.3, -1.0, 1.0))
	if steer != 0.0:
		c.steer = clampf(c.steer + steer, -1.0, 1.0)


# ---------------------------------------------------------------- positions and gaps

## Racer indices in race order, leader first: the finished by their time, then by progress (DNF last).
func standings() -> PackedInt32Array:
	var idx: Array = range(racers.size())
	idx.sort_custom(_ahead)
	return PackedInt32Array(idx)


func _ahead(i: int, j: int) -> bool:
	var a := racers[i]
	var b := racers[j]
	if a.race.finished != b.race.finished:
		return a.race.finished
	if a.race.finished:
		return a.race.finish_time < b.race.finish_time or (a.race.finish_time == b.race.finish_time and a.slot < b.slot)
	if a.dnf != b.dnf:
		return b.dnf
	if a.car.prog != b.car.prog:
		return a.car.prog > b.car.prog
	return a.slot < b.slot


## Racer i's place now (1-based).
func position(i: int) -> int:
	return standings().find(i) + 1


## How many seconds racer `behind` is behind racer `ahead`: the time since `ahead` was where `behind`
## is now (between finished cars: their times; before `ahead` has been there, the distance at
## `behind`'s speed).
func gap(ahead: int, behind: int) -> float:
	var a := racers[ahead]
	var b := racers[behind]
	if a.race.finished and b.race.finished:
		return b.race.finish_time - a.race.finish_time
	var p: float = b.car.prog / MARK
	var k: int = clampi(int(floor(p)), 0, a.marks.size() - 2)
	var t0: float = a.marks[k]
	var t1: float = a.marks[k + 1]
	if t0 >= 0.0 and a.mark_k > k:
		var at: float = t0 + (p - k) * (t1 - t0) if t1 >= t0 else t0
		return maxf(0.0, (b.race.finish_time if b.race.finished else time) - at)
	return maxf(0.0, (a.car.prog - b.car.prog) * track.seg_len / maxf(b.car.speed, 10.0))


## The HUD's field block for racer `me`: {pos, of, rows: [{i, code, name, color, gap (s against
## `me`: - ahead, + behind; null for `me`), me, finished, dnf}] in race order, ahead / behind: {code,
## gap} of the cars next to `me` ({} none)}.
func board(me: int) -> Dictionary:
	var order := standings()
	var at: int = order.find(me)
	var rows: Array = []
	for k in order.size():
		var i: int = order[k]
		var r := racers[i]
		var g: Variant = null
		if k < at:
			g = -gap(i, me)
		elif k > at:
			g = gap(me, i)
		rows.append({i = i, code = code_of(i), name = name_of(i), color = color_of(i), gap = g, me = i == me,
			finished = r.race.finished, dnf = r.dnf})
	var out: Dictionary = {pos = at + 1, of = order.size(), rows = rows, ahead = {}, behind = {}}
	if at > 0:
		out.ahead = {code = code_of(order[at - 1]), gap = gap(order[at - 1], me)}
	if at < order.size() - 1:
		out.behind = {code = code_of(order[at + 1]), gap = gap(me, order[at + 1])}
	return out


## The finish panel's rows in race order: {place, i, name, code, car (name), color, time (s, INF not
## finished), gap (s behind the winner; INF: not finished), me, dnf}.
func results() -> Array[Dictionary]:
	var order := standings()
	var out: Array[Dictionary] = []
	var first: float = racers[order[0]].race.finish_time
	for k in order.size():
		var i: int = order[k]
		var r := racers[i]
		var t: float = r.race.finish_time
		out.append({place = k + 1, i = i, name = name_of(i), code = code_of(i), car = String(Cars.get_car(String(r.car.spec.id)).name),
			color = color_of(i), time = t, gap = t - first if r.race.finished and is_finite(first) else INF, me = r.player, dnf = r.dnf})
	return out


func name_of(i: int) -> String:
	return String(racers[i].info.get("name", "You"))


func code_of(i: int) -> String:
	return String(racers[i].info.get("code", "YOU"))


func color_of(i: int) -> Color:
	var c: Variant = racers[i].info.get("color")
	if c is Color:
		return c
	if c is String:
		return Color(String(c))
	return Color(str(Cars.get_car(String(racers[i].car.spec.id)).get("look", {}).get("color", "#d7263d")))
