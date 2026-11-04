extends Button
## part_chip.gd (v6.11.0)
## ------------------------------------------------------------------
## One part of the picked car's upgrades on the menu's car picker, as a chip that buys its next
## level: the part's name, a pip for each level (green: bought) and the next level's price (in
## the accent when the money is there, grey when not), MAX when every level is bought. Pressing it
## emits `pressed` (the menu asks the game to buy it, which asks first). A car you don't own
## shows its parts greyed out (disabled): buy the car first. Drawn by hand over the ChipButton plate.

var part_id := ""
var part_name := ""
var level := 0
var max_level := 3
var price := 0
var affordable := false
var locked := false


func _init() -> void:
	theme_type_variation = "ChipButton"
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(1, 26)
	clip_text = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


## What the chip shows: `lv` levels of `max` bought, the next costs `p` (`can`: the money is
## there), `is_locked`: the car isn't owned.
func show_part(id: String, name_: String, lv: int, max_: int, p: int, can: bool, is_locked: bool) -> void:
	part_id = id
	part_name = name_
	level = lv
	max_level = max_
	price = p
	affordable = can
	locked = is_locked
	disabled = is_locked or lv >= max_
	queue_redraw()


func is_max() -> bool:
	return level >= max_level


## The price text: "$1,500", "MAX".
func price_text() -> String:
	return "MAX" if is_max() else UiFormat.money(price)


func _draw() -> void:
	var pad := float(UiStyle.S2)
	var font := UiStyle.font("text_semi", UiStyle.FS_S, 0, true)
	var hover := is_hovered() and not disabled
	var base := _baseline(font)
	# the price (right), the pips (before it), the name (left, cut short when narrow)
	var pt := price_text()
	var pcol := UiStyle.GOOD if is_max() else (UiStyle.TEXT_3 if locked or not affordable else UiStyle.ACCENT)
	var pw := font.get_string_size(pt, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.FS_S).x
	var px := size.x - pad - pw
	draw_string(font, Vector2(px, base), pt, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.FS_S, pcol)
	var pip_w := 7.0
	var pip_gap := 3.0
	var pips_w := max_level * pip_w + (max_level - 1) * pip_gap
	var pips_x := px - UiStyle.S2 - pips_w
	var pip_h := 10.0
	var pip_y := roundf((size.y - pip_h) * 0.5)
	for k in max_level:
		var r := Rect2(pips_x + k * (pip_w + pip_gap), pip_y, pip_w, pip_h)
		var on := k < level
		var col := UiStyle.GOOD if on else UiStyle.BG_4
		if locked:
			col = UiStyle.BG_3.lightened(0.05)
		_skewed(r, col)
	var nf := UiStyle.font("text_semi", UiStyle.FS_S, 0, true)
	var ncol := UiStyle.TEXT_3 if locked else (UiStyle.TEXT if hover else UiStyle.TEXT_2)
	var room := pips_x - UiStyle.S2 - pad
	var nm := part_name
	if nf.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.FS_S).x > room:
		while nm.length() > 1 and nf.get_string_size(nm + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.FS_S).x > room:
			nm = nm.left(nm.length() - 1)
		nm += "…"
	draw_string(nf, Vector2(pad, base), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.FS_S, ncol)


## The text baseline for the chip's height.
func _baseline(font: Font) -> float:
	var asc := font.get_ascent(UiStyle.FS_S)
	var desc := font.get_descent(UiStyle.FS_S)
	return roundf((size.y - (asc + desc)) * 0.5 + asc)


## A parallelogram with the interface's slant (a level pip).
func _skewed(r: Rect2, col: Color) -> void:
	var k := UiStyle.SKEW * r.size.y * 0.5
	draw_colored_polygon(PackedVector2Array([
		Vector2(r.position.x + k, r.position.y), Vector2(r.end.x + k, r.position.y),
		Vector2(r.end.x - k, r.end.y), Vector2(r.position.x - k, r.end.y)]), col)

