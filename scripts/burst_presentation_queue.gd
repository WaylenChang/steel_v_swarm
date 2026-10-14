class_name BurstPresentationQueue
extends RefCounted

var pending: Array[Dictionary] = []

func schedule(definition: Dictionary, now: float, payload: Dictionary) -> void:
	if not is_finite(now) or not definition.has("burst"):
		return
	var count := int(definition.burst.count)
	var gap: float = definition.burst.gap
	if count <= 1 or not is_finite(gap) or gap <= 0:
		return
	for index in range(1, count):
		pending.append({"at": now + gap * index, "index": index, "count": count, "payload": payload.duplicate(true)})

func take_due(now: float) -> Array[Dictionary]:
	var due: Array[Dictionary] = []
	if not is_finite(now):
		return due
	# Source walks backward through insertion order, including several callbacks due after a hitch.
	for index in range(pending.size() - 1, -1, -1):
		if now < pending[index].at:
			continue
		due.append(pending[index])
		pending.remove_at(index)
	return due
