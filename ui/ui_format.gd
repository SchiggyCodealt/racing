class_name UiFormat
extends RefCounted
## ui_format.gd
## ------------------------------------------------------------------
## How the interface writes times, time differences and points: the same strings as the
## web game's formatTime / formatDelta (src/game/race.js) and formatPoints (src/game/score.js).


## Seconds as m:ss.mmm ("--:--.---" for none). Rounded once, so 119.9996 s shows as 2:00.000.
static func time(t: Variant) -> String:
	if t == null or not (t is float or t is int) or is_inf(float(t)) or is_nan(float(t)):
		return "--:--.---"
	var v := float(t)
	var neg := v < 0.0
	var ms := int(roundf(absf(v) * 1000.0))
	var m := ms / 60000
	var rest := ms - m * 60000
	return "%s%d:%02d.%03d" % ["-" if neg else "", m, rest / 1000, rest % 1000]


## A split difference: "+0.123" / "-0.456".
static func delta(d: float) -> String:
	return "%s%.3f" % ["+" if d >= 0.0 else "-", absf(d)]


## 12345 -> "12,345" (whole points; a real minus sign for negatives).
static func points(n: float) -> String:
	var v := int(roundf(n))
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("−" if v < 0 else "") + s + out


## Track number as two digits: 0 -> "01".
static func track_number(i: int) -> String:
	return "%02d" % (i + 1)


## Metres as km with two decimals: 3120 -> "3.12".
static func km(m: float) -> String:
	return "%.2f" % (m / 1000.0)
