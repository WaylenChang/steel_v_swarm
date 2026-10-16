class_name DeathPresentation
extends RefCounted

static func commands(kind: String, side: String, position: Vector3, ground: float) -> Array[Dictionary]:
	var rules: Dictionary = Content.balance.presentationFrame.deathEffects
	var templates: Dictionary = rules.get(kind, rules.unknown)
	var result: Array[Dictionary] = []
	for template: Dictionary in templates["neutral" if side.is_empty() else "side"]:
		var command := template.duplicate(true)
		command.point = Vector3(position.x + float(template.point[0]), ground + float(template.point[1]), position.z + float(template.point[2]))
		if command.get("accent") == -1:
			command.accent = int(Color(Content.side_info(side).color).to_rgba32() >> 8)
		result.append(command)
	return result

static func has_effects(kind: String) -> bool:
	var rules: Dictionary = Content.balance.presentationFrame.deathEffects
	return not rules.get(kind, rules.unknown).neutral.is_empty()
