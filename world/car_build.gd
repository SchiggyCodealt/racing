## car_build.gd
## ------------------------------------------------------------------
## Turns a car shape (world/car_shapes.gd) into the whole detailed car, as
## one skinned mesh (world/car_kit.gd) plus its see-through glass, and the rig
## that world/car_model.gd poses every frame:
##   - body: panels, livery, carbon parts, lamps with bezels, mirrors with
##     glass, exhaust tips, louvres, panel lines (drawn by the shader from the
##     shape's seams), race-number roundels, cockpit floor, seats, dash, cages
##   - wheels: tyre, rim with the car's spoke count and colour, brake disc
##     (they spin); caliper and hub carrier (they steer and travel); upper and
##     lower suspension arms that stretch between the body and the wheel
##     (blended bones), coil-overs on the buggy
##   - the driver: torso, helmet with visor and stripe, arms and gloves on a
##     steering wheel (bones: torso, head, upper arm and forearm each side)
## detail 1 is the full car, 0 a lighter one for low graphics quality.
##
##   var car := CarBuild.build("vortex", 1)  # {opaque: CarKit, glass: CarKit, rig: {...}} (cached)
##   CarBuild.profile("dune")                 # side view for the car picker
##   CarBuild.fleet_geometry("racer")         # {paint: Geo, dark: Geo} for the AI fleet's MultiMeshes
##
## Car frame: x = left, y = up, z = forward, the origin on the road between the axles.
extends RefCounted

const Geo = preload("res://world/geo.gd")
const Shapes = preload("res://world/car_shapes.gd")
const Kit = preload("res://world/car_kit.gd")

## The driver's proportions (m).
const UPPER_ARM := 0.29
const FOREARM := 0.3        # elbow to the middle of the fist
const SHOULDER_UP := 0.46   # hip to shoulder line, along the back
const SHOULDER_W := 0.2     # half the shoulder width
const HEAD_UP := 0.72       # hip to the middle of the head, along the back
const HELMET_R := 0.125
const WHEEL_R := 0.135      # steering wheel radius
const REACH := 0.46         # longest shoulder-to-hand distance at rest (the arms are 0.59 m: room to turn the wheel)

static var _cache: Dictionary = {}
static var _digits: Dictionary = {}


# =============================================================================
# public
# =============================================================================

## The whole car `id` at `detail` (1 full, 0 light), built once and cached.
static func build(id: String, detail := 1) -> Dictionary:
	var key := "%s:%d" % [id, detail]
	if _cache.has(key):
		return _cache[key]
	var s := Shapes.shape_of(id)
	var opaque := Kit.new()
	var glass := Kit.new()
	var rig := _rig(s)
	_body(opaque, s, detail, rig)
	for i in rig["wheels"].size():
		_wheel(opaque, s, detail, rig, i)
	_steering_wheel(opaque, detail, rig)
	_driver(opaque, s, detail, rig)
	glass.add(Shapes.glass_geometry(s, detail), Kit.PAINT, Kit.BODY)
	var out := {"opaque": opaque, "glass": glass, "rig": rig}
	_cache[key] = out
	return out


## Where the driver, the wheels and the moving parts of car `id` are (no geometry).
static func rig(id: String) -> Dictionary:
	return build(id, 0)["rig"]


## Linear colour from 0xRRGGBB.
static func lin(hex: int) -> Color:
	return Color.hex((hex << 8) | 0xff).srgb_to_linear()


# =============================================================================
# rig: where things are
# =============================================================================

static func _rig(s: Dictionary) -> Dictionary:
	var wheels := []
	for w in Shapes.wheel_layout(s):
		wheels.append({"c": Vector3(w[0], w[2], w[1]), "r": w[2], "w": w[3], "front": w[4]})
	var hip_d: Array = s["hip"]
	var lean: float = s["lean"]
	var hip := Shapes.warp_point(s, hip_d[0], hip_d[2], hip_d[1])
	var u := Vector3(0, cos(lean), -sin(lean))   # up the driver's back
	var f := Vector3(0, sin(lean), cos(lean))    # out of the chest
	var glass_geo := Shapes.glass_geometry(s, 0)
	var roof := INF
	if not s["open"] and glass_geo.pos.size() > 0:
		# sit low enough that the helmet clears the canopy or roof by 3 cm
		var head := hip + u * HEAD_UP + f * 0.03
		var top := _surface_y([glass_geo] + _roof_parts(s), head.x, head.z, -1.0)
		if top < INF:
			roof = top
			var over := head.y + HELMET_R + 0.03 - top
			if over > 0.0:
				hip.y -= over
	var wd: Array = s["wheel"]
	var wc := Shapes.warp_point(s, hip_d[0], wd[1], wd[0])
	wc.x = hip.x
	var tilt: float = wd[2]
	var wb := Basis(Vector3(1, 0, 0), Vector3(0, cos(tilt), sin(tilt)), Vector3(0, -sin(tilt), cos(tilt)))
	var shoulders := [hip + u * SHOULDER_UP + Vector3(SHOULDER_W, 0, 0), hip + u * SHOULDER_UP - Vector3(SHOULDER_W, 0, 0)]
	# a wheel out of reach comes towards the driver
	for side in 2:
		var grip: Vector3 = wc + wb.x * (WHEEL_R if side == 0 else -WHEEL_R)
		var d: float = grip.distance_to(shoulders[side])
		if d > REACH:
			var mid: Vector3 = (shoulders[0] + shoulders[1]) * 0.5
			wc += (mid - wc).normalized() * (d - REACH)
	var hands := [wc + wb.x * WHEEL_R, wc - wb.x * WHEEL_R]
	var poles := [Vector3(0.55, -0.8, -0.1).normalized(), Vector3(-0.55, -0.8, -0.1).normalized()]
	var elbows := []
	for side in 2:
		elbows.append(ik(shoulders[side], hands[side], UPPER_ARM, FOREARM, poles[side])[0])
	var head_c := hip + u * HEAD_UP + f * 0.03
	var flap := Vector3.ZERO
	for p in s["parts"]:
		if String(p.get("bone", "")) == "flap" and p.has("wing"):
			flap = Shapes.warp_point(s, 0, p["at"][1], p["at"][2])
	var seams := []
	for m in s["seams"]:
		var axis: int = m[0]
		if axis == 0:
			seams.append([0, _wz(s, m[1]), m[2] * s["width"], m[3] * s["width"], _wy(s, m[4]), _wy(s, m[5])])
		else:
			seams.append([1, m[1] * s["width"], _wz(s, m[2]), _wz(s, m[3]), _wy(s, m[4]), _wy(s, m[5])])
	return {
		"wheels": wheels, "hip": hip, "u": u, "f": f, "lean": lean, "neck": hip + u * 0.58, "head": head_c,
		"shoulders": shoulders, "elbows": elbows, "hands": hands, "poles": poles,
		"wheel_c": wc, "wheel_basis": wb, "open": s["open"], "roof": roof, "flap": flap, "seams": seams,
		"nozzles": Shapes.nozzles(s),
	}


