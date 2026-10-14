class_name NpcRules
extends RefCounted

static func fog_sight(raw_fog: float) -> float:
	var density := clampf((raw_fog - 75) / 25, 0, 1) if raw_fog >= 75 else 0.0
	return 1 - (1 - float(Content.constants.FOG_SIGHT.MIN_MULT)) * density

static func upward_range(height: float) -> float:
	var rule: Dictionary = Content.constants.ALTITUDE
	return 1 + rule.NPC_AA_RANGE * minf(1, height / rule.NPC_AA_REF_DH) if height > 0 else 1.0

static func blocked(observer: Dictionary, target: Dictionary, profile: Dictionary, weapon: Dictionary,
		distance: float, altitude_factor: float, fog: float = 0.0) -> bool:
	if observer.get("blind", false) or target.side == observer.side or target.get("neutral", false) or target.hp <= 0:
		return true
	if target.get("siege_locked", false) or target.get("garrison", false) or target.get("stealth", false) or target.get("hero", false) and target.get("dead", false):
		return true
	var third_observer: bool = observer.side in ["GUER", "MILI"]
	var third_target: bool = target.side in ["GUER", "MILI"]
	if observer.get("third", false) and target.get("third", false):
		return true
	if observer.side == Content.constants.SUPER_SIDE and third_target or third_observer and target.side == Content.constants.SUPER_SIDE:
		return true
	if target.kind in ["drone", "heli", "morph"] and target.altitude > minf(float(profile.range) * 0.9, Content.constants.GAME.GUN_CEIL_M):
		return true
	var gap: float = (target.altitude if target.get("hero", false) else target.sight_height) - (observer.altitude if observer.get("hero", false) else observer.sight_height)
	var reach: float = float(profile.range) * altitude_factor
	if CombatMath.trajectory_class(weapon) == "lob":
		reach = CombatMath.max_horizontal(reach, gap)
	else:
		if not observer.get("hero", false) and weapon.get("npcAa", false):
			reach *= upward_range(gap)
	return distance > reach or distance > reach * fog_sight(fog)

static func score(distance: float, target: Dictionary, weapon: Dictionary) -> float:
	if target.get("hologram", false):
		distance /= 10.0
	if target.get("hero", false):
		distance /= Content.constants.GAME.CREEP_AGGRO_HERO_BIAS
	if not weapon.is_empty():
		distance /= CombatMath.vs_multiplier(weapon, target.kind)
	return distance

static func creep_multiplier(level: float) -> float:
	if is_nan(level) or level == -INF:
		level = 0.0
	elif level == INF:
		level = float(Content.constants.CREEP_UPG.MAX)
	var clamped := clampf(floorf(level), 0, Content.constants.CREEP_UPG.MAX)
	return 1 + log(1 + clamped) / log(10.0)

static func creep_damage_taken(multiplier: float, armor: float, penetration: float) -> float:
	return CombatMath.armor_multiplier(armor * multiplier, penetration) / (multiplier * CombatMath.armor_multiplier(armor, penetration)) if multiplier > 1 else 1.0
