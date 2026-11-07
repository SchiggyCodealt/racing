class_name CupRun
extends RefCounted
## cup_run.gd (v6.14.0): one championship in progress (sim/cups.gd): which cup, the field level, your
## car, the five AI drivers and the results of the races run so far.
## ------------------------------------------------------------------
## The drivers come from Field.cup_drivers(cup, level): the same five in every race, each with its own
## pace (the k-th aims at Field.PACE[k] × the level's time with your car on each track). The grid of a
## race follows the standings (Cups.grid_order): before the first race the field's own grid (the AI
## slowest first, you last), then the leader on pole. You always start on the usual start spot
## (sim/field.gd grid's anchor), so every race counts for medals, records and unlocks as a field race.
## The save file keeps it (SaveData.set_cup_run(run.to_dict())), so a cup carries on after a restart.
##
##   var run := CupRun.start(cup_id, level, car_id)     (null for an unknown cup, level or car)
##   run.entrants() -> the five driver ids then Cups.PLAYER
##   run.race_count(), run.races_done(), run.finished(), run.next_track() ("" when finished)
##   run.table() -> Cups.table(...) of the races run;  run.grid() -> ids in grid order, pole first
##   run.place() -> your place in the standings (1-based)
##   run.field(track_id) -> {lineup: the AI's Field entries in grid order, player_slot} for the next race
##       ({lineup: []} when there are no AI opponents for the track and car)
##   run.add(rows) -> the race's results: FieldRace.results() rows ({id, place, dnf}); every entrant must
##       be in them (false and nothing kept otherwise)
##   run.to_dict() / CupRun.from_dict(d) (null when it isn't a valid run: unknown cup, level, car or
##       drivers, more results than races, a result that misses an entrant)

var cup: String = ""
var level: String = ""
var car: String = ""
## the AI drivers (Field roster ids), the slowest first
var drivers: PackedStringArray = []
## one Dictionary per race run: {entrant id: {place, dnf}}
var races: Array = []


static func start(cup_id: String, level_id: String, car_id: String) -> CupRun:
	if Cups.cup(cup_id).is_empty() or Opponents.rank(level_id) < 0 or not Cars.has_car(car_id):
		return null
	var r := CupRun.new()
	r.cup = cup_id
	r.level = level_id
	r.car = car_id
	r.drivers = Field.cup_drivers(cup_id, level_id)
	return r


func entrants() -> PackedStringArray:
	var out := drivers.duplicate()
	out.append(Cups.PLAYER)
	return out


func race_count() -> int:
	return Cups.tracks_of(cup).size()


func races_done() -> int:
	return races.size()


func finished() -> bool:
	return races.size() >= race_count()


func next_track() -> String:
	return "" if finished() else Cups.tracks_of(cup)[races.size()]


func table() -> Array[Dictionary]:
	return Cups.table(entrants(), races)


func grid() -> PackedStringArray:
	return Cups.grid_order(entrants(), races)


func place() -> int:
	for r: Dictionary in table():
		if String(r.id) == Cups.PLAYER:
			return int(r.pos)
	return 0


## The field of the next race on `track_id`: the AI's lineup entries (Field.lineup_of with the cup's
## drivers and paces) in grid order, and your grid slot.
func field(track_id: String) -> Dictionary:
	var base: Array[Dictionary] = Field.lineup_of(track_id, level, car, drivers)
	if base.is_empty():
		return {lineup = [], player_slot = 0}
	var by_id: Dictionary = {}
	for e: Dictionary in base:
		by_id[String(e.id)] = e
	var out: Array = []
	var slot := 0
	var g := grid()
	for k in g.size():
		if g[k] == Cups.PLAYER:
			slot = k
		else:
			out.append(by_id[g[k]])
	return {lineup = out, player_slot = slot}


## Keep a race's results ({id, place, dnf} rows, e.g. FieldRace.results()). False (nothing kept) when
## the cup is finished or an entrant is missing.
func add(rows: Array) -> bool:
	if finished():
		return false
	var res: Dictionary = {}
	for r: Dictionary in rows:
		res[String(r.get("id", ""))] = {place = int(r.get("place", 0)), dnf = bool(r.get("dnf", false))}
	for id: String in entrants():
		if not res.has(id) or int(res[id].place) < 1:
			return false
	var keep: Dictionary = {}
	for id: String in entrants():
		keep[id] = res[id]
	races.append(keep)
	return true


func to_dict() -> Dictionary:
	return {cup = cup, level = level, car = car, drivers = Array(drivers), races = races.duplicate(true)}


static func from_dict(d: Variant) -> CupRun:
	if not (d is Dictionary):
		return null
	var r := start(str(d.get("cup", "")), str(d.get("level", "")), str(d.get("car", "")))
	if r == null:
		return null
	var dr: Variant = d.get("drivers")
	if dr is Array and PackedStringArray(dr) != r.drivers:
		return null # (another version's roster: the cup starts over)
	var rs: Variant = d.get("races")
	if not (rs is Array) or (rs as Array).size() > r.race_count():
		return null
	for race: Variant in rs:
		if not (race is Dictionary):
			return null
		var rows: Array = []
		for id: Variant in race:
			var e: Variant = race[id]
			if e is Dictionary:
				rows.append({id = str(id), place = int(e.get("place", 0)) if (e.get("place") is float or e.get("place") is int) else 0, dnf = e.get("dnf") == true})
		if not r.add(rows):
			return null
	return r
