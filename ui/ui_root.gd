class_name UiRoot
extends CanvasLayer
## ui_root.gd
## ------------------------------------------------------------------
## The whole interface on one canvas layer above the 3D view: the race HUD (with the finish
## panel and the Watch-AI panel), the main menu (with its Controls and Settings screens), the
## gamepad notice on top, and the MenuInput that feeds the menu keys and pad presses. The game
## connects the menu's signals and drives the HUD; this node only puts the pieces together.

var input: MenuInput
var hud: RaceHud
var menu: MainMenu
var notice: PadNotice


func _init() -> void:
	layer = 10
	input = MenuInput.new()
	add_child(input)
	hud = RaceHud.new()
	add_child(hud)
	menu = MainMenu.new()
	menu.input = input
	add_child(menu)
	notice = PadNotice.new()
	add_child(notice)
	input.notice = notice.show_text


## The menu (true) or the race HUD (false).
func show_menu(on: bool) -> void:
	menu.show_menu(on)
	hud.show_hud(not on)