static func _wz(s: Dictionary, z: float) -> float:
	return z * (s["front"] if z > 0.0 else s["rear"])


static func _wy(s: Dictionary, y: float) -> float:
	return s["lift"] + y * s["height"]


## The painted roof parts of a shape (the rally car's roof), warped.
static func _roof_parts(s: Dictionary) -> Array:
	var out := []
	for g in Shapes.part_geometries(s, "paint", 0, ""):
		var gg: Geo = g
		if gg.aabb().position.y > 1.0:
			out.append(Shapes.warp(gg, s))
	return out


## Two-bone IK: the elbow for a shoulder at `s` reaching `t` with arm lengths a and b, the
## elbow pushed towards `pole`. Returns [elbow, hand] (the hand pulled in when out of reach).
static func ik(s: Vector3, t: Vector3, a: float, b: float, pole: Vector3) -> Array:
	var v := t - s
	var dist := v.length()
	var dir := v / dist if dist > 1e-6 else Vector3.FORWARD
	var d := clampf(dist, absf(a - b) + 1e-3, a + b - 1e-3)
	var x := (a * a - b * b + d * d) / (2.0 * d)
	var h := sqrt(maxf(0.0, a * a - x * x))
	var p := pole - dir * pole.dot(dir)
	p = p.normalized() if p.length_squared() > 1e-9 else Vector3.DOWN
	return [s + dir * x + p * h, s + dir * d]


# =============================================================================
# geometry helpers
# =============================================================================

## A round tube from a to b (radius ra at a, rb at b).
static func tube(a: Vector3, b: Vector3, ra: float, rb := -1.0, seg := 8, caps := true) -> Geo:
	var d := b - a
	var len := d.length()
	var g := Geo.cylinder(rb if rb > 0.0 else ra, ra, len, seg, 1, not caps) # top (+y) at b
	var y := d / len
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	return g.xform(Transform3D(Basis(x, y, z), (a + b) * 0.5))


## Nearest surface hit of the line through `o` along `dir` among some geometries (the hit
## point's coordinate along -dir is returned as the distance t), INF when none.
static func _ray(geos: Array, o: Vector3, dir: Vector3) -> float:
	var best := INF
	for g in geos:
		var gg: Geo = g
		var n := gg.idx.size() if gg.indexed else gg.pos.size()
		for t in range(0, n - 2, 3):
			var a := gg.pos[gg.idx[t]] if gg.indexed else gg.pos[t]
			var b := gg.pos[gg.idx[t + 1]] if gg.indexed else gg.pos[t + 1]
			var c := gg.pos[gg.idx[t + 2]] if gg.indexed else gg.pos[t + 2]
			var e1 := b - a
			var e2 := c - a
			var p := dir.cross(e2)
			var det := e1.dot(p)
			if absf(det) < 1e-12:
				continue
			var inv := 1.0 / det
			var tv := o - a
			var uu := tv.dot(p) * inv
			if uu < 0.0 or uu > 1.0:
				continue
			var q := tv.cross(e1)
			var vv := dir.dot(q) * inv
			if vv < 0.0 or uu + vv > 1.0:
				continue
			var hit := e2.dot(q) * inv
			if hit > 0.0 and hit < best:
				best = hit
	return best


## Height of the top surface at (x, z) (dir -1: from above), or INF.
static func _surface_y(geos: Array, x: float, z: float, dir := -1.0) -> float:
	var t := _ray(geos, Vector3(x, 10.0 if dir < 0.0 else -10.0, z), Vector3(0, dir, 0))
	return 10.0 + dir * t if t < INF else INF


## The outer side surface x at (y, z) on side `sx` (+1 left, -1 right), or NAN.
static func _surface_x(geos: Array, y: float, z: float, sx: float) -> float:
	var t := _ray(geos, Vector3(sx * 5.0, y, z), Vector3(-sx, 0, 0))
	return sx * (5.0 - t) if t < INF else NAN


