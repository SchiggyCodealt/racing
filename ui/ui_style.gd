class_name UiStyle
extends RefCounted
## ui_style.gd
## ------------------------------------------------------------------
## Track Rush's one design system (the v5 look of web/css/style.css), as GDScript tokens,
## fonts, a Theme and small factories every screen uses:
## - Type: Barlow for text and Barlow Condensed for headings, buttons and numbers
##   (assets/fonts, SIL OFL 1.1), four text sizes (13 / 16 / 20 / 32) plus the big HUD
##   read-outs, tabular figures ("tnum") on every number that changes.
## - Colour: near-black and greys, white and greys for text, one accent (the yellow);
##   green / red only for gains and losses, the medal colours only for medals, the
##   nitro blue only while the nitro burns.
## - Shape: sharp cards, and buttons, tags and HUD plates slanted by SKEW (StyleBoxFlat.skew,
##   so the text stays upright). Spacing on a 4 px grid (S1..S6).
## Sizes are in interface pixels, the web's CSS pixels: UiRoot lays the interface out at the
## window's size (divided by the Interface size setting, Auto = 1 up to 1920x1080).

# ---- colours (style.css :root) ----
const BG_0 := Color("#0a0b0d")            # page, canvases
const BG_1 := Color("#121316")            # panels
const BG_2 := Color("#1a1b1f")            # cards
const BG_3 := Color("#25272c")            # buttons, hover
const BG_4 := Color("#31343a")            # pressed, empty bars
const BTN_ACTIVE := Color("#3c3f46")
const PANEL := Color(18 / 255.0, 19 / 255.0, 22 / 255.0, 0.94)   # a panel over the 3D view
const PLATE := Color(10 / 255.0, 11 / 255.0, 13 / 255.0, 0.74)   # a HUD plate over the 3D view
const CARD := Color(26 / 255.0, 27 / 255.0, 31 / 255.0, 0.94)
const CARD_HI := Color(37 / 255.0, 39 / 255.0, 44 / 255.0, 0.97)
const LINE := Color(1, 1, 1, 0.08)        # rules, used sparingly
const SCRIM_MENU := Color(10 / 255.0, 11 / 255.0, 13 / 255.0, 0.62)
const SCRIM_DIALOG := Color(10 / 255.0, 11 / 255.0, 13 / 255.0, 0.72)
const TEXT := Color("#f2f2ef")
const TEXT_2 := Color("#a7a9ae")
const TEXT_3 := Color("#6f7278")
const ACCENT := Color("#ffc83d")
const ACCENT_HI := Color("#ffd76b")
const ACCENT_INK := Color("#17140a")      # text on the accent
const GOOD := Color("#4cd982")            # faster, points won
const BAD := Color("#ff5d52")             # slower, points lost, walls
const BOOST := Color("#9fdcff")           # the nitro while it burns
const MEDAL_COLORS := {
	"author": Color("#2bd46a"), "gold": Color("#f2c230"), "silver": Color("#c4ccd8"), "bronze": Color("#c97b42"),
}
const MEDAL_ORDER: Array[String] = ["author", "gold", "silver", "bronze"]   # best first
const MEDAL_NAMES := {"author": "Author", "gold": "Gold", "silver": "Silver", "bronze": "Bronze"}
const SHADOW := Color(0, 0, 0, 0.8)       # text-shadow of read-outs drawn straight on the 3D view

# ---- type ----
const FS_S := 13      # labels, captions, small print
const FS_M := 16      # body, buttons, card names
const FS_L := 20      # headings, values
const FS_XL := 32     # titles
const FS_NUM := 44    # HUD race time
const FS_SPEED := 64
const FS_COUNT := 150

# ---- spacing (4 px grid) and shape ----
const S1 := 4
const S2 := 8
const S3 := 12
const S4 := 16
const S5 := 24
const S6 := 32
## tan(12°): the slant of buttons, tags and plates (CSS skewX(-12deg); the top leans right).
const SKEW := 0.2126
const HUD_X := 24     # the HUD's distance from the window's edges

## Font faces: "text" Barlow 400, "text_semi" Barlow 600, "display" Barlow Condensed 600,
## "display_bold" Barlow Condensed 700.
const FONT_FILES := {
	"text": "res://assets/fonts/Barlow-Regular.woff2",
	"text_semi": "res://assets/fonts/Barlow-SemiBold.woff2",
	"display": "res://assets/fonts/BarlowCondensed-SemiBold.woff2",
	"display_bold": "res://assets/fonts/BarlowCondensed-Bold.woff2",
}

static var _faces := {}
static var _variations := {}
static var _theme: Theme = null


