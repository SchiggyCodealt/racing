class_name RaceMinimap
extends PanelContainer
## race_minimap.gd (v6.26.0): the HUD's minimap, at the bottom right above the nitro gauge: the track
## from above in its three sectors (sim/sectors.gd), the cars as dots, and under it the sector times of
## the lap being driven, in the way of the F1 games.
## ------------------------------------------------------------------
## The map is the track's centre line turned a quarter when it is taller than wide (as the menu's
## track tiles: a rotation, never a mirror), fitted into MAP_SIZE. Each sector is drawn in the colour of
## its state this lap: the one being driven yellow (the accent), one done green when it beat the track's
## sector record and white when not, one still to come grey. A short bar marks the start line (and a
## sprint's finish). The cars: yours a yellow dot with a dark rim on top, the others in their colours.
## The cells under the map: S1 S2 S3 with the lap's times (green: a new record; the record's time in grey
## while the sector is still to come; a dash when there is none).
##
##   set_track(track)          the map (once per race)
##   show_state(s)             every frame: {sector (0..2, 3 done), cells: [{time (s or null), state:
##                             "best" | "done" | "now" | "next"}, ...] × 3, records: [s or null] × 3,
##                             cars: [{x, z, color, me}]}
##   lines -> PackedStringArray  what the cells read ("S1 0:24.512 best", ...: tests)

const MAP_SIZE := Vector2(224, 118)
const LINE_W := 3.0
const NEXT_COLOR := Color(1, 1, 1, 0.22)
const DIM_COLOR := Color(1, 1, 1, 0.1)   # a sprint's road before the start and past the finish

var lines := PackedStringArray()

var _map: Control
var _cells: Array = []   # [{name: Label, time: Label}]
var _sectors: Array = [] # [PackedVector2Array] × 3 in map units
var _dim: Array = []     # [PackedVector2Array]
var _ticks: Array = []   # [[Vector2 a, Vector2 b]] start (and finish) bars
var _box := Vector2.ONE
var _turn := false
var _x0 := 0.0
var _x1 := 0.0
var _z0 := 0.0
var _z1 := 0.0
var _pad := 0.0
var _state: Dictionary = {}


func _init() -> void:
	add_theme_stylebox_override("panel", UiStyle.plate([UiStyle.S2, UiStyle.S2, UiStyle.S2, UiStyle.S1]))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := UiStyle.vbox(UiStyle.S1)
	_map = Control.new()
	_map.custom_minimum_size = MAP_SIZE
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.draw.connect(_draw_map)
	col.add_child(_map)
	var row := UiStyle.hbox(UiStyle.S2)
	for k in Sectors.COUNT:
		var cell := UiStyle.hbox(UiStyle.S1)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var n := UiStyle.caption(Sectors.name(k), UiStyle.TEXT_3, UiStyle.FS_S)
		var t := UiStyle.label("—", "display", UiStyle.FS_S, UiStyle.TEXT_2, 0.0, false, true, false, 18)
		n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cell.add_child(n)
		cell.add_child(t)
		row.add_child(cell)
		_cells.append({"name": n, "time": t})
	col.add_child(row)
	add_child(col)


## The map of `t`: the centre line split by sector, in map units (metres, turned when taller than wide).
func set_track(t: BuiltTrack) -> void:
	var n: int = t.N if t.closed else t.count
	_x0 = INF
	_x1 = -INF
	_z0 = INF
	_z1 = -INF
	for i in n:
		_x0 = minf(_x0, t.px[i])
		_x1 = maxf(_x1, t.px[i])
		_z0 = minf(_z0, t.pz[i])
		_z1 = maxf(_z1, t.pz[i])
	_turn = _z1 - _z0 > _x1 - _x0
	var w := (_z1 - _z0) if _turn else (_x1 - _x0)
	var h := (_x1 - _x0) if _turn else (_z1 - _z0)
	_pad = maxf(w, h) * 0.05
	_box = Vector2(w + 2.0 * _pad, h + 2.0 * _pad)
	var m: PackedInt32Array = Sectors.marks(t)
	var step := maxi(1, roundi(n / 240.0))
	var spans: Array = []
	if t.closed:
		spans = [[0, m[0]], [m[0], m[1]], [m[1], t.N]]
	else:
		spans = [[t.start_idx, m[0]], [m[0], m[1]], [m[1], t.finish_idx]]
	_sectors = []
	for sp: Array in spans:
		_sectors.append(_run(t, int(sp[0]), int(sp[1]), step))
	_dim = []
	if not t.closed:
		if t.start_idx > 0:
			_dim.append(_run(t, 0, t.start_idx, step))
		if t.finish_idx < t.count - 1:
			_dim.append(_run(t, t.finish_idx, t.count - 1, step))
	_ticks = [_tick(t, 0 if t.closed else t.start_idx)]
	if not t.closed:
		_ticks.append(_tick(t, t.finish_idx))
	_map.queue_redraw()