## The race number as flat geometry (the Barlow Condensed digits, 1 m tall, centred, facing +z).
static func number_geometry(text: String, detail: int) -> Geo:
	var key := "%s:%d" % [text, detail]
	if _digits.has(key):
		return (_digits[key] as Geo).duplicate_geo()
	var g := Geo.new()
	var font: Font = load("res://assets/fonts/BarlowCondensed-Bold.woff2") if ResourceLoader.exists("res://assets/fonts/BarlowCondensed-Bold.woff2") else null
	var tm := TextMesh.new()
	if font != null:
		tm.font = font
	tm.text = text
	tm.font_size = 64
	tm.pixel_size = 0.01
	tm.depth = 0.0
	tm.curve_step = 4.0 if detail else 8.0
	var arr := tm.get_mesh_arrays()
	if arr.size() > Mesh.ARRAY_INDEX and arr[Mesh.ARRAY_VERTEX] != null:
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var b := AABB(v[0], Vector3.ZERO) if v.size() > 0 else AABB()
		for p in v:
			b = b.expand(p)
		var k := 1.0 / maxf(b.size.y, 1e-3)
		var c := b.get_center()
		for p in v:
			g.pos.append(Vector3((p.x - c.x) * k, (p.y - c.y) * k, 0.0))
			g.nor.append(Vector3.BACK)
		if ix.is_empty():
			for t in range(0, v.size() - 2, 3):
				ix.append_array([t, t + 1, t + 2])
		# Godot winding (clockwise) to the Geo's counter-clockwise
		for t in range(0, ix.size() - 2, 3):
			g.idx.append_array([ix[t], ix[t + 2], ix[t + 1]])
	_digits[key] = g
	return g.duplicate_geo()


# =============================================================================
# body
# =============================================================================

static func _body(kit: Kit, s: Dictionary, detail: int, rig: Dictionary) -> void:
	var B := Kit.BODY
	var panels := Shapes.body_panels(s, detail)
	var warped := {}
	for k: String in panels:
		warped[k] = Shapes.warp(panels[k], s)
	# the cockpit: an opening in the top of the tub (the shape's tray) with a well under it
	var well := _well_rect(s, rig)
	for k: String in warped:
		kit.add(_cut(warped[k], well, true) if k == "tub" else warped[k], Kit.PAINT, B)
	for g in Shapes.part_geometries(s, "paint", detail, ""):
		kit.add(Shapes.warp(g, s), Kit.PAINT, B)
	kit.add(_cut(Shapes.stripe_geometry(s), well, false), Kit.STRIPE, B)
	kit.add(Shapes.carbon_geometry(s, detail, false, ""), Kit.CARBON, B, lin(0x17191e))
	var acc := Shapes.accent_geometry(s, detail, "")
	if acc != null:
		kit.add(acc, Kit.ACCENT, B)
	# the active wing (the Vortex): its own bone
	for g in Shapes.part_geometries(s, "carbon", detail, "flap"):
		kit.add(Shapes.warp(g, s), Kit.CARBON, Kit.FLAP, lin(0x17191e))
	for g in Shapes.part_geometries(s, "accent", detail, "flap"):
		kit.add(Shapes.warp(g, s), Kit.ACCENT, Kit.FLAP)
	# lamps
	var lights := Shapes.light_geometries(s, detail)
	kit.add(lights["head"], Kit.HEAD, B)
	kit.add(lights["tail"], Kit.TAIL, B)
	kit.add(lights["housing"], Kit.CARBON, B, lin(0x0b0c0f))
	# mirrors: shell in the body colour, a glass face looking back
	var m: Array = s["mirror"]
	if not m.is_empty():
		kit.add(Shapes.mirror_geometry(s), Kit.PAINT, B)
		for sx in [1.0, -1.0]:
			var mp := Shapes.warp_point(s, sx * m[0], m[1], m[2] - 0.075)
			kit.add(Geo.sphere(0.062, 10 if detail else 6, 5).scale(1.35, 0.62, 0.15).translate(mp.x, mp.y, mp.z), Kit.DARK_GLASS, B, lin(0x2a3442))
	# exhaust tips: a bright ring round a dark pipe
	for e in s["exhausts"]:
		var ep := Shapes.warp_point(s, e[0], e[1], e[2])
		var r: float = e[3]
		var seg := 14 if detail else 8
		kit.add(Geo.cylinder(r, r, 0.18, seg, 1, true).rotate_x(PI / 2.0).translate(ep.x, ep.y, ep.z + 0.09), Kit.METAL, B, lin(0xb8bcc4))
		kit.add(Geo.cylinder(r * 0.78, r * 0.78, 0.16, seg, 1, false).rotate_x(PI / 2.0).translate(ep.x, ep.y, ep.z + 0.1), Kit.CARBON, B, lin(0x050506))
	var body_geos: Array = warped.values()
	_louvres(kit, s, detail, body_geos)
	_numbers(kit, s, detail, warped)
	_cockpit(kit, s, detail, rig, warped)
	# tubes in the car's own frame: cages and bars
	for t in s["tubes"]:
		var a := Vector3(t[0], t[1], t[2])
		var b := Vector3(t[3], t[4], t[5])
		var sym: bool = t.size() > 7 and t[7]
		for sx in ([1.0, -1.0] if sym else [1.0]):
			kit.add(tube(Vector3(a.x * sx, a.y, a.z), Vector3(b.x * sx, b.y, b.z), t[6], -1.0, 10 if detail else 6), Kit.GLOSS, B, lin(s["cage"]))
	if s["lights"] == "buggy":
		# light bar on the cage, small tail lamps on the rear frame
		var top: Array = []
		for t in s["tubes"]:
			if not (t.size() > 7 and t[7]) and t[1] > 1.4 and t[2] > -0.2:
				top = t
		if not top.is_empty():
			var y: float = top[1] + 0.06
			var z: float = top[2] + 0.05
			kit.add(Shapes.box(0.74, 0.07, 0.07, 0, y, z), Kit.CARBON, B, lin(0x141518))
			for k in 4:
				var x := -0.27 + k * 0.18
				kit.add(Geo.cylinder(0.04, 0.04, 0.03, 10 if detail else 6).rotate_x(PI / 2.0).translate(x, y, z + 0.045), Kit.HEAD, B)
		for sx in [1.0, -1.0]:
			kit.add(Shapes.box(0.12, 0.06, 0.04, sx * 0.4, 0.92, -2.0), Kit.TAIL, B)


