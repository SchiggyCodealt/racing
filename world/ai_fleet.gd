class_name AIFleet
extends Node3D
## ai_fleet.gd (AIFleet of web/src/game/carMesh.js)
## ------------------------------------------------------------------
## Many cars (an AI training population) drawn with two MultiMeshes: the
## racer's paint (one colour per car) and its dark parts (carbon, canopy,
## plain wheels). The viewed car gets a floating marker and a glowing ring
## on the road; wall sparks come from one pool shared by the whole fleet.
##
## Use:
##   var fleet := AIFleet.new(80)
##   world.add_child(fleet)
##   fleet.update(agents, track, selected, time, alpha)   # every drawn frame
##   fleet.selected_view                                  # interpolated copy of the viewed car (chase camera)
##   fleet.pick(camera, screen_pos)                       # agent index under the pointer, or -1
## An agent is an Object or Dictionary with `car` (the car state, see
## CarEffects.Pose), `prev` (the state one physics step before, or null) and
## `alive` (bool).

const Geo = preload("res://world/geo.gd")
const Shapes = preload("res://world/car_shapes.gd")

const FLEET_SPARKS := 240      # spark pool shared by every car of the fleet
const FLEET_SPARK_FRAME := 40  # most new sparks per frame for the whole fleet (high quality)

var count := 0
var body: MultiMeshInstance3D
var dark: MultiMeshInstance3D
var marker: MeshInstance3D
var ring: MeshInstance3D
var sparks: CarEffects.Sparks
## Interpolated copy of the selected agent's car (for a smooth chase camera), or null.
var selected_view: Dictionary = {}
var has_selected_view := false

var _wall: Array[CarEffects.WallState] = []
var _spark_from := 0
var _poses := PackedFloat32Array()
var _show := PackedByteArray()
var _was := PackedByteArray()
var _spots := PackedFloat32Array()
var _n_spots := 0
var _time := -1.0
var _pose := CarEffects.Pose.new()
var _ring_mat: StandardMaterial3D
var _buf_body := PackedFloat32Array()
var _buf_dark := PackedFloat32Array()


func _init(max_count := 80) -> void:
	name = "ai-fleet"
	count = max_count
	var shape := Shapes.shape_of("racer")
	var paint := Shapes.paint_geometry(shape, 0)
	var parts: Array = [Shapes.carbon_geometry(shape, 0), Shapes.loft(Shapes.canopy_stations(), 10, 1)]
	for w: Array in Shapes.WHEELS:
		var R: float = w[2]
		parts.append(Geo.cylinder(R, R, w[3], 10).rotate_z(PI / 2.0).translate(w[0], R, w[1]))
	var dark_geo := Geo.merge(parts)

	var bm := StandardMaterial3D.new()
	bm.roughness = 0.38
	bm.metallic = 0.35
	bm.vertex_color_use_as_albedo = true  # the per-car colour (instance colour, sRGB)
	bm.vertex_color_is_srgb = true
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color.hex(0x16181dff)
	dm.roughness = 0.45
	dm.metallic = 0.3
	body = _mm(paint.to_mesh(bm, false, false), true, "fleet-body")
	dark = _mm(dark_geo.to_mesh(dm, false, false), false, "fleet-dark")
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	dark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(body)
	add_child(dark)

	# Selected car: a floating marker and a glowing ring on the road.
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color.hex(0xffd23fff)
	mm.emission_enabled = true
	mm.emission = Color.hex(0xffb300ff)
	mm.emission_energy_multiplier = 2.2
	mm.roughness = 0.3
	marker = MeshInstance3D.new()
	marker.name = "marker"
	marker.mesh = Geo.octahedron(0.55, 0).scale(1, 1.6, 1).to_mesh(mm, false, false)
	marker.top_level = true
	add_child(marker)
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.albedo_color = Color(1.0, 0.784, 0.239, 0.85)
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring_mat.render_priority = 2
	ring = MeshInstance3D.new()
	ring.name = "ring"
	ring.mesh = Geo.ring(2.7, 3.2, 40).rotate_x(-PI / 2.0).to_mesh(_ring_mat, false, false)
	ring.top_level = true
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	marker.visible = false
	ring.visible = false

	# Wall sparks for the whole fleet: one pool, at most FLEET_SPARK_FRAME new sparks a frame.
	sparks = CarEffects.Sparks.new(FLEET_SPARKS)
	add_child(sparks.node)
	for k in count:
		_wall.append(CarEffects.WallState.new())
	_poses.resize(count * 4)
	_show.resize(count)
	_was.resize(count)
	_spots.resize(count * 5)
	_buf_body.resize(count * 16)
	_buf_dark.resize(count * 12)


