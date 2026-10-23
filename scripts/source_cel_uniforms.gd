class_name SourceCelUniforms
extends RefCounted

static var NEGATIVE_ZERO: float = PackedByteArray([0, 0, 0, 128]).decode_float(0)

static func bind(material: ShaderMaterial, bundle: SourceCelData, entries: Dictionary, names: Array) -> bool:
	var transaction := prepare(material, bundle, entries, names)
	if not transaction.ok:
		push_error("Cannot bind original cel uniforms: " + str(transaction.error))
		return false
	for name: String in transaction.value:
		material.set_shader_parameter(name, transaction.value[name])
	return true

static func prepare(material: ShaderMaterial, bundle: SourceCelData, entries: Dictionary, names: Array) -> Dictionary:
	if material == null or material.shader == null:
		return _failure("Original cel uniforms require a native shader material")
	var schema := {}
	for property: Dictionary in material.shader.get_shader_uniform_list():
		schema[String(property.name)] = property
	var prepared := {}
	for name: String in names:
		if not entries.get(name) is Dictionary or not schema.has(name):
			return _failure("Missing source/native cel uniform declaration: " + name)
		var result := decode(bundle, entries[name], schema[name])
		if not result.ok:
			return _failure("%s: %s" % [name, result.error])
		prepared[name] = result.value
	# Validate the complete transaction before replacing any material parameter.
	return {"ok": true, "value": prepared}

