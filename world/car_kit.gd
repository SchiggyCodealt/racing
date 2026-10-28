## car_kit.gd
## ------------------------------------------------------------------
## Builds a whole car as one mesh: every part (Geo, world/geo.gd) is added with
## a material kind and the bone that moves it, and the kit turns into one
## ArrayMesh drawn with one material (world/shaders/car.gdshader), skinned to
## the car's skeleton (world/car_model.gd), so a detailed car with spinning
## wheels and a moving driver costs one draw call per pass instead of dozens.
##
## Per vertex: COLOR = the albedo (linear in the Geo, stored as sRGB) for the
## kinds that don't take a uniform colour; UV2.x = the kind; the rest position
## (UV = x, z; UV2.y = y) so the shader can draw panel lines that stay on the
## body while the bones move it; BONES / WEIGHTS: one bone, or two blended
## (a suspension arm: the body at one end, the wheel upright at the other).
##
##   var kit := CarKit.new()
##   kit.add(geo, CarKit.PAINT, CarKit.BODY)              # white albedo: the shader paints it
##   kit.add(geo, CarKit.METAL, CarKit.SPIN0, Color(...)) # albedo for kinds without a uniform
##   kit.add_blend(geo, CarKit.CARBON, CarKit.BODY, CarKit.UPRIGHT0, from, to)  # weight by position along from -> to
##   kit.to_mesh(true)  -> ArrayMesh (skinned), kit.to_mesh(false) -> static
##   kit.triangles()
extends RefCounted

const Geo = preload("res://world/geo.gd")

# --- material kinds (car.gdshader has the same table) -------------------------------
const PAINT := 0    # the body colour (uniform), clear coat
const ACCENT := 1   # the accent colour (uniform)
const STRIPE := 2   # the livery stripe colour (uniform)
const GLOSS := 3    # glossy paint in the vertex colour (helmets, calipers, decals)
const MATTE := 4    # cloth, rubber trim, seats (vertex colour)
const METAL := 5    # rims, discs, exhaust tips, cage tubes (vertex colour)
const CARBON := 6   # carbon fibre and dark plastics (vertex colour)
const DARK_GLASS := 7 # opaque glossy glass: visors, mirror faces (vertex colour)
const HEAD := 8     # headlights: glow with the head_glow uniform
const TAIL := 9     # tail and brake lights: glow with the tail_glow uniform
const TYRE := 10    # tyre rubber (vertex colour)

# --- bones (car_model.gd poses them; all have the identity as rest, so a bone's pose
# is the transform of the car-frame vertices it carries) -----------------------------
const BODY := 0
const UPRIGHT0 := 1 # + wheel index 0..3 (FL, FR, RL, RR): steers and travels, does not spin
const SPIN0 := 5    # + wheel index: the rolling parts of the wheel
const STEERING := 9 # the steering wheel
const TORSO := 10
const HEAD_BONE := 11
const ARM_UL := 12  # left upper arm
const ARM_FL := 13  # left forearm and hand
const ARM_UR := 14
const ARM_FR := 15
const FLAP := 16    # an active rear wing (tilts up as an air brake)
const BONE_COUNT := 17
const BONE_NAMES := ["body", "upright_fl", "upright_fr", "upright_rl", "upright_rr", "spin_fl", "spin_fr", "spin_rl", "spin_rr",
	"steering", "torso", "head", "arm_ul", "arm_fl", "arm_ur", "arm_fr", "flap"]

var pos := PackedVector3Array()
var nor := PackedVector3Array()
var col := PackedColorArray()
var kind := PackedFloat32Array()
var bones := PackedInt32Array()   # 4 per vertex
var weights := PackedFloat32Array() # 4 per vertex
var idx := PackedInt32Array()     # web winding (counter-clockwise), flipped by to_mesh()


func vertex_count() -> int:
	return pos.size()


func triangles() -> int:
	return idx.size() / 3


## Adds `g` (its normals computed when missing) as material `k` on bone `bone`, albedo `c`.
func add(g: Geo, k: int, bone: int, c := Color(1, 1, 1)) -> void:
	_append(g, k, c, func(_p: Vector3) -> Vector4: return Vector4(bone, -1, 1.0, 0.0))


