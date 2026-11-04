class_name Upgrades
extends RefCounted
## upgrades.gd: car upgrades (v6.11.0): four parts per car, three levels each, bought in order
## with the career's money on the car picker (or with the terminal's `upgrade`).
## ------------------------------------------------------------------
## An upgraded car is its stock spec (sim/cars.gd) with a few numbers scaled, so everything that
## takes a CarSpec (sim/car.gd, the autopilots, FleetSim through Trainer.spec_data) drives it with
## no change of its own. Each level adds `step` × the stock value to what the part changes:
##   engine  the torque curve (+5 % a level: more power everywhere, so quicker acceleration and,
##           where drag holds the car back, a little more top speed)
##   tyres   the asphalt grip (mu, +4 % a level); the grip on dirt and snow stays where it was (the
##           car's shares are divided by the same factor), so each part does one thing
##   nitro   a bigger tank (nitro_time, +10 % a level: the push is the same, it lasts longer) and a
##           faster refill (nitro_refill, +10 % a level: the style score's points refill more of the
##           tank)
##   loose   the grip on dirt and snow (the car's dirt_grip and snow_grip shares, +5 % a level, but
##           never above its asphalt grip: the Dune, which keeps 97 % on dirt, gains 3 % there)
## Never changed: max_speed (it scales the AI's speed input, so a network sees the same range in an
## upgraded car), the mass, the brakes, the steering and the stability control: an upgraded car
## keeps its character. Levels 0, 0, 0, 0 are the stock car itself (Cars.spec(id), the same object),
## so stock runs stay bit for bit what they were.
## Medal times and the AI opponents are always the stock cars' (data/medals.json, data/opponents):
## upgrades make medals and AI wins easier, on purpose; rewards are still paid once.
##
## Prices: level k of a part costs the car's base price × LEVEL_SHARE[k - 1] × the part's `cost`,
## rounded to $50 (the base price is the car's shop price; a car that costs nothing, the Racer,
## counts as FREE_CAR_BASE). Every part of every car costs total_all() (see the README).
## Data-driven: PARTS and LEVEL_SHARE are the whole table; MEASURED is what tools/upgrades.gd
## measured with the real physics for the car picker's bars (`tools/upgrades.gd --check` measures
## again and compares; the tests check each level's gain is in range).
##
##   Upgrades.ids() -> ["engine", "tyres", "nitro", "loose"];  Upgrades.part(id) -> {...} or {}
##   Upgrades.index_of(id) -> 0..3 (-1 unknown);  Upgrades.part_id(word) -> id for a part name
##       or alias ("tires", "grip", "dirt" ...), "" unknown
##   Upgrades.stock() -> PackedInt32Array [0, 0, 0, 0];  Upgrades.is_stock(levels)
##   Upgrades.clean(v) -> PackedInt32Array of 4 levels 0..MAX_LEVEL from anything (junk: 0)
##   Upgrades.changes(car_id, levels) -> the CarSpec fields that differ (JS names)
##   Upgrades.spec(car_id, levels) -> CarSpec (cached; stock levels: Cars.spec(car_id))
##   Upgrades.player_spec(car_id) -> the car with the levels the save file holds
##   Upgrades.price(car_id, part, level) -> $ for that level (1..3), 0 otherwise
##   Upgrades.car_total(car_id) / total_all() -> $ for every level of every part
##   Upgrades.code(levels) -> "E2 T1 N0 L3";  Upgrades.text(levels) -> "engine 2, tyres 1, ..."
##   Upgrades.stats(car_id, levels) -> the car's stats (sim/cars.gd) with the measured upgrades
##   Upgrades.bars(car_id, levels) -> Cars.stat_bars of those stats (the car picker)
##   Upgrades.effect(part, level) -> "+10 % power" (the picker's and the terminal's words)

const MAX_LEVEL: int = 3
## Price of level k (1..3) as a share of the car's base price, × the part's cost.
const LEVEL_SHARE: Array[float] = [0.1, 0.2, 0.35]
## The base price of a car that costs nothing in the shop (the Racer: between the Kestrel and the Drifter).
const FREE_CAR_BASE: int = 12000
## Prices are rounded to this many dollars.
const ROUND: int = 50

