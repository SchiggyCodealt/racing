## geo.gd
## ------------------------------------------------------------------
## Mesh data and procedural geometry for the 3D world (the Godot side of
## the BufferGeometry / GeoBuilder code in the web game's carMesh.js and
## trackMesh.js).
##
## A Geo holds plain arrays (positions, normals, uvs, colours, triangle
## indices) in the web game's convention: right-handed, y up, triangles
## counter-clockwise seen from the front. to_arrays() / add_to() flip the
## winding for Godot (clockwise front faces), so every generator and
## builder below ports the JS line for line.
##
##   - primitives with the same parameters and vertex layout as Three.js:
##     box, cylinder / cone, sphere, torus, lathe, circle, ring, plane,
##     icosahedron / dodecahedron / octahedron, extrude (a 2D outline)
##   - transforms (translate, rotate_x/y/z, scale, xform), merge, normals
##   - the builder calls of trackMesh.js: vert, quad, flat_quad, quad_uv,
##     sweep_quad, add_geometry, box_at
##
## Colours are linear (like Three.js vertex colours); to_arrays() writes them
## as sRGB, so every material that uses them sets vertex_color_is_srgb.
extends RefCounted

const Geo = preload("res://world/geo.gd")

var pos := PackedVector3Array()
var nor := PackedVector3Array()
var uv := PackedVector2Array()
var col := PackedColorArray()
var idx := PackedInt32Array()
## false: the triangles are a plain list (Three.js "non-indexed": flat shading after normals())
var indexed := true


func count() -> int:
	return pos.size()


func duplicate_geo() -> Geo:
	var g := Geo.new()
	g.pos = pos.duplicate()
	g.nor = nor.duplicate()
	g.uv = uv.duplicate()
	g.col = col.duplicate()
	g.idx = idx.duplicate()
	g.indexed = indexed
	return g


# ---- builder (GeoBuilder of trackMesh.js) -------------------------------------

## Adds a vertex; returns its index.
func vert(p: Vector3, n: Vector3, t: Vector2, c: Color) -> int:
	var k := pos.size()
	pos.append(p)
	nor.append(n)
	uv.append(t)
	col.append(c)
	return k


func tri(a: int, b: int, c: int) -> void:
	idx.append(a)
	idx.append(b)
	idx.append(c)


func quad(a: int, b: int, c: int, d: int) -> void:
	tri(a, b, c)
	tri(a, c, d)


## Flat-shaded quad lying on the road, facing up.
func flat_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	quad_uv(a, b, c, d, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), color, Vector3.UP)


## Flat-shaded quad a-b-c-d. The normal comes from the corner order, or is
## flipped to agree with `ref` if given (non-zero); the winding always matches it.
func quad_uv(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2,
		color: Color, ref := Vector3.ZERO) -> void:
	var n := (b - a).cross(d - a)
	var l := n.length()
	n = n / l if l > 0.0 else Vector3.UP
	var flip := false
	if ref != Vector3.ZERO and n.dot(ref) < 0.0:
		n = -n
		flip = true
	var s := pos.size()
	vert(a, n, ua, color)
	vert(b, n, ub, color)
	vert(c, n, uc, color)
	vert(d, n, ud, color)
	if not flip:
		tri(s, s + 1, s + 2)
		tri(s, s + 2, s + 3)
	else:
		tri(s, s + 3, s + 2)
		tri(s, s + 2, s + 1)


## Quad with given per-edge normals (smooth along a sweep); winding follows the normal.
func sweep_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ni: Vector3, nj: Vector3, color: Color,
		ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	var s := pos.size()
	vert(a, ni, ua, color)
	vert(b, nj, ub, color)
	vert(c, nj, uc, color)
	vert(d, ni, ud, color)
	if (b - a).cross(d - a).dot(ni) >= 0.0:
		tri(s, s + 1, s + 2)
		tri(s, s + 2, s + 3)
	else:
		tri(s, s + 3, s + 2)
		tri(s, s + 2, s + 1)


