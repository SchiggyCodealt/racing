// skyline.gdshader
// ------------------------------------------------------------------
// Night city blocks (trackMesh.js skylineMaterial): a dark facade with a grid
// of windows in world space (so every block size gets the same window
// size), about 40 % of them lit. Blocks are instanced boxes, never rotated
// (walls face x or z).
shader_type spatial;
render_mode cull_back;

uniform vec3 facade : source_color = vec3(0.106, 0.129, 0.188);

varying vec3 win_w;
varying vec3 win_n;

void vertex() {
	win_w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	win_n = NORMAL;
}

void fragment() {
	ALBEDO = facade;
	ROUGHNESS = 0.8;
	METALLIC = 0.1;
	vec3 an = abs(win_n);
	if (an.y < 0.5) {
		float u = an.x > an.z ? win_w.z : win_w.x;
		vec2 g = vec2(u / 3.4, (win_w.y + 0.6) / 3.8), cell = floor(g), f = fract(g);
		float win = step(0.2, f.x) * step(f.x, 0.8) * step(0.28, f.y) * step(f.y, 0.78);
		float r = fract(sin(dot(cell, vec2(12.9898, 78.233)) + dot(floor(win_w.xz / 9.0), vec2(3.17, 7.31))) * 43758.5453);
		vec3 tint = mix(vec3(1.0, 0.72, 0.38), vec3(0.75, 0.88, 1.0), step(0.85, r));
		EMISSION = tint * win * step(0.6, r) * (0.6 + 0.9 * fract(r * 13.7));
	}
}
