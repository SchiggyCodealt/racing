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
// (v6.41) the livery painted over the body (sim/looks.gd LIVERIES: 0 none, 1 stripes, 2 two-tone,
// 3 sash, 4 chequer, 5 fade), laid out in the painted body's box (CarBuild.body_box: rear z, front z,
// low y, high y) so it fits every car; trim: white on a dark paint, near-black on a light one
uniform int livery = 0;
uniform vec4 body_box = vec4(-2.3, 2.5, 0.15, 1.1);
uniform vec3 trim : source_color = vec3(0.95, 0.95, 0.95);

varying float v_kind;
varying vec3 v_rest;

void vertex() {
	v_kind = UV2.x;
	v_rest = vec3(UV.x, UV2.y, UV.y);
}

// The body colour at rest position p with the livery over it (linear colours).
vec3 livery_paint(vec3 base, vec3 p) {
	float u = clamp((p.z - body_box.x) / max(body_box.y - body_box.x, 0.1), 0.0, 1.0); // 0 tail .. 1 nose
	float v = clamp((p.y - body_box.z) / max(body_box.w - body_box.z, 0.1), 0.0, 1.0); // 0 bottom .. 1 top
	float ax = abs(p.x);
	if (livery == 1) { // twin stripes over the car, nose to tail (and down the nose and the tail; the sides lie further out)
		float s = step(0.07, ax) * step(ax, 0.21) * step(0.12, v);
		return mix(base, trim, s);
	} else if (livery == 2) { // the lower body in the accent
		return mix(base, accent, step(v, 0.42));
	} else if (livery == 3) { // a broad band rising towards the nose, edged in the accent
		float d = abs((u - 0.5) - (v - 0.5) * 0.9);
		return mix(mix(base, accent, step(d, 0.11)), trim, step(d, 0.085));
	} else if (livery == 4) { // a chequered band along the sides (0.14 m squares)
		float band = step(0.2, v) * step(v, 0.44);
		float c = mod(floor(p.z / 0.14) + floor(p.y / 0.14), 2.0);
		return mix(base, mix(vec3(0.85), vec3(0.015), c), band);
	} else if (livery == 5) { // the paint fading into the accent towards the tail
		return mix(base, accent, smoothstep(0.62, 0.12, u));
	}
	return base;
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
		alb = (livery > 0 ? livery_paint(paint, v_rest) : paint) * alb; rough = 0.36; metal = 0.3; coat = 1.0;
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
