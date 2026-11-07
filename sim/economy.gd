class_name Economy
extends RefCounted
## economy.gd: money and career points (v6.5.0): the reward table, the payouts, the car shop.
## ------------------------------------------------------------------
## You earn money and points by beating medal times and AI opponents (sim/opponents.gd). Each
## reward is paid once per track, car and medal (or AI level): a better time or a harder AI
## pays what you had not been paid yet, the same result again pays nothing. A medal pays the
## medals below it too (a gold time is a silver and a bronze time), and beating an AI level
## pays the levels below it on that track with that car (they are slower: their times are fixed
## and known, so you would have beaten them too). Later tracks pay more: track k (0-based, menu
## order) pays × (1 + TRACK_STEP × k). Money buys cars (the car picker's shop: Cars DEFS
## `price`; a car that costs 0 is owned from the start, the Racer). Points are a career total
## and buy nothing; they are not the style score of one run (sim/score.gd).
## Data-driven: REWARDS is the whole reward table, in one place.
##
##   Economy.reward(track_id, id) -> {money, points} for one reward on a track ({} unknown id)
##   Economy.payout(track_id, medal, beaten, paid) -> {items [{id, kind, label, money, points}],
##       money, points, repeat [ids earned again but paid before]}   (pure: nothing is saved)
##   Economy.claim(track_id, car_id, medal, beaten) -> payout(), paid into the save file
##   Economy.price(car_id) -> int;  Economy.owns(car_id) -> bool
##   Economy.buy(car_id) -> {ok, error ("" | "owned" | "money" | "unknown"), price, short (money missing)}
##   Economy.money() / Economy.points() (the save file's career, SaveData.get_money ...)
##   Economy.career(scenario) -> the money a player who always earns `scenario` makes, track by
##       track (the price check in tests/test_sim.gd and the README)
##   Economy.upgrade_price(car_id, part) -> the price of the part's next level (0: at the top level)
##   Economy.buy_upgrade(car_id, part) -> {ok, error ("" | "locked" | "max" | "money" | "unknown"),
##       price, level (the part's level now), short (money missing)}  (v6.11.0, sim/upgrades.gd)
## Reward ids: the medal ids (Medals.ORDER: "bronze" ... "author") and "ai-" + an AI level id
## ("ai-rookie" ... "ai-elite").
## v6.13.0, Race the field (sim/field.gd): a finishing place in a field of a level pays too, from
## FIELD_PLACES × FIELD_LEVELS[level] (× the track's scale), and like a medal it pays the places below
## it (2nd pays 5th, 4th, 3rd and 2nd; last pays nothing): once per track, car, field level and place,
## so a better place later pays only the difference. Reward ids "field-" + level + "-" + place
## ("field-pro-1"). The medal the run's time won is paid as in Drive.
##   Economy.payout(track_id, medal, beaten, paid, field_level, place) / claim(..., field_level, place)
##   Economy.field_ids(field_level, place) -> the place rewards a finish earns
## v6.14.0, championships (sim/cups.gd): the end of a cup pays by your place in its standings, from
## CUP_PLACES × FIELD_LEVELS[level] × the cup's scale (1 + CUP_STEP × its index: later cups pay more),
## and like a place in a field it pays the places below it (2nd pays 4th, 3rd and 2nd; 5th and 6th pay
## nothing): once per cup, level and place (not per car or track), so a better place later pays only
## the difference. Reward ids "cup-" + cup + "-" + level + "-" + place ("cup-rookie-pro-1"), kept in the
## save file's career.cups.paid. Each race of a cup pays as a field race on top of it.
##   Economy.cup_ids(cup_id, level, place) -> the cup rewards a final place earns
##   Economy.cup_reward(id) -> {money, points} ({} unknown);  Economy.cup_scale(cup_id)
##   Economy.cup_payout(cup_id, level, place, paid) -> {items [{id, kind "cup", label, money, points}],
##       money, points, repeat}  (pure)
##   Economy.claim_cup(cup_id, level, place) -> cup_payout(), paid into the save file with the trophy
##       (SaveData.finish_cup), with money_total and points_total

