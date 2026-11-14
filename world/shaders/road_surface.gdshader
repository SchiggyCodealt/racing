// road_surface.gdshader
// ------------------------------------------------------------------
// The road of a track that is not all asphalt (world/track_mesh.gd; an all-asphalt track keeps
// the StandardMaterial3D, so it looks exactly as before). The road carries two surfaces besides
// asphalt, the track's two "slots" (sim/surfaces.gd slots(): dirt and packed snow on the older
// tracks; v6.23: any two of dirt, snow, gravel, sand, ice and mud). Per vertex:
// COLOR.r = the asphalt's wear tint (sRGB, as on the plain road), COLOR.g / COLOR.b =
// the blend weights of slots 1 and 2 from BuiltTrack.surf_w (what the car feels, blended over
// ~10 m); UV = (lateral, along) in 7 m tiles; CUSTOM0 (v6.10) = (lateral fraction -1..1, half
// width m, wide weights of slots 1 and 2 spread over about ±20 m by track_mesh.gd, for the look
// only).
//
// Asphalt is drawn as the StandardMaterial3D draws it (textures times tint times tint_scale).
// A slot is its surface's colour from sim/surfaces.gd times its detail texture (tex_n / texn_n
// from Tex.surface(): two samples at different scales and angles mixed by a large noise, so the
// 7 m tile never repeats visibly, plus a slow colour drift over 50-200 m), drawn by one of three
// looks (kind_n) with four numbers each (style_n):
//   0 earth (dirt, gravel, sand, mud): wheel ruts along both lanes (darker, packed, fewer
//     stones), damp patches and small puddles in the ruts (dark and glossy), stones from the
//     texture. style = (wetness: 1 dirt, 0 none, over 1 more and bigger puddles; ruts: how dark
//     and deep; tint: how far the texture's G varies the colour between warm and cool, stone by
//     stone; sheen: wet gloss where the texture's B is high).
//   1 snow (packed snow): packed tyre tracks in the lanes (greyer, smoother), loose powder at the
//     sides (whiter, lumpy), glints that twinkle as the view moves, icy patches (glossy,
//     blue-grey), bluish shading in the hollows. Detail in the texture's B.
//   2 ice (a frozen lake): clear, glossy blue ice with dark deep patches, white cracks (the
//     texture's G) and bubbles, snow blown over it in patches (B) and banked at the sides, the
//     lanes scuffed white and dull by studded tyres.
// Where the surface changes, the 50 % line follows what the car feels (the physics
// weights) and the wide weights spread the change out: big ragged patches, tongues of dirt
// or snow stretched along the road (carried by the tyres), snow drifting in from the edges
// and scattered clumps before and after. On asphalt away from any change (both wide
// weights 0) it is the plain asphalt; where two slots meet without asphalt between them
// (v6.23) no asphalt shows through.
shader_type spatial;
render_mode cull_back;

uniform sampler2D asphalt_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_rough : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// shared noise (Tex.loose().map: G large patches, A medium clumps, R and B grain for the film)
uniform sampler2D loose_map : filter_linear_mipmap_anisotropic, repeat_enable;
// the slots' detail textures and their normals (Tex.surface())
uniform sampler2D tex_1 : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D texn_1 : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_2 : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D texn_2 : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// the asphalt material's linear albedo multiplier (track_mesh.gd K) and normal strength
uniform float tint_scale = 1.13;
uniform float asphalt_normal_scale = 0.55;
// slots 1 and 2: colour, roughness, normal strength, look (0 earth, 1 snow, 2 ice) and its style
uniform vec3 color_1 : source_color = vec3(0.541, 0.416, 0.282);
uniform vec3 color_2 : source_color = vec3(0.91, 0.933, 0.957);
uniform float rough_1 = 0.95;
uniform float rough_2 = 0.6;
uniform float normal_1 = 0.9;
uniform float normal_2 = 0.25;
uniform float kind_1 = 0.0;
uniform float kind_2 = 1.0;
uniform vec4 style_1 = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 style_2 = vec4(0.0);

