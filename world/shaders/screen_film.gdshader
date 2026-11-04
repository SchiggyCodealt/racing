// screen_film.gdshader (v6.10)
// ------------------------------------------------------------------
// The full-screen part of world/screen_grime.gd's overlay (a ColorRect, UV 0..1 over the
// screen): a dirty film of dried mud and specks creeping in from the corners and the bottom
// (`mud` 0..1), and frost with grains of crystals growing in from the corners (`frost` 0..1).
// Both stay outside the keep-out ellipse `keep` (centre and radii in screen fractions): at full
// strength they reach no closer to the middle than its edge, and only in a few ragged fingers.
shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform float mud = 0.0;
uniform float frost = 0.0;
uniform vec3 mud_color : source_color = vec3(0.3, 0.22, 0.15);
uniform vec3 frost_color : source_color = vec3(0.84, 0.9, 0.98);
uniform vec4 keep = vec4(0.5, 0.5, 0.34, 0.31);
uniform float aspect = 1.7778;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;

void fragment() {
	vec2 uv = UV;
	float e = length((uv - keep.xy) / keep.zw); // 1 on the keep-out ellipse, about 2.2 in the corners
	vec2 nuv = uv * vec2(aspect, 1.0);
	vec4 n1 = texture(noise, nuv * 0.45 + vec2(0.13, 0.57));
	vec4 n2 = texture(noise, nuv * 1.6 + vec2(0.31, 0.62));
	vec4 n3 = texture(noise, nuv * 4.3 + vec2(0.71, 0.09));
	vec4 dst = vec4(0.0);
	if (mud > 0.002) {
		// the film: in from the corners and the bottom edge, ragged
		float t = mix(2.5, 1.6, mud);
		float f = e + (n1.a - 0.5) * 0.5 + (uv.y - 0.5) * 0.45;
		float m = smoothstep(t, t + 0.4, f);
		// specks of dried mud on it and a little ahead of it
		float speck = smoothstep(0.8, 0.86, n3.a * 0.7 + n2.g * 0.45) * smoothstep(t - 0.1, t + 0.15, f);
		float alpha = clamp(m * (0.42 + 0.3 * n2.a) + speck * 0.75, 0.0, 0.9);
		dst = vec4(mud_color * (0.8 + 0.45 * n2.r), alpha);
	}
	if (frost > 0.002) {
		float t = mix(2.1, 1.3, frost);
		float f = e + (n1.g - 0.5) * 0.4 + (n3.a - 0.5) * 0.12;
		float m = smoothstep(t, t + 0.35, f);
		// a blue-grey haze with grains of white crystals, thicker towards the corners
		float grain = smoothstep(0.55, 0.78, n3.a * 0.55 + n2.g * 0.25 + n3.r * 0.3);
		float alpha = m * (0.5 + 0.4 * grain) * (0.75 + 0.25 * smoothstep(t + 0.2, t + 0.9, f));
		alpha = clamp(alpha * (0.75 + 0.25 * frost), 0.0, 0.88);
		vec3 c = mix(frost_color, vec3(1.0), grain * 0.8);
		// over the mud
		float oa = alpha + dst.a * (1.0 - alpha);
		dst = vec4((c * alpha + dst.rgb * dst.a * (1.0 - alpha)) / max(oa, 1e-4), oa);
	}
	COLOR = dst;
}
