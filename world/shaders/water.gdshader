// water.gdshader
// ------------------------------------------------------------------
// The sea (trackMesh.js: a slightly see-through, glossy plane with drifting
// ripple normals). Reflections come from the sky (and SSR on high).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec3 water_color : source_color = vec3(0.106, 0.416, 0.549);
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float opacity = 0.84;

void vertex() {
	TANGENT = vec3(1.0, 0.0, 0.0);
	BINORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	ALBEDO = water_color;
	ROUGHNESS = 0.07;
	METALLIC = 0.0;
	SPECULAR = 0.5;
	NORMAL_MAP = texture(normal_map, UV + vec2(TIME * 0.011, TIME * 0.007)).rgb;
	NORMAL_MAP_DEPTH = 0.32;
	ALPHA = opacity;
}
