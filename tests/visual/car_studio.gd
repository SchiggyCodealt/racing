extends SceneTree
## car_studio.gd: the car models on a plain pad under a theme's sky, for looking at the
## detail: one car close up from any side, or a row of them.
##
##   godot --path . --resolution 1280x720 --script res://tests/visual/car_studio.gd -- \
##       cars=racer,dune view=front34 out=/tmp/studio.png
##
## Options (key=value, all optional):
##   cars       ids (default: every car), placed in a row 5.5 m apart along x
##   view       front34 | rear34 | side | front | rear | top | cockpit | driver | wheel | chase | row (default row:
##              the whole row; the others look at the car `focus`, default 0)
##   dist       camera distance for the single-car views (m, default 6.5)
##   theme, quality   (World), out (png path)
##   steer      front wheel angle (rad); turn: drive in a circle at this lateral g (m/s²,
##              the body rolls, the driver leans) instead of standing still
##   brake      1: braking (brake lights, nose dive, the Vortex's air brake) at speed
##   air        1: airborne (wheels droop)
##   celebrate  seconds into the fist pump
##   ghost      1: draw them as ghosts
##   frames     frames of motion before the shot (default 40)
##   noglass    1: hide the glass (to see the driver)

func _initialize() -> void:
	var o := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		o[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var ids: PackedStringArray = String(o["cars"]).split(",") if o.has("cars") else Cars.ids()
	var world := World.new()
	get_root().add_child(world)
	world.set_theme(String(o.get("theme", "meadow")))
	world.set_quality(String(o.get("quality", "high")))
	var pad := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	pad.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.31, 0.33)
	mat.roughness = 0.92
	pad.material_override = mat
	world.add_child(pad)
	var cars: Array[CarModel] = []
	for id in ids:
		var car := CarModel.new(id, {"ghost": o.get("ghost", "0") == "1"})
		world.add_child(car)
		if o.get("noglass", "0") == "1" and car.glass_mesh != null:
			car.glass_mesh.visible = false
		cars.append(car)
	var steer := float(o.get("steer", "0"))
	var turn := float(o.get("turn", "0"))
	var brake: bool = o.get("brake", "0") == "1"
	var air: bool = o.get("air", "0") == "1"
	var speed := 30.0 if (brake or turn != 0.0) else 0.0
	var frames := int(o.get("frames", "40"))
	var cel := float(o.get("celebrate", "-1"))
	var dt := 1.0 / 60.0
	var yaw_rate := turn / speed if speed > 0.0 else 0.0
	for f in frames:
		var t := f * dt
		for k in cars.size():
			var yaw := yaw_rate * (t - frames * dt)
			var fs := speed - (12.0 * t if brake else 0.0)
			# the sim's attitude: squat / dive and roll with the accelerations (sim/car.gd _attitude)
			var st := {"x": k * 5.5, "y": 1.2 if air else 0.0, "z": 0.0, "yaw": yaw, "pitch": 0.0032 * (-12.0 if brake else 0.0),
				"roll": 0.0035 * turn,
				"steer_angle": steer, "wheel_rot": fmod(t * fs / 0.38, TAU), "forward_speed": fs, "speed": fs,
				"grounded": not air, "braking": brake, "throttle": -1.0 if brake else 0.0}
			cars[k].update(st, null, 1.0, dt)
			# the row stays put on the pad: undo the drive's heading and motion
			cars[k].position = Vector3(k * 5.5, 1.2 if air else 0.0, 0.0)
			cars[k].rotation.y = 0.0
			if cel >= 0.0 and f == frames - 1:
				cars[k].celebrate()
				cars[k].celebration = cel
				cars[k].update(st, null, 1.0, 0.0001)
				cars[k].position = Vector3(k * 5.5, 1.2 if air else 0.0, 0.0)
				cars[k].rotation.y = 0.0
		await process_frame
	var cam := Camera3D.new()
	world.add_child(cam)
	var view: String = o.get("view", "row")
	var focus := int(o.get("focus", "0"))
	var c := Vector3(focus * 5.5, 0.0, 0.0)
	var d := float(o.get("dist", "6.5"))
	cam.fov = float(o.get("fov", "40"))
	match view:
		"front34":
			cam.look_at_from_position(c + Vector3(d * 0.62, 1.7, d * 0.78), c + Vector3(0, 0.55, 0.2))
		"rear34":
			cam.look_at_from_position(c + Vector3(-d * 0.62, 1.9, -d * 0.78), c + Vector3(0, 0.6, -0.2))
		"side":
			cam.look_at_from_position(c + Vector3(d, 0.8, 0.0), c + Vector3(0, 0.6, 0))
		"front":
			cam.look_at_from_position(c + Vector3(0, 1.1, d), c + Vector3(0, 0.6, 0))
		"rear":
			cam.look_at_from_position(c + Vector3(0, 1.5, -d), c + Vector3(0, 0.7, 0))
		"top":
			cam.look_at_from_position(c + Vector3(0.01, d * 1.4, 0), c, Vector3(0, 0, 1))
		"cockpit":
			cam.look_at_from_position(c + Vector3(1.6, 1.9, 1.9), c + Vector3(0, 0.75, -0.3))
		"chase":
			cam.look_at_from_position(c + Vector3(0, 3.4, -9.0), c + Vector3(0, 1.0, 6.0))
		"wheel":
			cam.look_at_from_position(c + Vector3(2.6, 0.7, 3.0), c + Vector3(0.8, 0.4, 1.4))
		"driver":
			cam.look_at_from_position(c + Vector3(0.9, 1.6, 1.3), c + Vector3(0, 0.8, -0.2))
		_:
			var mid := Vector3((ids.size() - 1) * 5.5 * 0.5, 0, 0)
			cam.look_at_from_position(mid + Vector3(-3.0, 5.0, 17.0), mid + Vector3(0, 0.4, 0))
	cam.make_current()
	for f in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var out: String = o.get("out", "/tmp/studio.png")
	img.save_png(out)
	print("saved ", out, " ", JSON.stringify(world.render_stats()))
	quit(0)
