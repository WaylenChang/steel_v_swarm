shader_type canvas_item;
render_mode blend_disabled;
uniform sampler2D input_texture : filter_linear, repeat_disable;
uniform vec2 target_size;
uniform vec2 direction;
uniform float sigma;

void fragment() {
	vec4 total = vec4(0.0);
	float weight = 0.0;
	int radius = int(ceil(sigma * 3.0));
	for (int i = -radius; i <= radius; i++) {
		float sample_weight = sigma > 0.0 ? exp(-float(i * i) / (2.0 * sigma * sigma)) : 1.0;
		vec2 point = UV + direction * float(i) / target_size;
		if (all(greaterThanEqual(point, vec2(0.0))) && all(lessThanEqual(point, vec2(1.0)))) {
			total += texture(input_texture, point) * sample_weight;
		}
		weight += sample_weight;
	}
	COLOR = total / weight;
}
