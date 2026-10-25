extends SceneTree
## world_cars.gd: the four cars (and a ghost) on a flat pad under one theme's sky.
##   godot --path . --resolution 1280x720 --script res://tests/visual/world_cars.gd -- [theme] [quality] [out.png]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var theme_name: String = args[0] if args.size() > 0 else "meadow"
	var level: String = args[1] if args.size() > 1 else "high"
	var out: String = args[2] if args.size() > 2 else "user://world_cars.png"
	var world := World.new()
	get_root().add_child(world)
	world.set_theme(theme_name)
	world.set_quality(level)
	var pad := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	pad.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.33, 0.35)
	mat.roughness = 0.9
	pad.material_override = mat
	world.add_child(pad)
	var ids := ["racer", "kestrel", "thunder", "drifter"]
	var cars: Array[CarModel] = []
	for k in ids.size():
		var car := CarModel.new(ids[k])
		world.add_child(car)
		cars.append(car)
		var s := {x = (k - 1.5) * 4.2, y = 0.0, z = 0.0, yaw = 0.35, steer_angle = 0.2 if k % 2 == 0 else -0.1, wheel_rot = 0.0,
			vx = 0.0, vz = 0.0, speed = 0.0, boosting = k == 2, boost = 1.0 if k == 2 else 0.0}
		car.update(s, null, 1.0, 1.0 / 60.0)
	var ghost := CarModel.new("racer", {ghost = true})
	world.add_child(ghost)
	ghost.update({x = 0.0, y = 0.0, z = -6.0, yaw = 0.0}, null, 1.0, 1.0 / 60.0)
	var cam := Camera3D.new()
	cam.fov = 50
	world.add_child(cam)
	cam.look_at_from_position(Vector3(-6, 4.5, 11), Vector3(0, 0.6, -1))
	for i in 8:
		for k in cars.size():
			var s2 := {x = (k - 1.5) * 4.2, y = 0.0, z = 0.0, yaw = 0.35, boosting = k == 2, boost = 1.0 if k == 2 else 0.0}
			cars[k].update(s2, null, 1.0, 1.0 / 60.0)
		await process_frame
	var img := get_root().get_texture().get_image()
	img.save_png(out)
	print("saved ", out, " ", world.render_stats())
	quit(0)
