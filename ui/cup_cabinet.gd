class_name CupCabinet
extends Button
## cup_cabinet.gd (v6.14.0): the menu's Cups button, which is also its trophy cabinet: "Cups", then one
## trophy per cup (sim/cups.gd order) in the colour of your best place at the highest level you took a
## trophy at (faint: none yet), with five pips under it for Rookie .. Elite (each in its trophy's colour,
## or dark), and the key cap T. Pressed (or T on the menu) it opens the cup screen (ui/cup_screen.gd). The
## tooltip spells the cabinet out; refresh() redraws it from UiData.cup_trophies().

const W := preload("res://ui/widgets.gd")
const KeyCap := preload("res://ui/key_cap.gd")
const CELL := 18.0
const H := 28.0

var _cab: Control
var _label: Label
## The cabinet as data: [{id, trophy ("gold" | ... | ""), levels: [5 trophy kinds]}] (tests).
var cells: Array = []


func _init() -> void:
	theme_type_variation = "SmallButton"
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size.y = H
	var row := UiStyle.hbox(UiStyle.S2, BoxContainer.ALIGNMENT_CENTER)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = UiStyle.label("Cups", "text_semi", UiStyle.FS_S, UiStyle.TEXT)
	_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_label)
	_cab = Control.new()
	_cab.custom_minimum_size = Vector2(Cups.ids().size() * CELL, H - 6.0)
	_cab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_cab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cab.draw.connect(_draw_cab)
	row.add_child(_cab)
	row.add_child(KeyCap.in_btn("T"))
	add_child(row)
	custom_minimum_size.x = row.get_combined_minimum_size().x + 2 * UiStyle.S3
	refresh()


## Read the cabinet again (after a cup, the terminal) and redraw it.
func refresh() -> void:
	var tro := UiData.cup_trophies()
	cells = []
	var lines: PackedStringArray = []
	var won := 0
	for id: String in Cups.ids():
		var t: Dictionary = tro.get(id, {})
		var levels: Array = []
		var best := ""
		var parts: PackedStringArray = []
		for lv: String in Opponents.ids():
			var kind := Cups.trophy(int(t.get(lv, 0)))
			levels.append(kind)
			if kind != "":
				best = kind # (the highest level with a trophy)
				parts.append("%s %s" % [Opponents.level_name(lv), kind])
				won += 1
		cells.append({"id": id, "trophy": best, "levels": levels})
		lines.append("%s: %s" % [Cups.name_of(id), ", ".join(parts) if not parts.is_empty() else "-"])
	tooltip_text = "Championships (T): three or four races against the same five AI drivers, points, trophies and a big payout.\nTrophy cabinet (%d of %d):\n%s" % [
		won, Cups.ids().size() * Opponents.ids().size(), "\n".join(lines)]
	_cab.queue_redraw()


func _draw_cab() -> void:
	var h := _cab.size.y
	for k in cells.size():
		var c: Dictionary = cells[k]
		var cx := CELL * (k + 0.5)
		W.trophy(_cab, cx, 0.0, h - 6.0, CupScreen.trophy_color(String(c.trophy)) if String(c.trophy) != "" else Color(1, 1, 1, 0.16))
		var lv: Array = c.levels
		var pw := 2.0
		var gap := 1.0
		var x0 := cx - (lv.size() * pw + (lv.size() - 1) * gap) * 0.5
		for j in lv.size():
			var kind := String(lv[j])
			_cab.draw_rect(Rect2(x0 + j * (pw + gap), h - 3.0, pw, 3.0), CupScreen.trophy_color(kind) if kind != "" else Color(1, 1, 1, 0.14))
