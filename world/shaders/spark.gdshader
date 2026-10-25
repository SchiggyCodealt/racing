// spark.gdshader: wall sparks (carMesh.js SPARK_*). One MultiMesh instance per
// spark: head in the instance origin, tail in basis x; INSTANCE_CUSTOM = (half
// width m, heat 0..1, brightness 0..1). A streak from tail to head turned to
// face the camera, orange cooling to red with a hot core; premultiplied, so
// the colour adds light and the alpha dims what is behind a little.
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled;

varying vec2 v_uv;
varying float v_heat;
varying float v_bright;

void vertex() {
	vec4 h = VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0);
	vec4 t = VIEW_MATRIX * vec4(MODEL_MATRIX[0].xyz, 1.0);
	vec2 d = h.xy - t.xy;
	float len = length(d);
	vec2 dir = len > 1e-5 ? d / len : vec2(1.0, 0.0);
	// half width; at least about a pixel wide in the distance, so far sparks don't shimmer
	float w = max(INSTANCE_CUSTOM.x, -h.z * 0.0012);
	vec4 p = mix(t, h, VERTEX.x);
	p.xy += dir * (VERTEX.x * 2.0 - 1.0) * w + vec2(-dir.y, dir.x) * VERTEX.y * w;
	v_uv = VERTEX.xy;
	v_heat = INSTANCE_CUSTOM.y;
	v_bright = INSTANCE_CUSTOM.z;
	VERTEX = p.xyz;
}

void fragment() {
	float across = abs(v_uv.y);
	float a = (1.0 - across * across) * mix(0.3, 1.0, v_uv.x) * v_bright;
	if (a < 0.004) discard;
	vec3 col = v_heat > 0.5 ? mix(vec3(1.0, 0.3, 0.04), vec3(1.0, 0.5, 0.1), v_heat * 2.0 - 1.0)
		: mix(vec3(0.6, 0.08, 0.02), vec3(1.0, 0.3, 0.04), v_heat * 2.0);
	col = col * (0.8 + 1.2 * v_heat) + vec3(1.0, 0.85, 0.55) * smoothstep(0.6, 0.0, across) * v_heat * 1.4;
	ALBEDO = col * a;
	ALPHA = a * 0.5;
}
