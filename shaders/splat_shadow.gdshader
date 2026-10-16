shader_type canvas_item;
render_mode blend_disabled;
uniform sampler2D foreground : filter_linear, repeat_disable;
uniform sampler2D shadow : filter_linear, repeat_disable;
uniform vec4 shadow_color;

void fragment() {
	vec4 front = texture(foreground, UV);
	float alpha = texture(shadow, UV).a * shadow_color.a;
	COLOR = front + vec4(shadow_color.rgb * alpha, alpha) * (1.0 - front.a);
}
