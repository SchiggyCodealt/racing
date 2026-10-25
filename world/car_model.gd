class_name CarModel
extends Node3D
## car_model.gd
## ------------------------------------------------------------------
## A detailed procedural car (carMesh.js CarModel): the player's car, a
## watched AI car or a see-through ghost, in the shape of one of the four
## cars (world/car_shapes.gd), with steering and spinning wheels, brake
## lights, body attitude (pitch and roll), a soft contact shadow, tyre
## smoke, skid marks, wall sparks and nitro flames.
##
## Use:
##   var car := CarModel.new("thunder")                    # body colour from the car's look
##   var ghost := CarModel.new("racer", {ghost = true, color = Color("#8fd6ff")})
##   add_child(car)
##   # every frame: the car's state after the last physics step, the state before it,
##   # how far the frame is between them (0..1) and the frame time
##   car.update(state, prev_state, alpha, delta)
##   car.reset_effects()      # after a restart / respawn
##   ghost.set_fade(f)        # 0..1 (CarModel.ghost_fade() gives the web game's fade)
##   CarModel.profile("kestrel")  # side view polygons for the car picker
##
## A state is the sim's car object or a Dictionary with its fields (x, y, z,
## yaw, pitch, roll, steer_angle, wheel_rot, vx, vz, speed, forward_speed,
## side_speed, grounded, slip, drifting, braking, throttle, steer, boost,
## boosting, hit_wall, wall_hits, wall_impact, wall_scrape, wall_x, wall_z,
## wall_nx, wall_nz); missing fields fall back as in the web game.
## Car frame: x = left, y = up, z = forward; the origin is on the road
## between the axles. A ghost makes no smoke, skid marks or sparks; it shows
## the nitro jets. The car's meshes are on visual layer CAR_LAYER (the
## contact shadow decal skips them).

const Shapes = preload("res://world/car_shapes.gd")
const Themes = preload("res://world/themes.gd")

const CAR_LAYER := 2
## Looks of the cars (cars.js look): body and accent colour. Unknown ids: the racer's.
const LOOKS := {
	"racer": {"color": "#d7263d", "accent": "#1b1b1e"},
	"kestrel": {"color": "#f2c14e", "accent": "#2b2d42"},
	"thunder": {"color": "#3a86ff", "accent": "#0b0c10"},
	"drifter": {"color": "#2ec4b6", "accent": "#ff9f1c"},
}

var car_id := "racer"
var ghost := false
var body: Node3D
var wheels: Array = [] # {pivot, spin, front, r}
var materials: Array[Material] = []
var smoke: CarEffects.TyreSmoke = null
var skids: CarEffects.SkidMarks = null
var sparks: CarEffects.Sparks = null
var flame: CarEffects.NitroFlame
var wall := CarEffects.WallState.new()
## The pose drawn last frame (interpolated); the camera can use it.
var pose := CarEffects.Pose.new()

var _tail_mat: StandardMaterial3D = null
var _ghost_mat: StandardMaterial3D = null
var _att := Vector2.ZERO # pitch, roll
var _spin_angle := 0.0
var _steer_vis := 0.0
var _brake_glow := 1.0
var _smoke_acc := 0.0
var _first := true
var _fade := 1.0

static var _mesh_cache: Dictionary = {}


