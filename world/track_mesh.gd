extends Node3D
## track_mesh.gd (port of web/src/game/trackMesh.js)
## ------------------------------------------------------------------
## Builds the visible 3D world of one built track (sim/ BuiltTrack):
##
##   - road: procedural asphalt (colour, roughness and normal maps) with
##     rubbered racing line, painted edge/centre lines, start grid boxes
##   - raised 3D curbs on corners, concrete barriers with coloured panels,
##     embankments under raised road
##   - checkpoint and start/finish gates with emissive light strips
##   - trackside props: lamp posts, chevron boards, banners, a grandstand
##     (world/track_scenery.gd)
##   - a large terrain: flat under and around the road, gentle hills further
##     out and a ring of mountains (or mesas) towards the horizon
##     (world/track_terrain.gd)
##   - themed, instanced scenery (trees, cacti, rocks, ...) never on the road
##   - theme extras: glowing barrier stripes and a lit city skyline (night);
##     the sea on one side of the track with a beach, a lighthouse and
##     boats (seaside)
##
## Everything is merged or instanced (MultiMeshInstance3D) to keep draw calls
## low; the terrain and (long tracks) the barriers are split into spatial
## chunks so the camera and the shadow splits skip the far parts. The look
## follows track.theme (world/themes.gd).
##
## Use: var node := TrackMesh.build(track)   (World.show_track does this)
##      node.apply_quality(Themes.get_quality("low"))
##      node.set_checkpoint_state(k, "next" | "passed" | "idle")
##      node.stats   build times (ms) and sizes

const TrackMesh = preload("res://world/track_mesh.gd")
const Geo = preload("res://world/geo.gd")
const Themes = preload("res://world/themes.gd")
const VNoise = preload("res://world/noise.gd")
const Tex = preload("res://world/textures.gd")
const TrackCtx = preload("res://world/track_ctx.gd")
const Terrain = preload("res://world/track_terrain.gd")
const Scenery = preload("res://world/track_scenery.gd")
const PAINT_SHADER = preload("res://world/shaders/road_paint.gdshader")

const BARRIER_H := TrackCtx.BARRIER_H
const BARRIER_W := TrackCtx.BARRIER_W

const GATE_STATE := {
	"next": {"color": 0x19d3ff, "glow": 3.2},
	"passed": {"color": 0x2ee66a, "glow": 2.2},
	"idle": {"color": 0x56636f, "glow": 0.25},
	"start": {"color": 0xfff1c8, "glow": 2.6},
}

# Barrier cross-section: [outward offset from the road edge, height]; part 0 = concrete,
# 1 = coloured panel, 2 = top cap (per profile segment)
const BARRIER_PROFILE := [
	Vector2(0.0, 0.0), Vector2(0.05, 0.26), Vector2(0.12, 0.32), Vector2(0.2, 0.96), Vector2(0.24, 1.05),
	Vector2(0.3, BARRIER_H), Vector2(0.58, BARRIER_H), Vector2(BARRIER_W, 0.0),
]
const BARRIER_PART := [0, 0, 1, 0, 2, 2, 0]

const WHITE := Color(1, 1, 1)
## Barriers of tracks with this many triangles or more are split into CHUNK m cells
## (only shadow casters gain: the main camera sees most of the track anyway).
const CHUNK_TRIS := 30000
const CHUNK := 500.0

## Build times (ms) and sizes, like the JS group.userData.stats.
var stats: Dictionary = {}
var ctx: TrackCtx
var theme: Dictionary
var terrain: Terrain
## checkpoint gate light materials, by checkpoint index
var cp_materials: Array[StandardMaterial3D] = []
## instanced scenery thinned by the quality level: {node: MultiMeshInstance3D, full: int, kind: "scenery" | "tuft"}
var detail_nodes: Array[Dictionary] = []
## real lights under the lamps (high quality), and the additive pools that stand in for them
var lamp_lights: Array[Light3D] = []
var lamp_pool: GeometryInstance3D = null


