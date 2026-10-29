extends RefCounted
## test_world.gd: headless checks of the 3D world (world/): noise and random ports,
## themes and quality levels, car models, chase camera, track meshes, fleet; the road
## surfaces (v6.3): dirt and snow roads, no paint on them, dusty / snowy barriers, dust and
## snow spray (pooled, scaled by quality), surface-coloured tyre marks, the camera's rumble.
## The pictures themselves are checked by eye with tests/visual/world_*.gd.

const VNoise = preload("res://world/noise.gd")
const Themes = preload("res://world/themes.gd")
const TrackMesh = preload("res://world/track_mesh.gd")
const TrackCtx = preload("res://world/track_ctx.gd")
const Shapes = preload("res://world/car_shapes.gd")
const Kit = preload("res://world/car_kit.gd")


func run(t) -> bool:
	_noise(t)
	_themes(t)
	_cars(t)
	_camera(t)
	_tracks(t)
	_surfaces(t)
	_fleet(t)
	_threaded(t)
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
	for id: String in Cars.ids():
		var car := CarModel.new(id)
		t.tree.root.add_child(car)
		var tris := car.triangles()
		t.check(tris > 8000 and car.skeleton.get_bone_count() == Kit.BONE_COUNT and car.opaque_mesh.skin != null and car.opaque_mesh.mesh != null,
			"%s builds: one skinned mesh of %d triangles on %d bones" % [id, tris, car.skeleton.get_bone_count()])
		var state := {"x": 10.0, "y": 2.0, "z": -5.0, "yaw": 0.7, "pitch": 0.02, "roll": -0.03, "steer_angle": 0.3, "wheel_rot": 1.2,
			"vx": 3.0, "vz": 20.0, "speed": 20.2, "boost": 1.0, "boosting": true, "drifting": true, "slip": 0.4}
		var prev := state.duplicate()
		prev["x"] = 9.0
		car.update(state, prev, 0.5, 1.0 / 60.0)
		var p := car.position
		t.check(p.is_finite() and _near(p.x, 9.5, 1e-6) and _near(p.z, -5.0, 1e-6), "%s interpolates its position" % id)
		t.check(_near(car.rotation.y, 0.7, 1e-6), "%s faces its yaw" % id)
		# wheels: the fronts steer, the rears don't; all of them roll by wheel_rot
		var sk := car.skeleton
		var fl := sk.get_bone_pose(Kit.UPRIGHT0)
		var rl := sk.get_bone_pose(Kit.UPRIGHT0 + 2)
		var spin := sk.get_bone_pose(Kit.SPIN0 + 3)
		t.check(_near(fl.basis.get_euler().y, 0.3, 1e-4) and rl.basis.is_equal_approx(Basis.IDENTITY) and
			spin.basis.is_equal_approx(Basis(Vector3.RIGHT, 1.2)), "%s: front wheels steer 0.3 rad, every wheel rolls" % id)
		# the steering wheel turns with the front wheels and the hands stay on it (arm IK)
		var sw := sk.get_bone_pose(Kit.STEERING)
		var turned := sw.basis.get_rotation_quaternion().get_angle()
		var gap := 0.0
		var joint := 0.0
		for side in 2:
			var hd_r: Vector3 = car.rig["hands"][side]
			var el_r: Vector3 = car.rig["elbows"][side]
			var fore := sk.get_bone_pose(Kit.ARM_FL if side == 0 else Kit.ARM_FR)
			var upper := sk.get_bone_pose(Kit.ARM_UL if side == 0 else Kit.ARM_UR)
			gap = maxf(gap, (fore * hd_r).distance_to(sw * hd_r))
			joint = maxf(joint, (fore * el_r).distance_to(upper * el_r))
		t.check(_near(turned, 0.3 * CarModel.WHEEL_TURN, 0.02) and gap < 0.002 and joint < 1e-4,
			"%s: steering wheel turned %.2f rad, hands on it (%.4f m off), elbows joined" % [id, turned, gap])
		var look := sk.get_bone_pose(Kit.HEAD_BONE).basis * Vector3(0, 0, 1)
		t.check(look.x > 0.1, "%s: the driver looks into the left turn (%.2f)" % [id, look.x])
		var prof := CarModel.profile(id)
		t.check((prof["parts"] as Array).size() > 3 and (prof["wheels"] as Array).size() == 2 and prof.has("rim"), "%s side profile" % id)
		car.free()
	_car_motion(t)
	_car_lights(t)
	var ghost := CarModel.new("dune", {"ghost": true})
	ghost.update({"x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0}, null, 1.0, 1.0 / 60.0)
	var gm := ghost.opaque_mesh.material_override as StandardMaterial3D
	t.check(ghost.position.is_finite() and ghost.glass_mesh == null and gm != null and gm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and
		ghost.smoke == null and ghost.headlights.is_empty(), "ghost: see-through, driver included, no glass, smoke or lights; updates with a minimal state")
	ghost.free()
	var light := CarModel.new("racer", {"detail": 0})
	var full := CarModel.new("racer")
	t.check(light.triangles() < full.triangles() * 0.6, "low detail: %d triangles against %d" % [light.triangles(), full.triangles()])
	light.free()
	full.free()


## Drives a car through `frames` frames of a motion (`f` changes the state each frame); returns the last state.
func _drive(car: CarModel, frames: int, from: Dictionary, f: Callable) -> Dictionary:
	var st := from.duplicate()
	for k in frames:
		f.call(st, k)
		car.update(st, null, 1.0, 1.0 / 60.0)
	return st


func _car_motion(t) -> void:
	t.section("car models: body, suspension and driver in motion")
	var base := {"x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0, "pitch": 0.0, "roll": 0.0, "steer_angle": 0.0, "wheel_rot": 0.0,
		"forward_speed": 30.0, "speed": 30.0, "grounded": true, "braking": false}
	for id: String in ["dune", "vortex", "racer"]:
		var car := CarModel.new(id)
		var sk := car.skeleton
		# a left turn at 18 m/s²: the body rolls out of it over the wheels, the driver leans out
		_drive(car, 60, base, func(st: Dictionary, k: int) -> void:
			st.yaw = 0.6 * k / 60.0
			st.steer_angle = 0.2)
		var body := sk.get_bone_pose(Kit.BODY)
		var torso := sk.get_bone_pose(Kit.TORSO)
		var lean := (torso.basis * Vector3.UP).x - (body.basis * Vector3.UP).x
		t.check(body.basis.get_euler().z > 0.03 and lean < -0.05 and sk.get_bone_pose(Kit.UPRIGHT0 + 2).origin.is_zero_approx(),
			"%s: rolls %.3f rad out of a left turn on its wheels, the driver leans out (%.2f)" % [id, body.basis.get_euler().z, lean])
		# braking hard at speed: the nose dives, the brake lights glow, the Vortex's wing tilts up
		car.reset_effects()
		_drive(car, 40, base, func(st: Dictionary, k: int) -> void:
			st.forward_speed = 40.0 - 12.0 * k / 60.0
			st.braking = true)
		body = sk.get_bone_pose(Kit.BODY)
		var nose := (body * Vector3(0, 0.5, 2.0)).y - 0.5
		var glow := float(car.materials[0].get_shader_parameter("tail_glow"))
		var flap := sk.get_bone_pose(Kit.FLAP).basis.get_euler().x - body.basis.get_euler().x
		t.check(nose < -0.03 and glow > 3.0 and (flap > 0.4 if id == "vortex" else absf(flap) < 1e-6),
			"%s: under braking the nose dives %.3f m, tail lights %.2f, wing %.2f rad" % [id, nose, glow, flap])
		# a jump: the wheels droop in the air; the landing sinks the body onto them, then it settles
		car.reset_effects()
		var air := _drive(car, 30, base, func(st: Dictionary, k: int) -> void:
			var tt := k / 60.0
			st.grounded = false
			st.y = 2.0 + 2.0 * tt - 9.81 * tt * tt)
		var droop := sk.get_bone_pose(Kit.UPRIGHT0).origin.y
		var low := 0.0
		var after := air.duplicate()
		after.grounded = true
		after.y = 0.0
		for k in 90:
			car.update(after, null, 1.0, 1.0 / 60.0)
			low = minf(low, sk.get_bone_pose(Kit.BODY).origin.y)
		var settled := sk.get_bone_pose(Kit.BODY).origin.y
		t.check(droop < -0.04 and low < -0.02 and absf(settled) < 0.01,
			"%s: wheels droop %.3f m in the air, the body sinks %.3f m on landing and settles" % [id, droop, low])
		# the finish: a fist pump (above the helmet in an open car, under the roof in a closed one)
		car.reset_effects()
		_drive(car, 5, base, func(_st: Dictionary, _k: int) -> void: pass)
		car.celebrate()
		var top := -INF
		var side := 0 if float(car.rig["hip"].x) >= 0.0 else 1
		var hd_r: Vector3 = car.rig["hands"][side]
		for k in 60:
			car.update(base, null, 1.0, 1.0 / 60.0)
			top = maxf(top, (sk.get_bone_pose(Kit.ARM_FL if side == 0 else Kit.ARM_FR) * hd_r).y)
		var head_y: float = car.rig["head"].y
		var ok: bool = (top > head_y + 0.1) if car.rig["open"] else (top > hd_r.y + 0.08 and top < float(car.rig["roof"]) - 0.05)
		for k in int(CarModel.CELEBRATION * 60.0):
			car.update(base, null, 1.0, 1.0 / 60.0)
		t.check(ok and car.celebration < 0.0, "%s: fist pump up to %.2f m (head %.2f m), then back on the wheel" % [id, top, head_y])
		car.free()


func _car_lights(t) -> void:
	t.section("car models: headlights follow the theme and quality")
	var w := World.new()
	t.tree.root.add_child(w)
	w.set_theme("night")
	w.set_quality("high")
	var car := CarModel.new("thunder")
	w.add_child(car)
	var ghost := CarModel.new("thunder", {"ghost": true})
	w.add_child(ghost)
	var kinds := func() -> String:
		var out := []
		for n in car.headlights:
			out.append(n.get_class())
		return ",".join(out)
	var st := {"x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0}
	car.update(st)
	t.check(kinds.call() == "SpotLight3D,SpotLight3D" and car.detail == 1, "night, high: two spot lights (%s)" % kinds.call())
	w.set_quality("medium")
	t.check(kinds.call() == "SpotLight3D", "night, medium: one (%s)" % kinds.call())
	w.set_quality("low")
	t.check(kinds.call() == "Decal" and car.detail == 0, "night, low: a light pool decal and the light mesh (%s, detail %d)" % [kinds.call(), car.detail])
	w.set_theme("meadow")
	car.update(st)
	t.check(car.headlights.is_empty() and ghost.headlights.is_empty(), "day: no headlights; a ghost never has them")
	w.free()


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


func _surfaces(t) -> void:
	t.section("road surfaces: dirt and snow")
	# the road: the plain asphalt material on asphalt tracks; on Ramp Rally the surface shader
	# with the dirt's weight in the vertex colours; no lines or curbs on the dirt
	var plain := TrackMesh.build(Tracks.build("rookie-oval"))
	var pm: Material = (plain.find_child("road", false, false) as MeshInstance3D).mesh.surface_get_material(0)
	var rr := Tracks.build("ramp-rally")
	var node := TrackMesh.build(rr)
	var road := node.find_child("road", false, false) as MeshInstance3D
	var sm: Material = road.mesh.surface_get_material(0)
	var cols: PackedColorArray = road.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var dirt := Surfaces.index_of("dirt")
	var on_dirt := 0
	var off_dirt := 0
	var n_dirt := 0
	var n_plain := 0
	for k in cols.size() / 7: # (a row of 7 vertices across the road a sample)
		var i := node.ctx.wrap(k)
		var g: float = cols[k * 7 + 3].g # (the centre column; stored as sRGB)
		var w := rr.surf_w[i * rr.surf_n + dirt]
		if w == 1.0:
			n_dirt += 1
			on_dirt += 1 if g > 0.99 else 0
		elif w == 0.0:
			n_plain += 1
			off_dirt += 1 if g == 0.0 else 0
	var asphalt := TrackMesh.build(Tracks.build_asphalt("ramp-rally"))
	var lines_v: int = (node.find_child("lines", false, false) as MeshInstance3D).mesh.surface_get_array_len(0)
	var lines_a: int = (asphalt.find_child("lines", false, false) as MeshInstance3D).mesh.surface_get_array_len(0)
	var curbs: MeshInstance3D = node.find_child("curbs", false, false)
	var curbs_a: MeshInstance3D = asphalt.find_child("curbs", false, false)
	var curb_v: int = curbs.mesh.surface_get_array_len(0) if curbs != null else 0
	var curb_a: int = curbs_a.mesh.surface_get_array_len(0) if curbs_a != null else 0
	t.check(pm is StandardMaterial3D and sm is ShaderMaterial and (sm as ShaderMaterial).shader.resource_path.ends_with("road_surface.gdshader") and \
		on_dirt == n_dirt and off_dirt == n_plain,
		"the road: asphalt tracks keep the plain material; on Ramp Rally the surface shader, the dirt's weight in every vertex colour (%d samples all dirt, %d all asphalt)" % [n_dirt, n_plain])
	t.check(lines_v < lines_a * 0.75 and curb_v < curb_a, "no paint on the dirt: %d line vertices (all asphalt: %d), %d curb vertices (%d)" % [lines_v, lines_a, curb_v, curb_a])
	plain.free()
	asphalt.free()
	node.free()
	# barriers: snow on top along Hairpin Valley's snow, plain concrete elsewhere
	var hv := Tracks.build("hairpin-valley")
	var hnode := TrackMesh.build(hv)
	var hplain := TrackMesh.build(Tracks.build_asphalt("hairpin-valley"))
	var bc := PackedColorArray()
	var bp := PackedColorArray()
	for n: Node in hnode.get_children():
		if String(n.name).begins_with("barriers-"):
			bc.append_array((n as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR])
			bp.append_array((hplain.find_child(n.name, false, false) as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR])
	var changed := 0
	var same := 0
	var lum := 0.0
	for k in mini(bc.size(), bp.size()):
		if bc[k] == bp[k]:
			same += 1
		else:
			changed += 1
			lum += bc[k].get_luminance() - bp[k].get_luminance()
	t.check(bc.size() == bp.size() and changed > 500 and same > changed and lum > 0.0,
		"barriers: snow on them along the snow (%d vertices, %.2f brighter on average), the rest as on the all-asphalt track (%d)" % [
			changed, lum / maxi(1, changed), same])
	hnode.free()
	hplain.free()

	# the tyres on loose ground: dust on dirt, snow spray on snow, made only when needed, pooled;
	# tyre marks of the surface's colour (faint ones without a slide); fewer puffs at low quality
	var counts: Dictionary = {}
	for q: float in [1.0, 0.3]:
		CarEffects.spark_share = q
		for sid: String in ["dirt", "snow", "asphalt"]:
			var tr := rr if sid != "snow" else hv
			var i := 0
			for k in tr.count:
				if tr.surface[k] == Surfaces.index_of(sid) and tr.surface[tr.wrap(k + 40)] == Surfaces.index_of(sid) and k > 20:
					i = k + 10
					break
			var car := CarModel.new("dune")
			t.tree.root.add_child(car)
			var y := tr.heading(i)
			var st := {"x": tr.px[i], "y": tr.py[i], "z": tr.pz[i], "yaw": y, "vx": sin(y) * 25.0, "vz": cos(y) * 25.0, "speed": 25.0,
				"forward_speed": 25.0, "idx": i, "grounded": true, "slip": 0.5}
			var emitted := 0
			for f in 60:
				st.x = tr.px[i] + sin(y) * 25.0 * f / 60.0
				st.z = tr.pz[i] + cos(y) * 25.0 * f / 60.0
				car.update(st, null, 1.0, 1.0 / 60.0, tr)
				var pool: CarEffects.Spray = car.dust if sid == "dirt" else car.spray
				emitted = pool.alive if pool != null else 0
			var mark := Color(0, 0, car.skids.newest_tint.x, car.skids.newest_tint.y) if car.skids.used > 0 else Color(0, 0, 0, 0)
			counts["%s %s" % [sid, q]] = {alive = emitted, dust = car.dust != null, spray = car.spray != null, mark = mark, smoke = car.smoke.node.visible}
			car.free()
	CarEffects.spark_share = 1.0
	var d1: Dictionary = counts["dirt 1.0"]
	var s1: Dictionary = counts["snow 1.0"]
	var a1: Dictionary = counts["asphalt 1.0"]
	t.check(d1.dust and not d1.spray and d1.alive > 12 and s1.spray and not s1.dust and s1.alive > 12 and not a1.dust and not a1.spray and a1.smoke and not d1.smoke,
		"a sliding Dune at 90 km/h for 1 s: %d dust puffs on dirt, %d snow puffs on snow (pools made only there), tyre smoke only on asphalt" % [d1.alive, s1.alive])
	t.check(counts["dirt 0.3"].alive < d1.alive * 0.5 and counts["snow 0.3"].alive < s1.alive * 0.5,
		"low quality: %d dust and %d snow puffs (30 %% of the emission)" % [counts["dirt 0.3"].alive, counts["snow 0.3"].alive])
	t.check(d1.mark.b > 0.99 and d1.mark.a == 0.0 and s1.mark.a > 0.99 and a1.mark.b == 0.0 and a1.mark.a == 0.0,
		"tyre marks take the colour of the surface: dirt %.2f, snow %.2f, none on asphalt" % [d1.mark.b, s1.mark.a])

	# the camera rumbles on dirt at speed (not on asphalt, not with reduced motion)
	var rumble: Dictionary = {}
	for sid: String in ["dirt", "asphalt", "dirt reduced"]:
		ChaseCamera.reduce_motion = sid == "dirt reduced"
		var cam := ChaseCamera.new()
		cam.set_track(rr)
		var i := 400 if sid != "asphalt" else 40
		var y := rr.heading(i)
		var st := {"x": rr.px[i], "y": rr.py[i], "z": rr.pz[i], "yaw": y, "vx": sin(y) * 35.0, "vz": cos(y) * 35.0, "speed": 35.0, "idx": i, "grounded": true}
		cam.snap(st, rr)
		for f in 90:
			cam.update(st, 1.0 / 60.0)
		rumble[sid] = Vector2(cam.ground_rumble, cam.shake)
		cam.free()
	ChaseCamera.reduce_motion = false
	t.check(rumble.dirt.x > 0.3 and rumble.dirt.y > 0.05 and rumble.asphalt.y == 0.0 and rumble["dirt reduced"].y == 0.0,
		"the camera rumbles on dirt at 126 km/h (shake %.3f), not on asphalt, not with reduced motion" % rumble.dirt.y)


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


var _built: Node3D = null


func _threaded(t) -> void:
	t.section("threaded track build")
	var tr := Tracks.build("ramp-rally")
	var task := WorkerThreadPool.add_task(func() -> void: _built = World.build_track_node(tr))
	WorkerThreadPool.wait_for_task_completion(task)
	var world := World.new()
	var node: Node3D = world.show_track(tr, _built)
	t.check(_built != null and node == _built and node.get_parent() == world and world.render_stats()["build_ms"] > 0,
		"World.build_track_node in a worker thread, then show_track(track, node) (%d ms)" % world.render_stats()["build_ms"])
	world.free()
	_built = null
