extends RefCounted
## test_world.gd: headless checks of the 3D world (world/): noise and random ports,
## themes and quality levels, car models, chase camera, track meshes, fleet; the road
## surfaces (v6.3): dirt and snow roads, no paint on them, dusty / snowy barriers, dust and
## snow spray (pooled, scaled by quality), surface-coloured tyre marks; (v6.10) the barriers'
## grime shader, the AI opponent's dust, no camera rumble on loose ground but mud and snow on
## the screen (world/screen_grime.gd: builds, fades, quality, setting, the middle kept clear);
## the themes of v6.4: the arctic sky's northern lights, the autumn woods, the highland's snow
## beside snowy road (and the trees that know it).
## The pictures themselves are checked by eye with tests/visual/world_*.gd.

const VNoise = preload("res://world/noise.gd")
const Themes = preload("res://world/themes.gd")
const TrackMesh = preload("res://world/track_mesh.gd")
const TrackCtx = preload("res://world/track_ctx.gd")
const Shapes = preload("res://world/car_shapes.gd")
const Kit = preload("res://world/car_kit.gd")
const TrackScenery = preload("res://world/track_scenery.gd")


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
	var auroras := []
	for nm: String in Themes.NAMES:
		w.set_theme(nm)
		t.check(w.theme_name == nm and _near(w.env.fog_depth_end, float(Themes.THEMES[nm]["fog"]["far"]), 1e-3), "World.set_theme(%s)" % nm)
		if float(w.sky_mat.get_shader_parameter("aurora")) > 0.0:
			auroras.append(nm)
	# v6.4: the arctic night has the northern lights in its sky, no other theme does
	t.check(auroras == ["arctic"], "northern lights in the sky of %s only" % [auroras])
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
	var near_road := {}
	for id: String in ["rookie-oval", "night-highway", "lighthouse-bay", "seaside-stunts", "forest-rally", "northern-lights", "summit-rush"]:
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
				if terrain.edge_dist(o.x, o.z) < 50.0:
					near_road[id] = int(near_road.get(id, 0)) + 1
			full += mmi.multimesh.instance_count
		t.check(full > 500 and bad == 0, "%s: %d scenery instances, none on the road or in the sea" % [id, full])
		if id == "summit-rush":
			_road_snow(t, tr, node)
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
	# v6.4: the autumn theme's woods (theme "woods") grow close to Forest Rally's road
	t.check(int(near_road.get("forest-rally", 0)) > 2 * int(near_road.get("rookie-oval", 0)),
		"autumn woods: %d trees and rocks within 50 m of Forest Rally's road (the meadow of Rookie Oval: %d)" % [near_road.get("forest-rally", 0), near_road.get("rookie-oval", 0)])