static func build(track: BuiltTrack) -> TrackMesh:
	var t0 := Time.get_ticks_usec()
	var node := TrackMesh.new()
	node.name = "Track"
	node.theme = Themes.get_theme(track.theme)
	node.ctx = TrackCtx.analyse(track, node.theme)
	var c := node.ctx
	var t1 := Time.get_ticks_usec()
	node.terrain = Terrain.new()
	node.terrain.build(c)
	c.terrain = node.terrain
	node._add_terrain()
	var t2 := Time.get_ticks_usec()

	var lap := {}
	var tl := Time.get_ticks_usec()
	node._add(node._build_road(), "road")
	lap["road"] = (Time.get_ticks_usec() - tl) / 1000
	tl = Time.get_ticks_usec()
	node._add(node._build_lines(), "lines")
	lap["lines"] = (Time.get_ticks_usec() - tl) / 1000
	tl = Time.get_ticks_usec()
	node._build_curbs()
	lap["curbs"] = (Time.get_ticks_usec() - tl) / 1000
	tl = Time.get_ticks_usec()
	node._build_barriers()
	lap["barriers"] = (Time.get_ticks_usec() - tl) / 1000
	tl = Time.get_ticks_usec()
	node._build_embankments()
	lap["embank"] = (Time.get_ticks_usec() - tl) / 1000
	tl = Time.get_ticks_usec()
	node._build_start_lines()
	node._build_gates()
	lap["gates"] = (Time.get_ticks_usec() - tl) / 1000
	var t3 := Time.get_ticks_usec()
	Scenery.add_props(node, c)
	var t4 := Time.get_ticks_usec()
	Scenery.add_scenery(node, c)
	Scenery.add_set_pieces(node, c)
	var t5 := Time.get_ticks_usec()
	node.stats = {
		"build_ms": (t5 - t0) / 1000,
		"analyse_ms": (t1 - t0) / 1000,
		"terrain_ms": (t2 - t1) / 1000,
		"track_ms": (t3 - t2) / 1000,
		"props_ms": (t4 - t3) / 1000,
		"scenery_ms": (t5 - t4) / 1000,
		"terrain_verts": node.terrain.vertex_count,
		"scenery_instances": c.scenery_count,
		"lap": lap,
	}
	return node


## Colour a checkpoint gate: "next" (cyan), "passed" (green) or "idle".
func set_checkpoint_state(k: int, state: String) -> void:
	if k < 0 or k >= cp_materials.size() or cp_materials[k] == null:
		return
	var s: Dictionary = GATE_STATE.get(state, GATE_STATE["idle"])
	_strip_style(cp_materials[k], s)


## Thin the scenery, drop the grass and the scenery shadows, switch the lamp lights for the quality.
func apply_quality(q: Dictionary) -> void:
	for d in detail_nodes:
		var mmi: MultiMeshInstance3D = d["node"]
		if d["kind"] == "tuft":
			mmi.visible = q["tufts"]
		else:
			mmi.multimesh.visible_instance_count = maxi(1, roundi(int(d["full"]) * float(q["scenery"])))
			mmi.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if q["scenery_shadows"]
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	var lights: bool = q.get("lamp_lights", false)
	for l in lamp_lights:
		l.visible = lights


# =============================================================================
# helpers
# =============================================================================

