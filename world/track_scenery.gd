## track_scenery.gd (addProps, addScenery, addSetPieces of web/src/game/trackMesh.js)
## ------------------------------------------------------------------
## Trackside props (lamp posts with light pools, chevron boards, sponsor
## banners, a grandstand), the themed instanced scenery (trees, cacti,
## rocks, ... and grass tufts near the road) and the theme set pieces (a
## lighthouse and boats by the sea, a lit city skyline at night).
##
## Repeated things are MultiMeshInstance3D: each scenery species is split
## into a 3 x 3 grid of chunks (so the camera and the shadow splits skip
## the far ones), with the instances in a scattered order so a lower quality
## level, which draws only the first part (visible_instance_count), thins
## them evenly. The species meshes are procedural low-poly shapes with
## vertex colours (a darker base as fake ambient occlusion), the same
## shapes and random draws as the JS.
extends RefCounted

const Geo = preload("res://world/geo.gd")
const Themes = preload("res://world/themes.gd")
const VNoise = preload("res://world/noise.gd")
const Tex = preload("res://world/textures.gd")
const TrackCtx = preload("res://world/track_ctx.gd")
const POOL_SHADER = preload("res://world/shaders/lamp_pool.gdshader")
const SKYLINE_SHADER = preload("res://world/shaders/skyline.gdshader")

const BARRIER_H := TrackCtx.BARRIER_H
const BARRIER_W := TrackCtx.BARRIER_W
const ZONE := TrackCtx.ZONE
const WHITE := Color(1, 1, 1)
const NO_TINT := Color(1, 1, 1, 0)

## Scenery species: scale range, min flatness of the ground, random tilt, sink into the
## ground (x scale), hue and brightness spread, weight (default 1), max height, receive.
const SPECIES := {
	"broadleaf": {"scale": [0.8, 1.35], "minFlat": 0.82, "tilt": 0.06, "sink": 0.2, "hue": 0.06, "light": 0.18},
	"pine": {"scale": [0.75, 1.4], "minFlat": 0.8, "tilt": 0.05, "sink": 0.2, "hue": 0.04, "light": 0.16},
	"pineSnow": {"scale": [0.75, 1.45], "minFlat": 0.8, "tilt": 0.05, "sink": 0.2, "hue": 0.02, "light": 0.1, "maxHeight": 160.0},
	"bush": {"scale": [0.7, 1.6], "minFlat": 0.75, "tilt": 0.1, "sink": 0.25, "hue": 0.06, "light": 0.18},
	"rock": {"scale": [0.6, 2.6], "minFlat": 0.5, "tilt": 0.4, "sink": 0.35, "hue": 0.02, "light": 0.15, "receive": true},
	"rockGrey": {"scale": [0.7, 3.0], "minFlat": 0.45, "tilt": 0.4, "sink": 0.35, "hue": 0.02, "light": 0.12, "receive": true},
	"rockRed": {"scale": [0.6, 2.8], "minFlat": 0.45, "tilt": 0.4, "sink": 0.35, "hue": 0.03, "light": 0.15, "receive": true},
	"saguaro": {"scale": [0.75, 1.3], "minFlat": 0.85, "tilt": 0.04, "sink": 0.1, "hue": 0.03, "light": 0.12},
	"barrel": {"weight": 0.7, "scale": [0.7, 1.5], "minFlat": 0.8, "tilt": 0.1, "sink": 0.1, "hue": 0.04, "light": 0.12},
	"shrubDry": {"scale": [0.6, 1.6], "minFlat": 0.7, "tilt": 0.15, "sink": 0.15, "hue": 0.05, "light": 0.15},
	"hoodoo": {"weight": 0.22, "scale": [0.6, 1.4], "minFlat": 0.6, "tilt": 0.05, "sink": 0.5, "hue": 0.02, "light": 0.1, "receive": true},
	"juniper": {"weight": 1.3, "scale": [0.8, 1.5], "minFlat": 0.75, "tilt": 0.08, "sink": 0.15, "hue": 0.04, "light": 0.12},
	"palm": {"weight": 1.6, "scale": [0.8, 1.3], "minFlat": 0.8, "tilt": 0.04, "sink": 0.15, "hue": 0.05, "light": 0.14},
	"bushCoast": {"scale": [0.6, 1.4], "minFlat": 0.7, "tilt": 0.12, "sink": 0.2, "hue": 0.06, "light": 0.16},
}


# =============================================================================
# Props: lamps, chevrons, banners, grandstand
# =============================================================================

