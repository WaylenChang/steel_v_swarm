extends RefCounted

const StatusHelper = preload("res://tests/status_suite.gd")

class NpcSimulation extends BattleSimulation:
	var queries: Array = []
	var blocked_id := 0

	func visible_to(_observer: BattleUnit, target: BattleUnit) -> bool:
		queries.append(target.entity_id)
		return target.entity_id != blocked_id and not target.get_meta("hidden", false)

	func _missile_target_altitude(unit: BattleUnit) -> float:
		return unit.position.y

	func _height_reference(_unit: BattleUnit) -> float:
		return 0.0

static func run(h: Node, fixtures: Dictionary) -> void:
	for key: String in ["npcGates", "npcSideGates", "npcSelection", "npcCache", "creepMath", "creepSettlement", "creepPurchases", "deadPurchases"]:
		if not fixtures.has(key):
			h._check(false, "Regenerate original NPC/economy oracle: " + key)
			return
	for item: Dictionary in fixtures.npcGates + fixtures.npcSideGates:
		var blocked := NpcRules.blocked(item.observer, item.target, item.profile, item.weapon, item.distance, item.altitude_factor, item.fog)
		h._check(blocked == bool(item.blocked), "Original NPC faction, control, altitude, AA, lob and fog eligibility")
	for item: Dictionary in fixtures.npcSelection:
		var simulation := context(h)
		var observer := npc(simulation, 1, item.kind, "STEEL", Vector3.ZERO)
		for input: Dictionary in item.actors:
			var unit := npc(simulation, int(input.id), input.kind, input.side, vector(input.position), "t05" if input.hero else "")
			if input.hologram:
				unit.special.role = "hologram"
		simulation.weather_fog = item.fog
		simulation.blocked_id = int(item.blocked)
		if item.grid:
			simulation._begin_npc_index()
		var profile: Dictionary = {"range": Content.constants.UNITS.base.guns.range} if item.kind == "base" else Content.constants.UNITS[item.kind]
		var target := simulation._npc_acquire(observer, profile)
		h._check((target.entity_id if target != null else 0) == int(item.target), "Original weighted target, hologram attraction and tick-grid ties")
		StatusHelper.compare(h, simulation.queries, item.queries, "Only improving target candidates pay for source LOS queries")
		simulation.free()
	for item: Dictionary in fixtures.npcCache:
		var simulation := context(h)
		var observer := npc(simulation, 1, "soldier", "STEEL", Vector3.ZERO)
		var first := npc(simulation, 2, "soldier", "SWARM", Vector3(0, 0, -40))
		var other := npc(simulation, 3, "soldier", "SWARM", Vector3(0, 0, -80))
		for step: Dictionary in item.steps:
			simulation.clock = step.now
			first.position = vector(step.first)
			other.position = vector(step.other)
			other.hp = step.other_hp
			other.set_meta("hidden", step.hidden)
			var target := simulation._npc_acquire_cached(observer, Content.constants.UNITS.soldier)
			h._check((target.entity_id if target != null else 0) == int(step.target), "Original held target validity and periodic preference rescan")
			h._check(observer.npc_cache_phase == int(step.phase), "Original per-actor target phase assignment")
		simulation.free()
	for item: Dictionary in fixtures.creepMath:
		h._near(NpcRules.creep_multiplier(item.level), item.multiplier, "Original clamped logarithmic creep curve")
		h._near(NpcRules.creep_damage_taken(item.multiplier, item.armor, item.penetration), item.taken, "Original per-penetration NPC durability conversion")
	for item: Dictionary in fixtures.creepSettlement:
		var simulation := context(h)
		var attacker := npc(simulation, 1, "robot" if item.heroAttack else "soldier", "STEEL", Vector3.ZERO, "t05" if item.heroAttack else "")
		var target := npc(simulation, 2, "tank", "SWARM", Vector3(0, 0, -15))
		target.hp = 10000
		target.armor = 30
		target.creep_multiplier = NpcRules.creep_multiplier(item.level)
		simulation.damage(attacker, target, {"type": "gun", "pen": item.penetration}, 80, false, {}, false)
		h._near(10000 - target.hp, item.loss, "Creep durability applies to non-hero attackers while hero damage remains unupgraded")
		simulation.free()
	for item: Dictionary in fixtures.creepPurchases:
		var simulation := context(h)
		var owner := npc(simulation, 1, "robot", "STEEL", Vector3.ZERO, "t05")
		owner.money = item.money
		owner.hp = 0 if item.dead else 10000
		for key: String in owner.upgrades:
			owner.upgrades[key] = int(Content.constants.ECON.UPGRADES[key].max) if item.maxed else 0
		simulation.creep_upgrades = {"STEEL": [int(item.level), 0], "SWARM": [0, 0]}
		h._check(simulation.buy_creep(owner, int(item.lane)) == bool(item.accepted), "Original all-tracks, lane, funds, cap and dead-purchase eligibility")
		h._near(owner.money, item.balance, "Creep upgrade settles one authority payment")
		StatusHelper.compare(h, simulation.creep_upgrades.STEEL, item.levels, "Creep upgrades belong to the faction lane")
		simulation.free()
	for item: Dictionary in fixtures.deadPurchases:
		var simulation := context(h)
		var owner := npc(simulation, 1, "robot", "STEEL", Vector3(999, 0, 999), "t05")
		owner.hp = 0 if item.dead else 400
		owner.shield = 0 if item.dead else 80
		owner.max_hp = roundf(Content.constants.UNITS.robot.hp * Content.heroes.t05.mods.hp)
		owner.max_shield = roundf(Content.constants.UNITS.robot.shield * Content.heroes.t05.mods.sp)
		owner.money = 10000
		owner.score = 1000
		owner.armor = 0
		h._check(simulation.buy(owner, item.track) == bool(item.accepted), "Source purchases are available remotely and during respawn")
		for property: String in ["hp", "max_hp", "shield", "max_shield", "armor", "money"]:
			h._near(float(owner.get(property)), float(item[property]), "Original upgrade settlement: " + property)
		h._check(owner.upgrades[item.track] == int(item.level), "Original track level update")
		if item.dead:
			h._check(not owner.alive(), "Buying durability during respawn must not revive the hero")
		simulation.free()
	authority_boundaries(h)
	print("NPC_REFERENCE_PASS gates=", fixtures.npcGates.size(), " selection=", fixtures.npcSelection.size(),
		" cache=", fixtures.npcCache.size(), " creep=", fixtures.creepSettlement.size(), " purchases=", fixtures.creepPurchases.size())