varying vec4 road;

// what every look needs to know about this spot of road
struct Spot {
	float rut; // 0..1 in a wheel track
	float rut_d; // the rut's slope across the road (for the normal)
	float wet; // large noise: low = damp, puddles, ice
	float macro; // slow colour drift
	float macro2;
	float clump; // medium noise
	float frac; // -1..1 across the road
	float lanes; // the worn racing line as packed lanes
	float twinkle; // 0 / 1, changes as the view moves
};

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

// One slot's look: albedo, roughness, the normal's xy and what it emits (snow glints).
// d: its detail texture (mixed samples), da / db: the two samples, nl: its normal's xy (-1..1).
void look(float kind, vec3 color, float rough, float nscale, vec4 st, vec4 d, vec4 da, vec4 db, vec2 nl, Spot p,
		out vec3 alb, out float rgh, out vec2 nrm, out vec3 emi) {
	vec2 rn = vec2(p.rut_d * 0.18, 0.0);
	emi = vec3(0.0);
	if (kind < 0.5) {
		// --- earth: colour drift, stones, ruts, damp patches and puddles
		float wm = clamp(st.x * 3.0, 0.0, 1.0);
		float wet = p.wet - (st.x - 1.0) * 0.1;
		vec3 col = color * mix(vec3(0.86, 0.92, 1.0), vec3(1.12, 1.0, 0.82), p.macro) * mix(0.82, 1.12, p.macro2);
		col *= mix(vec3(1.0), mix(vec3(0.84, 0.95, 1.1), vec3(1.14, 1.02, 0.84), d.g), st.z);
		float stones = mix(d.r, 0.8, p.rut * 0.65);
		float damp = smoothstep(0.38, 0.27, wet) * wm;
		float puddle = smoothstep(0.17, 0.15, wet) * smoothstep(0.45, 0.8, p.rut + damp * 0.25) * wm;
		float rim = smoothstep(0.2, 0.17, wet) * smoothstep(0.3, 0.7, p.rut + damp * 0.25) * wm;
		alb = col * stones * p.lanes * mix(1.0, 0.86, p.rut * st.y) * mix(1.0, 0.7, damp) * mix(1.0, 0.7, rim);
		alb = mix(alb, vec3(0.07, 0.055, 0.04), puddle);
		float sheen = smoothstep(0.35, 0.8, d.b) * st.w;
		rgh = mix(mix(mix(rough, 0.7, max(damp, rim)), 0.22, sheen), 0.14, puddle);
		nrm = (nl * (1.0 - p.rut * 0.5) * nscale + rn * st.y) * (1.0 - puddle);
	} else if (kind < 1.5) {
		// --- snow: packed tracks, powder at the sides, ice, glints, bluish hollows
		float sd = d.b;
		float glint = step(0.985, max(da.b, db.b));
		float powder = smoothstep(0.55, 0.92, abs(p.frac)) * (0.55 + 0.45 * p.clump);
		float ice = smoothstep(0.34, 0.27, p.wet) * (0.35 + 0.65 * p.rut) * (1.0 - powder);
		float hollow = clamp((0.95 - sd) * 9.0, 0.0, 1.0);
		vec3 snow_col = color * mix(vec3(1.0), vec3(0.8, 0.88, 1.04), hollow * 0.6 + p.rut * 0.35);
		alb = snow_col * mix(sd, 1.0, 0.35) * mix(1.0, p.lanes, 0.8) * mix(1.0, 0.9, p.rut * (1.0 - powder));
		alb = mix(alb, color * 1.04, powder * 0.6);
		alb = mix(alb, vec3(0.6, 0.7, 0.8) * color, ice * 0.7);
		rgh = mix(mix(mix(rough, 0.4, p.rut), 0.85, powder), 0.1, ice);
		rgh = mix(rgh, 0.04, glint);
		emi = vec3(0.55, 0.6, 0.7) * glint * p.twinkle * (1.0 - ice);
		nrm = (nl * nscale * (1.0 + powder * 1.5) + rn * 0.5) * (1.0 - ice);
	} else {
		// --- ice: clear glossy ice, deep dark patches, white cracks and bubbles, blown snow, scuffed lanes
		float deep = smoothstep(0.55, 0.3, p.wet + (p.macro - 0.5) * 0.3);
		float crack = max(da.g, db.g);
		float bank = smoothstep(0.62, 0.95, abs(p.frac)) * (0.6 + 0.4 * p.clump);
		float blown = smoothstep(0.5, 0.72, d.b * 0.75 + p.macro2 * 0.45 + (p.clump - 0.5) * 0.25) * (1.0 - p.rut * 0.75);
		float snow = max(bank, blown * 0.85);
		float scuff = p.rut * (0.45 + 0.4 * p.clump) * (1.0 - snow);
		vec3 base = color * mix(0.7, 1.12, d.r) * mix(vec3(1.0), vec3(0.42, 0.6, 0.78), deep * 0.75);
		alb = mix(base, vec3(0.9, 0.95, 1.0), crack * (0.75 - 0.3 * deep));
		alb = mix(alb, vec3(0.78, 0.86, 0.93), scuff);
		alb = mix(alb, vec3(0.92, 0.95, 0.98) * mix(0.9, 1.0, d.a), snow);
		float glint = step(0.8, d.a) * step(0.5, snow);
		rgh = mix(mix(mix(rough, 0.07, deep), 0.5, scuff), 0.85, snow);
		rgh = mix(rgh, 0.3, crack * (1.0 - snow));
		emi = vec3(0.5, 0.55, 0.65) * glint * p.twinkle * 0.6;
		nrm = nl * nscale * (0.5 + 2.0 * snow) * (1.0 - deep * 0.5) + rn * 0.25 * scuff;
	}
}

