extends Control
## diff_bars.gd
## ------------------------------------------------------------------
## A track's difficulty, 1-5, as five short slanted bars (style.css .diff; the fonts have no
## star glyphs).

var level := 1:
	set(v):
		level = v
		queue_redraw()
var bar_w := 9.0
var bar_gap := 3.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	custom_minimum_size = Vector2(UiStyle.difficulty_width(), 5)


func _draw() -> void:
	UiStyle.draw_difficulty(self, Vector2(1, 0), level, bar_w, bar_gap)
