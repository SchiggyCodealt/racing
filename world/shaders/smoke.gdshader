// smoke.gdshader: tyre smoke puffs (carMesh.js TyreSmoke). One MultiMesh
// instance per puff: centre in the instance origin, INSTANCE_CUSTOM.x = size
// (m), .y = alpha. Camera-facing soft discs, lit (dark at night, unlike the
// web game's unlit puffs), with the normal tilted up so they read as volume.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform, specular_disabled, diffuse_lambert_wrap;

uniform vec3 color : source_color = vec3(0.851, 0.855, 0.863);
varying vec2 v_uv;
varying float v_alpha;

void vertex() {
	v_uv = VERTEX.xy;
	v_alpha = INSTANCE_CUSTOM.y;
	vec4 mv = VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0);
	mv.xy += VERTEX.xy * INSTANCE_CUSTOM.x;
	VERTEX = mv.xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz + vec3(0.0, 0.0, 1.0));
}

void fragment() {
	float d = length(v_uv) * 2.0;
	float a = smoothstep(1.0, 0.15, d) * v_alpha;
	if (a < 0.004) discard;
	ALBEDO = color;
	ALPHA = a;
}
