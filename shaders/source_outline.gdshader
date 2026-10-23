shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;

uniform float local_width;
uniform float minimum_width;
uniform float maximum_width;
uniform float depth_minimum;
uniform float projection_minimum;
uniform float style_scale;
uniform vec4 ink_color : source_color;
uniform float curve_knee;
uniform float curve_inverse_radius;
uniform int source_layers = 1;
uniform float source_opacity = 1.0;
varying float outline_visible;

void vertex() {
	outline_visible = (CAMERA_VISIBLE_LAYERS & uint(source_layers)) != uint(0) ? 1.0 : 0.0;
	float distance = max(depth_minimum, -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z);
	float projection = max(projection_minimum, PROJECTION_MATRIX[1][1]);
	float minimum = minimum_width * distance / projection;
	float maximum = maximum_width * distance / projection;
	vec3 expanded = VERTEX + NORMAL * (min(max(local_width, minimum), maximum) * style_scale);
	vec4 world = MODEL_MATRIX * vec4(expanded, 1.0);
	float bend = length(world.xz - CAMERA_POSITION_WORLD.xz) - curve_knee;
	if (bend > 0.0) { world.y -= bend * bend * curve_inverse_radius; }
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * world;
	if (outline_visible < 0.5) { POSITION = vec4(0.0, 0.0, 2.0, 1.0); }
}

void fragment() {
	if (outline_visible < 0.5) { discard; }
	ALBEDO = ink_color.rgb;
#ifdef SOURCE_ALPHA
	ALPHA = source_opacity;
#endif
}
