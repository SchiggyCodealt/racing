class_name RaceHud
extends Control
## race_hud.gd
## ------------------------------------------------------------------
## The in-race heads-up display (web/src/ui/hud.js, v5 look): the track and car line, the
## race time, lap and checkpoint plates, the score with its combo chip, the drift / jump /
## wall contact building up, popups for every point won or lost, best time, the next medal
## (crossed out once missed, ticked when won), ghost notes, the countdown, split popups, the
## nitro gauge, speed, gear and rev bar, key-cap hints (keyboard or gamepad names), the
## Watch-AI network panel and the finish panel. Drawn over the 3D view; it never takes input.
##
## The play mode drives it with plain data, no game logic in here:
##   show_hud(on)            show / hide (and clear what the last race left)
##   set_mode(text)          "Night Highway · Racer", "WATCHING AI · …", "VS AI GHOST · …"
##   set_keys(keys, pad)     [[key, what, pad button or ""], ...] bottom left
##   update(state, dt)       every frame; state (hud.js update's s, snake_case):
##       time, lap, laps, cp, cps, sprint, speed (m/s), gear, rpm, spec {idle_rpm, redline,
##       upshift_rpm}, nitro (0..1 or null: no gauge), boosting, score {total, mult, live:
##       {kind: "drift"|"air"|"wall", time, points} or null} or null (no score), best (s or
##       null), medal {medal, time, all?} or null, finished, ghost_text, pad
##     and, optionally, the events of this frame: countdown ("3" / "GO!" / "" off), split
##     {label, time, delta or null}, pops [score events], mode, keys
##   countdown(text), split(label, time, delta), score_pops(events)   the same as events
##   show_panel(state) / hide_panel()   the finish panel (FinishPanel.update's state)
##   show_watch(on) / watch_net(net)   the AI's network, live (Watch the AI)
## Score events: {kind, text, points, mult, combo_lost} (score.js events: "Clean checkpoint"
## +1,500 x3, "Drift" +820, "Wall" −200 · combo lost, "Drift lost" ...).

const KeyCap := preload("res://ui/key_cap.gd")
const MedalDot := preload("res://ui/medal_dot.gd")
const NitroGauge := preload("res://ui/nitro_gauge.gd")
const RevBar := preload("res://ui/rev_bar.gd")

const POP_TIME := 2.2    # s a score popup stays up (it fades out over the last POP_FADE s)
const POP_FADE := 0.4
const POP_MAX := 4       # popups shown at once; the oldest goes first
const SPLIT_TIME := 2.2
const LIVE_NAMES := {"drift": "DRIFT", "air": "AIR"}

var panel_open := false
var finish: FinishPanel
var watch_panel: PanelContainer
var network_view: NetworkView

# top
var _mode: Label
var _time_plate: PanelContainer
var _time: Label
var _split: PanelContainer
var _split_time: Label
var _split_delta: Label
var _split_timer := 0.0
# left column
var _left: VBoxContainer
var _race_plate: PanelContainer
var _lap_lbl: Label
var _lap_val: Label
var _cp_val: Label
var _score_plate: PanelContainer
var _points: Label
var _combo: PanelContainer
var _combo_l: Label
var _live: PanelContainer
var _live_what: Label
var _live_pts: Label
var _live_line: Control
var _pops_box: VBoxContainer
var _pops: Array = []    # [{node, t}]
# right column
var _right: VBoxContainer
var _best_plate: PanelContainer
var _best_val: Label
var _medal_plate: PanelContainer
var _medal_lbl: Label
var _medal_dot: Control
var _medal_val: Label
var _medal_check: Control
var _medal_strike: Control
var _ghost_plate: PanelContainer
var _ghost_l: Label
# bottom
var _nitro: Control
var _speed_row: Control
var _speed: Label
var _rev: Control
var _keys: HFlowContainer
var _keys_data: Array = []
var _pad := false
var _countdown: Label
var _count_anim := 0.0
# state memory (only touch nodes when something changed)
var _score_state := ""
var _flash := 0.0
var _live_state := ""
var _medal_state := ""
var _kmh := -1
var _narrow := false
var _tiny := false
var _time_tpl := ""
var _watch_on := false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiStyle.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build()
	resized.connect(_layout)


# ================================================================= building

func _plate(pad: Array) -> PanelContainer:
	return UiStyle.panel(UiStyle.plate(pad))


