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
## Reward ids: the medal ids (Medals.ORDER: "bronze" ... "author") and "ai-" + an AI level id
## ("ai-rookie" ... "ai-elite").

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
## The medals in the order they are earned (slowest first).
const MEDALS_UP: PackedStringArray = ["bronze", "silver", "gold", "author"]


## How much track `track_id` pays: 1 + TRACK_STEP × its menu index (unknown tracks: 1).
static func track_scale(track_id: String) -> float:
	return 1.0 + TRACK_STEP * maxi(0, Tracks.index_of(track_id))


## One reward on a track: {money, points}, or {} for an unknown reward id.
static func reward(track_id: String, id: String) -> Dictionary:
	var r: Variant = REWARDS.get(id)
	if not (r is Dictionary):
		return {}
	var s: float = track_scale(track_id)
	return {money = roundi(float(r.money) * s / 10.0) * 10, points = roundi(float(r.points) * s)}


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
static func payout(track_id: String, medal: String, beaten: String, paid: PackedStringArray) -> Dictionary:
	var items: Array = []
	var repeat: PackedStringArray = []
	var money: int = 0
	var points: int = 0
	for id: String in earned_ids(medal, beaten):
		if paid.has(id):
			repeat.append(id)
			continue
		var r: Dictionary = reward(track_id, id)
		var ai: bool = id.begins_with(AI_PREFIX)
		items.append({id = id, kind = "ai" if ai else "medal", label = label(id), money = r.money, points = r.points})
		money += int(r.money)
		points += int(r.points)
	return {items = items, money = money, points = points, repeat = repeat}


## A reward's name for the finish panel: "Gold medal", "Beat the Pro AI".
static func label(id: String) -> String:
	if id.begins_with(AI_PREFIX):
		return "Beat the %s AI" % Opponents.level_name(id.substr(AI_PREFIX.length()))
	return "%s medal" % String(Medals.NAMES.get(id, id.capitalize()))


## payout() for a finished run, paid into the save file (once: the ids are remembered per track
## and car). Returns the payout, with `money_total` and `points_total` after it.
static func claim(track_id: String, car_id: String, medal: String, beaten: String) -> Dictionary:
	var p: Dictionary = payout(track_id, medal, beaten, SaveData.paid_rewards(track_id, car_id))
	var ids: PackedStringArray = []
	for it: Dictionary in p.items:
		ids.append(String(it.id))
	if not ids.is_empty():
		SaveData.pay_rewards(track_id, car_id, ids, int(p.money), int(p.points))
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