func _mm(mesh: Mesh, colors: bool, node_name: String) -> MultiMeshInstance3D:
	var m := MultiMesh.new()
	m.transform_format = MultiMesh.TRANSFORM_3D
	m.use_colors = colors
	m.mesh = mesh
	m.instance_count = count
	var mi := MultiMeshInstance3D.new()
	mi.name = node_name
	mi.multimesh = m
	mi.top_level = true
	return mi


## agents: see the header; selected: index of the viewed car; time: seconds;
## alpha: interpolation between agent.prev and agent.car (0..1).
func update(agents: Array, track: BuiltTrack, selected: int, time: float, alpha := 1.0) -> void:
	has_selected_view = false
	# A car inside the body of a car already drawn is not drawn: at every run start the
	# whole population sits on the grid, identical clones (elites) drive identical lines
	# (their bodies would z-fight as flickering stripes), and with the 'ride' wall rule a
	# trained pack presses into the same wall line a metre or two apart (a column of
	# bodies drawn through each other). Spots are claimed in a stable order, so the same
	# car stays the one drawn (no colour flicker as the pack leaves the grid): the viewed
	# car first, then the cars drawn last frame (they stay until they sit half inside one
	# already drawn), then the rest, which only appear once their body is clear of every
	# car drawn (hysteresis: no on/off flicker).
	var n := count
	_n_spots = 0
	for k in n:
		_show[k] = 0
		if k >= agents.size() or agents[k] == null:
			continue
		var a: Variant = agents[k]
		if not _alive(a) and k != selected:
			continue
		_posed(a, alpha, k)
		_show[k] = 2  # candidate
	if selected >= 0 and selected < n and _show[selected] == 2:
		_show[selected] = _claim(selected, 0.0, 0.0, 0.0)
	for k in n:
		if _show[k] == 2 and _was[k]:
			_show[k] = _claim(k, 2.2, 0.8, 0.35)
	for k in n:
		if _show[k] == 2:
			_show[k] = _claim(k, 4.4, 1.9, 0.5)
	_was = _show.duplicate()
	var hidden_at := Vector3(track.px[0], track.py[0], track.pz[0])
	var sel_xf := Transform3D()
	for k in n:
		var xf := Transform3D(Basis.from_scale(Vector3.ZERO), hidden_at)  # hidden: zero scale, parked at the start
		var col := Color(0, 0, 0)
		if _show[k]:
			var a: Variant = agents[k]
			var car := _pose.read(_field(a, "car"))
			var x := _poses[k * 4]
			var y := _poses[k * 4 + 1]
			var z := _poses[k * 4 + 2]
			var yaw := _poses[k * 4 + 3]
			var tilt := _tilt(car, track)
			xf = Transform3D(Basis.from_euler(Vector3(-tilt.x, yaw, tilt.y), EULER_ORDER_YXZ), Vector3(x, y, z))
			if k == selected:
				col = Color.hex(0xffc83dff)
			elif not _alive(a):
				col = Color.hex(0x6a6d73ff)
			else:
				col = _hsl(fmod(k * 0.137, 1.0), 0.7, 0.5)
			if k == selected:
				var src: Variant = _field(a, "car")
				var v := {}
				if src is Dictionary:
					v = (src as Dictionary).duplicate()
				elif src is Object:
					for p: Dictionary in (src as Object).get_property_list():
						if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
							v[p["name"]] = (src as Object).get(p["name"])
				v["x"] = x
				v["y"] = y
				v["z"] = z
				v["yaw"] = yaw
				selected_view = v
				has_selected_view = true
				sel_xf = Transform3D(Basis.from_euler(Vector3(-tilt.x, yaw, tilt.y), EULER_ORDER_YXZ), Vector3(x, y + 0.05, z))
		_put(_buf_body, k * 16, xf, col, true)
		_put(_buf_dark, k * 12, xf, col, false)
	body.multimesh.buffer = _buf_body
	dark.multimesh.buffer = _buf_dark

	marker.visible = has_selected_view
	ring.visible = has_selected_view
	if has_selected_view:
		marker.position = Vector3(selected_view["x"], float(selected_view["y"]) + 4.4 + sin(time * 4.0) * 0.3, selected_view["z"])
		marker.rotation = Vector3(0, time * 2.0, 0)
		ring.transform = sel_xf
		_ring_mat.albedo_color.a = 0.55 + 0.3 * sin(time * 6.0)

	# Sparks from the cars drawn: the viewed car first, then the others from a
	# starting point that moves on every frame, so a full budget is shared out.
	var dt := 0.0 if _time < 0.0 else clampf(time - _time, 0.0, 0.1)
	_time = time
	var budget := roundi(FLEET_SPARK_FRAME * CarEffects.spark_share)
	_spark_from = (_spark_from + 7) % maxi(1, n)
	for q in range(-1, n):
		var k := selected if q < 0 else (_spark_from + q) % n
		if k < 0 or k >= n or (q >= 0 and k == selected):
			continue
		var st := _wall[k]
		if not _show[k]:
			st.ready = false
			continue
		var car := _pose.read(_field(agents[k], "car"))
		var steps := CarEffects.wall_events(st, car)
		if steps > 0 and budget > 0:
			budget -= CarEffects.emit_sparks(sparks, st, steps, car, _poses[k * 4], _poses[k * 4 + 1], _poses[k * 4 + 2],
				_poses[k * 4 + 3], mini(budget, 24), 0.5)
	sparks.update(dt)


