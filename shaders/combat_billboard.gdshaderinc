uniform sampler2D spark_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 tint;
uniform float opacity = 1.0;
uniform float roll = 0.0;
uniform float curve_knee = 0.0;
uniform float curve_inverse_radius = 0.0;

void vertex() {
	vec4 world = MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float curve_distance = max(0.0, length(world.xz - CAMERA_POSITION_WORLD.xz) - curve_knee);
	world.y -= curve_distance * curve_distance * curve_inverse_radius;
	vec4 view = VIEW_MATRIX * world;
	vec2 size = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
	vec2 point = VERTEX.xy * size;
	view.xy += mat2(vec2(cos(roll), sin(roll)), vec2(-sin(roll), cos(roll))) * point;
	POSITION = PROJECTION_MATRIX * view;
}

void fragment() {
	vec4 pixel = texture(spark_texture, UV);
	ALBEDO = pixel.rgb * tint;
	ALPHA = pixel.a * opacity;
}
