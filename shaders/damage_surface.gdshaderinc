uniform sampler2D colour_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 tint = vec3(1.0);
uniform float opacity = 1.0;
uniform bool textured = false;
uniform float curve_knee = 0.0;
uniform float curve_inverse_radius = 0.0;
uniform float depth_factor = 0.0;
uniform float depth_units = 0.0;
uniform float depth_unit = 0.0;

void vertex() {
	vec4 world = MODEL_MATRIX * vec4(VERTEX, 1.0);
	float distance_to_curve = max(0.0, length(world.xz - CAMERA_POSITION_WORLD.xz) - curve_knee);
	world.y -= distance_to_curve * distance_to_curve * curve_inverse_radius;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * world;
}

void fragment() {
	vec4 pixel = textured ? texture(colour_texture, UV) : vec4(1.0);
	ALBEDO = pixel.rgb * tint;
	ALPHA = pixel.a * opacity;
	float slope = max(abs(dFdx(FRAGCOORD.z)), abs(dFdy(FRAGCOORD.z)));
	float offset = depth_factor * slope + depth_units * depth_unit;
	// Projection sign also covers compatibility's forward/reverse-Z variants.
	DEPTH = clamp(FRAGCOORD.z + (PROJECTION_MATRIX[2][2] > 0.0 ? -offset : offset), 0.0, 1.0);
}
