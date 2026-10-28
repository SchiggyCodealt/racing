class_name CarModel
extends Node3D
## car_model.gd
## ------------------------------------------------------------------
## A detailed procedural car: the player's car, a watched AI car or a
## see-through ghost, in the shape of one of the six cars. The whole car is
## one skinned mesh (world/car_build.gd, world/car_kit.gd) drawn with one
## material (world/shaders/car.gdshader), plus its tinted glass; a
## Skeleton3D moves the parts every frame:
##   - wheels: tyre, spoked rim and brake disc spin; the hub and caliper steer
##     (front) and travel; the suspension arms stretch between body and wheel
##   - body: squats under power, dives under braking, rolls out of corners and
##     sinks and rebounds on landings, while the wheels stay on the road; the
##     wheels droop in the air; the Vortex's wing tilts up as an air brake
##   - driver: the steering wheel turns with the front wheels and the arms
##     follow it (two-bone IK), the head looks into corners and leans with the
##     lateral g, the body rocks under braking and acceleration and bumps on
##     landings, and a fist pump at the finish (celebrate())
##   - lights: tail lights glow brighter when braking; on themes with
##     "headlights" (night, dusk) the lamps burn brighter and light the road
##     (two spot lights on high, one on medium, a light pool decal on low)
## plus a soft contact shadow, tyre smoke, skid marks, wall sparks and nitro
## flames (world/car_effects.gd). Under a World on low quality the car uses
## its lighter mesh and no panel lines.
##
## Use:
##   var car := CarModel.new("thunder")                    # body colour from the car's look
##   var ghost := CarModel.new("racer", {ghost = true, color = Color("#8fd6ff")})
##   add_child(car)
##   # every frame: the car's state after the last physics step, the state before it,
##   # how far the frame is between them (0..1) and the frame time
##   car.update(state, prev_state, alpha, delta)
##   car.celebrate()          # the fist pump (at the finish)
##   car.reset_effects()      # after a restart / respawn (ends a celebration too)
##   ghost.set_fade(f)        # 0..1 (CarModel.ghost_fade() gives the web game's fade)
##   CarModel.profile("kestrel")  # side view polygons for the car picker
##
## A state is the sim's car object or a Dictionary with its fields (x, y, z,
## yaw, pitch, roll, steer_angle, wheel_rot, vx, vz, speed, forward_speed,
## side_speed, grounded, slip, drifting, braking, throttle, steer, boost,
## boosting, hit_wall, wall_hits, wall_impact, wall_scrape, wall_x, wall_z,
## wall_nx, wall_nz); missing fields fall back as in the web game.
## Car frame: x = left, y = up, z = forward; the origin is on the road
## between the axles. A ghost makes no smoke, skid marks or sparks and has no
## lights or glass; it shows the nitro jets. The car's meshes are on visual
## layer CAR_LAYER (the contact shadow and the headlights skip them).

const Shapes = preload("res://world/car_shapes.gd")
const CarBuild = preload("res://world/car_build.gd")
const Kit = preload("res://world/car_kit.gd")
const Themes = preload("res://world/themes.gd")
const CAR_SHADER = preload("res://world/shaders/car.gdshader")
const GLASS_SHADER = preload("res://world/shaders/car_glass.gdshader")

const CAR_LAYER := 2
## Steering wheel turns per radian of front wheel angle.
const WHEEL_TURN := 3.2
## Lamp glow (shader emission): headlights by day and on headlight themes; tail lights and brake lights.
const HEAD_DAY := 2.2
const HEAD_NIGHT := 4.5
const TAIL_ON := 0.75
const TAIL_BRAKE := 3.4
## How long the fist pump lasts (s).
const CELEBRATION := 3.6

var car_id := "racer"
var ghost := false
## 1: the full mesh, 0: the lighter one (low quality).
var detail := 1
var skeleton: Skeleton3D
var opaque_mesh: MeshInstance3D
var glass_mesh: MeshInstance3D = null
## The car's opaque material (a ShaderMaterial; a StandardMaterial3D for a ghost) and the glass's.
var materials: Array[Material] = []
var rig: Dictionary
var wheels: Array = [] # {c: Vector3 centre at rest, r, front}
var smoke: CarEffects.TyreSmoke = null
var skids: CarEffects.SkidMarks = null
var sparks: CarEffects.Sparks = null
var flame: CarEffects.NitroFlame
var wall := CarEffects.WallState.new()
## The pose drawn last frame (interpolated); the camera can use it.
var pose := CarEffects.Pose.new()
## Seconds since celebrate() (-1: not celebrating).
var celebration := -1.0
## The headlight nodes in use (SpotLight3D or a Decal), [] by day.
var headlights: Array[Node3D] = []

