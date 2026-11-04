// road_surface.gdshader
// ------------------------------------------------------------------
// The road of a track with dirt or packed snow (world/track_mesh.gd; an all-asphalt
// track keeps the StandardMaterial3D, so it looks exactly as before). Per vertex:
// COLOR.r = the asphalt's wear tint (sRGB, as on the plain road), COLOR.g / COLOR.b =
// the blend weights of surface 1 (dirt) and 2 (packed snow) from BuiltTrack.surf_w (what
// the car feels, blended over ~10 m); UV = (lateral, along) in 7 m tiles; CUSTOM0 (v6.10) =
// (lateral fraction -1..1, half width m, wide weights of surfaces 1 and 2 spread over
// about ±20 m by track_mesh.gd, for the look only).
//
// Asphalt is drawn as the StandardMaterial3D draws it (textures times tint times
// tint_scale); dirt and snow are their colour from sim/surfaces.gd times the detail of
// Tex.loose() (v6.10: two samples at different scales and angles mixed by a large noise, so
// the 7 m tile never repeats visibly, plus a slow colour drift over 50-200 m).
//   Dirt: wheel ruts along both lanes (darker, packed, fewer stones), damp patches, small
//   puddles in the ruts (dark and glossy), gravel and pebbles from the texture.
//   Snow: packed tyre tracks in the lanes (greyer, smoother), loose powder at the sides
//   (whiter, lumpy), glints that twinkle as the view moves, icy patches (glossy, blue-grey),
//   bluish shading in the hollows.
// Where the surface changes, the 50 % line follows what the car feels (the physics
// weights) and the wide weights spread the change out: big ragged patches, tongues of dirt
// or snow stretched along the road (carried by the tyres), snow drifting in from the edges
// and scattered clumps before and after. On asphalt away from any change (both wide
// weights 0) it is the plain asphalt.
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

varying vec4 road;

vec3 srgb_to_lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