## The font face `kind` (see FONT_FILES).
static func face(kind: String) -> Font:
	if not _faces.has(kind):
		var f: FontFile = load(FONT_FILES[kind])
		_faces[kind] = f
	return _faces[kind]


## A font for `kind` with CSS-like letter spacing (`spacing_em` × `size`, rounded to whole
## pixels), tabular figures (`tnum`, numbers that change don't jitter) and, when `line_h` > 0,
## a CSS line box of `line_h` px at `size` (the font's own line is 1.25 em: the difference is
## added above and below, as browsers split the leading). Cached.
static func font(kind: String, size: int = FS_M, spacing_em: float = 0.0, tnum: bool = false, line_h: float = 0.0) -> Font:
	var px := int(roundf(spacing_em * size))
	var lead := 0
	if line_h > 0.0:
		lead = int(roundf(line_h - (face(kind).get_ascent(size) + face(kind).get_descent(size))))
	if px == 0 and not tnum and lead == 0:
		return face(kind)
	var key := "%s|%d|%s|%d|%d" % [kind, px, tnum, lead, size if lead != 0 else 0]
	if not _variations.has(key):
		var v := FontVariation.new()
		v.base_font = face(kind)
		v.spacing_glyph = px
		if lead != 0:
			v.spacing_top = int(floorf(lead / 2.0))
			v.spacing_bottom = lead - int(floorf(lead / 2.0))
		if tnum:
			v.opentype_features = {"tnum": 1}
		_variations[key] = v
	return _variations[key]


# ---------------------------------------------------------------- style boxes

## A flat box of colour `bg` (slanted when `skewed`), with content margins [left, top, right, bottom].
static func box(bg: Color, skewed: bool = false, pad: Array = [0, 0, 0, 0]) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.anti_aliasing = true
	if skewed:
		sb.skew = Vector2(SKEW, 0)
	sb.content_margin_left = pad[0]
	sb.content_margin_top = pad[1]
	sb.content_margin_right = pad[2]
	sb.content_margin_bottom = pad[3]
	return sb


## A slanted HUD plate (the dark shape behind a read-out) with padding [l, t, r, b].
static func plate(pad: Array = [S3, S1, S3, S1], bg: Color = PLATE) -> StyleBoxFlat:
	return box(bg, true, pad)


## The focus / gamepad highlight: a 2 px outline `offset` px outside the box (slanted for slanted shapes).
static func ring(skewed: bool, offset: float = 3.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = TEXT
	sb.set_border_width_all(2)
	sb.set_expand_margin_all(offset + 2.0)
	if skewed:
		sb.skew = Vector2(SKEW, 0)
	return sb


static func empty_box() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


# ---------------------------------------------------------------- the theme

## The game's Theme: default type, Label, Button (and its variations PrimaryButton,
## SmallButton, QuietButton, SmallQuietButton, SegButton, ChipButton / ChipOnButton), CheckBox,
## tooltips, scroll bars.
static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = face("text")
	t.default_font_size = FS_M
	# labels
	t.set_color("font_color", "Label", TEXT)
	t.set_constant("line_spacing", "Label", 0)
	# buttons: a slanted plate, the label upright (style.css .btn)
	var states := {"normal": BG_3, "hover": BG_4, "pressed": BTN_ACTIVE, "disabled": BG_2, "hover_pressed": BTN_ACTIVE}
	_button_type(t, "Button", states, FS_M, "text_semi", 0.0, [S4, 0, S4, 0], TEXT)
	t.set_color("font_disabled_color", "Button", TEXT_3)
	_button_type(t, "PrimaryButton", {"normal": ACCENT, "hover": ACCENT_HI, "pressed": ACCENT, "disabled": BG_2, "hover_pressed": ACCENT},
		FS_L, "display_bold", 0.08, [S6, 0, S6, 0], ACCENT_INK)
	_button_type(t, "SmallButton", states, FS_S, "text_semi", 0.0, [S3, 0, S3, 0], TEXT)
	# a plain button with less room beside its text (two side by side in a narrow column)
	_button_type(t, "TightButton", states, FS_M, "text_semi", 0.0, [S2, 0, S2, 0], TEXT)
	t.set_color("font_disabled_color", "TightButton", TEXT_3)
	var quiet := {"normal": Color(0, 0, 0, 0), "hover": Color(0, 0, 0, 0), "pressed": Color(0, 0, 0, 0), "disabled": Color(0, 0, 0, 0), "hover_pressed": Color(0, 0, 0, 0)}
	_button_type(t, "SmallQuietButton", quiet, FS_S, "text_semi", 0.0, [S3, 0, S3, 0], TEXT_2)
	t.set_color("font_hover_color", "SmallQuietButton", TEXT)
	var seg_on := {"normal": ACCENT, "hover": ACCENT_HI, "pressed": ACCENT, "disabled": BG_2, "hover_pressed": ACCENT}
	_button_type(t, "SegOnButton", seg_on, FS_S, "text_semi", 0.0, [S3, 0, S3, 0], ACCENT_INK)
	# small choice chips in a row (the menu's AI opponents): off and on
	_button_type(t, "ChipButton", states, FS_S, "text_semi", 0.0, [S1, 0, S1, 0], TEXT_2)
	t.set_color("font_hover_color", "ChipButton", TEXT)
	_button_type(t, "ChipOnButton", seg_on, FS_S, "text_semi", 0.0, [S1, 0, S1, 0], ACCENT_INK)
	# tooltips
	t.set_stylebox("panel", "TooltipPanel", box(BG_1, false, [S2, S1 + 2, S2, S1 + 2]))
	t.set_color("font_color", "TooltipLabel", TEXT_2)
	t.set_font_size("font_size", "TooltipLabel", FS_S)
	# scroll bars: thin, grey
	for sb_type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sb_type, box(Color(1, 1, 1, 0.03)))
		t.set_stylebox("grabber", sb_type, box(BG_4))
		t.set_stylebox("grabber_highlight", sb_type, box(BG_4.lightened(0.15)))
		t.set_stylebox("grabber_pressed", sb_type, box(BG_4.lightened(0.25)))
	t.set_stylebox("panel", "PanelContainer", empty_box())
	t.set_stylebox("panel", "ScrollContainer", empty_box())
	_theme = t
	return t


