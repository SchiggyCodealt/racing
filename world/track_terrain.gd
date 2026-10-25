## track_terrain.gd (buildTerrain of web/src/game/trackMesh.js)
## ------------------------------------------------------------------
## A large terrain around a track: flat under and around the road (at the
## road-side level G of the track analysis), gentle hills further out and a
## ring of mountains (or stepped mesas) towards the horizon; on seaside
## tracks the land slopes into the sea beyond a ragged shoreline. Vertex
## colours come from slope, height, noise and distance to the road. Also a
## far ground disc under everything and (seaside) the sea plane.
##
## The big noise loops use FastNoiseLite (same kind of value-noise fbm as the
## JS, not the same values): GDScript is far too slow for ~1M JS noise calls.
## Queries for the scenery: height_at (exactly as the triangles interpolate),
## edge_dist (distance beyond the nearest road edge), flatness, sea_at.
extends RefCounted

const VNoise = preload("res://world/noise.gd")
const Themes = preload("res://world/themes.gd")
const TrackCtx = preload("res://world/track_ctx.gd")
const Tex = preload("res://world/textures.gd")

const ZONE := TrackCtx.ZONE
const BLEND_R := 190.0

var x0 := 0.0
var z0 := 0.0
var W := 0.0
var H := 0.0
var min_x := 0.0
var max_x := 0.0
var min_z := 0.0
var max_z := 0.0
var cell := 6.0
var NX := 0
var NZ := 0
var hgt := PackedFloat32Array()
var E := PackedFloat32Array()
var SEA := PackedFloat32Array()
var up := PackedFloat32Array()  # y of the vertex normals (flatness)
var base := 0.0
var plane_y := 0.0
var has_water := false
var water_y := 0.0
var vertex_count := 0
## the terrain geometry (positions, normals, uvs, colours, indices), split into chunks by TrackMesh
var arrays: Array = []
var material: StandardMaterial3D
var far_plane: MeshInstance3D
var water: MeshInstance3D