static func authority_boundaries(h: Node) -> void:
	var simulation := context(h)
	var owner := npc(simulation, 1, "robot", "STEEL", Vector3.ZERO, "t05")
	for key: String in owner.upgrades:
		owner.upgrades[key] = int(Content.constants.ECON.UPGRADES[key].max)
	owner.money = 10000
	owner.hp = 0
	simulation.creep_upgrades = {"STEEL": [0, 0], "SWARM": [0, 0]}
	for malformed: String in ["", "null", "0x1", "0.5", "NaN"]:
		simulation.action(owner.peer_id, "buy_creep", malformed)
		h._check(simulation.creep_upgrades.STEEL == [0, 0], "Native action requires an explicit decimal integer lane and cannot coerce malformed input to lane zero")
	simulation.action(owner.peer_id, "buy_creep", "1")
	h._check(simulation.creep_upgrades.STEEL == [0, 1], "A dead pilot can purchase a shared lane upgrade through the authority action")
	var balance := owner.money
	simulation.authoritative = false
	h._check(not simulation.buy_creep(owner, 0) and owner.money == balance, "Replica cannot settle faction purchases")
	simulation.free()

static func context(h: Node) -> NpcSimulation:
	var simulation := NpcSimulation.new()
	h.add_child(simulation)
	simulation.set_physics_process(false)
	simulation.clock = 10
	simulation.world = BattleWorld.new()
	simulation.add_child(simulation.world)
	return simulation

static func npc(simulation: BattleSimulation, id: int, kind: String, side: String, point: Vector3, character: String = "") -> BattleUnit:
	if kind == "decoy_beacon":
		var unit := BattleUnit.new()
		simulation.add_child(unit)
		unit.entity_id = id
		unit.kind = kind
		unit.side = side
		unit.hp = 10000
		unit.position = point
		simulation.units[id] = unit
		return unit
	return StatusHelper.actor(simulation, {"id": id, "character": character, "kind": kind, "side": side, "position": [point.x, point.y, point.z], "hp": 10000, "max_hp": 10000})

static func vector(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])
