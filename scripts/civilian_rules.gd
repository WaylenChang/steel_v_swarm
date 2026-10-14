class_name CivilianRules
extends RefCounted

static func body(seed_value: int) -> Dictionary:
	var random := SourceRng.new((seed_value & 0xffffffff) ^ 0x63766264)
	var height := 0.88 + random.next() * 0.28
	var waist := 62 + random.next() * 70
	var width := 0.82 + (waist - 62) / 70 * 0.52
	return {"heightScale": height, "waistCm": waist, "widthScale": width, "radiusScale": height * width}

static func _pick(random: SourceRng, values: Array) -> Variant:
	return values[int(floorf(random.next() * values.size()))]

static func appearance(seed_value: int, profession: int) -> Dictionary:
	var cfg: Dictionary = Content.balance.civilian_appearance
	var options: Dictionary = cfg.options
	var random := SourceRng.new((seed_value & 0xffffffff) ^ 0x63766170)
	var family := posmod(profession, cfg.occupations.size())
	var gender: String = _pick(random, options.gender)
	var age := 18 + int(floorf(random.next() * 68))
	var ethnicity: String = _pick(random, options.ethnicity)
	var skin: int = _pick(random, options.skinColor)
	var hair: int = _pick(random, [0x827874, 0xc9c7c2] if age >= 60 and random.next() < 0.7 else options.hairColor)
	var result := {"seed": seed_value & 0xffffffff, "family": family, "occupation": _pick(random, cfg.occupations[family]),
		"gender": gender, "age": age, "ethnicity": ethnicity, "skinColor": skin, "hairColor": hair}
	for property: String in ["hairStyle", "clothing", "bottoms", "headwear", "accessory", "footwear"]:
		result[property] = _pick(random, options[property])
	result.facialHair = "none" if gender == "female" else _pick(random, options.facialHair)
	for property: String in ["clothColor", "trouserColor", "accentColor"]:
		result[property] = _pick(random, options.palette)
	result.shoulderScale = 0.88 + random.next() * 0.24
	result.headScale = 0.92 + random.next() * 0.16
	result.merge(body(seed_value))
	return result

static func speed(spy: bool) -> float:
	return float(Content.constants.UNITS.soldier.speed) * float(Content.constants.CIVILIAN.SPY_SPEED_F if spy else Content.constants.CIVILIAN.CIV_SPEED_F)

static func point(random: SourceRng, state: Dictionary, terrain_blocked: Callable) -> Dictionary:
	var cfg: Dictionary = Content.constants.CIVILIAN
	var bounds: Dictionary = state.bounds
	for attempt in range(40):
		var x := float(bounds.minX) + random.next() * (float(bounds.maxX) - float(bounds.minX))
		var z := float(bounds.maxZ) - random.next() * (float(bounds.maxZ) - float(bounds.minZ))
		if not SceneRules.in_bounds(bounds, x, z, 4) or SceneRules.lane_distance(state.lanes, x, z) < float(cfg.LANE_MIN):
			continue
		if not SceneRules.far_from_structures(state, x, z, cfg.BASE_CLEAR, 0):
			continue
		var bad := false
		for obstacle: Dictionary in state.blockers:
			var dx := x - float(obstacle.x)
			var dz := z - float(obstacle.z)
			if sqrt(dx * dx + dz * dz) < float(obstacle.radius) + 2:
				bad = true
				break
		if not bad and not terrain_blocked.call(x, z):
			return {"x": x, "z": z}
	return {}

static func wander(random: SourceRng, state: Dictionary, home: Vector2, terrain_blocked: Callable) -> Dictionary:
	for attempt in range(12):
		var angle := random.next() * TAU
		var radius := random.next() * float(Content.constants.CIVILIAN.WANDER_R)
		var x := float(home.x) + cos(angle) * radius
		var z := float(home.y) - sin(angle) * radius
		if not SceneRules.in_bounds(state.bounds, x, z, 4) or SceneRules.lane_distance(state.lanes, x, z) < float(Content.constants.CIVILIAN.LANE_MIN):
			continue
		if not terrain_blocked.call(x, z):
			return {"x": x, "z": z}
	return {"x": home.x, "z": home.y}

static func move(state: Dictionary, goal: Vector2, movement_speed: float, delta: float, bounds: Dictionary, terrain_blocked: Callable, away: bool = false) -> Dictionary:
	var dx := float(goal.x) - float(state.x)
	var dz := float(goal.y) - float(state.z)
	var distance := sqrt(dx * dx + dz * dz)
	if distance < 0.001:
		return {}
	var direction := (-1.0 if away else 1.0) / distance
	var x := clampf(float(state.x) + direction * dx * movement_speed * delta, float(bounds.minX) + 4, float(bounds.maxX) - 4)
	var z := clampf(float(state.z) + direction * dz * movement_speed * delta, float(bounds.minZ) + 4, float(bounds.maxZ) - 4)
	if terrain_blocked.call(x, z) and not terrain_blocked.call(state.x, state.z):
		return {}
	return {"x": x, "z": z, "yaw": atan2(-direction * dx, -direction * dz)}

static func kill_reward(own: bool, spy: bool) -> float:
	var cfg: Dictionary = Content.constants.CIVILIAN.KILL_F
	var factor := float(cfg.ownSpy if own else cfg.enemySpy) if spy else float(cfg.ownCiv if own else cfg.enemyCiv)
	return floorf(float(Content.constants.ECON.BOUNTY.soldier) * factor + 0.5)