## Louvred vents on top of the body: dark slats over a darker recess.
static func _louvres(kit: Kit, s: Dictionary, detail: int, geos: Array) -> void:
	for v in s["vents"]:
		var n: int = v[4] if detail else maxi(2, int(v[4]) / 2)
		for sx in [1.0, -1.0]:
			var x: float = sx * float(v[0]) * float(s["width"])
			var zc := _wz(s, v[1])
			var len: float = float(v[2]) * (s["front"] if zc > 0.0 else s["rear"])
			var hw: float = float(v[3]) * float(s["width"])
			var y0 := _surface_y(geos, x, zc)
			if y0 == INF:
				continue
			var y1 := _surface_y(geos, x, zc + len * 0.5)
			var y2 := _surface_y(geos, x, zc - len * 0.5)
			var slope := atan2((y1 if y1 < INF else y0) - (y2 if y2 < INF else y0), len)
			kit.add(Shapes.box(hw * 2.0, 0.006, len, 0, 0, 0).rotate_x(-slope).translate(x, y0 + 0.004, zc), Kit.CARBON, Kit.BODY, lin(0x040405))
			for k in n:
				var z := zc - len * 0.5 + (k + 0.5) * len / n
				var y := y0 + (z - zc) * tan(slope)
				kit.add(Shapes.box(hw * 2.0, 0.012, len / n * 0.55, 0, 0, 0).rotate_x(0.45 - slope).translate(x, y + 0.012, z), Kit.CARBON, Kit.BODY, lin(0x15171b))


## The race number on a white roundel on each side (and on the bonnet of the cars that have one).
static func _numbers(kit: Kit, s: Dictionary, detail: int, warped: Dictionary) -> void:
	var dc: Array = s["decal"]
	var zc := _wz(s, dc[0])
	var yc := _wy(s, dc[1])
	var r: float = dc[2]
	var num := number_geometry(s["number"], detail)
	for sx in [1.0, -1.0]:
		var geos := []
		if s["pods"]:
			geos.append(warped["pod_l" if sx > 0.0 else "pod_r"])
		geos.append(warped["tub"])
		# the roundel sits flat just outside the bulgiest point of the panel under it
		var x := -INF
		for k in 9:
			var a := k / 8.0 * TAU
			var rr := 0.0 if k == 8 else r
			var px := _surface_x(geos, yc + rr * sin(a), zc + rr * cos(a), sx)
			if not is_nan(px):
				x = maxf(x, px * sx)
		if x == -INF:
			continue
		var rot := PI / 2.0 if sx > 0.0 else -PI / 2.0
		kit.add(Geo.circle(r, 28 if detail else 14).rotate_y(rot).translate(sx * (x + 0.005), yc, zc), Kit.GLOSS, Kit.BODY, lin(0xf4f4f0))
		var digits := num.duplicate_geo().scale(r * 1.15, r * 1.15, 1.0).rotate_y(rot).translate(sx * (x + 0.008), yc, zc)
		kit.add(digits, Kit.GLOSS, Kit.BODY, lin(0x111113))


## The cockpit opening of a shape with a tray: {z0, z1, hw, floor} in the car frame, {} without.
static func _well_rect(s: Dictionary, rig: Dictionary) -> Dictionary:
	var tray: Array = s["tray"]
	if tray.is_empty():
		return {}
	return {"z0": _wz(s, tray[0]), "z1": _wz(s, tray[1]), "hw": float(tray[2]) * float(s["width"]), "floor": float(rig["hip"].y) - 0.08}


## `g` without the triangles over the cockpit opening (top: only the upward-facing ones above
## the well floor; else every triangle wholly inside it). A new Geo; `g` itself when there is no well.
static func _cut(g: Geo, well: Dictionary, top: bool) -> Geo:
	if well.is_empty() or g == null:
		return g
	var z0: float = well["z0"]
	var z1: float = well["z1"]
	var hw: float = well["hw"]
	var fy: float = well["floor"] + 0.1
	var out := g.duplicate_geo()
	out.idx = PackedInt32Array()
	if not g.indexed:
		return g
	for t in range(0, g.idx.size() - 2, 3):
		var a := g.pos[g.idx[t]]
		var b := g.pos[g.idx[t + 1]]
		var c := g.pos[g.idx[t + 2]]
		var inside := true
		for p: Vector3 in [a, b, c]:
			if absf(p.x) > hw or p.z < z0 or p.z > z1 or (top and p.y < fy):
				inside = false
				break
		if inside and top and (b - a).cross(c - a).normalized().y < 0.2:
			inside = false
		if not inside:
			out.idx.append_array([g.idx[t], g.idx[t + 1], g.idx[t + 2]])
	return out


