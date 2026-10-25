class_name FinishPanel
extends PanelContainer
## finish_panel.gd
## ------------------------------------------------------------------
## The finish panel in the middle of the HUD (playMode.js onFinish / style.css #hud-panel):
## the FINISH tag, the time, the medal the run earned (NEW when it beats the one held), the
## new personal best or the comparison with it, the next medal and how far the run was from
## it, the AI ghost result, the score with its breakdown by category and the nitro the
## points earned, the lap times and the keys to race again or go back.
##
## update(state) with a Dictionary the play mode fills (no game logic here; deltas are the
## differences of the times given):
##   title       "Finish" or "AI finished"
##   time        the race time (s)
##   ai          true when the AI drove (no NEW medal, the comparison reads "(AI +1.234)")
##   medal       {got: "silver", new: bool} | {got: "", bronze: 183.0} (no medal) | {} (no medal times)
##   record      {prev: 215.05 or null} when the run is a new personal best
##   ghost_note  "Ghost saved: race it with R" (under the record line)
##   best        {car: "Racer", time: 215.05}: your best before this run (not a record)
##   next        {medal: "gold", time: 208.0}: the next medal above the best time
##   lines       ["AI ghost: 3:40.000, you win!"]: plain lines (the AI ghost's result)
##   score       {total, new_best: bool, prev: int (-1 none), car, rows: [{label, note, points}],
##               nitro_earned, nitro_lost} (absent: no score, e.g. the AI drove)
##   laps        [lap times] (shown when there are two or more)
##   pad         true: name the gamepad buttons too
## The panel adapts to the window: full width and a one-column breakdown in narrow windows,
## denser under 700 px of height and smallest under 520 px (set_window_size).

const KeyCap := preload("res://ui/key_cap.gd")
const MedalDot := preload("res://ui/medal_dot.gd")

var state: Dictionary = {}
var _box: VBoxContainer
var _win := Vector2(1280, 720)
## size class: "" normal, "short" (≤ 700 px tall), "tiny" (≤ 520 px), plus narrow (< 1000 px wide)
var _short := false
var _tiny := false
var _narrow := false
var _one_col := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_box = UiStyle.vbox(0)
	add_child(_box)
	_apply_box()


## Tell the panel the window (HUD) size it is centred in; rebuilds when the size class changes.
func set_window_size(s: Vector2) -> void:
	_win = s
	var short := s.y <= 700
	var tiny := s.y <= 520
	var narrow := s.x < 1000
	var one := s.x <= 520
	if short != _short or tiny != _tiny or narrow != _narrow or one != _one_col:
		_short = short
		_tiny = tiny
		_narrow = narrow
		_one_col = one
		_apply_box()
		if visible:
			_rebuild()
	_place()


func _apply_box() -> void:
	var pad := [UiStyle.S6, UiStyle.S5, UiStyle.S6, UiStyle.S5]
	if _narrow:
		pad = [UiStyle.S4, UiStyle.S4, UiStyle.S4, UiStyle.S4]
	if _short:
		pad = [UiStyle.S5, UiStyle.S3, UiStyle.S5, UiStyle.S3]
	if _tiny:
		pad = [UiStyle.S4, UiStyle.S2, UiStyle.S4, UiStyle.S2]
	add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, false, pad))


func update(s: Dictionary) -> void:
	state = s
	visible = true
	_rebuild()


func hide_panel() -> void:
	visible = false


# ---------------------------------------------------------------- building

func _fs_small() -> int:
	return 12 if _tiny else UiStyle.FS_S


func _num_size() -> int:
	return UiStyle.FS_S if _tiny else UiStyle.FS_M


