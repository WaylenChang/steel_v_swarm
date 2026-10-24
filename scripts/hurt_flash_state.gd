class_name HurtFlashState
extends RefCounted

var active := false
var started := 0.0

func trigger(now: float) -> bool:
	if active and now - started < float(Content.balance.hurtPresentation.duration) * 2:
		return false
	active = true
	started = now
	return true

func finish() -> void:
	active = false

func opacity(now: float) -> float:
	if not active:
		return 0
	var progress := (now - started) / float(Content.balance.hurtPresentation.duration)
	if progress < 0 or progress >= 1:
		return 0
	var peak: float = Content.balance.hurtPresentation.peak
	return _ease_out(progress / peak) if progress < peak else 1 - _ease_out((progress - peak) / (1 - peak))

static func _ease_out(value: float) -> float:
	return bezier(value, Vector2.ZERO, Vector2(.58, 1))

static func ease_in_out(value: float) -> float:
	return bezier(value, Vector2(.42, 0), Vector2(.58, 1))

static func bezier(value: float, first: Vector2, second: Vector2) -> float:
	return bezier_values(value, first.x, first.y, second.x, second.y)

static func bezier_values(value: float, first_x: float, first_y: float, second_x: float, second_y: float) -> float:
	var low := 0.0
	var high := 1.0
	for index in range(40):
		var time := (low + high) * .5
		var x := 3 * (1 - time) * (1 - time) * time * first_x + 3 * (1 - time) * time * time * second_x + time * time * time
		if x < value:
			low = time
		else:
			high = time
	var time := (low + high) * .5
	return 3 * (1 - time) * (1 - time) * time * first_y + 3 * (1 - time) * time * time * second_y + time * time * time
