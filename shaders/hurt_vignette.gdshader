shader_type canvas_item;
uniform float inner;
uniform float opacity = 0.0;
uniform vec4 hurt_color;

void fragment() {
	float radius = length((UV - vec2(0.5)) * sqrt(2.0));
	float edge = clamp((radius - inner) / (1.0 - inner), 0.0, 1.0);
	COLOR = vec4(hurt_color.rgb, hurt_color.a * edge * opacity);
}