static func add_props(node: Node3D, c: TrackCtx) -> void:
	var t := c.track
	var theme := c.theme
	var lit: bool = theme.get("lamps", false)

	# ---- lamp posts on the barrier tops ----
	var lamps: Array[Vector2i] = []  # (sample, side)
	var step := maxi(14, roundi(46.0 / t.seg_len))
	var n := 0
	var k := 6
	while k < c.segs - 2:
		var i := c.wrap(k)
		k += step
		if c.near_gate(i, 6):
			continue
		var s := 1 if n % 2 else -1
		n += 1
		lamps.append(Vector2i(i, s))
	var xfs: Array[Transform3D] = []
	for l in lamps:
		var i := l.x
		var s := float(l.y)
		var o := t.hw[i] + 0.44
		var p := Vector3(t.px[i] + t.nx[i] * s * o, c.edge_y(i, s) + BARRIER_H, t.pz[i] + t.nz[i] * s * o)
		xfs.append(Transform3D(Basis(Vector3.UP, atan2(s * t.nz[i], -s * t.nx[i])), p))
	if not lamps.is_empty():
		var pole_mat := _std(Themes.col(0x5b6069), 0.45, 0.7)
		_fade(pole_mat)
		var poles := _multimesh(_lamp_post_geometry().to_mesh(pole_mat), xfs, [], "lamp-posts")
		poles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		node.add_child(poles)
		var head_mat := _std(Themes.col(0xfff4e0), 0.3)
		head_mat.emission_enabled = true
		head_mat.emission = Themes.col(0xffd9a0)
		head_mat.emission_energy_multiplier = 7.0 if lit else 0.25
		_fade(head_mat)
		var heads := _multimesh(Geo.box(1.0, 0.16, 0.42).translate(2.25, 7.38, 0.0).to_mesh(head_mat), xfs, [], "lamp-heads")
		heads.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(heads)

	if lit and not lamps.is_empty():
		# light pools on the road under the lamps (additive decals)
		var b := Geo.new()
		for l in lamps:
			var i := l.x
			var s := float(l.y)
			var cl := s * (t.hw[i] + 0.44 - 2.25)
			var R := 8.0
			var rows := 4
			var prev: Array = []
			for r in range(-rows, rows + 1):
				var j := c.wrap(i + r)
				var la := minf(t.hw[j], cl + R)
				var lb := maxf(-t.hw[j], cl - R)
				var v := r * t.seg_len / (2.0 * R) + 0.5
				var ua := (la - cl) / (2.0 * R) + 0.5
				var ub := (lb - cl) / (2.0 * R) + 0.5
				var row := [c.P(j, la, 0.03), c.P(j, lb, 0.03), Vector2(ua, v), Vector2(ub, v)]
				if not prev.is_empty():
					b.quad_uv(prev[0], row[0], row[1], prev[1], prev[2], row[2], row[3], prev[3], WHITE, Vector3.UP)
				prev = row
		var pm := ShaderMaterial.new()
		pm.shader = POOL_SHADER
		pm.set_shader_parameter("glow_tex", Tex.glow())
		pm.set_shader_parameter("tint", Themes.col(0xffb877))
		pm.set_shader_parameter("opacity", 0.5)
		var pool := MeshInstance3D.new()
		pool.name = "lamp-pools"
		pool.mesh = b.to_mesh(pm, true, false)
		pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(pool)
		node.set("lamp_pool", pool)
		# Godot extra (high quality): a real light under every lamp head, which also lights the cars
		var lights: Array[Light3D] = []
		for x in xfs:
			var sl := SpotLight3D.new()
			sl.light_color = Themes.col(0xffc890)
			sl.light_energy = 6.0
			sl.spot_range = 15.0
			sl.spot_angle = 62.0
			sl.spot_angle_attenuation = 0.6
			sl.spot_attenuation = 1.2
			sl.shadow_enabled = false
			sl.light_specular = 0.4
			sl.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), x * Vector3(2.25, 7.2, 0.0))
			sl.visible = false
			sl.distance_fade_enabled = true
			sl.distance_fade_begin = 260.0
			sl.distance_fade_length = 60.0
			node.add_child(sl)
			lights.append(sl)
		node.set("lamp_lights", lights)

	# ---- chevron boards on the outside of tight corners ----
	var cb := Geo.new()
	k = 0
	while k < c.segs:
		var i := c.wrap(k)
		var j := c.wrap(k + 1)
		k += 4
		if absf(c.kappa[i]) < 1.0 / 55.0 or c.near_gate(i, 5):
			continue
		var s := -1.0 if c.kappa[i] > 0.0 else 1.0  # outer side
		var o := t.hw[i] + 0.3
		var oj := t.hw[j] + 0.3
		var y0 := c.edge_y(i, s) + BARRIER_H + 0.05
		var y0j := c.edge_y(j, s) + BARRIER_H + 0.05
		var A := Vector3(t.px[i] + t.nx[i] * s * o, y0, t.pz[i] + t.nz[i] * s * o)
		var B := Vector3(t.px[j] + t.nx[j] * s * oj, y0j, t.pz[j] + t.nz[j] * s * oj)
		cb.quad_uv(A, B, Vector3(B.x, y0j + 1.0, B.z), Vector3(A.x, y0 + 1.0, A.z), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), WHITE)
	if cb.count() > 0:
		var cm := _std(Color.WHITE, 0.5)
		cm.albedo_texture = Tex.chevron()
		cm.cull_mode = BaseMaterial3D.CULL_DISABLED
		cm.emission_enabled = true
		cm.emission = Color.WHITE
		cm.emission_texture = Tex.chevron()
		cm.emission_energy_multiplier = 0.5 if lit else 0.08
		_fade(cm)
		var mi := MeshInstance3D.new()
		mi.name = "chevrons"
		mi.mesh = cb.to_mesh(cm, true, false)
		node.add_child(mi)

	# ---- banners on the barrier tops along straights ----
	var banner_b := Geo.new()
	var lamp_at := {}
	for l in lamps:
		lamp_at[l] = true
	var bstep := maxi(20, roundi(130.0 / t.seg_len))
	n = 0
	k = 10
	while k < c.segs - 4:
		var i := c.wrap(k)
		k += bstep
		var straight := true
		for d in range(-2, 5):
			if absf(c.kappa[c.wrap(i + d)]) > 1.0 / 300.0:
				straight = false
		if not straight or c.near_gate(i, 8):
			continue
		var s := 1 if n % 2 else -1
		var near_lamp := false
		for d in range(-4, 5):
			if lamp_at.has(Vector2i(c.wrap(i + d), s)):
				near_lamp = true
		if near_lamp:
			continue
		var row := n % 4
		n += 1
		var prev: Array = []
		for d in 4:
			var j := c.wrap(i + d)
			var o := t.hw[j] + 0.32
			var y := c.edge_y(j, s) + BARRIER_H + 0.02
			var p0 := Vector3(t.px[j] + t.nx[j] * s * o, y, t.pz[j] + t.nz[j] * s * o)
			var p1 := Vector3(p0.x, y + 1.25, p0.z)
			# banners read left to right from the road
			var u := d / 3.0 if s > 0 else 1.0 - d / 3.0
			var va := (row + 1) / 4.0
			var vb := row / 4.0
			if not prev.is_empty():
				banner_b.quad_uv(prev[0], p0, p1, prev[1], Vector2(prev[2], va), Vector2(u, va), Vector2(u, vb), Vector2(prev[2], vb), WHITE)
			prev = [p0, p1, u]

	# ---- grandstand ----
	var pad := c.pad("grandstand")
	if not pad.is_empty():
		var gs := _grandstand_geometry(pad, theme, c.seed, banner_b)
		var gm := _std(Color.WHITE, 0.75, 0.05)
		gm.vertex_color_use_as_albedo = true
		gm.vertex_color_is_srgb = true
		var mi := MeshInstance3D.new()
		mi.name = "grandstand"
		mi.mesh = gs.to_mesh(gm)
		node.add_child(mi)

	if banner_b.count() > 0:
		var tex := Tex.banner()
		var bm := _std(Color.WHITE, 0.6)
		bm.albedo_texture = tex
		bm.cull_mode = BaseMaterial3D.CULL_DISABLED
		bm.emission_enabled = true
		bm.emission = Color.WHITE
		bm.emission_texture = tex
		bm.emission_energy_multiplier = 0.45 if lit else 0.06
		_fade(bm)
		var mi := MeshInstance3D.new()
		mi.name = "banners"
		mi.mesh = banner_b.to_mesh(bm, true, false)
		node.add_child(mi)


