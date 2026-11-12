class_name ResultRow
extends PanelContainer
## result_row.gd (v6.20.0): one row of a results or standings table in the F1 games' way: a dark strip
## (yours lighter) with the place in a box (white; yours in the accent; the top three of a final
## table can take their medal's colour), the car's colour as a bar, then the cells the table gives
## (name, car, time, gap, points ...). The tables (the finish panel's field results, ui/cup_table.gd)
## give every row cells of the same widths, so the columns line up.
##
##   var row := ResultRow.make(place, color, me, cells, font_size)   cells: Controls, left to right
##   ResultRow.head(cells, font_size)                                the column heads over the rows
##   ResultRow.cell(text, kind, size, color, width, right)           a Label cell (width 0: it expands)

const W := preload("res://ui/widgets.gd")
const BG := Color(1, 1, 1, 0.045)
const BG_ME := Color(1, 1, 1, 0.13)
const BOX := Color("#f2f3f5")
const BOX_INK := Color("#0b0c0f")

var place := 0
var me := false


## A car's colour for its bar: a very dark one is lightened, so it shows on the dark strip.
static func bar_color(c: Color) -> Color:
	return c.lightened(0.32) if c.get_luminance() < 0.1 else c


## The width of the place box and the colour bar with their gaps (the heads leave it free).
static func lead_width(fs: int) -> float:
	return roundf(fs * 1.7) + UiStyle.S2 + 4 + UiStyle.S2


static func make(place_: int, color: Color, is_me: bool, cells: Array, fs: int = UiStyle.FS_S, box_color: Variant = null) -> ResultRow:
	var r := ResultRow.new()
	r.place = place_
	r.me = is_me
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pad := 2 if fs <= UiStyle.FS_S else 3
	r.add_theme_stylebox_override("panel", UiStyle.box(BG_ME if is_me else BG, false, [3, pad, UiStyle.S3, pad]))
	var row := UiStyle.hbox(UiStyle.S2)
	var box := Control.new()
	var bw := roundf(fs * 1.7)
	var bh := roundf(fs * 1.45)
	box.custom_minimum_size = Vector2(bw, bh)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill: Color = box_color if box_color is Color else (UiStyle.ACCENT if is_me else BOX)
	box.draw.connect(func() -> void:
		box.draw_rect(Rect2(Vector2.ZERO, box.size), fill)
		var f := UiStyle.face("display_bold")
		var s := str(place_) if place_ > 0 else "–"
		var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		box.draw_string(f, Vector2(roundf((box.size.x - w) * 0.5), W.baseline(f, fs, 0, box.size.y)), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			UiStyle.ACCENT_INK if is_me and not (box_color is Color) else BOX_INK))
	row.add_child(box)
	var bar := ColorRect.new()
	bar.color = bar_color(color)
	bar.custom_minimum_size = Vector2(4, roundf(fs * 1.1))
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar)
	for c: Control in cells:
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(c)
	r.add_child(row)
	return r


## The column heads: the same cells (their texts the heads), set in from the place box and the bar.
static func head(cells: Array, fs: int = UiStyle.FS_S) -> Control:
	var m := UiStyle.margin([3, 0, UiStyle.S3, 1])
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := UiStyle.hbox(UiStyle.S2)
	row.add_child(UiStyle.gap(lead_width(fs) - UiStyle.S2, 0))
	for c: Control in cells:
		row.add_child(c)
	m.add_child(row)
	return m


## A Label cell: `width` px wide (0: it takes the room left), right-aligned numbers when `right`.
static func cell(text: String, kind: String, size: int, color: Color, width: float = 0.0, right: bool = false) -> Label:
	var l := UiStyle.label(text, kind, size, color, 0.0, false, right, false, roundf(size * 1.4))
	if width > 0.0:
		l.custom_minimum_size.x = width
	else:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.custom_minimum_size.x = 1
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if right:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l
