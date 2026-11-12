class_name CupTable
extends VBoxContainer
## cup_table.gd (v6.14.0; v6.20.0 in the F1 games' way): a championship's standings as a table (the cup
## screen between races, the finish panel's trophy moment), leader first: column heads, then one row
## per driver (ui/result_row.gd: the place in a box, yours in the accent; the driver's colour; the
## name), the finishing place in each race run (a dot for one still to come; a win in the accent's
## green) and the points.
##
##   var t := CupTable.new()
##   t.show_rows(rows, races, font_size, medals)   rows: [{pos, name, color, places [int, 0: not run],
##                                         points, me, dnf?}]; races: the race names (column heads:
##                                         their first word); medals: the top three's place boxes in
##                                         gold, silver and bronze (the final table)
##   t.rows                                the ResultRows shown, leader first (for tests)

const MEDALS: Array[String] = ["gold", "silver", "bronze"]

var rows: Array = []
var _fs := UiStyle.FS_S


func _init() -> void:
	add_theme_constant_override("separation", 2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_rows(data: Array, races: Array, fs: int = UiStyle.FS_S, medals: bool = false) -> void:
	_fs = fs
	rows = []
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var race_w := roundf(fs * 3.4)
	var pts_w := roundf(fs * 2.8)
	# heads
	var heads: Array = [ResultRow.cell("Driver", "text", UiStyle.FS_S, UiStyle.TEXT_3)]
	for r: Variant in races:
		var h := ResultRow.cell(String(str(r).split(" ")[0]), "text", UiStyle.FS_S, UiStyle.TEXT_3, race_w, true)
		h.clip_text = true
		h.tooltip_text = str(r)
		h.mouse_filter = Control.MOUSE_FILTER_PASS
		heads.append(h)
	heads.append(ResultRow.cell("Pts", "text", UiStyle.FS_S, UiStyle.TEXT_3, pts_w, true))
	add_child(ResultRow.head(heads, fs))
	for row: Dictionary in data:
		var me := bool(row.get("me", false))
		var c := UiStyle.ACCENT if me else UiStyle.TEXT
		var cells: Array = [ResultRow.cell(str(row.get("name", "")), "text_semi", fs, c)]
		var places: Array = row.get("places", [])
		for k in races.size():
			var p: int = int(places[k]) if k < places.size() else 0
			var txt := "·" if p <= 0 else "P%d" % p
			var col := UiStyle.TEXT_3 if p <= 0 else (UiStyle.GOOD if p == 1 else (c if me else UiStyle.TEXT_2))
			cells.append(ResultRow.cell(txt, "display", fs, col, race_w, true))
		cells.append(ResultRow.cell(str(int(row.get("points", 0))), "display_bold", fs, c, pts_w, true))
		var pos := int(row.get("pos", 0))
		var box: Variant = UiStyle.MEDAL_COLORS[MEDALS[pos - 1]] if medals and pos >= 1 and pos <= 3 else null
		var rr := ResultRow.make(pos, row.get("color", Color.WHITE), me, cells, fs, box)
		add_child(rr)
		rows.append(rr)
