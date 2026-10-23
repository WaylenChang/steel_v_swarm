extends RefCounted

const Helper = preload("res://tests/status_suite.gd")
const Primitives = preload("res://tests/npc_shot_suite.gd")

class RecordedEffects extends CombatEffects:
	var calls: Array = []
	func _ready() -> void:
		pass
	func explosion(point: Vector3, radius: float, color: int) -> void:
		calls.append({"type": "explosion", "point": [point.x, point.y, point.z], "radius": radius, "color": color})
	func shock(point: Vector3, radius: float, color: int) -> void:
		calls.append({"type": "shock", "point": [point.x, point.y, point.z], "radius": radius, "color": color})
	func embers(point: Vector3, count: int = 8, spread: float = 2) -> void:
		calls.append({"type": "embers", "point": [point.x, point.y, point.z], "count": count, "spread": spread})

class FlatWorld extends BattleWorld:
	func source_height(_x: float, _z: float) -> float:
		return 23.0
	func ground_height(_x: float, _z: float) -> float:
		return 23.0

class FeedbackSimulation extends BattleSimulation:
	var view_draws := 0
	func camera_origin(unit: BattleUnit) -> Vector3:
		return unit.get_meta("eye", unit.position + Vector3.UP * 4)
	func _recoil_next() -> float:
		view_draws += 1
		return .5
	func visible_to_side(unit: BattleUnit, side: String) -> bool:
		return unit.side == side

static func run(h: Node, fixtures: Dictionary) -> void:
	for key: String in ["blastFeedback", "blastReports", "blastProtocol", "localBlastPoints"]:
		if not fixtures.has(key):
			h._check(false, "Regenerate original blast feedback geometry and local/reported trigger references")
			return
	for item: Dictionary in fixtures.blastFeedback:
		var response := BlastFeedback.reaction(BodyPose.vector(item.point), float(item.radius), BodyPose.vector(item.position),
			BodyPose.vector(item.eye), float(item.height), float(item.yaw), item.flying, float(item.trauma), item.hasSide, item.dead)
		h._near(float(response.trauma), item.result.trauma, "Original separate camera distance, energy clamp, squared trauma and saturation")
		h._near(float(response.lift), item.result.lift, "Original ground-only independent upward speed account")
		Primitives._point(h, response.velocity, item.result.velocity, "Original body-centre range, radial impulse and centre-hit backward fallback")
	for item: Dictionary in fixtures.localBlastPoints:
		var at := BlastFeedback.local_point(BodyPose.vector(item.position), float(item.ground), item.tunnel if item.tunnel != null else {})
		Primitives._point(h, at, item.calls[1].point, "Original local projectile closed-tunnel floor versus terrain clamp")
		h._near(BlastFeedback.local_radius(item.radius), item.calls[1].radius, "Original local projectile radius fallback")
	_reports(h, fixtures)
	_authority(h)
	_replica(h)

static func _context(h: Node, authoritative: bool = true) -> FeedbackSimulation:
	var simulation := FeedbackSimulation.new()
	simulation.authoritative = authoritative
	simulation.over = true
	h.add_child(simulation)
	simulation.world = FlatWorld.new()
	simulation.add_child(simulation.world)
	simulation.world.combat_effects = RecordedEffects.new()
	simulation.world.add_child(simulation.world.combat_effects)
	return simulation

static func _actor(simulation: BattleSimulation, peer: int, flying: bool = false) -> BattleUnit:
	var unit := BattleUnit.new()
	unit.entity_id = peer
	unit.peer_id = peer
	unit.character = "t09" if flying else "t01"
	unit.kind = "drone" if flying else "robot"
	unit.flying = flying
	unit.side = "STEEL"
	unit.hp = 100
	unit.shield = 20
	unit.power = 30
	unit.money = 40
	unit.height = 16
	unit.position = Vector3(12, 23, -9)
	unit.set_meta("eye", Vector3(12, 27, -9))
	simulation.add_child(unit)
	unit.camera = Camera3D.new()
	unit.add_child(unit.camera)
	simulation.units[unit.entity_id] = unit
	simulation.pilots[peer] = unit
	return unit