static func _lamp_post_geometry() -> Geo:
	var b := Geo.new()
	b.add_geometry(Geo.cylinder(0.09, 0.13, 7.6, 8).translate(0, 3.8, 0))
	b.add_geometry(Geo.cylinder(0.06, 0.06, 2.4, 6).rotate_z(PI / 2.0 + 0.08).translate(1.15, 7.5, 0))
	b.add_geometry(Geo.cylinder(0.2, 0.24, 0.3, 8).translate(0, 0.15, 0))
	return b


## Tiered seating with a crowd, roof and a sponsor banner. Local x along the track, z away from it.
static func _grandstand_geometry(pad: Dictionary, theme: Dictionary, seed: int, banner_b: Geo) -> Geo:
	var b := Geo.new()
	var rnd := VNoise.Rng.new(seed ^ 0x51a7)
	var ax: float = pad["ax"]
	var az: float = pad["az"]
	var ox: float = pad["ox"]
	var oz: float = pad["oz"]
	var D: float = pad["D"]
	var L: float = pad["L"]
	var basis := Basis(Vector3(ax, 0, az), Vector3.UP, Vector3(ox, 0, oz))
	# the basis may be mirrored: keep it right-handed by flipping x
	if basis.determinant() < 0.0:
		basis = Basis(Vector3(-ax, 0, -az), Vector3.UP, Vector3(ox, 0, oz))
	var m := Transform3D(basis, Vector3(float(pad["cx"]) - ox * (D / 2.0), pad["y"], float(pad["cz"]) - oz * (D / 2.0)))
	var concrete := Themes.lin(0xb7b4ae)
	var dark_c := Themes.lin(0x8d8a85)
	var seat := Themes.lin(theme["accent"][0])
	var roof_c := Themes.lin(0xe9ecef)
	var steel := Themes.lin(0x5b6069)
	# foundation and front wall
	b.box_at(m, Vector3(0, -1.2, D / 2.0), Vector3(L + 1.0, 3.0, D + 1.0), dark_c)
	b.box_at(m, Vector3(0, 0.9, 0.9), Vector3(L, 1.2, 0.3), concrete)
	var rows := 9
	var tread := 1.15
	var rise := 0.55
	var crowd := [0xe8423f, 0x2f7de1, 0xf5c542, 0xffffff, 0x2a2a2a, 0x46b05a, 0xf08a3c, 0x9b59d0, 0x1fb6c9]
	for r in rows:
		var z := 1.6 + r * tread
		var y := 0.6 + r * rise
		b.box_at(m, Vector3(0, y / 2.0, z + tread / 2.0), Vector3(L, y, tread), concrete)
		b.box_at(m, Vector3(0, y + 0.18, z + tread * 0.55), Vector3(L - 0.4, 0.12, 0.45), seat)
		var x := -L / 2.0 + 0.6
		while x < L / 2.0 - 0.4:
			if rnd.next() < 0.18:
				x += 0.75
				continue
			var cc := Themes.lin(crowd[int(floorf(rnd.next() * crowd.size()))])
			var h := 0.75 + rnd.next() * 0.2
			b.box_at(m, Vector3(x + (rnd.next() - 0.5) * 0.15, y + 0.2 + h / 2.0, z + tread * 0.5), Vector3(0.42, h, 0.32), cc)
			var skin := Themes.lin(0xe0b48a) * (0.6 + rnd.next() * 0.5)
			skin.a = 1.0
			b.box_at(m, Vector3(x, y + 0.28 + h, z + tread * 0.5), Vector3(0.24, 0.24, 0.24), skin)
			x += 0.75
	var back_z := 1.6 + rows * tread
	var top_y := 0.6 + rows * rise
	b.box_at(m, Vector3(0, top_y / 2.0 + 1.0, back_z + 0.2), Vector3(L, top_y + 2.0, 0.4), dark_c)
	for s: float in [-1.0, 1.0]:
		b.box_at(m, Vector3(s * (L / 2.0 + 0.15), (top_y + 2.0) / 2.0, D / 2.0 + 0.3), Vector3(0.3, top_y + 2.0, D - 1.2), dark_c)
	# roof on columns, cantilevered towards the track
	var roof_y := top_y + 4.2
	for x: float in [-L / 2.0 + 1.0, -L / 6.0, L / 6.0, L / 2.0 - 1.0]:
		b.box_at(m, Vector3(x, roof_y / 2.0, back_z), Vector3(0.35, roof_y, 0.35), steel)
	var roof := Transform3D(Basis.IDENTITY, Vector3(0, roof_y, back_z - D / 2.0 + 0.5)) * Transform3D(Basis(Vector3.RIGHT, -0.12), Vector3.ZERO)
	b.box_at(m * roof, Vector3.ZERO, Vector3(L + 2.0, 0.25, D + 1.5), roof_c)
	# sponsor banner along the front wall (banner mesh, shared atlas: the top row)
	var fx := L / 2.0 - 1.0
	banner_b.quad_uv(m * Vector3(fx, 0.35, 0.73), m * Vector3(-fx, 0.35, 0.73), m * Vector3(-fx, 1.45, 0.73), m * Vector3(fx, 1.45, 0.73),
		Vector2(0, 0.25), Vector2(1, 0.25), Vector2(1, 0), Vector2(0, 0), WHITE)
	return b


# =============================================================================
# Scenery
# =============================================================================