static func decode(bundle: SourceCelData, source: Dictionary, property: Dictionary) -> Dictionary:
	var kind: String = source.get("type", "")
	var expected := int(property.get("type", TYPE_NIL))
	if kind == "undefined":
		return _failure("Undefined source values cannot satisfy a required uniform")
	if kind in ["sampler", "null"]:
		if expected != TYPE_OBJECT or property.get("hint_string", "") != "Texture2D":
			return _failure("Source sampler requires a native Texture2D uniform")
		if kind == "null":
			return {"ok": true, "value": null}
		if bundle == null or typeof(source.get("value")) not in [TYPE_INT, TYPE_FLOAT]:
			return _failure("Source sampler has no retained bundle/index")
		var index := int(source.value)
		if float(index) != float(source.value):
			return _failure("Source sampler index is not integral")
		if index < 0 or index >= bundle.sampler_images.size() or bundle.sampler_images[index] == null:
			return _failure("Source sampler index has no captured image")
		var texture := bundle.texture(index)
		return {"ok": true, "value": texture} if texture != null else _failure("Source sampler cannot be decoded")
	if expected == TYPE_ARRAY:
		if kind != "array" or not source.get("value") is Array or not str(property.get("hint_string", "")).ends_with("Texture2D"):
			return _failure("Native sampler arrays require source array entries")
		if source.value.is_empty():
			return _failure("Empty source sampler arrays require an explicit producer policy")
		var textures: Array[Texture2D] = []
		for item: Variant in source.value:
			if not item is Dictionary:
				return _failure("Invalid source sampler array entry")
			var result := decode(bundle, item, {"type": TYPE_OBJECT, "hint_string": "Texture2D"})
			if not result.ok:
				return result
			textures.append(result.value)
		return {"ok": true, "value": textures}
	var components := _components(source)
	if not components.ok:
		return components
	var values: Array = components.value
	var scalar := kind in ["number", "boolean", "nonfinite"]
	var array := kind in ["array", "buffer"]
	var packed_types := [TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_VECTOR4_ARRAY, TYPE_PACKED_COLOR_ARRAY]
	if kind == "array" and not values.is_empty() and components.shape != "scalar" and expected not in packed_types:
		return _failure("Structured source arrays cannot substitute for a scalar/vector/matrix")
	var value: Variant
	match expected:
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT:
			if not scalar or values.size() != 1:
				return _failure("Source scalar does not match the native uniform")
			value = float(values[0]) if expected == TYPE_FLOAT else _int32(float(values[0]))
			if expected == TYPE_BOOL:
				value = int(value) != 0
		TYPE_VECTOR2, TYPE_VECTOR2I:
			if values.size() != 2 or kind in ["mat3", "mat4"]:
				return _failure("Source vec2 has the wrong component count/type")
			value = Vector2(values[0], values[1]) if expected == TYPE_VECTOR2 else Vector2i(_int32(values[0]), _int32(values[1]))
		TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_COLOR:
			var count := 3 if expected != TYPE_COLOR or int(property.get("hint", PROPERTY_HINT_NONE)) == PROPERTY_HINT_COLOR_NO_ALPHA else 4
			if values.size() != count or kind in ["mat3", "mat4"]:
				return _failure("Source vec3/colour has the wrong component count/type")
			if expected == TYPE_VECTOR3I:
				value = Vector3i(_int32(values[0]), _int32(values[1]), _int32(values[2]))
			elif count == 3:
				value = Vector3(values[0], values[1], values[2])
			else:
				value = Vector4(values[0], values[1], values[2], values[3])
			# Three Color values are already linear; vectors avoid Godot's Color sRGB conversion.
		TYPE_VECTOR4, TYPE_VECTOR4I:
			if values.size() != 4 or kind in ["mat3", "mat4"]:
				return _failure("Source vec4 has the wrong component count/type")
			value = Vector4(values[0], values[1], values[2], values[3]) if expected == TYPE_VECTOR4 else Vector4i(_int32(values[0]), _int32(values[1]), _int32(values[2]), _int32(values[3]))
		TYPE_BASIS:
			if values.size() != 9 or kind not in ["mat3", "array", "buffer"]:
				return _failure("Source mat3 requires nine column-major components")
			value = Basis(Vector3(values[0], values[1], values[2]), Vector3(values[3], values[4], values[5]), Vector3(values[6], values[7], values[8]))
		TYPE_PROJECTION:
			if values.size() != 16 or kind not in ["mat4", "array", "buffer"]:
				return _failure("Source mat4 requires all sixteen column-major components")
			value = Projection(Vector4(values[0], values[1], values[2], values[3]), Vector4(values[4], values[5], values[6], values[7]),
				Vector4(values[8], values[9], values[10], values[11]), Vector4(values[12], values[13], values[14], values[15]))
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_VECTOR4_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			if not array:
				return _failure("Native uniform arrays require source arrays or typed buffers")
			if values.is_empty():
				return _failure("Empty source uniform arrays require an explicit producer policy")
			if expected == TYPE_PACKED_FLOAT32_ARRAY:
				if kind == "array" and not values.is_empty() and components.shape not in ["scalar", "mat3", "mat4"]:
					return _failure("Native float/matrix arrays require matching source scalar/matrix elements")
				value = PackedFloat32Array(values)
			elif expected == TYPE_PACKED_INT32_ARRAY:
				value = PackedInt32Array()
				for entry: float in values:
					value.append(_int32(entry))
			else:
				var count := 4
				if expected == TYPE_PACKED_VECTOR2_ARRAY:
					count = 2
				elif expected == TYPE_PACKED_VECTOR3_ARRAY or expected == TYPE_PACKED_COLOR_ARRAY and int(property.get("hint", PROPERTY_HINT_NONE)) == PROPERTY_HINT_COLOR_NO_ALPHA:
					count = 3
				var shapes: Array = {2: ["scalar", "vec2"], 3: ["scalar", "vec3", "color"], 4: ["scalar", "vec4", "quaternion"]}[count]
				if kind == "array" and not values.is_empty() and components.shape not in shapes:
					return _failure("Source vector array elements do not match the native vector width")
				if values.size() % count != 0:
					return _failure("Source vector array has an incomplete element")
				value = PackedVector2Array() if count == 2 else PackedVector3Array() if count == 3 else PackedVector4Array()
				for offset in range(0, values.size(), count):
					if count == 2:
						value.append(Vector2(values[offset], values[offset + 1]))
					elif count == 3:
						value.append(Vector3(values[offset], values[offset + 1], values[offset + 2]))
					else:
						value.append(Vector4(values[offset], values[offset + 1], values[offset + 2], values[offset + 3]))
		_:
			return _failure("Unsupported native uniform type: " + type_string(expected))
	return {"ok": true, "value": value}

