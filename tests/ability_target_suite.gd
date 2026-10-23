extends RefCounted

const Helper = preload("res://tests/status_suite.gd")

class AimSimulation extends BattleSimulation:
	var fixture: Dictionary = {}
	var masks: Array = []
	var target := BattleUnit.new()

	func _projectile_ray(_unit: BattleUnit, origin: Vector3, direction: Vector3, reach: float, _pierce: bool = false, mask: int = -1) -> Dictionary:
		masks.append(mask)
		var distance: Variant = fixture.stop if mask == 1 else fixture.target
		var point := origin + direction * (float(distance) if distance != null else reach)
		var hit := {"position": point} if distance != null else {}
		return {"point": point, "hit": hit, "target": target if mask != 1 and distance != null and not fixture.missile else null,
			"missile": 17 if mask != 1 and distance != null and fixture.missile else 0}

class RoutedSimulation extends BattleSimulation:
	var requests: Array = []
	func cast(unit: BattleUnit, slot: String, requested_point: Vector3 = Vector3(INF, INF, INF)) -> bool:
		requests.append({"actor": unit.entity_id, "slot": slot, "point": requested_point})
		return true

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("abilityTarget") or not fixtures.has("abilityAim"):
		h._check(false, "Regenerate original ability input rounding, authority clamping and TPS aim references")
		return
	for fixture: Dictionary in fixtures.abilityTarget:
		var wire := AbilityTarget.wire_point(fixture.presentation[0], fixture.presentation[1])
		h._check(wire.distance_to(Vector2(fixture.wire[0], fixture.wire[1])) < .0001,
			"Original cast input rounds source server coordinates once, including negative half-decimal ties")
		var origin := Vector2(fixture.origin.x, -float(fixture.origin.z))
		var point := AbilityTarget.clamp_point(origin, fixture.reach, Vector2(wire.x, -wire.y))
		h._check(point.distance_to(Vector2(fixture.result[0], fixture.result[1])) < .0001,
			"Authority retains source planar range clamps and ignores a client point for self-centered abilities")
	var simulation := AimSimulation.new()
	h.add_child(simulation)
	simulation.set_physics_process(false)
	var camera := Camera3D.new()
	simulation.add_child(camera)
	var player := BattleUnit.new()
	simulation.add_child(player)
	simulation.target.entity_id = 23
	for fixture: Dictionary in fixtures.abilityAim:
		simulation.fixture = fixture
		simulation.masks.clear()
		player.position = Vector3(0, 0, fixture.cameraDistance)
		var result := simulation.presentation_aim(player, camera, 100, fixture.thirdPerson)
		Helper.compare(h, {"point": [result.point.x, result.point.y, result.point.z],
			"actor": result.target.entity_id if result.target != null else 0, "missile": result.missile}, fixture.result,
			"Original reticle extends TPS range and ignores only a terrain/obstacle stop inside the rear-camera threshold")
		Helper.compare(h, simulation.masks, [1, 2 | 512], "Presentation reuses native geometry and target ray queries without tracing decorative meshes")
	simulation.target.free()
	simulation.free()
	_route(h)

static func _route(h: Node) -> void:
	var simulation := RoutedSimulation.new()
	var unit := BattleUnit.new()
	unit.entity_id = 31
	unit.peer_id = 7
	unit.character = "t01"
	unit.hp = 10
	simulation.authoritative = true
	simulation.pilots[7] = unit
	h._check(simulation.cast_player_at(7, "def", Vector2(12.3, -45.6)), "Authority routes a finite cast point through the stable logical player")
	Helper.compare(h, simulation.requests, [{"actor": 31, "slot": "def", "point": Vector3(12.3, 0, 45.6)}],
		"Source server Z converts once at the shared authority entry")
	for request: Array in [[8, "def", Vector2.ZERO], [7, "heavy", Vector2.ZERO], [7, "atk", Vector2(INF, 0)]]:
		h._check(not simulation.cast_player_at(request[0], request[1], request[2]), "Invalid actor, slot and nonfinite point reject before settlement")
	unit.is_bot = true
	h._check(not simulation.cast_player_at(7, "atk", Vector2.ZERO), "A client cast cannot control a bot seat")
	unit.is_bot = false
	unit.hp = 0
	h._check(not simulation.cast_player_at(7, "atk", Vector2.ZERO), "Dead-body cast rejects before entering ability settlement")
	h._check(simulation.requests.size() == 1, "Rejected cast inputs cannot reach authority ability resource consumption")
	unit.free()
	simulation.free()
