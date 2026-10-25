extends RefCounted
## ui_fixture.gd
## ------------------------------------------------------------------
## Fixture data for the interface previews and tests: the save data, HUD states and finish
## panels of the approved v5 screenshots (Night Highway with the Racer: menu, driving, finish),
## plus the stress cases (long names, 12-minute times, big scores, every score category).

const STATE_KEYS := [["Shift", "nitro", "X / RB"], ["R", "restart", "View"], ["Enter", "respawn", "B"], ["G", "ghost", "Y"], ["Esc", "menu", "Menu"]]


## The save data of the approved menu shot: best times on six tracks (medals follow), a best
## score and a ghost on Night Highway, a trained AI network.
static func save_data_v5() -> void:
	UiData.reset()
	UiData.store.records = {
		"rookie-oval|racer": {"time": 143.6}, "hairpin-valley|racer": {"time": 239.95}, "ramp-rally|racer": {"time": 189.45},
		"night-highway|racer": {"time": 215.05}, "lighthouse-bay|racer": {"time": 182.167}, "seaside-stunts|racer": {"time": 75.583},
	}
	UiData.store.scores = {"night-highway|racer": 66000}
	UiData.store.ghosts = {"night-highway|racer": true}
	UiData.store.settings = {"car": "racer", "ghost": true}
	UiData.store.network = {"generation": 60, "fitness": 1417, "sizes": [18, 16, 8, 2],
		"trained_on": ["rookie-oval", "hairpin-valley", "mountain-pass"], "walls": "crash", "best_times": {}}


## Stress save data: 12-minute times, a ten-million score, an AI best lap and a long AI status.
static func save_data_stress() -> void:
	save_data_v5()
	for i in UiData.track_count():
		UiData.store.records["%s|racer" % UiData.track_id(i)] = {"time": 754.321 + i}
	UiData.store.scores["night-highway|racer"] = 9876543
	UiData.store.network.best_times = {"night-highway": {"lap": 612.345, "finish": 1834.5}}
	UiData.store.network.trained_on = ["rookie-oval", "hairpin-valley", "ramp-rally", "banked-speedway", "technical-trial",
		"grand-marathon", "coastal-gp", "mountain-pass", "canyon-run", "night-highway", "lighthouse-bay", "seaside-stunts"]
	UiData.store.network.sizes = [18, 32, 32, 16, 8, 2]
	UiData.store.network.generation = 12345


## The rev limits of a car (the fixture's car data).
static func spec(car: String = "racer") -> Dictionary:
	return UiData.car_info(car).rev


## The HUD of the approved driving shot (lap 1, CP 6 of 7, nitro burning, score x5).
static func hud_drive() -> Dictionary:
	return {
		"time": 57.533, "lap": 1, "laps": 3, "cp": 6, "cps": 7, "sprint": false, "speed": 154.2 / 3.6,
		"gear": 4, "rpm": 7600.0, "spec": spec(), "nitro": 0.62, "boosting": true,
		"score": {"total": 10000, "mult": 5, "live": null}, "best": 215.05,
		"medal": {"medal": "gold", "time": 208.0}, "finished": false, "ghost_text": "", "pad": false,
	}


## The HUD at the finish of the approved finish shot.
static func hud_finish() -> Dictionary:
	var s := hud_drive()
	s.merge({"time": 221.967, "lap": 3, "cp": 7, "finished": true, "score": {"total": 40940, "mult": 5, "live": null},
		"speed": 80.0 / 3.6, "gear": 3, "rpm": 5200.0, "boosting": false, "nitro": 0.35}, true)
	return s


## The finish panel of the approved finish shot (silver, 6.917 s off the best, a 40,940 score).
static func panel_finish() -> Dictionary:
	return {
		"title": "Finish", "time": 221.967,
		"medal": {"got": "silver", "new": false},
		"best": {"car": "Racer", "time": 215.05},
		"next": {"medal": "gold", "time": 208.0},
		"score": {"total": 40940, "new_best": false, "prev": 66000, "car": "Racer", "nitro_earned": 2.5, "nitro_lost": 0.0,
			"rows": [
				{"label": "Clean checkpoints", "note": "22 of 24 · best x5", "points": 40000},
				{"label": "Clean laps", "note": "1 of 3", "points": 2000},
				{"label": "Walls", "note": "1 contact", "points": -560},
				{"label": "Respawns", "note": "1", "points": -500},
			]},
		"laps": [75.817, 73.117, 73.033], "pad": false,
	}


