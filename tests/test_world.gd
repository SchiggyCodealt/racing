extends RefCounted
## test_world.gd: headless checks of the 3D world (world/): noise and random ports,
## themes and quality levels, car models, chase camera, track meshes, fleet; the road
## surfaces (v6.3): dirt and snow roads, no paint on them, dusty / snowy barriers, dust and
## snow spray (pooled, scaled by quality), surface-coloured tyre marks; (v6.10) the barriers'
## grime shader, the AI opponent's dust, no camera rumble on loose ground but mud and snow on
## the screen (world/screen_grime.gd: builds, fades, quality, setting, the middle kept clear);
## the themes of v6.4: the arctic sky's northern lights, the autumn woods, the highland's snow
## beside snowy road (and the trees that know it); (v6.12.0) the cars' sound (audio/): every car's
## engine character, the pitch following the rpm (and the gear changes), the levels, the limiter,
## crackle, turbo and nitro, the script time, and a car's events (wall hits, landings, nitro, the
## turbo's blow-off) and ground loops from the sim's state.
## The pictures themselves are checked by eye with tests/visual/world_*.gd.

const VNoise = preload("res://world/noise.gd")
const Themes = preload("res://world/themes.gd")
const TrackMesh = preload("res://world/track_mesh.gd")
const TrackCtx = preload("res://world/track_ctx.gd")
const Shapes = preload("res://world/car_shapes.gd")
const Kit = preload("res://world/car_kit.gd")
const CarBuild = preload("res://world/car_build.gd")
const TrackScenery = preload("res://world/track_scenery.gd")


func run(t) -> bool:
	_noise(t)
	_themes(t)
	_cars(t)
	_camera(t)
	_tracks(t)
	_surfaces(t)
	# (the sound before the fleet and the threaded build: the audio thread lets go of a freed
	# player's playback a moment later, and quitting right after a free counts it as leaked)
	_engine_sound(t)
	_car_sound(t)
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
	_car_upgrades(t)


