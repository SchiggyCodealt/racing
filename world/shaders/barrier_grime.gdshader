// barrier_grime.gdshader (v6.10)
// ------------------------------------------------------------------
// The concrete barriers of a track with dirt or snow (world/track_mesh.gd; an all-asphalt
// track keeps the plain vertex-coloured StandardMaterial3D). Drawn as that material draws
// them (the vertex colour, sRGB, times the grey detail texture, roughness 0.82) where the road
// beside them is asphalt; COLOR.a carries what the road beside them throws at them:
// 0.5 nothing, 1 dirt, 0 snow (track_mesh.gd's wide weights, so it fades in and out over
// about ±20 m). UV = (along, height) in 3 m units.
//   Dirt: dust darkening the lower half, a wavy band of wet mud at the foot, drops of mud
//   flung up the face (many low, a few higher up) and grime streaks running down from the top.
//   Snow: a crust of snow on the top faces, snow piled at the foot, rime and flecks of snow
//   low on the faces, and a glossy glaze of ice in places.
shader_type spatial;
render_mode cull_back;

uniform sampler2D detail : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float roughness = 0.82;
uniform vec3 mud : source_color = vec3(0.3, 0.22, 0.15);
uniform vec3 snow : source_color = vec3(0.93, 0.95, 0.98);

varying vec3 wn;

vec3 srgb_to_lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

float hash12(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

// Round drops on a grid of `size` m cells (p = along, up in m): a cell holds one drop when its
// hash is below the density, which goes from `lo` (high up) to `hi` (at the foot). Far away,
// where a cell gets smaller than a pixel or two, it fades to its average cover (no shimmer).
float drops(vec2 p, float size, float lo, float hi) {
	vec2 q = p / size;
	vec2 c = floor(q);
	vec2 f = q - c;
	float dens = mix(lo, hi, 1.0 - smoothstep(0.05, 0.9, (c.y + 0.5) * size));
	vec2 o = vec2(hash12(c + 17.3), hash12(c + 41.7)) * 0.5 + 0.25;
	float r = 0.07 + 0.18 * hash12(c + 7.1);
	float d = length((f - o) * vec2(1.0, 0.75));
	float px = length(fwidth(q));
	float drop = step(hash12(c), dens) * (1.0 - smoothstep(r - max(r * 0.2, px), r, d));
	return mix(drop, dens * 0.12, smoothstep(0.12, 0.45, px));
}

void vertex() {
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 base = srgb_to_lin(COLOR.rgb) * texture(detail, UV).rgb;
	float dirt = clamp(COLOR.a * 2.0 - 1.0, 0.0, 1.0);
	float ice_w = clamp(1.0 - COLOR.a * 2.0, 0.0, 1.0);
	float u = UV.x * 3.0; // m along
	float y = UV.y * 3.0; // m up
	float face = step(wn.y, 0.5); // a side face (not the top)
	vec3 alb = base;
	float rough = roughness;
	if (dirt > 0.001) {
		vec4 n1 = texture(noise, vec2(u / 9.0, 0.37));
		vec4 n3 = texture(noise, vec2(u * 0.9, y * 0.12));
		vec4 n5 = texture(noise, vec2(u, y) / 2.7);
		// dust darkening the lower half, unevenly
		float low = 1.0 - smoothstep(0.0, 0.85, y + (n5.g - 0.5) * 0.5);
		alb *= mix(vec3(1.0), vec3(0.66, 0.53, 0.4), low * dirt * face);
		// grime streaks running down from the top, fading out lower down
		float streak = smoothstep(0.5, 0.8, n3.a) * (0.25 + 0.75 * smoothstep(0.2, 1.0, y)) * 0.4;
		alb *= mix(vec3(1.0), vec3(0.8, 0.74, 0.66), streak * dirt);
		// smears of dried mud low on the face, ragged on top
		vec4 n6 = texture(noise, vec2(u * 1.7, y * 1.1));
		float smear = smoothstep(0.45, 0.6, n6.a * 0.6 + n5.a * 0.4 + low * 0.45 - 0.2) * low * dirt * face;
		alb = mix(alb, mud * 1.25, smear * 0.6);
		// drops of mud: small ones dense low and a few higher, bigger ones only low
		vec2 p = vec2(u, y);
		float spray = max(drops(p, 0.07, 0.08, 0.85), drops(p + 0.31, 0.15, 0.01, 0.55)) * dirt * face;
		alb = mix(alb, mud * (0.85 + 0.3 * n5.r), spray * 0.85);
		rough = mix(rough, 0.7, spray);
		// wet mud at the foot, along a wavy line
		float foot = 0.1 + 0.22 * n1.a * dirt;
		float band = (1.0 - smoothstep(foot - 0.03, foot + 0.03, y)) * dirt * face;
		alb = mix(alb, mud * 0.55, band);
		rough = mix(rough, 0.5, band);
	}
	if (ice_w > 0.001) {
		vec4 n1 = texture(noise, vec2(u / 7.0, 0.61));
		vec4 n2 = texture(noise, vec2(u, y) / 3.1);
		vec4 n4 = texture(noise, vec2(u, y) / 0.9);
		float low = 1.0 - smoothstep(0.05, 0.8, y + (n2.a - 0.5) * 0.4);
		// rime: the faces greyed white, most low down, with a fine grain
		alb = mix(alb, snow * 0.85, (0.12 + 0.3 * low) * (0.6 + 0.4 * n4.a) * ice_w * face);
		// flecks of snow thrown up by the cars
		vec2 p = vec2(u, y);
		float fl = drops(p + 0.17, 0.07, 0.03, 0.45) * ice_w * face;
		alb = mix(alb, snow, fl * 0.8);
		// a glaze of ice in places: glossy and a little blue, the colour mostly kept
		float ice = smoothstep(0.5, 0.62, n2.g) * face * ice_w;
		alb = mix(alb, alb * vec3(0.82, 0.9, 1.02) + vec3(0.03, 0.05, 0.08), ice * 0.7);
		rough = mix(rough, 0.15, ice);
		// a crust of snow on the top faces and snow piled at the foot
		float crust = smoothstep(0.35, 0.6, wn.y + (n2.a - 0.5) * 0.5) * ice_w;
		float pile = (1.0 - smoothstep(0.07 + 0.25 * n1.g, 0.13 + 0.25 * n1.g, y)) * ice_w;
		float sn = max(crust, pile);
		alb = mix(alb, snow * (0.9 + 0.1 * n4.r), sn);
		rough = mix(rough, 0.85, sn);
	}
	ALBEDO = alb;
	ROUGHNESS = rough;
}
