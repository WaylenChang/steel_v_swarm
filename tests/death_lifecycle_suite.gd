extends RefCounted

const Helper = preload("res://tests/status_suite.gd")

class SpawnWorld extends BattleWorld:
	var source_position := Vector3.ZERO
	var source_heading := 0.0

	func spawn_position(_side: String, _slot: int = 0, _flying: bool = false) -> Vector3:
		return source_position

	func spawn_heading(_side: String, _slot: int) -> float:
		return source_heading

class DeathSimulation extends Helper.SettlementSimulation:
	var weather_calls := 0

	func _tick_weather(_delta: float) -> void:
		weather_calls += 1

	func _tick_environment(_delta: float) -> void:
		pass

	func _begin_npc_index() -> void:
		pass

	func _tick_missiles(_delta: float) -> void:
		pass

class EndingBrain extends RefCounted:
	var simulation: BattleSimulation

	func update(_delta: float) -> void:
		simulation._kill_unit(simulation.units[2], simulation.units[1])

static func run(h: Node, fixtures: Dictionary) -> void:
	for key: String in ["deathBurns", "respawnFrames", "deathOutcomes"]:
		if not fixtures.has(key):
			h._check(false, "Regenerate original death/fire/respawn references: " + key)
			return
	for item: Dictionary in fixtures.deathBurns:
		var simulation := context(h, item.inputs)
		var target: BattleUnit = simulation.units[1]
		if item.killer != "none":
			simulation._apply_hit_elements(simulation.units[2], item.element, target)
			simulation.events.clear()
		simulation._fire_burn(target, item.amount)
		Helper.compare(h, {"target": actor_state(target),
			"killer_money": simulation.units[2].money if item.killer != "none" else 0,
			"stats": simulation.match_stats, "events": reports(simulation)}, item.result,
			"Original fire eligibility, simultaneous HP/shield loss, elemental-owner credit and terminal settlement")
		Helper.check_draws(h, simulation, int(item.draws))
		simulation.free()
	for item: Dictionary in fixtures.respawnFrames:
		var simulation := context(h, item.inputs)
		simulation.simulation_tick = int(item.initialTick)
		var world := SpawnWorld.new()
		world.source_position = Vector3(item.spawn.position[0], item.spawn.position[1], item.spawn.position[2])
		world.source_heading = item.spawn.yaw
		for side: String in item.bases:
			var point: Array = item.bases[side]
			world.bases[side] = Vector3(point[0], point[1], point[2])
		simulation.world = world
		simulation.add_child(world)
		var target: BattleUnit = simulation.units[1]
		simulation._fire_burn(target, 100000)
		Helper.compare(h, {"target": actor_state(target), "events": reports(simulation)}, item.killed,
			"Original lethal fire records the current death tick and preserves timed pickup state")
		simulation.clock = item.start
		simulation.next_wave = 1e9
		simulation.next_airdrop = 1e9
		for frame: Dictionary in item.frames:
			simulation._tick_authority(frame.delta)
			Helper.compare(h, {"delta": frame.delta, "clock": simulation.clock, "tick": simulation.simulation_tick,
				"target": actor_state(target), "events": reports(simulation),
				"trail": target.position_trail.map(func(point): return point.at)}, frame,
				"Original full-tick death snapshot barrier, inclusive respawn deadline, affix retention and final history sampling")
			if target.alive():
				h._near(target.position.y, item.spawn.position[1], "Original respawn relative hover altitude")
		Helper.check_draws(h, simulation, int(item.draws))
		simulation.free()
	for item: Dictionary in fixtures.deathOutcomes:
		var simulation := context(h, item.inputs)
		simulation.simulation_tick = int(item.initialTick)
		simulation.next_wave = 1e9
		simulation.next_airdrop = 1e9
		var world := SpawnWorld.new()
		for side: String in item.bases:
			var point: Array = item.bases[side]
			world.bases[side] = Vector3(point[0], point[1], point[2])
		simulation.world = world
		simulation.add_child(world)
		var brain := EndingBrain.new()
		brain.simulation = simulation
		simulation.units[1].is_bot = true
		simulation.bot_brains[1] = brain
		simulation._tick_authority(.125)
		Helper.compare(h, {"clock": simulation.clock, "tick": simulation.simulation_tick, "over": simulation.over,
			"winner": simulation.winner, "weather_calls": simulation.weather_calls}, item.result,
			"Original room bot result stops clock, weather and subsequent combat settlement")
		simulation.free()
	var replica := context(h, fixtures.deathBurns[0].inputs)
	var victim: BattleUnit = replica.units[1]
	victim.hp = 50
	victim.upgrade_survivor = false
	var before := actor_state(victim)
	var stats := replica.match_stats.duplicate(true)
	replica.authoritative = false
	replica._fire_burn(victim, 100000)
	replica.respawn(victim)
	h._check(actor_state(victim) == before and replica.match_stats == stats and replica.events.is_empty(),
		"Replica cannot settle fire, death, respawn resources or reports")
	replica.free()
	print("DEATH_LIFECYCLE_REFERENCE_PASS burns=", fixtures.deathBurns.size(), " respawns=", fixtures.respawnFrames.size(), " outcomes=", fixtures.deathOutcomes.size())