## The parts, in the picker's order. step: the share of the stock value each level adds; cost:
## × the car's base price share; alias: other words the terminal takes; what: what it does (one
## line), effect: the picker's "+5 % power" per level ("%d" = the level's percentage).
const PARTS: Array[Dictionary] = [
	{id = "engine", name = "Engine", short = "E", step = 0.05, cost = 1.25, alias = ["power", "motor"],
		what = "more power: quicker acceleration and a little more top speed", effect = "+%d %% power"},
	{id = "tyres", name = "Tyres", short = "T", step = 0.04, cost = 1.0, alias = ["tyre", "tires", "tire"],
		what = "more grip on asphalt: faster corners", effect = "+%d %% asphalt grip"},
	{id = "nitro", name = "Nitro", short = "N", step = 0.1, cost = 0.6, alias = ["tank", "boost"],
		what = "a bigger nitro tank that refills faster", effect = "+%d %% tank and refill"},
	{id = "loose", name = "Loose grip", short = "L", step = 0.05, cost = 0.75, alias = ["grip", "dirt", "snow", "rally"],
		what = "more grip on dirt and snow (never above the car's asphalt grip)", effect = "+%d %% dirt and snow grip"},
]

## Measured with the real physics by tools/upgrades.gd (tools/car_stats.gd's measurements of the
## upgraded specs): per car, the engine's levels 1-3 {top, accel100, accel200} and the tyres'
## levels 1-3 {grip, gripFast}; the car picker's bars use them. Filled by the tool; tests check it.
const MEASURED: Dictionary = {
	racer = {
		engine = [{top = 282.7, accel100 = 2.57, accel200 = 9.23}, {top = 286.2, accel100 = 2.47, accel200 = 8.77}, {top = 289.5, accel100 = 2.37, accel200 = 8.33}],
		tyres = [{grip = 1.75, gripFast = 1.64}, {grip = 1.82, gripFast = 1.7}, {grip = 1.89, gripFast = 1.73}],
	},
	kestrel = {
		engine = [{top = 233, accel100 = 2.35, accel200 = 10.52}, {top = 235.6, accel100 = 2.27, accel200 = 9.87}, {top = 237.7, accel100 = 2.2, accel200 = 9.3}],
		tyres = [{grip = 1.85, gripFast = 1.65}, {grip = 1.93, gripFast = 1.68}, {grip = 2, gripFast = 1.71}],
	},
	thunder = {
		engine = [{top = 318.7, accel100 = 2.58, accel200 = 7.8}, {top = 323.8, accel100 = 2.52, accel200 = 7.48}, {top = 327.9, accel100 = 2.47, accel200 = 7.18}],
		tyres = [{grip = 1.53, gripFast = 1.62}, {grip = 1.62, gripFast = 1.68}, {grip = 1.69, gripFast = 1.74}],
	},
	drifter = {
		engine = [{top = 268.5, accel100 = 2.45, accel200 = 8.77}, {top = 272.3, accel100 = 2.38, accel200 = 8.35}, {top = 275.7, accel100 = 2.35, accel200 = 7.98}],
		tyres = [{grip = 1.68, gripFast = 1.58}, {grip = 1.75, gripFast = 1.61}, {grip = 1.82, gripFast = 1.67}],
	},
	dune = {
		engine = [{top = 225.8, accel100 = 2.78, accel200 = 11.73}, {top = 228.9, accel100 = 2.72, accel200 = 10.95}, {top = 231.6, accel100 = 2.67, accel200 = 10.28}],
		tyres = [{grip = 1.78, gripFast = 1.48}, {grip = 1.85, gripFast = 1.56}, {grip = 1.92, gripFast = 1.58}],
	},
	vortex = {
		engine = [{top = 328.5, accel100 = 2.45, accel200 = 5.92}, {top = 335.3, accel100 = 2.33, accel200 = 5.63}, {top = 342, accel100 = 2.25, accel200 = 5.4}],
		tyres = [{grip = 1.75, gripFast = 1.85}, {grip = 1.82, gripFast = 1.92}, {grip = 1.9, gripFast = 1.98}],
	},
}