## A centred line of pieces: [text, kind, size, color] arrays or Controls.
func _line(pieces: Array, top: float = 0.0, sep: int = 0) -> Control:
	var row := UiStyle.hbox(sep, BoxContainer.ALIGNMENT_CENTER)
	var labels: Array = []
	for p in pieces:
		if p is Control:
			labels.append(p)
		else:
			var l := UiStyle.label(p[0], p[1], p[2], p[3], p[4] if p.size() > 4 else 0.0, p[5] if p.size() > 5 else false, false, false,
				p[6] if p.size() > 6 else roundf(p[2] * 1.4))
			labels.append(l)
	for l in labels:
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(l)
	if top > 0:
		var m := UiStyle.margin([0, int(top), 0, 0])
		m.add_child(row)
		return m
	return row


## A time difference, green when ahead (negative) and red when behind.
func _delta(d: float) -> Array:
	return [UiFormat.delta(d), "display", _num_size(), UiStyle.GOOD if d <= 0 else UiStyle.BAD, 0.0, false, roundf(_fs_small() * 1.4)]


func _sp() -> Array:
	return [" ", "text", _fs_small(), UiStyle.TEXT_2]


func _tag(text: String, size: int, pad: Array, spacing: float) -> Control:
	var p := UiStyle.panel(UiStyle.box(UiStyle.ACCENT, true, pad))
	p.add_child(UiStyle.label(text, "display_bold", size, UiStyle.ACCENT_INK, spacing, true, false, false, roundf(size * (1.2 if size > 13 else 1.3))))
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p


