extends RefCounted

const CarrierHelper = preload("res://tests/carrier_suite.gd")
const Helper = preload("res://tests/status_suite.gd")
const LaunchTrig = preload("res://scripts/source_carrier_trig.gd")

class ControllerSimulation extends CarrierHelper.CarrierSimulation:
	var trace: Array = []
	var active_carrier := 0

	func _finish_carrier_step(unit: BattleUnit, outcome: Dictionary) -> void:
		var previous := active_carrier
		active_carrier = unit.entity_id
		super._finish_carrier_step(unit, outcome)
		active_carrier = previous

	func _publish_blast_event(event: Dictionary) -> void:
		if event.type == "boom":
			trace.append({"type": "boom", "carrier": active_carrier, "point": point(event.position),
				"radius": event.radius, "side": event.side, "sam": event.get("sam", false),
				"kami": event.get("kami", false), "hyper": event.get("hyper", false)})
		super._publish_blast_event(event)

	func _cast_effect(owner: BattleUnit, definition: Dictionary, center: Vector3, fraction: float = 1.0,
			once: bool = true, count_override: int = -1) -> void:
		trace.append({"type": "effect", "carrier": active_carrier, "owner": owner.entity_id,
			"point": point(center), "fraction": fraction, "count": count_override, "fx": definition.fx})
		super._cast_effect(owner, definition, center, fraction, once, count_override)

	func blast(owner: BattleUnit, definition: Dictionary, center: Vector3, _friendly: bool = false,
			_relative: bool = false, level: int = -1, _npc_damage: float = NAN) -> void:
		trace.append({"type": "blast", "carrier": active_carrier, "owner": owner.entity_id,
			"point": point(center), "damage": definition.dmg, "level": level})

	func _carrier_arrive(unit: BattleUnit, center: Vector3, fraction: float, count_override: int = -1) -> void:
		var before := events.size()
		super._carrier_arrive(unit, center, fraction, count_override)
		if events.size() > before and events.back().type == "ability_arrive":
			var event: Dictionary = events.back()
			trace.append({"type": "arrival", "carrier": unit.entity_id, "owner": event.actor,
				"point": point(event.position), "fraction": fraction, "fx": event.fx})

	static func point(value: Vector3) -> Array:
		return [value.x, value.y, value.z]

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("carrierControllers") or not fixtures.has("carrierLaunchMath"):
		h._check(false, "Regenerate original mixed carrier controller references")
		return
	for row: Dictionary in fixtures.carrierLaunchMath:
		h._check(same_double(LaunchTrig.sine(row.angle), row.sin), "Original carrier launch sine retains exact scalar bits")
		h._check(same_double(LaunchTrig.cosine(row.angle), row.cos), "Original carrier launch cosine retains exact scalar bits")
		h._check(same_double(CarrierRules.hypot2(row.x, row.z), row.distance), "Original carrier launch length retains exact scalar bits")
	for item: Dictionary in fixtures.carrierControllers:
		var simulation := context(h, item)
		var expected_random := SourceRng.new(42)
		var previous_draws := compare_frame(h, simulation, item.initial, expected_random, 0)
		var affected: BattleUnit = simulation.units[int(item.affected)]
		for frame: Dictionary in item.frames:
			simulation.clock = frame.now
			if frame.dead:
				affected.hp = 0
			if frame.missing:
				simulation.pilots.erase(affected.peer_id)
			if frame.restore:
				simulation.pilots[affected.peer_id] = affected
			simulation._tick_carriers(frame.delta)
			previous_draws = compare_frame(h, simulation, frame.result, expected_random, previous_draws)
		simulation.free()
	# Replica ticks must never move authoritative carriers or consume delivery RNG.
	var replica := context(h, fixtures.carrierControllers[0])
	var before := snapshot(replica)
	var seed := replica.rng.state
	replica.authoritative = false
	replica.clock += .125
	replica._tick_carriers(.125)
	h._check(snapshot(replica) == before and replica.rng.state == seed, "Replica cannot advance carrier rosters, deliveries or combat RNG")
	replica.free()
	print("CARRIER_CONTROLLER_REFERENCE_PASS programs=", fixtures.carrierControllers.size())

static func same_double(actual: float, expected: float) -> bool:
	var a := PackedByteArray()
	var b := PackedByteArray()
	a.resize(8)
	b.resize(8)
	a.encode_double(0, actual)
	b.encode_double(0, expected)
	return a == b

static func context(h: Node, item: Dictionary) -> ControllerSimulation:
	var simulation := ControllerSimulation.new()
	h.add_child(simulation)
	simulation.set_physics_process(false)
	simulation.recording = false
	simulation.clock = 10
	simulation.world = BattleWorld.new()
	simulation.add_child(simulation.world)
	for input: Dictionary in item.inputs:
		var owner := Helper.actor(simulation, input)
		simulation.pilots.erase(owner.entity_id)
		owner.peer_id = int(input.peer)
		simulation.pilots[owner.peer_id] = owner
		owner.yaw = .7
		if input.superLevel != null:
			owner.upgrades["super"] = int(input.superLevel)
	for launch: Dictionary in item.launches:
		var owner: BattleUnit = simulation.units[int(launch.owner)]
		simulation._launch_carriers(owner, Content.ability(owner.character, "atk", launch.level),
			Vector3(launch.point[0], launch.point[1], launch.point[2]), Vector3(launch.origin[0], launch.origin[1], launch.origin[2]))
	simulation.events.clear()
	return simulation

static func compare_frame(h: Node, simulation: ControllerSimulation, expected: Dictionary, random: SourceRng, previous: int) -> int:
	var actual := snapshot(simulation)
	CarrierHelper.compare(h, actual.carriers, expected.carriers, "Original active carrier entities and scalar trajectory across roster presence changes")
	CarrierHelper.compare(h, actual.rosters, expected.rosters, "Original active owner roster membership and reverse traversal order")
	CarrierHelper.compare(h, actual.trace, expected.trace, "Original mixed producer completion/effect/blast/report order and indivisible delivery budgets")
	for draw in range(previous, int(expected.draws)):
		random.next()
	h._check(simulation.rng.state == random.state, "Original per-frame launch and strike scatter consume the exact shared combat RNG stream")
	for item: Dictionary in expected.carriers:
		if simulation.units.has(int(item.id)):
			var unit: BattleUnit = simulation.units[int(item.id)]
			h._check(unit.position == Vector3(item.position[0], item.position[1], item.position[2]),
				"Carrier native position is the captured scalar trajectory at the scene boundary")
	return int(expected.draws)

static func snapshot(simulation: ControllerSimulation) -> Dictionary:
	var carriers: Array = []
	var rosters: Array = []
	for unit: BattleUnit in simulation.units.values():
		if unit.is_pilot():
			rosters.append({"owner": unit.entity_id, "active": unit.carrier_ids.filter(func(id): return simulation.units.has(id) and simulation.units[id].alive())})
		if simulation.carrier_states.has(unit.entity_id):
			var state: Dictionary = simulation.carrier_states[unit.entity_id]
			carriers.append({"id": unit.entity_id, "kind": unit.kind, "position": [state.x, state.y, -state.z],
				"yaw": state.yaw, "hp": unit.hp})
	var result := {"carriers": carriers, "rosters": rosters, "trace": simulation.trace.duplicate(true)}
	simulation.trace.clear()
	simulation.events.clear()
	simulation.pending_blast_feedback.clear()
	return result
