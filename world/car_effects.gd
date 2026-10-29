class_name CarEffects
## car_effects.gd
## ------------------------------------------------------------------
## Car effects in world space (carMesh.js TyreSmoke, SkidMarks, Sparks,
## NitroFlame, wallEvents, emitSparks; v6.3: Spray, the dust and snow the tyres
## throw up on loose ground, and tyre marks coloured by the surface) and Pose,
## the drawn state of a car.
##
## Each effect is a fixed pool drawn with one MultiMeshInstance3D (one draw
## call, nothing allocated per frame): the particles are simulated on the
## CPU exactly as in the web game and their data goes into the MultiMesh
## buffer; small shaders (world/shaders) turn each instance into a
## camera-facing disc or streak. The nodes are top_level, so they stay in
## world space under the car that owns them.
##
## Pose.read(state, prev, alpha) takes a car snapshot (the sim's car object
## or a Dictionary with the same fields, snake_case; camelCase is accepted
## too) and the previous physics step's, and makes the interpolated state the
## model, the effects and the camera draw.
extends RefCounted

const SMOKE_SHADER = preload("res://world/shaders/smoke.gdshader")
const SKID_SHADER = preload("res://world/shaders/skid.gdshader")
const SPARK_SHADER = preload("res://world/shaders/spark.gdshader")
const JET_SHADER = preload("res://world/shaders/jet.gdshader")
const GLOW_SHADER = preload("res://world/shaders/glow.gdshader")

## Share of the full spark, nitro-glow, dust and snow-spray emission (graphics quality: 1 high,
## 0.65 medium, 0.3 low).
static var spark_share := 1.0

const STEP := 1.0 / 60.0      # the physics step (wall_hits counts steps)
const CORE := 2.2 - 1.0       # half length of the physics capsule's core segment (halfLength - radius)
const SPARK_Y := 0.45         # m above the car's base: bumper height
const BURST_MIN := 3.0        # m/s into the wall for a burst
const SCRAPE_MIN := 3.0       # m/s along the wall for a stream
const FLAME_POOL := 64        # glow particles per car
const FLAME_RATE := 150.0     # glow particles per second at full nitro (high quality), over all tail pipes
const FLOATS := 16            # MultiMesh buffer floats per instance: transform (12) + custom data (4)
const NO_CULL := AABB(Vector3(-1e5, -1e4, -1e5), Vector3(2e5, 2e4, 2e5))


# =============================================================================
# Pose: the drawn (interpolated) state of a car
# =============================================================================

