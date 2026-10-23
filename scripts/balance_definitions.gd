class_name BalanceDefinitions
extends RefCounted

var preferences: BalancePreferences
var rules: Dictionary = {}
var initial_speed := 1.0
var range_mid: Dictionary = {}
var building: Dictionary = {}
var trail_seconds := 0.0
var reach_metres := 0.0
var bot_roles: BalanceBotRoles

func configure(profile: BalancePreferences, metadata: Dictionary) -> void:
	preferences = profile
	rules = metadata
	initial_speed = preferences.multiplier("speed")
	range_mid = {}
	building = rules.baseBuilding.duplicate(true)
	trail_seconds = 0.0
	reach_metres = 0.0
	bot_roles = BalanceBotRoles.new()
	bot_roles.configure(self)
	for slot: String in ["light", "heavy"]:
		var total := 0.0
		var count := 0
		for character: String in Content.heroes:
			var reach := _range(character, slot)
			if reach > 0:
				total += log(reach)
				count += 1
		range_mid[slot] = exp(total / count) if count > 0 else 1.0
	_calibrate_buildings()

func _range(character: String, slot: String) -> float:
	var hero: Dictionary = Content.heroes[character]
	var sight := float(Content.constants.UNITS[hero.kind].get("sight", 0)) * preferences.multiplier("sight")
	var cap := INF if sight == 0 else sight * float(Content.constants.GAME.AIM_SIGHT_MULT if slot == "heavy" else 1.0) * float(Content.constants.GAME.RANGE_SIGHT_F)
	return minf(float(hero[slot].range) * float(Content.constants.HEROIC.range), cap)

func _core_weapon(character: String, slot: String, level: float) -> Dictionary:
	var definition := Content.weapon(character, slot, level).duplicate(true)
	var base_range := float(Content.heroes[character].weapons[slot][0].range)
	var reach := _range(character, slot)
	# Original geometric midpoints are fixed at module initialization.
	var mobility := pow(initial_speed / preferences.multiplier("speed"), float(Content.constants.MOB_BUDGET.K))
	var range_factor := pow(float(range_mid[slot]) / float(rules.rangeMid[slot]) * base_range / reach, float(Content.constants.RANGE_BUDGET.K)) if reach > 0 else 1.0
	definition.dmg *= mobility * range_factor * preferences.curve("hw" if slot == "heavy" else "lw", level) * preferences.multiplier("dmg")
	definition.range = reach * preferences.multiplier("range")
	definition.rate *= preferences.multiplier("rate")
	definition.rate0 *= preferences.multiplier("rate")
	definition.reload *= preferences.multiplier("cd")
	definition.vs.building = building[character][slot]
	return definition

func weapon(character: String, slot: String, level: float = 1) -> Dictionary:
	var definition := _core_weapon(character, slot, level)
	var count := mini(int(Content.constants.FIRE_RATE.BURST_MAX), maxi(1, floori(float(definition.rate0) / float(definition.rate) + .5)))
	definition.burst = {"count": count, "gap": 1.0 / (float(definition.rate) * count)}
	var top := _core_weapon(character, slot, 4)
	var sub_damage := float(top.dmg) * float(Content.constants.FAN_SUB_F) * float(definition.vs.building)
	definition.fanMaxBuildingHits = maxi(1, mini(int(definition.fanSubs), floori(float(rules.expectedBuildingDamage[slot]) / maxf(1, sub_damage) + .5)))
	var height := float(Content.constants.TARGET_H.tower) * float(Content.constants.ALTITUDE.TIERS)
	var reach := float(definition.range) * CombatMath.altitude_range(definition, height) * float(Content.constants.RANGE_TOL)
	definition.projectile.flightCap = ShotHistory.flight_seconds(definition, reach, -height)
	definition.projectile.fuel = float(definition.projectile.flightCap) * float(Content.constants.SEEK.CHASE_F)
	# Source heavyMpCost uses the magazine cycle, without stat_mpCost.
	definition.heavyMp = floorf((float(definition.reload) + float(definition.mag) / float(definition.rate)) / float(definition.mag) * float(Content.constants.ECON.HEAVY_MP_PER_CD) + .5) if slot == "heavy" else 0.0
	return definition

func ability(character: String, slot: String, level: float = 1) -> Dictionary:
	var definition := Content.ability(character, slot, level).duplicate(true)
	var curve := preferences.curve(slot, level)
	definition.dmg *= curve * preferences.multiplier("dmg")
	definition.heal *= curve
	definition.cd *= preferences.multiplier("cd")
	definition.mp *= preferences.multiplier("mpCost")
	definition.range *= preferences.multiplier("range")
	return definition

