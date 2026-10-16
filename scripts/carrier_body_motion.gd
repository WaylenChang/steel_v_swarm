class_name CarrierBodyMotion
extends RefCounted

var yaw := 0.0
var pitch := 0.0
var previous := Vector3.ZERO
var sampled := false

func place(position: Vector3) -> void:
	previous = position
	sampled = true

func advance(position: Vector3, reported_yaw: float, delta: float, hyper: bool, snap: bool) -> void:
	if not position.is_finite() or not is_finite(reported_yaw) or not is_finite(delta) or delta < 0:
		return
	var rules: Dictionary = Content.balance.bodyRules.presentation.carrier
	var factor := 1.0 - exp(-float(rules.response) * delta)
	var wanted := reported_yaw + PI
	yaw = wanted if snap else yaw + atan2(sin(wanted - yaw), cos(wanted - yaw)) * factor
	if hyper:
		var offset := position - previous if sampled else Vector3.ZERO
		var horizontal := Vector2(offset.x, offset.z).length()
		if horizontal + absf(offset.y) > float(rules.pitchThreshold):
			wanted = -atan2(offset.y, horizontal)
			pitch = wanted if snap else pitch + (wanted - pitch) * factor
	previous = position
	sampled = true
