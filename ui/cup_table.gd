class_name CupTable
extends GridContainer
## cup_table.gd (v6.14.0): a championship's standings as a table (the cup screen between races, the
## finish panel's trophy moment): the place, the driver's colour and name (yours in the accent), the
## finishing place in each race run (a dot for one still to come)
## and the points, leader first.
##
##   var t := CupTable.new()
##   t.show_rows(rows, races, font_size)   rows: [{pos, name, color, places [int, 0: not run], points,
##                                         me, dnf?}]; races: the race names (column heads: their
##                                         first word)

var _fs := UiStyle.FS_S


func _init() -> void:
	columns = 4
	add_theme_constant_override("h_separation", UiStyle.S3)
	add_theme_constant_override("v_separation", 1)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_rows(rows: Array, races: Array, fs: int = UiStyle.FS_S) -> void:
	_fs = fs
	for c in get_children():
		remove_child(c)
		c.queue_free()
	columns = 4 + races.size()
	var lh := roundf(fs * 1.45)
	# heads
	add_child(_cell("", "text", UiStyle.TEXT_3, lh))
	add_child(_cell("", "text", UiStyle.TEXT_3, lh))
	add_child(_cell("Driver", "text", UiStyle.TEXT_3, lh))
	for r: Variant in races:
		var head := _cell(String(str(r).split(" ")[0]), "text", UiStyle.TEXT_3, lh, true)
		head.tooltip_text = str(r)
		head.mouse_filter = Control.MOUSE_FILTER_PASS
		add_child(head)
	add_child(_cell("Pts", "text", UiStyle.TEXT_3, lh, true))
	for row: Dictionary in rows:
		var me := bool(row.get("me", false))
		var c := UiStyle.ACCENT if me else UiStyle.TEXT
		add_child(_cell(str(int(row.get("pos", 0))), "display_bold", UiStyle.TEXT_2, lh, true))
		var chip := ColorRect.new()
		chip.color = row.get("color", Color.WHITE)
		chip.custom_minimum_size = Vector2(5, roundf(fs * 1.0))
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(chip)
		add_child(_cell(str(row.get("name", "")), "text_semi" if me else "text", c, lh))
		var places: Array = row.get("places", [])
		for k in races.size():
			var p: int = int(places[k]) if k < places.size() else 0
			var txt := "·" if p <= 0 else str(p)
			var col := UiStyle.TEXT_3 if p <= 0 else (c if me else UiStyle.TEXT_2)
			add_child(_cell(txt, "display", col, lh, true))
		var pts := _cell(str(int(row.get("points", 0))), "display_bold", c, lh, true)
		pts.custom_minimum_size.x = 30
		add_child(pts)


func _cell(text: String, kind: String, color: Color, lh: float, right: bool = false) -> Label:
	var l := UiStyle.label(text, kind, _fs, color, 0.0, false, true, false, lh)
	if right:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l
