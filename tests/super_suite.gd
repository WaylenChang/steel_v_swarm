extends RefCounted

const Helper = preload("res://tests/status_suite.gd")
const BotTests = preload("res://tests/bot_suite.gd")
const SessionScript = preload("res://scripts/session.gd")

class CountingRandom extends RefCounted:
	var random: SourceRng
	var draws := 0

	func next() -> float:
		draws += 1
		return random.next()

static func run(h: Node, fixtures: Dictionary) -> void:
	for key: String in ["superMath", "superLevels", "superBuys", "superDeaths", "superSummons", "superSpawns", "superCameraAnchors", "superCompanions", "superWeaponGates"]:
		if not fixtures.has(key):
			h._check(false, "Regenerate original super oracle: " + key)
			return
	for item: Dictionary in fixtures.superMath:
		h._near(SuperRules.defense_level(item.value), item.defense, "Original fractional super defense")
		h._near(SuperRules.combat_level(item.value), item.combat, "Original fractional super combat")
		h._near(SuperRules.body_scale(item.value), item.scale, "Original super scale boundaries")
	h._check(SuperRules.body_scale(NAN) == 1 and SuperRules.body_scale(INF) == 1, "Nonfinite super scale keeps valid volumes")
	for item: Dictionary in fixtures.superCameraAnchors:
		var scale_factor := SuperRules.body_scale(item.level)
		var position := Vector3(item.position[0], item.position[1], item.position[2])
		var point := CameraPose.anchor(item.character, position, item.yaw, item.flight, item.charge, scale_factor)
		h._check(point.distance_to(Vector3(item.result[0], item.result[1], item.result[2])) < 0.001, "Original super camera scales eye/forward while crouch stays absolute")
		h._near(CameraPose.eye_height(item.character, item.flight, item.charge, scale_factor), item.eye, "Original super charged-jump eye height")
	for item: Dictionary in fixtures.superLevels:
		var simulation := context(h)
		var unit := actor(simulation, item.character, item.initial)
		for step: Dictionary in item.steps:
			unit.ammo = {"light": 1, "heavy": 2}
			unit.reload_at = {"light": 90, "heavy": 100}
			simulation.events.clear()
			simulation._set_super_level(unit, step.value)
			compare_state(h, unit, step.state, "Original super level recomputation")
			h._check(simulation.events.filter(func(event): return event.type == "buy").size() == int(step.buys), "Original idempotent super level event")
			for slot: String in ["light", "heavy"]:
				Helper.compare(h, Content.weapon(unit.character, slot, unit.combat_level(slot)), step.weapons[slot], "Original super weapon interpolation/extrapolation")
			for slot: String in ["def", "atk"]:
				Helper.compare(h, Content.ability(unit.character, slot, unit.combat_level(slot)), step.abilities[slot], "Original super ability interpolation/extrapolation")
			Helper.compare(h, StatusRules.self_attack_boost(unit.character, unit.combat_level("atk"), unit.combat_level("light"), unit.combat_level("heavy")), step.boost, "Original super self attack compensation")
			h._near(minf(float(Content.constants.ECON.UPGRADES.ch.max), SuperRules.defense_level(unit.upgrades["super"])), step.charge, "Original super charge cap")
		simulation.free()
	for item: Dictionary in fixtures.superBuys:
		var simulation := context(h)
		var unit := actor(simulation, item.character, item.initial)
		h._check(not simulation.buy(unit, "hp") and not simulation.buy_creep(unit, 0), "Super purchases exclude faction tracks and lanes")
		h._check(simulation.buy(unit, "super") == bool(item.success), "Original fixed-price super purchase gate")
		compare_state(h, unit, item.result, "Original super purchase settlement")
		simulation.free()
	for item: Dictionary in fixtures.superDeaths:
		var simulation := context(h)
		var unit := actor(simulation, item.character, item.initial)
		simulation._kill_unit(unit, null)
		compare_state(h, unit, item.result, "Original super death clears wallet and floors level loss")
		var penalties := simulation.events.filter(func(event): return event.type == "penalty")
		h._check(penalties.size() == 1, "One super death penalty event")
		if not penalties.is_empty():
			h._near(penalties[0].amount, item.penalty, "Original super lost wallet report")
		simulation.free()
	for item: Dictionary in fixtures.superSummons:
		var simulation := context(h)
		var owner := actor(simulation, item.character, fixtures.superLevels.filter(func(entry): return entry.character == item.character and not entry.dead)[0].initial)
		simulation._set_super_level(owner, item.value)
		simulation.rng = SourceRng.new(int(item.seed))
		simulation._spawn_autonomous_summons(owner, item.definition, Vector3(50, 0, 30), item.fraction)
		h._check(simulation.autonomous_summons.size() == item.result.size(), "Original super fractional summon count")
		for index in range(mini(simulation.autonomous_summons.size(), item.result.size())):
			var summon: BattleUnit = simulation.units[simulation.autonomous_summons[index]]
			var expected: Dictionary = item.result[index]
			for key: String in ["hp", "max_hp", "armor", "speed"]:
				h._near(summon.get(key), expected[key], "Original super summon creep multiplier/" + key)
			h._near(summon.special.dmg, expected.dmg, "Original super summon damage multiplier")
			h._check(summon.position.distance_to(Vector3(expected.position[0], expected.position[1], expected.position[2])) < 0.001, "Original super summon polar position")
			var health := summon.max_hp
			simulation._set_super_level(owner, 0)
			h._near(summon.max_hp, health, "Existing super summons retain spawn-time strength")
		simulation.free()
	for item: Dictionary in fixtures.superCompanions:
		var simulation := context(h)
		var owner := actor(simulation, item.character, item.initial)
		owner.yaw = 0.4
		simulation._cast_effect(owner, item.definition, Vector3.ZERO, 0.5)
		var ids: Array = simulation.hologram_decoys if item.definition.fx == "decoy_beacon" else owner.clone_ids
		h._check(ids.size() == item.result.size(), "Original super clone/beacon fractional count")
		for index in range(mini(ids.size(), item.result.size())):
			var companion: BattleUnit = simulation.units[ids[index]]
			var expected: Dictionary = item.result[index]
			for key: String in ["hp", "max_hp", "shield", "max_shield", "armor", "radius", "height"]:
				h._near(companion.get(key), expected[key], "Original super companion copied stats and unscaled volume/" + key)
			h._check(companion.position.distance_to(Vector3(expected.position[0], expected.position[1], expected.position[2])) < 0.001, "Original super companion position")
			if item.definition.fx == "decoy_beacon":
				for key: String in ["range", "rate", "until"]:
					h._near(companion.special[key], expected[key], "Original super beacon owner weapon tier/" + key)
		simulation.free()
	for item: Dictionary in fixtures.superSpawns:
		var random := CountingRandom.new()
		random.random = SourceRng.new(int(item.seed))
		var last: Variant = Vector2(item.initialLast[0], item.initialLast[1]) if item.initialLast != null else null
		var per_peer: Dictionary = {}
		var name: String = item.name
		var blocked := func(x: float, z: float): return name == "fallback" or name == "hazards" and x < -150 and z < -100
		for step: Dictionary in item.steps:
			var point := SuperRules.spawn_point(random.next, item.bounds, item.lanes, item.guns, item.blockers, blocked, per_peer.get(step.pid, last))
			h._check(point.distance_to(Vector2(step.result[0], step.result[1])) < 0.001, "Original super random spawn/last-peer/fallback " + name)
			h._check(random.draws == int(step.draws), "Super spawn independent stream preserves source draws " + name)
			last = point
			per_peer[step.pid] = point
	for item: Dictionary in fixtures.superWeaponGates:
		var simulation := context(h)
		var unit := actor(simulation, item.character, item.initial)
		unit.power = item.power
		var definition := Content.weapon(item.character, item.slot, unit.combat_level(item.slot))
		var ready := simulation._weapon_ready(unit, item.slot, definition, true)
		h._check(ready == bool(item.success), "Original super fractional magazine/power gate")
		if ready:
			simulation._spend_weapon_fire(unit, item.slot, definition)
		h._near(unit.ammo[item.slot], item.ammo, "Original super fractional last round may spend below zero")
		h._near(unit.power, item.remainingPower, "Original super heavy power budget")
		h._near(unit.reload_at.get(item.slot, 0), item.reload, "Original super reload starts after the fractional last round")
		h._near(unit.last_fired_at.get(item.slot, 0), item.fireAt, "Original super accepted fire clock")
		simulation.free()
	room_lifecycle(h)
	print("SUPER_REFERENCE_PASS levels=", fixtures.superLevels.size(), " purchases=", fixtures.superBuys.size(), " spawns=", fixtures.superSpawns.size())