## Adds a quad a b c d (around its edge) facing `n`.
static func _quad(g: Geo, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	var k := g.pos.size()
	for p: Vector3 in [a, b, c, d]:
		g.pos.append(p)
		g.nor.append(n)
	if (b - a).cross(c - a).dot(n) >= 0.0:
		g.idx.append_array([k, k + 1, k + 2, k, k + 2, k + 3])
	else:
		g.idx.append_array([k, k + 2, k + 1, k, k + 3, k + 2])


## The cockpit: the well under the opening (floor and walls up to the tub's top), seats, the
## driver's legs.
static func _cockpit(kit: Kit, s: Dictionary, detail: int, rig: Dictionary, warped: Dictionary) -> void:
	var well := _well_rect(s, rig)
	if not well.is_empty():
		var z0: float = well["z0"]
		var z1: float = well["z1"]
		var hw: float = well["hw"]
		var fy: float = well["floor"]
		var tub := [warped["tub"]]
		var n := 8 if detail else 4
		var walls := Geo.new()
		# along the sides (x = +-hw) and across the ends (z = z0, z1); tops 5 mm over the tub's surface
		for side in 4:
			var prev := Vector3.INF
			for k in n + 1:
				var t := float(k) / n
				var p: Vector3
				var nn: Vector3
				if side < 2:
					var sx := 1.0 if side == 0 else -1.0
					p = Vector3(sx * hw, 0, lerpf(z0, z1, t))
					nn = Vector3(-sx, 0, 0)
				else:
					p = Vector3(lerpf(-hw, hw, t), 0, z0 if side == 2 else z1)
					nn = Vector3(0, 0, 1 if side == 2 else -1)
				var y := _surface_y(tub, p.x, p.z)
				if y == INF or y < fy + 0.02:
					prev = Vector3.INF
					continue
				p.y = y + 0.005
				if prev != Vector3.INF:
					_quad(walls, Vector3(prev.x, fy, prev.z), Vector3(p.x, fy, p.z), p, prev, nn)
				prev = p
		kit.add(walls, Kit.MATTE, Kit.BODY, lin(0x2a2c31))
		var fl := Geo.new()
		_quad(fl, Vector3(-hw, fy, z0), Vector3(hw, fy, z0), Vector3(hw, fy, z1), Vector3(-hw, fy, z1), Vector3.UP)
		kit.add(fl, Kit.MATTE, Kit.BODY, lin(0x1c1d21))
	# seats: a reclined bucket behind each seat position (the driver's when none are listed)
	var seats: Array = s["seats"]
	var hip: Vector3 = rig["hip"]
	var u: Vector3 = rig["u"]
	var f: Vector3 = rig["f"]
	if seats.is_empty():
		seats = [[hip.x / s["width"], 0.0]]
	var basis := Basis(Vector3(1, 0, 0), u, -f)
	for st in seats:
		var x: float = st[0] * s["width"]
		var o := Vector3(x, hip.y, hip.z) + u * 0.4 - f * 0.17
		kit.add(Shapes.box(0.5, 0.8, 0.07, 0, 0, 0).xform(Transform3D(basis, o)), Kit.MATTE, Kit.BODY, lin(0x17181b))
		kit.add(Shapes.box(0.12, 0.1, 0.08, 0, 0, 0).xform(Transform3D(basis, o + u * 0.32 + f * 0.01)), Kit.ACCENT, Kit.BODY)
		for sx in [1.0, -1.0]:
			kit.add(Shapes.box(0.06, 0.6, 0.16, 0, 0, 0).xform(Transform3D(basis, o + Vector3(sx * 0.26, 0, 0) - u * 0.05 + f * 0.06)), Kit.MATTE, Kit.BODY, lin(0x17181b))
		# the cushion under the thighs
		kit.add(Shapes.box(0.46, 0.06, 0.38, x, hip.y - 0.06, hip.z + 0.12), Kit.MATTE, Kit.BODY, lin(0x17181b))
	# the driver's legs (they don't move): thighs, shins, boots towards the pedals
	var suit := lin(s["suit"])
	var ring := 10 if detail else 6
	for sx in [1.0, -1.0]:
		var h := hip + Vector3(sx * 0.1, 0.02, 0.02)
		var knee := h + Vector3(sx * 0.02, 0.14, 0.4)
		var ankle := knee + Vector3(0, -0.12, 0.38)
		kit.add(tube(h, knee, 0.075, 0.06, ring), Kit.MATTE, Kit.BODY, suit)
		kit.add(Geo.sphere(0.06, ring, ring / 2).translate(knee.x, knee.y, knee.z), Kit.MATTE, Kit.BODY, suit)
		kit.add(tube(knee, ankle, 0.058, 0.045, ring), Kit.MATTE, Kit.BODY, suit)
		kit.add(Shapes.box(0.09, 0.13, 0.2, ankle.x, ankle.y + 0.02, ankle.z + 0.06), Kit.MATTE, Kit.BODY, lin(0x111214))


# =============================================================================
# wheels and suspension
# =============================================================================

static func _wheel(kit: Kit, s: Dictionary, detail: int, rig: Dictionary, i: int) -> void:
	var wd: Dictionary = rig["wheels"][i]
	var c: Vector3 = wd["c"]
	var R: float = wd["r"]
	var W: float = wd["w"]
	var sx := signf(c.x)
	var seg := 28 if detail else 16
	var spin := Kit.SPIN0 + i
	var up := Kit.UPRIGHT0 + i
	# everything is laid out facing +x (the outside of a left wheel), then turned for the right side
	var xf := Transform3D(Basis(Vector3.UP, 0.0 if sx > 0.0 else PI), c)
	# tyre: rounded shoulders and two tread grooves
	var tp := PackedVector2Array([Vector2(R * 0.66, -W / 2), Vector2(R - 0.05, -W / 2), Vector2(R - 0.012, -W / 2 + 0.03),
		Vector2(R, -W / 2 + 0.08)])
	if detail:
		for gz in [-0.17, 0.17]:
			var z0: float = gz * W - 0.012
			tp.append(Vector2(R, z0))
			tp.append(Vector2(R - 0.012, z0 + 0.004))
			tp.append(Vector2(R - 0.012, z0 + 0.02))
			tp.append(Vector2(R, z0 + 0.024))
	tp.append_array([Vector2(R, W / 2 - 0.08), Vector2(R - 0.012, W / 2 - 0.03), Vector2(R - 0.05, W / 2), Vector2(R * 0.66, W / 2)])
	kit.add(Geo.lathe(tp, seg).rotate_z(-PI / 2.0).xform(xf), Kit.TYRE, spin, lin(0x1c1c1e))
	# rim: lip, dished barrel, spokes, centre cap
	var rr := R * 0.68
	var rim_c := lin(s["rim"])
	var rp := PackedVector2Array([Vector2(rr * 0.25, W / 2 - 0.07), Vector2(rr * 0.3, W / 2 - 0.05), Vector2(rr * 0.95, W / 2 - 0.1),
		Vector2(rr, W / 2 - 0.03), Vector2(rr + 0.01, W / 2 - 0.02), Vector2(rr, -W / 2 + 0.03), Vector2(rr - 0.03, -W / 2 + 0.03)])
	kit.add(Geo.lathe(rp, seg).rotate_z(-PI / 2.0).xform(xf), Kit.METAL, spin, rim_c)
	var n: int = s["spokes"]
	if not detail:
		n = mini(n, 5)
	var thin := n >= 8
	for k in n:
		var a := float(k) / n * TAU
		var sp := Geo.box(0.03, rr * 0.78, 0.028 if thin else 0.05).translate(W / 2 - 0.06, rr * 0.5, 0).rotate_x(a)
		kit.add(sp.xform(xf), Kit.METAL, spin, rim_c)
	kit.add(Geo.cylinder(0.045, 0.05, 0.04, 12 if detail else 8).rotate_z(-PI / 2.0).translate(W / 2 - 0.05, 0, 0).xform(xf), Kit.METAL, spin, lin(0x9a9ea6))
	# brake disc (spins) and caliper (does not)
	var disc_r := minf(0.21, rr - 0.03)
	kit.add(Geo.cylinder(disc_r, disc_r, 0.028, seg).rotate_z(PI / 2.0).translate(-W / 2 + 0.11, 0, 0).xform(xf), Kit.CARBON, spin, lin(0x6a6d73))
	kit.add(Geo.box(0.07, 0.15, 0.12).translate(-W / 2 + 0.11, disc_r - 0.04, -0.1).xform(xf), Kit.GLOSS, up, lin(s["caliper"]))
	kit.add(Geo.box(0.08, 0.16, 0.1).translate(-W / 2 + 0.02, 0, 0).xform(xf), Kit.CARBON, up, lin(0x1a1b1e))
	# suspension: upper and lower wishbones from the body (inboard) to the hub carrier
	var inner := absf(c.x) - (0.32 if s["fenders"] else absf(c.x) - 0.42)
	var outer := absf(c.x) - W / 2 - 0.02
	var arm_c := lin(0x2a2c31)
	var arms := [[-0.1, 0.035], [0.12, 0.028]] if detail else [[-0.1, 0.035]]
	for a in arms:
		var y := c.y + float(a[0])
		var o := Vector3(sx * outer, y, c.z)
		for dz in [-0.2, 0.2]:
			var ib := Vector3(sx * inner, y + 0.02, c.z + dz)
			kit.add_blend(tube(ib, o, a[1], -1.0, 6 if detail else 4), Kit.METAL if not s["fenders"] else Kit.CARBON, Kit.BODY, up, ib, o, arm_c if s["fenders"] else lin(s["cage"]))
	if not s["fenders"]:
		# coil-over: damper body and a spring of rings, squashed and stretched with the wheel
		var top := Vector3(sx * (absf(c.x) - 0.5), c.y + 0.42, c.z - 0.06)
		var bot := Vector3(sx * (outer - 0.04), c.y + 0.06, c.z)
		kit.add_blend(tube(top, bot, 0.022, -1.0, 8), Kit.METAL, Kit.BODY, up, top, bot, lin(0xb0b4ba))
		var coils := 7 if detail else 4
		for k in coils:
			var p := top.lerp(bot, 0.12 + 0.6 * float(k) / (coils - 1))
			var ring := Geo.torus(0.05, 0.009, 4, 12 if detail else 8).xform(Transform3D(_basis_y((bot - top).normalized()) * Basis(Vector3.RIGHT, PI / 2.0), p))
			kit.add_blend(ring, Kit.GLOSS, Kit.BODY, up, top, bot, lin(s["caliper"]))


## A basis whose y axis is `y`.
static func _basis_y(y: Vector3) -> Basis:
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y))


