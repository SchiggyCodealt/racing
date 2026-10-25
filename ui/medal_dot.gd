extends Control
## medal_dot.gd
## ------------------------------------------------------------------
## A medal disc inline with text (style.css .medal, 0.78 em of the text beside it): filled
## when won, a ring when not (`off`), dimmed by `alpha` (the HUD's missed medal).

var medal := "":
	set(v):
		medal = v
		queue_redraw()
var diameter := 10.0
var off := false:
	set(v):
		off = v
		queue_redraw()
var alpha := 1.0:
	set(v):
		alpha = v
		queue_redraw()


static func make(m: String, d: float, is_off: bool = false) -> Control:
	var c: Control = load("res://ui/medal_dot.gd").new()
	c.medal = m
	c.diameter = d
	c.off = is_off
	c.custom_minimum_size = Vector2(ceilf(d), ceilf(d))
	return c


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _draw() -> void:
	if medal != "":
		UiStyle.draw_medal(self, size * 0.5, diameter, medal, off, alpha)