## Appends geometry `g` transformed by `m`. `color` (alpha > 0) replaces the
## vertex colours of a geometry without colours, or multiplies them.
func add_geometry(g: Geo, m := Transform3D.IDENTITY, color := Color(1, 1, 1, 0)) -> void:
	var s := pos.size()
	var nb := m.basis.inverse().transposed()
	var has_col: bool = g.col.size() == g.pos.size()
	var has_uv: bool = g.uv.size() == g.pos.size()
	var has_nor: bool = g.nor.size() == g.pos.size()
	var tint := color.a > 0.0
	var white := Color(1, 1, 1)
	var n: int = g.pos.size()
	for k in n:
		pos.append(m * g.pos[k])
		nor.append((nb * g.nor[k]).normalized() if has_nor else Vector3.UP)
		uv.append(g.uv[k] if has_uv else Vector2.ZERO)
		var c: Color = g.col[k] if has_col else (Color(color.r, color.g, color.b) if tint else white)
		if has_col and tint:
			c = Color(c.r * color.r, c.g * color.g, c.b * color.b)
		col.append(c)
	if g.indexed:
		for i in g.idx:
			idx.append(s + i)
	else:
		for k in n:
			idx.append(s + k)


## Axis-aligned box in the frame m: centre p, size sz (a unit box scaled).
func box_at(m: Transform3D, p: Vector3, sz: Vector3, color: Color) -> void:
	var t := m * Transform3D(Basis.from_scale(sz), p)
	add_geometry(unit_box(), t, color)


static var _unit_box: Geo = null


static func unit_box() -> Geo:
	if _unit_box == null:
		_unit_box = box(1, 1, 1)
	return _unit_box


# ---- transforms ---------------------------------------------------------------

func xform(m: Transform3D) -> Geo:
	var nb := m.basis.inverse().transposed()
	for k in pos.size():
		pos[k] = m * pos[k]
	for k in nor.size():
		nor[k] = (nb * nor[k]).normalized()
	return self


func translate(x: float, y: float, z: float) -> Geo:
	var d := Vector3(x, y, z)
	for k in pos.size():
		pos[k] += d
	return self


func rotate_x(a: float) -> Geo:
	return xform(Transform3D(Basis(Vector3.RIGHT, a), Vector3.ZERO))


func rotate_y(a: float) -> Geo:
	return xform(Transform3D(Basis(Vector3.UP, a), Vector3.ZERO))


func rotate_z(a: float) -> Geo:
	return xform(Transform3D(Basis(Vector3.BACK, a), Vector3.ZERO))


func scale(x: float, y: float, z: float) -> Geo:
	return xform(Transform3D(Basis.from_scale(Vector3(x, y, z)), Vector3.ZERO))


## Solid vertex colour.
func paint_solid(c: Color) -> Geo:
	col.resize(pos.size())
	col.fill(c)
	return self


# ---- normals ------------------------------------------------------------------

## Three.js computeVertexNormals: area-weighted smooth normals for an indexed
## geometry, flat (per triangle) normals for a non-indexed one.
func compute_normals() -> Geo:
	var n := pos.size()
	nor.resize(n)
	nor.fill(Vector3.ZERO)
	if indexed:
		for t in range(0, idx.size(), 3):
			var a := idx[t]
			var b := idx[t + 1]
			var c := idx[t + 2]
			var f := (pos[c] - pos[b]).cross(pos[a] - pos[b])
			nor[a] += f
			nor[b] += f
			nor[c] += f
	else:
		for t in range(0, n - 2, 3):
			var f := (pos[t + 2] - pos[t + 1]).cross(pos[t] - pos[t + 1])
			nor[t] = f
			nor[t + 1] = f
			nor[t + 2] = f
	for k in n:
		var v := nor[k]
		nor[k] = v.normalized() if v.length_squared() > 0.0 else Vector3.UP
	return self


# ---- output -------------------------------------------------------------------

