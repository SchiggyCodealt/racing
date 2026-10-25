// lamp_pool.gdshader
// ------------------------------------------------------------------
// Light pools on the road under the lamps (trackMesh.js: an additive,
// unlit decal mesh with the glow texture), drawn a hair towards the camera
// like the road paint.
shader_type spatial;
render_mode skip_vertex_transform, unshaded, blend_add, depth_draw_never, cull_back, fog_disabled;

uniform sampler2D glow_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0, 0.72, 0.47);
uniform float opacity = 0.5;
uniform float pull = 0.0012;

void vertex() {
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz * (1.0 - pull);
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	ALBEDO = texture(glow_tex, UV).rgb * tint * opacity;
}
