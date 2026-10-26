class_name SensorRays
extends MeshInstance3D
## sensor_rays.gd (SensorRays of web/src/game/carMesh.js)
## ------------------------------------------------------------------
## The AI's sensor rays, drawn from the car's nose (green far, red when
## close) with a dot where each ray hits a wall. Drawn over everything,
## unlit and not tone mapped, like the JS (depthTest off, toneMapped off).
##
## Use: var rays := SensorRays.new(); world.add_child(rays)
##      rays.update(car, distances, range)   # car: x, y, z, yaw; distances: one per angle (m)

## Sensor directions in degrees (+ = left), as ai/sensors.js SENSOR_ANGLES.
var angles: PackedFloat32Array = PackedFloat32Array([90, 60, 35, 15, 0, -15, -35, -60, -90])

var _im := ImmediateMesh.new()
var _line_mat: StandardMaterial3D
var _dot_mat: StandardMaterial3D


func _init(p_angles: PackedFloat32Array = PackedFloat32Array()) -> void:
	name = "sensor-rays"
	if not p_angles.is_empty():
		angles = p_angles
	top_level = true
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-1e5, -1e4, -1e5), Vector3(2e5, 2e4, 2e5))
	_line_mat = StandardMaterial3D.new()
	_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_mat.vertex_color_use_as_albedo = true
	_line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_line_mat.no_depth_test = true
	_line_mat.disable_fog = true
	_line_mat.render_priority = 10
	_dot_mat = StandardMaterial3D.new()
	_dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dot_mat.albedo_color = Color.WHITE
	_dot_mat.no_depth_test = true
	_dot_mat.disable_fog = true
	_dot_mat.use_point_size = true
	_dot_mat.point_size = 5.0
	_dot_mat.render_priority = 11


## car: Object or Dictionary with x, y, z, yaw; rays: distance per angle (m); range: the sensor range (m).
func update(car: Variant, rays: PackedFloat32Array, sensor_range: float) -> void:
	var yaw := float(car.get("yaw"))
	var fx := sin(yaw)
	var fz := cos(yaw)
	var lx := fz
	var lz := -fx
	var o := Vector3(float(car.get("x")) + fx * 1.5, float(car.get("y")) + 0.8, float(car.get("z")) + fz * 1.5)
	_im.clear_surfaces()
	var n := mini(angles.size(), rays.size())
	if n == 0:
		return
	var ends := PackedVector3Array()
	_im.surface_begin(Mesh.PRIMITIVE_LINES, _line_mat)
	for k in n:
		var a := deg_to_rad(angles[k])
		var d := rays[k]
		var dir := Vector3(fx * cos(a) + lx * sin(a), 0.0, fz * cos(a) + lz * sin(a))
		var e := o + dir * d
		ends.append(e)
		# Three.js setHSL(0.33 * share, 0.9, 0.55): red (close) to green (far), shown untonemapped (sRGB)
		var c := AIFleet._hsl(0.33 * minf(1.0, d / sensor_range), 0.9, 0.55).srgb_to_linear()
		c.a = 0.9
		_im.surface_set_color(c)
		_im.surface_add_vertex(o)
		_im.surface_set_color(c)
		_im.surface_add_vertex(e)
	_im.surface_end()
	_im.surface_begin(Mesh.PRIMITIVE_POINTS, _dot_mat)
	for e in ends:
		_im.surface_add_vertex(e)
	_im.surface_end()
