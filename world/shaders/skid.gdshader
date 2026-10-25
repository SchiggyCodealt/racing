// skid.gdshader: skid mark strip pieces (carMesh.js SkidMarks). One MultiMesh
// instance per piece: its four corners are the columns of the instance
// transform (basis x, y, z and origin), picked by the vertex's x (0..3);
// INSTANCE_CUSTOM.x / .y = alpha at the old / new end. Unlit, near black,
// nudged towards the camera so it never fights the road.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled;

uniform vec3 color : source_color = vec3(0.051);
varying float v_alpha;

void vertex() {
	int k = int(VERTEX.x + 0.5);
	vec3 p = k == 0 ? MODEL_MATRIX[0].xyz : k == 1 ? MODEL_MATRIX[1].xyz : k == 2 ? MODEL_MATRIX[2].xyz : MODEL_MATRIX[3].xyz;
	v_alpha = k < 2 ? INSTANCE_CUSTOM.x : INSTANCE_CUSTOM.y;
	vec4 mv = VIEW_MATRIX * vec4(p, 1.0);
	mv.xyz += normalize(-mv.xyz) * 0.04;
	VERTEX = mv.xyz;
}

void fragment() {
	ALBEDO = color;
	ALPHA = v_alpha;
}