## v6.11.0: the upgrades' parts on the model (CarBuild.upgrades): one more skinned mesh with the car's
## material, more of it at higher levels, none on a stock car or a ghost; the mud flaps only on cars
## with wheel arches and without their own; the tyre rings spin with the wheels.
func _car_upgrades(t) -> void:
	var stock := CarModel.new("racer", {"levels": [0, 0, 0, 0]})
	var none := CarModel.new("racer")
	var ghost := CarModel.new("racer", {"ghost": true, "levels": [3, 3, 3, 3, 3]})
	t.check(stock.upgrade_mesh == null and none.upgrade_mesh == null and ghost.upgrade_mesh == null and stock.triangles() == none.triangles(),
		"a stock car and a ghost draw no upgrade parts")
	stock.free()
	ghost.free()
	var lines: PackedStringArray = []
	var ok := true
	var grow_max := 0.0
	for id: String in Cars.ids():
		var tri := {}
		for lv: Array in [[1, 0, 0, 0], [3, 0, 0, 0], [0, 1, 0, 0], [0, 3, 0, 0], [0, 0, 1, 0], [0, 0, 3, 0], [0, 0, 0, 3], [0, 0, 0, 0, 1], [0, 0, 0, 0, 3], [3, 3, 3, 3, 3],
				[10, 0, 0, 0], [0, 10, 0, 0], [0, 0, 10, 0], [0, 0, 0, 10], [0, 0, 0, 0, 10], [10, 10, 10, 10, 10]]:
			var kit = CarBuild.upgrades(id, PackedInt32Array(lv), 1)
			tri[",".join(lv.map(func(x: int) -> String: return str(x)))] = kit.triangles()
		var flaps: bool = tri["0,0,0,3"] > 0
		var want_flaps: bool = not (id in ["drifter", "dune", "apex", "quadra"])
		# (each part adds its own pieces: everything at 3 is the sum of the parts at 3)
		ok = ok and tri["1,0,0,0"] > 0 and tri["3,0,0,0"] >= tri["1,0,0,0"] and tri["0,1,0,0"] > 0 and tri["0,0,3,0"] > tri["0,0,1,0"] and flaps == want_flaps and \
			tri["3,3,3,3,3"] == tri["3,0,0,0"] + tri["0,3,0,0"] + tri["0,0,3,0"] + tri["0,0,0,3"] + tri["0,0,0,0,3"] and \
			tri["10,10,10,10,10"] == tri["10,0,0,0"] + tri["0,10,0,0"] + tri["0,0,10,0"] + tri["0,0,0,10"] + tri["0,0,0,0,10"] and tri["0,0,10,0"] > tri["0,0,3,0"] and tri["10,10,10,10,10"] < 6000 and \
			tri["0,0,0,0,1"] > 0 and tri["0,0,0,0,10"] == tri["0,0,0,0,1"] # (v6.21: the weight's wheel covers, the same pieces at every level, only bigger)
		# (v6.16: level 10 grows the parts only a little past level 3: the box round them at most 6 cm bigger each way)
		var b3: AABB = _kit_box(CarBuild.upgrades(id, PackedInt32Array([3, 3, 3, 3, 3]), 1))
		var b10: AABB = _kit_box(CarBuild.upgrades(id, PackedInt32Array([10, 10, 10, 10, 10]), 1))
		var d0: Vector3 = (b3.position - b10.position).abs()
		var d1: Vector3 = (b10.end - b3.end).abs()
		var grow: float = maxf(maxf(d0.x, maxf(d0.y, d0.z)), maxf(d1.x, maxf(d1.y, d1.z)))
		ok = ok and grow < 0.06
		grow_max = maxf(grow_max, grow)
		var car := CarModel.new(id, {"levels": [3, 3, 3, 3, 3]})
		t.tree.root.add_child(car)
		ok = ok and car.upgrade_mesh != null and car.upgrade_mesh.material_override == car.materials[0] and car.upgrade_mesh.skin == car.opaque_mesh.skin and \
			car.triangles() == int(CarModel.meshes(id, 1)["triangles"]) + tri["3,3,3,3,3"] and tri["3,3,3,3,3"] < 6000
		lines.append("%s %d%s" % [id, tri["3,3,3,3,3"], "" if flaps else " (no flaps)"])
		car.free()
	var low := CarModel.new("thunder", {"levels": [3, 3, 3, 3, 3], "detail": 0})
	ok = ok and low.upgrade_mesh != null and CarBuild.upgrades("thunder", PackedInt32Array([3, 3, 3, 3, 3]), 0).triangles() < CarBuild.upgrades("thunder", PackedInt32Array([3, 3, 3, 3, 3]), 1).triangles()
	low.free()
	none.free()
	t.check(ok, "the upgrades on the model (one skinned mesh with the car's material, triangles with everything at 3: %s): bigger exhaust tips, tyre rings, nitro bands (more at each level), mud flaps where the car has none and has wheel arches, carbon wheel covers for the weight part (v6.21); fewer on low detail; v6.16: everything at 10 is the sum of the parts at 10, at most %.1f cm bigger round than at 3" % [", ".join(lines), grow_max * 100.0])


static func _kit_box(kit: RefCounted) -> AABB:
	var pos: PackedVector3Array = kit.get("pos")
	var box := AABB(pos[0], Vector3.ZERO)
	for p: Vector3 in pos:
		box = box.expand(p)
	return box


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



# ---------------------------------------------------------------- sound (v6.12.0)

## Goertzel power of `s` (Hann window) at `f` Hz.
static func _gz(s: PackedFloat32Array, f: float, rate: float, a: int = 0, n: int = -1) -> float:
	if n < 0:
		n = s.size() - a
	var c := 2.0 * cos(TAU * f / rate)
	var s1 := 0.0
	var s2 := 0.0
	var k := TAU / (n - 1)
	for i in n:
		var s0 := s[a + i] * (0.5 - 0.5 * cos(k * i)) + c * s1 - s2
		s2 = s1
		s1 = s0
	return s1 * s1 + s2 * s2 - c * s1 * s2


