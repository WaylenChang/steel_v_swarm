class_name ShieldPresentation
extends RefCounted

static func material(spec: Dictionary, textures: Array[ImageTexture], curve: Dictionary) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = preload("res://shaders/reference_shield.gdshader")
	result.set_meta("source_transparent", true)
	result.set_meta("source_opacity", spec.opacity)
	result.set_meta("source_depth_write", spec.depthWrite)
	for key: String in spec.uniforms:
		var value: Variant = spec.uniforms[key]
		if key == "uPattern":
			if int(value) >= 0:
				result.set_shader_parameter(key, textures[int(value)])
		elif key in ["uColor", "uAccent"]:
			result.set_shader_parameter(key, Vector3(value[0], value[1], value[2]))
		else:
			result.set_shader_parameter(key, value)
	result.set_shader_parameter("uPatternFlipY", 1.0 if spec.patternFlipY else 0.0)
	result.set_shader_parameter("curve_knee", curve.knee)
	result.set_shader_parameter("curve_inverse_radius", curve.inverse)
	return result

static func step(material: ShaderMaterial, delta: float, decay: float = NAN) -> void:
	var rate: float = Content.balance.bodyRules.shield.decay if is_nan(decay) else decay
	material.set_shader_parameter("uTime", float(material.get_shader_parameter("uTime")) + delta)
	material.set_shader_parameter("uFlash", maxf(0, float(material.get_shader_parameter("uFlash")) - delta * rate))

static func hit_strength(drop: float) -> float:
	var rules: Dictionary = Content.balance.bodyRules.shield
	return minf(float(rules.maximum), float(rules.base) + maxf(0, 0 if is_nan(drop) else drop) / float(rules.reference))

static func hit(material: ShaderMaterial, strength: float) -> void:
	material.set_shader_parameter("uFlash", maxf(float(material.get_shader_parameter("uFlash")), strength))
