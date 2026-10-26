extends RefCounted

static var next_order := 0

static func stamp() -> int:
	var order := next_order
	next_order += 1
	return order

static func advance(owners: Array, delta: float) -> void:
	if not is_finite(delta) or delta < 0:
		return
	var entries: Array[Dictionary] = []
	for owner: Node in owners:
		if not is_instance_valid(owner) or owner.is_queued_for_deletion():
			continue
		for effect: Dictionary in owner.presentation_effects():
			entries.append({"owner": owner, "effect": effect, "index": entries.size()})
	entries.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_order := int(left.effect.get("order", -1))
		var right_order := int(right.effect.get("order", -1))
		return left.index < right.index if left_order == right_order else left_order < right_order)
	# The source trims once before fading, including on a zero-delta frame.
	var over := maxi(0, entries.size() - int(Content.balance.npcShots.limits.maximum))
	for index in range(over):
		var entry: Dictionary = entries[index]
		if is_instance_valid(entry.owner) and not entry.owner.is_queued_for_deletion():
			entry.owner.discard_effect(entry.effect)
	for index in range(entries.size() - 1, over - 1, -1):
		var entry: Dictionary = entries[index]
		if is_instance_valid(entry.owner) and not entry.owner.is_queued_for_deletion():
			entry.owner.advance_effect(entry.effect, delta)
