extends SceneTree
## car_cost.gd: what one car model costs to draw: draw calls and primitives (triangles) of a
## frame with the car minus the same frame without it, for every car at each quality level.
##
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --resolution 1280x720 \
##       --script res://tests/visual/car_cost.gd -- [cars=racer,kestrel] [qualities=high,low] \
##       [theme=meadow] [ghost=1] [fleet=80] [out=/tmp/car_cost.json]
##
## The car stands on a flat pad 9 m in front of the camera (the chase camera's distance), so
## its shadow pass is counted too. ghost=1 also measures a see-through ghost of each car;
## fleet=N measures an AIFleet of N cars spread over the pad. Prints one line per car and level
## (calls: all passes, visible + shadow; primitives: the same). Needs a rendering device
## (xvfb-run works, on llvmpipe too).

const Themes = preload("res://world/themes.gd")

var _world: World
var _cam: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var o := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		o[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var ids: PackedStringArray = Cars.ids()
	if o.has("cars"):
		ids = String(o["cars"]).split(",")
	var levels: PackedStringArray = String(o.get("qualities", "high,low")).split(",")
	var rows: Array = []
	_world = World.new()
	get_root().add_child(_world)
	_world.set_theme(String(o.get("theme", "meadow")))
	var pad := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	pad.mesh = pm
	_world.add_child(pad)
	_cam = Camera3D.new()
	_cam.fov = 60
	_world.add_child(_cam)
	_cam.look_at_from_position(Vector3(0, 3.2, -9.0), Vector3(0, 0.8, 0))
	_cam.make_current()
	print("car        quality  kind    calls (vis + shadow)   primitives (vis + shadow)")
	for q in levels:
		_world.set_quality(q)
		var base := await _stats(null)
		for id in ids:
			var kinds := ["car"]
			if o.get("ghost", "0") == "1":
				kinds.append("ghost")
			for kind: String in kinds:
				var car := CarModel.new(id, {"ghost": kind == "ghost"})
				var s := await _stats(car)
				var row := {"car": id, "quality": q, "kind": kind}
				for k in ["calls", "visible_calls", "shadow_calls", "primitives", "visible_primitives", "shadow_primitives"]:
					row[k] = int(s[k]) - int(base[k])
				rows.append(row)
				print("%-10s %-7s  %-6s %4d (%3d + %3d)    %7d (%6d + %6d)" % [id, q, kind, row.calls, row.visible_calls, row.shadow_calls,
					row.primitives, row.visible_primitives, row.shadow_primitives])
		if o.has("fleet"):
			var n := int(o["fleet"])
			var fleet := AIFleet.new(n)
			var s := await _stats(fleet, n)
			var row := {"car": "fleet%d" % n, "quality": q, "kind": "fleet"}
			for k in ["calls", "visible_calls", "shadow_calls", "primitives", "visible_primitives", "shadow_primitives"]:
				row[k] = int(s[k]) - int(base[k])
			rows.append(row)
			print("%-10s %-7s  %-6s %4d (%3d + %3d)    %7d (%6d + %6d)" % [row.car, q, "fleet", row.calls, row.visible_calls, row.shadow_calls,
				row.primitives, row.visible_primitives, row.shadow_primitives])
	if o.has("out"):
		var f := FileAccess.open(String(o["out"]), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(rows, "  "))
	quit(0)


## Render a few frames with `node` (a CarModel, an AIFleet or null) on the pad; the frame's stats.
func _stats(node: Node3D, fleet_n := 0) -> Dictionary:
	if node != null:
		_world.add_child(node)
	var state := {"x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0, "speed": 20.0, "forward_speed": 20.0, "steer_angle": 0.1,
		"pitch": 0.0, "roll": 0.0, "wheel_rot": 0.0, "grounded": true, "throttle": 1.0}
	var agents: Array = []
	for k in fleet_n:
		var c := state.duplicate()
		c["x"] = float(k % 10 - 5) * 3.0
		c["z"] = float(k / 10) * 6.0
		agents.append({"car": c, "prev": null, "alive": true})
	for f in 6:
		if node is CarModel:
			(node as CarModel).update(state, null, 1.0, 1.0 / 60.0)
		elif node is AIFleet:
			(node as AIFleet).update(agents, _flat_track(), -1, f / 60.0)
		await process_frame
	await RenderingServer.frame_post_draw
	var s := _world.render_stats()
	if node != null:
		node.queue_free()
		await process_frame
	return s


var _flat: BuiltTrack = null


func _flat_track() -> BuiltTrack:
	if _flat == null:
		_flat = Tracks.build("rookie-oval")
	return _flat
