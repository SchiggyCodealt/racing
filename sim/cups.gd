class_name Cups
extends RefCounted
## cups.gd (v6.14.0): Championships, the data and the rules.
## ------------------------------------------------------------------
## A cup is three tracks (the Rally Cup, v6.23: four) raced back to back against the same five AI drivers (sim/field.gd: a field
## race each, modes/field_mode.gd) at one field level (Rookie to Elite) with the car you picked.
## Every race gives points by finishing place (POINTS, F1 style: 10, 8, 6, 5, 4, 3 for 1st to 6th; an
## AI that is out, DNF, scores nothing); the standings add them up, and the grid of the next race
## follows them (the leader on pole). After the last race the top three of the standings get the
## trophies (gold, silver, bronze) and the cup pays by your place (sim/economy.gd CUP_PLACES, once per
## cup, level and place). sim/cup_run.gd keeps one cup in progress.
## Data-driven: CUPS is the list: five cups of three, rising in difficulty (the tracks' mean difficulty
## 2.0, 2.7, 3.7, 4.0, 4.7), and the Rally Cup of four (v6.23; 4.0), every track in exactly one. A cup
## opens when every one of its tracks is open (sim/unlocks.gd: they open one at a time, in menu order),
## so they open in this order too: with track 3, 10, 12, 13, 15 and 19.
##
##   Cups.ids() -> cup ids, easiest first;  Cups.cup(id) -> {id, name, tracks, blurb} ({} unknown)
##   Cups.index_of(id), Cups.name_of(id), Cups.tracks_of(id)
##   Cups.is_open(id) -> every track of the cup is open;  Cups.missing(id) -> its tracks still locked
##   Cups.points_for(place, dnf) -> the points of a finishing place (1-based)
##   Cups.table(entrants, races) -> the standings, leader first: [{id, pos, points, places (one per race
##       run, 0: none), best (best place), last (place in the last race), dnf (races out)}]
##       races: [{driver id: {place, dnf}}] in the order they were run. Ties: the better best finishing
##       place first, then the better place in the last race (then the race before, ...), then entrant order
##   Cups.grid_order(entrants, races) -> ids in grid order, pole first: before the first race the
##       entrants as given (the field's own grid: the AI slowest first, you last), after it the standings
##   Cups.trophy(place) -> "gold" | "silver" | "bronze" | "" (4th and worse)

## The cups, easiest first (id, name, the tracks in race order, a line for the picker).
const CUPS: Array[Dictionary] = [
	{id = "rookie", name = "Rookie Cup", tracks = ["rookie-oval", "hairpin-valley", "ramp-rally"],
		blurb = "The first three tracks: a meadow loop, a snowy ridge and dirt jumps."},
	{id = "asphalt", name = "Asphalt Cup", tracks = ["night-highway", "banked-speedway", "coastal-gp"],
		blurb = "Three fast asphalt circuits: the night highway, the banked bowls and a grand prix."},
	{id = "technical", name = "Technical Cup", tracks = ["lighthouse-bay", "technical-trial", "seaside-stunts"],
		blurb = "Car control: the bay's long slides, tight chicanes and the stunt road's kickers."},
	{id = "dirt-snow", name = "Dirt and Snow Cup", tracks = ["forest-rally", "mountain-pass", "canyon-run"],
		blurb = "Loose ground: a forest rally, the pass over the snow and the red-rock canyon."},
	{id = "finale", name = "Grand Finale", tracks = ["northern-lights", "grand-marathon", "summit-rush"],
		blurb = "The hardest three: the snow bowls, the 6 km marathon and the summit."},
	# v6.23: the four rally stages, point to point, each on a surface of its own
	{id = "rally", name = "Rally Cup", tracks = ["pine-ridge", "dune-sea", "frozen-lake", "monsoon-trail"],
		blurb = "Four rally stages: forest gravel, desert sand, a frozen lake and jungle mud."},
]
## Points per finishing place, 1st first (places further back score nothing).
const POINTS: PackedInt32Array = [10, 8, 6, 5, 4, 3]
## The trophies of the top three of a cup's standings.
const TROPHIES: PackedStringArray = ["gold", "silver", "bronze"]
## Your id in the standings (the AI's are sim/field.gd driver ids).
const PLAYER: String = "you"