static func _reports(h: Node, fixtures: Dictionary) -> void:
	var simulation := _context(h)
	for item: Dictionary in fixtures.blastReports:
		var source: Dictionary = item.event
		var mine := not source.has("y")
		var event := {"type": "mine_blast" if mine else "boom", "actor": 9, "blast_serial": simulation.blast_event_serial + 1,
			"position": Vector3(source.x, 0 if mine else float(item.ground) + float(source.y), -float(source.z)),
			"radius": source.r, "kami": source.kami, "sam": source.sam}
		simulation.blast_event_serial += 1
		var effects := simulation.world.combat_effects as RecordedEffects
		effects.calls.clear()
		simulation.present_blast(event)
		var visual: Array = item.calls.filter(func(command): return command.type != "blast")
		Helper.compare(h, effects.calls, visual, "Original global boom height default, style, ground ring and kamikaze ember producer order")
		var requests := simulation._blast_requests(event)
		var expected: Array = item.calls.filter(func(command): return command.type == "blast")
		h._check(requests.size() == expected.size(), "One source reported explosion supplies one physical feedback request")
		if requests.size() == 1:
			Primitives._point(h, requests[0].point, expected[0].point, "Authoritative feedback uses the same source explosion point as presentation")
			h._near(float(requests[0].radius), expected[0].radius, "Source feedback reach uses the actual blast radius")
		var count := effects.calls.size()
		simulation.present_blast(event)
		h._check(effects.calls.size() == count, "A repeated global publication cannot allocate another explosion")
	for item: Dictionary in fixtures.blastProtocol:
		simulation.blast_event_serial += 1
		var source: Dictionary = item.event
		var event := {"type": item.native, "actor": 9, "missile": 7, "blast_serial": simulation.blast_event_serial,
			"position": Vector3(source.x, float(item.ground) + float(source.y), -float(source.z)), "radius": source.r}
		var effects := simulation.world.combat_effects as RecordedEffects
		effects.calls.clear()
		simulation.present_blast(event)
		Helper.compare(h, effects.calls, item.calls.filter(func(command): return command.type != "blast"),
			"Actual source missile blast/interception/reflection reports retain their distinct default colour and geometry")
	simulation.free()

static func _authority(h: Node) -> void:
	var simulation := _context(h)
	var ground := _actor(simulation, 1)
	var air := _actor(simulation, 2, true)
	air.side = "SWARM"
	var bot := _actor(simulation, 3)
	bot.is_bot = true
	var dead := _actor(simulation, 4)
	dead.hp = 0
	var spectator := _actor(simulation, 5)
	spectator.side = ""
	var detached := _actor(simulation, 6)
	detached.camera.free()
	detached.camera = null
	ground.velocity = Vector3(1.25, 2.5, 3.75)
	ground.impulse_velocity = Vector2(.25, -.5)
	air.velocity = Vector3(-1, -2, -3)
	var resources := _resources(simulation)
	var point := Vector3(13, 24, -9)
	var ground_response := BlastFeedback.reaction(point, 12, ground.position, simulation.camera_origin(ground), ground.height, ground.yaw, false, 0)
	var air_response := BlastFeedback.reaction(point, 12, air.position, simulation.camera_origin(air), air.height, air.yaw, true, 0)
	simulation._publish_blast_event({"type": "boom", "actor": ground.entity_id, "position": point, "radius": 12.0})
	h._check(ground.velocity == Vector3(1.25, 2.5, 3.75), "Reported feedback waits for the shared publication boundary")
	simulation.flush_blast_feedback()
	var impulse: Vector3 = ground_response.velocity
	h._check(ground.velocity.distance_to(Vector3(1.25 + impulse.x, 2.5 + float(ground_response.lift), 3.75 + impulse.z)) < .0001
		and ground.impulse_velocity.distance_to(Vector2(.25 + impulse.x, -.5 + impulse.z)) < .0001,
		"Ground feedback updates horizontal impulse and vy lift without treating discarded source vel.y as flight velocity")
	h._check(air.velocity.distance_to(Vector3(-1, -2, -3) + air_response.velocity) < .0001, "Flying feedback applies the complete three-axis source impulse")
	h._near(ground.recoil.trauma, ground_response.trauma, "Reported feedback combines with the existing owner recoil trauma")
	h._near(air.recoil.trauma, air_response.trauma, "Blast feedback affects the opposing faction as well as self/friendly bodies")
	for skipped: BattleUnit in [bot, dead, spectator, detached]:
		h._check(skipped.velocity == Vector3.ZERO and skipped.recoil.trauma == 0 and skipped.blast_applied_serial == 0,
			"Only a live human primary view receives client-origin blast feedback")
	var velocities := [ground.velocity, ground.impulse_velocity, air.velocity]
	var trauma := [ground.recoil.trauma, air.recoil.trauma]
	var draws := simulation.view_draws
	simulation.flush_blast_feedback()
	h._check(velocities == [ground.velocity, ground.impulse_velocity, air.velocity] and trauma == [ground.recoil.trauma, air.recoil.trauma]
		and simulation.view_draws == draws and draws == 6, "Publication settles once and refreshes one private shake sample per changed primary pilot")
	var remote_before := air.velocity
	simulation._publish_local_blast(ground, point, 12)
	h._check(air.velocity == remote_before, "Local predicted impact feedback is restricted to its human shooter")
	var report: Dictionary = simulation.events.back()
	var own := simulation.snapshot(1)
	var other := simulation.snapshot(2)
	h._check(own.events.any(func(event): return event.type == "local_blast") and not other.events.any(func(event): return event.type == "local_blast"),
		"Immediate local impact metadata stays in the shooter's private snapshot stream")
	h._check(not simulation.snapshot(0).events.any(func(event): return event.type == "local_blast"), "An unbound/public view cannot receive another pilot's local impact packet")
	h._check(other.events.any(func(event): return event.type == "boom"), "Global boom events survive shooter fog filtering")
	h._check(int(own.blast_serial) == int(report.blast_serial), "Owner recoil snapshot carries the applied feedback watermark")
	h._check(resources == _resources(simulation), "Feedback changes velocity/trauma only, without damage, spending, outcomes, time or combat RNG")
	simulation.free()