## Godot surface arrays (winding flipped to clockwise front faces).
func to_arrays(with_uv := true, with_col := true) -> Array:
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = pos
	if nor.size() != pos.size():
		compute_normals()
	a[Mesh.ARRAY_NORMAL] = nor
	if with_uv and uv.size() == pos.size():
		a[Mesh.ARRAY_TEX_UV] = uv
	if with_col and col.size() == pos.size():
		# Godot keeps vertex colours as 8-bit unorm: store them as sRGB (materials set
		# vertex_color_is_srgb), so dark colours keep their precision. Values above 1 clamp.
		var c8 := PackedColorArray()
		c8.resize(col.size())
		for k in col.size():
			c8[k] = col[k].linear_to_srgb()
		a[Mesh.ARRAY_COLOR] = c8
	var out := PackedInt32Array()
	if indexed:
		out.resize(idx.size())
		for t in range(0, idx.size() - 2, 3):
			out[t] = idx[t]
			out[t + 1] = idx[t + 2]
			out[t + 2] = idx[t + 1]
	else:
		out.resize(pos.size() - pos.size() % 3)
		for t in range(0, out.size(), 3):
			out[t] = t
			out[t + 1] = t + 2
			out[t + 2] = t + 1
	a[Mesh.ARRAY_INDEX] = out
	return a


## Adds this geometry as a surface of `mesh` (a new ArrayMesh if null). Returns the mesh.
func add_to(mesh: ArrayMesh, mat: Material = null, with_uv := true, with_col := true) -> ArrayMesh:
	if mesh == null:
		mesh = ArrayMesh.new()
	if pos.is_empty():
		return mesh
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, to_arrays(with_uv, with_col))
	if mat != null:
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	return mesh


func to_mesh(mat: Material = null, with_uv := true, with_col := true) -> ArrayMesh:
	return add_to(null, mat, with_uv, with_col)


## Bounding box of the positions.
func aabb() -> AABB:
	if pos.is_empty():
		return AABB()
	var b := AABB(pos[0], Vector3.ZERO)
	for p in pos:
		b = b.expand(p)
	return b


# ---- merging ------------------------------------------------------------------

## One indexed geometry from several (positions, normals, uvs, colours kept when all have them).
static func merge(list: Array) -> Geo:
	var out := Geo.new()
	for g in list:
		if g == null:
			continue
		if g.nor.size() != g.pos.size():
			g.compute_normals()
		out.add_geometry(g)
	return out


# ---- primitives (Three.js layouts) --------------------------------------------

static func _new() -> Geo:
	return Geo.new()


static func box(w: float, h: float, d: float, ws := 1, hs := 1, ds := 1) -> Geo:
	var g := _new()
	# buildPlane(u, v, w, udir, vdir, width, height, depth, gridX, gridY); axes: 0 x, 1 y, 2 z
	g._plane(2, 1, 0, -1, -1, d, h, w, ds, hs)
	g._plane(2, 1, 0, 1, -1, d, h, -w, ds, hs)
	g._plane(0, 2, 1, 1, 1, w, d, h, ws, ds)
	g._plane(0, 2, 1, 1, -1, w, d, -h, ws, ds)
	g._plane(0, 1, 2, 1, -1, w, h, d, ws, hs)
	g._plane(0, 1, 2, -1, -1, w, h, -d, ws, hs)
	return g


func _plane(u: int, v: int, w: int, udir: float, vdir: float, width: float, height: float, depth: float, gx: int, gy: int) -> void:
	var sw := width / gx
	var sh := height / gy
	var s := pos.size()
	for iy in gy + 1:
		var y := iy * sh - height / 2.0
		for ix in gx + 1:
			var x := ix * sw - width / 2.0
			var p := Vector3()
			p[u] = x * udir
			p[v] = y * vdir
			p[w] = depth / 2.0
			var n := Vector3()
			n[w] = 1.0 if depth > 0.0 else -1.0
			pos.append(p)
			nor.append(n)
			uv.append(Vector2(float(ix) / gx, 1.0 - float(iy) / gy))
	for iy in gy:
		for ix in gx:
			var a := s + ix + (gx + 1) * iy
			var b := s + ix + (gx + 1) * (iy + 1)
			var c := s + (ix + 1) + (gx + 1) * (iy + 1)
			var d := s + (ix + 1) + (gx + 1) * iy
			tri(a, b, d)
			tri(b, c, d)