static func ids() -> PackedStringArray:
	var out: PackedStringArray = []
	for c: Dictionary in CUPS:
		out.append(String(c.id))
	return out


static func cup(id: String) -> Dictionary:
	for c: Dictionary in CUPS:
		if String(c.id) == id:
			return c
	return {}


static func index_of(id: String) -> int:
	return ids().find(id)


static func name_of(id: String) -> String:
	return String(cup(id).get("name", id))


static func tracks_of(id: String) -> PackedStringArray:
	return PackedStringArray(cup(id).get("tracks", []))


## True when every track of cup `id` is open (an unknown cup: false).
static func is_open(id: String) -> bool:
	var tr := tracks_of(id)
	if tr.is_empty():
		return false
	for t: String in tr:
		if not Unlocks.is_open(t):
			return false
	return true


## The tracks of cup `id` that are still locked (race order).
static func missing(id: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for t: String in tracks_of(id):
		if not Unlocks.is_open(t):
			out.append(t)
	return out


## The points finishing `place` (1-based) scores; a car that is out (dnf) scores nothing.
static func points_for(place: int, dnf: bool = false) -> int:
	if dnf or place < 1 or place > POINTS.size():
		return 0
	return POINTS[place - 1]


## "gold", "silver" or "bronze" for 1st, 2nd and 3rd in a cup; "" otherwise.
static func trophy(place: int) -> String:
	return TROPHIES[place - 1] if place >= 1 and place <= TROPHIES.size() else ""


## The standings after `races` (see the header): one row per entrant, leader first.
static func table(entrants: PackedStringArray, races: Array) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for k in entrants.size():
		var id: String = entrants[k]
		var places: PackedInt32Array = []
		var pts := 0
		var best := 0
		var outs := 0
		for r: Variant in races:
			var e: Variant = (r as Dictionary).get(id) if r is Dictionary else null
			var p: int = int((e as Dictionary).get("place", 0)) if e is Dictionary else 0
			var out: bool = bool((e as Dictionary).get("dnf", false)) if e is Dictionary else false
			places.append(p)
			pts += points_for(p, out)
			if out:
				outs += 1
			if p > 0 and (best == 0 or p < best):
				best = p
		rows.append({id = id, order = k, points = pts, places = places, best = best, last = places[places.size() - 1] if places.size() > 0 else 0, dnf = outs})
	rows.sort_custom(_ahead)
	for k in rows.size():
		rows[k].pos = k + 1
		rows[k].erase("order")
	return rows


## Standings order: more points; then the better best place; then the better place in the last race
## (and the race before, ...); then the entrant order. A place of 0 (not raced) counts as the worst.
static func _ahead(a: Dictionary, b: Dictionary) -> bool:
	if int(a.points) != int(b.points):
		return int(a.points) > int(b.points)
	var ba: int = _rank(int(a.best))
	var bb: int = _rank(int(b.best))
	if ba != bb:
		return ba < bb
	var pa: PackedInt32Array = a.places
	var pb: PackedInt32Array = b.places
	for k in range(mini(pa.size(), pb.size()) - 1, -1, -1):
		if _rank(pa[k]) != _rank(pb[k]):
			return _rank(pa[k]) < _rank(pb[k])
	return int(a.order) < int(b.order)


static func _rank(place: int) -> int:
	return place if place > 0 else 1 << 20


## The grid of the next race (ids, pole first): the entrants as given before the first race, then the
## standings, the leader on pole.
static func grid_order(entrants: PackedStringArray, races: Array) -> PackedStringArray:
	if races.is_empty():
		return entrants.duplicate()
	var out: PackedStringArray = []
	for r: Dictionary in table(entrants, races):
		out.append(String(r.id))
	return out
