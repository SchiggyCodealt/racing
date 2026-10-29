// sky.gdshader
// ------------------------------------------------------------------
// The theme sky (scene.js SKY_FRAG): a gradient from the horizon to the
// zenith, a warm glow and a disc for the sun, drifting fbm clouds and (night)
// a star field (v6.4: and the northern lights, `aurora`); below the horizon it
// fades into the fog colour.
//
// The radiance cubemap pass (Godot's environment lighting, Three.js' PMREM
// environment map) is the ENV variant of the JS shader: the theme's sky
// scaled by `env`, the ground colour below the horizon, no clouds, no stars,
// no sun disc, plus the hemisphere light of the theme (sky colour above,
// ground colour below), so ambient light and reflections come from it.
shader_type sky;

uniform vec3 zenith : source_color = vec3(0.24, 0.55, 1.0);
uniform vec3 horizon : source_color = vec3(0.81, 0.92, 1.0);
uniform vec3 below : source_color = vec3(0.43, 0.54, 0.31);   // fog colour (seen) ...
uniform vec3 ground : source_color = vec3(0.43, 0.54, 0.31);  // ... and theme ground (environment)
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_color : source_color = vec3(1.0);
uniform vec3 cloud_lit : source_color = vec3(1.0);
uniform vec3 cloud_shade : source_color = vec3(0.67, 0.73, 0.8);
uniform float cloud_cover = 0.4;
uniform float haze = 0.5;
uniform float stars = 0.0;
uniform float env = 1.0;
uniform vec3 hemi_sky : source_color = vec3(0.8);
uniform vec3 hemi_ground : source_color = vec3(0.3);
uniform float hemi = 0.0;     // hemisphere light intensity / PI
uniform float cloud_time = 0.0; // seconds, set by World (not TIME: that would rebake the radiance every frame)
// v6.4: the northern lights (theme sky.aurora): rippling curtains of light in the night sky
uniform float aurora = 0.0;
uniform vec3 aurora_color : source_color = vec3(0.2, 1.0, 0.6);
uniform vec3 aurora_edge : source_color = vec3(0.54, 0.3, 1.0);

float hash(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int k = 0; k < 5; k++) { v += a * noise(p); p = p * 2.03 + vec2(17.1, 9.2); a *= 0.5; }
	return v;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	float sd = max(dot(d, sun_dir), 0.0);
	if (AT_CUBEMAP_PASS) {
		vec3 col = mix(horizon, zenith, pow(clamp(h, 0.0, 1.0), 0.5)) * env;
		col += sun_color * env * (pow(sd, 6.0) * 0.22 * haze * (1.0 - 0.6 * clamp(h, 0.0, 1.0)) + pow(sd, 48.0) * 0.35);
		col = mix(col, ground * env * 0.55, smoothstep(0.02, -0.12, h));
		col += mix(hemi_ground, hemi_sky, 0.5 * h + 0.5) * hemi;
		COLOR = col;
	} else {
		vec3 col = mix(horizon, zenith, pow(clamp(h, 0.0, 1.0), 0.5));
		col += sun_color * (pow(sd, 6.0) * 0.22 * haze * (1.0 - 0.6 * clamp(h, 0.0, 1.0)) + pow(sd, 48.0) * 0.35);
		col += sun_color * smoothstep(0.99955, 0.9998, sd) * 18.0;
		if (stars > 0.0 && h > 0.0) {
			// one possible star per small cell of the sky dome, a few percent of them lit
			vec3 q = d * 300.0, cell = floor(q);
			float r = fract(sin(dot(cell, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
			float b = smoothstep(0.3, 0.05, length(fract(q) - 0.5)) * smoothstep(0.985, 1.0, r);
			col += vec3(0.85, 0.9, 1.0) * b * 2.2 * stars * smoothstep(0.02, 0.3, h);
		}
		if (aurora > 0.0 && h > 0.0) {
			// curtains hanging from a high sky plane: each band has a sharp, bright lower edge and
			// fades upwards into a violet fringe, streaked by thin vertical rays; they drift slowly
			vec2 p = d.xz / (h + 0.18);
			float t = cloud_time * 0.03;
			float glow = 0.0;
			float fringe = 0.0;
			for (int k = 0; k < 2; k++) {
				float fk = float(k);
				float along = p.x * (0.5 + 0.2 * fk) + fk * 3.1;
				float edge = 0.35 + 1.25 * fk + 0.45 * sin(along * 0.9 + t + fk * 1.7) + 0.6 * (noise(vec2(along * 0.7, t * 0.5 + fk * 7.0)) - 0.5);
				float x = edge - p.y; // > 0: above the curtain's lower edge
				float hang = smoothstep(-0.06, 0.03, x);
				float streak = noise(vec2(along * 14.0 + t * 2.0, fk * 5.0));
				streak = 0.15 + 0.85 * streak * streak;
				float wane = (0.5 + 0.5 * noise(vec2(along * 0.3 + 11.0, t * 0.3))) * (1.0 - 0.3 * fk);
				glow += hang * exp(-max(x, 0.0) * 2.6) * streak * wane;
				fringe += hang * smoothstep(0.2, 0.6, x) * exp(-max(x - 0.6, 0.0) * 2.5) * streak * wane;
			}
			float fade = smoothstep(0.0, 0.12, h) * (1.0 - smoothstep(0.55, 0.95, h));
			col += (aurora_color * glow + aurora_edge * fringe * 0.6) * fade * aurora * 0.65;
		}
		if (h > 0.0 && cloud_cover > 0.0) {
			vec2 uv = d.xz / (h + 0.1) * 0.9 + vec2(cloud_time * 0.006, cloud_time * 0.002);
			float n = fbm(uv);
			float c = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.28, n) * smoothstep(0.0, 0.18, h);
			float lit = clamp(0.5 - (fbm(uv + sun_dir.xz * 0.06) - n) * 3.0, 0.0, 1.0);
			vec3 cc = mix(cloud_shade, cloud_lit, lit) * (1.0 + pow(sd, 6.0) * 0.6);
			col = mix(col, cc, c * 0.92);
		}
		col = mix(col, below, smoothstep(0.0, -0.04, h));
		COLOR = col;
	}
}
