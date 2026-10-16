shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform vec3 uColor;
uniform vec3 uAccent;
uniform sampler2D uPattern : filter_linear_mipmap, repeat_disable;
uniform float uHasPattern = 0.0;
uniform float uPatternAspect = 1.0;
uniform float uPatternFlipY = 0.0;
uniform float uTime = 0.0;
uniform float uFlash = 0.0;
uniform float uPlanar = 0.0;
uniform float uHexR = 1.0;
uniform float curve_knee = 0.0;
uniform float curve_inverse_radius = 0.0;

varying vec3 vN;
varying vec3 vV;
varying vec3 vP;

void vertex() {
	vN = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
	vP = VERTEX;
	vec4 world = MODEL_MATRIX * vec4(VERTEX, 1.0);
	float curve_distance = length(world.xz - CAMERA_POSITION_WORLD.xz) - curve_knee;
	if (curve_distance > 0.0) {
		world.y -= curve_distance * curve_distance * curve_inverse_radius;
	}
	vec4 view = VIEW_MATRIX * world;
	vV = -view.xyz;
	POSITION = PROJECTION_MATRIX * view;
}

float hex_distance(vec2 point) {
	point = abs(point);
	return max(dot(point, vec2(0.8660254, 0.5)), point.x);
}

float hex_sdf(vec2 point) {
	vec2 q = abs(point);
	return max(dot(q, vec2(0.8660254, 0.5)), max(q.y, dot(q, vec2(-0.8660254, 0.5)))) - 0.8660254;
}

float hex_edge(vec2 uv) {
	vec2 period = vec2(1.0, 1.7320508);
	vec2 half_period = period * 0.5;
	vec2 a = mod(uv, period) - half_period;
	vec2 b = mod(uv - half_period, period) - half_period;
	vec2 nearest = dot(a, a) < dot(b, b) ? a : b;
	return smoothstep(0.38, 0.48, hex_distance(nearest));
}

void fragment() {
	vec3 normal = normalize(vN);
	vec3 view = normalize(vV);
	float fresnel = pow(1.0 - abs(dot(normal, view)), 2.2);
	vec2 uv = mix(vec2(atan(vP.z, vP.x) * 3.2, vP.y * 0.55 - uTime * 0.35) * 3.0,
		vec2(vP.x, vP.y - uTime * 0.35) * 3.0, uPlanar);
	float edge = hex_edge(uv);
	float rim_width = 0.10 + uFlash * 0.30;
	float rim = uPlanar * smoothstep(-rim_width, -0.012, hex_sdf(vP.xy / uHexR));
	float rim_glow = rim * (0.55 + uFlash * 1.6);
	float ripple = uFlash * (1.0 - smoothstep(0.0, 0.25, abs(fract(vP.y * 0.04 + uTime * 1.6) - 0.5) - 0.2));
	float glow = edge * (0.25 + uFlash * 1.4) + fresnel * 0.55 + ripple + rim_glow;
	float alpha = 0.05 + edge * 0.08 + fresnel * 0.22 + uFlash * (0.30 + edge * 0.45) + rim * (0.10 + uFlash * 0.35);
	float glyph = 0.0;
	if (uHasPattern > 0.5) {
		vec2 motif_uv = vec2(vP.x, vP.y * uPatternAspect) / (2.0 * uHexR) + 0.5;
		motif_uv.y = mix(motif_uv.y, 1.0 - motif_uv.y, uPatternFlipY);
		glyph = texture(uPattern, motif_uv).a;
	}
	ALBEDO = uColor * (0.6 + glow * 1.8) + uAccent * glyph * (0.8 + uFlash);
	ALPHA = alpha + glyph * 0.3;
}