## True when agent k's car was drawn on the last update (alive, and not merged into a car drawn on the same spot).
func is_drawn(k: int) -> bool:
	return k >= 0 and k < count and _show[k] != 0


## The agent index under the screen point (e.g. the mouse), or -1.
func pick(cam: Camera3D, screen_pos: Vector2) -> int:
	var o := cam.project_ray_origin(screen_pos)
	var d := cam.project_ray_normal(screen_pos)
	var best := -1
	var best_t := INF
	var box := AABB(Vector3(-1.05, 0.0, -2.35), Vector3(2.1, 1.25, 4.7))
	for k in count:
		if not _show[k]:
			continue
		var xf := Transform3D(Basis(Vector3.UP, _poses[k * 4 + 3]), Vector3(_poses[k * 4], _poses[k * 4 + 1], _poses[k * 4 + 2]))
		var inv := xf.affine_inverse()
		var hit: Variant = box.intersects_ray(inv * o, inv.basis * d)
		if hit != null:
			var t := ((hit as Vector3) - inv * o).length()
			if t < best_t:
				best_t = t
				best = k
	return best


# k is merged into a car already drawn when its centre lies within ±along × ±across
# of that car (in its frame: 4.4 × 2 m body) at a heading within yaw_lim.
func _claim(k: int, along: float, across: float, yaw_lim: float) -> int:
	var x := _poses[k * 4]
	var z := _poses[k * 4 + 2]
	var yaw := _poses[k * 4 + 3]
	var r2 := along * along + across * across
	for j in range(0, _n_spots * 5, 5):
		var dx := x - _spots[j]
		var dz := z - _spots[j + 1]
		if dx * dx + dz * dz >= r2:
			continue
		var s := _spots[j + 3]
		var c := _spots[j + 4]
		if absf(dx * s + dz * c) >= along or absf(dx * c - dz * s) >= across:
			continue
		if absf(angle_difference(_spots[j + 2], yaw)) < yaw_lim:
			return 0
	var j := _n_spots * 5
	_n_spots += 1
	_spots[j] = x
	_spots[j + 1] = z
	_spots[j + 2] = yaw
	_spots[j + 3] = sin(yaw)
	_spots[j + 4] = cos(yaw)
	return 1