static func _button_type(t: Theme, type: String, bgs: Dictionary, size: int, kind: String, spacing_em: float, pad: Array, ink: Color) -> void:
	if type != "Button":
		t.set_type_variation(type, "Button")
	for state in bgs:
		t.set_stylebox(state, type, box(bgs[state], true, pad))
	t.set_stylebox("focus", type, empty_box()) # (focus is drawn by the screens' gamepad highlight)
	t.set_font("font", type, font(kind, size, spacing_em))
	t.set_font_size("font_size", type, size)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, type, ink)
	t.set_color("font_disabled_color", type, TEXT_3)
	t.set_constant("h_separation", type, S2)


# ---------------------------------------------------------------- factories

## A Label in the design system: `kind` face, `size` px, colour, CSS letter spacing (em),
## upper case, tabular figures, and the read-out shadow for text straight on the 3D view.
## `line_h`: the CSS line box in px (0: the font's own 1.25 em).
static func label(text: String, kind: String = "text", size: int = FS_M, color: Color = TEXT,
		spacing_em: float = 0.0, upper: bool = false, tnum: bool = false, shadow: bool = false, line_h: float = 0.0) -> Label:
	var l := Label.new()
	l.text = text
	style_label(l, kind, size, color, spacing_em, upper, tnum, shadow, line_h)
	return l


static func style_label(l: Label, kind: String, size: int, color: Color, spacing_em: float = 0.0,
		upper: bool = false, tnum: bool = false, shadow: bool = false, line_h: float = 0.0) -> void:
	l.add_theme_font_override("font", font(kind, size, spacing_em, tnum, line_h))
	l.set_meta("line_h", line_h)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.uppercase = upper
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if shadow:
		add_shadow(l)


## The read-out shadow (CSS text-shadow 0 1px 3px rgba(0,0,0,.8)) on a Label.
static func add_shadow(l: Label, color: Color = SHADOW, offset_y: int = 1, size: int = 3) -> void:
	l.add_theme_color_override("font_shadow_color", color)
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", offset_y)
	l.add_theme_constant_override("shadow_outline_size", size)


## The small caps label of a read-out (".lbl": 13 px semi-bold, upper case, spaced, grey).
static func caption(text: String, color: Color = TEXT_2, line_h: float = 0.0) -> Label:
	return label(text, "text_semi", FS_S, color, 0.06, true, false, false, line_h)


## A plain container row / column with `sep` px between children.
static func hbox(sep: int = 0, align: BoxContainer.AlignmentMode = BoxContainer.ALIGNMENT_BEGIN) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	b.alignment = align
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


static func vbox(sep: int = 0, align: BoxContainer.AlignmentMode = BoxContainer.ALIGNMENT_BEGIN) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	b.alignment = align
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