var _mat: ShaderMaterial = null
var _ghost_mat: StandardMaterial3D = null
var _world: World = null
var _theme_name := ""
var _night := 0.0
var _quality := "high"
var _forced_detail := -1
var _att := Vector2.ZERO  # pitch, roll of the wheels' frame
var _rel := Vector2.ZERO  # body pitch, roll against the wheels (squat, dive, roll)
var _rel_v := Vector2.ZERO
var _ax := 0.0            # smoothed longitudinal and lateral acceleration (m/s²)
var _ay := 0.0
var _yaw_rate := 0.0
var _last_fs := 0.0
var _last_yaw := 0.0
var _last_y := 0.0
var _vy := 0.0
var _air_vy := 0.0
var _was_grounded := true
var _heave := 0.0
var _heave_v := 0.0
var _bob := 0.0
var _bob_v := 0.0
var _droop := 0.0
var _flap := 0.0
var _spin_angle := 0.0
var _steer_vis := 0.0
var _brake_glow := TAIL_ON
var _head_glow := HEAD_DAY
var _set_glow := Vector2(-1, -1)
var _smoke_acc := 0.0
var _first := true
var _fade := 1.0
var _fist_side := 0
var _rest_upper: Array[Basis] = []  # inverse rest frames of the arm segments
var _rest_fore: Array[Basis] = []
var _paint := Color()

static var _mesh_cache: Dictionary = {}
static var _skin: Skin = null