static func add_scenery(node: Node3D, c: TrackCtx) -> void:
	var theme := c.theme
	var terrain = c.terrain
	var seed := c.seed
	var rnd := VNoise.Rng.new(seed ^ 0x9e3779b9)
	var names: Array = theme["scenery"]
	var species: Array[Dictionary] = []
	for nm: String in names:
		species.append(SPECIES[nm])
	# cumulative weights: the big set pieces (hoodoos) are rarer than shrubs
	var wsum := 0.0
	for sp in species:
		wsum += float(sp.get("weight", 1.0))
	var acc := 0.0
	var cum := PackedFloat32Array()
	for sp in species:
		acc += float(sp.get("weight", 1.0)) / wsum
		cum.append(acc)
	var min_x: float = terrain.min_x
	var max_x: float = terrain.max_x
	var min_z: float = terrain.min_z
	var max_z: float = terrain.max_z
	var reach := 650.0
	var area := (max_x - min_x + 2.0 * reach) * (max_z - min_z + 2.0 * reach)
	var spacing := maxf(11.0, sqrt(area / 60000.0))
	var max_total := 2600
	var lists: Array[Array] = []
	for sp in species:
		lists.append([])
	var tufts: Array = []
	var total := 0
	# Candidates first, then thin them evenly so a big map stays under the cap
	# everywhere (instead of filling up row by row and leaving the rest bare).
	var cand := PackedFloat32Array()
	var sum_p := 0.0
	var forest_n := VNoise.fast_fbm(seed + 31, 3)
	var z := min_z - reach
	while z < max_z + reach:
		var x := min_x - reach
		while x < max_x + reach:
			var jx := x + (rnd.next() - 0.5) * spacing
			var jz := z + (rnd.next() - 0.5) * spacing
			x += spacing
			var e: float = terrain.edge_dist(jx, jz)
			if e < 16.0 or e > reach:
				continue
			var forest := 0.5 + 0.5 * forest_n.get_noise_2d(jx * 0.004, jz * 0.004)
			var mask := 1.0 if forest > 0.5 else 0.18
			var p := 0.5 * exp(-(e - 16.0) / 260.0) * mask + 0.03
			cand.append_array([jx, jz, p])
			sum_p += p
		z += spacing
	var thin := minf(1.0, max_total * 0.97 / maxf(1.0, sum_p))
	var has_water: bool = terrain.has_water
	var water_y: float = terrain.water_y
	var base: float = terrain.base
	for ci in range(0, cand.size(), 3):
		var jx := cand[ci]
		var jz := cand[ci + 1]
		var p := cand[ci + 2] * thin
		var r := rnd.next()
		if r > p or total >= max_total:
			continue
		var flat: float = terrain.flatness(jx, jz)
		# pick a species: noise decides the local mix
		var pick := VNoise.vnoise(jx * 0.01, jz * 0.01, seed + 41) * 0.6 + rnd.next() * 0.4
		var s_idx := 0
		while s_idx < species.size() - 1 and pick >= cum[s_idx]:
			s_idx += 1
		var sp := species[s_idx]
		if flat < float(sp["minFlat"]):
			continue
		var y: float = terrain.height_at(jx, jz)
		if sp.has("maxHeight") and y - base > float(sp["maxHeight"]):
			continue
		if has_water and (y < water_y + 0.8 or terrain.sea_at(jx, jz) > 0.12):
			continue  # not in the sea or on the wet sand
		var sc: Array = sp["scale"]
		var it := PackedFloat32Array([jx, y, jz, float(sc[0]) + rnd.next() * (float(sc[1]) - float(sc[0])), rnd.next() * TAU, rnd.next()])
		lists[s_idx].append(it)
		total += 1
	# small tufts close to the track for ground detail
	var tuft_spec = theme["tuft"]
	if tuft_spec != null:
		var tr := c.track
		var t_step := maxi(1, ceili(tr.count * 2.0 / 4800.0))  # spread evenly on long tracks
		var i := 0
		while i < tr.count and tufts.size() < 5000:
			for k in 2:
				var s := 1.0 if rnd.next() < 0.5 else -1.0
				var o := tr.hw[i] + ZONE + 1.0 + rnd.next() * 45.0
				var x := tr.px[i] + tr.nx[i] * s * o + (rnd.next() - 0.5) * 3.0
				var zz := tr.pz[i] + tr.nz[i] * s * o + (rnd.next() - 0.5) * 3.0
				if terrain.edge_dist(x, zz) < ZONE + 1.0 or terrain.sea_at(x, zz) > 0.12:
					continue
				tufts.append(PackedFloat32Array([x, terrain.height_at(x, zz), zz, 0.7 + rnd.next() * 0.8, rnd.next() * TAU, rnd.next()]))
			i += t_step

	# Split each species into a 3x3 grid of chunks so the camera and the
	# shadow pass can skip the far ones.
	var cx0 := min_x - reach
	var cz0 := min_z - reach
	var cw := (max_x - min_x + 2.0 * reach) / 3.0
	var ch := (max_z - min_z + 2.0 * reach) / 3.0
	var mat := _std(Color.WHITE, 0.88)
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	for k in species.size():
		var mesh := species_geometry(names[k], seed + k).to_mesh(mat)
		var chunks: Array[Array] = []
		for q in 9:
			chunks.append([])
		for it: PackedFloat32Array in lists[k]:
			var a := clampi(floori((it[0] - cx0) / cw), 0, 2)
			var b := clampi(floori((it[2] - cz0) / ch), 0, 2)
			chunks[b * 3 + a].append(it)
		for q in 9:
			# Lower graphics quality draws only the first part of each chunk (apply_quality),
			# so put the instances in a scattered order (a hash of the position: no rnd() draws,
			# the scenery stays the same), not the row-by-row order they were generated in.
			var order := chunks[q]
			order.sort_custom(func(p1: PackedFloat32Array, p2: PackedFloat32Array) -> bool: return _hash(p1[0], p1[2]) < _hash(p2[0], p2[2]))
			_place_chunk(node, mesh, order, species[k], true, "%s-%d" % [names[k], q])
	if tuft_spec != null and not tufts.is_empty():
		var tm := _std(Color.WHITE, 0.9)
		tm.vertex_color_use_as_albedo = true
		tm.vertex_color_is_srgb = true
		tm.cull_mode = BaseMaterial3D.CULL_DISABLED
		# one mesh: tiny, no shadows, and mostly in view along the track anyway
		_place_chunk(node, _tuft_geometry(tuft_spec).to_mesh(tm), tufts, {"tilt": 0.2, "sink": 0.05, "hue": 0.03, "light": 0.12}, false, "tufts")
	c.scenery_count = total + tufts.size()


static func _hash(x: float, z: float) -> float:
	var v := sin(x * 12.9898 + z * 78.233) * 43758.5453
	return v - floorf(v)


