// screen_splat.gdshader (v6.10)
// ------------------------------------------------------------------
// One splat of world/screen_grime.gd's overlay, drawn on a quad of a MultiMeshInstance2D
// (UV 0..1, y down). The instance colour is its colour and opacity; INSTANCE_CUSTOM:
//   x  a random seed 0..1 (the shape)
//   y  the kind / 3: 0 mud, 1 snow, 2 a clod or flake flying past (the quad is stretched along
//      its motion)
//   z  mud: how far its drip has run down (0..1); snow: how far it has melted (0 a white fleck,
//      1 a clear drop of water)
// A splat is a few overlapping round blobs merged into one smooth lump (metaballs), with small
// droplets around it; everything stays inside the quad.
shader_type canvas_item;
render_mode blend_mix, unshaded;

varying vec4 info;

float h1(float n) {
	return fract(sin(n * 12.9898 + 4.1414) * 43758.5453);
}

// The lump: n blobs within `spread` of the middle, radius `rmin`..`rmin + rvar` (a field that is
// 1 on its outline and grows inward).
float lump(vec2 p, float seed, int n, float spread, float rmin, float rvar) {
	float f = 0.0;
	for (int k = 0; k < n; k++) {
		float fk = float(k) + 1.0;
		float an = h1(seed + fk * 7.13) * 6.2832;
		vec2 c = vec2(cos(an), sin(an)) * spread * sqrt(h1(seed + fk * 3.71));
		float rad = rmin + rvar * h1(seed + fk * 5.37);
		vec2 d = p - c;
		f += rad * rad / max(dot(d, d), 1e-4);
	}
	return f;
}

// Small droplets around it (0..1 cover).
float droplets(vec2 p, float seed, int n, float aa, float size) {
	float s = 0.0;
	for (int k = 0; k < n; k++) {
		float fk = float(k) + 11.0;
		float an = h1(seed + fk * 7.13) * 6.2832;
		float d = 0.56 + 0.34 * h1(seed + fk * 3.71);
		float rad = size * (0.4 + 0.6 * h1(seed + fk * 5.37));
		s = max(s, 1.0 - smoothstep(rad - aa, rad + aa, length(p - vec2(cos(an), sin(an)) * d)));
	}
	return s;
}

void vertex() {
	info = INSTANCE_CUSTOM;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float seed = info.x * 113.0 + 1.0;
	int kind = int(round(info.y * 3.0));
	float px = max(fwidth(p.x), 1e-4);
	float aa = max(px, 0.025); // a little soft: it is right on the lens
	vec4 col = COLOR;
	if (kind == 2) {
		// flying past: a soft streak
		float s = 1.0 - smoothstep(0.3, 1.0, length(p * vec2(1.0, 1.7)));
		COLOR = vec4(col.rgb, col.a * s);
	} else if (kind == 0) {
		// mud: a lump with droplets around it and maybe a drip running down
		float f = min(lump(p, seed, 7, 0.4, 0.08, 0.13), 3.0); // (capped: the field is huge at a blob's centre)
		float w = max(fwidth(f), 0.06);
		float body = smoothstep(1.0 - w, 1.0 + w, f);
		float sat = droplets(p, seed, 7, aa, 0.07);
		float dl = info.z * 0.52;
		float on = step(0.02, dl);
		float dx = (h1(seed + 9.1) - 0.5) * 0.24;
		float y0 = 0.22;
		float t = clamp((p.y - y0) / max(dl, 1e-3), 0.0, 1.0);
		float wdt = mix(0.07, 0.04, t);
		float trail = (1.0 - smoothstep(wdt - aa, wdt + aa, abs(p.x - dx))) * step(y0 - 0.15, p.y) * (1.0 - step(y0 + dl, p.y)) * on;
		float tip = (1.0 - smoothstep(0.07 - aa, 0.07 + aa, length(p - vec2(dx, y0 + dl)))) * on;
		float m = max(max(body, sat), max(trail, tip));
		// thick (darker, opaque) in the middle, thin (lighter, see-through) towards the edge with a
		// dried, darker outline; a wet glint
		float thick = smoothstep(1.1, 1.9, f);
		float outline = 1.0 - smoothstep(1.0, 1.35, f);
		vec3 c = col.rgb * mix(1.3, 0.82, thick) * mix(1.0, 0.75, outline * body);
		float alpha = m * mix(0.72, 0.97, max(thick, outline * body));
		float glint = (1.0 - smoothstep(0.0, 0.08, length(p - vec2(-0.12, -0.14)))) * body * 0.5;
		c = mix(c, vec3(0.9), glint);
		COLOR = vec4(c, col.a * alpha);
	} else {
		// snow: a soft fleck that melts into a clear drop (dark rim, bright glint)
		float melt = info.z;
		float f = min(lump(p * mix(1.0, 1.3, melt), seed, 4, mix(0.22, 0.05, melt), 0.14, 0.1), 3.0);
		float w = max(fwidth(f), mix(0.35, 0.08, melt));
		float body = smoothstep(1.0 - w, 1.0 + w, f);
		float sat = droplets(p, seed, 4, aa * 2.0, 0.08) * (1.0 - melt);
		float m = max(body, sat);
		float rim = 1.0 - smoothstep(1.1, 2.4, f);
		// lit from the top left: a blue-grey shade on the lower right and rim, so it shows on white snow
		vec3 snow_c = mix(col.rgb, col.rgb * vec3(0.62, 0.7, 0.82), clamp(smoothstep(-0.3, 0.6, dot(p, vec2(0.6, 0.8))) * 0.6 + rim * 0.35, 0.0, 1.0));
		vec3 drop_c = mix(vec3(0.8, 0.86, 0.93), vec3(0.3, 0.36, 0.44), rim * body);
		float glint = (1.0 - smoothstep(0.0, 0.07, length(p - vec2(-0.08, -0.11)))) * body;
		vec3 c = mix(snow_c, drop_c, melt);
		c = mix(c, vec3(1.0), glint * melt);
		float alpha = m * mix(0.9, 0.1 + 0.55 * rim, melt) + glint * melt * 0.6;
		COLOR = vec4(c, col.a * clamp(alpha, 0.0, 1.0));
	}
}
