shader_type canvas_item;
uniform sampler2D shadow_texture : filter_linear, repeat_disable;
uniform vec2 target_size;
uniform vec2 canvas_size;
uniform float padding;
uniform vec4 rim_color : source_color;
uniform float opacity;
void fragment() {
	float shadow = texture(shadow_texture, (UV * canvas_size + vec2(padding)) / target_size).a;
	COLOR = vec4(rim_color.rgb, rim_color.a * opacity * shadow);
}
