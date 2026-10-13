class_name CombatMath
extends RefCounted

# Game-specific settlement cannot be replaced by the engine's physics solver.
static func armor_multiplier(armor: float, penetration: float = 0.0) -> float:
	var effective := maxf(0.0, armor - penetration)
	return 1.0 - effective / (effective + Content.constants.VITALS.AR_K)

static func shield_split(definition: Dictionary, damage: float, shield: float) -> Dictionary:
	var shield_multiplier: float = definition.get("vsSp", 1.0)
	var hp_multiplier: float = definition.get("vsHp", 1.0)
	var pierced: float = damage * definition.get("spPierce", 0.0)
	var budget := damage - pierced
	var spent := minf(budget, maxf(0.0, shield) / shield_multiplier) if shield_multiplier > 0 else budget
	return {"toSp": spent * shield_multiplier, "toHp": (pierced + budget - spent) * hp_multiplier}

static func damage_falloff(definition: Dictionary, distance: float) -> float:
	var c: Dictionary = Content.constants
	if definition.get("fan", false):
		var reach: float = definition.get("range", 0)
		return maxf(c.FAN_FLOOR, c.FAN_MUZZLE * (1.0 - distance / reach)) if reach > 0 else 1.0
	var floor_value: float = c.FALLOFF.FLOOR.get(definition.type, 0)
	if floor_value == 0:
		return 1.0
	var delta: float = distance - definition.get("range", 0) * c.FALLOFF.PLATEAU
	if delta <= 0:
		return 1.0
	var kinetic: bool = definition.type in ["gun", "rail"]
	var length_scale: float = definition.get("mv", 600) * c.FALLOFF.KIN_L if kinetic else c.FALLOFF.EXT[definition.type]
	return maxf(floor_value, exp(-(2.0 if kinetic else 1.0) * delta / length_scale))

static func blast_falloff(radius: float, distance: float) -> float:
	var bands: Dictionary = Content.constants.BLAST
	if distance <= radius * bands.CORE:
		return 1.0
	if radius <= 0 or distance >= radius * bands.EDGE:
		return 0.0
	return pow((radius * bands.EDGE - distance) / (radius * (bands.EDGE - bands.CORE)), bands.EXP)

static func max_horizontal(reach: float, height: float) -> float:
	var c: Dictionary = Content.constants
	if reach <= 0:
		return 0.0
	var transition: float = reach * c.WEAPON_TRANS_Y_F
	if height >= transition:
		var radius: float = reach * c.WEAPON_SPHERE_R_F
		return 0.0 if height >= radius else sqrt(radius * radius - height * height)
	return maxf(0.0, reach - height / c.SQRT3)

static func in_range(reach: float, delta: Vector3, radius: float = 0.0) -> bool:
	if reach <= 0 or delta.y > reach * Content.constants.WEAPON_SPHERE_R_F:
		return false
	return maxf(0.0, Vector2(delta.x, delta.z).length() - radius) <= max_horizontal(reach, delta.y)

static func target_class(kind: String) -> String:
	return Content.constants.TARGET_CLASS.get(kind, "armor")

static func vs_multiplier(definition: Dictionary, kind: String) -> float:
	var factor: float = definition.get("vs", {}).get(target_class(kind), 1.0)
	return minf(1.0, factor) if target_class(kind) == "building" else factor

static func view_lock_step(difference: float, delta: float) -> float:
	var lock: Dictionary = Content.constants.VIEW_LOCK
	return clampf(difference * minf(1.0, lock.EASE * delta), -lock.W * delta, lock.W * delta)

static func fan_bin_distance(definition: Dictionary, bin: int, distance: float, angle: float, radius: float) -> float:
	if not is_finite(distance) or not is_finite(angle):
		return -1.0
	radius = maxf(0.0, radius)
	if distance <= 0:
		return 0.0
	var half_arc := deg_to_rad(definition.get("arc", 15))
	var width: float = half_arc * 2 / definition.fanSubs
	var low := -half_arc + bin * width
	var high := low + width
	if angle >= low and angle <= high:
		return maxf(0.0, distance - radius)
	var edge := low if angle < low else high
	var offset := angle - edge
	var lateral := distance * sin(offset)
	if absf(lateral) > radius:
		return -1.0
	return maxf(0.0, distance * cos(offset) - sqrt(radius * radius - lateral * lateral))

static func lance_zones(offset: Vector2, radius: float, beam_radius: float) -> Array[int]:
	var core: float = beam_radius * Content.constants.LANCE.CORE_F
	var distance := offset.length()
	var zones: Array[int] = []
	if distance - radius <= core:
		zones.append(0)
	if distance + radius > core:
		if distance <= radius:
			for bin in range(1, 7):
				zones.append(bin)
		else:
			var angle := atan2(offset.y, offset.x)
			var half := asin(minf(1.0, radius / distance))
			var segment := TAU / 6
			var first := floori((angle - half + PI) / segment)
			var last := floori((angle + half + PI) / segment)
			for bin in range(first, last + 1):
				zones.append(posmod(bin, 6) + 1)
	zones.sort()
	return zones

