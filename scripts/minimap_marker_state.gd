class_name MinimapMarkerState
extends RefCounted

var bunkers: Dictionary = {}

func remember(rows: Array) -> void:
	for row: Dictionary in rows:
		if row.kind != "bunker":
			continue
		var point: Vector3 = row.position
		var key := "%d,%d" % [int(floorf(point.x + .5)), int(floorf(point.z + .5))]
		bunkers[key] = {"point": Vector2(point.x, point.z), "side": row.side}

static func commands(rows: Array, viewer: String, known: Array, own: Variant, yaw: float) -> Array:
	var rules: Dictionary = Content.balance.minimap.markers
	var templates: Dictionary = rules.templates.get(viewer, rules.templates[""])
	var result: Array = []
	for row: Dictionary in rows:
		if row.neutral or row.kind == "bunker":
			continue
		var family: String = row.kind if row.kind in ["base", "tower"] else "self" if row.hero and row["self"] else "hero" if row.hero else "heli" if row.kind == "heli" else "npc"
		_append(result, templates.get(row.side, templates[""])[family], row.point)
	for row: Dictionary in known:
		_append(result, templates.get(row.side, templates[""]).bunker, row.point)
	if not viewer.is_empty() and own != null:
		_append(result, rules.own, own, -yaw, true)
	var width := float(rules.initialWidth)
	for command: Dictionary in result:
		if not command.fill:
			if command.width != null:
				width = float(command.width)
			command.width = width
	return result

static func _append(result: Array, template: Array, point: Vector2, yaw: float = 0, local: bool = false) -> void:
	for primitive: Dictionary in template:
		var command := primitive.duplicate(true)
		if local:
			command.position = [point.x, point.y]
			command.rotation = yaw
		elif command.shape == "rect":
			command.rect[0] += point.x
			command.rect[1] += point.y
		elif command.shape == "circle":
			command.center[0] += point.x
			command.center[1] += point.y
		result.append(command)