static func _replica(h: Node) -> void:
	var simulation := _context(h, false)
	var pilot := _actor(simulation, Session.player_id())
	var initial := _resources(simulation)
	var recoil := pilot.recoil.snapshot()
	recoil.pitch = .1
	recoil.trauma = .5
	var local := {"type": "local_blast", "actor": pilot.entity_id, "only_peer": pilot.peer_id, "position": Vector3(12, 24, -9),
		"radius": 12.0, "blast_serial": 4, "body_serial": 7, "feedback_recoil": recoil}
	var effects := simulation.world.combat_effects as RecordedEffects
	simulation.receive_body_events([local.merged({"only_peer": pilot.peer_id + 10}, true)], 10)
	h._check(effects.calls.is_empty() and pilot.blast_received_serial == 0, "Foreign local impact packets cannot consume replay state or change the private view")
	simulation.receive_body_events([local], 10)
	h._check(effects.calls.size() == 1 and pilot.recoil.pitch == .1 and pilot.blast_received_serial == 4,
		"Immediate owner impact delivers fresh trauma and visual response before the full snapshot")
	simulation.present_world_events([local])
	h._check(effects.calls.size() == 1, "RPC then snapshot fallback cannot duplicate the local explosion")
	var old := pilot.recoil.snapshot()
	old.pitch = 0
	h._check(not simulation.apply_owner_recoil({"blast_serial": 3, "recoil": old}) and pilot.recoil.pitch == .1,
		"An older full snapshot cannot rewind freshly delivered recoil/trauma")
	var latest := pilot.recoil.snapshot()
	latest.pitch = .2
	h._check(simulation.apply_owner_recoil({"blast_serial": 5, "recoil": latest}), "A newer authority snapshot supersedes immediate owner feedback")
	latest.pitch = .3
	h._check(simulation.apply_owner_recoil({"blast_serial": 5, "recoil": latest}) and pilot.recoil.pitch == .3,
		"Ordinary decay snapshots remain valid when their feedback watermark is unchanged")
	simulation.present_blast({"type": "boom", "actor": pilot.entity_id, "blast_serial": 8, "position": Vector3(12, 24, -9), "radius": 12.0})
	local.blast_serial = 6
	simulation.present_blast(local)
	h._check(effects.calls.size() >= 3 and pilot.blast_received_serial == 6, "Immediate and global feedback use independent bounded replay streams across native channels")
	var before := effects.calls.size()
	simulation.present_blast(local)
	h._check(effects.calls.size() == before and simulation.pending_blast_feedback.is_empty(), "Replica visual replay never enqueues or repeats authority impulses")
	h._check(initial == _resources(simulation) and pilot.velocity == Vector3.ZERO and pilot.impulse_velocity == Vector2.ZERO,
		"Replica feedback cannot settle damage, body motion, resources or combat RNG")
	simulation.free()

static func _resources(simulation: BattleSimulation) -> Array:
	var result: Array = [simulation.clock, simulation.rng.state, simulation.projectile_rng.state, simulation.over, simulation.winner]
	for pilot: BattleUnit in simulation.pilots.values():
		result.append([pilot.hp, pilot.shield, pilot.power, pilot.money, pilot.ammo.duplicate(true)])
	return result
