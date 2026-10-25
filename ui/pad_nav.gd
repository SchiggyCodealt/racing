extends RefCounted
## pad_nav.gd
## ------------------------------------------------------------------
## Moving the gamepad highlight between controls on screen (input.js nearestTo / menu.js
## sameRow), on plain rectangles so it can be tested without a window.


## The index in `rects` of the one next to `from` in direction `dir` ("up" / "down" / "left" /
## "right"): the nearest one in the same row (left / right) or column (up / down), else the
## closest one that way at all. -1 if there is none. `skip`: an index to leave out (`from` itself).
static func nearest(from: Rect2, dir: String, rects: Array, skip: int = -1) -> int:
	var horiz := dir == "left" or dir == "right"
	var sgn := -1.0 if dir == "left" or dir == "up" else 1.0
	var a := from.get_center()
	var cands: Array = []
	for k in rects.size():
		if k == skip:
			continue
		var b: Rect2 = rects[k]
		var d := b.get_center() - a
		var main := sgn * (d.x if horiz else d.y)
		if main < 2.0:
			continue
		var gap: float
		var in_line: bool
		if horiz:
			gap = b.position.x - from.end.x if sgn > 0 else from.position.x - b.end.x
			in_line = b.position.y < from.end.y and b.end.y > from.position.y
		else:
			gap = b.position.y - from.end.y if sgn > 0 else from.position.y - b.end.y
			in_line = b.position.x < from.end.x and b.end.x > from.position.x
		cands.append({"k": k, "main": main, "side": absf(d.y if horiz else d.x), "gap": gap, "in_line": in_line})
	var line := cands.filter(func(c: Dictionary) -> bool: return c.in_line)
	if not line.is_empty():
		var g := INF
		for c in line:
			g = minf(g, c.gap)
		var close := line.filter(func(c: Dictionary) -> bool: return c.gap <= g + 8.0)
		close.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return p.side < q.side or (p.side == q.side and p.k < q.k)) # (stable, like JS sort)
		return close[0].k
	if cands.is_empty():
		return -1
	cands.sort_custom(func(p: Dictionary, q: Dictionary) -> bool:
		var sp: float = p.main + 2.0 * p.side
		var sq: float = q.main + 2.0 * q.side
		return sp < sq or (sp == sq and p.k < q.k))
	return cands[0].k


## The control of `list` next to `from` in direction `dir`, or null.
static func nearest_control(from: Control, dir: String, list: Array) -> Control:
	var rects: Array = []
	var skip := -1
	for k in list.size():
		rects.append((list[k] as Control).get_global_rect())
		if list[k] == from:
			skip = k
	var k := nearest(from.get_global_rect(), dir, rects, skip)
	return list[k] if k >= 0 else null


## True when two rects sit on the same row (they overlap vertically).
static func same_row(p: Rect2, q: Rect2) -> bool:
	return q.position.y < p.end.y and q.end.y > p.position.y
