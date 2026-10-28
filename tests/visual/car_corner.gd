extends SceneTree
## car_corner.gd: one car driven by the medal autopilot on a real track, stopped mid-corner
## (or after a number of steps) and photographed: close up in the car's frame (the driver
## turning the wheel and leaning, the front wheels steered, the body rolled) or from the
## chase camera (night-highway: the headlights on the road).
##
##   godot --path . --resolution 1280x720 --script res://tests/visual/car_corner.gd -- \
##       car=vortex track=hairpin-valley out=/tmp/corner.png
##
## Options (key=value, all optional): car, track, quality, out,
##   steer      stop at the first step past `after` with |front wheel angle| above this (rad, default 0.12)
##   after      steps to drive first (default 600)
##   steps      stop after this many steps whatever the steering (default 6000)
##   cam        camera position in the car's frame "x,y,z" (x left, y up, z forward; default 2.6,1.25,3.4)
##   look       where it looks in the car's frame (default 0,0.75,0)
##   chase      1: the game's chase camera instead
##   fov        (default 45)
##   alat, lookk  the medal autopilot's setting (default 26, 0.75: brisk cornering)
##   celebrate  seconds into the fist pump (to see it on the road)

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var o := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		o[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var id: String = o.get("car", "racer")
	var track := Tracks.build(String(o.get("track", "hairpin-valley")))
	var world := World.build(track, String(o.get("quality", "high")))
	get_root().add_child(world)
	var car := Car.new(track, track.start_idx, Cars.spec(id))
	var pilot := Autopilot.medal(track, float(o.get("alat", "26")), float(o.get("lookk", "0.75")))
	var model := CarModel.new(id)
	world.add_child(model)
	var chase: bool = o.get("chase", "0") == "1"
	var cam: Camera3D
	if chase:
		var cc := ChaseCamera.new()
		cc.set_track(track)
		world.add_child(cc)
		cc.snap(car)
		cam = cc
	else:
		cam = Camera3D.new()
		world.add_child(cam)
	cam.fov = float(o.get("fov", "45" if not chase else str(cam.fov)))
	cam.make_current()
	var dt := 1.0 / 60.0
	var after := int(o.get("after", "600"))
	var max_steps := int(o.get("steps", "6000"))
	var min_steer := float(o.get("steer", "0.12"))
	var k := 0
	while k < max_steps:
		var c: Car.Controls = pilot.drive(car)
		car.step(track, c, dt)
		model.update(car, null, 1.0, dt, track)
		if chase:
			(cam as ChaseCamera).update(model.pose, dt, track)
		k += 1
		if k >= after and absf(car.steer_angle) > min_steer and car.grounded and car.speed > 15.0 and not o.has("steps"):
			break
	if o.has("celebrate"):
		model.celebrate()
		model.celebration = float(o["celebrate"])
		model.update(car, null, 1.0, 0.0001, track)
	var xf := model.global_transform
	if not chase:
		var cp := String(o.get("cam", "2.6,1.25,3.4")).split_floats(",")
		var lp := String(o.get("look", "0,0.75,0")).split_floats(",")
		cam.look_at_from_position(xf * Vector3(cp[0], cp[1], cp[2]), xf * Vector3(lp[0], lp[1], lp[2]))
	world.focus_shadows(car.x, car.y, car.z)
	for f in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var out: String = o.get("out", "/tmp/corner.png")
	img.save_png(out)
	print("saved %s after %d steps: %s at %.0f km/h, front wheels %.2f rad, lateral %.1f m/s² (%s)" % [out, k, id, car.speed * 3.6,
		car.steer_angle, car.forward_speed * car.yaw_rate, track.name])
	quit(0)