static var _specs: Dictionary = {}
static var _mutex: Mutex = Mutex.new()
static var _index: Dictionary = _make_index()


static func _make_index() -> Dictionary:
	var out: Dictionary = {}
	for i in PARTS.size():
		out[String(PARTS[i].id)] = i
	return out


static func ids() -> PackedStringArray:
	var out: PackedStringArray = []
	for p: Dictionary in PARTS:
		out.append(String(p.id))
	return out


static func part(id: String) -> Dictionary:
	var i: int = index_of(id)
	return PARTS[i] if i >= 0 else {}


static func index_of(id: String) -> int:
	return int(_index.get(id, -1))


## The part id for a word the player typed: an id, a name or an alias, any case ("" unknown).
static func part_id(word: String) -> String:
	var w: String = word.strip_edges().to_lower()
	for p: Dictionary in PARTS:
		if w == String(p.id) or w == String(p.name).to_lower() or w == String(p.name).to_lower().replace(" ", "") or (p.alias as Array).has(w):
			return String(p.id)
	return ""


static func stock() -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(PARTS.size())
	return out


static func is_stock(levels: PackedInt32Array) -> bool:
	for l in levels:
		if l != 0:
			return false
	return true


## Four levels 0..MAX_LEVEL from an array (a save file's list: numbers; anything else reads as 0).
static func clean(v: Variant) -> PackedInt32Array:
	var out: PackedInt32Array = stock()
	if v is Array or v is PackedInt32Array or v is PackedFloat64Array or v is PackedInt64Array:
		var a: Array = Array(v)
		for i in mini(a.size(), PARTS.size()):
			var x: Variant = a[i]
			if (x is int or x is float) and is_finite(float(x)):
				out[i] = clampi(int(x), 0, MAX_LEVEL)
	return out


## The share of the stock value part `i` adds at `level` (0.15 for the engine at level 3).
static func gain(i: int, level: int) -> float:
	return float(PARTS[i].step) * clampi(level, 0, MAX_LEVEL)


## The CarSpec fields an upgraded car changes, with the JS names (CarSpec.make() takes them).
## Stock levels: {}.
static func changes(car_id: String, levels: PackedInt32Array) -> Dictionary:
	var lv: PackedInt32Array = clean(levels)
	var s: CarSpec = Cars.spec(car_id)
	var out: Dictionary = {}
	var e: float = gain(0, lv[0])
	var t: float = gain(1, lv[1])
	var n: float = gain(2, lv[2])
	var l: float = gain(3, lv[3])
	if e > 0.0:
		var tq: Array = []
		for p: Variant in s.torque:
			tq.append([float(p[0]), float(p[1]) * (1.0 + e)])
		out.torque = tq
	if t > 0.0:
		out.mu = s.mu * (1.0 + t)
	if t > 0.0 or l > 0.0:
		# the shares of the (upgraded) asphalt grip: the loose part raises them, never above 1
		# (as much grip as on asphalt), and the tyres' factor comes off again, so the grip on
		# dirt and snow is mu × share × (1 + l) whatever the tyres
		out.dirtGrip = minf(1.0, s.dirt_grip * (1.0 + l)) / (1.0 + t)
		out.snowGrip = minf(1.0, s.snow_grip * (1.0 + l)) / (1.0 + t)
	if n > 0.0:
		out.nitroTime = s.nitro_time * (1.0 + n)
		out.nitroRefill = s.nitro_refill * (1.0 + n)
	return out


