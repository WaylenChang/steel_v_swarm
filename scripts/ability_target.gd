class_name AbilityTarget
extends RefCounted

static func wire_point(x: float, visual_z: float) -> Vector2:
	return Vector2(floorf(x * 10 + .5) / 10, floorf(-visual_z * 10 + .5) / 10)

static func clamp_point(origin: Vector2, reach: float, requested: Vector2) -> Vector2:
	if reach == 0:
		return origin
	var offset := requested - origin
	if offset.length() > reach:
		return origin + offset.normalized() * reach
	return requested
