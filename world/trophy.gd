class_name Trophy
extends Node3D
## trophy.gd (v6.14.0): a cup trophy for the trophy moment at the end of a championship (world/podium.gd,
## modes/field_mode.gd): a two-handled cup on a stem and a dark two-step base, gold, silver or bronze,
## from a handful of primitive meshes (no model files). About `height` m tall; its origin is the bottom
## of the base.
##
##   var t := Trophy.new("gold", 1.0)      # "gold" | "silver" | "bronze"

const COLORS := {"gold": Color("#e3b737"), "silver": Color("#c9cfd8"), "bronze": Color("#c47a3c")}
const BASE := Color("#1b1d22")

var kind := "gold"


func _init(p_kind: String = "gold", height: float = 1.0) -> void:
	kind = p_kind if COLORS.has(p_kind) else "gold"
	name = "Trophy"
	var h := height
	var metal := StandardMaterial3D.new()
	metal.albedo_color = COLORS[kind]
	metal.metallic = 0.85
	metal.roughness = 0.28
	var dark := StandardMaterial3D.new()
	dark.albedo_color = BASE
	dark.roughness = 0.5
	# the base: two dark steps and a metal plate on the front
	_add(_box(Vector3(0.46, 0.12, 0.46) * h, dark), Vector3(0, 0.06 * h, 0))
	_add(_box(Vector3(0.34, 0.1, 0.34) * h, dark), Vector3(0, 0.17 * h, 0))
	_add(_box(Vector3(0.2, 0.05, 0.01) * h, metal), Vector3(0, 0.06 * h, 0.231 * h))
	# the stem and its knot
	_add(_cyl(0.035 * h, 0.07 * h, 0.2 * h, metal), Vector3(0, 0.32 * h, 0))
	_add(_sphere(0.07 * h, metal), Vector3(0, 0.4 * h, 0))
	# the cup: a bowl narrowing to the stem, a rim
	_add(_cyl(0.24 * h, 0.06 * h, 0.42 * h, metal), Vector3(0, 0.66 * h, 0))
	var rim := TorusMesh.new()
	rim.inner_radius = 0.215 * h
	rim.outer_radius = 0.255 * h
	rim.material = metal
	_add(_mesh(rim), Vector3(0, 0.87 * h, 0))
	# the handles: rings on either side, upright
	for side in [-1.0, 1.0]:
		var ring := TorusMesh.new()
		ring.inner_radius = 0.075 * h
		ring.outer_radius = 0.11 * h
		ring.material = metal
		var mi := _mesh(ring)
		mi.rotation = Vector3(0, 0, PI * 0.5)
		mi.position = Vector3(side * 0.25 * h, 0.7 * h, 0)
		add_child(mi)


func _add(mi: MeshInstance3D, at: Vector3) -> void:
	mi.position = at
	add_child(mi)


func _mesh(m: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _box(size: Vector3, mat: Material) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	return _mesh(b)


func _cyl(top: float, bottom: float, height: float, mat: Material) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = 24
	c.material = mat
	return _mesh(c)


func _sphere(r: float, mat: Material) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = 2.0 * r
	s.radial_segments = 16
	s.rings = 8
	s.material = mat
	return _mesh(s)