func _rebuild() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	var s := state
	var small := _fs_small()
	var lh := roundf(small * 1.4)
	var t := float(s.get("time", 0.0))
	# FINISH tag and the time
	var tag := _tag(str(s.get("title", "Finish")), small if _tiny else UiStyle.FS_M, [UiStyle.S3, 3, UiStyle.S3, 3], 0.12)
	var tag_row := UiStyle.hbox(0, BoxContainer.ALIGNMENT_CENTER)
	tag_row.add_child(tag)
	_box.add_child(tag_row)
	var big := 30 if _tiny else (40 if _short or _narrow else 56)
	var big_l := UiStyle.label(UiFormat.time(t), "display_bold", big, UiStyle.TEXT, 0.0, false, false, false, big)
	big_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var bm := UiStyle.margin([0, UiStyle.S1 if _short else UiStyle.S2, 0, 0 if _short else UiStyle.S1])
	bm.add_child(big_l)
	_box.add_child(bm)
	# the medal the run earned
	var medal: Dictionary = s.get("medal", {})
	if not medal.is_empty():
		var got := str(medal.get("got", ""))
		if got == "":
			var bronze := float(medal.get("bronze", 0.0))
			_box.add_child(_line([["No medal: bronze is %s" % UiFormat.time(bronze), "text", small, UiStyle.TEXT_2], _sp(), _delta(t - bronze)],
				UiStyle.S1 if _short else UiStyle.S2))
		else:
			var size := small if _tiny else (UiStyle.FS_M if _short else UiStyle.FS_L)
			var pieces: Array = [MedalDot.make(got, roundf(size * 0.9 * 0.78)), UiStyle.gap(UiStyle.S1),
				[UiStyle.MEDAL_NAMES[got] + " medal", "display_bold", size, UiStyle.TEXT, 0.06, true, roundf(size * 1.2)]]
			if medal.get("new", false) and not s.get("ai", false):
				pieces.append(UiStyle.gap(UiStyle.S2 + UiStyle.S1))
				pieces.append(_tag("New", small, [UiStyle.S2, 1, UiStyle.S2, 1], 0.1))
			_box.add_child(_line(pieces, UiStyle.S1 if _short else UiStyle.S2))
		if not _short:
			_box.add_child(UiStyle.gap(0, UiStyle.S1))
	# a new personal best, or how this run compares with the best
	if s.has("record"):
		var prev: Variant = s.record.get("prev")
		var pieces: Array = [["New personal best", "display_bold", _num_size(), UiStyle.ACCENT, 0.08, true, roundf(_num_size() * 1.4)]]
		if prev != null:
			pieces.append_array([_sp(), _delta(t - float(prev))])
		_box.add_child(_line(pieces))
		if str(s.get("ghost_note", "")) != "":
			_box.add_child(_line([[s.ghost_note, "text", small, UiStyle.TEXT_2]], 2))
	if s.has("best"):
		var b: Dictionary = s.best
		if s.get("ai", false):
			_box.add_child(_line([["Your best with the %s: %s (AI %s)" % [b.car, UiFormat.time(b.time), UiFormat.delta(t - float(b.time))], "text", small, UiStyle.TEXT]]))
		else:
			_box.add_child(_line([["Best with the %s: %s" % [b.car, UiFormat.time(b.time)], "text", small, UiStyle.TEXT], _sp(), _delta(t - float(b.time))]))
	# the next medal and how far this run was from it
	if s.has("next") and not (s.next as Dictionary).is_empty():
		var nx: Dictionary = s.next
		_box.add_child(_line([["Next", "text", small, UiStyle.TEXT_2], UiStyle.gap(UiStyle.S1), MedalDot.make(nx.medal, roundf(small * 0.78)),
			UiStyle.gap(5), ["%s %s" % [UiStyle.MEDAL_NAMES[nx.medal], UiFormat.time(nx.time)], "text", small, UiStyle.TEXT_2], _sp(),
			_delta(t - float(nx.time))], 2))
	for line in s.get("lines", []):
		_box.add_child(_line([[str(line), "text", small, UiStyle.TEXT]]))
	if s.has("score"):
		_box.add_child(_score(s.score))
	# lap times
	var laps: Array = s.get("laps", [])
	if laps.size() > 1:
		var row := UiStyle.hbox(UiStyle.S4, BoxContainer.ALIGNMENT_CENTER)
		for k in laps.size():
			var r := UiStyle.baseline_row([
				UiStyle.label("Lap %d" % (k + 1), "text", small, UiStyle.TEXT_2, 0.0, false, false, false, lh),
				UiStyle.label(UiFormat.time(laps[k]), "display", _num_size(), UiStyle.TEXT, 0.0, false, false, false, _num_size())], UiStyle.S1)
			row.add_child(r)
		var m := UiStyle.margin([0, UiStyle.S1 if _short else UiStyle.S3, 0, 0])
		m.add_child(row)
		_box.add_child(m)
	# keys
	var keys := UiStyle.hbox(UiStyle.S5, BoxContainer.ALIGNMENT_CENTER)
	var cap_h := 18.0 if _tiny else 22.0
	for k in [["R", "View", "race again"], ["Esc", "Menu", "back"]]:
		var item := UiStyle.hbox(UiStyle.S1)
		item.add_child(KeyCap.make(k[0], cap_h, 12 if _tiny else UiStyle.FS_S))
		if s.get("pad", false):
			item.add_child(KeyCap.make(k[1], cap_h, 12 if _tiny else UiStyle.FS_S))
		var l := UiStyle.label(" " + k[2], "text", small, UiStyle.TEXT_2, 0.0, false, false, false, lh)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.add_child(l)
		keys.add_child(item)
	var km := UiStyle.margin([0, UiStyle.S1 if _tiny else (UiStyle.S2 if _short else UiStyle.S4), 0, 0])
	km.add_child(keys)
	_box.add_child(km)
	_place()


