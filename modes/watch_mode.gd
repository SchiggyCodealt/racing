extends "res://modes/play_mode.gd"
## watch_mode.gd (playMode.js with driver 'ai')
## ------------------------------------------------------------------
## Watch the AI: the AI drives a full race on the selected track in its network's car
## (opts.ai_car, in that car's colours), with its sensor rays drawn in the 3D view and its
## network drawn live in the HUD's Watch panel. It scores nothing and never uses nitro. If it
## makes no progress for STUCK_TIME seconds (nose against a wall: walls don't bounce cars
## back), it is put back at its last checkpoint, standing, like a player pressing Enter, and
## the HUD says so. The finish panel compares its time with your best with that car.
## setup(app, {track, net, ai_car, return_to}) as play_mode.gd (the driver is always "ai").

var rays: SensorRays = null
var _net_view := {}


func setup(p_app: GameApp, opts: Dictionary) -> void:
	var o := opts.duplicate()
	o.driver = "ai"
	o.ghost = false
	super(p_app, o)
	name = "WatchMode"


func _mode_text(cname: String) -> String:
	return "WATCHING AI · %s · %s" % [track.name, cname]


func _enter_view() -> void:
	ai = AiLink.driver(net)
	rays = SensorRays.new()
	app.world.add_child(rays)
	app.ui.hud.show_watch(true)


func _exit_view() -> void:
	if rays != null and is_instance_valid(rays):
		rays.queue_free()
	app.ui.hud.show_watch(false)


func _drive(_dt: float) -> Car.Controls:
	return ai.call("drive", track, car, race)


## Put the AI back at its last checkpoint when it is stuck (standing, like a respawn).
func _watchdog() -> void:
	if is_stuck(watch, car, race):
		respawn(true)
		ai_note = 2.5


func _render_view(view: CarEffects.Pose) -> void:
	rays.visible = phase != "countdown"
	rays.update(view, ai.get("rays"), AiLink.sensor_range())
	if _net_view.is_empty():
		var sizes: Array = []
		for n: int in net.get("sizes"):
			sizes.append(n)
		_net_view = {"sizes": sizes, "weights": net.get("weights"), "acts": net.get("acts")}
	app.ui.hud.watch_net(_net_view)