## Interpolated pose of agent a's car between a.prev and a.car, into _poses[k].
func _posed(a: Variant, alpha: float, k: int) -> void:
	var car: Variant = _field(a, "car")
	var p: Variant = _field(a, "prev")
	var x := float(car.get("x"))
	var y := float(car.get("y"))
	var z := float(car.get("z"))
	var yaw := float(car.get("yaw"))
	if p != null and alpha < 1.0:
		var px := float(p.get("x"))
		var py := float(p.get("y"))
		var pz := float(p.get("z"))
		var pyaw := float(p.get("yaw"))
		x = px + (x - px) * alpha
		y = py + (y - py) * alpha
		z = pz + (z - pz) * alpha
		yaw = pyaw + angle_difference(pyaw, yaw) * alpha
	_poses[k * 4] = x
	_poses[k * 4 + 1] = y
	_poses[k * 4 + 2] = z
	_poses[k * 4 + 3] = yaw


static func _field(a: Variant, key: String) -> Variant:
	if a is Dictionary:
		return (a as Dictionary).get(key)
	return (a as Object).get(key)


static func _alive(a: Variant) -> bool:
	var v: Variant = _field(a, "alive")
	return v == null or bool(v)


## Body attitude (x = pitch, y = roll) from the car state or the road under it.
static func _tilt(car: CarEffects.Pose, track: BuiltTrack) -> Vector2:
	if car.has_att:
		return Vector2(car.pitch, car.roll)
	if car.idx < 0:
		return Vector2.ZERO
	var i := clampi(car.idx, 0, track.count - 1)
	var j := (i + 1) % track.N if track.closed else mini(i + 1, track.count - 1)
	var slope := (track.py[j] - track.py[i]) / track.seg_len
	var rel := cos(car.yaw - atan2(track.tx[i], track.tz[i]))
	return Vector2(atan(slope * rel), -track.bank[i] * rel)


## Three.js Color.setHSL (sRGB).
static func _hsl(h: float, s: float, l: float) -> Color:
	var q := l * (1.0 + s) if l <= 0.5 else l + s - l * s
	var p := 2.0 * l - q
	return Color(_hue(p, q, h + 1.0 / 3.0), _hue(p, q, h), _hue(p, q, h - 1.0 / 3.0))


static func _hue(p: float, q: float, t: float) -> float:
	if t < 0.0:
		t += 1.0
	if t > 1.0:
		t -= 1.0
	if t < 1.0 / 6.0:
		return p + (q - p) * 6.0 * t
	if t < 0.5:
		return q
	if t < 2.0 / 3.0:
		return p + (q - p) * 6.0 * (2.0 / 3.0 - t)
	return p


static func _put(buf: PackedFloat32Array, o: int, xf: Transform3D, c: Color, with_color: bool) -> void:
	var b := xf.basis
	buf[o] = b.x.x
	buf[o + 1] = b.y.x
	buf[o + 2] = b.z.x
	buf[o + 3] = xf.origin.x
	buf[o + 4] = b.x.y
	buf[o + 5] = b.y.y
	buf[o + 6] = b.z.y
	buf[o + 7] = xf.origin.y
	buf[o + 8] = b.x.z
	buf[o + 9] = b.y.z
	buf[o + 10] = b.z.z
	buf[o + 11] = xf.origin.z
	if with_color:
		buf[o + 12] = c.r
		buf[o + 13] = c.g
		buf[o + 14] = c.b
		buf[o + 15] = 1.0