static func _place_chunk(node: Node3D, mesh: Mesh, list: Array, sp: Dictionary, shadow: bool, node_name: String) -> void:
	if list.is_empty():
		return
	var tilt: float = sp["tilt"]
	var sink: float = sp["sink"]
	var hue: float = sp["hue"]
	var light: float = sp["light"]
	var buf := PackedFloat32Array()
	buf.resize(list.size() * 16)
	var o := 0
	for it: PackedFloat32Array in list:
		var x := it[0]
		var y := it[1]
		var z := it[2]
		var s := it[3]
		var yaw := it[4]
		var r := it[5]
		var e := Vector3((r - 0.5) * tilt, yaw, (fmod(r * 7.0, 1.0) - 0.5) * tilt)
		var sc := Vector3(s * (0.9 + r * 0.2), s * (0.85 + fmod(r * 13.0, 1.0) * 0.3), s * (0.9 + fmod(r * 5.0, 1.0) * 0.2))
		var bs := Basis.from_euler(e, EULER_ORDER_XYZ) * Basis.from_scale(sc)
		var p := Vector3(x, y - sink * s, z)
		var br := 1.0 + (fmod(r * 17.0, 1.0) - 0.5) * light * 2.0
		var warm := (fmod(r * 3.0, 1.0) - 0.5) * hue * 4.0
		# the instance colour multiplies the (sRGB) vertex colour before it is decoded: give it in sRGB too
		var tint := Color(br * (1.0 + warm), br, br * (1.0 - warm)).linear_to_srgb()
		_put(buf, o, bs, p, tint)
		o += 16
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = list.size()
	mm.buffer = buf
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mmi)
	# the graphics quality level thins these out (TrackMesh.apply_quality)
	(node.get("detail_nodes") as Array).append({"node": mmi, "full": list.size(), "kind": "scenery" if shadow else "tuft"})


## Writes one instance (transform rows + colour) into a MultiMesh buffer at offset o.
static func _put(buf: PackedFloat32Array, o: int, b: Basis, p: Vector3, c: Color) -> void:
	buf[o] = b.x.x
	buf[o + 1] = b.y.x
	buf[o + 2] = b.z.x
	buf[o + 3] = p.x
	buf[o + 4] = b.x.y
	buf[o + 5] = b.y.y
	buf[o + 6] = b.z.y
	buf[o + 7] = p.y
	buf[o + 8] = b.x.z
	buf[o + 9] = b.y.z
	buf[o + 10] = b.z.z
	buf[o + 11] = p.z
	buf[o + 12] = c.r
	buf[o + 13] = c.g
	buf[o + 14] = c.b
	buf[o + 15] = c.a


## A MultiMeshInstance3D of `mesh` at the transforms (optional colours).
static func _multimesh(mesh: Mesh, xfs: Array, colors: Array, node_name: String) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for k in xfs.size():
		mm.set_instance_transform(k, xfs[k])
		if not colors.is_empty():
			mm.set_instance_color(k, colors[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	return mmi


# =============================================================================
# Set pieces: lighthouse, boats, skyline
# =============================================================================

## Theme set pieces: the lighthouse and boats (seaside) and a lit city on the
## horizon (night). Boats and buildings are instanced and thinned by the
## graphics quality level like the rest of the scenery.
static func add_set_pieces(node: Node3D, c: TrackCtx) -> void:
	var theme := c.theme
	var terrain = c.terrain
	var seed := c.seed
	var x0: float = terrain.x0
	var z0: float = terrain.z0
	var W: float = terrain.W
	var H: float = terrain.H

	var pad := c.pad("lighthouse")
	if not pad.is_empty():
		var lh := _lighthouse_geometry()
		var bm := _std(Color.WHITE, 0.6, 0.05)
		bm.vertex_color_use_as_albedo = true
		bm.vertex_color_is_srgb = true
		var lm := _std(Themes.col(0xfff3c4), 0.2)
		lm.emission_enabled = true
		lm.emission = Themes.col(0xffd77a)
		lm.emission_energy_multiplier = 2.6
		var yaw := atan2(float(c.coast["dx"]), float(c.coast["dz"]))  # the keeper's house on the landward side
		var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(pad["cx"], float(pad["y"]) - 0.15, pad["cz"]))
		var body := MeshInstance3D.new()
		body.name = "lighthouse"
		body.mesh = (lh["body"] as Geo).to_mesh(bm)
		body.transform = xf
		node.add_child(body)
		var lamp := MeshInstance3D.new()
		lamp.name = "lighthouse-lamp"
		lamp.mesh = (lh["lamp"] as Geo).to_mesh(lm, true, false)
		lamp.transform = xf
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(lamp)

	if c.has_coast:
		# boats out on the water, at least 3 m deep and apart from each other
		var rnd := VNoise.Rng.new(seed ^ 0xb0a75)
		var boats: Array[Vector4] = []  # x, z, yaw, scale
		var k := 0
		while k < 600 and boats.size() < 10:
			k += 1
			var x := x0 + 250.0 + rnd.next() * (W - 500.0)
			var z := z0 + 250.0 + rnd.next() * (H - 500.0)
			if terrain.sea_at(x, z) < 0.999 or terrain.water_y - terrain.height_at(x, z) < 3.0 or terrain.edge_dist(x, z) > 900.0:
				continue
			var close := false
			for b in boats:
				if Vector2(b.x - x, b.y - z).length() < 90.0:
					close = true
			if close:
				continue
			boats.append(Vector4(x, z, rnd.next() * TAU, 0.85 + rnd.next() * 0.4))
		var wy: float = terrain.water_y
		var xfs: Array = []
		for b in boats:
			xfs.append(Transform3D(Basis(Vector3.UP, b.z).scaled(Vector3(b.w, b.w, b.w)), Vector3(b.x, wy - 0.35, b.y)))
		var mat := _std(Color.WHITE, 0.55, 0.05)
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
		_instanced(node, _boat_geometry().to_mesh(mat), xfs, "boats")

	if theme.get("skyline", false):
		# city blocks 450-1000 m out, in a few clusters; windows are lit by the material (skyline.gdshader)
		var rnd := VNoise.Rng.new(seed ^ 0x5c1e)
		var blocks: Array[Dictionary] = []
		var k := 0
		while k < 9000 and blocks.size() < 170:
			k += 1
			var x := x0 + 300.0 + rnd.next() * (W - 600.0)
			var z := z0 + 300.0 + rnd.next() * (H - 600.0)
			var e: float = terrain.edge_dist(x, z)
			if e < 450.0 or e > 1000.0 or VNoise.fbm(x * 0.0022, z * 0.0022, 2, seed + 61) < 0.52:
				continue
			var w := 14.0 + rnd.next() * 26.0
			var d := 14.0 + rnd.next() * 26.0
			var h := 12.0 + rnd.next() * rnd.next() * 120.0
			var clash := false
			for b in blocks:
				if absf(b["x"] - x) < (b["w"] + w) / 2.0 + 5.0 and absf(b["z"] - z) < (b["d"] + d) / 2.0 + 5.0:
					clash = true
					break
			if clash:
				continue
			# stand on the lowest corner of the footprint, so no block floats over a slope
			var y := INF
			for q: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2(0, 0)]:
				y = minf(y, terrain.height_at(x + q.x * w / 2.0, z + q.y * d / 2.0))
			blocks.append({"x": x, "y": y - 1.5, "z": z, "w": w, "d": d, "h": h + 1.5})
		var xfs: Array = []
		for b in blocks:
			xfs.append(Transform3D(Basis.from_scale(Vector3(b["w"], b["h"], b["d"])), Vector3(b["x"], b["y"], b["z"])))
		var sm := ShaderMaterial.new()
		sm.shader = SKYLINE_SHADER
		sm.set_shader_parameter("facade", Themes.col(0x1b2130))
		_instanced(node, Geo.box(1, 1, 1).translate(0, 0.5, 0).to_mesh(sm, false, false), xfs, "skyline")


