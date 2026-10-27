class_name PipViewState
extends RefCounted

static func sources(rows: Array, peer: int, drone: bool, dead: bool, side: String, low_power: bool, render_scale: float, rules: Dictionary) -> Array:
	if side.is_empty() or dead or rules.is_empty():
		return []
	var result: Array = []
	for index in rows.size():
		var row: Dictionary = rows[index]
		if int(row.peer) != peer:
			continue
		if drone:
			if row.hero and not row.self and not row.dead:
				result.append({"row": row, "order": index})
		elif row.decoy and not row.lost:
			result.append({"row": row, "order": index})
	# Godot's native sort is unstable; source insertion order breaks equal indices.
	result.sort_custom(func(a, b):
		return a.order < b.order if int(a.row.index) == int(b.row.index) else int(a.row.index) < int(b.row.index))
	var maximum := int(rules.LOW_COUNT) if low_power or render_scale != 0 and render_scale < 1 else int(rules.HIGH_COUNT)
	return result.slice(0, maximum).map(func(entry): return entry.row)

static func frame(size: Vector2, index: int, position: Vector3, yaw: float, decoy: bool, rules: Dictionary) -> Dictionary:
	var width := floori(minf(float(rules.MAX_W), size.x * float(rules.W_FRAC)) + 0.5)
	var height := floori(width * float(rules.ASPECT) + 0.5)
	var offset := Vector2(float(rules.PAD), float(rules.TOP) + index * (height + float(rules.GAP)))
	# The source adds the eye offset before the camera position enters Float32 storage.
	var eye := Vector3(position.x, float(position.y) + float(rules.DECOY_EYE if decoy else rules.HERO_EYE), position.z)
	return {"rect": Rect2(offset, Vector2(width, height)), "position": eye, "yaw": yaw, "fov": float(rules.FOV)}
