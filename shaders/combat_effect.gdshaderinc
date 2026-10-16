uniform vec3 tint = vec3(1.0);
uniform float opacity = 1.0;
uniform float curve_knee = 0.0;
uniform float curve_inverse_radius = 0.0;
uniform bool sweep = false;
uniform float sweep_time = 0.0;
uniform float sweep_bins = 1.0;
varying float fan_weight;

void vertex() {
	fan_weight = sweep ? max(0.06, 1.0 - abs(sweep_time - UV.x / sweep_bins * 0.55 - 0.12) / 0.22) : 1.0;
	vec4 world = MODEL_MATRIX * vec4(VERTEX, 1.0);
	float curve_distance = max(0.0, length(world.xz - CAMERA_POSITION_WORLD.xz) - curve_knee);
	world.y -= curve_distance * curve_distance * curve_inverse_radius;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * world;
}

void fragment() {
	ALBEDO = tint * COLOR.rgb * fan_weight;
	ALPHA = opacity * COLOR.a;
}
