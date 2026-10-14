class_name StatusRules
extends RefCounted

static var minimum_evasion_speed := NAN

static func evasion_min_speed() -> float:
	if is_finite(minimum_evasion_speed):
		return minimum_evasion_speed
	var logarithms := 0.0
	var count := 0
	for hero: Dictionary in Content.heroes.values():
		var unit: Dictionary = Content.constants.UNITS[hero.kind]
		for key: String in ["speed", "fly"]:
			var speed: float = float(unit.get(key, 0)) * float(hero.mods.get("speed", 1))
			if speed > 0:
				logarithms += log(speed)
				count += 1
	var middle := exp(logarithms / count) if count > 0 else 1.0
	var floor_speed: float = Content.constants.EVASION.MOBILITY_MIN
	minimum_evasion_speed = floor_speed if Content.constants.SPEED_COMP.K >= 1 else middle * pow(floor_speed / middle, Content.constants.SPEED_COMP.K)
	return minimum_evasion_speed

static func boss_hp_cap(segment: float) -> float:
	var cfg: Dictionary = Content.constants.BOSS
	var remaining := float(cfg.HP_MUL)
	for index in range(ceili(clampf(segment, 0, cfg.SEG_W.size()))):
		remaining -= float(cfg.SEG_W[index])
	return remaining / float(cfg.HP_MUL)

static func multiplier(buffs: Array, key: String, now: float) -> float:
	var result := 1.0
	for buff: Dictionary in buffs:
		if float(buff.until) > now:
			result *= float(buff.get("mul", {}).get(key, 1.0))
	return result

static func maximum(buffs: Array, key: String, now: float) -> float:
	var result := 0.0
	for buff: Dictionary in buffs:
		if float(buff.until) > now:
			result = maxf(result, float(buff.get("mul", {}).get(key, 0.0)))
	return result

static func movement_modifier(buffs: Array, key: String, now: float) -> float:
	return maxf(1.0, maximum(buffs, key, now))

static func tier_value(value: Variant, level: float) -> float:
	if not value is Array:
		return float(value)
	var index := level - 1
	if index <= 0:
		return float(value[0])
	if index < value.size():
		var low := mini(value.size() - 1, floori(index))
		var high := mini(value.size() - 1, ceili(index))
		return lerpf(float(value[low]), float(value[high]), index - low)
	var last := float(value[-1])
	var step := last - float(value[-2]) if value.size() > 1 else 0.0
	return maxf(0, last + step * (index - (value.size() - 1)))

static func self_attack_boost(character: String, level: int, light_level: int, heavy_level: int) -> Dictionary:
	var neutral := {"dmgMul": 0.0, "heal": 0.0, "alphaX": 1.0}
	var raw: Dictionary = Content.heroes[character].atk
	# The original compensation gate uses effect semantics, including direct team effects.
	if raw.fx in ["strike", "emp", "summon"] or (raw.fx in ["heal", "buff"] and raw.get("target") == "team"):
		return neutral
	var tier := (light_level + heavy_level) / 2.0
	var budget: float = Content.constants.SPECIAL.BASE * (1 + Content.constants.SPECIAL.PER_LVL * (tier - 1))
	var equivalent: float = budget * Content.constants.SELF_ATK.REALIZED_F * tier_value(raw.cd, level) / Content.constants.SPECIAL_CD_S
	var weapon := Content.weapon(character, "heavy", heavy_level)
	var cycle: float = weapon.mag / (weapon.rate if weapon.rate else Content.constants.RATE_DEF) + weapon.reload
	var dps: float = weapon.dmg * weapon.mag / cycle
	if raw.fx == "stealth" and dps > 0:
		neutral.alphaX = minf(Content.constants.SELF_ATK.ALPHA_MAX, 1 + equivalent / (dps * Content.constants.SELF_ATK.ALPHA_S))
	elif raw.fx == "heal":
		neutral.heal = equivalent
	elif raw.fx == "buff" and raw.get("mul") is Dictionary and raw.mul.get("dmg", 0) and dps > 0:
		var duration := tier_value(raw.dur, level)
		if duration > 0:
			neutral.dmgMul = minf(Content.constants.SELF_ATK.MUL_MAX, equivalent / (dps * duration))
	return neutral

static func fluid_factor(wet: int) -> float:
	match wet:
		1: return Content.constants.TERRAIN_FX.WATER_FACTOR
		2: return Content.constants.TERRAIN_FX.SWAMP_FACTOR
		3: return Content.constants.TERRAIN_FX.FROZEN_FACTOR
	return 1.0

static func shield_kind_factor(kind: String, blast: bool, boosted: bool, attack_slot: String) -> float:
	var kinds: Dictionary = Content.constants.SHIELD_DEFENSE.KINDS
	var spec: Dictionary = kinds.get(kind, kinds.drone)
	var result: float = spec.boostBlast if blast and boosted else spec.blast if blast else spec.boostDirect if boosted else spec.direct
	if attack_slot == "light":
		result = minf(1, result * 2)
	elif attack_slot == "heavy":
		result = minf(1, result * 3)
	return result

static func critical_factors(height_difference: float) -> Dictionary:
	var strength := CombatMath.altitude_strength(height_difference)
	var altitude: Dictionary = Content.constants.ALTITUDE
	if height_difference > 0:
		return {"rate": 1 - altitude.ATK_CRIT_RATE * strength, "damage": 1 - altitude.ATK_CRIT_DMG * strength}
	return {"rate": 1 + altitude.RCV_CRIT_RATE * strength, "damage": 1 + altitude.RCV_CRIT_DMG * strength}

static func suppression_strength(height_difference: float) -> float:
	if height_difference <= 0:
		return 0.0
	var strength := CombatMath.altitude_strength(height_difference)
	return Content.constants.HIGH_SUP.FLOOR + (1 - Content.constants.HIGH_SUP.FLOOR) * strength if strength > 0 else 0.0

static func miss_probability(dodge: float, suppression: float, unbalanced: bool, weather_penalty: float = 0.0) -> float:
	var probability: float = 1 - (1 - clampf(dodge, 0, Content.constants.EVASION.P_MAX)) * (1 - Content.constants.HIGH_SUP.HIT * suppression)
	if unbalanced:
		probability = 1 - (1 - probability) * Content.constants.FLIGHT.UNBAL_ACC_MUL
	return 1 - (1 - probability) * (1 - weather_penalty)
