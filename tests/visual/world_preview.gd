extends SceneTree
## world_preview.gd: renders one moment of a track and saves a PNG.
##
##   godot --path . --resolution 1280x720 --script res://tests/visual/world_preview.gd -- \
##       track=rookie-oval quality=high cam=chase at=0.1 car=racer out=/tmp/shot.png
##
## Options (key=value, all optional):
##   track     track id (Tracks.ids()), default rookie-oval
##   theme     override the track's theme (meadow desert alpine canyon dusk night seaside autumn arctic highland)
##   quality   high | medium | low
##   cam       chase (behind the car) | overview (training) | orbit (menu) | side (low, beside the car)
##             | free (pos=x,y,z look=x,y,z)
##   at        where the car stands: a fraction of the lap (0..1) or a sample index (>= 1)
##   lat       metres left of the centre line
##   car       racer | kestrel | thunder | drifter | none
##   ghost     1: a ghost car 6 m ahead
##   fleet     N: an AI fleet of N cars over the lap (the first one viewed), rays=1: its sensor rays
##   boost     1: nitro on
##   speed     km/h shown by the camera (field of view) and the effects, default 120
##   angle     orbit angle (rad)
##   frames    frames to render before the shot (default 6)
##   out       PNG path (default user://world_preview.png)
## Prints the track build stats and the frame's draw calls and primitives.

func _initialize() -> void:
	var o := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		o[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var tid: String = o.get("track", "rookie-oval")
	var quality: String = o.get("quality", "high")
	var cam_mode: String = o.get("cam", "chase")
	var car_id: String = o.get("car", "racer")
	var out: String = o.get("out", "user://world_preview.png")
	var frames := int(o.get("frames", "6"))
	var t0 := Time.get_ticks_msec()
	var track := Tracks.build(tid)
	if track == null:
		push_error("unknown track " + tid)
		quit(1)
		return
	var t1 := Time.get_ticks_msec()
	if o.has("theme"):
		track.theme = o["theme"]
	var world := World.build(track, quality)
	var t2 := Time.get_ticks_msec()
	get_root().add_child(world)

	# the car on the road
	var at := float(o.get("at", "0.05"))
	var i := int(at) if at >= 1.0 else int(at * track.count) % track.count
	i = track.wrap(i)
	var lat := float(o.get("lat", "0"))
	var kmh := float(o.get("speed", "120"))
	var v := kmh / 3.6
	var yaw := track.heading(i)
	var y := track.py[i] - lat * tan(track.bank[i])
	var boost: bool = o.get("boost", "0") == "1"
	var state := {
		"x": track.px[i] + track.nx[i] * lat, "y": y, "z": track.pz[i] + track.nz[i] * lat, "yaw": yaw,
		"vx": sin(yaw) * v, "vz": cos(yaw) * v, "speed": v, "forward_speed": v, "idx": i,
		"boost": 1.0 if boost else 0.0, "boosting": boost, "throttle": 1.0, "grounded": true,
	}
	var car: CarModel = null
	if car_id != "none":
		car = CarModel.new(car_id)
		world.add_child(car)
	var ghost: CarModel = null
	if o.get("ghost", "0") == "1":
		ghost = CarModel.new("racer", {"ghost": true})
		world.add_child(ghost)
	var cam := ChaseCamera.new()
	world.add_child(cam)
	cam.make_current()
	var gi := track.wrap(i + 3)
	var gstate := {"x": track.px[gi], "y": track.py[gi], "z": track.pz[gi], "yaw": track.heading(gi), "idx": gi}
	# training view: a fleet spread over the lap (the first is the viewed car, at the car's spot) and its sensor rays
	var fleet: AIFleet = null
	var agents: Array = []
	var nf := int(o.get("fleet", "0"))
	if nf > 0:
		fleet = AIFleet.new(nf)
		world.add_child(fleet)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for k in nf:
			var j := i if k == 0 else track.wrap(i + rng.randi_range(-60, 400))
			var la := 0.0 if k == 0 else rng.randf_range(-0.7, 0.7) * track.hw[j]
			var hy := track.heading(j)
			agents.append({"alive": k % 9 != 4, "prev": null, "car": {"x": track.px[j] + track.nx[j] * la, "y": track.py[j] - la * tan(track.bank[j]),
				"z": track.pz[j] + track.nz[j] * la, "yaw": hy + rng.randf_range(-0.15, 0.15), "idx": j, "speed": 30.0}})
	var rays: SensorRays = null
	if o.get("rays", "0") == "1":
		rays = SensorRays.new()
		world.add_child(rays)

	for f in frames:
		var dt := 1.0 / 60.0
		if car != null:
			car.update(state, null, 1.0, dt, track)
		if ghost != null:
			ghost.update(gstate, null, 1.0, dt, track)
		if fleet != null:
			fleet.update(agents, track, 0, f * dt, 1.0)
		if rays != null:
			var d := PackedFloat32Array()
			var fx := sin(yaw)
			var fz := cos(yaw)
			for a: float in rays.angles:
				var r := deg_to_rad(a)
				var dx := fx * cos(r) + fz * sin(r)
				var dz := fz * cos(r) - fx * sin(r)
				d.append(Collision.raycast(track.grid, float(state["x"]) + fx * 1.5, float(state["z"]) + fz * 1.5, dx, dz, 100.0))
			rays.update(state, d, 100.0)
		match cam_mode:
			"chase":
				if f == 0:
					cam.snap(state, track)
				else:
					cam.update(state, dt, track)
			"overview":
				ChaseCamera.overview_pose(cam, track)
			"orbit":
				ChaseCamera.orbit_pose(cam, track, float(o.get("angle", "0.6")))
			"side":
				var p := Vector3(state["x"], y, state["z"])
				var side := Vector3(track.nx[i], 0, track.nz[i])
				var fwd := Vector3(sin(yaw), 0, cos(yaw))
				cam.fov = 50.0
				var eye := p + side * 7.0 + fwd * 3.0 + Vector3(0, 1.6, 0)
				cam.global_transform = Transform3D(Basis.looking_at(p + Vector3(0, 0.7, 0) - eye, Vector3.UP), eye)
			"free":
				var pp: PackedStringArray = String(o.get("pos", "0,50,0")).split(",")
				var ll: PackedStringArray = String(o.get("look", "0,0,100")).split(",")
				var eye := Vector3(float(pp[0]), float(pp[1]), float(pp[2]))
				var tgt := Vector3(float(ll[0]), float(ll[1]), float(ll[2]))
				cam.fov = float(o.get("fov", "70"))
				cam.global_transform = Transform3D(Basis.looking_at(tgt - eye, Vector3.UP), eye)
		await process_frame
	await RenderingServer.frame_post_draw
	var stats := world.render_stats()
	var img := get_root().get_texture().get_image()
	img.save_png(out)
	print("TRACK %s theme=%s quality=%s cam=%s sample=%d" % [tid, world.theme_name, quality, cam_mode, i])
	print("  track build (sim) %d ms, world build %d ms" % [t1 - t0, t2 - t1])
	print("  stats ", JSON.stringify(stats))
	print("  saved ", out)
	quit(0)
