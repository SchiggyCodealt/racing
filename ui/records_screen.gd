class_name RecordsScreen
extends "res://ui/dialog_screen.gd"
## records_screen.gd (v6.26.0; v6.32.0 the top 10s): the Records screen. At the top one track's top-10
## lists (sim/top_lists.gd): its ten fastest laps and the ten fastest times through each of its three
## sectors (sim/sectors.gd), by any car, each with the car (its upgrades and the date in the tooltip),
## and the career points a place pays (25 for 1st to 1 for 10th). Under them the table of every
## track: its fastest lap, the record of each sector (the time over the car and its upgrade code:
## "Quadra  E3 T3 N0 L3 W2", or "stock") and the ideal lap the three add up to (a dash until all three
## are set). Times come from every race you drive yourself (time trial, AI race, the field, cups);
## SaveData keeps them (get_tops / submit_tops, get_sectors), UiData.top_lists / sector_records read
## them.
## ------------------------------------------------------------------
## It opens on the menu's track (focus_track). Left / right (A / D, the d-pad, LB / RB) or the
## Previous / Next buttons go to another track; a click on a row of the table shows that track's
## lists. The menu opens it with R or its header button (pad: the button, then A); Esc, R, Backspace
## or the pad's B or Menu close it. Up / down (W / S, the d-pad) scroll it.
##
##   focus_track                  the track shown at the top (index; open() keeps it)
##   show_track(i)                show track i's lists (wraps round)
##   refresh()                    reads the records again (open() calls it)
##   lines -> PackedStringArray   what each track's row reads ("01 Rookie Oval: lap 1:12.004 Racer stock,
##                                S1 24.512 Racer stock, S2 -, S3 -, ideal -": tests)
##   top_lines -> PackedStringArray  the shown track's lists ("Laps: 1 1:12.004 Racer, 2 1:12.950
##                                Kestrel", "S1: -", ...: tests)

const TrackMapView := preload("res://ui/track_map_view.gd")

const MAP_SIZE := Vector2(64, 36)
const BIG_MAP := Vector2(112, 63)
const NAME_W := 180.0
const CELL_W := 156.0
const IDEAL_W := 92.0
const NARROW := 760.0
const SCROLL_STEP := 64

var lines := PackedStringArray()
var top_lines := PackedStringArray()
var focus_track := 0

var _intro: Label
var _count: Label
var _table: VBoxContainer
var _maps: Array = []        # [TrackMapView] (hidden on narrow windows)
var _fixed: Array = []       # [Control] the columns with a fixed width (shrink on narrow windows)
var _names: Array = []       # [Label] each table row's track name (the shown one in the accent)
var _rows: Array = []        # [Control] each table row
# the top 10s of the shown track
var _top_map: TrackMapView
var _top_num: Label
var _top_name: Label
var _top_grid: GridContainer
var _prev_btn: Button
var _next_btn: Button


func _init() -> void:
	super("Records")
	max_width = 1120.0
	body.add_child(UiStyle.gap(0, UiStyle.S2))
	_intro = UiStyle.label("", "text", UiStyle.FS_S, UiStyle.TEXT_2, 0.0, false, false, false, 19)
	_intro.text = "The ten fastest laps and the ten fastest runs through each third of every track, by any car, in any race you drive yourself. A time that makes a top 10 earns career points by its place: 25, 18, 15, 12, 10, 8, 6, 4, 2 and 1."
	_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_intro.custom_minimum_size.x = 1
	body.add_child(_intro)
	body.add_child(UiStyle.gap(0, UiStyle.S4))
	body.add_child(_top_block())
	body.add_child(UiStyle.gap(0, UiStyle.S5))
	_count = UiStyle.caption("", UiStyle.TEXT_3)
	body.add_child(_count)
	body.add_child(UiStyle.gap(0, UiStyle.S3))
	_table = UiStyle.vbox(0)
	body.add_child(_table)


func open() -> void:
	refresh()
	super.open()
	_scroll.scroll_vertical = 0