## A record run: a new personal best, a new medal and a new best score, every score category.
static func panel_record() -> Dictionary:
	return {
		"title": "Finish", "time": 207.433,
		"medal": {"got": "gold", "new": true},
		"record": {"prev": 215.05}, "ghost_note": "Ghost saved: race it with R",
		"next": {"medal": "author", "time": 195.45},
		"lines": ["AI ghost: 3:31.250, you win!"],
		"score": {"total": 73120, "new_best": true, "prev": 66000, "car": "Racer", "nitro_earned": 3.4, "nitro_lost": 0.6,
			"rows": [
				{"label": "Clean checkpoints", "note": "24 of 24 · best x5", "points": 52500},
				{"label": "Drifts", "note": "6 · best 1,240", "points": 4310},
				{"label": "Air", "note": "2 · longest 1.6 s", "points": 1550},
				{"label": "Close calls", "note": "3", "points": 750},
				{"label": "Clean laps", "note": "3 of 3", "points": 6000},
				{"label": "Clean run", "note": "", "points": 5000},
				{"label": "Walls", "note": "2 contacts", "points": -490},
				{"label": "Respawns", "note": "0", "points": 0},
			]},
		"laps": [70.317, 68.6, 68.516], "pad": true,
	}


## Twelve-minute times, a seven-digit score and no medal (the stress case).
static func panel_stress() -> Dictionary:
	var p := panel_record()
	p.time = 754.321
	p.medal = {"got": "", "bronze": 293.0}
	p.erase("record")
	p.erase("ghost_note")
	p.best = {"car": "Thunder", "time": 721.999}
	p.next = {}
	p.lines = ["AI ghost hasn't finished: you win!"]
	p.score.total = 1234567
	p.score.new_best = false
	p.score.prev = 9876543
	p.score.car = "Thunder"
	p.score.rows[0].points = 1180000
	p.score.rows[0].note = "240 of 240 · best x5"
	p.laps = [251.111, 250.005, 253.205]
	return p


## The AI's finish (Watch the AI).
static func panel_ai() -> Dictionary:
	return {"title": "AI finished", "time": 219.4, "ai": true, "medal": {"got": "silver", "new": false},
		"best": {"car": "Racer", "time": 215.05}, "laps": [74.0, 72.6, 72.8], "pad": false}


## A network to draw in the Watch-AI panel: 18-16-8-2 with seeded weights and activations.
static func network() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	var sizes := [18, 16, 8, 2]
	var weights: Array = []
	var acts: Array = []
	for l in sizes.size():
		var a := PackedFloat64Array()
		for i in sizes[l]:
			a.append(rng.randf_range(-1.0, 1.0))
		acts.append(a)
		if l < sizes.size() - 1:
			var w := PackedFloat64Array()
			for k in sizes[l] * sizes[l + 1]:
				w.append(rng.randfn(0.0, 0.9))
			weights.append(w)
	return {"sizes": sizes, "weights": weights, "acts": acts}


## Score events as score.js emits them.
static func pops() -> Array:
	return [
		{"kind": "checkpoints", "text": "Clean checkpoint", "points": 2500, "mult": 5},
		{"kind": "drift", "text": "Drift", "points": 820, "mult": 1},
		{"kind": "lap", "text": "Clean lap", "points": 2000, "mult": 1},
		{"kind": "wall", "text": "Wall", "points": -200, "mult": 1, "combo_lost": true},
	]


## A fake menu input: queue presses with press(); pad_active as given.
class FakeInput:
	extends RefCounted
	var pressed := {}
	var pad_active := false
	func press(code: String) -> void:
		pressed[code] = true
	func consume(codes: Array) -> bool:
		for c in codes:
			if pressed.has(c):
				pressed.erase(c)
				return true
		return false
	func nav_dir() -> String:
		for d in ["up", "down", "left", "right"]:
			if consume(["Nav" + d.capitalize()]):
				return d
		return ""
	func clear_pressed() -> void:
		pressed.clear()