## dB the firing frequency `f0` stands above 2.5 semitones either side.
static func _prominence(s: PackedFloat32Array, f0: float, rate: float, a: int = 0, n: int = -1) -> float:
	var p := _gz(s, f0, rate, a, n)
	var q := 0.5 * (_gz(s, f0 * pow(2.0, -2.5 / 12.0), rate, a, n) + _gz(s, f0 * pow(2.0, 2.5 / 12.0), rate, a, n))
	return 10.0 * log(maxf(p, 1e-30) / maxf(q, 1e-30)) / log(10.0)


## The strongest frequency within ±40 % of `f0` (quarter-semitone steps).
static func _peak_near(s: PackedFloat32Array, f0: float, rate: float, a: int = 0, n: int = -1) -> float:
	var best := -1.0
	var at := f0
	for k in range(-24, 25):
		var f := f0 * pow(2.0, k / 48.0)
		var p := _gz(s, f, rate, a, n)
		if p > best:
			best = p
			at = f
	return at


static func _rms_db(s: PackedFloat32Array, a: int = 0, n: int = -1) -> float:
	if n < 0:
		n = s.size() - a
	var e := 0.0
	for i in n:
		e += s[a + i] * s[a + i]
	return linear_to_db(maxf(1e-10, sqrt(e / maxf(1, n))))


## Render `seconds` of voice `v` at `rpm` and `load` (block by block, as the game feeds it).
static func _drive_voice(v: EngineVoice, at_rpm: float, ld: float, seconds: float, block: int = 400) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	v.rpm = at_rpm
	v.load = ld
	v.throttle = ld
	for i in int(seconds * v.mix_rate / block):
		out.append_array(v.render_mono(block))
	return out


