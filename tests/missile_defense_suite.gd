extends RefCounted

class DefenseSimulation extends BattleSimulation:
	var blasts: Array = []
	var blocked := false

	func _missile_target_altitude(unit: BattleUnit) -> float:
		return unit.position.y

	func _missile_world_position(point: Vector3) -> Vector3:
		return point

	func _unit_level(_unit: BattleUnit) -> int:
		return 0

	func _missile_obstruction(_start: Vector3, _end: Vector3) -> bool:
		return blocked

	func _sync_missile_bodies() -> void:
		pass

	func blast(owner: BattleUnit, definition: Dictionary, point: Vector3, friendly: bool = false,
			_relative: bool = false, level: int = -1, npc_damage: float = NAN) -> void:
		blasts.append({"side": owner.side, "definition": definition, "position": [point.x, point.y, point.z],
			"level": level, "friendly": friendly, "amount": npc_damage})

const StatusHelper = preload("res://tests/status_suite.gd")

static func run(h: Node, fixtures: Dictionary) -> void:
	for key: String in ["missileDefenses", "missileReportGates", "missileSkillIntercepts"]:
		if not fixtures.has(key):
			h._check(false, "Regenerate original missile defense oracle: " + key)
			return
	for item: Dictionary in fixtures.missileDefenses:
		var simulation := context(h)
		simulation.blocked = item.blocked
		for id in item.decoys:
			simulation.hologram_decoys.append(int(id))
		var flight := missile(item.steps[0].before)
		simulation.missiles.assign([flight])
		for step: Dictionary in item.steps:
			simulation.clock = item.now
			sync_actors(simulation, step.actors)
			simulation.events.clear()
			simulation.blasts.clear()
			simulation._tick_missiles(item.delta)
			var label: String = "Original missile defense " + item.name
			h._check(simulation.missiles.size() == (1 if step.alive else 0), label + " removal")
			h._check(int(flight.target) == int(step.after.target), label + " attraction and stable ties")
			h._check(flight.get("lost", false) == bool(step.after.lost), label + " permanent phase loss")
			h._check(flight.position.distance_to(vector(step.after.position)) < 0.001, label + " source motion")
			h._near(flight.ttl, step.after.ttl, label + " TTL first")
			StatusHelper.compare(h, simulation.blasts, step.blasts, label + " raw blast / harmless deflection")
			var reports: Array = simulation.events.filter(func(event): return event.type in ["reflect_hit", "missile_deflect"])
			h._check(reports.size() == step.events.size(), label + " visual event count")
			for index in range(mini(reports.size(), step.events.size())):
				var actual: Dictionary = reports[index]
				var expected: Dictionary = step.events[index]
				h._check(actual.type == expected.type, label + " visual order")
				# Source reflect_hit omits altitude; its paired harmless boom carries altitude.
				var position: Vector3 = actual.position
				if actual.type == "reflect_hit":
					position.y = 0
					h._check(int(actual.actor) == int(expected.actor) and actual.deflected, label + " reflector identity")
				else:
					h._near(actual.radius, expected.radius, label + " visual blast radius")
					h._check(actual.side == expected.side, label + " visual faction")
				h._check(position.distance_to(vector(expected.position)) < 0.001, label + " harmless visual endpoint")
		StatusHelper.check_draws(h, simulation, 0)
		simulation.free()
	for item: Dictionary in fixtures.missileReportGates:
		var simulation := context(h)
		simulation.over = item.over
		var owner := actor(simulation, item.input)
		owner.input_state = {"aim": item.aiming}
		# Even a just-released aim cannot use the ordinary projectile grace window for missiles.
		owner.aim_off_at = simulation.clock
		var flight := {"id": 9, "side": "SWARM", "position": Vector3(0, 20, -10), "hp": 1.0}
		simulation.missiles.assign([flight])
		simulation._damage_missile(owner, Content.weapon(item.character, item.slot, int(item.level)), 9, owner.position)
		h._check(absf((1.0 - flight.hp) - float(item.damage)) < 0.001, "Original hitMissile status/aim gate " + item.gate)
		h._check((not simulation.missiles.is_empty()) == bool(item.alive), "Original blocked report cannot remove missile")
		h._near(owner.money, item.bounty, "Original blocked report cannot pay bounty")
		StatusHelper.check_draws(h, simulation, int(item.draws))
		simulation.free()
	for item: Dictionary in fixtures.missileSkillIntercepts:
		var simulation := context(h)
		var owner := actor(simulation, item.input)
		for input: Dictionary in item.missiles:
			simulation.missiles.append(missile(input))
		simulation._cast_effect(owner, Content.ability(item.character, item.slot, int(item.level)), Vector3(999, 0, 999), item.fraction)
		StatusHelper.compare(h, simulation.missiles.map(func(state): return int(state.id)), item.remaining, "Original planar skill radius/fraction/faction")
		StatusHelper.compare(h, simulation.events.filter(func(event): return event.type == "missile_intercept").map(func(event): return int(event.missile)), item.order, "Original reverse-order skill interception")
		h._near(simulation.vision_until.STEEL, item.vision, "Original skill vision fraction")
		h._near(owner.money, item.bounty, "Skill interception pays no weapon bounty")
		h._check(simulation.blasts.is_empty(), "Skill interception cannot deal explosive damage")
		StatusHelper.check_draws(h, simulation, int(item.draws))
		simulation.free()
	print("MISSILE_DEFENSE_REFERENCE_PASS flight=", fixtures.missileDefenses.size(),
		" reports=", fixtures.missileReportGates.size(), " skills=", fixtures.missileSkillIntercepts.size())

static func context(h: Node) -> DefenseSimulation:
	var simulation := DefenseSimulation.new()
	h.add_child(simulation)
	simulation.set_physics_process(false)
	simulation.authoritative = true
	simulation.clock = 10
	simulation.rng = SourceRng.new(42)
	return simulation

static func actor(simulation: BattleSimulation, input: Dictionary) -> BattleUnit:
	var unit := BattleUnit.new()
	simulation.add_child(unit)
	unit.entity_id = int(input.id)
	unit.peer_id = int(input.id)
	unit.character = input.character
	unit.kind = input.kind
	unit.side = input.side
	unit.hp = input.hp
	unit.position = vector(input.position)
	unit.yaw = input.yaw
	unit.status = input.status.duplicate(true)
	for id in input.get("carriers", []):
		unit.carrier_ids.append(int(id))
	simulation.units[unit.entity_id] = unit
	return unit

static func sync_actors(simulation: BattleSimulation, inputs: Array) -> void:
	for unit: BattleUnit in simulation.units.values():
		unit.free()
	simulation.units.clear()
	for input: Dictionary in inputs:
		actor(simulation, input)

static func missile(input: Dictionary) -> Dictionary:
	var state: Dictionary = input.duplicate(true)
	state.position = vector(input.position)
	state.origin = vector(input.origin)
	return state

static func vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])