static func cylinder(rt: float, rb: float, h: float, radial := 32, hseg := 1, open_ended := false,
		theta_start := 0.0, theta_len := TAU) -> Geo:
	var g := _new()
	var half := h / 2.0
	var slope := (rb - rt) / h
	var grid := []
	for y in hseg + 1:
		var row := PackedInt32Array()
		var v := float(y) / hseg
		var r := v * (rb - rt) + rt
		for x in radial + 1:
			var u := float(x) / radial
			var th := u * theta_len + theta_start
			var st := sin(th)
			var ct := cos(th)
			row.append(g.pos.size())
			g.pos.append(Vector3(r * st, -v * h + half, r * ct))
			g.nor.append(Vector3(st, slope, ct).normalized())
			g.uv.append(Vector2(u, 1.0 - v))
		grid.append(row)
	for x in radial:
		for y in hseg:
			var a: int = grid[y][x]
			var b: int = grid[y + 1][x]
			var c: int = grid[y + 1][x + 1]
			var d: int = grid[y][x + 1]
			g.tri(a, b, d)
			g.tri(b, c, d)
	if not open_ended:
		if rt > 0.0:
			g._cap(true, rt, half, radial, theta_start, theta_len)
		if rb > 0.0:
			g._cap(false, rb, half, radial, theta_start, theta_len)
	return g


func _cap(top: bool, r: float, half: float, radial: int, theta_start: float, theta_len: float) -> void:
	var sgn := 1.0 if top else -1.0
	var c0 := pos.size()
	for x in radial:
		pos.append(Vector3(0, half * sgn, 0))
		nor.append(Vector3(0, sgn, 0))
		uv.append(Vector2(0.5, 0.5))
	var e0 := pos.size()
	for x in radial + 1:
		var th := float(x) / radial * theta_len + theta_start
		pos.append(Vector3(r * sin(th), half * sgn, r * cos(th)))
		nor.append(Vector3(0, sgn, 0))
		uv.append(Vector2(cos(th) * 0.5 + 0.5, sin(th) * 0.5 * sgn + 0.5))
	for x in radial:
		var c := c0 + x
		var i := e0 + x
		if top:
			tri(i, i + 1, c)
		else:
			tri(i + 1, i, c)


static func cone(r: float, h: float, radial := 32, hseg := 1, open_ended := false) -> Geo:
	return cylinder(0.0, r, h, radial, hseg, open_ended)


static func sphere(r: float, ws := 32, hs := 16, phi_start := 0.0, phi_len := TAU, theta_start := 0.0, theta_len := PI) -> Geo:
	var g := _new()
	var theta_end := minf(theta_start + theta_len, PI)
	var grid := []
	for iy in hs + 1:
		var row := PackedInt32Array()
		var v := float(iy) / hs
		var uoff := 0.0
		if iy == 0 and theta_start == 0.0:
			uoff = 0.5 / ws
		elif iy == hs and theta_end == PI:
			uoff = -0.5 / ws
		for ix in ws + 1:
			var u := float(ix) / ws
			var p := Vector3(
				-r * cos(phi_start + u * phi_len) * sin(theta_start + v * theta_len),
				r * cos(theta_start + v * theta_len),
				r * sin(phi_start + u * phi_len) * sin(theta_start + v * theta_len))
			row.append(g.pos.size())
			g.pos.append(p)
			g.nor.append(p.normalized() if p.length_squared() > 0.0 else Vector3.UP)
			g.uv.append(Vector2(u + uoff, 1.0 - v))
		grid.append(row)
	for iy in hs:
		for ix in ws:
			var a: int = grid[iy][ix + 1]
			var b: int = grid[iy][ix]
			var c: int = grid[iy + 1][ix]
			var d: int = grid[iy + 1][ix + 1]
			if iy != 0 or theta_start > 0.0:
				g.tri(a, b, d)
			if iy != hs - 1 or theta_end < PI:
				g.tri(b, c, d)
	return g


