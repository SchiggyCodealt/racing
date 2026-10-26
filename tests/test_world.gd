extends RefCounted
## test_world.gd: headless checks of the 3D world (world/): noise and random ports,
## themes and quality levels, car models, chase camera, track meshes, fleet.
## The pictures themselves are checked by eye with tests/visual/world_*.gd.

const VNoise = preload("res://world/noise.gd")
const Themes = preload("res://world/themes.gd")
const TrackMesh = preload("res://world/track_mesh.gd")
const TrackCtx = preload("res://world/track_ctx.gd")
const Shapes = preload("res://world/car_shapes.gd")


func run(t) -> bool:
	_noise(t)
	_themes(t)
	_cars(t)
	_camera(t)
	_tracks(t)
	_fleet(t)
	return true


func _near(a: float, b: float, eps := 1e-12) -> bool:
	return absf(a - b) <= eps


func _noise(t) -> void:
	t.section("noise and random numbers = the JS (trackMesh.js)")
	# reference values from node (the JS functions verbatim)
	var seed := VNoise.track_seed("lighthouse-bay")
	t.check(seed == 3307829481, "track seed of lighthouse-bay (%d)" % seed)
	var r := VNoise.Rng.new(seed ^ 0x9e3779b9)
	var a := r.next()
	var b := r.next()
	var c := r.next()
	t.check(_near(a, 0.32860470563173294) and _near(b, 0.6063826936297119) and _near(c, 0.14256579498760402), "mulberry32 sequence")
	t.check(_near(VNoise.vnoise(3.7, -12.25, 5), 0.25340890675818084), "vnoise")
	t.check(_near(VNoise.vnoise(-1003.4, 77.1, seed + 41), 0.3429865046370618), "vnoise, big seed")
	t.check(_near(VNoise.vnoise(0.5, 0.5, -7), 0.47894758341135457), "vnoise, negative seed")
	t.check(_near(VNoise.fbm(12.5, -3.25, 3, seed + 31), 0.5796967497860075), "fbm 3 octaves")
	t.check(_near(VNoise.fbm(-0.37, 2.2, 4, 11), 0.503399964159159), "fbm 4 octaves")
	var fast := VNoise.fast_fbm(seed, 4)
	var lo := INF
	var hi := -INF
	for k in 2000:
		var v := 0.5 + 0.5 * fast.get_noise_2d(k * 0.37, k * 0.11)
		lo = minf(lo, v)
		hi = maxf(hi, v)
	t.check(lo >= 0.0 and hi <= 1.0 and hi - lo > 0.4, "fast fbm stays in 0..1 with spread (%.2f..%.2f)" % [lo, hi])


func _themes(t) -> void:
	t.section("themes and quality levels")
	var keys := ["sky", "sun", "hemi", "env", "fog", "exposure", "bloom", "ground", "hills", "mountains", "mountainStyle", "accent", "lamps", "scenery", "tuft"]
	for nm: String in Themes.NAMES:
		var th: Dictionary = Themes.THEMES[nm]
		var missing := []
		for k: String in keys:
			if not th.has(k):
				missing.append(k)
		t.check(missing.is_empty(), "theme %s has every field %s" % [nm, missing])
	t.check(Themes.get_theme("nope") == Themes.THEMES["meadow"], "unknown theme -> meadow")
	for q: String in Themes.QUALITY_ORDER:
		var d: Dictionary = Themes.QUALITY[q]
		t.check(d.has("scenery") and d.has("shadow") and d.has("tufts") and d.has("lamp_lights") and d.has("terrain_shadows"), "quality %s complete" % q)
	var low: Dictionary = Themes.QUALITY["low"]
	t.check(not low["bloom"] and not low["ssao"] and not low["tufts"] and float(low["scenery"]) < 0.5 and int(low["msaa"]) == 0, "low stays light")
	var w := World.new()
	for nm: String in Themes.NAMES:
		w.set_theme(nm)
		t.check(w.theme_name == nm and _near(w.env.fog_depth_end, float(Themes.THEMES[nm]["fog"]["far"]), 1e-3), "World.set_theme(%s)" % nm)
	w.set_quality("low")
	t.check(w.quality == "low" and w.sun.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL and not w.env.glow_enabled, "World.set_quality(low)")
	w.free()