## car_id: one of Cars.ids() (unknown: racer).
## opts: ghost (bool), color (Color or "#rrggbb": body colour, or the ghost's colour),
## detail (0 or 1: a fixed mesh whatever the quality).
func _init(p_car_id := "racer", opts := {}) -> void:
	car_id = p_car_id if Shapes.shapes().has(p_car_id) else "racer"
	ghost = opts.get("ghost", false)
	_forced_detail = int(opts.get("detail", -1))
	detail = _forced_detail if _forced_detail >= 0 else 1
	var look: Dictionary = Cars.get_car(car_id).get("look", {})
	_paint = Color(opts["color"]) if opts.has("color") else Color(str(look.get("color", "#d7263d")))
	name = "GhostCar" if ghost else "Car"
	var shape := Shapes.shape_of(car_id)
	rig = CarBuild.rig(car_id)
	for w: Dictionary in rig["wheels"]:
		wheels.append({"c": w["c"], "r": w["r"], "front": w["front"]})
	_fist_side = 0 if float(rig["hip"].x) >= 0.0 else 1
	for side in 2:
		var sh: Vector3 = rig["shoulders"][side]
		var el: Vector3 = rig["elbows"][side]
		var hd: Vector3 = rig["hands"][side]
		_rest_upper.append(_seg_basis(el - sh, (el - sh).cross(hd - sh), rig["poles"][side]).inverse())
		_rest_fore.append(_seg_basis(hd - el, (el - sh).cross(hd - sh), rig["poles"][side]).inverse())

	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton"
	for b: String in Kit.BONE_NAMES:
		skeleton.add_bone(b)
	add_child(skeleton)
	opaque_mesh = MeshInstance3D.new()
	opaque_mesh.name = "Body"
	_setup_mesh(opaque_mesh)
	skeleton.add_child(opaque_mesh)

	if ghost:
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(_paint, 0.4)
		gm.emission_enabled = true
		gm.emission = _paint
		gm.emission_energy_multiplier = 0.45
		gm.roughness = 0.35
		gm.metallic = 0.1
		# the depth pre-pass draws only the front-most surface: no X-ray wheels through the body
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		_ghost_mat = gm
		materials.append(gm)
		opaque_mesh.material_override = gm
		opaque_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		var accent := Color(str(look.get("accent", "#1b1b1e")))
		# stripe: the accent colour, or (the racer) white on dark paint, near-black on light paint
		var lin := _paint.srgb_to_linear()
		var lum := (maxf(lin.r, maxf(lin.g, lin.b)) + minf(lin.r, minf(lin.g, lin.b))) / 2.0
		var stripe: Color = accent if shape["stripeAccent"] else Themes.col(0x1b1d22 if lum > 0.62 else 0xf4f4f2)
		_mat = ShaderMaterial.new()
		_mat.shader = CAR_SHADER
		_mat.set_shader_parameter("paint", _paint)
		_mat.set_shader_parameter("accent", accent)
		_mat.set_shader_parameter("stripe", stripe)
		var sa := PackedVector4Array()
		var sb := PackedVector4Array()
		for m: Array in rig["seams"]:
			if sa.size() >= 12:
				break
			sa.append(Vector4(m[0], m[1], m[2], m[3]))
			sb.append(Vector4(m[4], m[5], 1.0, 0.0))
		_mat.set_shader_parameter("seam_count", sa.size())
		sa.resize(12)
		sb.resize(12)
		_mat.set_shader_parameter("seam_a", sa)
		_mat.set_shader_parameter("seam_b", sb)
		materials.append(_mat)
		opaque_mesh.material_override = _mat
		opaque_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var gmat := ShaderMaterial.new()
		gmat.shader = GLASS_SHADER
		materials.append(gmat)
		glass_mesh = MeshInstance3D.new()
		glass_mesh.name = "Glass"
		_setup_mesh(glass_mesh)
		glass_mesh.material_override = gmat
		glass_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		skeleton.add_child(glass_mesh)
	_apply_detail()

	if not ghost:
		# soft contact shadow under the car, projected on whatever is below (curbs, banking)
		var blob := Decal.new()
		blob.name = "ContactShadow"
		blob.texture_albedo = _blob_texture()
		blob.size = Vector3(2.6 * shape["width"] * (shape["track"] if not shape["fenders"] else 1.0), 2.0, 5.4 * (shape["front"] + shape["rear"]) / 2.0)
		blob.position = Vector3(0, 0.5, 0)
		blob.cull_mask = 0xFFFFF & ~CAR_LAYER
		blob.upper_fade = 0.2
		blob.lower_fade = 0.3
		blob.distance_fade_enabled = true
		blob.distance_fade_begin = 120.0
		blob.distance_fade_length = 40.0
		add_child(blob)
		smoke = CarEffects.TyreSmoke.new(64)
		skids = CarEffects.SkidMarks.new(240)
		sparks = CarEffects.Sparks.new(160)
		for n in [smoke.node, skids.node, sparks.node]:
			add_child(n)

	flame = CarEffects.NitroFlame.new(rig["nozzles"], not ghost)
	add_child(flame.jets)
	if flame.glow != null:
		add_child(flame.glow)
	_pose_bones()


func _setup_mesh(mi: MeshInstance3D) -> void:
	mi.layers = CAR_LAYER
	mi.skeleton = NodePath("..")
	mi.skin = _shared_skin()


## Every bone's bind is the identity: a bone's pose is the transform of the car-frame vertices it carries.
static func _shared_skin() -> Skin:
	if _skin == null:
		_skin = Skin.new()
		for i in Kit.BONE_COUNT:
			_skin.add_bind(i, Transform3D.IDENTITY)
	return _skin


## The meshes of car `id` at `d`, built once and shared by every model of that car.
static func meshes(id: String, d: int) -> Dictionary:
	var key := "%s:%d" % [id, d]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var car := CarBuild.build(id, d)
	var opaque: ArrayMesh = car["opaque"].to_mesh(true)
	var glass: ArrayMesh = car["glass"].to_mesh(true)
	# the bones move parts a little (steering, suspension, a raised fist): a roomier box for culling
	var box := opaque.get_aabb().grow(0.12)
	box = box.merge(AABB(box.position, Vector3(box.size.x, box.size.y + 0.45, box.size.z)))
	var out := {"opaque": opaque, "glass": glass, "aabb": box, "triangles": car["opaque"].triangles() + car["glass"].triangles()}
	_mesh_cache[key] = out
	return out


