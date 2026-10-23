shader_type canvas_item;
render_mode unshaded;

uniform float soft_start;
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	float radius = length((UV - vec2(0.5)) * 2.0);
	float coverage = clamp((1.0 - radius) / (1.0 - soft_start), 0.0, 1.0);
	COLOR = vec4(vec3(1.0), coverage) * tint;
}
