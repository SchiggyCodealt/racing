// town.gdshader
// ------------------------------------------------------------------
// (v6.28) Daytime houses of a theme's town (world/track_scenery.gd): boxes
// with a facade colour each (the MultiMesh instance colour), a roof colour on
// top, rows of windows with shutters on some houses and shop fronts on the
// ground floor. The grid is in metres on each face, so every house size gets
// the same window size; boxes may be turned about y.
shader_type spatial;
render_mode cull_back;

uniform vec3 roof : source_color = vec3(0.71, 0.35, 0.24);

varying vec3 v_col;
varying vec3 v_loc;
varying vec3 v_n;
varying float v_seed;
varying float v_h;

void vertex() {
	v_col = COLOR.rgb;
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	v_loc = VERTEX * sc;
	v_h = sc.y;
	v_n = NORMAL;
	v_seed = fract(sin(dot(MODEL_MATRIX[3].xz, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 an = abs(v_n);
	if (an.y > 0.5) {
		ALBEDO = roof * (0.85 + 0.3 * v_seed);
		ROUGHNESS = 0.9;
	} else {
		float u = (an.x > an.z ? v_loc.z : v_loc.x) + v_seed * 11.0;
		float y = v_loc.y;
		vec2 f = fract(vec2(u / 3.6, (y - 4.4) / 3.3));
		float up = step(4.4, y) * step(y, v_h - 1.4);
		float rows = step(0.22, f.y) * step(f.y, 0.8) * up;
		float win = step(0.3, f.x) * step(f.x, 0.7) * rows;
		float shut = (step(0.14, f.x) * step(f.x, 0.3) + step(0.7, f.x) * step(f.x, 0.86)) * rows * step(0.45, v_seed);
		float fs = fract(u / 6.2);
		float shop = step(0.5, y) * step(y, 3.3) * step(0.12, fs) * step(fs, 0.88);
		float band = step(3.5, y) * step(y, 4.0);
		vec3 c = v_col;
		c = mix(c, mix(vec3(0.20, 0.36, 0.24), vec3(0.62, 0.36, 0.22), step(0.75, v_seed)), shut);
		c = mix(c, c * 0.8, band);
		float glass = max(win, shop);
		c = mix(c, vec3(0.09, 0.11, 0.14), glass);
		ALBEDO = c;
		ROUGHNESS = mix(0.88, 0.15, glass);
		SPECULAR = mix(0.35, 0.9, glass);
	}
}