## Rebuild the lists and the table from the saved records.
func refresh() -> void:
	for c in _table.get_children():
		_table.remove_child(c)
		c.queue_free()
	_maps.clear()
	_fixed.clear()
	_names.clear()
	_rows.clear()
	_maps.append(_top_map)
	_table.add_child(_head_row())
	var out := PackedStringArray()
	var set_count := 0
	var n := UiData.track_count()
	for i in n:
		var info := UiData.track_info(i)
		var recs: Array = UiData.sector_records(str(info.id))
		var tops: Dictionary = UiData.top_lists(str(info.id))
		var lap: Dictionary = tops.laps[0] if not (tops.laps as Array).is_empty() else {}
		_table.add_child(_rule())
		_table.add_child(_track_row(i, info, recs, lap))
		var parts := PackedStringArray()
		parts.append("lap -" if lap.is_empty() else "lap %s %s %s" % [_short(float(lap.time)), _car_name(str(lap.car)), _up_code(lap.get("up"))])
		var ideal := 0.0
		for k in Sectors.COUNT:
			var r: Dictionary = recs[k] if k < recs.size() and recs[k] is Dictionary else {}
			if r.is_empty():
				parts.append("%s -" % Sectors.name(k))
				ideal = INF
			else:
				set_count += 1
				ideal += float(r.time)
				parts.append("%s %s %s %s" % [Sectors.name(k), _short(float(r.time)), _car_name(str(r.car)), _up_code(r.get("up"))])
		out.append("%s %s: %s, ideal %s" % [UiFormat.track_number(i), info.name, ", ".join(parts), _short(ideal) if is_finite(ideal) else "-"])
	lines = out
	_count.text = "Every track: %d of %d sectors set" % [set_count, n * Sectors.COUNT]
	show_track(focus_track)
	_on_layout(size.x)


## Show track `i`'s top 10s at the top (wraps round) and mark its row in the table.
func show_track(i: int) -> void:
	var n := UiData.track_count()
	if n <= 0:
		return
	focus_track = posmod(i, n)
	var info := UiData.track_info(focus_track)
	_top_map.map = UiData.track_map(focus_track)
	_top_map.queue_redraw()
	_top_num.text = UiFormat.track_number(focus_track)
	_top_name.text = str(info.name)
	for c in _top_grid.get_children():
		_top_grid.remove_child(c)
		c.queue_free()
	var tops: Dictionary = UiData.top_lists(str(info.id))
	var lists: Array = [tops.laps]
	lists.append_array(tops.sectors)
	var out := PackedStringArray()
	for li in lists.size():
		var list: Array = lists[li]
		_top_grid.add_child(_top_column(li, list))
		var parts := PackedStringArray()
		for p in list.size():
			parts.append("%d %s %s" % [p + 1, _short(float(list[p].time)), _car_name(str(list[p].car))])
		out.append("%s: %s" % [TopLists.list_name(li), ", ".join(parts) if not parts.is_empty() else "-"])
	top_lines = out
	for k in _names.size():
		(_names[k] as Label).add_theme_color_override("font_color", UiStyle.ACCENT if k == focus_track else UiStyle.TEXT)


func handle_keys(inp: Object) -> void:
	if inp.consume(["Escape", "Backspace", "KeyR", "PadB", "PadStart"]):
		UiSound.play("ui_back")
		close()
		return
	var dir: String = inp.nav_dir()
	if inp.consume(["ArrowLeft", "KeyA", "PadLB"]) or dir == "left":
		UiSound.play("ui_move")
		show_track(focus_track - 1)
	elif inp.consume(["ArrowRight", "KeyD", "PadRB"]) or dir == "right":
		UiSound.play("ui_move")
		show_track(focus_track + 1)
	elif inp.consume(["ArrowUp", "KeyW"]) or dir == "up":
		_scroll.scroll_vertical -= SCROLL_STEP
	elif inp.consume(["ArrowDown", "KeyS"]) or dir == "down":
		_scroll.scroll_vertical += SCROLL_STEP


func _on_layout(w: float) -> void:
	var narrow := w < NARROW
	for m: Control in _maps:
		m.visible = not narrow
	for c: Control in _fixed:
		c.custom_minimum_size.x = 1.0 if narrow else float(c.get_meta("w"))
	_top_grid.columns = 2 if narrow else 4
	for b: Button in [_prev_btn, _next_btn]:
		(b.get_meta("label") as Label).visible = not narrow
		b.custom_minimum_size.x = (b.get_meta("label") as Label).get_parent().get_combined_minimum_size().x + 2 * UiStyle.S3


# ---------------------------------------------------------------- the top 10s