## Every reward on the first track; track k pays × (1 + TRACK_STEP × k) (money rounded to 10,
## points to a whole number).
const REWARDS: Dictionary = {
	"bronze": {"money": 300, "points": 10},
	"silver": {"money": 500, "points": 20},
	"gold": {"money": 800, "points": 40},
	"author": {"money": 1200, "points": 80},
	"ai-rookie": {"money": 200, "points": 5},
	"ai-amateur": {"money": 400, "points": 10},
	"ai-pro": {"money": 700, "points": 20},
	"ai-expert": {"money": 1100, "points": 40},
	"ai-elite": {"money": 1600, "points": 80},
}
const TRACK_STEP: float = 0.1
const AI_PREFIX: String = "ai-"
## (v6.13) Race the field: what each place adds on the first track at a level of × 1 (the worse places
## first: a place pays its own and every worse one's), and each field level's factor.
const FIELD_PLACES: Array[Dictionary] = [
	{"place": 5, "money": 60, "points": 1},
	{"place": 4, "money": 90, "points": 2},
	{"place": 3, "money": 150, "points": 4},
	{"place": 2, "money": 250, "points": 8},
	{"place": 1, "money": 450, "points": 15},
]
const FIELD_LEVELS: Dictionary = {"rookie": 0.6, "amateur": 1.0, "pro": 1.5, "expert": 2.1, "elite": 3.0}
const FIELD_PREFIX: String = "field-"
## (v6.14) The end of a cup: what each place in its standings adds in the first cup at a level of × 1
## (the worse places first: a place pays its own and every worse one's), and the step per cup.
const CUP_PLACES: Array[Dictionary] = [
	{"place": 4, "money": 300, "points": 5},
	{"place": 3, "money": 700, "points": 15},
	{"place": 2, "money": 1200, "points": 30},
	{"place": 1, "money": 2000, "points": 60},
]
const CUP_STEP: float = 0.25
const CUP_PREFIX: String = "cup-"
## The medals in the order they are earned (slowest first).
const MEDALS_UP: PackedStringArray = ["bronze", "silver", "gold", "author"]


## How much track `track_id` pays: 1 + TRACK_STEP × its menu index (unknown tracks: 1).
static func track_scale(track_id: String) -> float:
	return 1.0 + TRACK_STEP * maxi(0, Tracks.index_of(track_id))


## One reward on a track: {money, points}, or {} for an unknown reward id.
static func reward(track_id: String, id: String) -> Dictionary:
	var r: Variant = REWARDS.get(id)
	var s: float = track_scale(track_id)
	if id.begins_with(FIELD_PREFIX):
		var f: Dictionary = _field_reward(id)
		if f.is_empty():
			return {}
		r = f
		s *= float(f.scale)
	if not (r is Dictionary):
		return {}
	return {money = roundi(float(r.money) * s / 10.0) * 10, points = roundi(float(r.points) * s)}


## A field reward id's {money, points (before any scale), scale (its level's), level, place}, or {}.
static func _field_reward(id: String) -> Dictionary:
	var parts: PackedStringArray = id.substr(FIELD_PREFIX.length()).split("-")
	if parts.size() != 2 or not FIELD_LEVELS.has(parts[0]) or not parts[1].is_valid_int():
		return {}
	var place: int = parts[1].to_int()
	for p: Dictionary in FIELD_PLACES:
		if int(p.place) == place:
			return {money = p.money, points = p.points, scale = FIELD_LEVELS[parts[0]], level = parts[0], place = place}
	return {}


## The place rewards a field finish earns: field level `field_level`, place `place` (1 = won) and every
## worse place that pays (none for an unknown level or a place that pays nothing).
static func field_ids(field_level: String, place: int) -> PackedStringArray:
	var out: PackedStringArray = []
	if not FIELD_LEVELS.has(field_level) or place < 1:
		return out
	for p: Dictionary in FIELD_PLACES:
		if int(p.place) >= place:
			out.append("%s%s-%d" % [FIELD_PREFIX, field_level, int(p.place)])
	return out