static func _instanced(node: Node3D, mesh: Mesh, xfs: Array, node_name: String) -> void:
	if xfs.is_empty():
		return
	# scattered order, so a lower quality level (which draws the first part) thins evenly
	xfs.sort_custom(func(a: Transform3D, b: Transform3D) -> bool: return _hash(a.origin.x, a.origin.z) < _hash(b.origin.x, b.origin.z))
	var mmi := _multimesh(mesh, xfs, [], node_name)
	node.add_child(mmi)
	(node.get("detail_nodes") as Array).append({"node": mmi, "full": xfs.size(), "kind": "scenery"})


## Lighthouse: a banded, tapering tower with a gallery, a lit lantern and a keeper's house. Local +z faces the sea.
static func _lighthouse_geometry() -> Dictionary:
	var b := Geo.new()
	var red := 0xc63a32
	var white := 0xf1eee6
	var dark := Themes.lin(0x3a3d42)
	var H := 19.0
	var R0 := 3.0
	var R1 := 2.0
	var bands := 6
	for k in bands:
		var y0 := k * H / bands
		var y1 := (k + 1) * H / bands
		var r0 := R0 + (R1 - R0) * k / bands
		var r1 := R0 + (R1 - R0) * (k + 1) / bands
		b.add_geometry(paint(Geo.cylinder(r1, r0, y1 - y0, 18, 1, true).translate(0, (y0 + y1) / 2.0, 0), red if k % 2 else white, 0.92 if k else 0.7))
	b.add_geometry(Geo.cylinder(3.6, 3.4, 1.2, 18).translate(0, 0.3, 0), Transform3D.IDENTITY, Themes.lin(0x9a958c))  # plinth
	b.add_geometry(Geo.cylinder(2.9, 2.7, 0.4, 18).translate(0, H + 0.2, 0), Transform3D.IDENTITY, dark)  # gallery floor
	b.add_geometry(Geo.cylinder(2.8, 2.8, 0.9, 18, 1, true).translate(0, H + 0.85, 0), Transform3D.IDENTITY, dark)  # railing
	b.add_geometry(Geo.cylinder(1.75, 1.75, 0.3, 14).translate(0, H + 3.0, 0), Transform3D.IDENTITY, dark)  # lantern top ring
	b.add_geometry(paint(Geo.cone(1.95, 1.9, 14).translate(0, H + 4.1, 0), red, 0.8))  # roof
	b.add_geometry(Geo.sphere(0.3, 8, 6).translate(0, H + 5.1, 0), Transform3D.IDENTITY, dark)
	# keeper's house on the landward side, with a pitched roof
	b.box_at(Transform3D.IDENTITY, Vector3(0, 1.6, -7.5), Vector3(7, 3.2, 5.5), Themes.lin(white))
	var slope := 0.5
	var half := 3.3  # roof pitch (rad) and slab width; the slabs meet at the ridge, eaves at the wall tops
	for s: float in [1.0, -1.0]:
		var m := Transform3D(Basis.IDENTITY, Vector3(0, 3.2 + half * sin(slope), -7.5)) \
			* Transform3D(Basis(Vector3.RIGHT, s * slope), Vector3.ZERO) * Transform3D(Basis.IDENTITY, Vector3(0, 0, s * half / 2.0))
		b.box_at(m, Vector3.ZERO, Vector3(7.6, 0.25, half), Themes.lin(red))
	var lamp := Geo.cylinder(1.45, 1.45, 2.3, 14).translate(0, H + 1.75, 0)
	return {"body": b, "lamp": lamp}


## A small sailing boat: tapered hull, cabin, mast and two flat sails.
static func _boat_geometry() -> Geo:
	var b := Geo.new()
	var hull := Geo.box(2.4, 1.1, 7.5, 1, 1, 2)
	for v in hull.pos.size():
		var p := hull.pos[v]
		var k := 0.12 if p.z > 0.1 else 1.0  # pointed bow
		if p.y < 0.0:
			k *= 0.6  # narrower keel
		p.x *= k
		if p.z > 0.1 and p.y > 0.0:
			p.y += 0.25  # raised bow
		hull.pos[v] = p
	hull.compute_normals()
	b.add_geometry(paint(hull.translate(0, 0.45, 0), 0xf3f4f6, 0.55, -0.1, 1.2))
	b.box_at(Transform3D.IDENTITY, Vector3(0, 1.25, -1.2), Vector3(1.5, 0.6, 2.4), Themes.lin(0x2f6fb4))
	b.add_geometry(Geo.cylinder(0.06, 0.08, 8, 5).translate(0, 4.8, 0.4), Transform3D.IDENTITY, Themes.lin(0xd8d8d8))
	var sail := func(h: float, w: float, z: float, dir: float) -> Geo:
		return Geo.cone(w, h, 3).scale(1, 1, 0.04).rotate_y(PI / 2.0).translate(0, 1.5 + h / 2.0, z + dir * w * 0.4)
	b.add_geometry(sail.call(7.0, 1.9, -0.6, -1.0), Transform3D.IDENTITY, Themes.lin(0xf6f3ea))
	b.add_geometry(sail.call(5.5, 1.3, 1.9, 1.0), Transform3D.IDENTITY, Themes.lin(0xf6f3ea))
	return b


# =============================================================================
# Species geometry
# =============================================================================