## v6.4, theme ground.roadSnow (Summit Rush's highland): the land beside the snowy road is white,
## the land beside its asphalt start is not, and the trees know it (species onSnow: snowy pines
## only on the snow, larches and green pines only off it).
func _road_snow(t, tr: BuiltTrack, node: Node3D) -> void:
	var terrain = node.terrain
	var snow := Surfaces.index_of("snow")
	var i_snow := -1
	for k in range(30, tr.count - 30):
		if tr.surface[k - 30] == snow and tr.surface[k] == snow and tr.surface[k + 30] == snow:
			i_snow = k
			break
	var side := func(i: int, off: float) -> float:
		return terrain.snow_at(tr.px[i] + tr.nx[i] * (tr.hw[i] + off), tr.pz[i] + tr.nz[i] * (tr.hw[i] + off))
	var on_snow := minf(side.call(i_snow, 20.0), side.call(i_snow, -20.0))
	var at_start := maxf(side.call(tr.start_idx, 20.0), side.call(tr.start_idx, -20.0))
	var wrong := 0
	var counted := {}
	for d: Dictionary in node.detail_nodes:
		var mmi: MultiMeshInstance3D = d["node"]
		var sp := String(mmi.name).get_slice("-", 0)
		if d["kind"] != "scenery" or not d.has("buffer") or not TrackScenery.SPECIES.get(sp, {}).has("onSnow"):
			continue
		var want: bool = TrackScenery.SPECIES[sp]["onSnow"]
		var buf: PackedFloat32Array = d["buffer"]
		for k in mmi.multimesh.instance_count:
			if (terrain.snow_at(buf[k * 16 + 3], buf[k * 16 + 11]) > 0.5) != want:
				wrong += 1
			counted[sp] = int(counted.get(sp, 0)) + 1
	t.check(i_snow >= 0 and on_snow > 0.9 and at_start == 0.0 and wrong == 0 and counted.size() == 3,
		"Summit Rush: snow on the land beside its snowy road (%.2f), none beside the asphalt start; %s, none on the wrong ground" % [on_snow, counted])


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
	# barriers (v6.10): the grime shader on a track with dirt or snow, with the colours of the
	# all-asphalt track and what the road beside them throws at them in the alpha: 0 snow along
	# Hairpin Valley's snow, 1 dirt along Ramp Rally's dirt, 0.5 elsewhere
	var hv := Tracks.build("hairpin-valley")
	var bars := {}
	for tid: String in ["hairpin-valley", "ramp-rally"]:
		var tn := TrackMesh.build(hv if tid == "hairpin-valley" else rr)
		var tp := TrackMesh.build(Tracks.build_asphalt(tid))
		var same_rgb := true
		var grime_mat := true
		var hist := Vector3i.ZERO # snow, nothing, dirt
		var plain_mat := true
		for n: Node in tn.get_children():
			if not String(n.name).begins_with("barriers-"):
				continue
			var mi := n as MeshInstance3D
			var other := tp.find_child(n.name, false, false) as MeshInstance3D
			var bm: Material = mi.mesh.surface_get_material(0)
			grime_mat = grime_mat and bm is ShaderMaterial and (bm as ShaderMaterial).shader.resource_path.ends_with("barrier_grime.gdshader")
			plain_mat = plain_mat and other.mesh.surface_get_material(0) is StandardMaterial3D
			var bc: PackedColorArray = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
			var bp: PackedColorArray = other.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
			same_rgb = same_rgb and bc.size() == bp.size()
			for k in mini(bc.size(), bp.size()):
				var dc := Vector3(bc[k].r - bp[k].r, bc[k].g - bp[k].g, bc[k].b - bp[k].b)
				same_rgb = same_rgb and dc.length() < 0.01
				if bc[k].a < 0.02:
					hist.x += 1
				elif absf(bc[k].a - 0.5) < 0.01:
					hist.y += 1
				elif bc[k].a > 0.98:
					hist.z += 1
		bars[tid] = {same = same_rgb, mat = grime_mat and plain_mat, hist = hist}
		tn.free()
		tp.free()
	var bh: Dictionary = bars["hairpin-valley"]
	var br: Dictionary = bars["ramp-rally"]
	t.check(bh.mat and br.mat and bh.same and br.same and bh.hist.x > 500 and bh.hist.y > 500 and bh.hist.z == 0 and \
		br.hist.z > 500 and br.hist.y > 500 and br.hist.x == 0,
		"barriers: the grime shader (plain material on the all-asphalt tracks), the same colours, snowy along the snow (%d vertices), dirty along the dirt (%d), clean elsewhere (%d / %d)" % [
			bh.hist.x, br.hist.z, bh.hist.y, br.hist.y])

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

	# (v6.10) the AI opponent's ghost throws up dust too (opts.dust); the best-run ghost doesn't
	var gd := {}
	for with_dust: bool in [true, false]:
		var gcar := CarModel.new("racer", {"ghost": true, "dust": with_dust})
		t.tree.root.add_child(gcar)
		var gi := 400
		var gy := rr.heading(gi)
		var gst := {"x": rr.px[gi], "y": rr.py[gi], "z": rr.pz[gi], "yaw": gy, "vx": sin(gy) * 30.0, "vz": cos(gy) * 30.0, "speed": 30.0,
			"forward_speed": 30.0, "idx": gi, "grounded": true, "slip": 0.2}
		for f in 40:
			gcar.update(gst, null, 1.0, 1.0 / 60.0, rr)
		gd[with_dust] = gcar.dust.alive if gcar.dust != null else 0
		gcar.free()
	t.check(gd[true] > 5 and gd[false] == 0, "the AI opponent's ghost throws up dust on dirt (%d puffs), the best-run ghost none" % gd[true])

	# (v6.10) no more camera rumble on loose ground (the screen gets mud and snow instead); the
	# wall shake stays (see the camera section)
	var cam := ChaseCamera.new()
	cam.set_track(rr)
	var ci := 400
	var cy := rr.heading(ci)
	var cst := {"x": rr.px[ci], "y": rr.py[ci], "z": rr.pz[ci], "yaw": cy, "vx": sin(cy) * 35.0, "vz": cos(cy) * 35.0, "speed": 35.0, "idx": ci, "grounded": true}
	cam.snap(cst, rr)
	for f in 90:
		cam.update(cst, 1.0 / 60.0)
	t.check(cam.shake == 0.0, "the camera stays still on dirt at 126 km/h (shake %.3f)" % cam.shake)
	cam.free()
	_screen_grime(t, rr, hv)


