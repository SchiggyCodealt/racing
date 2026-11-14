class_name RecordsScreen
extends "res://ui/dialog_screen.gd"
## records_screen.gd (v6.26.0): the Sector records screen: for every track the fastest time through
## each of its three sectors (sim/sectors.gd) by any car, with that car and its upgrades, and the ideal
## lap the three add up to. Records come from every race you drive yourself (time trial, AI race, the
## field, cups); SaveData keeps them (get_sectors / submit_sectors), UiData.sector_records reads them.
## ------------------------------------------------------------------
## One row a track: its small map with yellow dots where the sectors meet, the number and name, then
## S1 S2 S3 (the time over the car and its upgrade code: "Quadra  E3 T3 N0 L3 W2", or "stock"; the
## full upgrades and the date in the tooltip) and the ideal lap (a dash until all three are set).
## The menu opens it with R or its header button (pad: the button, then A); Esc, R, Backspace or the
## pad's B or Menu close it. The arrows, W / S or the d-pad scroll it.
##
##   refresh()                    reads the records again (open() calls it)
##   lines -> PackedStringArray   what each track's row reads ("01 Rookie Oval: S1 24.512 Racer stock,
##                                S2 -, S3 -, ideal -": tests)

const TrackMapView := preload("res://ui/track_map_view.gd")

const MAP_SIZE := Vector2(64, 36)
const NAME_W := 190.0
const CELL_W := 168.0
const IDEAL_W := 96.0
const NARROW := 760.0
const SCROLL_STEP := 64

var lines := PackedStringArray()

var _intro: Label
var _count: Label
var _table: VBoxContainer
var _maps: Array = []        # [TrackMapView] (hidden on narrow windows)
var _fixed: Array = []       # [Control] the columns with a fixed width (shrink on narrow windows)


func _init() -> void:
	super("Sector records")
	max_width = 1000.0
	body.add_child(UiStyle.gap(0, UiStyle.S2))
	_intro = UiStyle.label("", "text", UiStyle.FS_S, UiStyle.TEXT_2, 0.0, false, false, false, 19)
	_intro.text = "The fastest run through each third of every track, by any car, in any race you drive yourself. The yellow dots on a map are where its sectors meet. The ideal lap adds the three up."
	_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_intro.custom_minimum_size.x = 1
	body.add_child(_intro)
	body.add_child(UiStyle.gap(0, UiStyle.S2))
	_count = UiStyle.caption("", UiStyle.TEXT_3)
	body.add_child(_count)
	body.add_child(UiStyle.gap(0, UiStyle.S4))
	_table = UiStyle.vbox(0)
	body.add_child(_table)


func open() -> void:
	refresh()
	super.open()
	_scroll.scroll_vertical = 0


## Rebuild the table from the saved records.
func refresh() -> void:
	for c in _table.get_children():
		_table.remove_child(c)
		c.queue_free()
	_maps.clear()
	_fixed.clear()
	_table.add_child(_head_row())
	var out := PackedStringArray()
	var set_count := 0
	var n := UiData.track_count()
	for i in n:
		var info := UiData.track_info(i)
		var recs: Array = UiData.sector_records(str(info.id))
		_table.add_child(_rule())
		_table.add_child(_track_row(i, info, recs))
		var parts := PackedStringArray()
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
	_count.text = "%d of %d sectors set" % [set_count, n * Sectors.COUNT]
	_on_layout(size.x)


func handle_keys(inp: Object) -> void:
	if inp.consume(["Escape", "Backspace", "KeyR", "PadB", "PadStart"]):
		UiSound.play("ui_back")
		close()
		return
	var dir: String = inp.nav_dir()
	if inp.consume(["ArrowUp", "KeyW"]) or dir == "up":
		_scroll.scroll_vertical -= SCROLL_STEP
	elif inp.consume(["ArrowDown", "KeyS"]) or dir == "down":
		_scroll.scroll_vertical += SCROLL_STEP


func _on_layout(w: float) -> void:
	var narrow := w < NARROW
	for m: Control in _maps:
		m.visible = not narrow
	for c: Control in _fixed:
		c.custom_minimum_size.x = 1.0 if narrow else float(c.get_meta("w"))


func _head_row() -> Control:
	var row := _row()
	row.add_child(_fix(UiStyle.gap(MAP_SIZE.x, 0), MAP_SIZE.x, true))
	row.add_child(_fix(UiStyle.caption("Track", UiStyle.TEXT_3), NAME_W))
	for k in Sectors.COUNT:
		row.add_child(_fix(UiStyle.caption(Sectors.name(k), UiStyle.TEXT_3), CELL_W))
	row.add_child(_fix(UiStyle.caption("Ideal lap", UiStyle.TEXT_3), IDEAL_W))
	var m := UiStyle.margin([0, 0, 0, UiStyle.S2])
	m.add_child(row)
	return m


func _track_row(i: int, info: Dictionary, recs: Array) -> Control:
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
	_maps.append(map)
	row.add_child(map)
	var name_col := UiStyle.vbox(0)
	name_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_col.add_child(UiStyle.caption(UiFormat.track_number(i), UiStyle.TEXT_3))
	var nm := UiStyle.label(str(info.name), "text_semi", UiStyle.FS_M, UiStyle.TEXT)
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.custom_minimum_size.x = 1
	name_col.add_child(nm)
	row.add_child(_fix(name_col, NAME_W))
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
	return m


## One sector's record: the time over the car and its upgrades ("—" alone when there is none).
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