func _apply_detail() -> void:
	var m := meshes(car_id, detail)
	opaque_mesh.mesh = m["opaque"]
	opaque_mesh.custom_aabb = m["aabb"]
	if glass_mesh != null:
		glass_mesh.mesh = m["glass"]
		glass_mesh.custom_aabb = m["aabb"]
		glass_mesh.visible = (m["glass"] as ArrayMesh).get_surface_count() > 0
	if _mat != null:
		_mat.set_shader_parameter("seam_strength", 1.0 if detail > 0 else 0.0)


## Triangles drawn per pass (opaque + glass).
func triangles() -> int:
	return int(meshes(car_id, detail)["triangles"])


static var _blob_tex: ImageTexture = null


static func _blob_texture() -> ImageTexture:
	if _blob_tex != null:
		return _blob_tex
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var r := Vector2(x - 31.5, y - 31.5).length() / 32.0
			var a := 0.0
			if r < 0.6:
				a = lerpf(0.75, 0.35, r / 0.6)
			elif r < 1.0:
				a = lerpf(0.35, 0.0, (r - 0.6) / 0.4)
			img.set_pixel(x, y, Color(0, 0, 0, a))
	img.generate_mipmaps()
	_blob_tex = ImageTexture.create_from_image(img)
	return _blob_tex


static var _pool_tex: ImageTexture = null


## The low-quality headlight pool: a soft warm wedge, bright near the car (bottom of the image).
static func _pool_texture() -> ImageTexture:
	if _pool_tex != null:
		return _pool_tex
	var img := Image.create(64, 128, false, Image.FORMAT_RGBA8)
	for y in 128:
		var along := y / 127.0 # 0 at the car end, 1 far ahead (a decal maps the image top to -z)
		for x in 64:
			var half := lerpf(0.18, 1.0, sqrt(along))
			var across := absf(x - 31.5) / 32.0 / half
			var a := (1.0 - smoothstep(0.35, 1.0, across)) * smoothstep(0.0, 0.08, along) * (1.0 - smoothstep(0.35, 1.0, along)) * (1.0 - 0.5 * along)
			# emission ignores the alpha: the fade is in the colour (black outside the beam)
			img.set_pixel(x, y, Color(a, a * 0.9, a * 0.72, 1.0))
	img.generate_mipmaps()
	_pool_tex = ImageTexture.create_from_image(img)
	return _pool_tex


# ---- the world: theme and quality ------------------------------------------------

func _enter_tree() -> void:
	var p := get_parent()
	while p != null and not (p is World):
		p = p.get_parent()
	var n := p as World
	if n != _world:
		if _world != null and _world.quality_changed.is_connected(_on_quality):
			_world.quality_changed.disconnect(_on_quality)
		_world = n
		if _world != null:
			_world.quality_changed.connect(_on_quality)
	_sync_world(true)


func _exit_tree() -> void:
	if _world != null and _world.quality_changed.is_connected(_on_quality):
		_world.quality_changed.disconnect(_on_quality)
	_world = null


func _on_quality(_level: String) -> void:
	_sync_world(true)


## Follow the World's theme (headlights) and quality (mesh detail, headlight kind).
func _sync_world(force := false) -> void:
	var tn: String = _world.theme_name if _world != null else ""
	var q: String = _world.quality if _world != null else "high"
	if not force and tn == _theme_name and q == _quality:
		return
	_theme_name = tn
	_quality = q
	_night = float(Themes.get_theme(tn).get("headlights", 0.0)) if tn != "" else 0.0
	var d := _forced_detail if _forced_detail >= 0 else (0 if q == "low" else 1)
	if d != detail:
		detail = d
		_apply_detail()
	_build_headlights()


