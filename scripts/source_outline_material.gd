class_name SourceOutlineMaterial
extends RefCounted

static var fade_shader: Shader

static func create(uniforms: Dictionary, rules: Dictionary, curve: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/source_outline.gdshader")
	material.resource_local_to_scene = true
	material.set_meta("source_outline", true)
	material.set_meta("source_transparent", false)
	material.set_meta("source_opacity", 1.0)
	material.set_shader_parameter("local_width", uniforms.width)
	material.set_shader_parameter("minimum_width", uniforms.minimum)
	material.set_shader_parameter("maximum_width", uniforms.maximum)
	material.set_shader_parameter("depth_minimum", rules.depthMinimum)
	material.set_shader_parameter("projection_minimum", rules.projectionMinimum)
	material.set_shader_parameter("curve_knee", curve.knee)
	material.set_shader_parameter("curve_inverse_radius", curve.inverse)
	return material

static func faded(base: ShaderMaterial) -> ShaderMaterial:
	if fade_shader == null:
		fade_shader = Shader.new()
		fade_shader.code = base.shader.code.replace("shader_type spatial;", "shader_type spatial;\n#define SOURCE_ALPHA")
	var material := base.duplicate() as ShaderMaterial
	material.shader = fade_shader
	material.set_meta("source_transparent", true)
	return material

static func sync_visuals(material: ShaderMaterial, preferences: VisualPreferences, rules: Dictionary) -> void:
	var surface: Dictionary = preferences.selected_preset().surface
	var index := int(rules.renderStyles.get(preferences.value("renderStyle"), 0))
	material.set_shader_parameter("style_scale", float(rules.styleScales[index]) * float(surface.outline))
	material.set_shader_parameter("ink_color", Color.hex((int(surface.outlineColor) << 8) | 0xff))
