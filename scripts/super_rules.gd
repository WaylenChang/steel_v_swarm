class_name SuperRules
extends RefCounted

static func level(value: float) -> int:
	if is_nan(value):
		return 0
	return floori(clampf(value, 0, float(Content.constants.SUPER_UPG.MAX)))

static func defense_level(value: float) -> float:
	return level(value) * 3.0 / 20.0

static func combat_level(value: float) -> float:
	return 1.0 + defense_level(value)

static func body_scale(value: float) -> float:
	return 1.0 + floorf(clampf(value, 0, Content.constants.SUPER_UPG.MAX) / 20.0) if is_finite(value) else 1.0

static func spawn_point(random: Callable, bounds: Dictionary, lanes: Array, guns: Array, blockers: Array, terrain_blocked: Callable, last: Variant = null) -> Vector2:
	var rules: Dictionary = Content.balance["super"].spawn
	var clearance := float(Content.constants.UNITS.tower.range) * float(rules.rangeFactor)
	var base_clearance := maxf(clearance, maxf(float(Content.constants.UNITS.base.get("range", 0)), float(Content.constants.UNITS.base.get("guns", {}).get("range", 0))) * float(rules.rangeFactor))
	var candidates: Array[Vector2] = []
	for attempt in range(int(rules.attempts)):
		var x := float(bounds.minX) + float(rules.padding) + float(random.call()) * (float(bounds.maxX) - float(bounds.minX) - 2 * float(rules.padding))
		# Reverse source Z sampling after the coordinate conversion; preserve draw order.
		var z := float(bounds.maxZ) - float(rules.padding) - float(random.call()) * (float(bounds.maxZ) - float(bounds.minZ) - 2 * float(rules.padding))
		if terrain_blocked.call(x, z) or SceneRules.lane_distance(lanes, x, z) < clearance:
			continue
		var point := Vector2(x, z)
		var blocked := false
		for obstacle: Dictionary in blockers:
			if point.distance_to(Vector2(obstacle.x, obstacle.z)) < float(obstacle.r) + float(rules.hazardPadding):
				blocked = true
				break
		if blocked:
			continue
		for gun: Dictionary in guns:
			if point.distance_to(Vector2(gun.x, gun.z)) < (base_clearance if gun.kind == "base" else clearance):
				blocked = true
				break
		if not blocked:
			candidates.append(point)
	if candidates.is_empty():
		return Vector2((float(bounds.minX) + float(bounds.maxX)) / 2, (float(bounds.minZ) + float(bounds.maxZ)) / 2)
	if last is Vector2:
		var distant := candidates.filter(func(point): return point.distance_to(last) >= float(rules.separation))
		if not distant.is_empty():
			return distant[floori(float(random.call()) * distant.size())]
		var best := candidates[0]
		var distance := -1.0
		for point: Vector2 in candidates:
			var current := point.distance_to(last)
			if current > distance:
				distance = current
				best = point
		return best
	return candidates[floori(float(random.call()) * candidates.size())]