static func context(h: Node) -> BattleSimulation:
	var simulation := BattleSimulation.new()
	h.add_child(simulation)
	simulation.set_physics_process(false)
	simulation.clock = 10
	simulation.world = BotTests.FlatWorld.new()
	simulation.add_child(simulation.world)
	simulation.match_stats.SUPER = {"kills": 0, "deaths": 0, "creepKills": 0, "assists": 0}
	return simulation

static func actor(simulation: BattleSimulation, character: String, state: Dictionary) -> BattleUnit:
	var unit := BattleUnit.new()
	simulation.add_child(unit)
	unit.configure({"id": 1, "peer": 1, "side": "SUPER", "character": character, "kind": Content.heroes[character].kind, "position": Vector3.ZERO})
	for key: String in ["hp", "max_hp", "shield", "max_shield", "armor", "money"]:
		unit.set(key, state[key])
	unit.upgrades["super"] = int(state.level)
	unit.ammo = state.ammo.duplicate()
	unit.reload_at = state.reload.duplicate()
	unit.refresh_body_scale()
	simulation.units[1] = unit
	simulation.pilots[1] = unit
	simulation.next_id = 2
	return unit

static func compare_state(h: Node, unit: BattleUnit, state: Dictionary, label: String) -> void:
	for key: String in ["hp", "max_hp", "shield", "max_shield", "armor", "money", "radius", "height"]:
		h._near(unit.get(key), state[key], label + "/" + key)
	h._check(int(unit.upgrades["super"]) == int(state.level), label + "/level")
	h._near(unit.combat_level("light"), state.combat, label + "/combat")
	h._check(unit.ammo == state.ammo and unit.reload_at == state.reload, label + "/lazy weapon resources")

static func room_lifecycle(h: Node) -> void:
	for size in range(1, 6):
		var session := SessionScript.new()
		h.add_child(session)
		session.active = true
		session.config = {"super": true, "team_size": size}
		session.roster = [{"peer": 1, "side": "SUPER", "character": "s09", "bot": false}]
		session.start_battle()
		h._check(session.started and session.roster.size() == size * 2 + 1, "Super room has one human plus both full Bot factions")
		h._check(session.roster.filter(func(player): return player.side == "SUPER" and not player.bot).size() == 1, "One super seat")
		var count := session.roster.size()
		session.start_battle()
		h._check(session.roster.size() == count, "Super launch does not append duplicate Bots")
		session.free()
