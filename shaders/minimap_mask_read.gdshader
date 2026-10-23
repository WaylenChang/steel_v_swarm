shader_type canvas_item;
render_mode unshaded;

uniform bool red_channel = true;
uniform float strength = 1.0;
uniform vec3 ink = vec3(1.0);
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 mask = texture(TEXTURE, UV);
	float coverage = red_channel ? mask.r : mask.a;
	COLOR = vec4(ink, coverage * strength) * tint;
}