## The shown track's heading (Previous, its map, number and name, Next), its four lists and the points.
func _top_block() -> Control:
	var col := UiStyle.vbox(0)
	var head := UiStyle.hbox(UiStyle.S4)
	_prev_btn = button_with_cap("Previous", "←")
	_prev_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_prev_btn.pressed.connect(func() -> void:
		UiSound.play("ui_move")
		show_track(focus_track - 1))
	head.add_child(_prev_btn)
	_top_map = TrackMapView.new()
	_top_map.line_color = UiStyle.TEXT_2
	_top_map.line_width = 2.0
	_top_map.dot_color = UiStyle.TEXT
	_top_map.dot_size = 5.0
	_top_map.mark_color = UiStyle.ACCENT
	_top_map.custom_minimum_size = BIG_MAP
	_top_map.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_top_map)
	var name_col := UiStyle.vbox(0)
	name_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top_num = UiStyle.caption("", UiStyle.TEXT_3)
	name_col.add_child(_top_num)
	_top_name = UiStyle.label("", "display_bold", UiStyle.FS_L, UiStyle.TEXT, 0.04, true, false, false, UiStyle.FS_L * 1.3)
	_top_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_top_name.custom_minimum_size.x = 1
	name_col.add_child(_top_name)
	head.add_child(name_col)
	_next_btn = button_with_cap("Next", "→")
	_next_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_next_btn.pressed.connect(func() -> void:
		UiSound.play("ui_move")
		show_track(focus_track + 1))
	head.add_child(_next_btn)
	col.add_child(head)
	col.add_child(UiStyle.gap(0, UiStyle.S4))
	_top_grid = GridContainer.new()
	_top_grid.columns = 4
	_top_grid.add_theme_constant_override("h_separation", UiStyle.S5)
	_top_grid.add_theme_constant_override("v_separation", UiStyle.S4)
	_top_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_top_grid)
	col.add_child(UiStyle.gap(0, UiStyle.S3))
	var pts := PackedStringArray()
	for p in TopLists.SIZE:
		pts.append("%s %d" % [Field.place_name(p + 1), TopLists.points_for(p + 1)])
	var legend := UiStyle.label("Points by place: " + " · ".join(pts), "text", UiStyle.FS_S, UiStyle.TEXT_3, 0.0, false, true)
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend.custom_minimum_size.x = 1
	col.add_child(legend)
	return col


## One list: its heading ("Fastest laps", "S1" ...) and ten places, each the time and the car.
func _top_column(li: int, list: Array) -> Control:
	var col := UiStyle.vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.custom_minimum_size.x = 1
	col.add_child(UiStyle.caption("Fastest laps" if li == 0 else "Sector %d" % li, UiStyle.TEXT_2))
	col.add_child(UiStyle.gap(0, UiStyle.S1))
	for p in TopLists.SIZE:
		var row := UiStyle.hbox(UiStyle.S2)
		var pl := UiStyle.label(str(p + 1), "text_semi", UiStyle.FS_S, UiStyle.ACCENT if p == 0 else UiStyle.TEXT_3, 0.0, false, true)
		pl.custom_minimum_size.x = 18
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(pl)
		var has: bool = p < list.size() and list[p] is Dictionary
		var e: Dictionary = list[p] if has else {}
		var tl := UiStyle.label(_short(float(e.time)) if has else "—", "display", UiStyle.FS_M, UiStyle.TEXT if has else UiStyle.TEXT_3, 0.0, false, true)
		tl.custom_minimum_size.x = 74
		tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tl)
		if has:
			var cl := UiStyle.label(_car_name(str(e.car)), "text", UiStyle.FS_S, UiStyle.TEXT_2)
			cl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			cl.custom_minimum_size.x = 1
			cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(cl)
			row.mouse_filter = Control.MOUSE_FILTER_PASS
			var date := str(e.get("date", ""))
			row.tooltip_text = "%s, %s%s\n%s place: %d points" % [_car_name(str(e.car)), Upgrades.text(_levels(e.get("up"))),
				("\nSet " + date.substr(0, 10)) if date != "" else "", Field.place_name(p + 1), TopLists.points_for(p + 1)]
		var m := UiStyle.margin([0, 1, 0, 1])
		m.add_child(row)
		col.add_child(m)
	return col


# ---------------------------------------------------------------- the table

func _head_row() -> Control:
	var row := _row()
	row.add_child(_fix(UiStyle.gap(MAP_SIZE.x, 0), MAP_SIZE.x, true))
	row.add_child(_fix(UiStyle.caption("Track", UiStyle.TEXT_3), NAME_W))
	row.add_child(_fix(UiStyle.caption("Fastest lap", UiStyle.TEXT_3), CELL_W))
	for k in Sectors.COUNT:
		row.add_child(_fix(UiStyle.caption(Sectors.name(k), UiStyle.TEXT_3), CELL_W))
	row.add_child(_fix(UiStyle.caption("Ideal lap", UiStyle.TEXT_3), IDEAL_W))
	var m := UiStyle.margin([0, 0, 0, UiStyle.S2])
	m.add_child(row)
	return m


