// glow.gdshader: the nitro glow trail (carMesh.js GLOW_FRAG). One MultiMesh
// instance per blob: centre in the instance origin, INSTANCE_CUSTOM.x = size
// (m), .y = alpha. Camera-facing soft discs added to what is behind.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled;

uniform vec3 color = vec3(0.35, 0.75, 2.4);
uniform float opacity = 1.0;
varying vec2 v_uv;
varying float v_alpha;

void vertex() {
	v_uv = VERTEX.xy;
	v_alpha = INSTANCE_CUSTOM.y;
	vec4 mv = VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0);
	mv.xy += VERTEX.xy * INSTANCE_CUSTOM.x;
	VERTEX = mv.xyz;
}

void fragment() {
	float a = smoothstep(1.0, 0.0, length(v_uv) * 2.0) * v_alpha * opacity;
	if (a < 0.004) discard;
	ALBEDO = color;
	ALPHA = a;
}