## A PanelContainer drawn with `sb` (a plate, a card, a panel).
static func panel(sb: StyleBox) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## A MarginContainer with margins [left, top, right, bottom].
static func margin(m: Array) -> MarginContainer:
	var c := MarginContainer.new()
	c.add_theme_constant_override("margin_left", m[0])
	c.add_theme_constant_override("margin_top", m[1])
	c.add_theme_constant_override("margin_right", m[2])
	c.add_theme_constant_override("margin_bottom", m[3])
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## A fixed-size gap in a box container.
static func gap(w: float, h: float = 0.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## A slanted button of `variation` ("" plain, "PrimaryButton", "SmallButton", "SmallQuietButton").
## Focus stays with the screens (their keys and the gamepad highlight), never with the button.
static func button(text: String, variation: String = "", min_h: float = 40.0) -> Button:
	var b := Button.new()
	b.text = text
	if variation != "":
		b.theme_type_variation = variation
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = min_h
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


## Line `items` up on one baseline in a row (CSS align-items: baseline): each item is a Label
## styled with a CSS line box (`line_h`, in its meta "line_h"; 0 = 1.25 em) and is pushed up
## from the row's bottom by the difference of the space under the baselines.
static func baseline_row(items: Array, sep: int = S2) -> HBoxContainer:
	var row := hbox(sep)
	var below: Array[float] = []
	var most := 0.0
	for it in items:
		var l := it as Label
		var f: Font = l.get_theme_font("font")
		var sz: int = l.get_theme_font_size("font_size")
		var asc := f.get_ascent(sz)
		var desc := f.get_descent(sz)
		var lh: float = float(l.get_meta("line_h", 0.0))
		if lh <= 0.0:
			lh = asc + desc
		var under := lh - ((lh - (asc + desc)) * 0.5 + asc)
		below.append(under)
		most = maxf(most, under)
	for k in items.size():
		var m := margin([0, 0, 0, int(roundf(most - below[k]))])
		m.size_flags_vertical = Control.SIZE_SHRINK_END
		m.add_child(items[k])
		row.add_child(m)
	return row


## `text` broken into lines (with "\n") no wider than `width` in `font` / `size`, word by word
## (a word wider than a line keeps a line of its own). For labels whose size must be known before
## their container lays them out (an autowrapped Label measures its height at its old width).
static func wrap_text(text: String, f: Font, size: int, width: float) -> String:
	var lines: PackedStringArray = []
	var line := ""
	for word in text.split(" ", false):
		var t := word if line == "" else line + " " + word
		if line != "" and f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
			lines.append(line)
			line = word
		else:
			line = t
	if line != "":
		lines.append(line)
	return "\n".join(lines)


## Width of `text` in `kind` / `size` (for layouts that need it before drawing).
static func text_width(text: String, kind: String, size: int, spacing_em: float = 0.0, tnum: bool = false) -> float:
	return font(kind, size, spacing_em, tnum).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## Draw a slanted parallelogram filling `r` (the shape of a plate) on `ci`.
static func draw_skewed_rect(ci: CanvasItem, r: Rect2, color: Color) -> void:
	var d := r.size.y * SKEW * 0.5
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(r.position.x + d, r.position.y), Vector2(r.end.x + d, r.position.y),
		Vector2(r.end.x - d, r.end.y), Vector2(r.position.x - d, r.end.y)]), color)


## A medal disc (style.css .medal): filled with the medal colour and a faint dark rim, or
## (off: not won yet) only a ring of that colour at 60 %. `alpha` dims it further.
static func draw_medal(ci: CanvasItem, center: Vector2, diameter: float, medal: String, off: bool = false, alpha: float = 1.0) -> void:
	var c: Color = MEDAL_COLORS.get(medal, TEXT_3)
	var r := diameter * 0.5
	if off:
		c.a *= 0.6 * alpha
		ci.draw_arc(center, r - 0.75, 0, TAU, 32, c, 1.5, true)
	else:
		c.a *= alpha
		ci.draw_circle(center, r, c, true, -1.0, true)
		ci.draw_arc(center, r - 0.75, 0, TAU, 32, Color(0, 0, 0, 0.28 * alpha), 1.5, true)


## Five short slanted difficulty bars (style.css .diff): `bar_w` wide, `gap` apart, 5 px tall.
static func draw_difficulty(ci: CanvasItem, pos: Vector2, n: int, bar_w: float = 9.0, gap_px: float = 3.0, h: float = 5.0) -> void:
	for k in 5:
		var r := Rect2(pos.x + k * (bar_w + gap_px), pos.y, bar_w, h)
		draw_skewed_rect(ci, r, TEXT_2 if k < n else BG_4)


## Width of the difficulty bars.
static func difficulty_width(bar_w: float = 9.0, gap_px: float = 3.0) -> float:
	return 5 * bar_w + 4 * gap_px
