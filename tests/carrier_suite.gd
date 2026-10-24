extends RefCounted

const StatusHelper = preload("res://tests/status_suite.gd")

class CarrierSimulation extends BattleSimulation:
	var deliveries: Array = []
	var strikes: Array = []
	var recording := true

	func _missile_target_altitude(unit: BattleUnit) -> float:
		return unit.position.y

	func _unit_level(_unit: BattleUnit) -> int:
		return 0

	func _cast_effect(owner: BattleUnit, definition: Dictionary, center: Vector3, fraction: float = 1.0, once: bool = true, count_override: int = -1) -> void:
		if recording:
			deliveries.append({"owner": owner.entity_id, "fx": definition.fx, "x": center.x, "z": -center.z, "fraction": fraction, "count": count_override})
		else:
			super._cast_effect(owner, definition, center, fraction, once, count_override)

	func blast(_owner: BattleUnit, definition: Dictionary, point: Vector3, _friendly: bool = false,
			_relative: bool = false, level: int = -1, _npc_damage: float = NAN) -> void:
		strikes.append({"x": point.x, "z": -point.z, "y": point.y, "level": level, "damage": definition.dmg})

	func _apply_cc(_owner: BattleUnit, _added: Dictionary, _center: Vector3, _radius: float) -> void:
		pass

class LifecycleSimulation extends CarrierSimulation:
	var order: Array = []
	var arrivals: Array = []

	func _publish_blast_event(event: Dictionary) -> void:
		order.append("boom")
		super._publish_blast_event(event)

	func _carrier_arrive(_unit: BattleUnit, point: Vector3, fraction: float, count_override: int = -1) -> void:
		order.append("arrival")
		arrivals.append({"x": point.x, "z": -point.z, "fraction": fraction, "count": count_override})