static func torus(r: float, tube: float, radial := 12, tubular := 48, arc := TAU) -> Geo:
	var g := _new()
	for j in radial + 1:
		for i in tubular + 1:
			var u := float(i) / tubular * arc
			var v := float(j) / radial * TAU
			var p := Vector3((r + tube * cos(v)) * cos(u), (r + tube * cos(v)) * sin(u), tube * sin(v))
			var c := Vector3(r * cos(u), r * sin(u), 0)
			g.pos.append(p)
			g.nor.append((p - c).normalized())
			g.uv.append(Vector2(float(i) / tubular, float(j) / radial))
	for j in range(1, radial + 1):
		for i in range(1, tubular + 1):
			var a := (tubular + 1) * j + i - 1
			var b := (tubular + 1) * (j - 1) + i - 1
			var c := (tubular + 1) * (j - 1) + i
			var d := (tubular + 1) * j + i
			g.tri(a, b, d)
			g.tri(b, c, d)
	return g


## Lathe around y: points are (radius, height).
static func lathe(points: PackedVector2Array, segments := 12) -> Geo:
	var g := _new()
	var np := points.size()
	# Three.js r160 profile normals
	var init_n := PackedVector3Array()
	var prev := Vector3.ZERO
	for j in np:
		if j == 0:
			var d := points[1] - points[0]
			var n := Vector3(d.y, -d.x, 0)
			prev = n
			init_n.append(n.normalized())
		elif j == np - 1:
			init_n.append(prev)
		else:
			var d := points[j + 1] - points[j]
			var cur := Vector3(d.y, -d.x, 0)
			init_n.append((cur + prev).normalized())
			prev = cur
	for i in segments + 1:
		var phi := float(i) / segments * TAU
		var s := sin(phi)
		var c := cos(phi)
		for j in np:
			g.pos.append(Vector3(points[j].x * s, points[j].y, points[j].x * c))
			g.uv.append(Vector2(float(i) / segments, float(j) / (np - 1)))
			g.nor.append(Vector3(init_n[j].x * s, init_n[j].y, init_n[j].x * c).normalized())
	for i in segments:
		for j in np - 1:
			var base := j + i * np
			var a := base
			var b := base + np
			var c := base + np + 1
			var d := base + 1
			g.tri(a, b, d)
			g.tri(c, d, b)
	return g


## Flat disc in the XY plane facing +z (Three.js CircleGeometry).
static func circle(r: float, segments := 32) -> Geo:
	var g := _new()
	g.pos.append(Vector3.ZERO)
	g.nor.append(Vector3.BACK)
	g.uv.append(Vector2(0.5, 0.5))
	for s in segments + 1:
		var th := float(s) / segments * TAU
		g.pos.append(Vector3(r * cos(th), r * sin(th), 0))
		g.nor.append(Vector3.BACK)
		g.uv.append(Vector2(cos(th) * 0.5 + 0.5, sin(th) * 0.5 + 0.5))
	for i in range(1, segments + 1):
		g.tri(i, i + 1, 0)
	return g


## Flat ring in the XY plane facing +z.
static func ring(inner: float, outer: float, segments := 32) -> Geo:
	var g := _new()
	for j in 2:
		var r := inner if j == 0 else outer
		for i in segments + 1:
			var th := float(i) / segments * TAU
			g.pos.append(Vector3(r * cos(th), r * sin(th), 0))
			g.nor.append(Vector3.BACK)
			g.uv.append(Vector2(float(i) / segments, j))
	for i in segments:
		var a := i
		var b := i + segments + 1
		var c := i + segments + 2
		var d := i + 1
		g.tri(a, b, d)
		g.tri(b, c, d)
	return g