## Car `car_id` with `levels` (4 ints: engine, tyres, nitro, loose). Stock levels give the stock
## spec itself; others are made once and cached (a spec is read-only once a car uses it).
static func spec(car_id: String, levels: PackedInt32Array = PackedInt32Array()) -> CarSpec:
	var id: String = car_id if Cars.has_car(car_id) else Cars.DEFAULT_CAR
	var lv: PackedInt32Array = clean(levels)
	if is_stock(lv):
		return Cars.spec(id)
	var key: String = "%s:%s" % [id, ",".join(Array(lv).map(func(x: int) -> String: return str(x)))]
	_mutex.lock()
	var s: Variant = _specs.get(key)
	if s == null:
		var ch: Dictionary = changes(id, lv)
		ch.id = id
		s = CarSpec.make(ch, Cars.spec(id))
		_specs[key] = s
	_mutex.unlock()
	return s


## The player's car `car_id` with the levels bought for it (the save file's; stock when none).
static func player_spec(car_id: String) -> CarSpec:
	return spec(car_id, SaveData.get_upgrades(car_id))


## What car `car_id` counts as when pricing its upgrades.
static func base_price(car_id: String) -> int:
	var p: int = int(Cars.get_car(car_id).get("price", 0)) if Cars.has_car(car_id) else 0
	return p if p > 0 else FREE_CAR_BASE


## The price of level `level` (1..MAX_LEVEL) of part `part_id` for car `car_id`; 0 otherwise.
static func price(car_id: String, part_id: String, level: int) -> int:
	var i: int = index_of(part_id)
	if i < 0 or level < 1 or level > MAX_LEVEL or not Cars.has_car(car_id):
		return 0
	var v: float = base_price(car_id) * LEVEL_SHARE[level - 1] * float(PARTS[i].cost)
	return roundi(v / ROUND) * ROUND


## Every level of every part of car `car_id`.
static func car_total(car_id: String) -> int:
	var out: int = 0
	for p: String in ids():
		for k in range(1, MAX_LEVEL + 1):
			out += price(car_id, p, k)
	return out


## Every level of every part of every car.
static func total_all() -> int:
	var out: int = 0
	for id: String in Cars.ids():
		out += car_total(id)
	return out


## "E2 T1 N0 L3" (records, the terminal).
static func code(levels: PackedInt32Array) -> String:
	var lv: PackedInt32Array = clean(levels)
	var parts: PackedStringArray = []
	for i in PARTS.size():
		parts.append("%s%d" % [PARTS[i].short, lv[i]])
	return " ".join(parts)


## "engine 2, tyres 1, nitro 0, loose grip 3", or "stock".
static func text(levels: PackedInt32Array) -> String:
	var lv: PackedInt32Array = clean(levels)
	if is_stock(lv):
		return "stock"
	var parts: PackedStringArray = []
	for i in PARTS.size():
		parts.append("%s %d" % [String(PARTS[i].name).to_lower(), lv[i]])
	return ", ".join(parts)


## What `level` of part `part_id` adds over the stock car, in words ("+10 % power"; "stock" at 0).
static func effect(part_id: String, level: int) -> String:
	var i: int = index_of(part_id)
	if i < 0 or level <= 0:
		return "stock"
	return String(PARTS[i].effect) % roundi(gain(i, level) * 100.0)


## The car's stats (sim/cars.gd `stats`) with the measured effect of the engine and the tyres
## (MEASURED) and the nitro tank's length; the other numbers stay the stock car's.
static func stats(car_id: String, levels: PackedInt32Array) -> Dictionary:
	var out: Dictionary = (Cars.get_car(car_id).stats as Dictionary).duplicate()
	var lv: PackedInt32Array = clean(levels)
	var m: Dictionary = MEASURED.get(car_id, {})
	if lv[0] > 0 and m.get("engine") is Array and (m.engine as Array).size() >= lv[0]:
		out.merge(m.engine[lv[0] - 1], true)
	if lv[1] > 0 and m.get("tyres") is Array and (m.tyres as Array).size() >= lv[1]:
		out.merge(m.tyres[lv[1] - 1], true)
	if lv[2] > 0:
		out.tankTime = float(out.tankTime) * (1.0 + gain(2, lv[2]))
	return out


## The car picker's bars of car `car_id` with `levels` (Cars.stat_bars of stats()).
static func bars(car_id: String, levels: PackedInt32Array) -> Dictionary:
	return Cars.stat_bars(stats(car_id, levels), spec(car_id, levels))