## The low-poly mesh of a scenery species (seeded as the JS SPECIES[name].build(seed)).
static func species_geometry(sp_name: String, seed: int) -> Geo:
	match sp_name:
		"broadleaf":
			return _broadleaf(seed)
		"pine":
			return _pine(seed, false)
		"pineSnow":
			return _pine(seed, true)
		"bush":
			return _bush(seed, 0x4d8a36)
		"rock":
			return _rock(seed, 0x8a877f)
		"rockGrey":
			return _rock(seed, 0x7f838b)
		"rockRed":
			return _rock(seed, 0xa65d3c)
		"saguaro":
			return _saguaro(seed)
		"barrel":
			return _barrel(seed)
		"shrubDry":
			return _bush(seed, 0x8f7f4b, true)
		"hoodoo":
			return _hoodoo(seed)
		"juniper":
			return _juniper(seed)
		"palm":
			return _palm(seed)
		"bushCoast":
			return _bush(seed, 0x6f8f3e, true)
	return _bush(seed, 0x4d8a36)


static func _broadleaf(seed: int) -> Geo:
	var b := Geo.new()
	b.add_geometry(paint(Geo.cylinder(0.2, 0.34, 4.4, 6).translate(0, 2.2, 0), 0x6b4a32, 0.7))
	var rnd := VNoise.Rng.new(seed)
	for bl: Vector4 in [Vector4(0, 5.7, 0, 2.3), Vector4(1.2, 5.0, 0.5, 1.7), Vector4(-1.0, 5.1, -0.6, 1.8), Vector4(0.2, 6.9, -0.2, 1.6)]:
		var g := Geo.icosahedron(bl.w, 1 if bl.w > 2.0 else 0)
		displace(g, 0.28 * bl.w, seed + int(floorf(rnd.next() * 100.0)))
		g.translate(bl.x, bl.y, bl.z)
		b.add_geometry(paint(g, 0x4f8a3a, 0.55, 3.6, 8.5))
	return b


static func _pine(seed: int, snow: bool) -> Geo:
	var b := Geo.new()
	b.add_geometry(paint(Geo.cylinder(0.14, 0.26, 3.2, 5).translate(0, 1.6, 0), 0x5e4330, 0.7))
	var layers := [Vector3(2.7, 4.2, 3.9), Vector3(2.1, 3.6, 6.1), Vector3(1.4, 3.0, 8.2), Vector3(0.8, 2.2, 9.9)]
	for k in layers.size():
		var r: float = layers[k].x
		var h: float = layers[k].y
		var y: float = layers[k].z
		var g := Geo.cone(r, h, 8, 1, true).translate(0, y, 0)
		displace(g, 0.18, seed + k * 7)
		paint(g, 0x2d5e34, 0.5, y - h / 2.0, y + h / 2.0)
		if snow:
			var white := Themes.lin(0xf2f6fa)
			for v in g.pos.size():
				var tt := (g.pos[v].y - (y - h / 2.0)) / h
				g.col[v] = g.col[v].lerp(white, 0.85 if tt > 0.15 else 0.35)
		b.add_geometry(g)
	return b


static func _bush(seed: int, color: int, dry := false) -> Geo:
	var g := Geo.icosahedron(1.1, 0)
	displace(g, 0.5 if dry else 0.3, seed)
	g.scale(1.2, 0.65 if dry else 0.8, 1.1).translate(0, 0.65, 0)
	var b := Geo.new()
	b.add_geometry(paint(g, color, 0.55, 0.0, 1.4))
	return b


static func _rock(seed: int, color: int) -> Geo:
	var g := Geo.dodecahedron(1.2, 0)
	displace(g, 0.42, seed)
	g.scale(1.25, 0.75, 1.0).translate(0, 0.45, 0)
	var b := Geo.new()
	b.add_geometry(paint(g, color, 0.75, -0.4, 1.4))
	return b


static func _saguaro(seed: int) -> Geo:
	var b := Geo.new()
	var green := 0x4f7d3c
	var column := func(r: float, h: float, x: float, y: float, z: float) -> void:
		b.add_geometry(paint(Geo.cylinder(r, r * 1.08, h, 8, 1, y == 0.0).translate(x, y + h / 2.0, z), green, 0.7, 0.0, 8.0))
		b.add_geometry(paint(Geo.sphere(r, 8, 3, 0.0, TAU, 0.0, PI / 2.0).translate(x, y + h, z), green, 0.7, 0.0, 8.0))
	column.call(0.45, 6.4, 0.0, 0.0, 0.0)
	var rnd := VNoise.Rng.new(seed)
	var arm := func(side: float, y0: float, l: float, up: float) -> void:
		var g := Geo.cylinder(0.3, 0.3, l, 7).rotate_z(PI / 2.0).translate(side * l / 2.0, y0, 0)
		b.add_geometry(paint(g, green, 0.7, 0.0, 8.0))
		column.call(0.3, up, side * l, y0, 0.0)
	# argument order as the JS: y0 is drawn before up
	var y0a := 2.6 + rnd.next() * 0.8
	arm.call(1.0, y0a, 1.3, 2.0 + rnd.next())
	var y0b := 3.4 + rnd.next() * 0.8
	arm.call(-1.0, y0b, 1.1, 1.6 + rnd.next())
	return b


static func _barrel(seed: int) -> Geo:
	var b := Geo.new()
	var g := Geo.cylinder(0.42, 0.5, 0.9, 12, 1, true)
	for v in g.pos.size():
		var p := g.pos[v]
		var r := Vector2(p.x, p.z).length()
		if r < 1e-3:
			continue
		var a := atan2(p.z, p.x)
		var k := 1.0 + 0.08 * cos(a * 12.0)
		g.pos[v] = Vector3(p.x * k, p.y, p.z * k)
	g.compute_normals()
	g.translate(0, 0.45, 0)
	b.add_geometry(paint(g, 0x5f8a3e, 0.7, 0.0, 1.0))
	var top := Geo.sphere(0.47, 12, 2, 0.0, TAU, 0.0, PI / 2.0).scale(1, 0.5, 1).translate(0, 0.9, 0)
	b.add_geometry(paint(top, 0x6b9444, 0.9, 0.0, 1.0))
	var rnd := VNoise.Rng.new(seed)
	for k in 2:
		var fx := (rnd.next() - 0.5) * 0.4
		var fz := (rnd.next() - 0.5) * 0.4
		b.add_geometry(paint(Geo.icosahedron(0.1, 0).translate(fx, 1.1, fz), 0xf2c94c if k % 2 else 0xe0603a, 1.0))
	return b


