class_name MarineSurfaceMaterial
extends RefCounted

static var shaders: Dictionary = {}

static func create(base: StandardMaterial3D, spec: Dictionary, program: ShaderInclude, weather_field: Texture2D) -> ShaderMaterial:
	if program == null or program.resource_path.is_empty() or weather_field == null or not spec.get("marine") is Dictionary:
		push_error("Missing original marine surface shader dependencies")
		return null
	var source: Dictionary = spec.marine
	var modes := []
	var side := int(spec.get("side", 2))
	modes.append("cull_disabled" if side == 2 else "cull_front" if side == 1 else "cull_back")
	modes.append("depth_draw_always" if spec.get("depthWrite", true) else "depth_draw_never")
	if not spec.get("depthTest", true):
		modes.append("depth_test_disabled")
	var defines := "#define USE_GRADIENTMAP\n"
	for name: String in source.get("defines", []):
		if name.is_empty() or not name.is_valid_identifier():
			push_error("Invalid original marine shader define")
			return null
		defines += "#define " + name + "\n"
	if side == 2:
		defines += "#define NATIVE_MARINE_DOUBLE_SIDE\n"
	elif side == 1:
		defines += "#define NATIVE_MARINE_BACK_SIDE\n"
	var code := FileAccess.get_file_as_string("res://shaders/marine_surface.gdshader.template")
	code = code.replace("__MARINE_RENDER_MODES__", ", ".join(modes)).replace("__MARINE_DEFINES__", defines)
	code = code.replace("__MARINE_PROGRAM__", program.resource_path).replace("__MARINE_SAMPLER__", SourceTextureImages.sampler_hint(base))
	var key := code.sha256_text()
	if not shaders.has(key):
		var shader := Shader.new()
		shader.code = code
		shaders[key] = shader
	var material := ShaderMaterial.new()
	material.shader = shaders[key]
	material.render_priority = base.render_priority
	material.set_meta("source_marine", source)
	SourceCelData.retain_from(base, material)
	material.set_meta("source_marine_program", program)
	material.set_shader_parameter("uNativeBaseColor", Vector3(spec.albedo[0], spec.albedo[1], spec.albedo[2]))
	material.set_shader_parameter("uNativeOpacity", float(spec.opacity))
	var emission: Array = spec.get("emission", [0, 0, 0])
	material.set_shader_parameter("uNativeEmission", Vector3(emission[0], emission[1], emission[2]) * float(spec.get("emissionIntensity", 1)))
	material.set_shader_parameter("uNativeVertexColors", bool(spec.get("vertexColors", false)))
	material.set_shader_parameter("uNativeUseTexture", base.albedo_texture != null)
	material.set_shader_parameter("uNativeTexture", base.albedo_texture)
	material.set_shader_parameter("uCelWField", weather_field)
	var gradient := PackedByteArray(source.get("gradient", []))
	if gradient.is_empty():
		push_error("Missing original cel gradient samples")
		return null
	var cel_data := base.get_meta("source_cel_data", null) as SourceCelData
	var gradient_reference: Variant = spec.get("cel", {}).get("gradient")
	var gradient_index := int(gradient_reference) if typeof(gradient_reference) in [TYPE_INT, TYPE_FLOAT] else -1
	if cel_data == null or gradient_index < 0 or gradient_index >= cel_data.sampler_images.size():
		push_error("Missing original shared cel gradient sampler; regenerate world content")
		return null
	var gradient_image: Image = cel_data.sampler_images[gradient_index]
	var sampling := cel_data.sampling(gradient_index)
	if gradient_image == null or gradient_image.get_format() != Image.FORMAT_R8 or gradient_image.get_height() != 1 or gradient_image.get_data() != gradient:
		push_error("Original shared cel gradient does not match the marine material")
		return null
	if sampling.get("min") != "nearest" or sampling.get("mag") != "nearest" or sampling.get("mipmaps", false) or sampling.get("srgb", false) or sampling.get("wrapS") != "clamp" or sampling.get("wrapT") != "clamp":
		push_error("Original marine gradient requires its exact nearest/clamp linear sampler")
		return null
	var gradient_texture := cel_data.texture(gradient_index)
	if gradient_texture == null:
		return null
	material.set_shader_parameter("gradientMap", gradient_texture)
	return material