func _cars(t) -> void:
	t.section("car models")
	for id: String in ["racer", "kestrel", "thunder", "drifter"]:
		var car := CarModel.new(id)
		var tris := 0
		for n in car.find_children("*", "MeshInstance3D", true, false):
			var m: Mesh = (n as MeshInstance3D).mesh
			if m != null:
				for s in m.get_surface_count():
					tris += (m.surface_get_array_index_len(s) if m.surface_get_array_index_len(s) > 0 else m.surface_get_array_len(s)) / 3
		t.check(tris > 2000, "%s builds (%d triangles)" % [id, tris])
		var state := {"x": 10.0, "y": 2.0, "z": -5.0, "yaw": 0.7, "pitch": 0.02, "roll": -0.03, "steer_angle": 0.3, "wheel_rot": 1.2,
			"vx": 3.0, "vz": 20.0, "speed": 20.2, "boost": 1.0, "boosting": true, "drifting": true, "slip": 0.4}
		var prev := state.duplicate()
		prev["x"] = 9.0
		car.update(state, prev, 0.5, 1.0 / 60.0)
		var p := car.position
		t.check(p.is_finite() and _near(p.x, 9.5, 1e-6) and _near(p.z, -5.0, 1e-6), "%s interpolates its position" % id)
		t.check(_near(car.rotation.y, 0.7, 1e-6), "%s faces its yaw" % id)
		var prof := CarModel.profile(id)
		t.check((prof["parts"] as Array).size() > 3 and (prof["wheels"] as Array).size() == 2, "%s side profile" % id)
		car.free()
	var ghost := CarModel.new("racer", {"ghost": true})
	ghost.update({"x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0}, null, 1.0, 1.0 / 60.0)
	t.check(ghost.position.is_finite(), "ghost builds and updates with a minimal state")
	ghost.free()


func _camera(t) -> void:
	t.section("chase camera")
	var cam := ChaseCamera.new()
	var car := {"x": 0.0, "y": 1.0, "z": 0.0, "yaw": 0.0, "vx": 0.0, "vz": 0.0, "speed": 0.0}
	cam.snap(car)
	t.check(cam.position.distance_to(Vector3(0, 4.4, -9)) < 1e-4, "snap: 9 m behind, 3.4 m above")
	var fwd := -cam.transform.basis.z
	t.check(fwd.z > 0.9 and fwd.y < 0.0, "looks ahead and a little down")
	car["vz"] = 70.0
	car["speed"] = 70.0
	car["forward_speed"] = 70.0
	for k in 120:
		car["z"] = float(car["z"]) + 70.0 / 60.0
		cam.update(car, 1.0 / 60.0)
	t.check(cam.fov > 80.0 and cam.dist > 9.5, "speed widens the view and drops the camera back (fov %.1f, %.2f m)" % [cam.fov, cam.dist])
	car["boost"] = 1.0
	for k in 60:
		cam.update(car, 1.0 / 60.0)
	t.check(cam.kick > 0.9, "nitro kick eases in (%.2f)" % cam.kick)
	# a wall hit shakes, reduced motion does not
	car["wall_hits"] = 0
	cam.update(car, 1.0 / 60.0)
	car["wall_hits"] = 1
	car["hit_wall"] = true
	car["wall_impact"] = 15.0
	cam.update(car, 1.0 / 60.0)
	t.check(cam.shake > 0.1, "a hit at 15 m/s shakes (%.2f)" % cam.shake)
	ChaseCamera.reduce_motion = true
	car["wall_hits"] = 2
	cam.update(car, 1.0 / 60.0)
	t.check(cam.shake == 0.0, "no shake with reduced motion")
	ChaseCamera.reduce_motion = false
	var sd := ChaseCamera.smooth_damp(0.0, 1.0, 0.0, 0.3, INF, 1.0 / 60.0)
	var v := Vector2(0.0, 0.0)
	for k in 300:
		v = ChaseCamera.smooth_damp(v.x, 1.0, v.y, 0.3, INF, 1.0 / 60.0)
	t.check(sd.x > 0.0 and sd.x < 0.1 and absf(v.x - 1.0) < 1e-3, "smooth_damp eases to the target")
	var tr := Tracks.build("rookie-oval")
	ChaseCamera.overview_pose(cam, tr)
	t.check((-cam.transform.basis.z).y < -0.9 and cam.position.y > 200.0, "overview looks down from high above")
	cam.free()


func _tracks(t) -> void:
	t.section("track meshes")
	for id: String in ["rookie-oval", "night-highway", "lighthouse-bay", "seaside-stunts"]:
		var tr := Tracks.build(id)
		var t0 := Time.get_ticks_msec()
		var node := TrackMesh.build(tr)
		var ms := Time.get_ticks_msec() - t0
		var terrain = node.terrain
		var ctx: TrackCtx = node.ctx
		t.check(node.get_child_count() > 20, "%s builds in %d ms (%d nodes, %d scenery)" % [id, ms, node.get_child_count(), ctx.scenery_count])
		# the terrain never covers the road: at every sample it is below both road edges
		var worst := -INF
		for i in range(0, tr.count, 3):
			for s: float in [1.0, -1.0]:
				var e := Vector2(tr.px[i] + tr.nx[i] * s * tr.hw[i], tr.pz[i] + tr.nz[i] * s * tr.hw[i])
				worst = maxf(worst, terrain.height_at(e.x, e.y) - ctx.edge_y(i, s))
		t.check(worst < 0.05, "%s: terrain stays under the road edges (worst %.3f m)" % [id, worst])
		var gates := 0
		for n in node.get_children():
			if String(n.name).begins_with("gate-lights"):
				gates += 1
		t.check(gates == tr.cp_samples.size() + (1 if tr.closed else 2), "%s: one lit gate per checkpoint and start/finish" % id)
		node.set_checkpoint_state(0, "passed")
		t.check(node.cp_materials[0].albedo_color.is_equal_approx(Themes.col(0x2ee66a)), "%s: set_checkpoint_state colours the gate" % id)
		# scenery stays off the road and out of the sea
		var bad := 0
		var full := 0
		for d: Dictionary in node.detail_nodes:
			var mmi: MultiMeshInstance3D = d["node"]
			if d["kind"] != "scenery" or not d.has("buffer"):
				continue
			var buf: PackedFloat32Array = d["buffer"]
			for k in mmi.multimesh.instance_count:
				var o := Vector3(buf[k * 16 + 3], buf[k * 16 + 7], buf[k * 16 + 11])
				if terrain.edge_dist(o.x, o.z) < 12.0 or (terrain.has_water and terrain.sea_at(o.x, o.z) > 0.2):
					bad += 1
			full += mmi.multimesh.instance_count
		t.check(full > 500 and bad == 0, "%s: %d scenery instances, none on the road or in the sea" % [id, full])
		node.apply_quality(Themes.QUALITY["low"])
		var shown := 0
		var tufts_hidden := true
		for d: Dictionary in node.detail_nodes:
			var mmi: MultiMeshInstance3D = d["node"]
			if d["kind"] == "tuft":
				tufts_hidden = tufts_hidden and not mmi.visible
			else:
				shown += mmi.multimesh.visible_instance_count
		t.check(tufts_hidden and shown < full * 0.5, "%s: low quality thins the scenery (%d of %d) and drops the grass" % [id, shown, full])
		if id == "night-highway":
			t.check(node.find_child("skyline", false, false) != null and node.find_child("glow-stripes-0", false, false) != null, "night: skyline and glowing stripes")
			t.check(node.lamp_lights.size() > 10 and not node.lamp_lights[0].visible, "night: lamp lights (off on low)")
		if id == "lighthouse-bay":
			t.check(node.find_child("lighthouse", false, false) != null and node.find_child("sea", false, false) != null, "seaside: sea and lighthouse")
		node.free()


func _fleet(t) -> void:
	t.section("AI fleet")
	var tr := Tracks.build("rookie-oval")
	var fleet := AIFleet.new(4)
	var car := {"x": tr.px[10], "y": tr.py[10], "z": tr.pz[10], "yaw": tr.heading(10), "idx": 10}
	var other := car.duplicate()
	other["x"] = float(other["x"]) + 0.3  # a clone driving the same line: drawn once
	var far := {"x": tr.px[100], "y": tr.py[100], "z": tr.pz[100], "yaw": tr.heading(100), "idx": 100}
	var agents := [{"car": car, "prev": null, "alive": true}, {"car": other, "prev": null, "alive": true},
		{"car": far, "prev": null, "alive": true}, {"car": far, "prev": null, "alive": false}]
	fleet.update(agents, tr, 0, 0.0, 1.0)
	var shown := 0
	for k in 4:
		if fleet.is_drawn(k):
			shown += 1
	t.check(shown == 2, "overlapping clones are drawn once, dead cars hidden (%d shown)" % shown)
	t.check(fleet.has_selected_view and _near(float(fleet.selected_view["x"]), tr.px[10], 1e-4), "selected view follows the viewed car")
	fleet.free()