void vertex() {
	road = CUSTOM0;
}

void fragment() {
	vec3 vc = srgb_to_lin(COLOR.rgb);
	float wear = vc.r;
	float lat = UV.x * 7.0;
	float s = UV.y * 7.0;
	Spot p;
	p.frac = road.x;
	float hw = max(road.y, 1.0);
	// --- detail: two samples, the second larger and turned, mixed by a slow noise (no tiling)
	vec2 uv_b = mat2(vec2(0.825, 0.565), vec2(-0.565, 0.825)) * UV * 0.61 + vec2(0.37, 0.71);
	vec4 da = texture(loose_map, UV);
	vec4 db = texture(loose_map, uv_b);
	float sel = smoothstep(0.3, 0.7, texture(loose_map, UV * 0.13 + vec2(0.21, 0.13)).g);
	vec4 d = mix(da, db, sel);
	p.macro = texture(loose_map, UV * 0.071 + vec2(0.53, 0.29)).g;
	p.macro2 = texture(loose_map, UV * 0.031 + vec2(0.11, 0.77)).a;
	p.wet = texture(loose_map, vec2(lat, s) / 41.0 + vec2(0.7, 0.2)).g;
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
	p.rut = rut;
	p.rut_d = rut_d;
	// --- the border between surfaces
	float big = texture(loose_map, vec2(lat, s) / 23.0 + vec2(0.4, 0.8)).g;
	float tongue = texture(loose_map, vec2(lat / 8.0, s / 52.0) + vec2(0.15, 0.45)).g;
	p.clump = texture(loose_map, vec2(lat, s) / 2.3 + vec2(0.6, 0.3)).a;
	float side = pow(abs(p.frac), 3.0);
	// (earth is carried along the wheel tracks onto the asphalt; snow and ice drift in from the sides)
	float e1 = kind_1 < 0.5 ? side * 0.12 + rut * 0.22 : side * 0.55 - rut * 0.08;
	float e2 = kind_2 < 0.5 ? side * 0.12 + rut * 0.22 : side * 0.55 - rut * 0.08;
	vec2 c1 = cover(vc.g, road.z, big, tongue, p.clump, e1);
	vec2 c2 = cover(vc.b, road.w, big, 1.0 - tongue, p.clump, e2);
	float w1 = c1.x;
	float w2 = c2.x;
	// (v6.23) where the two slots meet with no asphalt near, what neither covers is theirs, not asphalt's
	float no_asphalt = 1.0 - smoothstep(0.0, 0.08, clamp(1.0 - road.z - road.w, 0.0, 1.0));
	float gap = max(0.0, 1.0 - w1 - w2) * no_asphalt;
	float share = vc.g / max(vc.g + vc.b, 1e-4);
	w1 += gap * share;
	w2 += gap * (1.0 - share);
	float w0 = max(0.0, 1.0 - w1 - w2);
	float sum = max(w0 + w1 + w2, 1e-4);
	w0 /= sum;
	w1 /= sum;
	w2 /= sum;
	// the worn racing line shows on loose ground too, as packed lanes
	p.lanes = mix(1.0, clamp(wear * 1.45, 0.75, 1.15), 0.6);
	p.twinkle = step(0.5, hash12(floor(UV * 512.0) + floor(VIEW.xy * 7.0) * 13.0));
	// --- asphalt
	vec3 a0 = texture(asphalt_map, UV).rgb * tint_scale * wear;
	// dusty or frosted tarmac next to the patches (the film, broken up by the texture's grain)
	float grain = smoothstep(0.55, 0.95, d.a + d.r * 0.5);
	a0 = mix(a0, color_1 * (kind_1 < 0.5 ? 0.75 : 0.85), c1.y * (kind_1 < 0.5 ? 0.45 : 0.55) * grain);
	a0 = mix(a0, color_2 * (kind_2 < 0.5 ? 0.75 : 0.85), c2.y * (kind_2 < 0.5 ? 0.45 : 0.55) * grain);
	// --- the two slots
	vec4 ta = texture(tex_1, UV);
	vec4 tb = texture(tex_1, uv_b);
	vec2 nl = mix(texture(texn_1, UV).xy, texture(texn_1, uv_b).xy, sel) * 2.0 - 1.0;
	vec3 a1;
	float r1;
	vec2 n1;
	vec3 e_1;
	look(kind_1, color_1, rough_1, normal_1, style_1, mix(ta, tb, sel), ta, tb, nl, p, a1, r1, n1, e_1);
	ta = texture(tex_2, UV);
	tb = texture(tex_2, uv_b);
	nl = mix(texture(texn_2, UV).xy, texture(texn_2, uv_b).xy, sel) * 2.0 - 1.0;
	vec3 a2;
	float r2;
	vec2 n2;
	vec3 e_2;
	look(kind_2, color_2, rough_2, normal_2, style_2, mix(ta, tb, sel), ta, tb, nl, p, a2, r2, n2, e_2);
	EMISSION = e_1 * w1 + e_2 * w2;
	ALBEDO = a0 * w0 + a1 * w1 + a2 * w2;
	ROUGHNESS = texture(asphalt_rough, UV).r * w0 + r1 * w1 + r2 * w2;
	// --- normals: the asphalt's and the slots' (stones and grain, rut walls, powder lumps; flat in
	// puddles and on clear ice)
	vec2 n0 = (texture(asphalt_normal, UV).xy * 2.0 - 1.0) * asphalt_normal_scale;
	vec2 nm = n0 * w0 + n1 * w1 + n2 * w2;
	NORMAL_MAP = vec3(nm * 0.5 + 0.5, 1.0);
	NORMAL_MAP_DEPTH = 1.0;
}