## Adds a mesh made from `g` with material `mat` as a child; returns the MeshInstance3D.
func _add_geo(g: Geo, mat: Material, node_name: String, shadow := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = g.to_mesh(mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _add(n: Node3D, node_name: String) -> void:
	if n == null:
		return
	n.name = node_name
	add_child(n)


static func std_mat(color: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


## Vertex-coloured material (colours from Geo are sRGB in the mesh).
static func vc_mat(rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := std_mat(Color.WHITE, rough, metal)
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	return m


## Dissolves the surface (screen-door dither) where it comes within a few metres
## of the camera, so a gate beam or lamp post the chase camera passes through
## never blacks out the view (trackMesh.js fadeNearCamera).
static func fade_near_camera(m: BaseMaterial3D, near := 1.2, far := 4.5) -> BaseMaterial3D:
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
	m.distance_fade_min_distance = near
	m.distance_fade_max_distance = far
	return m


## Road paint material (world/shaders/road_paint.gdshader).
static func paint_mat(rough: float, tex: Texture2D = null, pull := 0.0006) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = PAINT_SHADER
	m.set_shader_parameter("roughness", rough)
	m.set_shader_parameter("pull", pull)
	if tex != null:
		m.set_shader_parameter("albedo_tex", tex)
	return m


func _strip_style(m: StandardMaterial3D, s: Dictionary) -> void:
	var c := Themes.col(s["color"])
	m.albedo_color = c
	m.emission = c
	m.emission_energy_multiplier = float(s["glow"]) * (1.25 if theme.get("lamps", false) else 1.0)


func _strip_material(s: Dictionary) -> StandardMaterial3D:
	var m := std_mat(Color.WHITE, 0.35)
	m.emission_enabled = true
	_strip_style(m, s)
	fade_near_camera(m)
	return m


# =============================================================================
# Terrain (chunks of the grid built by track_terrain.gd)
# =============================================================================

func _add_terrain() -> void:
	var t := terrain
	var src: Array = t.arrays
	var pos: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var nor: PackedVector3Array = src[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = src[Mesh.ARRAY_TEX_UV]
	var col: PackedColorArray = src[Mesh.ARRAY_COLOR]
	# 3 x 3 chunks of the vertex grid (sharing their border rows), as the JS splitMesh(cell = size / 3)
	var NX := t.NX
	var NZ := t.NZ
	var cuts_x := [0, (NX - 1) / 3, 2 * (NX - 1) / 3, NX - 1]
	var cuts_z := [0, (NZ - 1) / 3, 2 * (NZ - 1) / 3, NZ - 1]
	for cz in 3:
		for cx in 3:
			var i0: int = cuts_x[cx]
			var i1: int = cuts_x[cx + 1]
			var k0: int = cuts_z[cz]
			var k1: int = cuts_z[cz + 1]
			var w := i1 - i0 + 1
			var h := k1 - k0 + 1
			var p2 := PackedVector3Array()
			var n2 := PackedVector3Array()
			var u2 := PackedVector2Array()
			var c2 := PackedColorArray()
			for k in range(k0, k1 + 1):
				var a := k * NX + i0
				p2.append_array(pos.slice(a, a + w))
				n2.append_array(nor.slice(a, a + w))
				u2.append_array(uv.slice(a, a + w))
				c2.append_array(col.slice(a, a + w))
			var idx := PackedInt32Array()
			idx.resize((w - 1) * (h - 1) * 6)
			var p := 0
			for k in h - 1:
				for i in w - 1:
					var a := k * w + i
					idx[p] = a
					idx[p + 1] = a + 1
					idx[p + 2] = a + w
					idx[p + 3] = a + 1
					idx[p + 4] = a + w + 1
					idx[p + 5] = a + w
					p += 6
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = p2
			arr[Mesh.ARRAY_NORMAL] = n2
			arr[Mesh.ARRAY_TEX_UV] = u2
			arr[Mesh.ARRAY_COLOR] = c2
			arr[Mesh.ARRAY_INDEX] = idx
			var m := ArrayMesh.new()
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			m.surface_set_material(0, t.material)
			var mi := MeshInstance3D.new()
			mi.name = "terrain-%d" % (cz * 3 + cx)
			mi.mesh = m
			# the terrain casts shadows too (hills, mountains and road-side banks in the low sun)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			add_child(mi)
	t.arrays = []  # free the big source arrays
	add_child(t.far_plane)
	if t.water != null:
		add_child(t.water)


# =============================================================================
# Road, lines, curbs, start line
# =============================================================================

func _build_road() -> MeshInstance3D:
	var c := ctx
	var t := c.track
	# Lateral columns (fraction of half width) and their wear tint.
	var cols := [1.0, 0.78, 0.45, 0.0, -0.45, -0.78, -1.0]
	var wear := [1.06, 0.98, 0.84, 0.93, 0.84, 0.98, 1.06]
	var C := cols.size()
	var rows := c.segs + 1
	var g := Geo.new()
	var tan := PackedFloat32Array()
	# the tint goes up to ~1.12, over what 8-bit vertex colours hold: scaled down here, up in the material
	var K := 1.13
	for k in rows:
		var i := c.wrap(k)
		var s := k * t.seg_len
		var patch := 0.94 + 0.12 * VNoise.fbm(s * 0.02, 3.7, 2, c.seed + 21)
		for cc in C:
			var lat: float = cols[cc] * t.hw[i]
			var tint: float = wear[cc] * patch / K
			g.vert(Vector3(t.px[i] + t.nx[i] * lat, c.surf_y(i, lat), t.pz[i] + t.nz[i] * lat), Vector3.UP,
				Vector2(lat / 7.0, s / 7.0), Color(tint, tint, tint))
			tan.append_array([t.nx[i], 0.0, t.nz[i], -1.0])
	for k in c.segs:
		for cc in C - 1:
			var a := k * C + cc
			var b := a + 1
			var d := a + C
			var e := d + 1
			g.tri(a, b, d)
			g.tri(b, e, d)
	g.compute_normals()
	var arr := g.to_arrays()
	arr[Mesh.ARRAY_TANGENT] = tan
	var tex := Tex.asphalt()
	var mat := std_mat(Color(K, K, K).linear_to_srgb(), 1.0)
	mat.albedo_texture = tex["map"]
	mat.roughness_texture = tex["rough"]
	mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	mat.normal_enabled = true
	mat.normal_texture = tex["normal"]
	mat.normal_scale = 0.55
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Painted edge lines, dashed centre line and the start grid boxes.
func _build_lines() -> MeshInstance3D:
	var c := ctx
	var t := c.track
	var g := Geo.new()
	var white := Themes.lin(0xe8e8e2)
	var lift := 0.012
	for k in c.segs:
		var i := c.wrap(k)
		var j := c.wrap(k + 1)
		if not c.corner[i] or not c.corner[j]:
			for s: float in [1.0, -1.0]:
				_strip(g, i, j, s * (t.hw[i] - 0.38), s * (t.hw[i] - 0.62), s * (t.hw[j] - 0.38), s * (t.hw[j] - 0.62), lift, white)
		if int(floorf(k * t.seg_len / 4.0)) % 3 == 0:
			_strip(g, i, j, 0.12, -0.12, 0.12, -0.12, lift, white)
	# Start grid: the player's box at the start sample, staggered boxes behind the line.
	_grid_box(g, t.start_idx, 0.0, lift, white)
	if t.closed:
		for k in 4:
			_grid_box(g, t.count - 8 - k * 5, (-1.0 if k % 2 else 1.0) * minf(4.0, t.hw[0] * 0.45), lift, white)
	var mi := MeshInstance3D.new()
	mi.mesh = g.to_mesh(paint_mat(0.62))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _strip(g: Geo, i: int, j: int, la: float, lb: float, laj: float, lbj: float, lift: float, color: Color) -> void:
	g.flat_quad(ctx.P(i, la, lift), ctx.P(j, laj, lift), ctx.P(j, lbj, lift), ctx.P(i, lb, lift), color)


## Point at fractional sample fi, lat metres left, lift above the road.
func _at(fi: float, lat: float, lift: float) -> Vector3:
	var c := ctx
	var t := c.track
	var i0 := int(floorf(fi))
	var f := fi - i0
	var a := c.wrap(i0)
	var b := c.wrap(i0 + 1)
	var ux := t.nx[a] + (t.nx[b] - t.nx[a]) * f
	var uz := t.nz[a] + (t.nz[b] - t.nz[a]) * f
	var y := c.surf_y(a, lat) + (c.surf_y(b, lat) - c.surf_y(a, lat)) * f
	return Vector3(t.px[a] + (t.px[b] - t.px[a]) * f + ux * lat, y + lift, t.pz[a] + (t.pz[b] - t.pz[a]) * f + uz * lat)


func _grid_box(g: Geo, i: int, lat: float, lift: float, white: Color) -> void:
	var sl := ctx.track.seg_len
	var w := 1.45
	var th := 0.16
	var df := 2.7 / sl
	var dt := th / sl
	var rect := func(f0: float, f1: float, l0: float, l1: float) -> void:
		g.flat_quad(_at(i + f0, l0, lift), _at(i + f1, l0, lift), _at(i + f1, l1, lift), _at(i + f0, l1, lift), white)
	rect.call(-df, df, lat + w, lat + w - th)
	rect.call(-df, df, lat - w + th, lat - w)
	rect.call(-df, -df + dt, lat + w - th, lat - w + th)
	rect.call(df - dt * 2.5, df, lat + w - th, lat - w + th)


## Raised red/white curbs on both edges of every corner.
func _build_curbs() -> void:
	var c := ctx
	var t := c.track
	var g := Geo.new()
	var red := Themes.lin(0xd8322b)
	var white := Themes.lin(0xf2f2f2)
	var H := 0.075
	var W := 1.5
	var ramp := 0.35
	var n := 0
	for k in c.segs:
		var i := c.wrap(k)
		var j := c.wrap(k + 1)
		if not c.corner[i] or not c.corner[j]:
			continue
		var hi := H * _taper(i)
		var hj := H * _taper(j)
		for half in 2:
			var f0 := half * 0.5
			var f1 := f0 + 0.5
			var h0 := hi + (hj - hi) * f0
			var h1 := hi + (hj - hi) * f1
			var color := red if (k * 2 + half) % 2 else white
			for s: float in [1.0, -1.0]:
				var w0 := t.hw[i] + (t.hw[j] - t.hw[i]) * f0
				var w1 := t.hw[i] + (t.hw[j] - t.hw[i]) * f1
				var in_a := s * (w0 - W)
				var in_b := s * (w1 - W)
				var top_a := s * (w0 - W + ramp)
				var top_b := s * (w1 - W + ramp)
				var out_a := s * (w0 - 0.01)
				var out_b := s * (w1 - 0.01)
				# ramp up from the road, then the flat top to the barrier
				g.flat_quad(_pt(i, f0, in_a, 0.004), _pt(i, f1, in_b, 0.004), _pt(i, f1, top_b, h1), _pt(i, f0, top_a, h0), color)
				g.flat_quad(_pt(i, f0, top_a, h0), _pt(i, f1, top_b, h1), _pt(i, f1, out_b, h1), _pt(i, f0, out_a, h0), color)
				n += 1
	if n == 0:
		return
	_add_geo(g, paint_mat(0.5, null, 0.0003), "curbs")


## Curbs ramp up over the first and last few samples of a corner.
func _taper(i: int) -> float:
	for d in range(1, 4):
		if not ctx.corner[ctx.wrap(i - d)] or not ctx.corner[ctx.wrap(i + d)]:
			return d / 4.0
	return 1.0


## Point between sample i (f = 0) and its successor (f = 1).
func _pt(i: int, f: float, lat: float, dy: float) -> Vector3:
	var c := ctx
	var t := c.track
	var j := c.wrap(i + 1)
	var x := t.px[i] + (t.px[j] - t.px[i]) * f
	var z := t.pz[i] + (t.pz[j] - t.pz[i]) * f
	var ux := t.nx[i] + (t.nx[j] - t.nx[i]) * f
	var uz := t.nz[i] + (t.nz[j] - t.nz[i]) * f
	var y := c.surf_y(i, lat) + (c.surf_y(j, lat) - c.surf_y(i, lat)) * f
	return Vector3(x + ux * lat, y + dy, z + uz * lat)


## Checkered start (and finish) lines across the road.
func _build_start_lines() -> void:
	var c := ctx
	var t := c.track
	var g := Geo.new()
	var line := func(i: int) -> void:
		var a := c.wrap(i - 1)
		var b := c.wrap(i + 1)
		var v1 := 2.0 * t.seg_len / 1.6
		g.quad_uv(c.P(a, t.hw[a], 0.02), c.P(b, t.hw[b], 0.02), c.P(b, -t.hw[b], 0.02), c.P(a, -t.hw[a], 0.02),
			Vector2((t.hw[a] + 40.0) / 1.6, 0.0), Vector2((t.hw[b] + 40.0) / 1.6, v1),
			Vector2((-t.hw[b] + 40.0) / 1.6, v1), Vector2((-t.hw[a] + 40.0) / 1.6, 0.0), WHITE, Vector3.UP)
	if t.closed:
		line.call(0)
	else:
		line.call(t.start_line)
		line.call(t.finish_idx)
	_add_geo(g, paint_mat(0.6, Tex.checker(), 0.0009), "start-line")


# =============================================================================
# Barriers and embankments
# =============================================================================

func _build_barriers() -> void:
	var c := ctx
	var t := c.track
	var concrete := Themes.lin(0xb9bbbd)
	var cap := Themes.lin(0xd9dadb)
	var accent: Array = theme["accent"]
	var panel_a := Themes.lin(accent[0])
	var panel_b := Themes.lin(accent[1])
	var nP := BARRIER_PROFILE.size() - 1
	# 2D normals of each profile segment (outward, up)
	var pn: Array[Vector2] = []
	for p in nP:
		var d: Vector2 = BARRIER_PROFILE[p + 1] - BARRIER_PROFILE[p]
		pn.append(Vector2(-d.y, d.x) / d.length())
	# chunks (long tracks): one Geo per CHUNK m cell of the segment's position
	var chunked := 28 * c.segs >= CHUNK_TRIS
	var geos: Dictionary = {}
	var glow := theme.get("glow", false) as bool
	var stripes: Dictionary = {}
	for s: float in [1.0, -1.0]:
		for k in c.segs:
			var i := c.wrap(k)
			var j := c.wrap(k + 1)
			var key := Vector2i(floori(t.px[i] / CHUNK), floori(t.pz[i] / CHUNK)) if chunked else Vector2i.ZERO
			if not geos.has(key):
				geos[key] = Geo.new()
			var g: Geo = geos[key]
			var panel := panel_a if (k / 5) % 2 else panel_b
			var u0 := k * t.seg_len / 3.0
			var u1 := (k + 1) * t.seg_len / 3.0
			var oix := t.nx[i] * s
			var oiz := t.nz[i] * s
			var ojx := t.nx[j] * s
			var ojz := t.nz[j] * s
			var ei := Vector3(t.px[i] + oix * t.hw[i], c.edge_y(i, s), t.pz[i] + oiz * t.hw[i])
			var ej := Vector3(t.px[j] + ojx * t.hw[j], c.edge_y(j, s), t.pz[j] + ojz * t.hw[j])
			for p in nP:
				var pa: Vector2 = BARRIER_PROFILE[p]
				var pb: Vector2 = BARRIER_PROFILE[p + 1]
				var nO := pn[p].x
				var nY := pn[p].y
				var part: int = BARRIER_PART[p]
				var color := panel if part == 1 else (cap if part == 2 else concrete)
				var ni := Vector3(oix * nO, nY, oiz * nO)
				var nj := Vector3(ojx * nO, nY, ojz * nO)
				var v0 := g.vert(ei + Vector3(oix * pa.x, pa.y, oiz * pa.x), ni, Vector2(u0, pa.y / 3.0), color)
				var v1 := g.vert(ej + Vector3(ojx * pa.x, pa.y, ojz * pa.x), nj, Vector2(u1, pa.y / 3.0), color)
				var v2 := g.vert(ej + Vector3(ojx * pb.x, pb.y, ojz * pb.x), nj, Vector2(u1, pb.y / 3.0), color)
				var v3 := g.vert(ei + Vector3(oix * pb.x, pb.y, oiz * pb.x), ni, Vector2(u0, pb.y / 3.0), color)
				# counter-clockwise around the outward profile normal
				if s > 0.0:
					g.quad(v0, v1, v2, v3)
				else:
					g.quad(v0, v3, v2, v1)
			if glow:
				if not stripes.has(key):
					stripes[key] = Geo.new()
				_glow_stripe(stripes[key], i, j, s)
	# Sprint tracks: a barrier across each end of the road.
	if not t.closed:
		var g0: Geo = geos.values()[0]
		for e: Vector2i in [Vector2i(0, -1), Vector2i(t.count - 1, 1)]:
			var i := e.x
			var dir := float(e.y)
			var key := Vector2i(floori(t.px[i] / CHUNK), floori(t.pz[i] / CHUNK)) if chunked else Vector2i.ZERO
			var g: Geo = geos.get(key, g0)
			var ox := t.tx[i] * dir
			var oz := t.tz[i] * dir
			var steps := 8
			for q in steps:
				var la := -t.hw[i] - BARRIER_W + (2.0 * (t.hw[i] + BARRIER_W)) * q / steps
				var lb := -t.hw[i] - BARRIER_W + (2.0 * (t.hw[i] + BARRIER_W)) * (q + 1) / steps
				var ya := c.surf_y(i, clampf(la, -t.hw[i], t.hw[i]))
				var yb := c.surf_y(i, clampf(lb, -t.hw[i], t.hw[i]))
				for p in nP:
					var p0: Vector2 = BARRIER_PROFILE[p]
					var p1: Vector2 = BARRIER_PROFILE[p + 1]
					var part: int = BARRIER_PART[p]
					var color := panel_b if part == 1 else (cap if part == 2 else concrete)
					var n := Vector3(ox * pn[p].x, pn[p].y, oz * pn[p].x)
					var at := func(lat: float, yy: float, o: float, y: float) -> Vector3:
						return Vector3(t.px[i] + t.nx[i] * lat + ox * o, yy + y, t.pz[i] + t.nz[i] * lat + oz * o)
					g.sweep_quad(at.call(la, ya, p0.x, p0.y), at.call(lb, yb, p0.x, p0.y), at.call(lb, yb, p1.x, p1.y),
						at.call(la, ya, p1.x, p1.y), n, n, color,
						Vector2(la / 3.0, p0.y / 3.0), Vector2(lb / 3.0, p0.y / 3.0), Vector2(lb / 3.0, p1.y / 3.0), Vector2(la / 3.0, p1.y / 3.0))
	var mat := vc_mat(0.82)
	mat.albedo_texture = Tex.detail()
	var n := 0
	for key: Vector2i in geos:
		_add_geo(geos[key], mat, "barriers-%d" % n, true)
		n += 1
	if glow:
		# Night: an emissive stripe along the coloured panel of every barrier, for the glow to pick up.
		var sm := std_mat(Themes.col(0x06242e), 0.4)
		sm.emission_enabled = true
		sm.emission = Themes.col(accent[0])
		sm.emission_energy_multiplier = 1.4
		n = 0
		for key: Vector2i in stripes:
			_add_geo(stripes[key], sm, "glow-stripes-%d" % n)
			n += 1


func _glow_stripe(g: Geo, i: int, j: int, s: float) -> void:
	var t := ctx.track
	var y0 := 0.5
	var y1 := 0.66
	# just in front of the sloping panel face (BARRIER_PROFILE points 2-3)
	var at := func(n: int, y: float) -> Vector3:
		var o := t.hw[n] + 0.12 + (y - 0.32) * 0.08 / 0.64 - 0.015
		return Vector3(t.px[n] + t.nx[n] * s * o, ctx.edge_y(n, s) + y, t.pz[n] + t.nz[n] * s * o)
	g.quad_uv(at.call(i, y0), at.call(j, y0), at.call(j, y1), at.call(i, y1), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0),
		WHITE, Vector3(-t.nx[i] * s, 0.0, -t.nz[i] * s))


## Earth slopes from the outside of the barriers down into the terrain.
func _build_embankments() -> void:
	var c := ctx
	var t := c.track
	var rows := c.segs + 1
	var g := Geo.new()
	var gc: Dictionary = theme["ground"]
	# the terrain material brightens by 1/0.86 (Tex.BOOST), as the JS colours here do
	var verge := Themes.lin(gc["a"]) * 0.85
	var earth := Themes.lin(gc["dirt"])
	var rock := Themes.lin(gc["rock"])
	verge.a = 1.0
	for s: float in [1.0, -1.0]:
		var start := g.count()
		for k in rows:
			var i := c.wrap(k)
			var eY := c.edge_y(i, s)
			var inner := s * c.kappa[i] > 0.0
			var max_ext := clampf(1.0 / maxf(1e-4, absf(c.kappa[i])) - t.hw[i] - BARRIER_W - 1.0, 0.4, 10.0) if inner else 10.0
			var o0 := t.hw[i] + BARRIER_W
			var o1 := o0 + 0.35
			var q := _side(i, s, o1 + 2.0)
			var drop := eY - terrain.height_at(q.x, q.y)
			var ext := clampf(drop * 1.15, 0.6, max_ext)
			q = _side(i, s, o1 + ext)
			var toe_y := minf(terrain.height_at(q.x, q.y) - 0.9, eY - 0.5)
			var steep := (eY - toe_y) / ext
			var a := _side(i, s, o0)
			var b := _side(i, s, o1)
			var tc := earth.lerp(rock, VNoise.smoothstep(0.9, 1.6, steep))
			g.vert(Vector3(a.x, eY - 0.02, a.y), Vector3.UP, a / 7.0, verge)
			g.vert(Vector3(b.x, eY - 0.1, b.y), Vector3.UP, b / 7.0, verge)
			g.vert(Vector3(q.x, toe_y, q.y), Vector3.UP, q / 7.0, tc)
		for k in rows - 1:
			var a := start + k * 3
			var cc := a + 3
			# counter-clockwise seen from above on both sides
			if s > 0.0:
				g.quad(a, cc, cc + 1, a + 1)
				g.quad(a + 1, cc + 1, cc + 2, a + 2)
			else:
				g.quad(a, a + 1, cc + 1, cc)
				g.quad(a + 1, a + 2, cc + 2, cc + 1)
	if not t.closed:
		# end of a sprint: slope down behind the end barriers
		for e: Vector2i in [Vector2i(0, -1), Vector2i(t.count - 1, 1)]:
			var i := e.x
			var dir := float(e.y)
			var ox := t.tx[i] * dir
			var oz := t.tz[i] * dir
			var start := g.count()
			var steps := 8
			for q in steps + 1:
				var lat := -t.hw[i] - BARRIER_W + (2.0 * (t.hw[i] + BARRIER_W)) * q / steps
				var y := c.surf_y(i, clampf(lat, -t.hw[i], t.hw[i]))
				var ax := t.px[i] + t.nx[i] * lat + ox * BARRIER_W
				var az := t.pz[i] + t.nz[i] * lat + oz * BARRIER_W
				var ext := clampf((y - terrain.height_at(ax + ox * 3.0, az + oz * 3.0)) * 1.15, 0.6, 10.0)
				var qx := ax + ox * ext
				var qz := az + oz * ext
				var toe_y := minf(terrain.height_at(qx, qz) - 0.9, y - 0.5)
				g.vert(Vector3(ax, y - 0.02, az), Vector3.UP, Vector2(ax, az) / 7.0, verge)
				g.vert(Vector3(qx, toe_y, qz), Vector3.UP, Vector2(qx, qz) / 7.0, earth)
			for q in steps:
				var a := start + q * 2
				if dir < 0.0:
					g.quad(a, a + 2, a + 3, a + 1)
				else:
					g.quad(a, a + 1, a + 3, a + 2)
	g.compute_normals()
	_add_geo(g, terrain.material, "embankments")


## (x, z) of the point o metres out from the centre of sample i on side s.
func _side(i: int, s: float, o: float) -> Vector2:
	var t := ctx.track
	return Vector2(t.px[i] + t.nx[i] * s * o, t.pz[i] + t.nz[i] * s * o)


# =============================================================================
# Gates
# =============================================================================

func _build_gates() -> void:
	var c := ctx
	var t := c.track
	var defs: Array[Dictionary] = []
	if t.closed:
		defs.append({"i": 0, "kind": "start", "label": "START · FINISH"})
	else:
		defs.append({"i": t.start_line, "kind": "start", "label": "START"})
		defs.append({"i": t.finish_idx, "kind": "start", "label": "FINISH"})
	for k in t.cp_samples.size():
		defs.append({"i": t.cp_samples[k], "kind": "cp", "k": k, "label": "CHECKPOINT %d" % (k + 1)})
	var atlas := Tex.gate_atlas(defs)
	var frame := Geo.new()
	var banner := Geo.new()
	var dark := Themes.lin(0x2b2f37)
	var steel := Themes.lin(0x8b9099)
	var foot := Themes.lin(0xa9abad)
	cp_materials.resize(t.cp_samples.size())
	var start_mat := _strip_material(GATE_STATE["start"])
	for row in defs.size():
		var d := defs[row]
		var i: int = d["i"]
		var big: bool = d["kind"] == "start"
		var cb := cos(t.bank[i])
		var W := (t.hw[i] + 0.38) / cb  # pillar centre, in the frame tilted with the road
		var Hh := 8.2 if big else 7.2
		var m := Transform3D(Basis(Vector3.UP, atan2(t.tx[i], t.tz[i])) * Basis(Vector3.BACK, -t.bank[i]), Vector3(t.px[i], t.py[i], t.pz[i]))
		var pw := 1.0 if big else 0.8
		var pd := 1.2 if big else 0.9
		for s: float in [1.0, -1.0]:
			frame.box_at(m, Vector3(s * W, (Hh - 2.5) / 2.0, 0.0), Vector3(pw, Hh + 2.5, pd), dark)
			frame.box_at(m, Vector3(s * W, 0.3, 0.0), Vector3(pw + 0.4, 0.6, pd + 0.4), foot)
			frame.box_at(m, Vector3(s * (W + pw / 2.0 + 0.02), Hh * 0.5, 0.0), Vector3(0.06, Hh * 0.8, 0.3), steel)
		var beam_h := 2.0 if big else 1.6
		var beam_d := 1.4 if big else 1.0
		frame.box_at(m, Vector3(0.0, Hh - beam_h / 2.0, 0.0), Vector3(2.0 * W + pw, beam_h, beam_d), dark)
		# banner on both faces of the beam (atlas rows from the top of the image)
		var va := float(row + 1) / defs.size()
		var vb := float(row) / defs.size()
		var bx := W - pw / 2.0 - 0.05
		var by0 := Hh - beam_h + 0.12
		var by1 := Hh - 0.12
		var bz := beam_d / 2.0 + 0.02
		banner.quad_uv(m * Vector3(bx, by0, -bz), m * Vector3(-bx, by0, -bz), m * Vector3(-bx, by1, -bz), m * Vector3(bx, by1, -bz),
			Vector2(0, va), Vector2(1, va), Vector2(1, vb), Vector2(0, vb), WHITE)
		banner.quad_uv(m * Vector3(-bx, by0, bz), m * Vector3(bx, by0, bz), m * Vector3(bx, by1, bz), m * Vector3(-bx, by1, bz),
			Vector2(0, va), Vector2(1, va), Vector2(1, vb), Vector2(0, vb), WHITE)
		# emissive light strips: inside the pillars and under the beam
		var sb := Geo.new()
		var ix := W - pw / 2.0 - 0.05
		for s: float in [1.0, -1.0]:
			sb.box_at(m, Vector3(s * ix, 0.65 + (Hh - beam_h - 0.75) / 2.0, 0.0), Vector3(0.12, Hh - beam_h - 0.75, 0.42), WHITE)
		sb.box_at(m, Vector3(0.0, Hh - beam_h - 0.06, 0.0), Vector3(2.0 * ix, 0.12, 0.42), WHITE)
		for z: float in [-1.0, 1.0]:
			sb.box_at(m, Vector3(0.0, Hh - 0.06, z * (beam_d / 2.0 + 0.03)), Vector3(2.0 * W + pw - 0.2, 0.1, 0.08), WHITE)
		var mat := start_mat
		if d["kind"] == "cp":
			mat = _strip_material(GATE_STATE["next"])
			cp_materials[d["k"]] = mat
		_add_geo(sb, mat, "gate-lights-%d" % row)
	var fm := vc_mat(0.42, 0.55)
	fade_near_camera(fm)
	_add_geo(frame, fm, "gate-frames", true)
	var bm := std_mat(Color.WHITE, 0.55)
	bm.albedo_texture = atlas
	bm.emission_enabled = true
	bm.emission = Color.WHITE
	bm.emission_texture = atlas
	bm.emission_energy_multiplier = 0.55 if theme.get("lamps", false) else 0.12
	fade_near_camera(bm)
	_add_geo(banner, bm, "gate-banners")
