extends RefCounted

const Helper = preload("res://tests/status_suite.gd")

class FlatWorld extends BattleWorld:
	var reject_origin := false
	func ground_height(x: float, z: float) -> float:
		if reject_origin and x == -100 and z == -200:
			return NAN
		return 0

class RouteSimulation extends BattleSimulation:
	var calls: Array = []
	var emitted: Array = []
	var origin_queries := 0
	var launch_origin := Vector3(-100, 0, -200)

	func _missile_target_altitude(unit: BattleUnit) -> float:
		return unit.position.y

	func _ability_origin(_unit: BattleUnit, _slot: String) -> Vector3:
		origin_queries += 1
		return launch_origin

	func _launch_carriers(_unit: BattleUnit, _definition: Dictionary, point: Vector3, origin: Vector3) -> void:
		calls.append({"route": "carrier", "point": point, "origin": origin})

	func _cast_effect(_unit: BattleUnit, _definition: Dictionary, center: Vector3, _fraction: float = 1.0, _once: bool = true, _count: int = -1) -> void:
		calls.append({"route": "hull", "point": center})

	func _emit_body_event(event: Dictionary) -> void:
		emitted.append(event)

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("abilityRoutes"):
		h._check(false, "Regenerate original complete heroCast ability routing references")
		return
	var simulation := RouteSimulation.new()
	simulation.world = FlatWorld.new()
	var unit := BattleUnit.new()
	unit.entity_id = 1
	unit.peer_id = 1
	var rejected_characters := {}
	for item: Dictionary in fixtures.abilityRoutes:
		var definition := Content.ability(item.character, item.slot, item.level)
		Helper.compare(h, {"fx": definition.fx, "carrier": definition.carrier, "support": definition.support,
			"target": definition.get("target"), "added": definition.add.get("fx") if definition.add is Dictionary else null,
			"unit": definition.get("unit")}, item.definition, "Current source ability roster and routes include every normal and SUPER upgrade")
		h._check(not definition.support, "Current authored abilities never produce removed generic support fleets")
		h._check(simulation._ability_supported(definition, item.character), "Every current source ability has its native mechanic and required imported scenes: " + item.character + "/" + item.slot)
		unit.character = item.character
		unit.kind = Content.heroes[item.character].kind
		unit.side = Content.constants.SUPER_SIDE if item.has("superLevel") else "STEEL"
		unit.upgrades = {"super": item.superLevel} if item.has("superLevel") else {"def": item.level - 1, "atk": item.level - 1}
		unit.position = Vector3(40, 12, 50)
		unit.hp = 100
		unit.power = 100000
		unit.defending = true
		unit.status.clear()
		unit.cooldowns.clear()
		unit.ability_charges.clear()
		unit.cast_state.clear()
		unit.lock_target = 1
		simulation.clock = 10
		simulation.calls.clear()
		simulation.emitted.clear()
		simulation.origin_queries = 0
		var accepted := simulation.cast(unit, item.slot, Vector3(120, 0, 70))
		h._check(accepted, "Native authority accepts the complete active source ability roster")
		if not accepted:
			continue
		var route := "channel" if not unit.cast_state.is_empty() else str(simulation.calls[0].route) if not simulation.calls.is_empty() else ""
		h._check(route == item.route, "Original defensive channels and attack hull/carrier routes are exclusive")
		h._check(simulation.calls.size() == (0 if route == "channel" else 1), "Accepted abilities take exactly one authority route")
		Helper.compare(h, {"power": unit.power, "cooldown": unit.cooldowns.get(item.slot, 0), "defending": unit.defending,
			"castLock": unit.status.get("cast_lock_until", 0), "stealth": unit.status.get("stealth_until", 0)},
			item.state, "Original heroCast power, cooldown, defensive stance, stealth and attack-lock settlement")
		if route.is_empty():
			continue
		var point: Vector3 = unit.cast_state.point if route == "channel" else simulation.calls[0].point
		h._check(Vector2(point.x, point.z).distance_to(Vector2(item.point[0], item.point[2])) < .0001,
			"Original route applies clamped targets and self/clone effect centers before dispatch")
		if item.eventPoint != null:
			var event: Dictionary = simulation.emitted.back()
			var event_point: Vector3 = event.point
			h._check(Vector2(event_point.x, event_point.z).distance_to(Vector2(item.eventPoint[0], item.eventPoint[2])) < .0001,
				"Native cast publication uses the same effect center as the source event")
			h._check(event.type == item.event.type, "Original channel/attack event kind")
			if item.event.castDuration != null:
				h._near(event.cast_duration, item.event.castDuration, "Original attack cast duration includes the zero-duration fallback")
				h._check(event.carrier == bool(item.event.carrier), "Original cast event identifies carrier versus hull delivery")
			if item.event.origin != null:
				var expected := Vector3(item.event.origin[0], item.event.origin[1], item.event.origin[2])
				h._check(event.origin == expected and simulation.calls[0].origin == expected and simulation.origin_queries == 1,
					"Original carrier launch and publication share one captured allied-fort origin")
		if route == "carrier" and not rejected_characters.has(item.character):
			rejected_characters[item.character] = true
			_unavailable_origin(h, simulation, unit, item.slot)
	unit.free()
	simulation.world.free()
	simulation.free()

static func _unavailable_origin(h: Node, simulation: RouteSimulation, unit: BattleUnit, slot: String) -> void:
	for invalid_position: bool in [false, true]:
		simulation.launch_origin = Vector3(NAN, 0, -200) if invalid_position else Vector3(-100, 0, -200)
		simulation.world.reject_origin = not invalid_position
		unit.power = 100000
		unit.defending = true
		unit.cooldowns.clear()
		unit.ability_charges.clear()
		unit.cast_state.clear()
		unit.cast_preview.clear()
		unit.status = {"stealth_until": 30.0}
		simulation.calls.clear()
		simulation.emitted.clear()
		var before := [unit.power, unit.defending, unit.status.duplicate(true), unit.cooldowns.duplicate(true),
			unit.ability_charges.duplicate(true), simulation.rng.state]
		h._check(not simulation.cast(unit, slot, Vector3(120, 0, 70)), "Unavailable carrier launch position or terrain rejects before spending")
		Helper.compare(h, [unit.power, unit.defending, unit.status, unit.cooldowns, unit.ability_charges, simulation.rng.state], before,
			"Rejected carrier launch preserves power, stance, stealth, cooldowns, charges and combat RNG")
		h._check(simulation.calls.is_empty() and simulation.emitted.is_empty() and unit.cast_state.is_empty() and unit.cast_preview.is_empty(),
			"Unavailable carrier origin cannot publish a cast, schedule effects or start a channel")
		simulation.world.reject_origin = false
		simulation.launch_origin = Vector3(-100, 0, -200)
