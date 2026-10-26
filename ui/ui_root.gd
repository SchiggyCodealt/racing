class_name UiRoot
extends CanvasLayer
## ui_root.gd
## ------------------------------------------------------------------
## The whole interface on one canvas layer above the 3D view: the race HUD (with the finish
## panel and the Watch-AI panel), the main menu (with its Controls and Settings screens), the
## gamepad notice on top, and the MenuInput that feeds the menu keys and pad presses. The game
## connects the menu's signals and drives the HUD; this node only puts the pieces together.
##
## Size: the interface is laid out in its own pixels, like the web game's CSS pixels, not in the
## project's stretched 1280x720 canvas: at 1920x1080 it has the room of a 1920x1080 page (the
## approved v5 menu at that size), and windows smaller than 1280x720 get the web's compact and
## narrow layouts instead of a shrunken 1280x720 one. The layer's transform undoes the project
## stretch and applies the interface scale: setting "ui_scale" (Settings: Interface size),
## "auto" = 1 up to 1920x1080 and growing with bigger windows (2 at 3840x2160), so text stays
## readable on large screens, the way a browser's device pixel ratio does.

var input: MenuInput
var hud: RaceHud
var menu: MainMenu
var notice: PadNotice
## Holds every screen; its size is the window in interface pixels.
var frame: Control
## The interface scale in use (interface pixels to window pixels).
var ui_scale := 1.0


func _init() -> void:
	layer = 10
	frame = Control.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.size = Vector2(1280, 720)
	add_child(frame)
	input = MenuInput.new()
	add_child(input)
	hud = RaceHud.new()
	frame.add_child(hud)
	menu = MainMenu.new()
	menu.input = input
	frame.add_child(menu)
	notice = PadNotice.new()
	frame.add_child(notice)
	input.notice = notice.show_text
	menu.settings.setting_changed.connect(func(key: String, _v: Variant) -> void:
		if key == "ui_scale":
			fit())


func _ready() -> void:
	get_viewport().size_changed.connect(fit)
	fit()


## The menu (true) or the race HUD (false).
func show_menu(on: bool) -> void:
	menu.show_menu(on)
	hud.show_hud(not on)


## The interface scale for a window of `window` pixels: `setting` is "auto" or a factor.
static func scale_for(window: Vector2, setting: Variant) -> float:
	if setting is float or setting is int:
		return clampf(float(setting), 0.5, 4.0)
	return maxf(1.0, minf(window.x / 1920.0, window.y / 1080.0))


## Lay the interface out for the window's size (on every resize and Interface size change).
func fit() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var logical := vp.get_visible_rect().size
	var win := Vector2(get_window().size) if get_window() != null else logical
	if win.x <= 0 or logical.x <= 0:
		return
	var stretch := win.x / logical.x # (the project's canvas_items stretch factor)
	ui_scale = scale_for(win, UiData.get_setting("ui_scale"))
	scale = Vector2.ONE * (ui_scale / stretch)
	frame.size = (win / ui_scale).floor() # (the screens fill it: full-rect anchors)