class Pose:
	var x := 0.0
	var y := 0.0
	var z := 0.0
	var yaw := 0.0
	var pitch := 0.0
	var roll := 0.0
	var steer_angle := 0.0
	var wheel_rot := 0.0
	var vx := 0.0
	var vz := 0.0
	var speed := 0.0
	var forward_speed := 0.0
	var side_speed := 0.0
	var steer := 0.0
	var throttle := 0.0
	var slip := 0.0
	var boost := 0.0
	var grounded := true
	var drifting := false
	var braking := false
	var boosting := false
	var hit_wall := false
	var wall_hits := 0
	var wall_impact := 0.0
	var wall_scrape := 0.0
	var wall_x := 0.0
	var wall_z := 0.0
	var wall_nx := 0.0
	var wall_nz := 0.0
	var idx := -1
	## which optional fields the snapshot had (v1 fallbacks otherwise, as in carMesh.js)
	var has_att := false
	var has_wheel_rot := false
	var has_steer_angle := false
	var has_slip := false
	var has_braking := false
	var has_boost := false

	## Fill from `s` (car object or Dictionary), interpolated from `prev` (may be null) by alpha.
	func read(s: Variant, prev: Variant = null, alpha := 1.0) -> Pose:
		x = _f(s, "x", "x")
		y = _f(s, "y", "y")
		z = _f(s, "z", "z")
		yaw = _f(s, "yaw", "yaw")
		var p = s.get("pitch")
		var r = s.get("roll")
		has_att = p != null and r != null
		pitch = float(p) if p != null else 0.0
		roll = float(r) if r != null else 0.0
		var sa = _v(s, "steer_angle", "steerAngle")
		has_steer_angle = sa != null
		steer_angle = float(sa) if sa != null else 0.0
		var wr = _v(s, "wheel_rot", "wheelRot")
		has_wheel_rot = wr != null
		wheel_rot = float(wr) if wr != null else 0.0
		vx = _f(s, "vx", "vx")
		vz = _f(s, "vz", "vz")
		var sp = s.get("speed")
		speed = float(sp) if sp != null else sqrt(vx * vx + vz * vz)
		forward_speed = _f(s, "forward_speed", "forwardSpeed")
		side_speed = _f(s, "side_speed", "sideSpeed")
		steer = _f(s, "steer", "steer")
		throttle = _f(s, "throttle", "throttle")
		var sl = s.get("slip")
		has_slip = sl != null
		slip = float(sl) if sl != null else 0.0
		var bo = s.get("boost")
		has_boost = bo != null
		boost = float(bo) if bo != null else 0.0
		grounded = _b(s, "grounded", "grounded", true)
		drifting = _b(s, "drifting", "drifting", false)
		var br = s.get("braking")
		has_braking = br != null
		braking = bool(br) if br != null else false
		boosting = _b(s, "boosting", "boosting", false)
		hit_wall = _b(s, "hit_wall", "hitWall", false)
		wall_hits = int(_f(s, "wall_hits", "wallHits"))
		wall_impact = _f(s, "wall_impact", "wallImpact")
		wall_scrape = _f(s, "wall_scrape", "wallScrape")
		wall_x = _f(s, "wall_x", "wallX")
		wall_z = _f(s, "wall_z", "wallZ")
		wall_nx = _f(s, "wall_nx", "wallNx")
		wall_nz = _f(s, "wall_nz", "wallNz")
		var ix = s.get("idx")
		idx = int(ix) if ix != null else -1
		if prev != null and alpha < 1.0:
			var a := clampf(alpha, 0.0, 1.0)
			var px := _f(prev, "x", "x")
			var pz := _f(prev, "z", "z")
			# no blending across a restart / respawn jump
			if (x - px) * (x - px) + (z - pz) * (z - pz) < 400.0:
				x = px + (x - px) * a
				y = _f(prev, "y", "y") + (y - _f(prev, "y", "y")) * a
				z = pz + (z - pz) * a
				var py := _f(prev, "yaw", "yaw")
				yaw = py + angle_difference(py, yaw) * a
				if has_att:
					var pp := _f(prev, "pitch", "pitch")
					var pr := _f(prev, "roll", "roll")
					pitch = pp + (pitch - pp) * a
					roll = pr + (roll - pr) * a
				if has_steer_angle:
					var ps := _f(prev, "steer_angle", "steerAngle")
					steer_angle = ps + (steer_angle - ps) * a
				if has_wheel_rot:
					var pw := _f(prev, "wheel_rot", "wheelRot")
					wheel_rot = pw + angle_difference(pw, wheel_rot) * a
		return self

	## Copy of another pose.
	func copy_from(o: Pose) -> Pose:
		for prop in ["x", "y", "z", "yaw", "pitch", "roll", "steer_angle", "wheel_rot", "vx", "vz", "speed", "forward_speed",
				"side_speed", "steer", "throttle", "slip", "boost", "grounded", "drifting", "braking", "boosting", "hit_wall",
				"wall_hits", "wall_impact", "wall_scrape", "wall_x", "wall_z", "wall_nx", "wall_nz", "idx", "has_att",
				"has_wheel_rot", "has_steer_angle", "has_slip", "has_braking", "has_boost"]:
			set(prop, o.get(prop))
		return self

	static func _v(s: Variant, key: String, alt: String) -> Variant:
		var v = s.get(key)
		if v == null and alt != key:
			v = s.get(alt)
		return v

	static func _f(s: Variant, key: String, alt: String) -> float:
		var v = _v(s, key, alt)
		return float(v) if v != null else 0.0

	static func _b(s: Variant, key: String, alt: String, def: bool) -> bool:
		var v = _v(s, key, alt)
		return bool(v) if v != null else def


# =============================================================================
# Wall events (shared by the sparks and the camera shake)
# =============================================================================

## Per-car bookkeeping for wall_events().
class WallState:
	var ready := false
	var hits := 0
	var vx := 0.0
	var vz := 0.0
	var x := 0.0
	var z := 0.0
	var touching := false
	var impact := 0.0
	var scrape := 0.0
	var acc := 0.0