## Samples a..b (b may be N on a circuit: sample 0 again) as map points, every `step`-th and both ends.
func _run(t: BuiltTrack, a: int, b: int, step: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var i := a
	while i < b:
		out.append(_uv(t.px[_wrap(t, i)], t.pz[_wrap(t, i)]))
		i += step
	out.append(_uv(t.px[_wrap(t, b)], t.pz[_wrap(t, b)]))
	return out


static func _wrap(t: BuiltTrack, i: int) -> int:
	return posmod(i, t.N) if t.closed else clampi(i, 0, t.count - 1)


## A bar across the road at sample i (map units).
func _tick(t: BuiltTrack, i: int) -> Array:
	var j := _wrap(t, i)
	var hw := maxf(6.0, _box.x * 0.025)
	var a := _uv(t.px[j] + t.nx[j] * hw, t.pz[j] + t.nz[j] * hw)
	var b := _uv(t.px[j] - t.nx[j] * hw, t.pz[j] - t.nz[j] * hw)
	return [a, b]


## World x / z to map units (the menu tile's quarter turn when the track is taller than wide).
func _uv(x: float, z: float) -> Vector2:
	return (Vector2(_z1 - z, x - _x0) if _turn else Vector2(x - _x0, z - _z0)) + Vector2(_pad, _pad)


func show_state(s: Dictionary) -> void:
	_state = s
	var cells: Array = s.get("cells", [])
	var recs: Array = s.get("records", [])
	var out := PackedStringArray()
	for k in Sectors.COUNT:
		var c: Dictionary = cells[k] if k < cells.size() and cells[k] is Dictionary else {}
		var st := str(c.get("state", "next"))
		var tv: Variant = c.get("time")
		var rec: Variant = recs[k] if k < recs.size() else null
		var lbl: Label = _cells[k].time
		var txt := "—"
		var col := UiStyle.TEXT_3
		if tv != null and (st == "best" or st == "done"):
			txt = _short(float(tv))
			col = UiStyle.GOOD if st == "best" else UiStyle.TEXT
		elif rec != null:
			txt = _short(float(rec))
			col = UiStyle.TEXT_3 if st == "next" else UiStyle.TEXT_2
		if lbl.text != txt:
			lbl.text = txt
		lbl.add_theme_color_override("font_color", col)
		(_cells[k].name as Label).add_theme_color_override("font_color", UiStyle.ACCENT if st == "now" else UiStyle.TEXT_3)
		out.append("%s %s %s" % [Sectors.name(k), txt, st])
	lines = out
	_map.queue_redraw()


## A sector time as the cells show it: "24.512" under a minute, else "1:04.512".
static func _short(t: float) -> String:
	var s := RaceState.format_time(t)
	return s.substr(2) if s.begins_with("0:") else s


func _draw_map() -> void:
	if _sectors.is_empty():
		return
	var area := _map.size
	var k := minf(area.x / _box.x, area.y / _box.y)
	var off := (area - _box * k) * 0.5
	var cells: Array = _state.get("cells", [])
	for d: PackedVector2Array in _dim:
		_map.draw_polyline(_scaled(d, k, off), DIM_COLOR, LINE_W, true)
	for i in Sectors.COUNT:
		var st := str((cells[i] as Dictionary).get("state", "next")) if i < cells.size() and cells[i] is Dictionary else "next"
		var col := NEXT_COLOR
		match st:
			"now":
				col = UiStyle.ACCENT
			"best":
				col = UiStyle.GOOD
			"done":
				col = UiStyle.TEXT
		_map.draw_polyline(_scaled(_sectors[i], k, off), col, LINE_W, true)
	for tk: Array in _ticks:
		_map.draw_line(off + (tk[0] as Vector2) * k, off + (tk[1] as Vector2) * k, UiStyle.TEXT, 2.0, true)
	var cars: Array = _state.get("cars", [])
	var me: Dictionary = {}
	for c: Variant in cars:
		if not (c is Dictionary):
			continue
		if bool(c.get("me", false)):
			me = c
			continue
		var p := off + _uv(float(c.x), float(c.z)) * k
		_map.draw_circle(p, 4.0, Color(0, 0, 0, 0.7), true, -1.0, true)
		_map.draw_circle(p, 3.0, c.get("color", UiStyle.TEXT_2), true, -1.0, true)
	if not me.is_empty():
		var p := off + _uv(float(me.x), float(me.z)) * k
		_map.draw_circle(p, 6.0, Color(0, 0, 0, 0.8), true, -1.0, true)
		_map.draw_circle(p, 4.5, UiStyle.ACCENT, true, -1.0, true)


static func _scaled(src: PackedVector2Array, k: float, off: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(src.size())
	for i in src.size():
		out[i] = off + src[i] * k
	return out