# =============================================================================
# steering wheel and driver
# =============================================================================

static func _steering_wheel(kit: Kit, detail: int, rig: Dictionary) -> void:
	var wc: Vector3 = rig["wheel_c"]
	var wb: Basis = rig["wheel_basis"]
	var xf := Transform3D(wb, wc)
	var dark := lin(0x1b1c20)
	# rim (a flat-bottomed racing wheel: the torus with its lower arc cut away) and a bottom bar
	kit.add(Geo.torus(WHEEL_R, 0.016, 6 if detail else 4, 24 if detail else 12, PI * 1.6).rotate_z(-0.3 * PI).xform(xf), Kit.MATTE, Kit.STEERING, dark)
	var a0 := -0.3 * PI
	var p0 := Vector3(WHEEL_R * cos(a0), WHEEL_R * sin(a0), 0)
	var p1 := Vector3(-p0.x, p0.y, 0)
	kit.add(tube(p0, p1, 0.016, -1.0, 6).xform(xf), Kit.MATTE, Kit.STEERING, dark)
	for k in 3:
		var a := [0.0, PI, -PI / 2.0][k] as float
		var end := Vector3(WHEEL_R * cos(a), WHEEL_R * sin(a), 0) * 0.92
		kit.add(Geo.box(0.035, 0.012, 0.02).scale(end.length() / 0.035, 1.0, 1.0).rotate_z(a).translate(end.x * 0.5, end.y * 0.5, 0.01).xform(xf), Kit.CARBON, Kit.STEERING, lin(0x2a2c30))
	kit.add(Geo.cylinder(0.045, 0.05, 0.05, 12 if detail else 8).rotate_x(PI / 2.0).translate(0, 0, 0.02).xform(xf), Kit.CARBON, Kit.STEERING, lin(0x22242a))
	kit.add(Geo.box(0.07, 0.03, 0.012).translate(0, 0.02, -0.006).xform(xf), Kit.HEAD, Kit.STEERING) # shift lights
	kit.add(Geo.box(0.018, 0.03, 0.022).translate(0, WHEEL_R, 0).xform(xf), Kit.GLOSS, Kit.STEERING, lin(0xffc83d)) # top marker
	# the column (does not turn) and the instrument panel at its end, facing the driver
	kit.add(tube(wc + wb.z * 0.03, wc + wb.z * 0.2, 0.022, -1.0, 8), Kit.CARBON, Kit.BODY, dark)
	kit.add(Geo.box(0.3, 0.09, 0.05).xform(Transform3D(wb, wc + wb.z * 0.21 + wb.y * 0.02)), Kit.CARBON, Kit.BODY, lin(0x16171a))
	kit.add(Geo.box(0.12, 0.045, 0.006).xform(Transform3D(wb, wc + wb.z * 0.183 + wb.y * 0.025)), Kit.DARK_GLASS, Kit.BODY, lin(0x1d3a4a)) # display