## What a car's wall contact did since the last frame (carMesh.js wallEvents): new
## contact steps are counted with wall_hits (a frame can run several physics steps or
## none); a hit in a step that wasn't drawn is estimated from the speed into the wall
## seen on the frame before. Returns the number of new contact steps and leaves the
## hit's speed into the wall (m/s) in st.impact and the scrape speed in st.scrape.
## A jump of 20+ m (restart, respawn, another car) or st.ready = false starts over.
static func wall_events(st: WallState, car: Pose) -> int:
	var jump := (car.x - st.x) * (car.x - st.x) + (car.z - st.z) * (car.z - st.z) > 400.0
	var steps := car.wall_hits - st.hits if st.ready and not jump else 0
	if steps < 0 or steps > 60:
		steps = 0
	st.impact = 0.0
	st.scrape = car.wall_scrape if car.hit_wall else 0.0
	if steps > 0:
		var imp := car.wall_impact
		if not st.touching:
			imp = maxf(imp, -(st.vx * car.wall_nx + st.vz * car.wall_nz))
		st.impact = imp
	elif not st.ready or jump:
		st.acc = 0.0
	st.ready = true
	st.hits = car.wall_hits
	st.vx = car.vx
	st.vz = car.vz
	st.x = car.x
	st.z = car.z
	st.touching = car.hit_wall
	return steps


## Sparks for one car's wall contact this frame (after wall_events returned `steps` > 0):
## a burst for a hit, scaled by its speed into the wall, and a stream while scraping.
## (x, y, z, yaw) is the drawn car. Spawns at most `cap`; returns how many it spawned.
static func emit_sparks(sparks: Sparks, st: WallState, steps: int, car: Pose, x: float, y: float, z: float, yaw: float,
		cap: int, rate := 1.0) -> int:
	if cap <= 0 or (car.wall_nx == 0.0 and car.wall_nz == 0.0):
		return 0
	var q := spark_share
	var burst := 0
	var stream := 0
	if st.impact >= BURST_MIN:
		burst = roundi(minf(64.0, 8.0 + st.impact * 3.0) * q)
	if st.scrape > SCRAPE_MIN:
		st.acc += steps * STEP * minf(200.0, (st.scrape - SCRAPE_MIN) * 4.5) * q * rate
		stream = floori(st.acc)
		st.acc -= stream
	else:
		st.acc = 0.0
	burst = mini(burst, cap)
	stream = mini(stream, cap - burst)
	if burst + stream <= 0:
		return 0
	# where the drawn car touches the wall: the contact point slid along the wall into the
	# span of the drawn car's capsule, a few cm off the wall so the barrier doesn't hide it
	var nx := car.wall_nx
	var nz := car.wall_nz
	var tx := -nz
	var tz := nx
	var fx := sin(yaw) * CORE
	var fz := cos(yaw) * CORE
	var s0 := (x - fx - car.wall_x) * tx + (z - fz - car.wall_z) * tz
	var s1 := (x + fx - car.wall_x) * tx + (z + fz - car.wall_z) * tz
	var s := maxf(minf(s0, s1), minf(maxf(s0, s1), 0.0))
	var cx := car.wall_x + tx * s + nx * 0.06
	var cy := y + SPARK_Y
	var cz := car.wall_z + tz * s + nz * 0.06
	var cvx := car.vx
	var cvz := car.vz
	var floor_y := y + 0.03
	for k in burst:
		# a fan off the wall and upwards, carried along a little by the car
		var sp := 3.5 + randf() * minf(11.0, 3.0 + st.impact * 0.5)
		var a := 0.2 + randf() * 0.8
		var u := 0.4 + randf() * 1.1
		var t := (randf() - 0.5) * 1.8
		var l := sqrt(a * a + u * u + t * t)
		var m := 0.25 + randf() * 0.35
		sparks.spawn(cx, cy + (randf() - 0.5) * 0.2, cz,
			cvx * m + ((nx * a + tx * t) / l) * sp, (u / l) * sp, cvz * m + ((nz * a + tz * t) / l) * sp,
			0.3 + randf() * 0.35, 0.85 + randf() * 0.15, floor_y)
	var span := steps * STEP
	for k in stream:
		# shaved off along the wall, spread over the frame's steps so a stream doesn't come out in clumps
		var m := 0.45 + randf() * 0.4
		var vx := cvx * m + nx * (0.3 + randf() * 1.9) + (randf() - 0.5) * 1.6
		var vy := 0.6 + randf() * 2.6
		var vz := cvz * m + nz * (0.3 + randf() * 1.9) + (randf() - 0.5) * 1.6
		var age := randf() * span
		sparks.spawn(cx + (vx - cvx) * age, cy + (randf() - 0.5) * 0.25 + vy * age, cz + (vz - cvz) * age,
			vx, vy, vz, 0.2 + randf() * 0.3 - age, 0.7 + randf() * 0.3, floor_y)
	return burst + stream


