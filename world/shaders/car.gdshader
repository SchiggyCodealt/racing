// car.gdshader: every opaque part of a car in one material (world/car_kit.gd).
// The vertex says what the part is made of: UV2.x = the kind (the table below,
// the same as CarKit's constants); COLOR = its albedo (sRGB) for the kinds that
// don't take a uniform colour; UV = (x, z) and UV2.y = y of its rest position in
// the car's frame, where the panel lines are drawn (seam_a / seam_b), so they
// stay on the body while the skeleton moves it.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 paint : source_color = vec3(0.84, 0.15, 0.24);
uniform vec3 accent : source_color = vec3(0.1, 0.1, 0.12);
uniform vec3 stripe : source_color = vec3(0.95, 0.95, 0.95);
uniform float head_glow = 2.2;  // headlight emission (day: running lights; night: full beam)
uniform float tail_glow = 0.75; // tail lights; brake lights up to ~3.4
// panel lines: a line on the plane z = c (axis 0, limited to r0 <= |x| <= r1) or |x| = c
// (axis 1, limited to r0 <= z <= r1), between heights y0 and y1:
// seam_a = (axis, c, r0, r1), seam_b = (y0, y1, depth 0..1, 0)
uniform int seam_count = 0;
uniform vec4 seam_a[12];
uniform vec4 seam_b[12];
uniform float seam_strength = 1.0; // 0: no panel lines (low quality)

varying float v_kind;
varying vec3 v_rest;

void vertex() {
	v_kind = UV2.x;
	v_rest = vec3(UV.x, UV2.y, UV.y);
}

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	int k = int(v_kind + 0.5);
	vec3 alb = to_linear(COLOR.rgb);
	float rough = 0.5;
	float metal = 0.0;
	float coat = 0.0;
	vec3 emit = vec3(0.0);
	if (k == 0) {
		alb = paint * alb; rough = 0.36; metal = 0.3; coat = 1.0;
	} else if (k == 1) {
		alb = accent * alb; rough = 0.4; metal = 0.25; coat = 1.0;
	} else if (k == 2) {
		alb = stripe * alb; rough = 0.4; metal = 0.1; coat = 1.0;
	} else if (k == 3) {
		rough = 0.28; metal = 0.05; coat = 0.6;
	} else if (k == 4) {
		rough = 0.85;
	} else if (k == 5) {
		rough = 0.24; metal = 1.0;
	} else if (k == 6) {
		rough = 0.38; metal = 0.4;
	} else if (k == 7) {
		rough = 0.05; metal = 0.75;
	} else if (k == 8) {
		alb = vec3(1.0); rough = 0.2;
		emit = vec3(1.0, 0.88, 0.69) * head_glow;
	} else if (k == 9) {
		alb = vec3(0.043, 0.0016, 0.0016); rough = 0.3;
		// ACES bleeds bright red into green (the lights would turn orange): a little negative green and blue
		emit = vec3(1.0, -0.084, -0.034) * tail_glow;
	} else if (k == 10) {
		rough = 0.82;
	}
	if (k <= 1 && seam_count > 0 && seam_strength > 0.0) {
		// panel lines: thin dark grooves, faded out where a pixel covers more than a centimetre
		float fz = fwidth(v_rest.z);
		float fx = fwidth(abs(v_rest.x));
		float line = 0.0;
		for (int i = 0; i < seam_count; i++) {
			vec4 a = seam_a[i];
			vec4 b = seam_b[i];
			float d = a.x < 0.5 ? v_rest.z - a.y : abs(v_rest.x) - a.y;
			float r = a.x < 0.5 ? abs(v_rest.x) : v_rest.z;
			float fw = a.x < 0.5 ? fz : fx;
			float inside = step(a.z, r) * step(r, a.w) * step(b.x, v_rest.y) * step(v_rest.y, b.y);
			float l = 1.0 - smoothstep(0.003, 0.003 + fw * 1.5, abs(d));
			l *= 1.0 - smoothstep(0.006, 0.02, fw);
			line = max(line, l * inside * b.z);
		}
		alb *= 1.0 - 0.8 * line * seam_strength;
		coat *= 1.0 - line;
	}
	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = metal;
	CLEARCOAT = coat;
	CLEARCOAT_ROUGHNESS = 0.06;
	EMISSION = emit;
}