static func run(h: Node, fixtures: Dictionary) -> void:
	for key: String in ["carrierLaunch", "carrierMotion", "carrierOrigin", "carrierArrival", "carrierMath", "carrierStrike", "carrierInterceptions"]:
		if not fixtures.has(key):
			h._check(false, "Regenerate original carrier oracle: " + key)
			return
	for item: Dictionary in fixtures.carrierMath:
		var count := CarrierRules.parts(item.kind, item.effect)
		h._check(count == int(item.count), "Original chassis shares divisible budgets without splitting indivisible statuses")
		for index in range(item.parts.size()):
			h._check(CarrierRules.integer_part(item.total, count, index) == int(item.parts[index]), "Original cumulative rounding of integer delivery budgets")
	for item: Dictionary in fixtures.carrierOrigin:
		var simulation := context(h)
		var owner := pilot(simulation, "s01")
		if not item.missing:
			npc(simulation, 2, "tower", "STEEL", Vector3(25, 0, 30), 0 if item.dead else 100)
			npc(simulation, 3, "base", "STEEL", Vector3(15, 0, 30), 100)
			npc(simulation, 4, "tower", "SWARM", Vector3(20, 0, 30), 100)
		h._check(simulation._ability_origin(owner, item.slot).distance_to(vector(item.position)) < 0.00001, "Original nearest living allied fort and stable equal-distance tie")
		simulation.free()
	for item: Dictionary in fixtures.carrierLaunch:
		var simulation := context(h)
		var owner := pilot(simulation, item.character)
		if item.has("superLevel"):
			owner.side = "SUPER"
			owner.upgrades["super"] = int(item.superLevel)
		else:
			owner.upgrades.atk = int(item.level) - 1
		simulation._launch_carriers(owner, Content.ability(item.character, "atk", float(item.level)), vector(item.point), vector(item.origin))
		h._check(owner.carrier_ids.size() == item.actors.size(), "Original dedicated and chassis-default carrier count")
		for index in range(mini(owner.carrier_ids.size(), item.actors.size())):
			var id: int = owner.carrier_ids[index]
			var unit: BattleUnit = simulation.units[id]
			var expected: Dictionary = item.actors[index]
			compare(h, simulation.carrier_states[id], expected.state, "Original carrier launch state")
			for property: String in ["hp", "max_hp", "radius", "height"]:
				h._near(float(unit.get(property)), float(expected[property]), "Original carrier source-derived " + property)
			h._check(not unit.is_hero() and not unit.is_pilot() and unit.camera == null and unit.path_follower == null,
				"Native delivery actors are shootable NPCs without player cameras or creep movement")
			h._check(unit.collision_layer == 0 and unit.hit_area.collision_layer == 2, "Carrier flight is independent of world movement collision while remaining a physical shot target")
		StatusHelper.check_draws(h, simulation, int(item.draws))
		simulation.free()
	for item: Dictionary in fixtures.carrierMotion:
		var simulation := LifecycleSimulation.new()
		h.add_child(simulation)
		simulation.set_physics_process(false)
		# The source trajectory oracle uses an unattached flat weather surface.
		# Completion publication still requires a world for relative audio height.
		simulation.world = BattleWorld.new()
		simulation.add_child(simulation.world)
		var owner := pilot(simulation, "s01")
		var carrier := BattleUnit.new()
		carrier.entity_id = 2
		carrier.kind = item.kind
		carrier.side = owner.side
		carrier.hp = 100
		carrier.special = {"role": "carrier", "owner_id": owner.entity_id, "owner_peer": owner.peer_id}
		carrier.hit_area = Area3D.new()
		carrier.add_child(carrier.hit_area)
		simulation.add_child(carrier)
		simulation.units[carrier.entity_id] = carrier
		owner.carrier_ids.append(carrier.entity_id)
		var state: Dictionary = item.initial.duplicate(true)
		simulation.carrier_states[carrier.entity_id] = state
		var alive := true
		for step: Dictionary in item.steps:
			var outcome := {"arrivals": [], "remove": false}
			if not (item.kind == "hyper" and item.scenario == "owner_missing"):
				outcome = CarrierRules.advance(state, step.delta, step.now, step.target if step.target != null else {})
			alive = alive and not outcome.remove
			compare(h, state, step.state, "Original scalar carrier trajectory and fixed-step ordering")
			compare(h, outcome.arrivals, step.arrivals, "Original delivery location, fraction and integer budget")
			h._check(alive == bool(step.alive), "Original carrier arrival, timeout and deferred launch lifecycle")
			carrier.position = Vector3(state.x, state.y, -state.z)
			simulation._finish_carrier_step(carrier, outcome)
			var reports: Array = []
			var points: Array = []
			for event: Dictionary in simulation.events:
				reports.append({"radius": event.radius, "sam": event.sam, "kami": event.kami, "hyper": event.hyper})
				var point: Vector3 = event.position
				points.append([point.x, point.y, point.z])
			compare(h, reports, step.reports, "Original carrier completion report flags and radius")
			compare(h, points, step.points, "Original carrier event-time explosion points")
			compare(h, simulation.order, step.order, "Original completion boom precedes delivery effects")
			compare(h, simulation.arrivals, step.arrivals, "Authority carrier dispatch retains each delivery budget")
			h._check(simulation.units.has(carrier.entity_id) == bool(step.alive), "Authority completion removes only the finished carrier")
			simulation.events.clear()
			simulation.pending_blast_feedback.clear()
			simulation.order.clear()
			simulation.arrivals.clear()
		simulation.free()
	for item: Dictionary in fixtures.carrierArrival:
		var simulation := context(h)
		var owner := pilot(simulation, "s01")
		simulation._launch_carriers(owner, Content.ability("s01", "atk"), Vector3(200, 0, -140), Vector3(-80, 0, 30))
		var id: int = owner.carrier_ids[0]
		simulation.carrier_states[id].fraction = item.fraction
		simulation.carrier_states[id].count = int(item.budget) if item.budget != null else -1
		if item.dead:
			owner.hp = 0
		if item.missing:
			simulation.pilots.erase(owner.peer_id)
		simulation._carrier_arrive(simulation.units[id], Vector3(30, 0, 40), item.fraction, int(item.budget) if item.budget != null else -1)
		compare(h, simulation.deliveries, item.calls, "Source shared arrival accepts a dead owner but rejects a missing owner")
		simulation.free()
	for item: Dictionary in fixtures.carrierStrike:
		var simulation := context(h)
		simulation.recording = false
		var owner := pilot(simulation, item.character)
		simulation._cast_effect(owner, Content.ability(item.character, "atk"), Vector3(30, 0, 40), item.fraction, true,
			int(item.count) if item.count != null else -1)
		compare(h, simulation.strikes, item.hits, "Original arrival integer budget feeds the shared strike effect without an extra explosion")
		StatusHelper.check_draws(h, simulation, int(item.draws))
		simulation.free()
	for item: Dictionary in fixtures.carrierInterceptions:
		var simulation := context(h)
		var owner := pilot(simulation, item.character)
		var enemy := StatusHelper.actor(simulation, {"id": 99, "character": "t05", "side": "SWARM", "position": [0, 0, 0], "hp": 400, "max_hp": 1000})
		enemy.money = 100
		simulation._launch_carriers(owner, Content.ability(item.character, "atk"), Vector3(200, 0, -140), Vector3(-80, 0, 30))
		var id: int = owner.carrier_ids[0]
		var unit: BattleUnit = simulation.units[id]
		simulation.damage(enemy, unit, {"type": "gun"}, unit.hp + 1, false, {}, false)
		h._check(simulation.units.has(id) == bool(item.present) and not simulation.carrier_states.has(id), "Authority interception removes the actor, flight state and owner roster")
		h._near(enemy.money - 100, item.earned, "Original carrier interception bounty")
		h._near(enemy.score, item.score, "Original carrier interception battle score")
		h._check(simulation.deliveries.size() == int(item.effects) and simulation.strikes.size() == int(item.blasts), "Shot-down carriers cancel their effect budget without generic damage")
		var reports: Array = []
		for event: Dictionary in simulation.events:
			if event.type in ["die", "boom"]:
				reports.append({"type": event.type, "kind": event.get("kind"), "radius": event.get("radius"),
					"sam": bool(event.get("sam", false)), "kami": bool(event.get("kami", false))})
		StatusHelper.compare(h, reports, item.reports, "Original carrier death/fracture report order, absent decoy blast and SAM style")
		simulation.free()
	print("CARRIER_REFERENCE_PASS launch=", fixtures.carrierLaunch.size(), " motion=", fixtures.carrierMotion.size(),
		" arrival=", fixtures.carrierArrival.size(), " strikes=", fixtures.carrierStrike.size(), " interception=", fixtures.carrierInterceptions.size())