## car_id: "racer" | "kestrel" | "thunder" | "drifter" (unknown: racer).
## opts: ghost (bool), color (Color or "#rrggbb": body colour, or the ghost's colour).
func _init(p_car_id := "racer", opts := {}) -> void:
	car_id = p_car_id if Shapes.shapes().has(p_car_id) else "racer"
	ghost = opts.get("ghost", false)
	var look: Dictionary = LOOKS.get(car_id, LOOKS["racer"])
	var color: Color = Color(opts["color"]) if opts.has("color") else Color(look["color"])
	name = "GhostCar" if ghost else "Car"
	var shape := Shapes.shape_of(car_id)
	var meshes := _meshes(car_id)

	var paint: Material
	var carbon: Material
	var glass: Material
	var tyre_m: Material
	var rim_m: Material
	var brake_m: Material
	var head_m: Material
	var tail_m: Material
	var stripe_m: Material
	var accent_m: Material
	if ghost:
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(color, 0.4)
		gm.emission_enabled = true
		gm.emission = color
		gm.emission_energy_multiplier = 0.45
		gm.roughness = 0.35
		gm.metallic = 0.1
		# the depth pre-pass draws only the front-most surface: no X-ray wheels through the body
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		_ghost_mat = gm
		materials.append(gm)
		paint = gm
		carbon = gm
		glass = gm
		tyre_m = gm
		rim_m = gm
		brake_m = gm
		head_m = gm
		tail_m = gm
		stripe_m = gm
		accent_m = gm
	else:
		paint = _std(color, 0.36, 0.3, 0.06)
		accent_m = _std(Color(look["accent"]), 0.4, 0.25, 0.08)
		# stripe: the accent colour, or (the racer) white on dark paint, near-black on light paint
		var lin := color.srgb_to_linear()
		var lum := (maxf(lin.r, maxf(lin.g, lin.b)) + minf(lin.r, minf(lin.g, lin.b))) / 2.0
		stripe_m = accent_m if shape["stripeAccent"] else _std(Themes.col(0x1b1d22 if lum > 0.62 else 0xf4f4f2), 0.4, 0.1, 0.08)
		carbon = _std(Themes.col(0x17191e), 0.38, 0.4)
		glass = _std(Themes.col(0x0d1621), 0.04, 0.75)
		tyre_m = _std(Themes.col(0x1c1c1e), 0.82, 0.0)
		(tyre_m as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
		rim_m = _std(Themes.col(0xc3c7cf), 0.22, 1.0)
		var bm := _std(Color.WHITE, 0.45, 0.6)
		bm.vertex_color_use_as_albedo = true
		bm.vertex_color_is_srgb = true
		brake_m = bm
		var hm := _std(Color.WHITE, 0.2, 0.0)
		hm.emission_enabled = true
		hm.emission = Themes.col(0xfff1d6)
		hm.emission_energy_multiplier = 2.2
		head_m = hm
		var tm := _std(Themes.col(0x3a0505), 0.3, 0.0)
		tm.emission_enabled = true
		# ACES bleeds bright red into green (brake lights would turn orange): a little negative
		# green and blue (linear 1, -0.084, -0.034, as in the web game; emission is sRGB here)
		tm.emission = Color(1.0, -0.084 * 12.92, -0.034 * 12.92)
		tm.emission_energy_multiplier = 0.9
		tail_m = tm
		_tail_mat = tm

	# body (sprung part: pitches and rolls with the attitude)
	body = Node3D.new()
	body.name = "Body"
	add_child(body)
	_add_mesh(body, meshes["paint"], paint, true)
	_add_mesh(body, meshes["stripe"], stripe_m, true)
	_add_mesh(body, meshes["carbon"], carbon, true)
	_add_mesh(body, meshes["glass"], glass, true)
	_add_mesh(body, meshes["mirror"], paint, true)
	if meshes["accent"] != null:
		_add_mesh(body, meshes["accent"], accent_m, true)
	_add_mesh(body, meshes["head"], head_m, false)
	_add_mesh(body, meshes["tail"], tail_m, false)

	# wheels: pivot (steers) > spin (rolls) > tyre + rim; the brake on the pivot
	for w in Shapes.wheel_layout(shape):
		var x: float = w[0]
		var r: float = w[2]
		var key := "%s:%s:%s" % [r, w[3], "L" if x > 0.0 else "R"]
		var wm: Dictionary = meshes["wheels"][key]
		var pivot := Node3D.new()
		pivot.position = Vector3(x, r, w[1])
		var spin := Node3D.new()
		pivot.add_child(spin)
		_add_mesh(spin, wm["tyre"], tyre_m, true)
		_add_mesh(spin, wm["rim"], rim_m, true)
		_add_mesh(pivot, wm["brake"], brake_m, true)
		add_child(pivot)
		wheels.append({"pivot": pivot, "spin": spin, "front": w[4], "r": r})

	if not ghost:
		# soft contact shadow under the car, projected on whatever is below (curbs, banking)
		var blob := Decal.new()
		blob.name = "ContactShadow"
		blob.texture_albedo = _blob_texture()
		blob.size = Vector3(2.6 * shape["width"], 2.0, 5.4 * (shape["front"] + shape["rear"]) / 2.0)
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

	flame = CarEffects.NitroFlame.new(Shapes.nozzles(shape), not ghost)
	add_child(flame.jets)
	if flame.glow != null:
		add_child(flame.glow)


func _std(c: Color, rough: float, metal: float, clearcoat_rough := -1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if clearcoat_rough >= 0.0:
		m.clearcoat_enabled = true
		m.clearcoat = 1.0
		m.clearcoat_roughness = clearcoat_rough
	materials.append(m)
	return m


func _add_mesh(parent: Node3D, mesh: Mesh, mat: Material, shadow: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.layers = CAR_LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow and not ghost else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## The meshes of car `id`, built once and shared by every model of that car.
static func _meshes(id: String) -> Dictionary:
	if _mesh_cache.has(id):
		return _mesh_cache[id]
	var shape := Shapes.shape_of(id)
	var lights := Shapes.light_geometries(shape)
	var acc = Shapes.accent_geometry(shape)
	var out := {
		"paint": Shapes.paint_geometry(shape, 1).to_mesh(null, false, false),
		"stripe": Shapes.stripe_geometry(shape).to_mesh(null, false, false),
		"carbon": Shapes.carbon_geometry(shape, 1).to_mesh(null, false, false),
		"glass": Shapes.glass_geometry(shape).to_mesh(null, false, false),
		"mirror": Shapes.mirror_geometry(shape).to_mesh(null, false, false),
		"accent": acc.to_mesh(null, false, false) if acc != null else null,
		"head": lights["head"].to_mesh(null, false, false),
		"tail": lights["tail"].to_mesh(null, false, false),
		"wheels": {},
	}
	for w in Shapes.wheel_layout(shape):
		var key := "%s:%s:%s" % [w[2], w[3], "L" if w[0] > 0.0 else "R"]
		if out["wheels"].has(key):
			continue
		var g := Shapes.wheel_geometries(w[2], w[3])
		if w[0] < 0.0:
			for k in ["tyre", "rim", "brake"]:
				g[k].rotate_y(PI)
		out["wheels"][key] = {
			"tyre": g["tyre"].to_mesh(null, false, false),
			"rim": g["rim"].to_mesh(null, false, false),
			"brake": g["brake"].to_mesh(null, false, true),
		}
	_mesh_cache[id] = out
	return out


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


# ---- per frame ----------------------------------------------------------------

## Draw the car between the previous physics step (prev_state, may be null) and the
## last one (state): alpha 0..1 is how far the frame is between them; dt the frame time.
## `track` (BuiltTrack, optional) is only used when the state has no pitch / roll.
func update(state: Variant, prev_state: Variant = null, alpha := 1.0, dt := 1.0 / 60.0, track: BuiltTrack = null) -> void:
	dt = minf(dt, 0.1)
	var car := pose.read(state, prev_state, alpha)
	# a jump of several metres means restart / respawn: snap, start new skid strips
	if not _first and (car.x - position.x) * (car.x - position.x) + (car.z - position.z) * (car.z - position.z) > 64.0:
		_first = true
		if skids != null:
			skids.lift(0)
			skids.lift(1)

	# attitude: pitch / roll from the state when present, else follow the road (v1)
	var tilt := _att
	if car.has_att:
		tilt = Vector2(car.pitch, car.roll)
	elif car.grounded and track != null and car.idx >= 0:
		tilt = _road_tilt(car, track)
	var k := 1.0 if _first else 1.0 - exp(-dt * (30.0 if car.has_att else 14.0 if car.grounded else 2.0))
	_att += (tilt - _att) * k
	position = Vector3(car.x, car.y, car.z)
	rotation = Vector3(-_att.x, car.yaw, _att.y)
	if not car.has_att:
		# v1: the body leans out of corners a little
		var lean := clampf(-car.steer * car.speed * 0.0016, -0.06, 0.06)
		body.rotation.z += (lean - body.rotation.z) * (1.0 - exp(-dt * 8.0))
	else:
		body.rotation.z = 0.0

	# wheels
	var steer := car.steer_angle if car.has_steer_angle else car.steer * 0.42
	_steer_vis += (steer - _steer_vis) * (1.0 if _first else 1.0 - exp(-dt * 20.0))
	if car.has_wheel_rot:
		_spin_angle = car.wheel_rot
	else:
		_spin_angle += car.forward_speed / 0.39 * dt
	for w in wheels:
		(w["spin"] as Node3D).rotation.x = _spin_angle
		(w["pivot"] as Node3D).rotation.y = _steer_vis if w["front"] else 0.0

	# brake lights
	if _tail_mat != null:
		var braking := car.braking if car.has_braking else (car.throttle < -0.05 and car.forward_speed > 0.5)
		var target := 3.4 if braking else 0.75
		_brake_glow += (target - _brake_glow) * (1.0 - exp(-dt * 25.0))
		_tail_mat.emission_energy_multiplier = _brake_glow

	var xf := global_transform if is_inside_tree() else transform

	# tyre smoke and skid marks from the rear wheels
	if smoke != null:
		var slip := car.slip if car.has_slip else (0.75 if car.drifting else clampf((absf(car.side_speed) - 4.0) / 6.0, 0.0, 1.0))
		var sliding := car.grounded and slip > 0.3 and car.speed > 4.0
		var sx := cos(car.yaw)
		var sz := -sin(car.yaw) # left vector
		for wi in 2:
			var piv: Node3D = wheels[2 + wi]["pivot"]
			var p: Vector3 = xf * Vector3(piv.position.x, 0.03, piv.position.z)
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


## Pitch / roll from the road under the car (carMesh.js carTilt, for states without them).
func _road_tilt(car: CarEffects.Pose, track: BuiltTrack) -> Vector2:
	var i := clampi(car.idx, 0, track.count - 1)
	var j := (i + 1) % track.N if track.closed else mini(i + 1, track.count - 1)
	var slope := (track.py[j] - track.py[i]) / track.seg_len
	var rel := cos(car.yaw - atan2(track.tx[i], track.tz[i]))
	return Vector2(atan(slope * rel), -track.bank[i] * rel)


## Forget smoke, skid marks, sparks and flames (after a restart / respawn).
func reset_effects() -> void:
	if skids != null:
		skids.clear()
	if smoke != null:
		smoke.clear()
	if sparks != null:
		sparks.clear()
		wall.ready = false
	flame.clear()
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


## Side view of car `id` for the car picker (see Shapes.profile).
static func profile(id: String) -> Dictionary:
	return Shapes.profile(id)
