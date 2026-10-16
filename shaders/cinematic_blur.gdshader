shader_type canvas_item;

uniform float brightness = 1.0;
uniform float saturation = 1.0;
uniform float mip_level = 0.0;

void fragment() {
	vec4 sample_color = textureLod(TEXTURE, UV, mip_level);
	float luminance = dot(sample_color.rgb, vec3(0.2126, 0.7152, 0.0722));
	sample_color.rgb = mix(vec3(luminance), sample_color.rgb, saturation) * brightness;
	COLOR = sample_color * COLOR;
}