func _engine_sound(t) -> void:
	t.section("sound: the engines (audio/engine_voice.gd, v6.12.0)")
	var keys := ["name", "cylinders", "intervals", "amps", "jitter", "pulse", "pipe", "body", "direct", "tone", "rough", "intake",
		"whine", "turbo", "turbo_hz", "rattle", "drive", "off", "crackle", "limiter_hz", "gain"]
	var bad := []
	for cid: String in Cars.ids():
		if not EngineVoice.ENGINES.has(cid):
			bad.append(cid)
			continue
		var e: Dictionary = EngineVoice.ENGINES[cid]
		for k: String in keys:
			if not e.has(k):
				bad.append("%s.%s" % [cid, k])
		if (e.intervals as Array).size() != int(e.cylinders) or (e.amps as Array).size() != int(e.cylinders) or (e.body as Array).size() != 3:
			bad.append(cid + ": slots")
	t.check(bad.is_empty() and EngineVoice.ENGINES.size() == Cars.ids().size(), "every car has an engine with every parameter %s" % [bad])
	var E := EngineVoice.ENGINES
	var turbos := []
	for cid: String in E:
		if float(E[cid].turbo) > 0.0:
			turbos.append(cid)
	var jit := 0.0
	var pipe_lo := 1e9
	for cid: String in E:
		jit = maxf(jit, float(E[cid].jitter))
		pipe_lo = minf(pipe_lo, float(E[cid].pipe[0]))
	var uneven := false
	for v: float in E.thunder.intervals:
		uneven = uneven or absf(v - 1.0) > 0.02
	t.check(int(E.racer.cylinders) == 6 and int(E.kestrel.cylinders) == 4 and int(E.thunder.cylinders) == 8 and int(E.drifter.cylinders) == 4
		and int(E.dune.cylinders) == 4 and int(E.vortex.cylinders) == 12 and turbos == ["drifter", "quadra"] and float(E.dune.rattle) > 0.2
		and is_equal_approx(float(E.dune.jitter), jit) and uneven and is_equal_approx(float(E.thunder.pipe[0]), pipe_lo)
		and float(E.vortex.pulse[1]) > float(E.kestrel.pulse[1]) and float(E.thunder.crackle) >= 0.5
		and int(E.apex.cylinders) == 10 and float(E.apex.pulse[1]) > float(E.vortex.pulse[1]) and float(Cars.spec("apex").redline) > 11000.0
		and int(E.quadra.cylinders) == 5 and (E.quadra.intervals as Array).size() == 5 and float(E.quadra.turbo) > float(E.drifter.turbo) and float(E.quadra.crackle) > float(E.thunder.crackle),
		"the characters: Racer a V6, Kestrel a four, Thunder a cross-plane V8 (uneven firing, the deepest pipe, big crackle), Drifter and Quadra the turbos, Dune the roughest (rattle, jitter), Vortex a V12, Apex a V10 revving past 11,000 (the brightest), Quadra a five (the loudest turbo, the most crackle)")
	t.check(EngineVoice.of("nope") == E.racer and is_equal_approx(EngineVoice.firing_hz(4, 6000.0), 200.0) and is_equal_approx(EngineVoice.firing_hz(8, 3000.0), 200.0),
		"firing frequency = rpm / 120 × cylinders (4 at 6000 rpm: 200 Hz); an unknown car sounds like the Racer")
	# pitch, level, gear change: each car at a third and two thirds of its redline, on load
	var rate := 24000.0
	var rows := PackedStringArray()
	var all_ok := true
	var levels := []
	var usec := 0
	var samples := 0
	for cid: String in Cars.ids():
		var v := EngineVoice.new(cid, rate)
		var red := Cars.spec(cid).redline
		var lo_rpm := red * 0.35
		var hi_rpm := red * 0.7
		var cyl := int(E[cid].cylinders)
		var t0 := Time.get_ticks_usec()
		var a := _drive_voice(v, lo_rpm, 1.0, 0.6)
		var b := _drive_voice(v, hi_rpm, 1.0, 0.6)
		usec += Time.get_ticks_usec() - t0
		samples += a.size() + b.size()
		var n := 8192
		var start := a.size() - n
		var pa := _prominence(a, EngineVoice.firing_hz(cyl, lo_rpm), rate, start, n)
		var pb := _prominence(b, EngineVoice.firing_hz(cyl, hi_rpm), rate, start, n)
		var fa := _peak_near(a, EngineVoice.firing_hz(cyl, lo_rpm), rate, start, n)
		var fb := _peak_near(b, EngineVoice.firing_hz(cyl, hi_rpm), rate, start, n)
		var lvl := _rms_db(b, start, n)
		var pk := 0.0
		for x in b:
			pk = maxf(pk, absf(x))
		levels.append(lvl)
		var ok := pa >= 6.0 and pb >= 6.0 and absf(fb / fa - 2.0) < 0.08 and lvl > -24.0 and lvl < -11.0 and pk < 1.0
		all_ok = all_ok and ok
		rows.append("%s %d / %d Hz (+%.0f / +%.0f dB, x%.2f) %.1f dBFS" % [cid, roundi(fa), roundi(fb), pa, pb, fb / fa, lvl])
	t.check(all_ok, "the pitch is the firing frequency of the rpm (a third / two thirds of the redline: twice as high), each car about as loud: " + ", ".join(rows))
	var spread: float = levels.max() - levels.min()
	t.check(spread < 6.0, "every car's engine within %.1f dB of the others at two thirds of the redline on load" % spread)
	var us := float(usec) / samples
	t.check(us < 6.0, "script time %.2f µs a sample: %.2f ms a 60 Hz frame for the player's engine (24 kHz)" % [us, us * 400.0 / 1000.0])
	# a gear change: the revs drop with the drive cut, then pick up from the lower rpm
	var g := EngineVoice.new("racer", rate)
	var red_r := Cars.spec("racer").redline
	var up := _drive_voice(g, red_r * 0.9, 1.0, 0.4)
	var shift := _drive_voice(g, red_r * 0.62, 0.0, 0.15)
	var on := _drive_voice(g, red_r * 0.64, 1.0, 0.4)
	var f_up := _peak_near(up, EngineVoice.firing_hz(6, red_r * 0.9), rate, up.size() - 4096, 4096)
	var f_on := _peak_near(on, EngineVoice.firing_hz(6, red_r * 0.64), rate, 0, 4096)
	t.check(absf(f_on / f_up - 0.64 / 0.9) < 0.05 and _rms_db(shift) < _rms_db(up) - 2.0,
		"a gear change: %d Hz on load, quieter off load in the shift, then %d Hz in the next gear (x%.2f, the rpm x%.2f)" % [roundi(f_up), roundi(f_on), f_on / f_up, 0.64 / 0.9])
	# the limiter, the crackle on a lift, the turbo, nitro
	var lm := EngineVoice.new("kestrel", rate)
	lm.limiter = true
	_drive_voice(lm, Cars.spec("kestrel").redline, 1.0, 0.5)
	var fired0 := lm.fired
	t.check(lm.cut > 0 and lm.fired > 0, "on the rev limiter the ignition cuts (%d cut, %d fired)" % [lm.cut, fired0])
	var th := EngineVoice.new("thunder", rate)
	_drive_voice(th, Cars.spec("thunder").redline * 0.85, 1.0, 0.5)
	var p0 := th.popped
	var lift := _drive_voice(th, Cars.spec("thunder").redline * 0.8, 0.0, 1.0)
	t.check(p0 == 0 and th.popped > 3, "Thunder: no pops on load, %d crackles on a lift from high revs" % th.popped)
	var dr := EngineVoice.new("drifter", rate)
	_drive_voice(dr, Cars.spec("drifter").redline * 0.8, 1.0, 1.5)
	var spool_on := dr.spool
	_drive_voice(dr, Cars.spec("drifter").redline * 0.7, 0.0, 0.5)
	t.check(spool_on > 0.6 and dr.spool < 0.2, "Drifter: the turbo spools up on load (%.2f) and falls on a lift (%.2f)" % [spool_on, dr.spool])
	var plain := EngineVoice.new("racer", rate)
	var nit := EngineVoice.new("racer", rate)
	nit.boost = 1.0
	var x0 := _drive_voice(plain, red_r * 0.7, 1.0, 0.5)
	var x1 := _drive_voice(nit, red_r * 0.7, 1.0, 0.5)
	var hi0 := 0.0
	var hi1 := 0.0
	for i in range(1, x0.size()):
		hi0 += (x0[i] - x0[i - 1]) * (x0[i] - x0[i - 1])
		hi1 += (x1[i] - x1[i - 1]) * (x1[i] - x1[i - 1])
	var louder := _rms_db(x1) - _rms_db(x0)
	var brighter := 10.0 * log(hi1 / maxf(hi0, 1e-20)) / log(10.0) - louder
	t.check(louder > 0.5 and brighter > 0.5, "nitro: %.1f dB louder and %.1f dB brighter (the highs against the level)" % [louder, brighter])
	var r1 := EngineVoice.new("dune", rate)
	var r2 := EngineVoice.new("dune", rate)
	t.check(_drive_voice(r1, 4000.0, 1.0, 0.2) == _drive_voice(r2, 4000.0, 1.0, 0.2), "the same car and inputs give the same sound (seeded)")
	t.check(not is_nan(lift[lift.size() - 1]) and _rms_db(lift) > -60.0, "off throttle the engine is still heard (engine braking, %.1f dBFS)" % _rms_db(lift))