## (v6.10) world/screen_grime.gd: mud and snow on the screen.
func _screen_grime(t, rr: BuiltTrack, hv: BuiltTrack) -> void:
	var dirt_i := 400 # (Ramp Rally: dirt from sample 168 to 730)
	var tar_i := 40   # (asphalt)
	var snow_i := 650 # (Hairpin Valley: snow from 492 to 815)
	var pose := func(tr: BuiltTrack, i: int, speed: float, slip: float, dx := 0.0) -> CarEffects.Pose:
		var y := tr.heading(i)
		return CarEffects.Pose.new().read({"x": tr.px[i] + sin(y) * dx, "y": tr.py[i], "z": tr.pz[i] + cos(y) * dx, "yaw": y,
			"vx": sin(y) * speed, "vz": cos(y) * speed, "speed": speed, "forward_speed": speed, "idx": i, "grounded": true, "slip": slip})
	var drive := func(g: ScreenGrime, tr: BuiltTrack, p: CarEffects.Pose, secs: float, ahead := Vector2.ZERO) -> void:
		for f in roundi(secs * 60.0):
			g.update(1.0 / 60.0, p, tr, ahead)
	# whether anything is drawn inside the keep-out ellipse around the middle of the screen
	var clear := func(g: ScreenGrime) -> bool:
		for b: ScreenGrime.Blob in g.blobs():
			if g.keep_metric(b.pos, g.reach(b)) < 0.999:
				return false
		return true
	var g := ScreenGrime.new(rr)
	t.tree.root.add_child(g)
	var s := g.screen()
	# the middle of the screen (30..70 % each way) lies inside the keep-out ellipse
	var mid_in := g.keep_metric(s * 0.3, 0.0) < 1.0 and g.keep_metric(s * 0.7, 0.0) < 1.0 and \
		g.keep_metric(Vector2(s.x * 0.3, s.y * 0.7), 0.0) < 1.0 and g.keep_metric(Vector2(s.x * 0.7, s.y * 0.3), 0.0) < 1.0
	var clear_all := true
	# dirt at 126 km/h, sliding a little: mud builds up
	for k in 6:
		drive.call(g, rr, pose.call(rr, dirt_i, 35.0, 0.3), 0.5)
		clear_all = clear_all and clear.call(g)
	var mud := {n = g.count(), fly = g.flyer_count(), level = g.level, film = g.film, frost = g.frost, kinds = _kinds(g)}
	# then asphalt: it stops, slides off and fades
	drive.call(g, rr, pose.call(rr, tar_i, 35.0, 0.0), 2.5)
	clear_all = clear_all and clear.call(g)
	var off := {n = g.count(), film = g.film}
	drive.call(g, rr, pose.call(rr, tar_i, 35.0, 0.0), 4.0)
	var off2 := {n = g.count() + g.flyer_count(), film = g.film, vis = g._rect.visible}
	t.check(mid_in and mud.n >= 12 and mud.kinds.x == mud.n and mud.fly > 0 and mud.level.x > 0.6 and mud.film > 0.4 and mud.frost == 0.0,
		"dirt at 126 km/h for 3 s: %d mud splats, %d clods flying past, a film of mud %.2f, no frost" % [mud.n, mud.fly, mud.film])
	t.check(off.n == 0 and off.film < 0.15 and off2.n == 0 and off2.film == 0.0 and not off2.vis,
		"then asphalt: the splats gone after 2.5 s, the film %.2f, nothing left after 6.5 s" % off.film)
	t.check(clear_all, "nothing ever drawn inside the keep-out ellipse around the middle of the screen")
	# standing still: nothing; a car close ahead on the dirt throws its dust at the screen
	g.clear()
	var still: CarEffects.Pose = pose.call(rr, dirt_i, 0.0, 0.0)
	drive.call(g, rr, still, 2.0)
	var n_still := g.count()
	var ahead := ScreenGrime.ahead_of(still, pose.call(rr, dirt_i + 6, 30.0, 0.0), rr)
	var behind := ScreenGrime.ahead_of(still, pose.call(rr, dirt_i - 6, 30.0, 0.0), rr)
	var far := ScreenGrime.ahead_of(still, pose.call(rr, dirt_i + 25, 30.0, 0.0), rr)
	var on_tar := ScreenGrime.ahead_of(pose.call(rr, tar_i, 0.0, 0.0), pose.call(rr, tar_i + 6, 30.0, 0.0), rr)
	drive.call(g, rr, still, 2.0, ahead)
	t.check(n_still == 0 and ahead.x > 0.5 and behind == Vector2.ZERO and far.x < 0.1 and on_tar == Vector2.ZERO and g.count() > 3,
		"standing on the dirt: no mud; a car 12 m ahead at 108 km/h throws %.2f of its dust at the screen (%d splats; none from behind, %.2f from 50 m, none on asphalt)" % [
			ahead.x, g.count(), far.x])
	# fewer at low quality
	g.clear()
	CarEffects.spark_share = 0.3
	var low_max := 0
	for k in 8:
		drive.call(g, rr, pose.call(rr, dirt_i, 35.0, 0.3), 0.5)
		low_max = maxi(low_max, g.count())
	CarEffects.spark_share = 1.0
	t.check(low_max <= roundi(ScreenGrime.MAX_SPLATS * 0.3) and low_max < mud.n,
		"low quality: at most %d splats (%d at most, high: %d)" % [low_max, roundi(ScreenGrime.MAX_SPLATS * 0.3), mud.n])
	# the setting switches it off
	ScreenGrime.enabled = false
	drive.call(g, rr, pose.call(rr, dirt_i, 35.0, 0.3), 1.0)
	var off_n := g.count() + g.flyer_count()
	var off_vis := g.visible
	ScreenGrime.enabled = true
	drive.call(g, rr, pose.call(rr, dirt_i, 35.0, 0.3), 1.0)
	t.check(off_n == 0 and not off_vis and g.count() > 0, "the setting off: nothing on the screen; on again: mud again (%d)" % g.count())
	g.free()
	# snow: flecks of snow and frost, no mud
	var gs := ScreenGrime.new(hv)
	t.tree.root.add_child(gs)
	var clear_snow := true
	for k in 8:
		drive.call(gs, hv, pose.call(hv, snow_i, 35.0, 0.2), 0.5)
		clear_snow = clear_snow and clear.call(gs)
	var ks := _kinds(gs)
	t.check(ks.y >= 10 and ks.x == 0 and gs.frost > 0.4 and gs.film == 0.0 and clear_snow,
		"snow at 126 km/h for 4 s: %d flecks of snow (melting into drops), frost %.2f, no mud, the middle kept clear" % [ks.y, gs.frost])
	gs.free()


## Splats of mud (x) and snow (y) on the screen.
static func _kinds(g: ScreenGrime) -> Vector2i:
	var k := Vector2i.ZERO
	for b: ScreenGrime.Blob in g.blobs():
		if b.kind == 0:
			k.x += 1
		elif b.kind == 1:
			k.y += 1
	return k


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
