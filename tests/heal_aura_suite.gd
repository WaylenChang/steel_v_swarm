extends RefCounted

const Helper = preload("res://tests/status_suite.gd")

class AuraSimulation extends Helper.SettlementSimulation:
	pass

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("statusHealAuras"):
		h._check(false, "Regenerate original heal-aura lifecycle references")
		return
	for item: Dictionary in fixtures.statusHealAuras:
		var simulation := context(h, item)
		var owner: BattleUnit = simulation.units[1]
		var definition := Content.ability(item.character, "def", item.level)
		simulation._cast_effect(owner, definition, Vector3.ZERO, item.fraction)
		compare_frame(h, simulation, owner, item.initial)
		for frame: Dictionary in item.frames:
			simulation.clock = frame.now
			if frame.recast:
				simulation._cast_effect(owner, definition, Vector3.ZERO, item.fraction)
			if frame.zeroHpTarget:
				var target: BattleUnit = simulation.units[2]
				target.hp = 0
				target.upgrade_survivor = true
			if frame.die:
				owner.hp = 0
				# Exercise the real dead-owner cleanup before aura settlement.
				simulation._tick_ability_states(frame.delta)
			else:
				simulation._tick_heal_auras(frame.delta)
			compare_frame(h, simulation, owner, frame.result)
		Helper.check_draws(h, simulation, int(item.draws))
		simulation.free()
	var replica_case: Dictionary = fixtures.statusHealAuras.filter(func(item): return item.level == 1 and item.fraction == 1 and not item.inputs[0].boss)[0]
	_replica_guard(h, replica_case)
	print("HEAL_AURA_REFERENCE_PASS programs=", fixtures.statusHealAuras.size())

static func context(h: Node, item: Dictionary) -> AuraSimulation:
	var simulation := AuraSimulation.new()
	h.add_child(simulation)
	simulation.set_physics_process(false)
	simulation.clock = 10
	for input: Dictionary in item.inputs:
		var unit := Helper.actor(simulation, input)
		unit.effect_radius = input.effect_radius
		unit.peer_id = int(input.peer)
		unit.special = {"boss": input.boss, "boss_segment": int(input.boss_segment), "neutral": input.neutral}
		simulation.pilots.erase(unit.entity_id)
		if input.clone:
			unit.special.role = "clone"
		elif input.hero:
			simulation.pilots[unit.peer_id] = unit
	return simulation

static func _replica_guard(h: Node, item: Dictionary) -> void:
	var simulation := context(h, item)
	var owner: BattleUnit = simulation.units[1]
	simulation._cast_effect(owner, Content.ability(item.character, "def", item.level), Vector3.ZERO)
	simulation.events.clear()
	var before: Array = simulation.units.values().map(func(unit): return [unit.hp, unit.shield])
	var aura := owner.heal_aura.duplicate(true)
	var seed := simulation.rng.state
	simulation.authoritative = false
	simulation.clock += .125
	simulation._tick_heal_auras(.125)
	h._check(simulation.units.values().map(func(unit): return [unit.hp, unit.shield]) == before,
		"Replica aura ticks cannot settle health or shields")
	h._check(owner.heal_aura == aura and simulation.events.is_empty() and simulation.rng.state == seed,
		"Replica aura ticks cannot consume lifetime, publish reports or advance combat RNG")
	simulation.free()

static func compare_frame(h: Node, simulation: BattleSimulation, owner: BattleUnit, expected: Dictionary) -> void:
	var actors: Array = []
	for unit: BattleUnit in simulation.units.values():
		actors.append({"id": unit.entity_id, "hp": unit.hp, "shield": unit.shield, "dead": not unit.alive()})
	Helper.compare(h, actors, expected.actors, "Original aura representative/entity visits, BOSS source gate, neutral/radius/HP/death filters")
	h._check(not owner.heal_aura.is_empty() == bool(expected.active), "Original aura inclusive expiry, replacement and owner-death lifetime")
	if expected.active:
		Helper.compare(h, owner.heal_aura, expected.aura, "Original accepted aura rates, side and interruption fraction")
	var reports: Array = []
	for event: Dictionary in simulation.events:
		if event.type not in ["heal_aoe", "heal_aura_start", "heal_aura_end"]:
			continue
		var public := ActorSnapshot.event(event, false)
		var point: Variant = public.get("position")
		reports.append({"type": public.type, "actor": public.actor, "peer": public.get("peer"), "side": public.side,
			"radius": public.get("radius"), "duration": public.get("duration"),
			"position": [point.x, point.y, point.z] if point is Vector3 else null})
	Helper.compare(h, reports, expected.events, "Original public heal-area/start/end event payloads and exactly-once ordering")
	simulation.events.clear()