static func _components(source: Dictionary) -> Dictionary:
	var kind: String = source.get("type", "")
	var values: Array = []
	var shape := ""
	if kind == "number":
		if typeof(source.get("value")) not in [TYPE_INT, TYPE_FLOAT]:
			return _failure("Invalid source number")
		if source.has("negativeZero") and not source.negativeZero is bool:
			return _failure("Invalid source negative-zero marker")
		if source.get("negativeZero", false) and float(source.value) != 0:
			return _failure("Invalid source negative-zero marker")
		values.append(NEGATIVE_ZERO if source.get("negativeZero", false) else float(source.value))
	elif kind == "boolean":
		if not source.get("value") is bool:
			return _failure("Invalid source boolean")
		values.append(1.0 if source.value else 0.0)
	elif kind == "nonfinite":
		match source.get("value"):
			"NaN": values.append(NAN)
			"Infinity": values.append(INF)
			"-Infinity": values.append(-INF)
			_: return _failure("Invalid non-finite source number")
	elif kind == "array":
		if not source.get("value") is Array:
			return _failure("Invalid source uniform array")
		for item: Variant in source.value:
			if not item is Dictionary or item.get("type") in ["array", "buffer"]:
				return _failure("Nested source uniform arrays require an explicit shader adapter")
			var current := str(item.get("type", ""))
			if current in ["number", "boolean", "nonfinite"]:
				current = "scalar"
			elif current == "color":
				current = "vec3"
			elif current == "quaternion":
				current = "vec4"
			if not shape.is_empty() and current != shape:
				return _failure("Source uniform array mixes incompatible element types")
			shape = current
			var result := _components(item)
			if not result.ok:
				return result
			values.append_array(result.value)
	elif kind in ["vec2", "vec3", "vec4", "color", "quaternion", "mat3", "mat4", "buffer"]:
		var expected := {"vec2": 2, "vec3": 3, "vec4": 4, "color": 3, "quaternion": 4, "mat3": 9, "mat4": 16}
		if not source.get("value") is Array or expected.has(kind) and source.value.size() != int(expected[kind]):
			return _failure("Invalid source vector/matrix/buffer extent")
		var negative_zeros := []
		if source.has("negativeZeros"):
			if not source.negativeZeros is Array:
				return _failure("Invalid source vector/matrix negative-zero marker list")
			for nz: Variant in source.negativeZeros:
				if typeof(nz) not in [TYPE_INT, TYPE_FLOAT]:
					return _failure("Invalid source vector/matrix negative-zero marker index")
				var marker: float = float(nz)
				if not is_finite(marker) or floorf(marker) != marker:
					return _failure("Invalid source vector/matrix negative-zero marker index")
				if marker < 0.0 or marker >= float(source.value.size()):
					return _failure("Source vector/matrix negative-zero marker out of bounds")
				negative_zeros.append(int(marker))
		for index in range(source.value.size()):
			var entry: Variant = source.value[index]
			if typeof(entry) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(entry)):
				return _failure("Invalid source vector/matrix/buffer component")
			if index in negative_zeros and float(entry) != 0:
				return _failure("Invalid source vector/matrix negative-zero marker")
			values.append(NEGATIVE_ZERO if index in negative_zeros else float(entry))
	else:
		return _failure("Unsupported source uniform value: " + kind)
	return {"ok": true, "value": values, "shape": shape}

static func _int32(value: float) -> int:
	if not is_finite(value):
		return 0
	var wrapped := fmod(value - fmod(value, 1.0), 4294967296.0)
	if wrapped < 0:
		wrapped += 4294967296.0
	return int(wrapped) - (4294967296 if wrapped >= 2147483648.0 else 0)

static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