float hash12(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

// How much of a surface shows here: w = its physics weight, v = its wide weight. 0 where v is 0
// (clean asphalt), 1 where both are 1; in between the 50 % line follows w + v, made ragged by
// big patches, tongues along the road and `edge` (snow drifting in from the sides), with
// clumps scattered over the whole wide zone. y: a thin film of it on the asphalt around the
// patches (dusty or frosted tarmac), so their edges thin out instead of ending like paint.
vec2 cover(float w, float v, float big, float tongue, float clump, float edge) {
	float core = mix(v, w, 0.35);
	float zone = smoothstep(0.0, 0.12, v) * (1.0 - smoothstep(0.9, 1.0, w));
	float f = core + ((big - 0.5) * 0.6 + (tongue - 0.5) * 1.4 + edge) * zone;
	float c = smoothstep(0.46, 0.54, f);
	float cl = smoothstep(0.86, 0.89, clump + v * 0.3) * zone * (1.0 - core);
	float film = smoothstep(0.2, 0.46, f) * smoothstep(0.0, 0.25, v);
	return vec2(max(c, cl), film);
}

void vertex() {
	road = CUSTOM0;
}

void fragment() {
	vec3 vc = srgb_to_lin(COLOR.rgb);
	float wear = vc.r;
	float lat = UV.x * 7.0;
	float s = UV.y * 7.0;
	float frac = road.x;
	float hw = max(road.y, 1.0);
	// --- detail: two samples, the second larger and turned, mixed by a slow noise (no tiling)
	vec2 uv_b = mat2(vec2(0.825, 0.565), vec2(-0.565, 0.825)) * UV * 0.61 + vec2(0.37, 0.71);
	vec4 da = texture(loose_map, UV);
	vec4 db = texture(loose_map, uv_b);
	float sel = smoothstep(0.3, 0.7, texture(loose_map, UV * 0.13 + vec2(0.21, 0.13)).g);
	vec4 d = mix(da, db, sel);
	float macro = texture(loose_map, UV * 0.071 + vec2(0.53, 0.29)).g;
	float macro2 = texture(loose_map, UV * 0.031 + vec2(0.11, 0.77)).a;
	float wet = texture(loose_map, vec2(lat, s) / 41.0 + vec2(0.7, 0.2)).g;
	// --- wheel ruts / packed tracks: two lanes of two tyre tracks each, wandering a little
	float lane = 0.42 * hw;
	float wob = 0.35 * sin(s * 0.045 + 1.3) + 0.22 * sin(s * 0.113 + 4.0);
	float rut = 0.0;
	float rut_d = 0.0; // the rut's slope across the road (for the normal)
	for (int k = 0; k < 4; k++) {
		float c = (k < 2 ? -lane : lane) + (k % 2 == 0 ? -0.85 : 0.85) + wob;
		float x = abs(lat - c);
		float r = 1.0 - smoothstep(0.12, 0.62, x);
		if (r > rut) {
			rut = r;
			rut_d = sign(lat - c) * (smoothstep(0.12, 0.62, x) - smoothstep(0.12, 0.62, x - 0.05)) / 0.05;
		}
	}
	float rut_k = smoothstep(0.2, 0.8, texture(loose_map, vec2(0.31 + floor(lat / hw + 2.0) * 0.17, s / 61.0)).a);
	rut *= 0.25 + 0.75 * rut_k;
	rut_d *= 0.25 + 0.75 * rut_k;
	// --- the border between surfaces
	float big = texture(loose_map, vec2(lat, s) / 23.0 + vec2(0.4, 0.8)).g;
	float tongue = texture(loose_map, vec2(lat / 8.0, s / 52.0) + vec2(0.15, 0.45)).g;
	float clump = texture(loose_map, vec2(lat, s) / 2.3 + vec2(0.6, 0.3)).a;
	float side = pow(abs(frac), 3.0);
	// (dirt is carried along the wheel tracks onto the asphalt; snow drifts in from the sides)
	vec2 c1 = cover(vc.g, road.z, big, tongue, clump, side * 0.12 + rut * 0.22);
	vec2 c2 = cover(vc.b, road.w, big, 1.0 - tongue, clump, side * 0.55 - rut * 0.08);
	float w1 = c1.x;
	float w2 = c2.x;
	float w0 = max(0.0, 1.0 - w1 - w2);
	float sum = max(w0 + w1 + w2, 1e-4);
	w0 /= sum;
	w1 /= sum;
	w2 /= sum;
	// the worn racing line shows on loose ground too, as packed lanes
	float lanes = mix(1.0, clamp(wear * 1.45, 0.75, 1.15), 0.6);
	// --- asphalt
	vec3 a0 = texture(asphalt_map, UV).rgb * tint_scale * wear;
	// dusty or frosted tarmac next to the patches (the film, broken up by the texture's grain)
	float grain = smoothstep(0.55, 0.95, d.a + d.r * 0.5);
	a0 = mix(a0, color_1 * 0.75, c1.y * 0.45 * grain);
	a0 = mix(a0, color_2 * 0.85, c2.y * 0.55 * grain);
	// --- dirt: colour drift, stones, ruts, damp patches and puddles
	vec3 dirt_col = color_1 * mix(vec3(0.86, 0.92, 1.0), vec3(1.12, 1.0, 0.82), macro) * mix(0.82, 1.12, macro2);
	float stones = mix(d.r, 0.8, rut * 0.65);
	float damp = smoothstep(0.38, 0.27, wet);
	float puddle = smoothstep(0.17, 0.15, wet) * smoothstep(0.45, 0.8, rut + damp * 0.25);
	float rim = smoothstep(0.2, 0.17, wet) * smoothstep(0.3, 0.7, rut + damp * 0.25);
	vec3 a1 = dirt_col * stones * lanes * mix(1.0, 0.86, rut) * mix(1.0, 0.7, damp) * mix(1.0, 0.7, rim);
	a1 = mix(a1, vec3(0.07, 0.055, 0.04), puddle);
	float r1 = mix(mix(rough_1, 0.7, max(damp, rim)), 0.14, puddle);
	// --- snow: packed tracks, powder at the sides, ice, glints, bluish hollows
	float sd = d.b;
	float glint = step(0.985, max(da.b, db.b));
	float powder = smoothstep(0.55, 0.92, abs(frac)) * (0.55 + 0.45 * clump);
	float ice = smoothstep(0.34, 0.27, wet) * (0.35 + 0.65 * rut) * (1.0 - powder);
	float hollow = clamp((0.95 - sd) * 9.0, 0.0, 1.0);
	vec3 snow_col = color_2 * mix(vec3(1.0), vec3(0.8, 0.88, 1.04), hollow * 0.6 + rut * 0.35);
	vec3 a2 = snow_col * mix(sd, 1.0, 0.35) * mix(1.0, lanes, 0.8) * mix(1.0, 0.9, rut * (1.0 - powder));
	a2 = mix(a2, color_2 * 1.04, powder * 0.6);
	a2 = mix(a2, vec3(0.6, 0.7, 0.8) * color_2, ice * 0.7);
	float twinkle = step(0.5, hash12(floor(UV * 512.0) + floor(VIEW.xy * 7.0) * 13.0));
	float r2 = mix(mix(mix(rough_2, 0.4, rut), 0.85, powder), 0.1, ice);
	r2 = mix(r2, 0.04, glint);
	EMISSION = vec3(0.55, 0.6, 0.7) * glint * twinkle * w2 * (1.0 - ice);
	ALBEDO = a0 * w0 + a1 * w1 + a2 * w2;
	ROUGHNESS = texture(asphalt_rough, UV).r * w0 + r1 * w1 + r2 * w2;
	// --- normals: the asphalt's; stones and grain on dirt (flat in puddles), the rut walls,
	// powder lumps on snow (flat on ice)
	vec2 n0 = (texture(asphalt_normal, UV).xy * 2.0 - 1.0) * asphalt_normal_scale;
	vec2 nl = mix(texture(loose_normal, UV).xy, texture(loose_normal, uv_b).xy, sel) * 2.0 - 1.0;
	vec2 rn = vec2(rut_d * 0.18, 0.0);
	vec2 n1 = (nl * (1.0 - rut * 0.5) * normal_1 + rn) * (1.0 - puddle);
	vec2 n2 = (nl * normal_2 * (1.0 + powder * 1.5) + rn * 0.5) * (1.0 - ice);
	vec2 nm = n0 * w0 + n1 * w1 + n2 * w2;
	NORMAL_MAP = vec3(nm * 0.5 + 0.5, 1.0);
	NORMAL_MAP_DEPTH = 1.0;
}
