// road_paint.gdshader
// ------------------------------------------------------------------
// Paint on the road: edge and centre lines, start grid boxes, curbs and the
// checkered start line (trackMesh.js uses MeshStandardMaterial with a
// polygon offset). Vertex colour (stored as sRGB, see geo.gd) times an
// optional texture; the surface is drawn a hair closer to the camera
// (`pull` of the view distance, which keeps its place on screen) so it
// never fights with the asphalt underneath, near or far.
shader_type spatial;
render_mode skip_vertex_transform, cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform float roughness = 0.6;
uniform float pull = 0.0006;

vec3 srgb_to_lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz * (1.0 - pull);
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	ALBEDO = srgb_to_lin(COLOR.rgb) * texture(albedo_tex, UV).rgb;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
}
