extends Control
## dialog_screen.gd
## ------------------------------------------------------------------
## Base of the full-window dialogs (Controls, Settings): a dark scrim over the menu and a
## centred panel (style.css #controls / .controls-panel): at most `max_width` wide, S5 from the
## window edges, padding S5 S6 S6 (S4 under 760 px), scrolling when taller than the window.
## A click beside the panel closes it. Subclasses fill `body` (under the title row with the
## Close button) and may override _on_layout(width) for their own responsive rules.

signal closed

const KeyCap := preload("res://ui/key_cap.gd")

var panel: PanelContainer
## The panel's content column (title row first).
var body: VBoxContainer
var close_button: Button
var max_width := 960.0
var _scroll: ScrollContainer
var _center: CenterContainer
var _margin: MarginContainer
var _panel_box: StyleBoxFlat


func _init(title: String = "") -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiStyle.theme()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var scrim := ColorRect.new()
	scrim.color = UiStyle.SCRIM_DIALOG
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_scroll)
	_center = CenterContainer.new()
	_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_center.mouse_filter = Control.MOUSE_FILTER_STOP
	_center.gui_input.connect(_on_backdrop_input)
	_scroll.add_child(_center)
	_margin = UiStyle.margin([UiStyle.S5, UiStyle.S5, UiStyle.S5, UiStyle.S5])
	_margin.mouse_filter = Control.MOUSE_FILTER_PASS
	_center.add_child(_margin)
	_panel_box = UiStyle.box(UiStyle.BG_1, false, [UiStyle.S6, UiStyle.S5, UiStyle.S6, UiStyle.S6])
	panel = UiStyle.panel(_panel_box)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_margin.add_child(panel)
	body = UiStyle.vbox(0)
	panel.add_child(body)
	# header: title, Close [Esc]
	var head := UiStyle.hbox(UiStyle.S4)
	var t := UiStyle.label(title, "display_bold", UiStyle.FS_XL, UiStyle.TEXT, 0.04, true, false, false, UiStyle.FS_XL)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(t)
	close_button = button_with_cap("Close", "Esc")
	close_button.pressed.connect(close)
	head.add_child(close_button)
	body.add_child(head)
	resized.connect(_layout)


## A small button with its key cap (style.css .btn.small with a kbd): `Close [Esc]`.
static func button_with_cap(text: String, key: String, variation: String = "SmallButton") -> Button:
	var b := UiStyle.button("", variation, 30)
	var row := UiStyle.hbox(UiStyle.S2, BoxContainer.ALIGNMENT_CENTER)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiStyle.label(text, "text_semi", UiStyle.FS_S, UiStyle.TEXT)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	row.add_child(KeyCap.in_btn(key))
	b.add_child(row)
	b.custom_minimum_size.x = row.get_combined_minimum_size().x + 2 * UiStyle.S3
	b.set_meta("label", l)
	return b


func open() -> void:
	visible = true
	_layout()


func close() -> void:
	if visible:
		visible = false
		closed.emit()


var is_open: bool:
	get:
		return visible


func _on_backdrop_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		close()


## The panel's width for a window `w` wide, and its inner (content) width.
func panel_width(w: float) -> float:
	return minf(max_width, w - 2 * UiStyle.S5)


func inner_width(w: float) -> float:
	return panel_width(w) - _panel_box.content_margin_left - _panel_box.content_margin_right


func _layout() -> void:
	var w := size.x
	var narrow := w < 760
	_panel_box.content_margin_left = UiStyle.S4 if narrow else UiStyle.S6
	_panel_box.content_margin_right = _panel_box.content_margin_left
	_panel_box.content_margin_top = UiStyle.S4 if narrow else UiStyle.S5
	_panel_box.content_margin_bottom = UiStyle.S4 if narrow else UiStyle.S6
	panel.custom_minimum_size.x = panel_width(w)
	_on_layout(w)


## Subclasses: responsive rules for a window `w` wide (called on every resize and open).
func _on_layout(_w: float) -> void:
	pass
