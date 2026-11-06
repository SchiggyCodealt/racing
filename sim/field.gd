class_name Field
extends RefCounted
## field.gd (v6.13.0): Race the field, the data: the AI drivers, their pace, the starting grid.
## ------------------------------------------------------------------
## A field race is you against AI_COUNT AI drivers on one track, with solid cars (sim/car_contact.gd)
## and a two-wide staggered grid; sim/field_race.gd runs it. The player picks a field level on the menu
## (Rookie to Elite, the AI opponents' levels of sim/opponents.gd). Data-driven: the roster, the paces
## and the grid are the tables below.
##
## The drivers: DRIVERS is the roster (a name, a three-letter code for the standings, a car and a paint
## colour); a race takes AI_COUNT of them, in an order shuffled by the track and the level (so the same
## race has the same field every time, and another track another one). Each drives the shipped AI
## opponent network of its car on that track (data/opponents) with a speed cap of its own.
##
## The pace: grid slot k (0 = pole) aims at PACE[k] × the level's finish time with YOUR car on that
## track (Opponents.time_of), so a Pro field is about Pro pace for the car you drive whatever the AI
## drive: the pole sitter is the slowest (1.08 ×), the last AI on the grid the fastest (1.0 × : beating
## it is beating the level). A driver's speed cap comes from its car's measured levels on that track
## (cap_for: between two levels, log-interpolated; slower than the Rookie, the Rookie's cap scaled down).
## A car that can't reach its driver's pace on that track even at Elite (a Dune against your Vortex's
## author time) is swapped for your car, so the field stays close.
##
## The grid: the player starts last, on the usual start spot (track.start_idx, in the right-hand lane),
## so a field race covers the same distance as Drive and its time counts for medals, records and
## unlocks; the AI start ahead of you, SLOT_GAP m apart, alternating left and right of the centre line
## (LANE m, at most 40 % of the half width), the slowest at the front.
##
##   Field.lineup(track_id, level, player_car) -> [{slot, id, name, code, car, color, cap (m/s, INF none),
##       pace (expected finish time alone, s), target (the pace it aims at, s)}] (AI_COUNT, pole first;
##       [] when the track has no AI opponents for the player's car)
##   Field.cap_for(track_id, car_id, time) -> the speed cap for a finish time (INF: none; -1: no data)
##   Field.grid(track, n) -> [{idx, lat, x, z, yaw}] for n cars, pole first (the last is the player's)
##   Field.place_name(p) -> "1st", "2nd" ...

const AI_COUNT: int = 5
## The roster: id, name, code (standings), car (sim/cars.gd id), color (paint).
const DRIVERS: Array[Dictionary] = [
	{id = "brandt", name = "Ada Brandt", code = "BRA", car = "kestrel", color = "#eef0f2"},
	{id = "vance", name = "Rico Vance", code = "VAN", car = "thunder", color = "#2b2e36"},
	{id = "park", name = "Juno Park", code = "PAR", car = "drifter", color = "#d63af9"},
	{id = "reyes", name = "Sol Reyes", code = "REY", car = "dune", color = "#c8a96a"},
	{id = "ostrom", name = "Kai Ostrom", code = "OST", car = "vortex", color = "#6f4cff"},
	{id = "moreau", name = "Tess Moreau", code = "MOR", car = "racer", color = "#ff6fae"},
	{id = "haugen", name = "Nils Haugen", code = "HAU", car = "kestrel", color = "#24408e"},
	{id = "fox", name = "Lena Fox", code = "FOX", car = "drifter", color = "#b5652b"},
]
## Each AI grid slot's pace (pole first) × the level's finish time with the player's car.
const PACE: PackedFloat64Array = [1.08, 1.06, 1.04, 1.02, 1.0]
## m between two grid slots (one behind the other, alternating sides: rows 2 × SLOT_GAP apart).
const SLOT_GAP: float = 10.0
## m either side of the centre line (at most LANE_SHARE of the road's half width).
const LANE: float = 3.0
const LANE_SHARE: float = 0.4
## The lowest speed cap a driver gets (m/s).
const MIN_CAP: float = 8.0
## A level without a cap counts as this × the power law's cap for its time (cap_for).
const FREE_CAP: float = 1.1


## A stable number from a text (the shuffle's seed: the same on every machine and Godot version).
static func _seed(text: String) -> int:
	var h: int = 2166136261
	for k in text.length():
		h = ((h ^ text.unicode_at(k)) * 16777619) & 0xFFFFFFFF
	return h