func build(ctx: TrackCtx) -> void:
	var t := ctx.track
	var theme := ctx.theme
	var n_s := t.count
	var seed := ctx.seed
	min_x = INF
	max_x = -INF
	min_z = INF
	max_z = -INF
	for i in n_s:
		min_x = minf(min_x, t.px[i])
		max_x = maxf(max_x, t.px[i])
		min_z = minf(min_z, t.pz[i])
		max_z = maxf(max_z, t.pz[i])
	var margin := 1150.0
	x0 = min_x - margin
	z0 = min_z - margin
	W = max_x - min_x + 2.0 * margin
	H = max_z - min_z + 2.0 * margin
	cell = maxf(6.0, sqrt(W * H / 78000.0))
	NX = ceili(W / cell) + 1
	NZ = ceili(H / cell) + 1
	var NV := NX * NZ
	vertex_count = NV

	E.resize(NV)
	E.fill(1e9)  # distance beyond the nearest road edge
	var WS := PackedFloat32Array()
	var WG := PackedFloat32Array()
	var CAP := PackedFloat32Array()
	WS.resize(NV)
	WG.resize(NV)
	CAP.resize(NV)
	CAP.fill(1e9)

	# stamps: every sample caps the terrain under the road; every third (and the pads) also
	# blends the land towards the road-side level G
	var stamps: Array[PackedFloat32Array] = []
	for i in n_s:
		stamps.append(PackedFloat32Array([t.px[i], t.pz[i], t.hw[i], ctx.G[i], 1.0 if i % 3 != 0 else 0.0]))
	for pad in ctx.pads:
		for p: Vector2 in pad["pts"]:
			stamps.append(PackedFloat32Array([p.x, p.y, pad["r"], pad["y"], 0.0]))
	for st in stamps:
		var x := st[0]
		var z := st[1]
		var h := st[2]
		var g := st[3]
		var cap_only := st[4] > 0.5
		var cap_r := h + ZONE + cell * 1.5
		var R := cap_r if cap_only else h + BLEND_R
		var i0 := maxi(0, floori((x - R - x0) / cell))
		var i1 := mini(NX - 1, ceili((x + R - x0) / cell))
		var k0 := maxi(0, floori((z - R - z0) / cell))
		var k1 := mini(NZ - 1, ceili((z + R - z0) / cell))
		var R2 := R * R
		var cap_r2 := cap_r * cap_r
		for k in range(k0, k1 + 1):
			var dz := z0 + k * cell - z
			var dz2 := dz * dz
			if dz2 > R2:
				continue
			var row := k * NX
			for i in range(i0, i1 + 1):
				var dx := x0 + i * cell - x
				var d2 := dx * dx + dz2
				if d2 > R2:
					continue
				var v := row + i
				var e := sqrt(d2) - h
				if e < E[v]:
					E[v] = e
				if d2 <= cap_r2 and g < CAP[v]:
					CAP[v] = g
				if not cap_only:
					var q := (e if e > 0.0 else 0.0) / 22.0
					var q2 := q * q
					var w := 1.0 / (1.0 + q2 * q2)
					WS[v] += w
					WG[v] += w * g

	# Chamfer distance transform: approximate distance far from the track.
	var dS := cell
	var dD := cell * sqrt(2.0)
	for k in NZ:
		for i in NX:
			var v := k * NX + i
			var m := E[v]
			if i > 0:
				m = minf(m, E[v - 1] + dS)
			if k > 0:
				m = minf(m, E[v - NX] + dS)
				if i > 0:
					m = minf(m, E[v - NX - 1] + dD)
				if i < NX - 1:
					m = minf(m, E[v - NX + 1] + dD)
			E[v] = m
	for k in range(NZ - 1, -1, -1):
		for i in range(NX - 1, -1, -1):
			var v := k * NX + i
			var m := E[v]
			if i < NX - 1:
				m = minf(m, E[v + 1] + dS)
			if k < NZ - 1:
				m = minf(m, E[v + NX] + dS)
				if i < NX - 1:
					m = minf(m, E[v + NX + 1] + dD)
				if i > 0:
					m = minf(m, E[v + NX - 1] + dD)
			E[v] = m

	# Base level of the land: a low percentile of the road-side level.
	var sorted := ctx.G.duplicate()
	sorted.sort()
	base = minf(sorted[int(floorf(sorted.size() * 0.25))], 0.5)
	var min_g := base
	for i in n_s:
		min_g = minf(min_g, ctx.G[i])
	var hills: float = theme["hills"]
	var mountains: float = theme["mountains"]
	plane_y = minf(base - 2.0 - hills, min_g - 2.0)
	hgt.resize(NV)
	var mesa: bool = theme["mountainStyle"] == "mesa"
	# Seaside: the share of sea at each vertex (0 = land, 1 = open water) and the water level.
	has_water = ctx.has_coast
	var coast := ctx.coast
	var env: TrackCtx.Envelope = coast.get("env") if has_water else null
	var c_dx: float = coast.get("dx", 0.0)
	var c_dz: float = coast.get("dz", 0.0)
	var c_level: float = coast.get("level", 0.0)
	var c_off: float = coast.get("off", 0.0)
	if has_water:
		water_y = minf(base, min_g) - c_level  # below the lowest ground beside the road
		SEA.resize(NV)
	# noise (FastNoiseLite, see the header): fbm(x*0.0032, 4), fbm(x*0.011, 2), ridges, coast wiggle
	var n_hills := VNoise.fast_fbm(seed, 4)
	var n_hills2 := VNoise.fast_fbm(seed + 5, 2)
	var n_mesa := VNoise.fast_fbm(seed + 7, 4)
	var n_coast := VNoise.fast_fbm(seed + 13, 2)
	var n_ridge: Array[FastNoiseLite] = []
	for o in 5:
		n_ridge.append(VNoise.fast_fbm(seed + 11 + o, 1))
	for k in NZ:
		var z := z0 + k * cell
		for i in NX:
			var x := x0 + i * cell
			var v := k * NX + i
			var e := E[v]
			var gN := WG[v] / WS[v] if WS[v] > 1e-4 else base
			var t1 := _ss(ZONE, BLEND_R, e)
			var h := gN
			if t1 > 0.0:
				var n1 := 0.5 + 0.5 * n_hills.get_noise_2d(x * 0.0032, z * 0.0032)
				var hl := hills * (n1 - 0.4) * 2.2 + hills * 0.25 * (0.5 * n_hills2.get_noise_2d(x * 0.011, z * 0.011))
				h = gN + (base + hl - gN) * t1
			var t2 := _ss(330.0, 950.0, e)
			if t2 > 0.0:
				var ms := 0.0
				if mesa:
					var nm := 0.5 + 0.5 * n_mesa.get_noise_2d(x * 0.0021, z * 0.0021)
					var mv := clampf((nm - 0.43) * 3.2, 0.0, 1.0)
					var tt := mv * 3.0
					var fl := minf(2.0, floorf(tt))
					var fr := tt - fl
					ms = (fl + _ss(0.68, 0.93, fr)) / 3.0 * 0.85 + mv * 0.15
				else:
					var sum := 0.0
					var amp := 0.55
					var freq := 0.0019
					var prev := 1.0
					for o in 5:
						var r := 1.0 - absf(n_ridge[o].get_noise_2d(x * freq, z * freq))
						r *= r
						sum += r * amp * prev
						prev = r
						amp *= 0.5
						freq *= 2.1
					ms = maxf(0.0, sum * 1.35 - 0.18)
				h += mountains * t2 * ms
			if has_water:
				# no inland ponds: the land stays `level` m or more above the water (a smooth floor, so the
				# depth buffer never mixes land and water far away); beyond a ragged shoreline (at least
				# ~25 m off the road) the land slopes down under the water
				var fl2 := water_y + c_level
				h = (h + fl2 + sqrt((h - fl2) * (h - fl2) + 1.0)) / 2.0
				var p := x * c_dx + z * c_dz
				var shore := env.at(z * c_dx - x * c_dz) + c_off + 44.0 * (0.5 * n_coast.get_noise_2d(x * 0.005, z * 0.005))
				var ts := _ss(shore - 15.0, shore + 40.0, p) * _ss(ZONE + 10.0, ZONE + 45.0, e)
				if ts > 0.0:
					h += (water_y - 1.0 - 7.0 * _ss(shore, shore + 260.0, p) - h) * ts
				SEA[v] = ts
			if h < plane_y + 0.3:
				h = plane_y + 0.3
			var de := minf(minf(x - x0, x0 + W - x), minf(z - z0, z0 + H - z))
			var f := _ss(0.0, 280.0, de)
			h = (plane_y - 1.0) + (h - (plane_y - 1.0)) * f
			if CAP[v] < h:
				h = CAP[v]
			hgt[v] = h

	_build_geometry(ctx)
	_build_planes(ctx)