func _build() -> void:
	# track and car (straight on the 3D view, with a shadow)
	_mode = UiStyle.label("", "text_semi", UiStyle.FS_S, UiStyle.TEXT, 0.0, false, false, true, 18)
	_mode.position = Vector2(UiStyle.HUD_X, UiStyle.S4 - 2)
	add_child(_mode)
	# race time
	_time_plate = _plate([UiStyle.S5, UiStyle.S1, UiStyle.S5, 0])
	_time = UiStyle.label("0:00.000", "display_bold", UiStyle.FS_NUM, UiStyle.TEXT, 0.0, false, false, false, roundf(UiStyle.FS_NUM * 1.15))
	_time_plate.add_child(_time)
	add_child(_time_plate)
	# split popup
	_split = _plate([UiStyle.S4, UiStyle.S1, UiStyle.S4, UiStyle.S1])
	var srow := UiStyle.hbox(UiStyle.S4)
	_split_time = UiStyle.label("", "display", UiStyle.FS_L, UiStyle.TEXT, 0.0, false, false, false, 24)
	_split_delta = UiStyle.label("", "display", UiStyle.FS_L, UiStyle.TEXT, 0.0, false, false, false, 24)
	srow.add_child(_split_time)
	srow.add_child(_split_delta)
	_split.add_child(srow)
	_split.modulate.a = 0.0
	add_child(_split)
	# left: lap and checkpoint, score, live line, popups
	_left = UiStyle.vbox(UiStyle.S2)
	_left.position = Vector2(UiStyle.HUD_X, 44)
	add_child(_left)
	_race_plate = _plate([UiStyle.S3, UiStyle.S1, UiStyle.S4, UiStyle.S1])
	var race := UiStyle.hbox(UiStyle.S4)
	_lap_lbl = UiStyle.caption("Lap", UiStyle.TEXT_2, UiStyle.FS_S)
	_lap_val = UiStyle.label("", "display_bold", UiStyle.FS_L, UiStyle.TEXT, 0.0, false, false, false, 26)
	race.add_child(UiStyle.baseline_row([_lap_lbl, _lap_val], UiStyle.S2))
	_cp_val = UiStyle.label("", "display_bold", UiStyle.FS_L, UiStyle.TEXT, 0.0, false, false, false, 26)
	race.add_child(UiStyle.baseline_row([UiStyle.caption("CP", UiStyle.TEXT_2, UiStyle.FS_S), _cp_val], UiStyle.S2))
	_race_plate.add_child(race)
	_race_plate.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_left.add_child(_race_plate)
	_score_plate = _plate([UiStyle.S3, UiStyle.S1, UiStyle.S3, UiStyle.S1])
	_score_plate.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var srow2 := UiStyle.hbox(UiStyle.S3)
	var lbl := UiStyle.caption("Score", UiStyle.TEXT_2, UiStyle.FS_S)
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	srow2.add_child(lbl)
	_points = UiStyle.label("0", "display_bold", UiStyle.FS_XL, UiStyle.TEXT, 0.0, false, false, false, roundf(UiStyle.FS_XL * 1.1))
	_points.custom_minimum_size.x = roundf(2.2 * UiStyle.FS_XL)
	_points.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	srow2.add_child(_points)
	_combo = UiStyle.panel(UiStyle.box(UiStyle.BG_4, true, [UiStyle.S2, 2, UiStyle.S2, 2]))
	_combo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_combo_l = UiStyle.label("x1", "display_bold", UiStyle.FS_M, UiStyle.TEXT_2, 0.0, false, false, false, roundf(UiStyle.FS_M * 1.2))
	_combo.add_child(_combo_l)
	srow2.add_child(_combo)
	_score_plate.add_child(srow2)
	_left.add_child(_score_plate)
	# the drift / jump / wall contact in progress: its line is always there, so the popups under it never jump
	_live_line = Control.new()
	_live_line.custom_minimum_size = Vector2(0, 28)
	_live_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_live = _plate([UiStyle.S3, 0, UiStyle.S3, 0])
	_live.custom_minimum_size.y = 28
	var lrow := UiStyle.hbox(UiStyle.S2)
	_live_what = UiStyle.label("", "display_bold", UiStyle.FS_L, UiStyle.TEXT, 0.02, false, false, false, UiStyle.FS_L)
	_live_pts = UiStyle.label("", "display_bold", UiStyle.FS_L, UiStyle.GOOD, 0.02, false, false, false, UiStyle.FS_L)
	for l in [_live_what, _live_pts]:
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		lrow.add_child(l)
	_live.add_child(lrow)
	_live.visible = false
	_live_line.add_child(_live)
	_left.add_child(_live_line)
	_pops_box = UiStyle.vbox(UiStyle.S1)
	var pm := UiStyle.margin([0, -UiStyle.S1, 0, 0])
	pm.add_child(_pops_box)
	_left.add_child(pm)
	# right: best, the medal to aim for, ghost notes
	_right = UiStyle.vbox(UiStyle.S2)
	add_child(_right)
	_best_plate = _plate([UiStyle.S3, UiStyle.S1, UiStyle.S3, UiStyle.S1])
	_best_plate.size_flags_horizontal = Control.SIZE_SHRINK_END
	_best_val = UiStyle.label("—", "display_bold", UiStyle.FS_L, UiStyle.TEXT, 0.0, false, false, false, 26)
	_best_plate.add_child(UiStyle.baseline_row([UiStyle.caption("Best", UiStyle.TEXT_2, UiStyle.FS_S), _best_val], UiStyle.S2))
	_right.add_child(_best_plate)
	_medal_plate = _plate([UiStyle.S3, UiStyle.S1, UiStyle.S3, UiStyle.S1])
	_medal_plate.size_flags_horizontal = Control.SIZE_SHRINK_END
	var mrow := UiStyle.hbox(UiStyle.S2)
	_medal_lbl = UiStyle.caption("Gold", UiStyle.TEXT_2, UiStyle.FS_S)
	_medal_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mrow.add_child(_medal_lbl)
	var dot_box := UiStyle.margin([UiStyle.S1, 0, 0, 0])
	dot_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_medal_dot = MedalDot.make("gold", roundf(15 * 0.78))
	dot_box.add_child(_medal_dot)
	mrow.add_child(dot_box)
	_medal_val = UiStyle.label("", "display_bold", UiStyle.FS_L, UiStyle.TEXT, 0.0, false, false, false, 26)
	_medal_val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_medal_strike = Control.new()
	_medal_strike.set_anchors_preset(Control.PRESET_FULL_RECT)
	_medal_strike.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_medal_strike.draw.connect(func() -> void:
		var y := _medal_strike.size.y * 0.5 + 1.0
		_medal_strike.draw_line(Vector2(0, y), Vector2(_medal_strike.size.x, y), UiStyle.TEXT_3, 1.5))
	_medal_val.add_child(_medal_strike)
	mrow.add_child(_medal_val)
	_medal_check = Control.new()
	_medal_check.custom_minimum_size = Vector2(16, 14)
	_medal_check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_medal_check.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_medal_check.draw.connect(func() -> void: # (a green tick: the medal is won)
		_medal_check.draw_polyline(PackedVector2Array([Vector2(3, 6), Vector2(6.5, 9.5), Vector2(13, 2.5)]), UiStyle.GOOD, 2.5, true))
	mrow.add_child(_medal_check)
	_medal_plate.add_child(mrow)
	_right.add_child(_medal_plate)
	_ghost_plate = _plate([UiStyle.S3, 3, UiStyle.S3, 3])
	_ghost_plate.size_flags_horizontal = Control.SIZE_SHRINK_END
	_ghost_l = UiStyle.label("", "text", UiStyle.FS_S, UiStyle.TEXT_2, 0.0, false, false, false, 18)
	_ghost_plate.add_child(_ghost_l)
	_right.add_child(_ghost_plate)
	# bottom right: nitro, speed, gear and revs
	_nitro = NitroGauge.new()
	add_child(_nitro)
	_speed = UiStyle.label("0", "display_bold", UiStyle.FS_SPEED, UiStyle.TEXT, 0.0, false, false, false, UiStyle.FS_SPEED)
	UiStyle.add_shadow(_speed, Color(0, 0, 0, 0.45), 2, 8)
	var unit := UiStyle.caption("km/h", UiStyle.TEXT_2, UiStyle.FS_S)
	_speed_row = UiStyle.baseline_row([_speed, unit], UiStyle.S2)
	add_child(_speed_row)
	_rev = RevBar.new()
	add_child(_rev)
	# bottom left: key hints
	_keys = HFlowContainer.new()
	_keys.add_theme_constant_override("h_separation", UiStyle.S4)
	_keys.add_theme_constant_override("v_separation", UiStyle.S1)
	_keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_keys)
	# countdown
	_countdown = UiStyle.label("", "display_bold", UiStyle.FS_COUNT, UiStyle.ACCENT, 0.0, false, false, false, UiStyle.FS_COUNT)
	UiStyle.add_shadow(_countdown, Color(0, 0, 0, 0.3), 4, 16)
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown.visible = false
	add_child(_countdown)
	# the AI's network (Watch the AI)
	watch_panel = UiStyle.panel(UiStyle.box(UiStyle.PANEL, false, [UiStyle.S3, UiStyle.S3, UiStyle.S3, UiStyle.S3]))
	var wcol := UiStyle.vbox(5)
	wcol.add_child(UiStyle.label("AI network, live", "display_bold", UiStyle.FS_S, UiStyle.TEXT_2, 0.1, true, false, false, UiStyle.FS_S))
	network_view = NetworkView.new()
	network_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wcol.add_child(network_view)
	watch_panel.add_child(wcol)
	watch_panel.visible = false
	add_child(watch_panel)
	# the finish panel, above everything
	finish = FinishPanel.new()
	finish.placed.connect(_apply_panel_visibility)
	add_child(finish)


