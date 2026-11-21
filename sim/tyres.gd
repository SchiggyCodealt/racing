class_name Tyres
extends RefCounted
## tyres.gd (v6.39.0): the tyre compounds a car races on, chosen for each car and track on the car
## page (SaveData's setups, key `compound`: 0 soft, 1 medium, the default, 2 hard, 3 rally). Free.
## ------------------------------------------------------------------
## A compound scales the car's grip on asphalt (CarSpec.mu) by `asphalt` and on loose ground (dirt and
## snow) by `loose` (dirt_grip and snow_grip are shares of the asphalt grip, so they are rescaled by
## loose / asphalt), and wears with the distance driven on it: from `from` km its grip falls by
## `rate` of its new grip a km, down to `floor`. Medium is the stock tyre (the stock spec itself) and
## only wears in races longer than any time trial or normal race (the endurance races), as Rally
## does; Soft grips most and wears soonest; Hard grips least and never wears:
##   distance of the race   up to ~30 km: Soft    ~30-100 km: Medium    beyond: Hard
## Wear only runs where the race asks for it (Car.fit_tyres: the play mode, for every car of the
## race, the AI's on Medium); training, the tools and FleetSim never wear (Car.tyre_grip stays 1).
##
##   Tyres.count() -> 4;  Tyres.DEFAULT -> 1 (medium)
##   Tyres.def(i) -> {id, name, asphalt, loose, from, rate, floor, what} (i clamped to 0..3)
##   Tyres.index_of(id) -> 0..3, or -1
##   Tyres.fit(spec, i) -> CarSpec   `spec` on compound i (Medium, or an unknown i: `spec` itself)
##   Tyres.wear(i, km) -> 0..1      the share of its new grip left after `km` on it
##   Tyres.text(i) -> its `what`: "5 % more grip on asphalt, wears from 10 km (...)"

const DEFAULT: int = 1
const DEFS: Array[Dictionary] = [
	{id = "soft", name = "Soft", asphalt = 1.05, loose = 1.0, from = 10.0, rate = 0.0025, floor = 0.88,
		what = "5 % more grip on asphalt, wears from 10 km (down to Medium's grip by 30 km)"},
	{id = "medium", name = "Medium", asphalt = 1.0, loose = 1.0, from = 60.0, rate = 0.001, floor = 0.94,
		what = "the stock tyre, wears only in long races (from 60 km)"},
	{id = "hard", name = "Hard", asphalt = 0.96, loose = 0.96, from = 0.0, rate = 0.0, floor = 1.0,
		what = "4 % less grip, never wears (for races over about 100 km)"},
	{id = "rally", name = "Rally", asphalt = 0.92, loose = 1.1, from = 60.0, rate = 0.001, floor = 0.94,
		what = "10 % more grip on dirt and snow, 8 % less on asphalt, wears like Medium"},
]


static func count() -> int:
	return DEFS.size()


static func def(i: int) -> Dictionary:
	return DEFS[clampi(i, 0, DEFS.size() - 1)]


static func index_of(id: String) -> int:
	for i in DEFS.size():
		if String(DEFS[i].id) == id.to_lower() or String(DEFS[i].name).to_lower() == id.to_lower():
			return i
	return -1


## `spec` on compound `i`: asphalt grip × asphalt, loose grip × loose. Medium (or an unknown index)
## returns `spec` itself, so a stock car is bit for bit the stock car.
static func fit(spec: CarSpec, i: int) -> CarSpec:
	if i == DEFAULT or i < 0 or i >= DEFS.size():
		return spec
	var d: Dictionary = DEFS[i]
	var a: float = float(d.asphalt)
	var l: float = float(d.loose) / a
	return CarSpec.make({mu = spec.mu * a, dirtGrip = spec.dirt_grip * l, snowGrip = spec.snow_grip * l}, spec)


## The share of compound `i`'s new grip left after `km` on it (1 until its `from`, never below `floor`).
static func wear(i: int, km: float) -> float:
	if i < 0 or i >= DEFS.size():
		return 1.0
	var d: Dictionary = DEFS[i]
	if float(d.rate) <= 0.0 or km <= float(d.from):
		return 1.0
	return maxf(float(d.floor), 1.0 - float(d.rate) * (km - float(d.from)))


## What compound `i` does, in words (the car page).
static func text(i: int) -> String:
	return String(def(i).what)