func _build_headlights() -> void:
	for n in headlights:
		n.queue_free()
	headlights.clear()
	if ghost or _night <= 0.0:
		return
	var lamps: Array = _lamp_points()
	if _quality == "low":
		# no light: a glowing pool on the road ahead (one decal)
		var d := Decal.new()
		d.name = "HeadlightPool"
		d.texture_emission = _pool_texture()
		d.emission_energy = 0.3 * _night
		d.modulate = Color(1.0, 0.92, 0.78)
		d.size = Vector3(11.0, 3.0, 36.0)
		d.position = Vector3(0, 0.6, 19.5)
		d.cull_mask = 0xFFFFF & ~CAR_LAYER
		add_child(d)
		headlights.append(d)
		return
	var pts: Array = lamps if _quality == "high" else [(lamps[0] + lamps[1]) * 0.5]
	for p: Vector3 in pts:
		var l := SpotLight3D.new()
		l.name = "Headlight"
		l.position = p
		# aim ahead and a little down: the beam reaches the road ~12 m out
		l.rotation = Vector3(0, PI, 0) # a light shines down its -z: turn it to face +z
		l.rotate_object_local(Vector3.RIGHT, -0.035)
		l.light_color = Color(1.0, 0.93, 0.8)
		l.light_energy = (12.0 if pts.size() == 2 else 20.0) * _night
		l.spot_range = 80.0
		l.spot_angle = 22.0
		l.spot_angle_attenuation = 1.2
		l.spot_attenuation = 0.5
		l.shadow_enabled = false
		l.light_cull_mask = 0xFFFFF & ~CAR_LAYER
		l.light_specular = 0.3
		add_child(l)
		headlights.append(l)


## Where the headlights shine from (car frame): the outermost lamps at the nose.
func _lamp_points() -> Array:
	var s := Shapes.shape_of(car_id)
	var x := 0.79
	var y := 0.49
	var z := 2.31
	if s["lights"] == "strip":
		x = 0.66
		y = 0.47
	elif s["lights"] == "buggy":
		x = 0.3
		y = 0.42
		z = 2.4
	var a := Shapes.warp_point(s, x, y, z)
	return [a + Vector3(0, 0, 0.12), Vector3(-a.x, a.y, a.z + 0.12)]


# ---- per frame ----------------------------------------------------------------

## Draw the car between the previous physics step (prev_state, may be null) and the
## last one (state): alpha 0..1 is how far the frame is between them; dt the frame time.
## `track` (BuiltTrack, optional) is only used when the state has no pitch / roll.
func update(state: Variant, prev_state: Variant = null, alpha := 1.0, dt := 1.0 / 60.0, track: BuiltTrack = null) -> void:
	dt = clampf(dt, 1e-4, 0.1)
	if _world != null:
		_sync_world()
	var car := pose.read(state, prev_state, alpha)
	# a jump of several metres means restart / respawn: snap, start new skid strips
	if not _first and (car.x - position.x) * (car.x - position.x) + (car.z - position.z) * (car.z - position.z) > 64.0:
		_first = true
		if skids != null:
			skids.lift(0)
			skids.lift(1)
	_dynamics(car, dt)

	# attitude: pitch / roll from the state when present (less the body's own squat and roll,
	# which the body bone shows), else follow the road (v1)
	var tilt := _att
	if car.has_att:
		tilt = Vector2(car.pitch, car.roll) - _rel
	elif car.grounded and track != null and car.idx >= 0:
		tilt = _road_tilt(car, track)
	var k := 1.0 if _first else 1.0 - exp(-dt * (30.0 if car.has_att else 14.0 if car.grounded else 2.0))
	_att += (tilt - _att) * k
	position = Vector3(car.x, car.y, car.z)
	rotation = Vector3(-_att.x, car.yaw, _att.y)

	# wheels
	var steer := car.steer_angle if car.has_steer_angle else car.steer * 0.42
	_steer_vis += (steer - _steer_vis) * (1.0 if _first else 1.0 - exp(-dt * 20.0))
	if car.has_wheel_rot:
		_spin_angle = car.wheel_rot
	else:
		_spin_angle = fmod(_spin_angle + car.forward_speed / 0.39 * dt, TAU)

	# lights
	var braking := car.braking if car.has_braking else (car.throttle < -0.05 and car.forward_speed > 0.5)
	_brake_glow += ((TAIL_BRAKE if braking else TAIL_ON) - _brake_glow) * (1.0 if _first else 1.0 - exp(-dt * 25.0))
	_head_glow = lerpf(HEAD_DAY, HEAD_NIGHT, clampf(_night, 0.0, 1.0))
	if _mat != null and (absf(_brake_glow - _set_glow.x) > 0.01 or absf(_head_glow - _set_glow.y) > 0.01):
		_set_glow = Vector2(_brake_glow, _head_glow)
		_mat.set_shader_parameter("tail_glow", _brake_glow)
		_mat.set_shader_parameter("head_glow", _head_glow)

	# the active wing tilts up as an air brake when braking hard at speed
	var flap_to := 0.62 if braking and car.forward_speed > 20.0 else 0.0
	_flap += (flap_to - _flap) * (1.0 if _first else 1.0 - exp(-dt * 7.0))
	if celebration >= 0.0:
		celebration += dt
		if celebration > CELEBRATION:
			celebration = -1.0
	_pose_bones()

	var xf := global_transform if is_inside_tree() else transform

	# tyre smoke and skid marks from the rear wheels
	if smoke != null:
		var slip := car.slip if car.has_slip else (0.75 if car.drifting else clampf((absf(car.side_speed) - 4.0) / 6.0, 0.0, 1.0))
		var sliding := car.grounded and slip > 0.3 and car.speed > 4.0
		var sx := cos(car.yaw)
		var sz := -sin(car.yaw) # left vector
		for wi in 2:
			var c: Vector3 = wheels[2 + wi]["c"]
			var p: Vector3 = xf * Vector3(c.x, 0.03, c.z)
			if sliding:
				skids.add(wi, p, sx, sz, minf(0.75, 0.25 + slip * 0.6))
				_smoke_acc += dt * 18.0 * slip
				while _smoke_acc >= 1.0:
					_smoke_acc -= 1.0
					smoke.emit(p.x, p.y, p.z, car.vx, car.vz, slip)
			else:
				skids.lift(wi)
		smoke.update(dt)

	# sparks where the car hits or scrapes a wall (ghosts have none)
	if sparks != null:
		if _first:
			wall.ready = false
		var steps := CarEffects.wall_events(wall, car)
		if steps > 0:
			CarEffects.emit_sparks(sparks, wall, steps, car, car.x, car.y, car.z, car.yaw, sparks.max)
		sparks.update(dt)

	# nitro flames while boosting (a ghost shows them too)
	flame.update(car, dt, xf)
	_first = false


