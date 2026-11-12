class_name TimingTower
extends Control
## timing_tower.gd (v6.20.0): the standings of a field race as a timing tower on the left of the HUD,
## in the way the F1 games show them: a head line (the lap), then one row per car in race order with
## the place in a box (white; yours in the accent), the car's colour, the driver's three-letter code
## and the gap to the leader ("Leader" for the first, "+1.23", "+12.3" from ten seconds, "OUT" for a
## car that gave up; a chequered square marks a car that has finished). Your row is lighter. When
## the order changes the rows slide to their new places, and a car that gained or lost a place shows
## a green or red arrow for a moment. Drawn by hand; it never takes input.
##
##   tower.show_board(board, head)   board: FieldRace.board(me) ({rows: [{i, code, color, gap (s against
##                                   you: - ahead, + behind; null for you), me, finished, dnf}]} in race
##                                   order); head: the head line ("LAP 2/3")
##   tower.advance(dt)               the sliding and the arrows (the HUD calls it every frame)
##   tower.lines                     what it shows as text, for tests: "1 BRA Leader", "2 YOU +0.85" ...

const W := preload("res://ui/widgets.gd")
const WIDTH := 208.0
const HEAD_H := 26.0
const ROW_H := 26.0
const ROW_GAP := 2.0
const SLIDE := 12.0        # 1/s: how fast a row closes on its place
const ARROW_TIME := 2.5    # s a gained / lost place shows its arrow
const BG := Color(10 / 255.0, 11 / 255.0, 13 / 255.0, 0.84)
const BG_ME := Color(58 / 255.0, 62 / 255.0, 72 / 255.0, 0.92)
const BOX := Color("#f2f3f5")
const BOX_INK := Color("#0b0c0f")

var head := ""
var rows: Array = []                 # [{i, code, color, gap_text, me, finished, dnf}] in race order
var lines := PackedStringArray()
var _y: Dictionary = {}              # racer i -> the row's y now
var _place: Dictionary = {}          # racer i -> its place at the last board
var _arrow: Dictionary = {}          # racer i -> {dir: 1 gained / -1 lost, t}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _get_minimum_size() -> Vector2:
	return Vector2(WIDTH, HEAD_H + rows.size() * (ROW_H + ROW_GAP))


## A gap to the leader: "+1.24", from ten seconds "+12.3".
static func gap_text(g: float) -> String:
	var a := maxf(0.0, g)
	return "+" + (("%.1f" % a) if a >= 10.0 else ("%.2f" % a))


