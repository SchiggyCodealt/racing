// car_glass.gdshader: a car's windows and canopy, tinted and see-through (the driver shows
// through them), more mirror-like at grazing angles. Drawn without shadows (car_model.gd).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

uniform vec3 tint : source_color = vec3(0.05, 0.085, 0.13);
uniform float clear = 0.5;   // alpha looking straight through
uniform float edge = 0.94;   // alpha at grazing angles

void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = tint;
	ALPHA = mix(clear, edge, f);
	ROUGHNESS = 0.04;
	METALLIC = 0.0;
	SPECULAR = 0.8;
}
