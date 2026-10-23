shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform float source_size = 0.45;
uniform float source_opacity = 0.6;
uniform vec3 source_colour = vec3(1.0);
uniform bool source_vertex_colours = true;
uniform bool source_size_attenuation = true;
uniform float source_pixel_ratio = 1.0;

void vertex() {
	POINT_SIZE = source_size * source_pixel_ratio;
	if (source_size_attenuation && PROJECTION_MATRIX[2][3] == -1.0) {
		vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
		POINT_SIZE = source_size * VIEWPORT_SIZE.y * 0.5 / -view.z;
	}
}

void fragment() {
	ALBEDO = source_colour * (source_vertex_colours ? COLOR.rgb : vec3(1.0));
	ALPHA = source_opacity;
}