static func context(h: Node, inputs: Array) -> DeathSimulation:
	var simulation := DeathSimulation.new()
	h.add_child(simulation)
	simulation.set_physics_process(false)
	simulation.clock = 10
	simulation.simulation_tick = 5
	for input: Dictionary in inputs:
		var unit: BattleUnit
		if input.character.is_empty() and input.kind == "base":
			unit = BattleUnit.new()
			simulation.add_child(unit)
			unit.entity_id = int(input.id)
			unit.kind = input.kind
			unit.side = input.side
			unit.hp = input.hp
			unit.max_hp = input.max_hp
			simulation.units[unit.entity_id] = unit
		else:
			unit = Helper.actor(simulation, input)
		simulation.pilots.erase(unit.entity_id)
		unit.peer_id = int(input.peer)
		if unit.is_hero():
			simulation.pilots[unit.peer_id] = unit
		unit.money = input.money
		unit.upgrade_survivor = input.hp <= 0 and not input.dead
		unit.hit_area = Area3D.new()
		unit.add_child(unit.hit_area)
		for key: String in input.affixes:
			var definition: Dictionary = Content.constants.AFFIXES[key]
			var modifiers := {}
			for property: String in ["reload", "dmgTaken", "killHeal", "bounty"]:
				if definition.has(property):
					modifiers[property] = definition[property]
			unit.buffs.append({"until": input.affixes[key], "mul": modifiers, "affix": key})
		if input.aura != null:
			unit.heal_aura = input.aura.duplicate(true)
	return simulation

static func actor_state(unit: BattleUnit) -> Dictionary:
	var affixes := {}
	for buff: Dictionary in unit.buffs:
		if not str(buff.get("affix", "")).is_empty():
			affixes[buff.affix] = buff.until
	var ammo := {}
	for slot: String in ["light", "heavy"]:
		ammo[slot] = unit.ammo.get(slot, Content.weapon(unit.character, slot, unit.combat_level(slot)).mag)
	return {"hp": unit.hp, "shield": unit.shield, "power": unit.power, "dead": not unit.alive(),
		"deaths": unit.deaths, "death_tick": unit.death_tick, "respawn_at": unit.respawn_at if not unit.alive() else 0,
		"money": unit.money, "score": unit.score, "damaged_at": unit.damaged_at,
		"aura": not unit.heal_aura.is_empty(), "affixes": affixes, "ammo": ammo}

static func reports(simulation: BattleSimulation) -> Array:
	var result: Array = []
	for event: Dictionary in simulation.events:
		if event.type in ["die", "penalty", "respawn", "heal_aura_end"]:
			result.append({"type": event.type, "peer": simulation.units[int(event.actor)].peer_id,
				"amount": event.get("amount") if event.type == "penalty" else null})
	simulation.events.clear()
	return result
