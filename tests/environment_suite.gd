extends RefCounted

const StatusHelper = preload("res://tests/status_suite.gd")

class BurnSimulation extends BattleSimulation:
	var deaths: Array = []

	func _kill_unit(unit: BattleUnit, killer: BattleUnit) -> void:
		deaths.append({"id": unit.entity_id, "killer": killer.entity_id if killer != null else 0})

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("environmentFloods"):
		h._check(false, "Regenerate original flood-zone references before final verification")
		return
	for item: Dictionary in fixtures.environmentFloods:
		var effect := SceneRules.flood_effect(item.floods, Vector2(item.x, 0), item.flying, item.airborne)
		h._check(effect.active == item.active, "Flood zones exempt flight and off-ground traversal")
		h._near(effect.slow, item.speed, "Original flood zone takes the first matching water speed cap")
		h._near(effect.jump, item.jump, "Flood overrides terrain jump with source water square-root factor")
	for key: String in ["environmentHeights", "environmentDryBands", "environmentTriggers", "environmentStates", "environmentTides", "environmentFire", "environmentBurn", "environmentIce", "environmentWetGrid"]:
		if not fixtures.has(key):
			h._check(false, "Regenerate original environment oracle: " + key)
			return
	for item: Dictionary in fixtures.environmentHeights:
		h._near(EnvironmentRules.height_at(PackedFloat32Array(item.heights), int(item.grid), item.bounds, item.x, item.z), item.result, "Original clamped triangular terrain sampling")
	for item: Dictionary in fixtures.environmentDryBands:
		h._check(EnvironmentRules.in_dry_band(item.x, item.z, item.profile) == item.result, "Original dry corridor capsule endpoints and degenerate segments")
	for item: Dictionary in fixtures.environmentTriggers:
		h._check(EnvironmentRules.trigger(int(item.ground), item.waterY, item.foot, item.body, item.frozen) == int(item.result), "Original full immersion and frozen partial immersion")
	for item: Dictionary in fixtures.environmentStates:
		var ground := EnvironmentRules.ground_code(item.height, item.waterY, item.color, item.dry)
		h._check(ground == int(item.ground), "Original height/color/dry-band water-marsh classifier")
		var state := EnvironmentRules.environment(ground, item.waterY, item.foot, item.body, item.frozen, item.flying, item.surface, item.height)
		StatusHelper.compare(h, state, item.state, "Original native fluid/air environment")
		h._near(EnvironmentRules.movement_factor(state, item.frozen), item.speed, "Original shallow-water cap and gradual marsh movement penalty")
		h._near(EnvironmentRules.jump_velocity(state, item.frozen, item.flying), item.jump, "Original player shallow/full/frozen immersion jump composition")
	for item: Dictionary in fixtures.environmentTides:
		h._near(EnvironmentRules.tide(item.hour, item.lunarDay, item.marine), item.result, "Original marine-only semidiurnal lunar tide")
	for item: Dictionary in fixtures.environmentIce:
		var plane: Variant = float(item.waterY) + (float(Content.constants.WATER.SWAMP_BAND) if int(item.ground) == 2 else 0.0) if int(item.ground) > 0 else null
		h._near(EnvironmentRules.ice_surface(item.surface, item.foot, plane, item.frozen), item.floor, "Original frozen surface captures nearby feet and holds submerged floors")
		var ceiling: Variant = EnvironmentRules.ice_ceiling(item.ceiling, item.foot, plane, item.frozen)
		if item.ceilingResult == null:
			h._check(ceiling == null, "Original ice ceiling permits partially emerged escape")
		else:
			h._near(float(ceiling), item.ceilingResult, "Original submerged ice ceiling and existing ceiling priority")
	for item: Dictionary in fixtures.environmentWetGrid:
		h._check(EnvironmentRules.wet_at(item.grid, item.x, item.z) == int(item.result), "Original mirrored wet grid rounding/bounds/validation")
	for item: Dictionary in fixtures.environmentFire:
		h._near(EnvironmentRules.fire_multiplier(item.dynamics), item.result, "Original rain/snow quench then wind fire boost")
	for item: Dictionary in fixtures.environmentBurn:
		var simulation := BurnSimulation.new()
		h.add_child(simulation)
		simulation.set_physics_process(false)
		simulation.clock = 10
		var unit := StatusHelper.actor(simulation, {"id": 1, "character": "t05", "kind": "robot", "side": "STEEL", "position": [0, 0, 0],
			"hp": item.hp, "max_hp": 1000, "shield": item.shield, "max_shield": item.maximumShield})
		var killer := StatusHelper.actor(simulation, {"id": 2, "character": "t05", "kind": "robot", "side": "SWARM", "position": [0, 0, 0]})
		simulation.pilots[2] = killer
		unit.bleed = {"peer": 2}
		unit.buffs.append({"until": 20.0, "mul": {"dmgTaken": item.modifier}})
		if item.protection == "invulnerable":
			unit.special.invulnerable = true
		elif item.protection == "garrison":
			unit.special.garrison = true
		elif item.protection == "iframe":
			unit.status.inv_until = 20.0
		elif item.protection == "phase":
			unit.status.phase_until = 20.0
		simulation._fire_burn(unit, item.amount)
		h._near(unit.hp, item.result.hp, "Original fire/frozen DOT HP account bypasses armor/fluid/phase modifiers")
		h._near(unit.shield, item.result.shield, "Original proportional simultaneous shield burn")
		if item.result.damaged != null:
			h._near(unit.damaged_at, item.result.damaged, "Raw burn stamps combat time")
		else:
			h._near(unit.damaged_at, -100, "Rejected burn preserves combat time")
		StatusHelper.compare(h, simulation.deaths, item.result.deaths, "Raw burn routes through shared death settlement and prior bleed attribution")
		simulation.free()
	print("ENVIRONMENT_REFERENCE_PASS states=", fixtures.environmentStates.size(), " burn=", fixtures.environmentBurn.size())
