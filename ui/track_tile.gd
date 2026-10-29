extends Control
## track_tile.gd
## ------------------------------------------------------------------
## One track tile of the menu's grid (style.css .track-card): the number top left, the
## medal your best time with the picked car has earned top right, the minimap, the name,
## the difficulty bars and your best time. The selected tile is lighter, underlined with
## the accent, its map and number in the accent. Drawn by hand (no child nodes), so 15 of
## them cost next to nothing. Click picks the track, a double click drives.

signal picked
signal activated

const W := preload("res://ui/widgets.gd")
const TrackMapView := preload("res://ui/track_map_view.gd")

var index := 0
var title := ""
var difficulty := 1
var best_text := ""          # "" when there is no best time
var medal := ""              # "" when none is earned
var map: Dictionary = {}
var selected := false:
	set(v):
		if v != selected:
			selected = v
			queue_redraw()
var map_h := 56.0            # the map's height (bigger in big windows)
var pad_x := float(UiStyle.S3)
var pad_y := float(UiStyle.S3)
var name_size := UiStyle.FS_M
var _hover := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_NONE
	mouse_entered.connect(func() -> void: _hover = true; queue_redraw())
	mouse_exited.connect(func() -> void: _hover = false; queue_redraw())


func setup(i: int, info: Dictionary, track_map: Dictionary) -> void:
	index = i
	title = info.name
	difficulty = info.difficulty
	map = track_map
	# (the number keys reach the first 12 tracks; further ones are picked with the arrows, mouse or pad)
	tooltip_text = "%s (key %s)" % [title, ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="][i]] if i < 12 else title
	queue_redraw()


## Your best time ("" none) and the medal it earned ("" none) with the picked car.
func set_record(best: String, medal_: String) -> void:
	best_text = best
	medal = medal_
	queue_redraw()


func set_metrics(map_height: float, px: float, py: float, name_px: int) -> void:
	map_h = map_height
	pad_x = px
	pad_y = py
	name_size = name_px
	update_minimum_size()
	queue_redraw()


func _get_minimum_size() -> Vector2:
	# padding, map with its margins, the name's line (1.25), the foot (min 18 px, s1 above)
	var foot_gap := UiStyle.S2 if name_size > UiStyle.FS_M else UiStyle.S1
	return Vector2(0, pad_y + UiStyle.S2 + map_h + UiStyle.S2 + roundf(name_size * 1.25) + foot_gap + 18 + pad_y)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		picked.emit()
		if e.double_click:
			activated.emit()
		accept_event()


func _draw() -> void:
	var w := size.x
	var bg := UiStyle.CARD_HI if selected or _hover else UiStyle.CARD
	draw_rect(Rect2(Vector2.ZERO, size), bg)
	if selected:
		draw_rect(Rect2(0, size.y - 3, w, 3), UiStyle.ACCENT)
	var num_top := UiStyle.S3 if name_size > UiStyle.FS_M else UiStyle.S2
	# number and medal disc (absolutely placed in the corners)
	W.text(self, UiStyle.font("display", UiStyle.FS_S, 0, true), UiStyle.FS_S, pad_x, num_top, UiStyle.FS_S,
		UiFormat.track_number(index), UiStyle.ACCENT if selected else UiStyle.TEXT_3)
	if medal != "":
		var d := 14.0 * 0.78
		UiStyle.draw_medal(self, Vector2(w - pad_x - d * 0.5, num_top + d * 0.5), d, medal)
	# map
	var map_top := pad_y + UiStyle.S2
	_draw_map(Rect2(pad_x, map_top, w - 2 * pad_x, map_h))
	# name (cut with an ellipsis)
	var name_top := map_top + map_h + UiStyle.S2
	var name_lh := roundf(name_size * 1.25)
	W.text(self, UiStyle.face("display"), name_size, pad_x, name_top, name_lh, title, UiStyle.TEXT, false, w - 2 * pad_x)
	# foot: difficulty bars (narrow ones, so a ten-minute best still fits) and the best time
	var foot_top := name_top + name_lh + (UiStyle.S2 if name_size > UiStyle.FS_M else UiStyle.S1)
	UiStyle.draw_difficulty(self, Vector2(pad_x + 1, foot_top + 6.5), difficulty, 6.0, 2.0)
	if best_text != "":
		W.text(self, UiStyle.font("display", UiStyle.FS_S, 0, true), UiStyle.FS_S, w - pad_x, foot_top + 2.5, UiStyle.FS_S,
			best_text, UiStyle.TEXT if selected else UiStyle.TEXT_2, true)


func _draw_map(r: Rect2) -> void:
	if map.is_empty():
		return
	# (the same drawing as TrackMapView, inline: no child node per tile)
	var vb: Vector2 = map.size
	var k := minf(r.size.x / vb.x, r.size.y / vb.y)
	var off := r.position + (r.size - vb * k) * 0.5
	var src: PackedVector2Array = map.points
	var pts := PackedVector2Array()
	for p in src:
		pts.append(off + p * k)
	if map.closed:
		pts.append(pts[0])
	draw_polyline(pts, UiStyle.ACCENT if selected else UiStyle.TEXT_2, 2.0, true)
	draw_circle(off + map.start * k, 3.0, UiStyle.TEXT, true, -1.0, true)
	if map.finish != null:
		draw_circle(off + map.finish * k, 3.0, UiStyle.TEXT, true, -1.0, true)