static func context(h: Node) -> CarrierSimulation:
	var simulation := CarrierSimulation.new()
	h.add_child(simulation)
	simulation.set_physics_process(false)
	simulation.clock = 10
	simulation.world = BattleWorld.new()
	simulation.add_child(simulation.world)
	return simulation

static func pilot(simulation: BattleSimulation, character: String) -> BattleUnit:
	var unit := StatusHelper.actor(simulation, {"id": 1, "character": character, "side": "STEEL", "position": [20, 12, 30], "hp": 400, "max_hp": 1000})
	unit.yaw = 0.7
	return unit

static func npc(simulation: BattleSimulation, id: int, kind: String, side: String, point: Vector3, health: float) -> BattleUnit:
	return StatusHelper.actor(simulation, {"id": id, "kind": kind, "character": "", "side": side, "position": [point.x, point.y, point.z], "hp": health, "max_hp": 100})

static func compare(h: Node, actual: Variant, expected: Variant, label: String) -> void:
	if expected is Dictionary:
		h._check(actual is Dictionary, label + " dictionary")
		if not actual is Dictionary:
			return
		for key: String in expected:
			h._check(actual.has(key), label + " field: " + key)
			if actual.has(key):
				compare(h, actual[key], expected[key], label + ": " + key)
	elif expected is Array:
		h._check(actual is Array and actual.size() == expected.size(), label + " array size")
		if actual is Array:
			for index in range(mini(actual.size(), expected.size())):
				compare(h, actual[index], expected[index], label)
	elif expected is float or expected is int:
		var tolerance := maxf(0.00001, absf(float(expected)) * 0.000001)
		h._check(absf(float(actual) - float(expected)) < tolerance, label + " source numeric tolerance")
	else:
		h._check(actual == expected, label + " source value")

static func vector(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])