## What the body and the driver feel: smoothed accelerations, landings, the springs.
func _dynamics(car: CarEffects.Pose, dt: float) -> void:
	if _first:
		_ax = 0.0
		_ay = 0.0
		_yaw_rate = 0.0
		_rel = Vector2.ZERO
		_rel_v = Vector2.ZERO
		_heave = 0.0
		_heave_v = 0.0
		_bob = 0.0
		_bob_v = 0.0
		_vy = 0.0
		_droop = 0.0 if car.grounded else 1.0
		_was_grounded = car.grounded
	else:
		var f := 1.0 - exp(-dt * 8.0)
		_yaw_rate += (angle_difference(_last_yaw, car.yaw) / dt - _yaw_rate) * f
		_ax += (clampf((car.forward_speed - _last_fs) / dt, -25.0, 25.0) - _ax) * f
		_ay += (clampf(car.forward_speed * _yaw_rate, -25.0, 25.0) - _ay) * f
		_vy += ((car.y - _last_y) / dt - _vy) * (1.0 - exp(-dt * 20.0))
	_last_fs = car.forward_speed
	_last_yaw = car.yaw
	_last_y = car.y
	if not car.grounded:
		_air_vy = _vy
	elif not _was_grounded:
		# landing: the body sinks onto the suspension and the driver into the seat
		var impact := clampf(-_air_vy, 0.0, 30.0)
		_heave_v -= minf(1.2, 0.1 * impact)
		_bob_v -= minf(0.9, 0.05 * impact)
	_was_grounded = car.grounded
	# squat / dive and roll against the wheels (the sim's own attitude coefficients)
	var target := Vector2(0.0032 * _ax, 0.0035 * _ay) if car.grounded else Vector2.ZERO
	target = target.clamp(Vector2(-0.07, -0.08), Vector2(0.07, 0.08))
	var n := int(ceil(dt / 0.02))
	var h := dt / n
	for _i in n:
		_rel_v += ((target - _rel) * 140.0 - _rel_v * 16.0) * h
		_rel += _rel_v * h
		_heave_v += (-_heave * 220.0 - _heave_v * 9.0) * h
		_heave = clampf(_heave + _heave_v * h, -0.11, 0.06)
		_bob_v += (-_bob * 90.0 - _bob_v * 6.0) * h
		_bob = clampf(_bob + _bob_v * h, -0.07, 0.05)
	_droop += ((0.0 if car.grounded else 1.0) - _droop) * (1.0 - exp(-dt * (25.0 if car.grounded else 6.0)))


