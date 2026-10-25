// jet.gdshader: nitro jets (carMesh.js JET_*). One MultiMesh instance per jet
// layer: the pipe end in the instance origin, the tip in basis x;
// INSTANCE_CUSTOM = (half width m, brightness, 1 for the white core layer).
// A camera-facing streak with round ends (a glowing disc seen end-on from the
// chase camera), fading towards the tip, with bands running down it; added
// to what is behind.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled;

uniform vec3 edge = vec3(0.1, 0.34, 1.7);
uniform vec3 core = vec3(1.0, 1.45, 2.3);
uniform float opacity = 1.0;
varying float v_s;
varying float v_t;
varying float v_l;
varying float v_bright;
varying float v_core;

void vertex() {
	vec4 h = VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0);
	vec4 t = VIEW_MATRIX * vec4(MODEL_MATRIX[0].xyz, 1.0);
	vec2 d = h.xy - t.xy;
	float len = length(d);
	vec2 dir = len > 1e-5 ? d / len : vec2(1.0, 0.0);
	float w = INSTANCE_CUSTOM.x;
	vec4 p = mix(t, h, VERTEX.x);
	p.xy += dir * (VERTEX.x * 2.0 - 1.0) * w + vec2(-dir.y, dir.x) * VERTEX.y * w;
	v_l = len / w;
	v_s = VERTEX.x * (v_l + 2.0) - 1.0;
	v_t = VERTEX.y;
	v_bright = INSTANCE_CUSTOM.y;
	v_core = INSTANCE_CUSTOM.z;
	VERTEX = p.xyz;
}

void fragment() {
	float dx = max(0.0, max(-v_s, v_s - v_l));
	float d = sqrt(dx * dx + v_t * v_t);                   // from the streak's centre line (half widths)
	float dh = sqrt((v_l - v_s) * (v_l - v_s) + v_t * v_t); // from the pipe
	float f = clamp(1.0 - dh / (v_l + 1.0), 0.0, 1.0);     // fades towards the tip
	float a = smoothstep(1.0, 0.0, d) * pow(f, 1.3) * v_bright * opacity;
	a *= 0.84 + 0.16 * sin(dh * 2.2 - TIME * 50.0);        // bands running down the jet
	if (a < 0.003) discard;
	vec3 col = v_core > 0.5 ? core : mix(edge, core, f * f * f * (1.0 - d));
	ALBEDO = col;
	ALPHA = a;
}