## Regular grid, triangles (a,c,b) and (b,c,d) per cell; smooth normals; vertex colours.
func _build_geometry(ctx: TrackCtx) -> void:
	var theme := ctx.theme
	var seed := ctx.seed
	var NV := NX * NZ
	var pos := PackedVector3Array()
	var uv := PackedVector2Array()
	pos.resize(NV)
	uv.resize(NV)
	for k in NZ:
		for i in NX:
			var v := k * NX + i
			var x := x0 + i * cell
			var z := z0 + k * cell
			pos[v] = Vector3(x, hgt[v], z)
			uv[v] = Vector2(x / 7.0, z / 7.0)
	# Godot winding (clockwise front faces): (a,b,c) and (b,d,c) per cell
	var idx := PackedInt32Array()
	idx.resize((NX - 1) * (NZ - 1) * 6)
	var p := 0
	for k in NZ - 1:
		for i in NX - 1:
			var a := k * NX + i
			var b := a + 1
			var c := a + NX
			var d := c + 1
			idx[p] = a
			idx[p + 1] = b
			idx[p + 2] = c
			idx[p + 3] = b
			idx[p + 4] = d
			idx[p + 5] = c
			p += 6
	# smooth normals from the height field (central differences: the same as the
	# area-weighted triangle normals of a regular grid, up to the diagonal)
	var nor := PackedVector3Array()
	nor.resize(NV)
	up.resize(NV)
	for k in NZ:
		var k0 := maxi(0, k - 1)
		var k1 := mini(NZ - 1, k + 1)
		for i in NX:
			var i0 := maxi(0, i - 1)
			var i1 := mini(NX - 1, i + 1)
			var dx := (hgt[k * NX + i1] - hgt[k * NX + i0]) / ((i1 - i0) * cell)
			var dz := (hgt[k1 * NX + i] - hgt[k0 * NX + i]) / ((k1 - k0) * cell)
			var n := Vector3(-dx, 1.0, -dz).normalized()
			nor[k * NX + i] = n
			up[k * NX + i] = n.y

	# Vertex colours from slope, height, noise and distance to the road.
	var gc: Dictionary = theme["ground"]
	var cA := Themes.lin(gc["a"])
	var cB := Themes.lin(gc["b"])
	var cDry := Themes.lin(gc["dry"])
	var cDirt := Themes.lin(gc["dirt"])
	var cRock := Themes.lin(gc["rock"])
	var has_snow: bool = int(gc["snow"]) >= 0
	var cSnow := Themes.lin(gc["snow"]) if has_snow else Color.WHITE
	var cStrata: Array[Color] = [cRock, cDry, cDirt, cB]
	var cSand := Color.WHITE
	var cShallow := Color.WHITE
	var cDeep := Color.WHITE
	if has_water:
		cSand = Themes.lin(ctx.coast["sand"])
		cShallow = Themes.lin(ctx.coast["shallow"])
		cDeep = Themes.lin(ctx.coast["deep"])
	var mesa: bool = theme["mountainStyle"] == "mesa"
	var n3 := VNoise.fast_fbm(seed + 3, 3)
	var n4 := VNoise.fast_fbm(seed + 4, 1)
	var n9 := VNoise.fast_fbm(seed + 9, 2)
	var col := PackedColorArray()
	col.resize(NV)
	for k in NZ:
		var z := z0 + k * cell
		for i in NX:
			var x := x0 + i * cell
			var v := k * NX + i
			var slope := 1.0 - up[v]
			var h := hgt[v] - base
			var n := 0.5 + 0.5 * n3.get_noise_2d(x * 0.018, z * 0.018)
			var n2 := 0.5 + 0.5 * n4.get_noise_2d(x * 0.11, z * 0.11)
			var c := cA.lerp(cB, _ss(0.35, 0.65, n))
			c = c.lerp(cDry, _ss(0.55, 0.8, 0.5 + 0.5 * n9.get_noise_2d(x * 0.005, z * 0.005)) * 0.55)
			var e := E[v]
			if e < 6.0:
				c = c.lerp(cDirt, 0.3 * (1.0 - maxf(0.0, e) / 6.0))
			if mesa and h > 6.0:
				var band := int(floorf(h / 7.0 + n * 0.8)) & 3
				c = c.lerp(cStrata[band], _ss(6.0, 22.0, h) * 0.85)
			c = c.lerp(cRock, _ss(0.2, 0.42, slope + (n2 - 0.5) * 0.12))
			if has_snow:
				var line := 70.0 + n * 50.0
				c = c.lerp(cSnow, _ss(line, line + 30.0, h) * (1.0 - _ss(0.38, 0.6, slope)))
			if has_water and SEA[v] > 0.001:
				# a sandy beach down to the water line, then the sea bed darkening with depth
				# (seen through the water, which is slightly see-through)
				c = c.lerp(cSand, _ss(0.0, 0.2, SEA[v] + (n2 - 0.5) * 0.06))
				var depth := water_y - hgt[v]
				if depth > 0.0:
					c = c.lerp(cShallow, _ss(0.0, 1.5, depth)).lerp(cDeep, _ss(1.5, 6.0, depth))
			# the JS also multiplies by 1/0.86 (the detail texture darkens by ~14 % on average):
			# that is in the material colour here, vertex colours stay <= 1
			var j := 0.93 + n2 * 0.14
			col[v] = Color(c.r * j, c.g * j, c.b * j).linear_to_srgb()
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nor
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_COLOR] = col
	arrays[Mesh.ARRAY_INDEX] = idx

	material = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.albedo_texture = Tex.detail()
	material.albedo_color = Tex.BOOST  # 1/0.86 (see above)
	material.roughness = 0.94
	material.metallic = 0.0
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC


func _build_planes(ctx: TrackCtx) -> void:
	var gc: Dictionary = ctx.theme["ground"]
	var cx := (min_x + max_x) / 2.0
	var cz := (min_z + max_z) / 2.0
	far_plane = MeshInstance3D.new()
	far_plane.name = "far-ground"
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Themes.col(gc["far"])
	fm.roughness = 1.0
	far_plane.mesh = _disc(16000.0, 48, fm)
	far_plane.position = Vector3(cx, plane_y, cz)
	far_plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The sea: one big, slightly see-through plane at the water level, with drifting ripples.
	if has_water:
		water = MeshInstance3D.new()
		water.name = "sea"
		var wm := ShaderMaterial.new()
		wm.shader = preload("res://world/shaders/water.gdshader")
		wm.set_shader_parameter("water_color", Themes.col(ctx.coast["water"]))
		wm.set_shader_parameter("normal_map", Tex.water_normal())
		water.mesh = _disc(16000.0, 64, wm)
		water.position = Vector3(cx, water_y, cz)
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Flat disc facing up (Three.js CircleGeometry rotated flat), uv = world xz / 24 m for the water ripples.
static func _disc(r: float, segs: int, mat: Material) -> ArrayMesh:
	var pos := PackedVector3Array([Vector3.ZERO])
	var nor := PackedVector3Array([Vector3.UP])
	var uv := PackedVector2Array([Vector2.ZERO])
	var idx := PackedInt32Array()
	for k in segs + 1:
		var a := float(k) / segs * TAU
		var p := Vector3(cos(a) * r, 0.0, -sin(a) * r)
		pos.append(p)
		nor.append(Vector3.UP)
		uv.append(Vector2(p.x, p.z) / 24.0)
	for k in segs:
		# clockwise seen from above (Godot front face up)
		idx.append_array([0, k + 2, k + 1])
	var a2 := []
	a2.resize(Mesh.ARRAY_MAX)
	a2[Mesh.ARRAY_VERTEX] = pos
	a2[Mesh.ARRAY_NORMAL] = nor
	a2[Mesh.ARRAY_TEX_UV] = uv
	a2[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a2)
	m.surface_set_material(0, mat)
	return m


