extends SceneTree
## world_cars.gd: the four cars (and a ghost) under one theme's sky, on a flat pad or on a
## track just past its start line (the web README's cars.png moment).
##
##   godot --path . --resolution 1280x720 --script res://tests/visual/world_cars.gd -- \
##       theme=meadow quality=high out=/tmp/cars.png [track=rookie-oval] [ghost=1]
##
## Options (key=value, all optional): theme (pad only; a track uses its own; all or a,b,c: one shot
## per theme, saved as out_<theme>.png), quality, out,
## track (cars on that track instead of the pad), ghost (1: a ghost racer behind them; default 1 on the pad).

const Themes = preload("res://world/themes.gd")

func _initialize() -> void:
	var o := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		o[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var level: String = o.get("quality", "high")
	var out: String = o.get("out", "user://world_cars.png")
	var ids := ["racer", "kestrel", "thunder", "drifter"]
	var states: Array[Dictionary] = []
	var world: World
	var cam := Camera3D.new()
	var ghost_state := {}
	var track: BuiltTrack = null
	if o.has("track"):
		# on the road a little past the start line, staggered across it, the camera looking back at the gate
		track = Tracks.build(o["track"])
		world = World.build(track, level)
		get_root().add_child(world)
		var i0 := 0
		var step := track.seg_len
		for k in ids.size():
			var along := 13.0 - 2.6 * k
			var lat := -4.6 + 3.3 * k
			var j := track.wrap(i0 + roundi(along / step))
			var yaw := track.heading(j) + 0.55
			states.append({"x": track.px[j] + track.nx[j] * lat, "y": track.py[j] - lat * tan(track.bank[j]),
				"z": track.pz[j] + track.nz[j] * lat, "yaw": yaw, "idx": j, "steer_angle": 0.0, "speed": 0.0})
		var jc := track.wrap(i0 + roundi(25.0 / step))
		var jt := track.wrap(i0 + roundi(7.0 / step))
		var eye := Vector3(track.px[jc] - track.nx[jc] * 6.0, track.py[jc] + 2.4, track.pz[jc] - track.nz[jc] * 6.0)
		var at := Vector3(track.px[jt] + track.nx[jt] * 1.0, track.py[jt] + 0.9, track.pz[jt] + track.nz[jt] * 1.0)
		cam.fov = 52
		world.add_child(cam)
		cam.look_at_from_position(eye, at)
		if o.get("ghost", "0") == "1":
			var jg := track.wrap(i0 + roundi(2.0 / step))
			ghost_state = {"x": track.px[jg], "y": track.py[jg], "z": track.pz[jg], "yaw": track.heading(jg), "idx": jg}
	else:
		world = World.new()
		get_root().add_child(world)
		world.set_theme(String(o.get("theme", "meadow")).split(",")[0].replace("all", "meadow"))
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
		for k in ids.size():
			states.append({"x": (k - 1.5) * 4.2, "y": 0.0, "z": 0.0, "yaw": 0.35, "steer_angle": 0.2 if k % 2 == 0 else -0.1, "speed": 0.0})
		cam.fov = 50
		world.add_child(cam)
		cam.look_at_from_position(Vector3(-6, 4.5, 11), Vector3(0, 0.6, -1))
		if o.get("ghost", "1") == "1":
			ghost_state = {"x": 0.0, "y": 0.0, "z": -6.0, "yaw": 0.0}
	cam.make_current()
	var cars: Array[CarModel] = []
	for k in ids.size():
		var car := CarModel.new(ids[k])
		world.add_child(car)
		cars.append(car)
		states[k]["boosting"] = k == 2 and track == null
		states[k]["boost"] = 1.0 if states[k]["boosting"] else 0.0
	var ghost: CarModel = null
	if not ghost_state.is_empty():
		ghost = CarModel.new("racer", {"ghost": true})
		world.add_child(ghost)
	# theme=all (or a comma-separated list) on the pad: one shot per theme, out_<theme>.png
	var themes: PackedStringArray = [world.theme_name]
	if track == null and (o.get("theme", "") == "all" or String(o.get("theme", "")).contains(",")):
		themes = PackedStringArray(Themes.NAMES) if o["theme"] == "all" else String(o["theme"]).split(",")
	for th in themes:
		var path := out
		if themes.size() > 1:
			world.set_theme(th)
			path = out.get_basename() + "_" + th + ".png"
		for f in 8:
			for k in cars.size():
				cars[k].update(states[k], null, 1.0, 1.0 / 60.0, track)
			if ghost != null:
				ghost.update(ghost_state, null, 1.0, 1.0 / 60.0, track)
			world.focus_shadows(states[0]["x"], states[0]["y"], states[0]["z"])
			await process_frame
		await RenderingServer.frame_post_draw
		var img := get_root().get_texture().get_image()
		img.save_png(path)
		print("saved ", path, " ", JSON.stringify(world.render_stats()))
	quit(0)