## The gaps to the leader (s) of a board's rows (their gaps are against you: - ahead, + behind).
static func leader_gaps(board_rows: Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	if board_rows.is_empty():
		return out
	var g0: Variant = (board_rows[0] as Dictionary).get("gap")
	var lead: float = 0.0 if g0 == null else float(g0)
	for r: Dictionary in board_rows:
		var g: Variant = r.get("gap")
		out.append(maxf(0.0, (0.0 if g == null else float(g)) - lead))
	return out


func show_board(board: Dictionary, head_text: String) -> void:
	var src: Array = board.get("rows", [])
	var gaps := leader_gaps(src)
	var n0 := rows.size()
	rows = []
	lines = PackedStringArray()
	var seen: Dictionary = {}
	for k in src.size():
		var d: Dictionary = src[k]
		var i := int(d.get("i", k))
		var txt := "Leader" if k == 0 else gap_text(gaps[k])
		if bool(d.get("dnf", false)):
			txt = "OUT"
		rows.append({"i": i, "code": str(d.get("code", "")), "color": d.get("color", Color.WHITE), "gap_text": txt, "me": bool(d.get("me", false)),
			"finished": bool(d.get("finished", false)), "dnf": bool(d.get("dnf", false))})
		lines.append("%d %s %s" % [k + 1, str(d.get("code", "")), txt])
		seen[i] = true
		if _place.has(i) and int(_place[i]) != k:
			_arrow[i] = {"dir": 1 if k < int(_place[i]) else -1, "t": ARROW_TIME}
		_place[i] = k
		if not _y.has(i):
			_y[i] = _row_y(k)
	for i: Variant in _y.keys():
		if not seen.has(i):
			_y.erase(i)
			_place.erase(i)
			_arrow.erase(i)
	head = head_text
	if rows.size() != n0:
		update_minimum_size()
	queue_redraw()


## Forget the last race (the rows start on their places again).
func clear() -> void:
	rows = []
	lines = PackedStringArray()
	_y.clear()
	_place.clear()
	_arrow.clear()
	update_minimum_size()
	queue_redraw()


func _row_y(k: int) -> float:
	return HEAD_H + ROW_GAP + k * (ROW_H + ROW_GAP)


func advance(dt: float) -> void:
	var moved := false
	for k in rows.size():
		var i: int = rows[k].i
		var want := _row_y(k)
		var y: float = _y.get(i, want)
		if absf(y - want) > 0.25:
			y = lerpf(y, want, minf(1.0, SLIDE * dt))
			moved = true
		else:
			y = want
		_y[i] = y
	for i: Variant in _arrow.keys():
		_arrow[i].t = float(_arrow[i].t) - dt
		if float(_arrow[i].t) <= 0.0:
			_arrow.erase(i)
		moved = true
	if moved:
		queue_redraw()


func _draw() -> void:
	if rows.is_empty():
		return
	var bold := UiStyle.face("display_bold")
	var num := UiStyle.font("display", UiStyle.FS_S, 0.0, true)
	# the head line: an accent bar and the lap
	draw_rect(Rect2(0, 0, WIDTH, HEAD_H), BG)
	draw_rect(Rect2(0, 0, 4, HEAD_H), UiStyle.ACCENT)
	draw_string(UiStyle.font("display_bold", UiStyle.FS_S, 0.1), Vector2(12, W.baseline(bold, UiStyle.FS_S, 0, HEAD_H)), head.to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.FS_S, UiStyle.TEXT)
	# the rows; yours last, so it is on top while rows slide past each other
	var order: Array = range(rows.size())
	order.sort_custom(func(a: int, b: int) -> bool: return not bool(rows[a].me) and bool(rows[b].me))
	for k: int in order:
		var r: Dictionary = rows[k]
		var y: float = roundf(float(_y.get(r.i, _row_y(k))))
		var me := bool(r.me)
		draw_rect(Rect2(0, y, WIDTH, ROW_H), BG_ME if me else BG)
		# the place in its box
		var box := Rect2(3, y + 3, 22, ROW_H - 6)
		draw_rect(box, UiStyle.ACCENT if me else BOX)
		var ps := str(k + 1)
		var pw := bold.get_string_size(ps, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.FS_S).x
		draw_string(bold, Vector2(box.position.x + roundf((box.size.x - pw) * 0.5), W.baseline(bold, UiStyle.FS_S, y, ROW_H)), ps,
			HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.FS_S, UiStyle.ACCENT_INK if me else BOX_INK)
		# the car's colour, the code
		draw_rect(Rect2(31, y + 5, 4, ROW_H - 10), ResultRow.bar_color(r.color))
		var dim := bool(r.dnf)
		draw_string(UiStyle.font("display_bold", UiStyle.FS_M, 0.06), Vector2(42, W.baseline(bold, UiStyle.FS_M, y, ROW_H)), str(r.code),
			HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.FS_M, UiStyle.TEXT_3 if dim else UiStyle.TEXT)
		# a place gained or lost
		if _arrow.has(r.i):
			var a: Dictionary = _arrow[r.i]
			var col: Color = UiStyle.GOOD if int(a.dir) > 0 else UiStyle.BAD
			col.a = clampf(float(a.t) / 0.4, 0.0, 1.0)
			var c := Vector2(90, y + ROW_H * 0.5)
			var s := 4.5 * float(a.dir)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(5, s), c + Vector2(-5, s)]), col)
		# finished: a chequered square
		var right := WIDTH - 8.0
		if bool(r.finished) and not dim:
			var q := 4.0
			var o := Vector2(right - 2 * q, y + (ROW_H - 2 * q) * 0.5)
			draw_rect(Rect2(o, Vector2(2 * q, 2 * q)), BOX)
			draw_rect(Rect2(o, Vector2(q, q)), BOX_INK)
			draw_rect(Rect2(o + Vector2(q, q), Vector2(q, q)), BOX_INK)
			right -= 2 * q + 6
		var gt := str(r.gap_text)
		var gw := num.get_string_size(gt, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.FS_S).x
		draw_string(num, Vector2(right - gw, W.baseline(num, UiStyle.FS_S, y, ROW_H)), gt, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.FS_S,
			UiStyle.TEXT_3 if dim else (UiStyle.TEXT if me or k == 0 else UiStyle.TEXT_2))