# ================================================================= the race

func show_hud(on: bool) -> void:
	visible = on
	# clear anything left over from the previous race
	hide_panel()
	countdown("")
	_split.modulate.a = 0.0
	_split_timer = 0.0
	reset_score()
	_layout()


func set_mode(text: String) -> void:
	_mode.text = text


## Key hints at the bottom left: [[key, what it does, gamepad button or ""], ...]. They name the
## gamepad buttons while the pad is the last input used.
func set_keys(keys: Array, pad: bool = _pad) -> void:
	_keys_data = keys
	_pad = pad
	for c in _keys.get_children():
		_keys.remove_child(c)
		c.queue_free()
	for k in keys:
		var item := UiStyle.hbox(UiStyle.S1)
		var cap: String = k[2] if pad and k.size() > 2 and str(k[2]) != "" else k[0]
		var small := _narrow
		item.add_child(KeyCap.make(cap, 20.0 if small else 22.0, 12 if small else UiStyle.FS_S))
		var l := UiStyle.label(" " + str(k[1]), "text", 12 if small else UiStyle.FS_S, UiStyle.TEXT_2, 0.0, false, false, true, 18)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.add_child(l)
		_keys.add_child(item)
	_layout()


func update(s: Dictionary, dt: float) -> void:
	if s.has("mode"):
		set_mode(s.mode)
	if s.has("keys"):
		set_keys(s.keys, bool(s.get("pad", _pad)))
	if s.has("countdown"):
		countdown(str(s.countdown))
	if s.has("split") and s.split is Dictionary:
		split(s.split.label, s.split.time, s.split.get("delta"))
	if s.has("pops") and s.pops is Array and not (s.pops as Array).is_empty():
		score_pops(s.pops)
	_set_time(UiFormat.time(s.get("time", 0.0)))
	var sprint: bool = s.get("sprint", false)
	_lap_lbl.text = "Sprint" if sprint else "Lap"
	_lap_val.text = "" if sprint else "%d/%d" % [int(s.get("lap", 1)), int(s.get("laps", 1))]
	_lap_val.get_parent().visible = not sprint # (its baseline holder)
	_cp_val.text = "%d/%d" % [int(s.get("cp", 0)), int(s.get("cps", 0))]
	var kmh := roundi(float(s.get("speed", 0.0)) * 3.6)
	if kmh != _kmh:
		_kmh = kmh
		_speed.text = str(kmh)
	_best_val.text = "—" if s.get("best") == null else UiFormat.time(s.best) # (a dash until there is a best time)
	var gt := str(s.get("ghost_text", ""))
	_ghost_l.text = gt
	_ghost_plate.visible = gt != ""
	_update_medal(s.get("medal"), float(s.get("time", 0.0)), bool(s.get("finished", false)))
	if s.get("gear") == null or s.get("rpm") == null:
		_rev.visible = false
	else:
		_rev.visible = not panel_open
		_rev.set_revs(int(s.gear), float(s.rpm), s.get("spec", {}))
	if s.get("nitro") == null:
		_nitro.visible = false
	else:
		_nitro.visible = not panel_open
		_nitro.set_level(float(s.nitro), bool(s.get("boosting", false)))
	_update_score(s.get("score"), dt)
	if bool(s.get("pad", false)) != _pad and not _keys_data.is_empty():
		set_keys(_keys_data, bool(s.get("pad", false)))
	if _split_timer > 0.0:
		_split_timer -= dt
		_split.modulate.a = minf(1.0, _split.modulate.a + dt / 0.2)
		if _split_timer <= 0.0:
			_split_timer = 0.0
	elif _split.modulate.a > 0.0:
		_split.modulate.a = maxf(0.0, _split.modulate.a - dt / 0.2)
	_animate(dt)


