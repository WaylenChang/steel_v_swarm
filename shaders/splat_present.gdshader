shader_type canvas_item;
render_mode blend_premul_alpha;
uniform float opacity = 0.0;
void fragment() { COLOR = texture(TEXTURE, UV) * opacity; }
