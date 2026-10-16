shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform vec2 viewport_size = vec2(1.0);
uniform bool scoped = false;
uniform float radius_vmin = 0.0;
uniform float ring_width = 0.0;
uniform vec4 ring_color : source_color;
uniform float fire_opacity = 0.0;
uniform float fire_blur = 0.0;
uniform vec3 fire_stops;
uniform vec4 fire_color_0 : source_color;
uniform vec4 fire_color_1 : source_color;
uniform vec4 fire_color_2 : source_color;
uniform float weather_opacity = 0.0;
uniform vec2 weather_stops;
uniform float weather_inner_vmin = 0.0;
uniform vec4 weather_color_0 : source_color;
uniform vec4 weather_color_1 : source_color;
uniform vec4 weather_color_2 : source_color;

vec4 gradient_mix(vec4 a, vec4 b, float amount) {
	float t = clamp(amount, 0.0, 1.0);
	float alpha = mix(a.a, b.a, t);
	vec3 rgb = mix(a.rgb * a.a, b.rgb * b.a, t);
	return vec4(alpha > 0.0 ? rgb / alpha : vec3(0.0), alpha);
}

vec3 scope_color(vec3 input_color, float distance_px, float radius) {
	if (!scoped) {
		return input_color;
	}
	if (distance_px >= radius) {
		return vec3(0.0);
	}
	return distance_px >= radius - ring_width ? mix(input_color, ring_color.rgb, ring_color.a) : input_color;
}

void fragment() {
	vec2 viewport = max(viewport_size, vec2(1.0));
	float vmin = min(viewport.x, viewport.y) / 100.0;
	float distance_px = length((UV - vec2(0.5)) * viewport);
	float radius = radius_vmin * vmin;
	vec3 original = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;
	vec3 blurred = textureLod(screen_texture, SCREEN_UV, log2(1.0 + fire_blur)).rgb;
	vec3 rgb = scope_color(mix(original, blurred, fire_opacity), distance_px, radius);
	// CSS ellipse gradients use the farthest corner as the final stop.
	float ellipse = length((UV - vec2(0.5)) * sqrt(2.0));
	vec4 fire = ellipse <= fire_stops.y
		? gradient_mix(fire_color_0, fire_color_1, (ellipse - fire_stops.x) / max(0.000001, fire_stops.y - fire_stops.x))
		: gradient_mix(fire_color_1, fire_color_2, (ellipse - fire_stops.y) / max(0.000001, fire_stops.z - fire_stops.y));
	rgb = mix(rgb, fire.rgb, fire.a * fire_opacity);
	float weather_position = scoped ? distance_px / vmin : ellipse;
	float weather_middle = scoped ? weather_inner_vmin : weather_stops.x;
	float weather_end = scoped ? radius_vmin : weather_stops.y;
	vec4 weather = weather_position <= weather_middle
		? gradient_mix(weather_color_0, weather_color_1, weather_position / max(0.000001, weather_middle))
		: gradient_mix(weather_color_1, weather_color_2, (weather_position - weather_middle) / max(0.000001, weather_end - weather_middle));
	rgb = mix(rgb, weather.rgb, weather.a * weather_opacity);
	COLOR = vec4(rgb, 1.0);
}
