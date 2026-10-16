shader_type canvas_item;
render_mode blend_disabled;
uniform vec2 target_size;
uniform vec2 canvas_size;
uniform float padding;
uniform float spread;
void fragment() {
	vec2 point = UV * target_size - vec2(padding);
	bool hole = all(greaterThanEqual(point, vec2(spread))) && all(lessThanEqual(point, canvas_size - vec2(spread)));
	COLOR = hole ? vec4(0.0) : vec4(1.0);
}