## Flat w x h rectangle in the XY plane facing +z.
static func plane(w: float, h: float) -> Geo:
	var g := _new()
	for y in 2:
		for x in 2:
			g.pos.append(Vector3((x - 0.5) * w, (0.5 - y) * h, 0))
			g.nor.append(Vector3.BACK)
			g.uv.append(Vector2(x, 1 - y))
	g.tri(0, 2, 1)
	g.tri(2, 3, 1)
	return g


const _ICO_T := 1.618033988749895
const ICO_V := [-1, _ICO_T, 0, 1, _ICO_T, 0, -1, -_ICO_T, 0, 1, -_ICO_T, 0, 0, -1, _ICO_T, 0, 1, _ICO_T, 0, -1, -_ICO_T,
	0, 1, -_ICO_T, _ICO_T, 0, -1, _ICO_T, 0, 1, -_ICO_T, 0, -1, -_ICO_T, 0, 1]
const ICO_I := [0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
	3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1]
const _DOD_R := 0.6180339887498948
const DOD_V := [-1, -1, -1, -1, -1, 1, -1, 1, -1, -1, 1, 1, 1, -1, -1, 1, -1, 1, 1, 1, -1, 1, 1, 1,
	0, -_DOD_R, -_ICO_T, 0, -_DOD_R, _ICO_T, 0, _DOD_R, -_ICO_T, 0, _DOD_R, _ICO_T,
	-_DOD_R, -_ICO_T, 0, -_DOD_R, _ICO_T, 0, _DOD_R, -_ICO_T, 0, _DOD_R, _ICO_T, 0,
	-_ICO_T, 0, -_DOD_R, _ICO_T, 0, -_DOD_R, -_ICO_T, 0, _DOD_R, _ICO_T, 0, _DOD_R]
const DOD_I := [3, 11, 7, 3, 7, 15, 3, 15, 13, 7, 19, 17, 7, 17, 6, 7, 6, 15, 17, 4, 8, 17, 8, 10, 17, 10, 6,
	8, 0, 16, 8, 16, 2, 8, 2, 10, 0, 12, 1, 0, 1, 18, 0, 18, 16, 6, 10, 2, 6, 2, 13, 6, 13, 15,
	2, 16, 18, 2, 18, 3, 2, 3, 13, 18, 1, 9, 18, 9, 11, 18, 11, 3, 4, 14, 12, 4, 12, 0, 4, 0, 8,
	11, 9, 5, 11, 5, 19, 11, 19, 7, 19, 5, 14, 19, 14, 4, 19, 4, 17, 1, 12, 14, 1, 14, 5, 1, 5, 9]
const OCT_V := [1, 0, 0, -1, 0, 0, 0, 1, 0, 0, -1, 0, 0, 0, 1, 0, 0, -1]
const OCT_I := [0, 2, 4, 0, 4, 3, 0, 3, 5, 0, 5, 2, 1, 2, 5, 1, 5, 3, 1, 3, 4, 1, 4, 2]


## Three.js PolyhedronGeometry: non-indexed, subdivided `detail` times, on a sphere of radius r.
## Normals: flat for detail 0, smooth (radial) otherwise, as in Three.js.
static func polyhedron(verts: Array, faces: Array, r: float, detail := 0) -> Geo:
	var g := _new()
	g.indexed = false
	var cols := detail + 1
	for f in range(0, faces.size(), 3):
		var a := Vector3(verts[faces[f] * 3], verts[faces[f] * 3 + 1], verts[faces[f] * 3 + 2])
		var b := Vector3(verts[faces[f + 1] * 3], verts[faces[f + 1] * 3 + 1], verts[faces[f + 1] * 3 + 2])
		var c := Vector3(verts[faces[f + 2] * 3], verts[faces[f + 2] * 3 + 1], verts[faces[f + 2] * 3 + 2])
		var v := []
		for i in cols + 1:
			var row := []
			var aj := a.lerp(c, float(i) / cols)
			var bj := b.lerp(c, float(i) / cols)
			var rows := cols - i
			for j in rows + 1:
				if j == 0 and i == cols:
					row.append(aj)
				else:
					row.append(aj.lerp(bj, float(j) / rows))
			v.append(row)
		for i in cols:
			for j in 2 * (cols - i) - 1:
				var k := j / 2
				if j % 2 == 0:
					g.pos.append(v[i][k + 1])
					g.pos.append(v[i + 1][k])
					g.pos.append(v[i][k])
				else:
					g.pos.append(v[i][k + 1])
					g.pos.append(v[i + 1][k + 1])
					g.pos.append(v[i + 1][k])
	for k in g.pos.size():
		g.pos[k] = g.pos[k].normalized() * r
		g.uv.append(Vector2.ZERO)
	if detail == 0:
		g.compute_normals()
	else:
		for p in g.pos:
			g.nor.append(p.normalized())
	return g


