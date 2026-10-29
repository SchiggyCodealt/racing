// road_surface.gdshader
// ------------------------------------------------------------------
// The road of a track with dirt or packed snow (world/track_mesh.gd; an all-asphalt
// track keeps the StandardMaterial3D, so it looks exactly as before). Per vertex:
// COLOR.r = the asphalt's wear tint (sRGB, as on the plain road), COLOR.g / COLOR.b =
// the blend weights of surface 1 (dirt) and 2 (packed snow) from BuiltTrack.surf_w.
// Asphalt is drawn as the StandardMaterial3D draws it (textures times tint times
// tint_scale); dirt and snow are their colour from sim/surfaces.gd times the detail of
// Tex.loose(). Where the surface changes (the weights ramp over ~10 m) the border is
// ragged, following large noise patches, instead of a cross-fade.
shader_type spatial;
render_mode cull_back;

uniform sampler2D asphalt_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_rough : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D loose_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D loose_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// the asphalt material's linear albedo multiplier (track_mesh.gd K) and normal strength
uniform float tint_scale = 1.13;
uniform float asphalt_normal_scale = 0.55;
// surface 1 (dirt) and 2 (packed snow): colour, roughness, normal strength
uniform vec3 color_1 : source_color = vec3(0.541, 0.416, 0.282);
uniform vec3 color_2 : source_color = vec3(0.91, 0.933, 0.957);
uniform float rough_1 = 0.95;
uniform float rough_2 = 0.6;
uniform float normal_1 = 0.9;
uniform float normal_2 = 0.25;

vec3 srgb_to_lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

// A blend weight w (0..1) turned into a ragged edge: 0 stays 0, 1 stays 1, in between the
// noise n decides where the border runs.
float ragged(float w, float n) {
	float x = clamp((w - mix(0.12, 0.88, n)) / 0.16 + 0.5, 0.0, 1.0);
	return x * x * (3.0 - 2.0 * x);
}

void fragment() {
	vec3 vc = srgb_to_lin(COLOR.rgb);
	float wear = vc.r;
	vec4 lm = texture(loose_map, UV);
	float n = texture(loose_map, UV * 0.17 + vec2(0.31, 0.57)).g;
	float w1 = ragged(vc.g, n);
	float w2 = ragged(vc.b, n);
	float w0 = max(0.0, 1.0 - w1 - w2);
	float sum = max(w0 + w1 + w2, 1e-4);
	w0 /= sum;
	w1 /= sum;
	w2 /= sum;
	// the worn racing line shows on loose ground too, as packed lanes
	float lanes = mix(1.0, clamp(wear * 1.45, 0.75, 1.15), 0.6);
	vec3 a0 = texture(asphalt_map, UV).rgb * tint_scale * wear;
	vec3 a1 = color_1 * lm.r * lanes;
	vec3 a2 = color_2 * lm.b * mix(1.0, lanes, 0.8);
	ALBEDO = a0 * w0 + a1 * w1 + a2 * w2;
	ROUGHNESS = texture(asphalt_rough, UV).r * w0 + rough_1 * w1 + rough_2 * w2;
	vec2 n0 = (texture(asphalt_normal, UV).xy * 2.0 - 1.0) * asphalt_normal_scale;
	vec2 nl = texture(loose_normal, UV).xy * 2.0 - 1.0;
	vec2 nm = n0 * w0 + nl * (normal_1 * w1 + normal_2 * w2);
	NORMAL_MAP = vec3(nm * 0.5 + 0.5, 1.0);
	NORMAL_MAP_DEPTH = 1.0;
}