func _track_row(i: int, info: Dictionary, recs: Array, lap: Dictionary) -> Control:
	var row := _row()
	var map := TrackMapView.new()
	map.map = UiData.track_map(i)
	map.line_color = UiStyle.TEXT_3
	map.line_width = 1.5
	map.dot_color = UiStyle.TEXT
	map.dot_size = 4.0
	map.mark_color = UiStyle.ACCENT
	map.custom_minimum_size = MAP_SIZE
	map.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_maps.append(map)
	row.add_child(map)
	var name_col := UiStyle.vbox(0)
	name_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_col.add_child(UiStyle.caption(UiFormat.track_number(i), UiStyle.TEXT_3))
	var nm := UiStyle.label(str(info.name), "text_semi", UiStyle.FS_M, UiStyle.TEXT)
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.custom_minimum_size.x = 1
	name_col.add_child(nm)
	_names.append(nm)
	row.add_child(_fix(name_col, NAME_W))
	row.add_child(_fix(_sector_cell(lap), CELL_W))
	var ideal := 0.0
	for k in Sectors.COUNT:
		var r: Dictionary = recs[k] if k < recs.size() and recs[k] is Dictionary else {}
		ideal = INF if r.is_empty() else ideal + float(r.time)
		row.add_child(_fix(_sector_cell(r), CELL_W))
	var il := UiStyle.label(_short(ideal) if is_finite(ideal) else "—", "display", UiStyle.FS_L,
		UiStyle.TEXT if is_finite(ideal) else UiStyle.TEXT_3, 0.0, false, true)
	il.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_fix(il, IDEAL_W))
	var m := UiStyle.margin([0, UiStyle.S2, 0, UiStyle.S2])
	m.add_child(row)
	# (v6.32) a click shows the track's top 10s at the top
	m.mouse_filter = Control.MOUSE_FILTER_PASS
	m.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	m.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			UiSound.play("ui_move")
			show_track(i)
			_scroll.scroll_vertical = 0)
	_rows.append(m)
	return m


## A record (a sector's or the fastest lap): the time over the car and its upgrades ("—" alone when
## there is none).
func _sector_cell(r: Dictionary) -> Control:
	var col := UiStyle.vbox(0)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if r.is_empty():
		col.add_child(UiStyle.label("—", "display", UiStyle.FS_L, UiStyle.TEXT_3, 0.0, false, true))
		return col
	col.add_child(UiStyle.label(_short(float(r.time)), "display", UiStyle.FS_L, UiStyle.TEXT, 0.0, false, true))
	var who := UiStyle.hbox(UiStyle.S2)
	who.add_child(UiStyle.label(_car_name(str(r.car)), "text_semi", UiStyle.FS_S, UiStyle.TEXT_2))
	var up := UiStyle.label(_up_code(r.get("up")), "text", UiStyle.FS_S, UiStyle.TEXT_3, 0.0, false, true)
	up.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	up.custom_minimum_size.x = 1
	up.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.add_child(up)
	col.add_child(who)
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	var date := str(r.get("date", ""))
	col.tooltip_text = "%s, %s%s" % [_car_name(str(r.car)), Upgrades.text(_levels(r.get("up"))),
		("\nSet " + date.substr(0, 10)) if date != "" else ""]
	return col


func _row() -> HBoxContainer:
	var r := UiStyle.hbox(UiStyle.S3)
	return r


func _rule() -> ColorRect:
	var rule := ColorRect.new()
	rule.color = UiStyle.LINE
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule


## A column `w` wide (1 px and sharing the row on narrow windows, unless `keep`).
func _fix(c: Control, w: float, keep: bool = false) -> Control:
	c.custom_minimum_size.x = w
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL if not keep else Control.SIZE_FILL
	if not keep:
		c.set_meta("w", w)
		_fixed.append(c)
	else:
		_maps.append(c)
	return c


static func _car_name(id: String) -> String:
	return str(UiData.car_info(id).get("name", id))


static func _levels(up: Variant) -> PackedInt32Array:
	return Upgrades.clean(up)


## "stock", or the upgrade code ("E3 T3 N0 L3 W2").
static func _up_code(up: Variant) -> String:
	var lv := _levels(up)
	return "stock" if Upgrades.is_stock(lv) else Upgrades.code(lv)


## A sector or lap time: "24.512" under a minute, else "1:04.512".
static func _short(t: float) -> String:
	var s := UiFormat.time(t)
	return s.substr(2) if s.begins_with("0:") else s
