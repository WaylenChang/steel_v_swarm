shader_type canvas_item;
render_mode blend_disabled;
uniform vec2 target_size;
uniform float padding;
uniform float extent;
uniform float vmin;
uniform int drop_count;
uniform vec3 drops[12];
uniform vec4 stops;
uniform vec4 colors[4];

vec4 premultiplied(vec4 value) { return vec4(value.rgb * value.a, value.a); }

void fragment() {
	vec2 point = UV * target_size - vec2(padding);
	vec4 result = vec4(0.0);
	if (all(greaterThanEqual(point, vec2(0.0))) && all(lessThanEqual(point, vec2(extent)))) {
		for (int i = drop_count - 1; i >= 0; i--) {
			float distance = length(point - vec2(extent * 0.5) - drops[i].xy * vmin) / max(drops[i].z * vmin, 0.000001);
			vec4 layer = premultiplied(colors[3]);
			for (int stop = 0; stop < 3; stop++) {
				if (distance >= stops[stop] && distance < stops[stop + 1]) {
					layer = mix(premultiplied(colors[stop]), premultiplied(colors[stop + 1]),
						(distance - stops[stop]) / (stops[stop + 1] - stops[stop]));
				}
			}
			result = layer + result * (1.0 - layer.a);
		}
	}
	COLOR = result;
}