## The race time. Its digits are proportional (as in the approved v5 look), so the label is as wide
## as the same time written with zeros and the text is left-aligned in it: the plate keeps its
## width and the digits that don't change don't move while the milliseconds tick.
func _set_time(t: String) -> void:
	if t == _time.text:
		return
	_time.text = t
	var tpl := t
	for d in "123456789":
		tpl = tpl.replace(d, "0")
	if tpl != _time_tpl:
		_time_tpl = tpl
		_fit_time()


func _fit_time() -> void:
	var fs := _time.get_theme_font_size("font_size")
	_time.custom_minimum_size.x = ceilf(_time.get_theme_font("font").get_string_size(_time_tpl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)


## The medal to aim for under the best time: {medal, time, all?} (all: every medal is won, the
## author time is shown) or null. Struck through once this run's `time` is past it, ticked when won.
func _update_medal(target: Variant, time: float, finished: bool) -> void:
	var has := target is Dictionary and not (target as Dictionary).is_empty()
	var over := has and roundi(time * 1000.0) > roundi(float(target.time) * 1000.0) # (to the ms, as shown)
	var cls := ""
	if has:
		cls = "won" if target.get("all", false) or (finished and not over) else "missed" if over else ""
	var st := "%s %s %s" % [target.medal, target.time, cls] if has else "none"
	if st == _medal_state:
		return
	_medal_state = st
	_medal_plate.visible = has
	if not has:
		return
	_medal_lbl.text = UiStyle.MEDAL_NAMES[target.medal]
	_medal_dot.medal = target.medal
	_medal_dot.alpha = 0.45 if cls == "missed" else 1.0
	_medal_val.text = UiFormat.time(target.time)
	_medal_val.add_theme_color_override("font_color", UiStyle.TEXT_3 if cls == "missed" else UiStyle.TEXT)
	_medal_strike.visible = cls == "missed"
	_medal_check.visible = cls == "won"


## The score block: s = {total, mult, live} or null (no score: watching the AI). The total briefly
## turns green or red when it changes; the combo chip is in the accent from x2, dim at x1 and
## red at x1 after a wall contact or respawn broke a combo.
func _update_score(s: Variant, dt: float) -> void:
	if s == null:
		if _score_state != "off":
			_score_state = "off"
			_score_plate.visible = false
			_live_line.visible = false
			reset_score()
		return
	if _score_state == "off" or _score_state == "":
		_score_plate.visible = not (panel_open and _narrow)
		_live_line.visible = not (panel_open and _narrow)
	var total := int(s.get("total", 0))
	var mult := int(s.get("mult", 1))
	var st := "%d %d" % [total, mult]
	if st != _score_state:
		# (no previous race state: a new race starts without a flash)
		var prev_total := total
		var prev_mult := mult
		if _score_state != "" and _score_state != "off":
			prev_total = int(_score_state.get_slice(" ", 0))
			prev_mult = int(_score_state.get_slice(" ", 1))
		_score_state = st
		_points.text = UiFormat.points(total)
		_combo_l.text = "x%d" % mult
		var combo := "on" if mult > 1 else "reset" if prev_mult > 1 else ""
		var bg := UiStyle.ACCENT if combo == "on" else Color(1.0, 93 / 255.0, 82 / 255.0, 0.18) if combo == "reset" else UiStyle.BG_4
		_combo.add_theme_stylebox_override("panel", UiStyle.box(bg, true, [UiStyle.S2, 2, UiStyle.S2, 2]))
		_combo_l.add_theme_color_override("font_color", UiStyle.ACCENT_INK if combo == "on" else UiStyle.BAD if combo == "reset" else UiStyle.TEXT_2)
		if total != prev_total:
			_points.add_theme_color_override("font_color", UiStyle.GOOD if total > prev_total else UiStyle.BAD)
			_flash = 0.45
	if _flash > 0.0:
		_flash -= dt
		if _flash <= 0.0:
			_points.add_theme_color_override("font_color", UiStyle.TEXT)
	# the drift / jump / wall contact in progress: "DRIFT 1.2 s +640", "AIR 1.8 s +900", "WALL −350"
	var l: Variant = s.get("live")
	var what := ""
	var pts := ""
	if l is Dictionary:
		if l.kind == "wall":
			what = "WALL"
			pts = UiFormat.points(l.points) if float(l.points) < 0 else ""
		else:
			what = "%s %.1f s" % [LIVE_NAMES.get(l.kind, ""), float(l.time)]
			pts = "+" + UiFormat.points(l.points)
	var live := "%s|%s" % [what, pts]
	if live != _live_state:
		_live_state = live
		_live.visible = l is Dictionary
		_live_what.text = what
		_live_pts.text = pts
		_live_pts.visible = pts != ""
		var wall: bool = l is Dictionary and l.kind == "wall"
		_live_what.add_theme_color_override("font_color", UiStyle.BAD if wall else UiStyle.TEXT)
		_live_pts.add_theme_color_override("font_color", UiStyle.BAD if wall else UiStyle.GOOD)
		_live.reset_size()
		_live.position = Vector2.ZERO
	# popups age and fade
	for i in range(_pops.size() - 1, -1, -1):
		var p: Dictionary = _pops[i]
		p.t -= dt
		if p.t <= 0.0:
			p.node.queue_free()
			_pops.remove_at(i)


## Popups for score events: "Clean checkpoint +1,500 x3", "Drift +820", "Wall −200 · combo lost", "Drift lost" ...
func score_pops(events: Array) -> void:
	for ev in events:
		var pts := int(ev.get("points", 0))
		var kind := str(ev.get("kind", ""))
		var bad := pts < 0 or kind == "wall" or kind == "respawn"
		var plate := UiStyle.plate([UiStyle.S3, 3, UiStyle.S3, 3])
		var stripe := kind == "lap" or kind == "run" # (lap and run bonuses: an accent edge)
		var p := UiStyle.panel(plate)
		var row := UiStyle.hbox(0)
		var items: Array = []
		var text_col := UiStyle.TEXT_2 if (pts == 0 and not bad) else UiStyle.TEXT
		items.append(UiStyle.label(str(ev.get("text", "")), "text_semi", UiStyle.FS_S, text_col, 0.0, false, false, false, 16))
		if pts != 0:
			items.append(UiStyle.label(" %s%s" % ["+" if pts > 0 else "", UiFormat.points(pts)], "display_bold", UiStyle.FS_M,
				UiStyle.GOOD if pts > 0 else UiStyle.BAD, 0.0, false, false, false, 16))
		if int(ev.get("mult", 1)) > 1:
			items.append(UiStyle.label(" x%d" % int(ev.mult), "display_bold", UiStyle.FS_M, UiStyle.ACCENT, 0.0, false, false, false, 16))
		if ev.get("combo_lost", false):
			items.append(UiStyle.label(" · combo lost", "text_semi", UiStyle.FS_S, text_col, 0.0, false, false, false, 16))
		row.add_child(UiStyle.baseline_row(items, 0))
		p.add_child(row)
		p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		if stripe:
			p.draw.connect(func() -> void:
				var r := Rect2(0, 0, 3, p.size.y)
				var d := p.size.y * UiStyle.SKEW * 0.5
				p.draw_colored_polygon(PackedVector2Array([Vector2(d, 0), Vector2(d + 3, 0), Vector2(3 - d, r.size.y), Vector2(-d, r.size.y)]), UiStyle.ACCENT))
		# (a holder keeps the popup's place in the column while the popup itself slides in)
		var holder := Control.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(p)
		var fit := func() -> void:
			p.reset_size()
			holder.custom_minimum_size = p.get_combined_minimum_size()
		fit.call()
		p.minimum_size_changed.connect(fit) # (labels measure their final fonts once in the tree)
		holder.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_pops_box.add_child(holder)
		_pops.append({"node": holder, "pop": p, "t": POP_TIME})
		while _pops.size() > POP_MAX:
			_pops.pop_front().node.queue_free()


## Clear the popups and the live line and forget the last total (a new race).
func reset_score() -> void:
	for p in _pops:
		p.node.queue_free()
	_pops.clear()
	_live_state = ""
	_flash = 0.0
	if _score_state != "off":
		_score_state = ""
	if _live:
		_live.visible = false
	if _points:
		_points.add_theme_color_override("font_color", UiStyle.TEXT)


## The 3-2-1-GO countdown ("" hides it); each new text pops in (zooms from 1.8x).
func countdown(text: String) -> void:
	if text == "":
		_countdown.visible = false
		_countdown.text = ""
		return
	if _countdown.text != text:
		_countdown.text = text
		_count_anim = 0.5
	_countdown.visible = true


## Split popup at a checkpoint: "CP 3  1:02.345" and the delta to the best run (or null).
func split(label: String, time: float, delta: Variant) -> void:
	_split_time.text = "%s  %s" % [label, UiFormat.time(time)]
	if delta == null:
		_split_delta.text = ""
		_split_delta.visible = false
	else:
		_split_delta.visible = true
		_split_delta.text = UiFormat.delta(float(delta))
		_split_delta.add_theme_color_override("font_color", UiStyle.GOOD if float(delta) <= 0 else UiStyle.BAD)
	_split_timer = SPLIT_TIME


## Pop-in, fade-out and countdown animations (call with the frame time; update does).
func _animate(dt: float) -> void:
	for p in _pops:
		var age: float = POP_TIME - p.t
		var node: Control = p.pop
		var a_in := clampf(age / 0.2, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - a_in, 3.0) # ease-out
		var fade := clampf(p.t / POP_FADE, 0.0, 1.0) if p.t <= POP_FADE else 1.0
		node.modulate.a = minf(e, fade)
		node.position.x = -14.0 * (1.0 - e)
	if _count_anim > 0.0:
		_count_anim = maxf(0.0, _count_anim - dt)
		var k := 1.0 - _count_anim / 0.5
		var e := 1.0 - pow(1.0 - k, 3.0)
		var sc := lerpf(1.8, 1.0, e)
		_countdown.pivot_offset = _countdown.size * 0.5
		_countdown.scale = Vector2(sc, sc)
		_countdown.modulate.a = e


# ================================================================= the finish panel and the AI view

## Show the finish panel (FinishPanel.update's state). The speed, gear, nitro and key hints go while
## it is open (the run is over and the panel lists the keys); narrow and short windows also hide the
## rows the panel would cover.
func show_panel(state: Dictionary) -> void:
	panel_open = true
	finish.set_window_size(size)
	finish.update(state)
	_apply_panel_visibility()


func hide_panel() -> void:
	panel_open = false
	finish.hide_panel()
	_apply_panel_visibility()


func _apply_panel_visibility() -> void:
	for c in [_speed_row, _keys]:
		c.visible = not panel_open
	if panel_open:
		_rev.visible = false
		_nitro.visible = false
	# the parts the panel would cover go (as the web does in narrow windows, and here also when a
	# short window's panel reaches the score column or the best-time column): the panel shows them all
	var fr := Rect2(finish.position, finish.size)
	var left_w := 0.0 # (every part's width, hidden or not, so hiding them doesn't change the answer)
	for c in [_race_plate, _score_plate, _pops_box]:
		left_w = maxf(left_w, c.get_combined_minimum_size().x)
	var left_end := _left.position.x + left_w + UiStyle.S2
	var covers_left := panel_open and fr.position.x < left_end
	var covers_right := panel_open and fr.end.x > _right.position.x - UiStyle.S2 and fr.position.y < _right.position.y + _right.size.y
	var narrow_hide := panel_open and (_narrow or covers_left)
	_pops_box.visible = not narrow_hide
	_right.visible = not (panel_open and (_narrow or covers_right or _tiny))
	# (the split goes under a tall panel: hidden then, the panel shows the time)
	var split_y := 80.0 if not _narrow else 118.0
	_split.visible = not narrow_hide and not (panel_open and (_tiny or finish.position.y < split_y + _split.size.y + UiStyle.S2))
	if _score_state != "off":
		_score_plate.visible = not narrow_hide
		_live_line.visible = not narrow_hide
	for c in [_mode, _time_plate, _left]:
		c.visible = not (panel_open and _tiny)
	# the race time too, under a panel tall enough to reach it (v6.5.0: the payout): the panel shows the time
	if panel_open and Rect2(_time_plate.position, _time_plate.size).grow(UiStyle.S1).intersects(fr):
		_time_plate.visible = false
	# the lap plate too, when the (full-width) panel reaches up to it
	var race_r := Rect2(_left.position, _race_plate.get_combined_minimum_size())
	_race_plate.visible = not (panel_open and race_r.grow(UiStyle.S1).intersects(fr))
	# the AI's network goes under the finish panel in small windows: hidden while they would overlap
	watch_panel.visible = _watch_on and not (panel_open and Rect2(watch_panel.position, watch_panel.size).intersects(fr))


func show_watch(on: bool) -> void:
	_watch_on = on
	watch_panel.visible = on
	_layout()


## Draw the AI's network (see NetworkView.draw_net).
func watch_net(net: Dictionary) -> void:
	network_view.draw_net(net)


# ================================================================= layout

## Place everything for the HUD's size (style.css #hud positions; a smaller HUD under 1000 px wide).
## Every part is pinned to its edge of the window with a zero-size rect and a grow direction, so it
## always takes its minimum size and grows away from that edge (a longer time or score never
## pushes a read-out off the window, and nothing has to be placed again when a text changes).
func _layout() -> void:
	var w := size.x
	var h := size.y
	if w <= 0:
		return
	var narrow := w < 1000
	var tiny := h <= 520
	if narrow != _narrow:
		_narrow = narrow
		_restyle()
	_tiny = tiny
	var x := float(UiStyle.HUD_X if not narrow else 10)
	_pin(_mode, 0, 0, x, UiStyle.S4 - 2 if not narrow else UiStyle.S2)
	_pin(_time_plate, 0.5, 0, 0, UiStyle.S4 if not narrow else 28)
	_pin(_split, 0.5, 0, 0, 80 if not narrow else 118)
	_pin(_left, 0, 0, x, 44 if not narrow else 76)
	_pin(_right, 1, 0, x, UiStyle.S4 if not narrow else 76)
	var nw := 240.0 if not narrow else 170.0
	_pin(_nitro, 1, 1, x, 125 if not narrow else 89, Vector2(nw, 16))
	_pin(_speed_row, 1, 1, x, 54 if not narrow else 44)
	_pin(_rev, 1, 1, x, UiStyle.S5 if not narrow else UiStyle.S3, Vector2(nw, 26))
	_pin(_keys, 0, 1, x, UiStyle.S5 if not narrow else 64, Vector2(w * 0.45 if narrow else w - 2 * x - 260, 0))
	_pin(watch_panel, 0, 1, x if not narrow else 8, 64 if not narrow else 96, Vector2(minf(430.0, 0.4 * w), minf(300.0, 0.38 * h)))
	_pin(_countdown, 0.5, 0.34, 0, 0)
	finish.set_window_size(size)
	_apply_panel_visibility()


## Pin `c` to a point of the window: h / v are the anchor (0 left / top, 0.5 centre, 1 right /
## bottom; v 0.34 for the countdown, centred on it); dx / dy how far in from that edge. Its rect
## there is `fixed` (0: its minimum size), growing away from the edge.
func _pin(c: Control, h: float, v: float, dx: float, dy: float, fixed: Vector2 = Vector2.ZERO) -> void:
	c.anchor_left = h
	c.anchor_right = h
	c.anchor_top = v
	c.anchor_bottom = v
	c.grow_horizontal = Control.GROW_DIRECTION_END if h == 0 else Control.GROW_DIRECTION_BEGIN if h == 1 else Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_END if v == 0 else Control.GROW_DIRECTION_BEGIN if v == 1 else Control.GROW_DIRECTION_BOTH
	var ex := dx if h == 0 else -dx if h == 1 else 0.0
	var ey := dy if v == 0 else -dy if v == 1 else 0.0
	if h == 1:
		c.offset_left = ex - fixed.x
		c.offset_right = ex
	else:
		c.offset_left = ex
		c.offset_right = ex + fixed.x
	if v == 1:
		c.offset_top = ey - fixed.y
		c.offset_bottom = ey
	else:
		c.offset_top = ey
		c.offset_bottom = ey + fixed.y


## Font sizes for the phone-sized HUD (under 1000 px wide) or the normal one.
func _restyle() -> void:
	var n := _narrow
	UiStyle.style_label(_time, "display_bold", 28 if n else UiStyle.FS_NUM, UiStyle.TEXT, 0.0, false, false, false, roundf((28 if n else UiStyle.FS_NUM) * 1.15))
	_fit_time()
	UiStyle.style_label(_speed, "display_bold", 40 if n else UiStyle.FS_SPEED, UiStyle.TEXT, 0.0, false, false, false, 40 if n else UiStyle.FS_SPEED)
	UiStyle.add_shadow(_speed, Color(0, 0, 0, 0.45), 2, 8)
	UiStyle.style_label(_countdown, "display_bold", 96 if n else UiStyle.FS_COUNT, UiStyle.ACCENT, 0.0, false, false, false, 96 if n else UiStyle.FS_COUNT)
	for l in [_lap_val, _cp_val, _best_val, _medal_val]:
		UiStyle.style_label(l, "display_bold", UiStyle.FS_M if n else UiStyle.FS_L, l.get_theme_color("font_color"), 0.0, false, false, false, 21 if n else 26)
	UiStyle.style_label(_points, "display_bold", UiStyle.FS_L if n else UiStyle.FS_XL, _points.get_theme_color("font_color"), 0.0, false, false, false, roundf((UiStyle.FS_L if n else UiStyle.FS_XL) * 1.1))
	_points.custom_minimum_size.x = roundf(2.2 * (UiStyle.FS_L if n else UiStyle.FS_XL))
	if not _keys_data.is_empty():
		set_keys(_keys_data, _pad)