# =============================================================================
# MultiMesh helpers
# =============================================================================

static var _quads: Dictionary = {}


## Unit quads: "disc" (-0.5..0.5 in x and y), "streak" (x 0..1, y -1..1), "corners" (vertex x = corner 0..3).
static func quad(kind: String) -> ArrayMesh:
	if _quads.has(kind):
		return _quads[kind]
	var v := PackedVector3Array()
	match kind:
		"disc":
			v = PackedVector3Array([Vector3(-0.5, -0.5, 0), Vector3(0.5, -0.5, 0), Vector3(0.5, 0.5, 0), Vector3(-0.5, 0.5, 0)])
		"streak":
			v = PackedVector3Array([Vector3(0, -1, 0), Vector3(1, -1, 0), Vector3(1, 1, 0), Vector3(0, 1, 0)])
		_:
			v = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 0)])
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = v
	a[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	a[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 0, 3, 2])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	m.custom_aabb = NO_CULL
	_quads[kind] = m
	return m


## A world-space MultiMesh node with `count` instances of quad `kind` drawn with `shader`.
static func pool_node(kind: String, count: int, mat: Material, node_name: String) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad(kind)
	mm.instance_count = count
	mm.visible_instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = mm
	node.material_override = mat
	node.top_level = true
	node.custom_aabb = NO_CULL
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visible = false
	return node


