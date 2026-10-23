shader_type canvas_item;
render_mode unshaded;

uniform vec3 fog_colour;
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	COLOR = vec4(fog_colour, texture(TEXTURE, UV).r) * tint;
}