## Start the fist pump (the finish).
func celebrate() -> void:
	celebration = 0.0


## A transform rotating by `b` about point `p`.
static func _about(b: Basis, p: Vector3) -> Transform3D:
	return Transform3D(b, p - b * p)


## An orthonormal frame with x along `d` and z along the arm's bend normal `n` (`pole` x d when n is ~0).
static func _seg_basis(d: Vector3, n: Vector3, pole: Vector3) -> Basis:
	var x := d.normalized()
	var z := n - x * n.dot(x)
	if z.length_squared() < 1e-8:
		z = x.cross(pole)
	z = z.normalized()
	return Basis(x, z.cross(x), z)


## Every bone for the current state.
func _pose_bones() -> void:
	var wheels_r: Array = rig["wheels"]
	# body: rel pitch / roll about a point between the axles at hub height, heave
	var pivot := Vector3(0, (float(wheels_r[0]["r"]) + float(wheels_r[2]["r"])) * 0.5, 0)
	var body := _about(Basis.from_euler(Vector3(-_rel.x, 0.0, _rel.y)), pivot)
	body.origin.y += _heave
	skeleton.set_bone_pose(Kit.BODY, body)
	# wheels: travel (droop in the air), steer (front), spin
	var spin := Basis(Vector3.RIGHT, _spin_angle)
	for i in 4:
		var w: Dictionary = wheels_r[i]
		var c: Vector3 = w["c"]
		var up := Transform3D(Basis.IDENTITY, Vector3(0, -0.07 * _droop, 0))
		if w["front"]:
			up = up * _about(Basis(Vector3.UP, _steer_vis), c)
		skeleton.set_bone_pose(Kit.UPRIGHT0 + i, up)
		skeleton.set_bone_pose(Kit.SPIN0 + i, up * _about(spin, c))
	# the steering wheel
	var wc: Vector3 = rig["wheel_c"]
	var wb: Basis = rig["wheel_basis"]
	var turn := clampf(-_steer_vis * WHEEL_TURN, -1.9, 1.9)
	var steering := body * _about(Basis(wb.z, turn), wc)
	skeleton.set_bone_pose(Kit.STEERING, steering)
	# the active wing (the cars without one keep the bone on the body)
	var flap: Vector3 = rig["flap"]
	skeleton.set_bone_pose(Kit.FLAP, body * _about(Basis(Vector3.RIGHT, _flap), flap) if flap != Vector3.ZERO else body)
	_pose_driver(body, steering)


