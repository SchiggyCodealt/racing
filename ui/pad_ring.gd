extends Control
## pad_ring.gd
## ------------------------------------------------------------------
## The gamepad highlight (input.js PadMark / style.css .pad-focus): a 2 px white outline 3 px
## outside one control at a time, slanted around slanted buttons. It is an overlay that
## follows its target's rect every frame, so the target needs no highlight code. Add it as
## the last child of a full-rect screen.

var target: Control = null:
	set(v):
		target = v
		visible = v != null
		_follow()
var _skewed := false
var _offset := 3.0
var _sub := Rect2()        # a part of the target to ring instead of all of it (zero size: all)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	top_level = false
	z_index = 10


## Highlight `c` (null: none). `skewed`: follow a slanted shape; `offset`: px outside it;
## `sub`: only that part of `c` (in its own coordinates), e.g. a check box beside its label.
func set_target(c: Control, skewed: bool = false, offset: float = 3.0, sub: Rect2 = Rect2()) -> void:
	_skewed = skewed
	_offset = offset
	_sub = sub
	target = c
	queue_redraw()


func _process(_dt: float) -> void:
	if target != null:
		_follow()


func _follow() -> void:
	if target == null or not is_instance_valid(target) or not target.is_visible_in_tree():
		visible = false
		return
	visible = true
	var parent := get_parent() as Control
	var r := target.get_global_rect()
	if _sub.size != Vector2.ZERO:
		r = Rect2(r.position + _sub.position, _sub.size)
	var origin := parent.get_global_rect().position if parent else Vector2.ZERO
	if position != r.position - origin or size != r.size:
		position = r.position - origin
		size = r.size
		queue_redraw()


func _draw() -> void:
	draw_style_box(UiStyle.ring(_skewed, _offset), Rect2(Vector2.ZERO, size))