## The field of a race: AI_COUNT drivers, pole first (see the header).
static func lineup(track_id: String, level: String, player_car: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var base: float = Opponents.time_of(track_id, player_car, level)
	if base <= 0.0:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed("%s|%s" % [track_id, level])
	var order: Array = range(DRIVERS.size())
	for k in range(order.size() - 1, 0, -1): # (Fisher-Yates with the seeded generator)
		var j: int = rng.randi_range(0, k)
		var x: int = order[k]
		order[k] = order[j]
		order[j] = x
	for k in AI_COUNT:
		var d: Dictionary = DRIVERS[order[k]]
		var target: float = PACE[k] * base
		var car: String = String(d.car)
		var fastest: float = Opponents.time_of(track_id, car, "elite")
		if fastest <= 0.0 or fastest > target * 1.0001 or Opponents.cap_of(track_id, car, level) < 0.0:
			car = player_car # (can't keep up: drives your car)
			fastest = Opponents.time_of(track_id, car, "elite")
		out.append({slot = k, id = d.id, name = d.name, code = d.code, car = car, color = d.color,
			cap = cap_for(track_id, car, target), pace = maxf(target, fastest), target = target})
	return out


## The speed cap (m/s) that makes the car's AI opponent network finish in about `time` on the track:
## log-interpolated between the two levels around it, the Rookie's cap × its time / `time` below it,
## the Elite's cap above it. A level without a cap (the network flat out) counts as the cap the power
## law through the two levels below it gives for its time, × FREE_CAP (the time gained flattens out as the
## cap nears the speeds the network reaches; measured on the levels that have a cap: within about 5 %),
## at most the car's max_speed. INF: no cap; -1: no opponents for this track and car.
static func cap_for(track_id: String, car_id: String, time: float) -> float:
	var ids: PackedStringArray = Opponents.ids()
	var times: PackedFloat64Array = []
	var caps: PackedFloat64Array = []
	var top: float = Cars.spec(car_id).max_speed
	for id: String in ids:
		var t: float = Opponents.time_of(track_id, car_id, id)
		var c: float = Opponents.cap_of(track_id, car_id, id)
		if t <= 0.0 or c < 0.0:
			return -1.0
		if c == INF and caps.size() >= 2:
			# time ∝ cap^-p through the two levels below, p from them
			var c1: float = caps[caps.size() - 2]
			var c2: float = caps[caps.size() - 1]
			var t1: float = times[times.size() - 2]
			var t2: float = times[times.size() - 1]
			var p: float = log(t1 / t2) / log(c2 / c1) if c2 > c1 and t1 > t2 else 1.0
			c = c2 * pow(t2 / t, 1.0 / maxf(0.2, p)) * FREE_CAP
		times.append(t)
		caps.append(minf(c, top))
	var n: int = times.size()
	if time >= times[0]:
		return maxf(MIN_CAP, caps[0] * times[0] / time)
	if time <= times[n - 1]:
		return Opponents.cap_of(track_id, car_id, ids[n - 1])
	for k in n - 1:
		if time <= times[k] and time >= times[k + 1]:
			var span: float = log(times[k] / times[k + 1])
			var f: float = log(times[k] / time) / span if span > 0.0 else 1.0
			var c: float = exp(log(caps[k]) + f * (log(caps[k + 1]) - log(caps[k])))
			return INF if c >= top else c
	return INF


## The starting grid for n cars, pole first, the last on the usual start spot (see the header):
## [{idx (sample), lat (m, + = left), x, z, yaw}].
static func grid(t: BuiltTrack, n: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var step: int = maxi(1, roundi(SLOT_GAP / t.seg_len))
	for k in n:
		var back: int = n - 1 - k # (slots from the last one)
		var i: int = t.start_idx + back * step
		if t.closed:
			i = t.wrap(i)
		else:
			i = mini(i, t.count - 2)
		var side: float = 1.0 if back % 2 == 1 else -1.0
		var lat: float = side * minf(LANE, LANE_SHARE * t.hw[i])
		out.append({idx = i, lat = lat, x = t.px[i] + t.nx[i] * lat, z = t.pz[i] + t.nz[i] * lat, yaw = atan2(t.tx[i], t.tz[i])})
	return out


## "1st", "2nd", "3rd", "4th" ...
static func place_name(p: int) -> String:
	var suffix := "th"
	if p % 100 < 11 or p % 100 > 13:
		match p % 10:
			1:
				suffix = "st"
			2:
				suffix = "nd"
			3:
				suffix = "rd"
	return "%d%s" % [p, suffix]