static func _driver(kit: Kit, s: Dictionary, detail: int, rig: Dictionary) -> void:
	var hip: Vector3 = rig["hip"]
	var u: Vector3 = rig["u"]
	var f: Vector3 = rig["f"]
	var suit := lin(s["suit"])
	var gloves := lin(s["gloves"])
	var ring := 14 if detail else 8
	# torso: a loft up the back (local z along u, y backwards), belts over the shoulders
	var tb := Basis(Vector3(1, 0, 0), -f, u)
	var torso := Shapes.loft([Shapes.ST(-0.05, 0, 0.0, 0.15, 0.1, 3), Shapes.ST(0.12, 0, 0.0, 0.165, 0.11, 3),
		Shapes.ST(0.3, 0, -0.01, 0.185, 0.115, 3), Shapes.ST(0.42, 0, 0.0, 0.2, 0.1, 3), Shapes.ST(0.5, 0, 0.01, 0.15, 0.07, 3)], ring, 2 if detail else 1)
	kit.add(torso.xform(Transform3D(tb, hip)), Kit.MATTE, Kit.TORSO, suit)
	if detail:
		for sx in [1.0, -1.0]:
			var a: Vector3 = hip + u * 0.5 + Vector3(sx * 0.1, 0, 0) + f * 0.05
			var b: Vector3 = hip + u * 0.12 + Vector3(sx * 0.06, 0, 0) + f * 0.12
			kit.add(tube(a, b, 0.022, -1.0, 4).scale(1.0, 1.0, 1.0), Kit.MATTE, Kit.TORSO, lin(0x0e0f11))
	# neck and the head-restraint collar
	kit.add(tube(hip + u * 0.48, hip + u * 0.64, 0.05, -1.0, ring), Kit.MATTE, Kit.HEAD_BONE, suit)
	kit.add(Geo.torus(0.085, 0.03, 6 if detail else 4, 12 if detail else 8, PI * 1.3).rotate_z(-0.15 * PI).rotate_x(PI / 2.0).translate(0, 0, -0.01).xform(Transform3D(Basis.IDENTITY, hip + u * 0.5)),
		Kit.CARBON, Kit.TORSO, lin(0x1a1b1f))
	# helmet: shell, visor, stripe over the top, a small spoiler
	var hc: Vector3 = rig["head"]
	var hs := Vector3(0.92, 1.0, 1.06)
	kit.add(Geo.sphere(HELMET_R, 20 if detail else 10, 14 if detail else 7).scale(hs.x, hs.y, hs.z).translate(hc.x, hc.y, hc.z), Kit.GLOSS, Kit.HEAD_BONE, lin(s["helmet"]))
	kit.add(Geo.sphere(HELMET_R * 1.012, 14 if detail else 8, 4, PI / 2.0 - 1.15, 2.3, 1.2, 0.62).scale(hs.x, hs.y, hs.z).translate(hc.x, hc.y, hc.z),
		Kit.DARK_GLASS, Kit.HEAD_BONE, lin(s["visor"]))
	kit.add(Geo.torus(HELMET_R, 0.012, 4, 16 if detail else 8, PI).rotate_y(PI / 2.0).scale(hs.x, hs.y, hs.z).translate(hc.x, hc.y, hc.z),
		Kit.GLOSS, Kit.HEAD_BONE, lin(s["helmet_stripe"]))
	if detail:
		kit.add(Shapes.box(0.12, 0.025, 0.06, hc.x, hc.y + HELMET_R * 0.72, hc.z - HELMET_R * 0.9), Kit.GLOSS, Kit.HEAD_BONE, lin(s["helmet_stripe"]))
	# arms (upper arm, forearm) and gloves, laid out in the rest pose holding the wheel
	var shoulders: Array = rig["shoulders"]
	var elbows: Array = rig["elbows"]
	var hands: Array = rig["hands"]
	for side in 2:
		var sh: Vector3 = shoulders[side]
		var el: Vector3 = elbows[side]
		var hd: Vector3 = hands[side]
		var bu := Kit.ARM_UL if side == 0 else Kit.ARM_UR
		var bf := Kit.ARM_FL if side == 0 else Kit.ARM_FR
		kit.add(Geo.sphere(0.058, ring, ring / 2).translate(sh.x, sh.y, sh.z), Kit.MATTE, bu, suit)
		kit.add(tube(sh, el, 0.052, 0.046, ring), Kit.MATTE, bu, suit)
		kit.add(Geo.sphere(0.047, ring, ring / 2).translate(el.x, el.y, el.z), Kit.MATTE, bf, suit)
		var d := (hd - el).normalized()
		var wrist := hd - d * 0.06
		kit.add(tube(el, wrist, 0.045, 0.037, ring), Kit.MATTE, bf, suit)
		kit.add(tube(wrist - d * 0.035, wrist + d * 0.01, 0.044, 0.042, ring), Kit.MATTE, bf, gloves)
		kit.add(Geo.sphere(0.042, ring, ring / 2).scale(1.0, 0.9, 1.25).xform(Transform3D(_basis_y(d) * Basis(Vector3.RIGHT, PI / 2.0), hd)), Kit.MATTE, bf, gloves)


# =============================================================================
# side view (the car picker) and the AI fleet
# =============================================================================

