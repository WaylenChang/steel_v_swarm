extends RefCounted

const Helper = preload("res://tests/status_suite.gd")

class FlatWorld extends BattleWorld:
	func ground_height(_x: float, _z: float) -> float:
		return 0

class RouteSimulation extends BattleSimulation:
	var calls: Array = []
	var emitted: Array = []

	func _missile_target_altitude(unit: BattleUnit) -> float:
		return unit.position.y

	func _ability_origin(_unit: BattleUnit, _slot: String) -> Vector3:
		return Vector3(-100, 0, -200)

	func _launch_carriers(_unit: BattleUnit, _definition: Dictionary, point: Vector3, _origin: Vector3) -> void:
		calls.append({"route": "carrier", "point": point})

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
		var accepted := simulation.cast(unit, item.slot, Vector3(120, 0, 70))
		h._check(accepted, "Native authority accepts the complete active source ability roster")
		if not accepted:
			continue
		var route := "channel" if not unit.cast_state.is_empty() else str(simulation.calls[0].route) if not simulation.calls.is_empty() else ""
		h._check(route == item.route, "Original defensive channels and attack hull/carrier routes are exclusive")
		h._check(simulation.calls.size() == (0 if route == "channel" else 1), "Accepted abilities take exactly one authority route")
		if route.is_empty():
			continue
		var point: Vector3 = unit.cast_state.point if route == "channel" else simulation.calls[0].point
		h._check(Vector2(point.x, point.z).distance_to(Vector2(item.point[0], item.point[2])) < .0001,
			"Original route applies clamped targets and self/clone effect centers before dispatch")
		if item.eventPoint != null:
			var event_point: Vector3 = simulation.emitted.back().point
			h._check(Vector2(event_point.x, event_point.z).distance_to(Vector2(item.eventPoint[0], item.eventPoint[2])) < .0001,
				"Native cast publication uses the same effect center as the source event")
	unit.free()
	simulation.world.free()
	simulation.free()