## Adds `g` blended between two bones by the position along a -> b (a: all bone_a, b: all bone_b).
func add_blend(g: Geo, k: int, bone_a: int, bone_b: int, a: Vector3, b: Vector3, c := Color(1, 1, 1)) -> void:
	var ab := b - a
	var len2 := maxf(ab.length_squared(), 1e-9)
	_append(g, k, c, func(p: Vector3) -> Vector4:
		var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
		t = smoothstep(0.25, 0.75, t)
		return Vector4(bone_a, bone_b, 1.0 - t, t))


## Appends another kit.
func add_kit(o: RefCounted) -> void:
	var s := pos.size()
	pos.append_array(o.pos)
	nor.append_array(o.nor)
	col.append_array(o.col)
	kind.append_array(o.kind)
	bones.append_array(o.bones)
	weights.append_array(o.weights)
	for i in o.idx:
		idx.append(s + i)


func _append(g: Geo, k: int, c: Color, bw: Callable) -> void:
	if g == null or g.pos.is_empty():
		return
	if g.nor.size() != g.pos.size():
		g.compute_normals()
	var s := pos.size()
	var has_col := g.col.size() == g.pos.size()
	for i in g.pos.size():
		var p := g.pos[i]
		pos.append(p)
		nor.append(g.nor[i])
		col.append(Color(g.col[i].r * c.r, g.col[i].g * c.g, g.col[i].b * c.b) if has_col else c)
		kind.append(k)
		var w: Vector4 = bw.call(p)
		bones.append(int(w.x))
		bones.append(maxi(0, int(w.y)))
		bones.append(0)
		bones.append(0)
		weights.append(w.z)
		weights.append(w.w if w.y >= 0.0 else 0.0)
		weights.append(0.0)
		weights.append(0.0)
	if g.indexed:
		for i in g.idx:
			idx.append(s + i)
	else:
		for i in g.pos.size() - g.pos.size() % 3:
			idx.append(s + i)


## The mesh (one surface). skinned: with the bone arrays (a MeshInstance3D with the car's Skin).
func to_mesh(skinned: bool) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if pos.is_empty():
		return mesh
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = pos
	a[Mesh.ARRAY_NORMAL] = nor
	var c8 := PackedColorArray()
	c8.resize(col.size())
	for k in col.size():
		c8[k] = col[k].linear_to_srgb()
	a[Mesh.ARRAY_COLOR] = c8
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	uv.resize(pos.size())
	uv2.resize(pos.size())
	for k in pos.size():
		uv[k] = Vector2(pos[k].x, pos[k].z)
		uv2[k] = Vector2(kind[k], pos[k].y)
	a[Mesh.ARRAY_TEX_UV] = uv
	a[Mesh.ARRAY_TEX_UV2] = uv2
	if skinned:
		a[Mesh.ARRAY_BONES] = bones
		a[Mesh.ARRAY_WEIGHTS] = weights
	var out := PackedInt32Array()
	out.resize(idx.size())
	for t in range(0, idx.size() - 2, 3):
		out[t] = idx[t]
		out[t + 1] = idx[t + 2]
		out[t + 2] = idx[t + 1]
	a[Mesh.ARRAY_INDEX] = out
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return mesh


## A plain Geo of the parts of some kinds (vertex colours = albedo; uniform kinds get `paint`),
## for the AI fleet's static meshes.
func to_geo(kinds: Array, paint := Color(1, 1, 1)) -> Geo:
	var g := Geo.new()
	var keep := PackedInt32Array()
	keep.resize(pos.size())
	var remap := PackedInt32Array()
	remap.resize(pos.size())
	remap.fill(-1)
	for t in range(0, idx.size() - 2, 3):
		var k := int(kind[idx[t]])
		if not kinds.has(k):
			continue
		for j in 3:
			var v := idx[t + j]
			if remap[v] < 0:
				remap[v] = g.pos.size()
				g.pos.append(pos[v])
				g.nor.append(nor[v])
				g.uv.append(Vector2.ZERO)
				g.col.append(paint if int(kind[v]) <= STRIPE else col[v])
			g.idx.append(remap[v])
	return g