static func shader_mat(shader: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	return m


## Writes instance i: columns c0 (basis x) and c3 (origin), custom data (a, b, c, d).
static func put(buf: PackedFloat32Array, i: int, c3: Vector3, c0: Vector3, a: float, b: float, c := 0.0, d := 0.0) -> void:
	var o := i * CarEffects.FLOATS
	buf[o] = c0.x
	buf[o + 1] = 0.0
	buf[o + 2] = 0.0
	buf[o + 3] = c3.x
	buf[o + 4] = c0.y
	buf[o + 5] = 0.0
	buf[o + 6] = 0.0
	buf[o + 7] = c3.y
	buf[o + 8] = c0.z
	buf[o + 9] = 0.0
	buf[o + 10] = 0.0
	buf[o + 11] = c3.z
	buf[o + 12] = a
	buf[o + 13] = b
	buf[o + 14] = c
	buf[o + 15] = d


# =============================================================================
# Tyre smoke
# =============================================================================

class TyreSmoke:
	var max := 64
	var node: MultiMeshInstance3D
	var buf := PackedFloat32Array()
	# particle state: position, velocity, life left, full life, start size, alpha
	var p := PackedVector3Array()
	var v := PackedVector3Array()
	var life := PackedFloat32Array()
	var full := PackedFloat32Array()
	var s0 := PackedFloat32Array()
	var al := PackedFloat32Array()
	var next := 0
	var mat: ShaderMaterial

	func _init(n := 64) -> void:
		max = n
		mat = CarEffects.shader_mat(CarEffects.SMOKE_SHADER)
		node = CarEffects.pool_node("disc", max, mat, "TyreSmoke")
		node.multimesh.visible_instance_count = max
		buf.resize(max * CarEffects.FLOATS)
		for a in [p, v]:
			a.resize(max)
		for a in [life, full, s0, al]:
			a.resize(max)
		full.fill(1.0)

	func emit(x: float, y: float, z: float, vx: float, vz: float, strength: float) -> void:
		var k := next
		next = (next + 1) % max
		life[k] = 0.9 + randf() * 0.6
		full[k] = life[k]
		p[k] = Vector3(x + (randf() - 0.5) * 0.3, y + 0.25, z + (randf() - 0.5) * 0.3)
		v[k] = Vector3(vx * 0.25 + (randf() - 0.5) * 1.2, 0.6 + randf() * 0.6, vz * 0.25 + (randf() - 0.5) * 1.2)
		s0[k] = 0.6 + randf() * 0.4
		al[k] = 0.16 + 0.24 * strength

	func update(dt: float) -> void:
		var alive := 0
		var drag := exp(-dt * 1.8)
		var dragy := exp(-dt * 0.8)
		for k in max:
			if life[k] > 0.0:
				life[k] -= dt
				var w := v[k]
				w = Vector3(w.x * drag, w.y * dragy, w.z * drag)
				v[k] = w
				p[k] += w * dt
			var t := 1.0 - life[k] / full[k] if life[k] > 0.0 else 1.0
			var a := al[k] * (1.0 - t) * minf(1.0, t * 8.0) if life[k] > 0.0 else 0.0
			CarEffects.put(buf, k, p[k], Vector3.ZERO, s0[k] + t * 2.2, a)
			if life[k] > 0.0:
				alive += 1
		node.visible = alive > 0
		if alive > 0:
			node.multimesh.buffer = buf

	func clear() -> void:
		life.fill(0.0)
		node.visible = false


# =============================================================================
# Skid marks
# =============================================================================

## Strip pieces behind the rear wheels. Each piece's colour mixes the asphalt mark with the
## marks of surfaces 1 and 2 of sim/surfaces.gd (custom data .z / .w: their weights), so the
## marks are dark on asphalt, brown in the dirt and grey-blue in the snow.
class SkidMarks:
	var max := 240
	var node: MultiMeshInstance3D
	var next := 0
	var used := 0
	var last := [null, null] # per rear wheel: [Vector3 pos, Vector2 side, alpha] or null
	## the surface weights (tint) of the newest piece
	var newest_tint := Vector2.ZERO
	const HW := 0.13

	func _init(n := 240) -> void:
		max = n
		var mat := CarEffects.shader_mat(CarEffects.SKID_SHADER)
		mat.set_shader_parameter("color", Color.html(Surfaces.def(Surfaces.ASPHALT).marks))
		for slot in [1, 2]:
			if slot < Surfaces.count():
				mat.set_shader_parameter("color_%d" % slot, Color.html(Surfaces.def(slot).marks))
		node = CarEffects.pool_node("corners", max, mat, "SkidMarks")
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	## A strip piece for wheel w from its last point to p; side vector (sx, sz). tint: the
	## weights of surfaces 1 and 2 under the wheel; spacing: the shortest piece (m).
	func add(w: int, p: Vector3, sx: float, sz: float, alpha: float, tint := Vector2.ZERO, spacing := 0.5) -> void:
		var l = last[w]
		if l != null:
			var lp: Vector3 = l[0]
			var d2 := (p.x - lp.x) * (p.x - lp.x) + (p.z - lp.z) * (p.z - lp.z)
			if d2 < spacing * spacing:
				return
			if d2 < 9.0:
				var k := next
				next = (next + 1) % max
				used = mini(max, used + 1)
				var ls: Vector2 = l[1]
				var a := lp + Vector3(ls.x, 0, ls.y) * HW
				var b := lp - Vector3(ls.x, 0, ls.y) * HW
				var c := p - Vector3(sx, 0, sz) * HW
				var d := p + Vector3(sx, 0, sz) * HW
				var mm := node.multimesh
				mm.set_instance_transform(k, Transform3D(Basis(a, b, c), d))
				mm.set_instance_custom_data(k, Color(l[2], alpha, tint.x, tint.y))
				newest_tint = tint
				mm.visible_instance_count = used
				node.visible = true
		last[w] = [p, Vector2(sx, sz), alpha]

	func lift(w: int) -> void:
		last[w] = null

	func clear() -> void:
		node.multimesh.visible_instance_count = 0
		used = 0
		next = 0
		node.visible = false
		last = [null, null]


# =============================================================================
# Dust and snow spray (v6.3)
# =============================================================================

## What the tyres throw up on loose ground: "dust" (dirt: big soft brown puffs that hang in the
## air and drift up) or "snow" (small white clumps thrown back and up that fall again). A fixed
## pool of lit soft discs (the tyre smoke's shader, coloured), one draw call; a full pool reuses
## the oldest. The caller scales the emission by spark_share (graphics quality).
class Spray:
	var max := 96
	var kind := "dust"
	var node: MultiMeshInstance3D
	var buf := PackedFloat32Array()
	var p := PackedVector3Array()
	var v := PackedVector3Array()
	var life := PackedFloat32Array()
	var full := PackedFloat32Array()
	var s0 := PackedFloat32Array()
	var al := PackedFloat32Array()
	var fl := PackedFloat32Array()
	var next := 0
	var alive := 0

	func _init(p_kind: String, color: Color, n := 96) -> void:
		max = n
		kind = p_kind
		var mat := CarEffects.shader_mat(CarEffects.SMOKE_SHADER)
		mat.set_shader_parameter("color", color)
		node = CarEffects.pool_node("disc", max, mat, "Dust" if kind == "dust" else "SnowSpray")
		node.multimesh.visible_instance_count = max
		buf.resize(max * CarEffects.FLOATS)
		for a in [p, v]:
			a.resize(max)
		for a in [life, full, s0, al, fl]:
			a.resize(max)
		full.fill(1.0)

	## One puff at a wheel (x, y, z) of a car moving at (vx, vz); strength 0..1 (speed, slide).
	func emit(x: float, y: float, z: float, vx: float, vz: float, strength: float) -> void:
		var k := next
		next = (next + 1) % max
		alive = maxi(alive, 1) # (update() counts them)
		fl[k] = y + 0.05
		if kind == "snow":
			life[k] = 0.45 + randf() * 0.45
			p[k] = Vector3(x + (randf() - 0.5) * 0.4, y + 0.15, z + (randf() - 0.5) * 0.4)
			v[k] = Vector3(vx * 0.55 + (randf() - 0.5) * 3.0, 1.2 + randf() * 2.6 * (0.5 + strength), vz * 0.55 + (randf() - 0.5) * 3.0)
			s0[k] = 0.3 + randf() * 0.3
			al[k] = 0.35 + 0.45 * strength
		else:
			life[k] = 1.4 + randf() * 1.3
			p[k] = Vector3(x + (randf() - 0.5) * 0.6, y + 0.35, z + (randf() - 0.5) * 0.6)
			v[k] = Vector3(vx * 0.45 + (randf() - 0.5) * 2.4, 0.9 + randf() * 1.6, vz * 0.45 + (randf() - 0.5) * 2.4)
			s0[k] = 1.1 + randf() * 0.8
			al[k] = 0.2 + 0.35 * strength
		full[k] = life[k]

	func update(dt: float) -> void:
		if alive == 0 and not node.visible:
			return
		alive = 0
		var snow := kind == "snow"
		var drag := exp(-dt * (1.2 if snow else 1.8))
		var dragy := exp(-dt * (0.3 if snow else 1.0))
		var grav := (9.0 if snow else 0.0) * dt
		var grow := 1.1 if snow else 4.5
		for k in max:
			if life[k] > 0.0:
				life[k] -= dt
				var w := v[k]
				w = Vector3(w.x * drag, w.y * dragy - grav, w.z * drag)
				var q := p[k] + w * dt
				if q.y < fl[k]:
					q.y = fl[k]
					w = Vector3(w.x * 0.5, 0.0, w.z * 0.5)
				v[k] = w
				p[k] = q
			var t := 1.0 - life[k] / full[k] if life[k] > 0.0 else 1.0
			var a := al[k] * (1.0 - t) * minf(1.0, t * 10.0) if life[k] > 0.0 else 0.0
			# (dust balloons out at once, then drifts: the growth follows sqrt(t))
			CarEffects.put(buf, k, p[k], Vector3.ZERO, s0[k] + (t * grow if snow else sqrt(t) * grow), a)
			if life[k] > 0.0:
				alive += 1
		node.visible = alive > 0
		if alive > 0:
			node.multimesh.buffer = buf

	func clear() -> void:
		life.fill(0.0)
		alive = 0
		node.visible = false


# =============================================================================
# Wall sparks
# =============================================================================

## A fixed pool of sparks drawn as glowing streaks. Live sparks are packed at the
## front (only those are drawn); a full pool reuses slots in turn. Sparks fall with
## gravity, slow down in the air, bounce low off the road and cool down over their
## 0.2-0.65 s life, in render time (frame dt).
class Sparks:
	var max := 160
	var n := 0
	var cursor := 0
	var node: MultiMeshInstance3D
	var buf := PackedFloat32Array()
	var p := PackedVector3Array()
	var v := PackedVector3Array()
	var life := PackedFloat32Array()
	var full := PackedFloat32Array()
	var heat := PackedFloat32Array()
	var floor_y := PackedFloat32Array()

	func _init(n_max := 160) -> void:
		max = n_max
		node = CarEffects.pool_node("streak", max, CarEffects.shader_mat(CarEffects.SPARK_SHADER), "Sparks")
		buf.resize(max * CarEffects.FLOATS)
		for a in [p, v]:
			a.resize(max)
		for a in [life, full, heat, floor_y]:
			a.resize(max)

	func spawn(x: float, y: float, z: float, vx: float, vy: float, vz: float, l: float, h: float, fl: float) -> void:
		if not (l > 0.0):
			return
		var k := n
		if k < max:
			n += 1
		else:
			k = cursor
			cursor = (cursor + 1) % max
		p[k] = Vector3(x, y, z)
		v[k] = Vector3(vx, vy, vz)
		life[k] = l
		full[k] = l
		heat[k] = h
		floor_y[k] = fl

	func update(dt: float) -> void:
		if n == 0 and not node.visible:
			return
		var drag := exp(-dt * 2.2)
		var grav := 13.0 * dt
		var k := 0
		while k < n:
			life[k] -= dt
			if life[k] <= 0.0:
				# dead: move the last live spark into this slot
				n -= 1
				if k != n:
					p[k] = p[n]
					v[k] = v[n]
					life[k] = life[n]
					full[k] = full[n]
					heat[k] = heat[n]
					floor_y[k] = floor_y[n]
				continue
			var w := v[k]
			w = Vector3(w.x * drag, w.y * drag - grav, w.z * drag)
			var q := p[k] + w * dt
			if q.y < floor_y[k] and w.y < 0.0:
				q.y = floor_y[k]
				w = Vector3(w.x * 0.55, w.y * -0.3, w.z * 0.55)
			p[k] = q
			v[k] = w
			# streak: the last ~40 ms of flight, at most 0.9 m
			var tl := minf(0.04, 0.9 / maxf(w.length(), 1e-3))
			var t := 1.0 - life[k] / full[k]
			CarEffects.put(buf, k, q, q - w * tl, 0.025, heat[k] * (1.0 - 0.8 * t), minf(1.0, 4.0 * (1.0 - t)))
			k += 1
		if cursor >= n:
			cursor = 0
		node.visible = n > 0
		node.multimesh.visible_instance_count = n
		if n > 0:
			node.multimesh.buffer = buf

	func clear() -> void:
		n = 0
		node.multimesh.visible_instance_count = 0
		node.visible = false


# =============================================================================
# Nitro flames
# =============================================================================

## Nitro flames for one car, shown while it boosts (strength car.boost): from each
## tail pipe a blue jet with a white core, flickering, easing in within ~0.1 s and out
## within ~0.25 s; and, with `glow`, a pooled trail of glowing blobs left in the world
## behind the pipes (fewer on lower quality, like the sparks). A ghost gets the jets only.
class NitroFlame:
	var pipes: Array          # [[Vector3 end in the car frame, radius], ...]
	var power := 0.0
	var time := 0.0
	var jets: MultiMeshInstance3D
	var jet_mat: ShaderMaterial
	var jet_buf := PackedFloat32Array()
	var glow: MultiMeshInstance3D = null
	var glow_mat: ShaderMaterial
	var glow_buf := PackedFloat32Array()
	var p := PackedVector3Array()
	var v := PackedVector3Array()
	var life := PackedFloat32Array()
	var full := PackedFloat32Array()
	var size := PackedFloat32Array()
	var next := 0
	var acc := 0.0
	var pipe := 0
	var alive := 0

	func _init(p_pipes: Array, with_glow: bool) -> void:
		pipes = p_pipes
		var n := pipes.size() * 2 # a blue layer and a white core per pipe
		jet_mat = CarEffects.shader_mat(CarEffects.JET_SHADER)
		jets = CarEffects.pool_node("streak", n, jet_mat, "NitroJets")
		jets.multimesh.visible_instance_count = n
		jet_buf.resize(n * CarEffects.FLOATS)
		if with_glow:
			glow_mat = CarEffects.shader_mat(CarEffects.GLOW_SHADER)
			glow = CarEffects.pool_node("disc", CarEffects.FLAME_POOL, glow_mat, "NitroGlow")
			glow.multimesh.visible_instance_count = CarEffects.FLAME_POOL
			glow_buf.resize(CarEffects.FLAME_POOL * CarEffects.FLOATS)
			p.resize(CarEffects.FLAME_POOL)
			v.resize(CarEffects.FLAME_POOL)
			life.resize(CarEffects.FLAME_POOL)
			full.resize(CarEffects.FLAME_POOL)
			full.fill(1.0)
			size.resize(CarEffects.FLAME_POOL)

	## car: the drawn car; xf: the car's world transform.
	func update(car: Pose, dt: float, xf: Transform3D) -> void:
		var want := clampf(car.boost if car.has_boost else (1.0 if car.boosting else 0.0), 0.0, 1.0)
		power += (want - power) * (1.0 - exp(-dt * (30.0 if want > power else 12.0)))
		if want == 0.0 and power < 0.01:
			power = 0.0
		time = fmod(time + dt, 600.0)
		var on := power > 0.0
		jets.visible = on
		if on:
			var back := -xf.basis.z.normalized() # backwards along the car
			var t := time
			var P := power
			for k in pipes.size():
				var r: float = pipes[k][1]
				var w: Vector3 = xf * (pipes[k][0] as Vector3)
				# length grows with the boost and flickers; thicker pipes give bigger jets
				var f := 0.86 + 0.14 * sin(t * 47.0 + k * 1.7) * sin(t * 29.0 + k * 3.1)
				var length := (0.6 + 1.4 * P) * f * (r / 0.05)
				for layer in 2:
					var l := length * 0.45 if layer == 1 else length
					CarEffects.put(jet_buf, k * 2 + layer, w, w + back * l, r * (1.25 if layer == 1 else 3.0) * (0.75 + 0.25 * P),
						P * (0.9 if layer == 1 else 1.0), float(layer))
			jets.multimesh.buffer = jet_buf
		if glow != null:
			_update_glow(car, dt, xf)

	func _update_glow(car: Pose, dt: float, xf: Transform3D) -> void:
		# new blobs at the pipes, spread over the frame so a slow frame doesn't leave clumps
		acc += dt * CarEffects.FLAME_RATE * power * CarEffects.spark_share
		if power == 0.0:
			acc = 0.0
		var fx := sin(car.yaw)
		var fz := cos(car.yaw)
		while acc >= 1.0:
			acc -= 1.0
			var r: float = pipes[pipe][1]
			var w: Vector3 = xf * (pipes[pipe][0] as Vector3)
			pipe = (pipe + 1) % pipes.size()
			var k := next
			next = (next + 1) % CarEffects.FLAME_POOL
			var out := 6.0 + randf() * 4.0 # m/s out of the pipe
			var vel := Vector3(car.vx * 0.7 - fx * out + (randf() - 0.5) * 1.2, 0.3 + randf() * 0.6, car.vz * 0.7 - fz * out + (randf() - 0.5) * 1.2)
			v[k] = vel
			var age := randf() * dt
			p[k] = Vector3(w.x + (vel.x - car.vx) * age - fx * 0.3, w.y, w.z + (vel.z - car.vz) * age - fz * 0.3)
			life[k] = 0.14 + randf() * 0.14
			full[k] = life[k]
			size[k] = (0.4 + randf() * 0.25) * (r / 0.05) * (0.6 + 0.4 * power)
		if alive == 0 and power == 0.0:
			return
		var n := 0
		var drag := exp(-dt * 3.0)
		for k in CarEffects.FLAME_POOL:
			if life[k] > 0.0:
				life[k] -= dt
				v[k] *= drag
				p[k] += v[k] * dt
			var a := life[k] / full[k] if life[k] > 0.0 else 0.0 # 1 fresh .. 0 gone
			CarEffects.put(glow_buf, k, p[k], Vector3.ZERO, size[k] * (0.45 + 0.55 * a), a * a)
			if a > 0.0:
				n += 1
		alive = n
		glow.visible = n > 0
		if n > 0:
			glow.multimesh.buffer = glow_buf

	## The ghost's fade (0..1).
	func set_opacity(o: float) -> void:
		jet_mat.set_shader_parameter("opacity", o)
		if glow_mat != null:
			glow_mat.set_shader_parameter("opacity", o)

	## Put out at once (restart / respawn).
	func clear() -> void:
		power = 0.0
		acc = 0.0
		jets.visible = false
		if glow != null:
			life.fill(0.0)
			alive = 0
			glow.visible = false