## The reward ids a run earns: the medal `medal` and those below it, then the AI level `beaten`
## and those below it ("" for none).
static func earned_ids(medal: String, beaten: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var m: int = MEDALS_UP.find(medal)
	for k in m + 1:
		out.append(MEDALS_UP[k])
	var b: int = Opponents.rank(beaten)
	for k in b + 1:
		out.append(AI_PREFIX + Opponents.ids()[k])
	return out


## What a run on track `track_id` earns: the medal its time won (`medal`, "" none) and the AI
## level it beat (`beaten`, "" none), less what was paid before (`paid`: reward ids).
## {items: [{id, kind ("medal" | "ai"), label, money, points}], money, points, repeat: [ids]}.
## (v6.13) `field_level` and `place`: a field race's level and the player's place (1 = won; "" / 0: not a
## field race); its place rewards follow the medal's (kind "field").
static func payout(track_id: String, medal: String, beaten: String, paid: PackedStringArray, field_level: String = "", place: int = 0) -> Dictionary:
	var items: Array = []
	var repeat: PackedStringArray = []
	var money: int = 0
	var points: int = 0
	var ids: PackedStringArray = earned_ids(medal, beaten)
	ids.append_array(field_ids(field_level, place))
	for id: String in ids:
		if paid.has(id):
			repeat.append(id)
			continue
		var r: Dictionary = reward(track_id, id)
		var kind: String = "ai" if id.begins_with(AI_PREFIX) else ("field" if id.begins_with(FIELD_PREFIX) else "medal")
		items.append({id = id, kind = kind, label = label(id), money = r.money, points = r.points})
		money += int(r.money)
		points += int(r.points)
	return {items = items, money = money, points = points, repeat = repeat}


## A reward's name for the finish panel: "Gold medal", "Beat the Pro AI", "Pro field: 2nd",
## (v6.14) "Rookie Cup (Pro): 1st".
static func label(id: String) -> String:
	if id.begins_with(CUP_PREFIX):
		var c: Dictionary = _cup_reward(id)
		if not c.is_empty():
			return "%s (%s): %s" % [Cups.name_of(String(c.cup)), Opponents.level_name(String(c.level)), Field.place_name(int(c.place))]
	if id.begins_with(FIELD_PREFIX):
		var f: Dictionary = _field_reward(id)
		if not f.is_empty():
			return "%s field: %s" % [Opponents.level_name(String(f.level)), Field.place_name(int(f.place))]
	if id.begins_with(AI_PREFIX):
		return "Beat the %s AI" % Opponents.level_name(id.substr(AI_PREFIX.length()))
	return "%s medal" % String(Medals.NAMES.get(id, id.capitalize()))


## payout() for a finished run, paid into the save file (once: the ids are remembered per track
## and car). Returns the payout, with `money_total` and `points_total` after it.
static func claim(track_id: String, car_id: String, medal: String, beaten: String, field_level: String = "", place: int = 0) -> Dictionary:
	var p: Dictionary = payout(track_id, medal, beaten, SaveData.paid_rewards(track_id, car_id), field_level, place)
	var ids: PackedStringArray = []
	for it: Dictionary in p.items:
		ids.append(String(it.id))
	if not ids.is_empty():
		SaveData.pay_rewards(track_id, car_id, ids, int(p.money), int(p.points))
	p.money_total = SaveData.get_money()
	p.points_total = SaveData.get_points()
	return p


# ---------------------------------------------------------------- championships (v6.14.0)

## How much cup `cup_id` pays: 1 + CUP_STEP × its index (sim/cups.gd order; unknown: 1).
static func cup_scale(cup_id: String) -> float:
	return 1.0 + CUP_STEP * maxi(0, Cups.index_of(cup_id))


## A cup reward id's {cup, level, place, money, points (before any scale)}, or {} ("cup-<cup>-<level>-<place>";
## cup ids may hold "-", so it is read from the end).
static func _cup_reward(id: String) -> Dictionary:
	if not id.begins_with(CUP_PREFIX):
		return {}
	var parts: PackedStringArray = id.substr(CUP_PREFIX.length()).rsplit("-", true, 2)
	if parts.size() != 3 or Cups.cup(parts[0]).is_empty() or not FIELD_LEVELS.has(parts[1]) or not parts[2].is_valid_int():
		return {}
	var place: int = parts[2].to_int()
	for p: Dictionary in CUP_PLACES:
		if int(p.place) == place:
			return {cup = parts[0], level = parts[1], place = place, money = p.money, points = p.points}
	return {}


## One cup reward: {money, points}, or {} for an unknown id.
static func cup_reward(id: String) -> Dictionary:
	var c: Dictionary = _cup_reward(id)
	if c.is_empty():
		return {}
	var s: float = cup_scale(String(c.cup)) * float(FIELD_LEVELS[c.level])
	return {money = roundi(float(c.money) * s / 10.0) * 10, points = roundi(float(c.points) * s)}


## The cup rewards finishing a cup's standings in `place` earns (that place and every worse one that pays).
static func cup_ids(cup_id: String, level: String, place: int) -> PackedStringArray:
	var out: PackedStringArray = []
	if Cups.cup(cup_id).is_empty() or not FIELD_LEVELS.has(level) or place < 1:
		return out
	for p: Dictionary in CUP_PLACES:
		if int(p.place) >= place:
			out.append("%s%s-%s-%d" % [CUP_PREFIX, cup_id, level, int(p.place)])
	return out


## What `place` in cup `cup_id`'s standings at `level` earns, less what was paid before (`paid`).
static func cup_payout(cup_id: String, level: String, place: int, paid: PackedStringArray) -> Dictionary:
	var items: Array = []
	var repeat: PackedStringArray = []
	var money: int = 0
	var points: int = 0
	for id: String in cup_ids(cup_id, level, place):
		if paid.has(id):
			repeat.append(id)
			continue
		var r: Dictionary = cup_reward(id)
		items.append({id = id, kind = "cup", label = label(id), money = r.money, points = r.points})
		money += int(r.money)
		points += int(r.points)
	return {items = items, money = money, points = points, repeat = repeat}


## The end of a cup: cup_payout() paid into the save file, with the trophy (the best place in that cup
## at that level is kept: SaveData.finish_cup). Returns the payout with money_total and points_total.
static func claim_cup(cup_id: String, level: String, place: int) -> Dictionary:
	var p: Dictionary = cup_payout(cup_id, level, place, SaveData.cup_paid())
	var ids: PackedStringArray = []
	for it: Dictionary in p.items:
		ids.append(String(it.id))
	SaveData.finish_cup(cup_id, level, place, ids, int(p.money), int(p.points))
	p.money_total = SaveData.get_money()
	p.points_total = SaveData.get_points()
	return p


# ---------------------------------------------------------------- the car shop

## What car `car_id` costs (0: owned from the start).
static func price(car_id: String) -> int:
	return int(Cars.get_car(car_id).get("price", 0)) if Cars.has_car(car_id) else 0


static func owns(car_id: String) -> bool:
	return SaveData.owns_car(car_id)


static func money() -> int:
	return SaveData.get_money()


static func points() -> int:
	return SaveData.get_points()


## Buy car `car_id` with the career's money: {ok, error: "" | "owned" (already yours) | "money"
## (not enough: `short` is how much is missing) | "unknown", price}.
static func buy(car_id: String) -> Dictionary:
	if not Cars.has_car(car_id):
		return {ok = false, error = "unknown", price = 0, short = 0}
	var p: int = price(car_id)
	var err: String = SaveData.purchase_car(car_id, p)
	return {ok = err == "", error = err, price = p, short = maxi(0, p - SaveData.get_money()) if err == "money" else 0}


# ---------------------------------------------------------------- car upgrades (v6.11.0)

## The price of the next level of part `part` on car `car_id` with the levels bought (0 when the
## part is at its top level or the car or part is unknown).
static func upgrade_price(car_id: String, part: String) -> int:
	var i: int = Upgrades.index_of(part)
	if i < 0 or not Cars.has_car(car_id):
		return 0
	return Upgrades.price(car_id, part, SaveData.get_upgrades(car_id)[i] + 1)


## Buy the next level of part `part` for car `car_id` (only an owned car, one level at a time, in
## order): {ok, error: "" | "locked" (buy the car first) | "max" (every level bought) | "money" (not
## enough: `short`) | "unknown", price, level (the part's level after it)}.
static func buy_upgrade(car_id: String, part: String) -> Dictionary:
	var i: int = Upgrades.index_of(part)
	if i < 0 or not Cars.has_car(car_id):
		return {ok = false, error = "unknown", price = 0, level = 0, short = 0}
	var now: int = SaveData.get_upgrades(car_id)[i]
	var p: int = Upgrades.price(car_id, part, now + 1)
	var err: String = SaveData.purchase_upgrade(car_id, part, now + 1, p)
	return {ok = err == "", error = err, price = p if err != "max" else 0, level = SaveData.get_upgrades(car_id)[i],
		short = maxi(0, p - SaveData.get_money()) if err == "money" else 0}


# ---------------------------------------------------------------- balance

## The money a player makes driving the tracks in menu order, earning on each the medal
## scenario.medal and beating the AI level scenario.ai ("" none): the running total after each
## track (PackedInt32Array, one per track).
static func career(scenario: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array()
	var total: int = 0
	for id: String in Tracks.ids():
		total += int(payout(id, String(scenario.get("medal", "")), String(scenario.get("ai", "")), PackedStringArray()).money)
		out.append(total)
	return out