func _car_sound(t) -> void:
	t.section("sound: a car's sounds from the sim (audio/car_audio.gd, v6.12.0)")
	var track := Tracks.build("rookie-oval")
	var car := Car.new(track, track.start_idx, Cars.spec("thunder"))
	var ca := CarAudio.new(null, "thunder")
	var ctrl := Car.Controls.new(0.0, 1.0, false, 0.0)
	var hit_step := -1
	var hit_event := -1
	var max_scrape := 0.0
	var max_wind := [0.0, 0.0]
	for i in 60 * 40:
		car.step(track, ctrl, 1.0 / 60.0)
		var before := int(ca.events.get("hit_light", 0)) + int(ca.events.get("hit_medium", 0)) + int(ca.events.get("hit_heavy", 0))
		ca.update(car, track, 1.0 / 60.0)
		var after := int(ca.events.get("hit_light", 0)) + int(ca.events.get("hit_medium", 0)) + int(ca.events.get("hit_heavy", 0))
		if hit_step < 0 and car.wall_hits > 0:
			hit_step = i
		if hit_event < 0 and after > before:
			hit_event = i
		max_scrape = maxf(max_scrape, float(ca.levels.get("scrape", 0.0)))
		if float(ca.levels.get("wind", 0.0)) > max_wind[0]:
			max_wind = [float(ca.levels.get("wind", 0.0)), car.speed]
		if hit_step >= 0 and i > hit_step + 60:
			break
	t.check(hit_step > 0 and hit_event == hit_step, "flat out into Rookie Oval's first corner: a wall hit sound in the step the car hits (step %d, %s)" % [hit_step, ca.events])
	t.check(int(ca.events.get("hit_heavy", 0)) + int(ca.events.get("hit_medium", 0)) > 0, "at speed it is a medium or heavy hit")
	t.check(max_wind[0] > 0.2 and max_wind[1] > 40.0, "wind with speed (up to %.2f at %.0f m/s); the scrape along the wall up to %.2f" % [max_wind[0], max_wind[1], max_scrape])
	# the hit sizes by the speed into the wall
	var sizes := {}
	for sp: float in [3.0, 8.0, 20.0]:
		var c2 := Car.new(track, track.start_idx, Cars.spec("racer"))
		var a2 := CarAudio.new(null, "racer")
		a2.update(c2, track, 1.0 / 60.0)
		c2.wall_hits += 1
		c2.hit_wall = true
		c2.wall_impact = sp
		a2.update(c2, track, 1.0 / 60.0)
		sizes[sp] = a2.events.keys()
		a2.free()
	t.check(sizes[3.0] == ["hit_light"] and sizes[8.0] == ["hit_medium"] and sizes[20.0] == ["hit_heavy"], "hits by the speed into the wall: 3 m/s light, 8 medium, 20 heavy %s" % [sizes])
	var c3 := Car.new(track, track.start_idx, Cars.spec("racer"))
	var a3 := CarAudio.new(null, "racer")
	a3.update(c3, track, 1.0 / 60.0)
	c3.wall_hits += 1
	c3.wall_impact = 0.5
	a3.update(c3, track, 1.0 / 60.0)
	t.check(a3.events.is_empty(), "a touch below %.1f m/s makes no hit sound" % CarAudio.HIT_MIN)
	# a landing: in the air falling at 7 m/s, then down
	c3.grounded = false
	c3.vy = -7.0
	for i in 20:
		a3.update(c3, track, 1.0 / 60.0)
	c3.grounded = true
	a3.update(c3, track, 1.0 / 60.0)
	var landed := int(a3.events.get("land", 0))
	c3.grounded = false
	c3.vy = -1.0
	a3.update(c3, track, 1.0 / 60.0)
	c3.grounded = true
	a3.update(c3, track, 1.0 / 60.0)
	t.check(landed == 1 and int(a3.events.get("land", 0)) == 1, "a landing at 7 m/s thumps, a hop at 1 m/s does not")
	c3.boosting = true
	a3.update(c3, track, 1.0 / 60.0)
	a3.update(c3, track, 1.0 / 60.0)
	t.check(int(a3.events.get("nitro_on", 0)) == 1, "the nitro lighting is heard once")
	# a respawn jump (far away in one frame) makes no hit or landing
	c3.x += 100.0
	c3.wall_hits += 3
	c3.wall_impact = 20.0
	a3.update(c3, track, 1.0 / 60.0)
	t.check(not a3.events.has("hit_heavy"), "a respawn (a jump of 100 m) starts over: no hit from it")
	# the ground under the car
	var ramp := Tracks.build("ramp-rally")
	var hair := Tracks.build("hairpin-valley")
	var dirt := 0
	var snow := 0
	for i in ramp.count:
		if CarAudio.loose_at(ramp, i).x > 0.95:
			dirt += 1
	for i in hair.count:
		if CarAudio.loose_at(hair, i).y > 0.95:
			snow += 1
	var none := true
	for i in range(0, track.count, 7):
		none = none and CarAudio.loose_at(track, i) == Vector2.ZERO
	t.check(dirt > ramp.count / 4 and snow > hair.count / 8 and none and CarAudio.loose_at(null, 3) == Vector2.ZERO,
		"the ground: Ramp Rally's dirt (%d of %d samples), Hairpin Valley's snow (%d of %d), Rookie Oval none" % [dirt, ramp.count, snow, hair.count])
	# gravel on the dirt at speed: its loop level, none on asphalt
	var c4 := Car.new(ramp, ramp.start_idx, Cars.spec("dune"))
	var a4 := CarAudio.new(null, "dune")
	var di := -1
	for i in ramp.count:
		if CarAudio.loose_at(ramp, i).x > 0.99:
			di = i
			break
	c4.idx = di
	c4.speed = 30.0
	c4.slip = 0.2
	for i in 30:
		a4.update(c4, ramp, 1.0 / 60.0)
	var g_dirt := float(a4.levels.get("gravel", 0.0))
	c4.idx = ramp.start_idx
	for i in 120:
		a4.update(c4, ramp, 1.0 / 60.0)
	t.check(g_dirt > 0.3 and float(a4.levels.get("gravel", 0.0)) < 0.01 and float(a4.levels.get("road", 0.0)) > 0.1,
		"the Dune at 30 m/s: gravel %.2f on the dirt, %.3f on asphalt (road roar %.2f there)" % [g_dirt, float(a4.levels.get("gravel", 0.0)), float(a4.levels.get("road", 0.0))])
	c4.slip = 0.8
	for i in 30:
		a4.update(c4, ramp, 1.0 / 60.0)
	t.check(float(a4.levels.get("tyre_squeal", 0.0)) > 0.3, "sliding on asphalt: the tyres squeal (%.2f)" % float(a4.levels.get("tyre_squeal", 0.0)))
	# in the tree (headless: the dummy audio driver): the engine is fed, the turbo blows off on a lift
	GameAudio.setup_buses()
	var holder := Node3D.new()
	t.tree.root.add_child(holder)
	var c5 := Car.new(track, track.start_idx, Cars.spec("drifter"))
	var a5 := CarAudio.new(null, "drifter")
	holder.add_child(a5)
	c5.gear = 3
	c5.rpm = Cars.spec("drifter").redline * 0.85
	c5.throttle = 1.0
	# (the game's audio thread asks for the engine as it plays; here each frame renders its 1/60 s)
	for i in 90:
		a5.update(c5, track, 1.0 / 60.0)
		a5.engine.render_mono(400)
	var sp_on := a5.engine.spool
	c5.throttle = 0.0
	for i in 10:
		a5.update(c5, track, 1.0 / 60.0)
		a5.engine.render_mono(400)
	var player: AudioStreamPlayer = a5.get("_engine_player")
	t.check(player != null and player.playing and player.bus == "Engine" and a5.updates == 100, "in the tree the engine plays on the Engine bus (headless: the dummy driver)")
	var ahead := a5.queued()
	t.check(ahead > 0.0 and ahead <= CarAudio.LEAD_MIN + 0.005,
		"at 60 frames a second the engine is rendered %.0f ms ahead of what has played (the generator's ring is bigger than its buffer_length: counted from the empty ring)" % (ahead * 1000.0))
	t.check(sp_on > 0.5 and int(a5.events.get("blowoff", 0)) == 1, "the Drifter's turbo (spool %.2f) blows off once on the lift" % sp_on)
	var per := float(a5.usec) / a5.updates
	t.check(per < 2000.0, "a car's sound costs %.2f ms of script time a frame (engine, events, loops)" % (per / 1000.0))
	holder.free()
	var pos := CarAudio.new(null, "vortex", {"positional": true})
	t.check(pos.positional and is_equal_approx(pos.level, 0.6) and is_equal_approx(pos.engine.mix_rate, CarAudio.ENGINE_RATE_3D),
		"another car's sound: positional, quieter (0.6), a lighter engine voice (%d Hz)" % int(CarAudio.ENGINE_RATE_3D))
	pos.free()
	ca.free()
	a3.free()
	a4.free()