func speed(character: String, flying: bool = false) -> float:
	return float(Content.heroes[character].flySpeed if flying else Content.heroes[character].speed) * preferences.multiplier("speed")

func charge(level: float) -> float:
	var economy: Dictionary = Content.constants.ECON
	return (float(economy.CHARGE_MIN) + (1.0 - float(economy.CHARGE_MIN)) * level / float(economy.UPGRADES.ch.max)) * preferences.curve("ch", level)

func shot_trail_seconds() -> float:
	if trail_seconds > 0:
		return trail_seconds
	for character: String in Content.heroes:
		for slot: String in ["light", "heavy"]:
			var definition := weapon(character, slot)
			trail_seconds = maxf(trail_seconds, float(definition.projectile.fuel if definition.trajectory == "fnf" else definition.projectile.flightCap))
	return trail_seconds

func combat_reach() -> float:
	if reach_metres > 0:
		return reach_metres
	reach_metres = float(Content.constants.UNITS.tower.get("range", 0))
	var height := float(Content.constants.TARGET_H.tower) * float(Content.constants.ALTITUDE.TIERS)
	var weapon_factor := CombatMath.altitude_range({}, height) * float(Content.constants.RANGE_TOL)
	for character: String in Content.heroes:
		for slot: String in ["light", "heavy"]:
			reach_metres = maxf(reach_metres, _range(character, slot) * preferences.multiplier("range") * weapon_factor)
		for slot: String in ["def", "atk"]:
			for level in range(1, 5):
				reach_metres = maxf(reach_metres, float(ability(character, slot, level).range))
	reach_metres = maxf(reach_metres, float(rules.hyperMaxArc))
	return reach_metres

func view_curve() -> Dictionary:
	var knee := combat_reach() * float(Content.constants.CURVE.KNEE_F)
	var horizon := combat_reach() * float(Content.constants.DOF.NEAR_F)
	var radius := maxf(1, (horizon * horizon - knee * knee) / (2.0 * float(rules.curveEye)))
	return {"knee": knee, "inverse": 1.0 / (2.0 * radius)}

func bot_profile(character: String) -> Dictionary:
	return bot_roles.profile(character)

func _building_dps(character: String, slot: String, level: float) -> float:
	var definition := _core_weapon(character, slot, level)
	var damage := float(CombatMath.shield_split(definition, definition.dmg, 0).toHp)
	damage *= CombatMath.vs_multiplier(definition, "tower")
	damage *= CombatMath.armor_multiplier(Content.constants.UNITS.tower.armor, definition.pen)
	return CombatMath.weapon_dps(definition, damage)

func _set_building(character: String, slot: String, value: float) -> void:
	building[character][slot] = floorf(minf(float(Content.constants.BUILDING_VS_CAP), value) * 1000.0 + .5) / 1000.0

func _calibrate_buildings() -> void:
	var rows: Array[Dictionary] = []
	var level_total := 0.0
	for slot: String in ["light", "heavy"]:
		for character: String in Content.heroes:
			var top := 1 + int(Content.constants.ECON.UPGRADES["lw" if slot == "light" else "hw"].max)
			var damage := _building_dps(character, slot, 1)
			var top_damage := _building_dps(character, slot, top)
			rows.append({"character": character, "slot": slot, "top": top, "damage": damage})
			level_total += top_damage
	var original_mean := level_total / rows.size()
	for slot: String in ["light", "heavy"]:
		var total := 0.0
		var count := 0
		for row: Dictionary in rows:
			if row.slot == slot and row.damage > 0:
				total += log(float(row.damage))
				count += 1
		if count == 0:
			continue
		var midpoint := exp(total / count)
		for row: Dictionary in rows:
			if row.slot == slot and row.damage > 0:
				_set_building(row.character, slot, float(building[row.character][slot]) * pow(midpoint / float(row.damage), float(Content.constants.BUILD_DPS.K)))
	for iteration in range(int(Content.constants.BUILD_DPS.LEVEL_ITERS)):
		var current := 0.0
		for row: Dictionary in rows:
			current += _building_dps(row.character, row.slot, row.top)
		var factor := original_mean / (current / rows.size())
		if not absf(factor - 1.0) > .000001:
			break
		for row: Dictionary in rows:
			_set_building(row.character, row.slot, float(building[row.character][row.slot]) * factor)