static func _hoodoo(seed: int) -> Geo:
	var b := Geo.new()
	var strata := [0xa95b36, 0xc07648, 0x9c4f30, 0xb86c42, 0xc98a5c]
	var y := 0.0
	var r := 2.6
	var rnd := VNoise.Rng.new(seed)
	for k in 4:
		var h := 2.5 + rnd.next() * 2.0
		var g := Geo.cylinder(r * 0.82, r, h, 9, 2).translate(0, y + h / 2.0, 0)
		displace(g, 0.3, seed + k)
		b.add_geometry(paint(g, strata[k % strata.size()], 0.85, 0.0, 16.0))
		y += h
		r *= 0.78
	var cap := Geo.cylinder(r * 1.8, r * 1.5, 1.4, 9).translate(0, y + 0.6, 0)
	displace(cap, 0.3, seed + 9)
	b.add_geometry(paint(cap, 0x8f4a2c, 0.9))
	return b


static func _juniper(seed: int) -> Geo:
	var b := Geo.new()
	b.add_geometry(paint(Geo.cylinder(0.15, 0.28, 2.2, 5).rotate_z(0.15).translate(0.1, 1.1, 0), 0x6e5a44, 0.7))
	for bl: Vector4 in [Vector4(0.2, 2.6, 0, 1.4), Vector4(-0.7, 2.0, 0.4, 1.0), Vector4(0.8, 2.2, -0.5, 0.9)]:
		var g := Geo.icosahedron(bl.w, 1)
		displace(g, 0.3 * bl.w, seed + roundi(bl.x * 10.0))
		g.scale(1, 0.7, 1).translate(bl.x, bl.y, bl.z)
		b.add_geometry(paint(g, 0x4f5f37, 0.6, 1.0, 3.6))
	return b


## A palm: a curved, ringed trunk and a crown of drooping fronds (each two flat blades).
static func _palm(seed: int) -> Geo:
	var b := Geo.new()
	var rnd := VNoise.Rng.new(seed)
	var segs := 7
	var H := 8.6
	var x := 0.0
	var y := 0.0
	for k in segs:
		var h := H / segs
		var lean := 0.04 + k * 0.05  # leans further out towards the top
		var g := Geo.cylinder(0.3 - (k + 1) * 0.022, 0.3 - k * 0.022, h * 1.06, 7, 1, true)
		paint(g, 0x8d6c49 if k % 2 else 0x76583a, 0.8)
		b.add_geometry(g, Transform3D(Basis(Vector3.BACK, -lean), Vector3(x + sin(lean) * h / 2.0, y + cos(lean) * h / 2.0, 0)))
		x += sin(lean) * h
		y += cos(lean) * h
	var blade := func(l: float, wid: float) -> Geo:
		return paint(Geo.cone(wid, l, 4, 1).rotate_z(-PI / 2.0).scale(1, 0.14, 1).translate(l / 2.0, 0, 0), 0x4c8a35, 0.55, -0.2, 0.2)
	var n := 8
	for f in n:
		var az := float(f) / n * TAU + rnd.next() * 0.35
		var inner: Geo = blade.call(2.4, 0.5)
		var outer: Geo = blade.call(2.6, 0.45)
		var up := 0.2 + rnd.next() * 0.15
		var droop := -0.55 - rnd.next() * 0.25
		var m1 := Transform3D(Basis(Vector3.UP, az) * Basis(Vector3.BACK, up), Vector3(x, y + 0.1, 0))
		b.add_geometry(inner, m1)
		var tip := m1 * Vector3(2.3, 0, 0)
		b.add_geometry(outer, Transform3D(Basis(Vector3.UP, az) * Basis(Vector3.BACK, droop), tip))
	for k in 3:
		var a := k * 2.1 + rnd.next()
		b.add_geometry(paint(Geo.icosahedron(0.17, 0).translate(x + cos(a) * 0.32, y - 0.25, sin(a) * 0.32), 0x5a4128, 0.9))
	return b


static func _tuft_geometry(spec: Dictionary) -> Geo:
	var g := Geo.new()
	g.indexed = false
	var base := Themes.lin(spec["color"])
	var tip := Themes.lin(spec["tip"])
	for k in 6:
		var a := float(k) / 6.0 * TAU + k * 0.4
		var lean := 0.25 + (k % 3) * 0.1
		var h := 0.45 + (k % 2) * 0.2
		var w := 0.07
		var cx := cos(a)
		var cz := sin(a)
		g.pos.append_array([Vector3(-cz * w, 0, cx * w), Vector3(cz * w, 0, -cx * w), Vector3(cx * lean, h, cz * lean)])
		g.col.append_array([base, base, tip])
		g.uv.append_array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	g.compute_normals()
	# grass looks better lit from above
	for v in g.nor.size():
		var n := g.nor[v]
		g.nor[v] = Vector3(n.x * 0.3, 1.0, n.z * 0.3).normalized()
	return g


## Give a geometry a vertex colour with a darker base (fake ambient occlusion).
static func paint(g: Geo, hex: int, ao := 0.6, y0 := NAN, y1 := NAN) -> Geo:
	var lo := y0
	var hi := y1
	if is_nan(lo) or is_nan(hi):
		var bb := g.aabb()
		lo = bb.position.y
		hi = bb.end.y
	var base := Themes.lin(hex)
	g.col.resize(g.pos.size())
	for v in g.pos.size():
		var t := clampf((g.pos[v].y - lo) / maxf(1e-3, hi - lo), 0.0, 1.0)
		var k := ao + (1.0 - ao) * t
		g.col[v] = Color(base.r * k, base.g * k, base.b * k)
	return g


## Push vertices along their direction from the centre by position-based noise (crack-free).
static func displace(g: Geo, amount: float, seed: int) -> void:
	for v in g.pos.size():
		var p := g.pos[v]
		var n := VNoise.vnoise(p.x * 1.7 + p.y * 0.9, p.z * 1.7 - p.y * 1.1, seed) - 0.5
		var l := p.length()
		if l == 0.0:
			l = 1.0
		var k := 1.0 + n * 2.0 * amount / l
		g.pos[v] = p * k
	g.compute_normals()


static func _std(color: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


static func _fade(m: BaseMaterial3D) -> void:
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
	m.distance_fade_min_distance = 1.2
	m.distance_fade_max_distance = 4.5
