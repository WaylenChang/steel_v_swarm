class_name HurtBearingLog
extends RefCounted

var pending: Dictionary = {}

func record(target: int, attacker: int, origin: Vector3, amount: float, elevation: Variant = null) -> void:
	if not pending.has(target):
		pending[target] = {}
	var sources: Dictionary = pending[target]
	if sources.has(attacker):
		sources[attacker].amount += amount
		return
	sources[attacker] = {"origin": origin, "amount": amount, "elevation": elevation}

func flush(order: Array) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for target: int in order:
		for source: Dictionary in pending.get(target, {}).values():
			var point: Vector3 = source.origin
			var event := {"actor": target, "origin": Vector3(_quantize(point.x), 0, -_quantize(-point.z)), "amount": _quantize(float(source.amount))}
			if source.elevation != null:
				event.elevation = _quantize(float(source.elevation))
			events.append(event)
	pending.clear()
	return events

static func _quantize(value: float) -> float:
	return floorf(value * 10 + .5) / 10
