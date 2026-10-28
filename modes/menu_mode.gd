extends Node
## menu_mode.gd (main.js menuMode)
## ------------------------------------------------------------------
## The menu: the interface's MainMenu (ui/main_menu.gd: track tiles, the track panel, the car
## picker, Drive, the AI block, Controls and Settings) over the 3D world, where the camera
## slowly orbits the highlighted track. The menu reads its own keys and pad presses (it polls
## the app's GameInput while it shows) and talks to the app through its signals (game/app.gd);
## picking another track builds it on a worker thread, so the orbit never hitches.

var app: GameApp


func setup(p_app: GameApp) -> void:
	app = p_app
	name = "MenuMode"


func enter() -> void:
	# the background shows the highlighted track (a race or training may have left another one)
	app.show_track_async(app.tracks[app.selected_track])
	app.menu_camera.make_current()


func exit() -> void:
	pass


func update(dt: float) -> void:
	app.orbit(dt)