func _pose_driver(body: Transform3D, steering: Transform3D) -> void:
	var hip: Vector3 = rig["hip"]
	var u: Vector3 = rig["u"]
	# celebration: 0..1 how far the fist is up, and the pump
	var raise := 0.0
	var pump := 0.0
	if celebration >= 0.0:
		raise = smoothstep(0.0, 0.35, celebration) * (1.0 - smoothstep(CELEBRATION - 0.6, CELEBRATION, celebration))
		pump = sin(maxf(0.0, celebration - 0.3) * TAU * 2.1)
	# torso: leans out of corners, forward under braking, back under power, bumps on landings
	var t_roll := clampf(0.01 * _ay, -0.17, 0.17)
	var t_pitch := clampf(-0.007 * _ax, -0.05, 0.12) + raise * (0.03 + 0.03 * pump)
	var torso := body * Transform3D(Basis.IDENTITY, Vector3(0, _bob, 0)) * _about(Basis(Vector3.BACK, t_roll) * Basis(Vector3.RIGHT, t_pitch), hip)
	skeleton.set_bone_pose(Kit.TORSO, torso)
	# head: looks into the corner, tilts against the g, nods under braking, looks up when celebrating
	var h_yaw := clampf(_steer_vis * 0.9 + _yaw_rate * 0.1, -0.55, 0.55)
	var h_roll := -0.7 * t_roll
	var h_pitch := clampf(-0.005 * _ax, -0.04, 0.1) - raise * (0.18 + 0.06 * pump)
	var head := torso * _about(Basis(u, h_yaw) * Basis(Vector3.BACK, h_roll) * Basis(Vector3.RIGHT, h_pitch), rig["neck"])
	skeleton.set_bone_pose(Kit.HEAD_BONE, head)
	# arms: shoulders on the torso, hands on the steering wheel (or a fist in the air), IK elbows
	for side in 2:
		var sh_r: Vector3 = rig["shoulders"][side]
		var hd_r: Vector3 = rig["hands"][side]
		var sh: Vector3 = torso * sh_r
		var target: Vector3 = steering * hd_r
		if side == _fist_side and raise > 0.0:
			target = target.lerp(_fist(torso, side, pump), raise)
		var pole: Vector3 = torso.basis * (rig["poles"][side] as Vector3)
		var res := CarBuild.ik(sh, target, CarBuild.UPPER_ARM, CarBuild.FOREARM, pole)
		var el: Vector3 = res[0]
		var hd: Vector3 = res[1]
		var n := (el - sh).cross(hd - sh)
		var ru: Basis = _seg_basis(el - sh, n, pole) * _rest_upper[side]
		var rf: Basis = _seg_basis(hd - el, n, pole) * _rest_fore[side]
		var el_r: Vector3 = rig["elbows"][side]
		skeleton.set_bone_pose(Kit.ARM_UL if side == 0 else Kit.ARM_UR, Transform3D(ru, sh - ru * sh_r))
		skeleton.set_bone_pose(Kit.ARM_FL if side == 0 else Kit.ARM_FR, Transform3D(rf, el - rf * el_r))


## Where the celebrating fist goes: above the helmet in an open car, in front of the visor
## under a roof or canopy.
func _fist(torso: Transform3D, side: int, pump: float) -> Vector3:
	var u: Vector3 = rig["u"]
	var f: Vector3 = rig["f"]
	var sh: Vector3 = rig["shoulders"][side]
	var out := Vector3(1.0 if side == 0 else -1.0, 0, 0)
	var p: Vector3
	if rig["open"]:
		p = sh + Vector3(0, 0.5 + 0.09 * pump, 0) + out * 0.1 + f * 0.06
	else:
		p = sh + u * (0.2 + 0.05 * pump) + f * (0.3 + 0.04 * pump) + out * 0.02
		p.y = minf(p.y, float(rig["roof"]) - 0.09)
	return torso * p


## Pitch / roll from the road under the car (carMesh.js carTilt, for states without them).
func _road_tilt(car: CarEffects.Pose, track: BuiltTrack) -> Vector2:
	var i := clampi(car.idx, 0, track.count - 1)
	var j := (i + 1) % track.N if track.closed else mini(i + 1, track.count - 1)
	var slope := (track.py[j] - track.py[i]) / track.seg_len
	var rel := cos(car.yaw - atan2(track.tx[i], track.tz[i]))
	return Vector2(atan(slope * rel), -track.bank[i] * rel)


## Forget smoke, skid marks, sparks, flames and a celebration (after a restart / respawn).
func reset_effects() -> void:
	if skids != null:
		skids.clear()
	if smoke != null:
		smoke.clear()
	if sparks != null:
		sparks.clear()
		wall.ready = false
	flame.clear()
	celebration = -1.0
	_first = true


## A ghost's visibility 0..1 (hidden when nearly faded out).
func set_fade(f: float) -> void:
	visible = f > 0.02
	if f == _fade:
		return
	_fade = f
	if _ghost_mat != null:
		_ghost_mat.albedo_color.a = 0.4 * f
	flame.set_opacity(f)


## The web game's ghost fade: faded where the ghost sits on the player's car (every race
## starts that way) or right in front of the camera; 0 when `on` is false.
static func ghost_fade(ghost_pos: Vector3, car_pos: Vector3, cam_pos: Vector3, on := true) -> float:
	if not on:
		return 0.0
	return minf(smoothstep(1.0, 4.5, ghost_pos.distance_to(car_pos)), smoothstep(2.5, 6.5, ghost_pos.distance_to(cam_pos)))


## Side view of car `id` for the car picker (see CarBuild.profile).
static func profile(id: String) -> Dictionary:
	return CarBuild.profile(id)
