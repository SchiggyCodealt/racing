// skid.gdshader: skid mark strip pieces (carMesh.js SkidMarks). One MultiMesh
// instance per piece: its four corners are the columns of the instance
// transform (basis x, y, z and origin), picked by the vertex's x (0..3);
// INSTANCE_CUSTOM.x / .y = alpha at the old / new end, .z / .w = the weights of
// road surfaces 1 and 2 (dirt, packed snow: sim/surfaces.gd "marks" colours) under
// the wheel. Unlit, nudged towards the camera so it never fights the road.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled;

uniform vec3 color : source_color = vec3(0.051);
uniform vec3 color_1 : source_color = vec3(0.29, 0.208, 0.141);
uniform vec3 color_2 : source_color = vec3(0.553, 0.612, 0.682);
varying float v_alpha;
varying vec3 v_color;

void vertex() {
	int k = int(VERTEX.x + 0.5);
	vec3 p = k == 0 ? MODEL_MATRIX[0].xyz : k == 1 ? MODEL_MATRIX[1].xyz : k == 2 ? MODEL_MATRIX[2].xyz : MODEL_MATRIX[3].xyz;
	v_alpha = k < 2 ? INSTANCE_CUSTOM.x : INSTANCE_CUSTOM.y;
	float w1 = clamp(INSTANCE_CUSTOM.z, 0.0, 1.0);
	float w2 = clamp(INSTANCE_CUSTOM.w, 0.0, 1.0);
	v_color = color * max(0.0, 1.0 - w1 - w2) + color_1 * w1 + color_2 * w2;
	vec4 mv = VIEW_MATRIX * vec4(p, 1.0);
	mv.xyz += normalize(-mv.xyz) * 0.04;
	VERTEX = mv.xyz;
}

void fragment() {
	ALBEDO = v_color;
	ALPHA = v_alpha;
}