## Side view of car `id` for the car picker (plain numbers, same data as the 3D model):
## {parts: [{mat, pts: PackedVector2Array of (z, y)[, color]}], wheels: [Vector2(z, radius)], rim: Color}
## in metres (z forward, y up). mat is "glass", "paint", "accent", "carbon", "head", "helmet" or
## "metal" (a part with `color` is drawn in that colour). Draw the parts in order, then the wheels.
static func profile(id: String) -> Dictionary:
	var s := Shapes.shape_of(id)
	var P := func(z: float, y: float) -> Vector2:
		var p := Shapes.warp_point(s, 0, y, z)
		return Vector2(snappedf(p.z, 0.001), snappedf(p.y, 0.001))
	var side := func(st: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for t in st:
			out.append(P.call(t[0], t[2] + t[4]))
		for i in range(st.size() - 1, -1, -1):
			var t: Array = st[i]
			out.append(P.call(t[0], t[2] - t[4]))
		return out
	var rect := func(z: float, y: float, dz: float, dy: float) -> PackedVector2Array:
		return PackedVector2Array([P.call(z - dz, y - dy), P.call(z + dz, y - dy), P.call(z + dz, y + dy), P.call(z - dz, y + dy)])
	var b := Shapes.body_stations(s)
	var r := rig(id)
	var parts := []
	if not (s["glass"] as Array).is_empty():
		parts.append({"mat": "glass", "pts": side.call(s["glass"])})
	# the driver's helmet (seen through the glass, or above an open cockpit)
	var hc: Vector3 = r["head"]
	var helmet := PackedVector2Array()
	for k in 16:
		var a := float(k) / 16.0 * TAU
		helmet.append(Vector2(snappedf(hc.z + HELMET_R * 1.06 * cos(a), 0.001), snappedf(hc.y + HELMET_R * sin(a), 0.001)))
	parts.append({"mat": "helmet", "pts": helmet, "color": Color.hex((int(s["helmet"]) << 8) | 0xff)})
	var keys: Array = ["tub"]
	if s["fenders"]:
		keys = ["rearFender", "frontFender", "tub"]
	if s["pods"]:
		keys.push_front("sidePod")
	for key in keys:
		parts.append({"mat": "paint", "pts": side.call(b[key])})
	parts.append({"mat": "carbon", "pts": rect.call(0.13, 0.135, 2.38, 0.025)}) # floor
	for p in s["parts"]:
		if p.get("flat", false):
			continue
		var at: Array = p.get("at", [0, 0, 0])
		var y: float = at[1]
		var z: float = at[2]
		var pts := PackedVector2Array()
		if p.has("loft"):
			pts = side.call(p["loft"])
		elif p.has("box"):
			pts = rect.call(z, y, p["box"][2] / 2.0, p["box"][1] / 2.0)
		elif p.has("hoop"):
			pts = rect.call(z, y + (p["hoop"][0] + p["hoop"][1]) / 2.0, p["hoop"][1], (p["hoop"][0] + p["hoop"][1]) / 2.0)
		elif p.has("lamp"):
			pts = rect.call(z, y, p["lamp"][1] / 2.0, p["lamp"][0])
		elif p.has("fin"):
			for f in Shapes.FIN:
				pts.append(P.call(f[0], f[1]))
		elif p.has("wing"):
			var chord: float = p["wing"][1]
			var thick: float = p["wing"][2]
			var a: float = p.get("rx", 0.0)
			var tz := z - chord * cos(a)
			var ty := y + chord * sin(a)
			pts = PackedVector2Array([P.call(z, y), P.call(z - chord * 0.3, y + thick), P.call(tz, ty + thick * 0.25), P.call(tz, ty),
				P.call(z - chord * 0.3, y - thick * 0.2)])
		if not pts.is_empty():
			parts.append({"mat": p["mat"], "pts": pts})
	# cage and bars (car frame), at least 4 cm thick so they show at card size
	for t in s["tubes"]:
		var a := Vector2(t[2], t[1])
		var e := Vector2(t[5], t[4])
		var n := (e - a).orthogonal().normalized() * maxf(0.02, float(t[6]))
		if (e - a).length() < 0.05:
			continue
		parts.append({"mat": "metal", "color": Color.hex((int(s["cage"]) << 8) | 0xff), "pts": PackedVector2Array([a - n, e - n, e + n, a + n])})
	var wheels := []
	for w in Shapes.wheel_layout(s):
		if w[0] > 0.0:
			wheels.append(Vector2(snappedf(w[1], 0.001), w[2]))
	return {"parts": parts, "wheels": wheels, "rim": Color.hex((int(s["rim"]) << 8) | 0xff)}


## The AI fleet's two static meshes of car `id` (low detail): paint (one colour per car) and the
## dark parts (carbon, glass, plain wheels, the driver's helmet).
static func fleet_geometry(id: String) -> Dictionary:
	var s := Shapes.shape_of(id)
	var paint := Shapes.paint_geometry(s, 0)
	var parts: Array = [Shapes.carbon_geometry(s, 0)]
	if not (s["glass"] as Array).is_empty():
		parts.append(Shapes.warp(Shapes.loft(s["glass"], 10, 1), s))
	for t in s["tubes"]:
		var sym: bool = t.size() > 7 and t[7]
		for sx in ([1.0, -1.0] if sym else [1.0]):
			parts.append(tube(Vector3(t[0] * sx, t[1], t[2]), Vector3(t[3] * sx, t[4], t[5]), t[6], -1.0, 4, false))
	for w in Shapes.wheel_layout(s):
		var R: float = w[2]
		parts.append(Geo.cylinder(R, R, w[3], 10).rotate_z(PI / 2.0).translate(w[0], R, w[1]))
	if s["open"]:
		var hc: Vector3 = rig(id)["head"]
		parts.append(Geo.sphere(HELMET_R, 8, 5).translate(hc.x, hc.y, hc.z))
	return {"paint": paint, "dark": Geo.merge(parts)}