static func icosahedron(r: float, detail := 0) -> Geo:
	return polyhedron(ICO_V, ICO_I, r, detail)


static func dodecahedron(r: float, detail := 0) -> Geo:
	return polyhedron(DOD_V, DOD_I, r, detail)


static func octahedron(r: float, detail := 0) -> Geo:
	return polyhedron(OCT_V, OCT_I, r, detail)


## Three.js ExtrudeGeometry (no bevel): the outline (x, y) extruded from z = 0 to
## z = depth; non-indexed with flat normals.
static func extrude(outline: PackedVector2Array, depth: float) -> Geo:
	var pts := outline.duplicate()
	if pts.size() > 2 and pts[0].distance_to(pts[pts.size() - 1]) < 1e-6:
		pts.remove_at(pts.size() - 1)
	# counter-clockwise (seen from +z)
	var area := 0.0
	for i in pts.size():
		var p := pts[i]
		var q := pts[(i + 1) % pts.size()]
		area += p.x * q.y - q.x * p.y
	if area < 0.0:
		pts.reverse()
	var tris := Geometry2D.triangulate_polygon(pts)
	var g := _new()
	g.indexed = false
	var front := func(a: Vector3, b: Vector3, c: Vector3) -> void:
		g.pos.append(a)
		g.pos.append(b)
		g.pos.append(c)
	for t in range(0, tris.size(), 3):
		var a := pts[tris[t]]
		var b := pts[tris[t + 1]]
		var c := pts[tris[t + 2]]
		# make each cap triangle counter-clockwise seen from outside
		if (b - a).cross(c - a) < 0.0:
			var tmp := b
			b = c
			c = tmp
		front.call(Vector3(a.x, a.y, depth), Vector3(b.x, b.y, depth), Vector3(c.x, c.y, depth))
		front.call(Vector3(a.x, a.y, 0), Vector3(c.x, c.y, 0), Vector3(b.x, b.y, 0))
	for i in pts.size():
		var p := pts[i]
		var q := pts[(i + 1) % pts.size()]
		var a := Vector3(p.x, p.y, 0)
		var b := Vector3(q.x, q.y, 0)
		var c := Vector3(q.x, q.y, depth)
		var d := Vector3(p.x, p.y, depth)
		front.call(a, b, c)
		front.call(a, c, d)
	for k in g.pos.size():
		g.uv.append(Vector2.ZERO)
	g.compute_normals()
	return g


# ---- 2D outlines (Three.js Shape curves) --------------------------------------

## Points of a cubic Bezier from p0 (excluded) to p3, `div` steps.
static func bezier(out: PackedVector2Array, p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, div: int) -> void:
	for i in range(1, div + 1):
		var t := float(i) / div
		var u := 1.0 - t
		out.append(p0 * u * u * u + p1 * 3.0 * u * u * t + p2 * 3.0 * u * t * t + p3 * t * t * t)


## Points of a quadratic Bezier from p0 (excluded) to p2, `div` steps.
static func quadratic(out: PackedVector2Array, p0: Vector2, p1: Vector2, p2: Vector2, div: int) -> void:
	for i in range(1, div + 1):
		var t := float(i) / div
		var u := 1.0 - t
		out.append(p0 * u * u + p1 * 2.0 * u * t + p2 * t * t)
