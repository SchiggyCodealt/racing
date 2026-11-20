class_name TuneTrial
extends RefCounted
## tune_trial.gd (v6.34.0): the trial that fits a supercharger level (and, from v6.35.0, an aero
## tune level): a row of arrow prompts to press in order before the time runs out.
## ------------------------------------------------------------------
## The car page asks first (the price, what a miss costs), then ui/trial_screen.gd runs one of
## these and draws it. The rules, all here so tests can play a trial without a screen:
##   - "ready": the prompts are shown for READY_TIME seconds and the clock has not started;
##     presses are ignored (no jumping the gun, no penalty either).
##   - "go": press the prompts in order (press("up") ...) before `limit` seconds are up. Each
##     right press marks one done; a wrong one is a miss straight away, and so is the clock
##     running out (tick()).
##   - "won" when the last prompt is pressed in time, "missed" otherwise (`why`: "wrong",
##     "time" or "quit": the player left the trial, which counts as a miss).
## Harder each level (LEVELS): more prompts and less time for each; the whole row takes about
## the same time at every level, so the pace is what climbs (level 1: 4 prompts at 0.9 s each,
## level 5: 8 at 0.45 s).
## The row is random (a seed for tests); never three of the same arrow in a row.
##
##   TuneTrial.new(level, seed = -1)  (seed -1: a random row)
##   trial.tick(dt) -> state;  trial.press(dir) -> "ok" | "wrong" | "ignored" | "won"
##   trial.quit()  (a miss)
##   trial.state, trial.why, trial.sequence (PackedStringArray of "up" / "down" / "left" / "right"),
##   trial.done (prompts pressed), trial.time (seconds since "go"), trial.limit, trial.left()
##   TuneTrial.rule(level) -> {count, per, limit}

const DIRS: PackedStringArray = ["up", "down", "left", "right"]
## Seconds the row is shown before the clock starts.
const READY_TIME: float = 1.2
## Per level (1..5): how many prompts and the seconds allowed for each.
const LEVELS: Array[Dictionary] = [
	{count = 4, per = 0.9},
	{count = 5, per = 0.75},
	{count = 6, per = 0.62},
	{count = 7, per = 0.52},
	{count = 8, per = 0.45},
]

var level: int = 1
var sequence: PackedStringArray = []
var limit: float = 0.0
var state: String = "ready"
var why: String = ""
var done: int = 0
var time: float = 0.0
var ready_left: float = READY_TIME


## Level `level`'s rule: {count, per, limit} (limit = count × per seconds).
static func rule(lv: int) -> Dictionary:
	var r: Dictionary = LEVELS[clampi(lv, 1, LEVELS.size()) - 1]
	return {count = int(r.count), per = float(r.per), limit = snappedf(int(r.count) * float(r.per), 0.001)}


func _init(lv: int = 1, seed_: int = -1) -> void:
	level = clampi(lv, 1, LEVELS.size())
	var r: Dictionary = rule(level)
	limit = float(r.limit)
	var rng := RandomNumberGenerator.new()
	if seed_ >= 0:
		rng.seed = seed_
	else:
		rng.randomize()
	while sequence.size() < int(r.count):
		var d: String = DIRS[rng.randi_range(0, DIRS.size() - 1)]
		var n: int = sequence.size()
		if n >= 2 and sequence[n - 1] == d and sequence[n - 2] == d:
			continue
		sequence.append(d)


## Seconds left on the clock (the whole limit while "ready", 0 once it is over).
func left() -> float:
	if state == "ready":
		return limit
	return maxf(0.0, limit - time)


## The arrow to press now ("" when the trial is over).
func current() -> String:
	return sequence[done] if state in ["ready", "go"] and done < sequence.size() else ""


## Advance the clocks by `dt` seconds: the ready time, then the trial's clock (out of time: a miss).
func tick(dt: float) -> String:
	if state == "ready":
		ready_left -= dt
		if ready_left <= 0.0:
			state = "go"
			time = -ready_left # (the part of the step after the ready time already counts)
			ready_left = 0.0
	elif state == "go":
		time += dt
	if state == "go" and time >= limit:
		state = "missed"
		why = "time"
	return state


## Arrow `dir` pressed: "ok" (right, more to go), "won" (the last one), "wrong" (a miss), "ignored"
## (before the clock starts or after the trial is over).
func press(dir: String) -> String:
	if state != "go":
		return "ignored"
	if dir != sequence[done]:
		state = "missed"
		why = "wrong"
		return "wrong"
	done += 1
	if done >= sequence.size():
		state = "won"
		return "won"
	return "ok"


## The player left the trial: a miss (unless it was over already).
func quit() -> void:
	if state in ["ready", "go"]:
		state = "missed"
		why = "quit"


func is_over() -> bool:
	return state == "won" or state == "missed"
