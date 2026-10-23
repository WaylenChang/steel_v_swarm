class_name AudioPan
extends RefCounted

static func routes(pan: float, channels: int) -> Array[Dictionary]:
	var position := clampf(pan, -1, 1)
	if channels == 1:
		var coefficients := mono_coefficients(position)
		return [_route(coefficients.x, coefficients.y)]
	if channels == 2:
		if position <= 0:
			var angle := (position + 1.0) * PI / 2.0
			return [_route(1, 0), _route(cos(angle), sin(angle))]
		var angle := position * PI / 2.0
		return [_route(cos(angle), sin(angle)), _route(0, 1)]
	push_error("Source stereo panning requires one or two captured mono channels")
	return []

static func mono_coefficients(pan: float) -> Vector2:
	var angle := (clampf(pan, -1, 1) + 1.0) * PI / 4.0
	return Vector2(cos(angle), sin(angle))

static func _route(left: float, right: float) -> Dictionary:
	var total := left + right
	# Godot's native panner mixes duplicated mono as gain * (1-pan, 1+pan).
	return {"gain": total / 2.0, "pan": (right - left) / total if total > 0 else 0.0}