## The score block: total and best, the breakdown in two columns (one in very narrow windows), the nitro note.
func _score(sc: Dictionary) -> Control:
	var small := _fs_small()
	var outer := UiStyle.margin([0, UiStyle.S2 if _short else UiStyle.S4, 0, 0])
	var col := UiStyle.vbox(0)
	outer.add_child(col)
	var rule := ColorRect.new()
	rule.color = UiStyle.LINE
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(rule)
	col.add_child(UiStyle.gap(0, UiStyle.S2 if _short else UiStyle.S3))
	# head: SCORE 40,940 and the best score
	var total_size := UiStyle.FS_L if _tiny else (24 if _short else (26 if _narrow else UiStyle.FS_XL))
	var head := UiStyle.hbox(UiStyle.S3, BoxContainer.ALIGNMENT_CENTER)
	var cap := UiStyle.caption("Score", UiStyle.TEXT_2, small)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(cap)
	var total := UiStyle.label(UiFormat.points(sc.get("total", 0)), "display_bold", total_size, UiStyle.TEXT, 0.0, false, false, false, total_size)
	total.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(total)
	var prev := int(sc.get("prev", -1))
	if sc.get("new_best", false):
		head.add_child(_tag("New best score", small, [UiStyle.S2, 1, UiStyle.S2, 1], 0.1))
		if prev >= 0:
			var was := UiStyle.label("was %s" % UiFormat.points(prev), "text", small, UiStyle.TEXT_2)
			was.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			head.add_child(was)
	elif prev >= 0:
		var b := UiStyle.label("Best with the %s: %s" % [sc.get("car", ""), UiFormat.points(prev)], "text", small, UiStyle.TEXT_2)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(b)
	col.add_child(head)
	# the breakdown, row by row in two columns
	var grid := GridContainer.new()
	grid.columns = 1 if _one_col else 2
	grid.add_theme_constant_override("h_separation", UiStyle.S4 if _narrow else UiStyle.S6)
	grid.add_theme_constant_override("v_separation", 0)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rows: Array = []
	var row_pad := 1 if _short else 3
	var pts_size := UiStyle.FS_S if _tiny else UiStyle.FS_M
	for r in sc.get("rows", []):
		var pts := int(r.points)
		var line := UiStyle.hbox(UiStyle.S3)
		var left := UiStyle.baseline_row([
			UiStyle.label(str(r.label), "text", small, UiStyle.TEXT, 0.0, false, false, false, roundf(small * 1.4)),
			UiStyle.label(str(r.get("note", "")), "text", small, UiStyle.TEXT_3, 0.0, false, false, false, roundf(small * 1.4))], UiStyle.S2)
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var p := UiStyle.label("%s%s" % ["+" if pts > 0 else "", UiFormat.points(pts)], "display", pts_size, UiStyle.BAD if pts < 0 else UiStyle.GOOD,
			0.0, false, false, false, roundf(small * 1.4))
		p.size_flags_vertical = Control.SIZE_SHRINK_END
		line.add_child(left)
		line.add_child(p)
		var m := UiStyle.margin([0, row_pad, 0, row_pad])
		m.add_child(line)
		m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(m)
		rows.append(m)
	# both columns as wide as the widest row (CSS 1fr 1fr)
	var widest := 0.0
	for m in rows:
		widest = maxf(widest, m.get_combined_minimum_size().x)
	for m in rows:
		m.custom_minimum_size.x = widest
	var gm := UiStyle.margin([0, UiStyle.S1 if _short else UiStyle.S3, 0, 0])
	gm.add_child(grid)
	col.add_child(gm)
	# the nitro the points earned
	var earned := float(sc.get("nitro_earned", 0.0))
	var lost := float(sc.get("nitro_lost", 0.0))
	var note := "Nitro earned: none"
	if earned >= 0.05:
		var e := "%.1f" % earned
		note = "Nitro earned: %s %s" % [e, "tank" if e == "1.0" else "tanks"]
		if lost >= 0.05:
			note += " (%.1f lost: the tank was full)" % lost
	col.add_child(_line([[note, "text", small, UiStyle.TEXT_2]], UiStyle.S2))
	return outer


## Centre the panel in the window: at least 360 wide, at most the window less 32 px (narrow
## windows: the window less 24 px).
func _place() -> void:
	if not visible:
		return
	var min_w := 0.0 if _narrow else 360.0
	var max_w := _win.x - (24.0 if _narrow else 32.0)
	var want := get_combined_minimum_size()
	var w := clampf(want.x, min_w, max_w)
	if _narrow:
		w = max_w
	size = Vector2(w, want.y)
	position = ((_win - size) * 0.5).round()
