class_name FanEffectGeometry
extends RefCounted

static func vertices(source: Array, owners: Array, ownership_count: int, definition: Dictionary,
		origin: Vector3, direction: Vector3, reach: float, clip: Callable) -> PackedVector3Array:
	var result := PackedVector3Array()
	var arc: Variant = definition.get("arc")
	var half := deg_to_rad(float(arc) if ControlPreferences.truthy(arc) else 15.0)
	var count := int(definition.fanSubs)
	var span := half * 2 / count
	var orientation := SourceQuaternion.from_unit_vectors(Vector3.BACK, SourceQuaternion.vector_normalized(direction))
	for index in range(owners.size()):
		var x := float(source[index * 3])
		var y := float(source[index * 3 + 1])
		var z := maxf(0, float(source[index * 3 + 2]))
		var bin := int(owners[index])
		var low := -half + bin * span
		var high := low + span
		var phi := clampf(atan2(x, z), low, high)
		var maximum := acos(minf(1, cos(half) / cos(phi)))
		var elevation := clampf(atan2(y, sqrt(x * x + z * z)), -maximum, maximum)
		var nearest_bin := clampi(floori(phi / span + count / 2.0), 0, count - 1)
		var factor := minf(_range_factor(definition, bin), _range_factor(definition, nearest_bin))
		if phi - low < .000001 and bin > 0:
			factor = minf(factor, _range_factor(definition, bin - 1))
		if high - phi < .000001 and bin + 1 < ownership_count:
			factor = minf(factor, _range_factor(definition, bin + 1))
		var length := minf(sqrt(x * x + y * y + z * z), factor)
		var local := SourceQuaternion.rotate(orientation, Vector3(sin(phi) * cos(elevation) * length * reach,
			sin(elevation) * length * reach, cos(phi) * cos(elevation) * length * reach))
		if clip.is_valid() and local.length_squared() > .0000000001:
			var hit: Dictionary = clip.call(origin, origin + local)
			if hit.get("to") is Vector3 and origin.distance_squared_to(hit.to) < local.length_squared():
				local = SourceQuaternion.vector_normalized(local) * origin.distance_to(hit.to)
		result.append(local)
	return result

static func _range_factor(definition: Dictionary, bin: int) -> float:
	var factors: Array = definition.fanRangeFactors
	if bin >= 0 and bin < factors.size():
		return float(factors[bin])
	return float(Content.constants.FAN_RANGE_CENTER_F) if factors.size() <= 1 else 1.0