## Terrain height at (x, z), exactly as the triangles interpolate it.
func height_at(x: float, z: float) -> float:
	var fx := clampf((x - x0) / cell, 0.0, NX - 1.001)
	var fz := clampf((z - z0) / cell, 0.0, NZ - 1.001)
	var i := int(fx)
	var k := int(fz)
	var u := fx - i
	var w := fz - k
	var a := k * NX + i
	var ha := hgt[a]
	var hb := hgt[a + 1]
	var hc := hgt[a + NX]
	var hd := hgt[a + NX + 1]
	if u + w <= 1.0:
		return ha + (hb - ha) * u + (hc - ha) * w
	return hd + (hc - hd) * (1.0 - u) + (hb - hd) * (1.0 - w)


## Approximate distance beyond the nearest road edge (bilinear).
func edge_dist(x: float, z: float) -> float:
	var fx := (x - x0) / cell
	var fz := (z - z0) / cell
	if fx < 0.0 or fz < 0.0 or fx > NX - 1.001 or fz > NZ - 1.001:
		return 1e9
	var i := int(fx)
	var k := int(fz)
	var u := fx - i
	var w := fz - k
	var a := k * NX + i
	return (E[a] * (1.0 - u) + E[a + 1] * u) * (1.0 - w) + (E[a + NX] * (1.0 - u) + E[a + NX + 1] * u) * w


## Up-facing component of the terrain normal (1 = flat).
func flatness(x: float, z: float) -> float:
	var i := clampi(roundi((x - x0) / cell), 0, NX - 1)
	var k := clampi(roundi((z - z0) / cell), 0, NZ - 1)
	return up[k * NX + i]


## Share of open water at (x, z): 0 on land (and off the terrain), 1 out at sea (bilinear).
func sea_at(x: float, z: float) -> float:
	if not has_water:
		return 0.0
	var fx := (x - x0) / cell
	var fz := (z - z0) / cell
	if fx < 0.0 or fz < 0.0 or fx > NX - 1.001 or fz > NZ - 1.001:
		return 0.0
	var i := int(fx)
	var k := int(fz)
	var u := fx - i
	var w := fz - k
	var a := k * NX + i
	return (SEA[a] * (1.0 - u) + SEA[a + 1] * u) * (1.0 - w) + (SEA[a + NX] * (1.0 - u) + SEA[a + NX + 1] * u) * w


static func _ss(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
