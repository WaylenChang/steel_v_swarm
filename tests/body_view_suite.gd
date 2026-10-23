extends RefCounted

const Helper = preload("res://tests/status_suite.gd")

class FrameLayers extends StructureLayers:
	var current: Dictionary = {}
	func tunnel_at(_point: Vector2) -> Dictionary:
		return current.get("tunnel", {})

class FrameWorld extends BattleWorld:
	var current: Dictionary = {}
	var calls: Array = []
	func _init() -> void:
		layers = FrameLayers.new()
	func source_height(_x: float, _z: float) -> float:
		return float(current.ground)
	func visual_deck(_x: float, _z: float) -> Variant:
		return current.get("deck")
	func ground_query(x: float, z: float) -> float:
		calls.append(["ground", x, z])
		return source_height(x, z)
	func visual_surface(point: Vector3) -> float:
		calls.append(["surface", point.x, point.z, point.y])
		return float(current.surface)
	func flight_query(x: float, z: float) -> float:
		calls.append(["flight", x, z])
		return visual_flight_surface(x, z)
	func lane_query(x: float, z: float) -> Variant:
		calls.append(["lane", x, z])
		return current.get("lane")
	func deck_query(x: float, z: float) -> Variant:
		calls.append(["deck", x, z])
		return visual_deck(x, z)
	func nearest_query(now: float, previous: Vector3) -> Variant:
		calls.append(["nearest", now, previous.x, previous.y, previous.z])
		if not current.has("nearest"):
			return null
		return Vector3(60, 7, -20) if current.get("nearestSelf", false) else BodyPose.vector(current.nearest)

static func run(h: Node, fixtures: Dictionary) -> void:
	for key: String in ["bodyViewFrames", "laneSurfaceProfiles"]:
		if not fixtures.has(key):
			h._check(false, "Regenerate original remote body frame and lane surface references")
			return
	for trace: Dictionary in fixtures.bodyViewFrames:
		var motion := BodyViewMotion.new()
		motion.place(BodyPose.vector(trace.initial))
		var carrier := CarrierBodyMotion.new()
		var world := FrameWorld.new()
		h.add_child(world)
		var altitude := 0.0
		var aim: Variant = null
		for index in range(trace.steps.size()):
			var step: Dictionary = trace.steps[index]
			world.current = step
			(world.layers as FrameLayers).current = step
			world.calls.clear()
			altitude = float(step.get("heroY", altitude))
			if step.has("aim"):
				aim = step.aim
			var state := {"id": trace.id, "kind": trace.kind, "side": trace.side, "hero": trace.hero, "flies": trace.flies,
				"static": trace["static"], "target": BodyPose.vector(step.target), "reported_yaw": step.reportedYaw,
				"heroY": altitude, "aim": aim, "carrier": trace.kind in ["kami", "hyper", "decoy"], "waterY": step.get("water"), "padY": step.get("pad")}
			var plan := motion.advance(step.delta, step.now, int(step.frame), BodyPose.vector(step.camera), state,
				index == 0 or step.get("snap", false), {"ground": world.ground_query, "surface": world.visual_surface,
					"flight": world.flight_query, "lane": world.lane_query, "deck": world.deck_query}, world.nearest_query, carrier)
			h._check(not plan.is_empty(), "Original valid body view frame has a presentation plan")
			if plan.is_empty():
				continue
			h._check(motion.position.distance_to(BodyPose.vector(step.position)) < .00003, "Original remote planar interpolation, cached terrain and exact lift height")
			h._near(motion.yaw, step.yaw, "Original body facing follows movement, live fire memory, nearest enemy and wrap easing")
			h._near(motion.pitch, step.pitch, "Original carrier local pitch after remote position interpolation")
			h._check(plan.due == step.result.due, "Original body LOD measures the previous rendered position")
			h._check(plan.previous.distance_to(BodyPose.vector(step.result.previous)) < .00003, "Original first-heavy-frame displacement baseline")
			Helper.compare(h, world.calls, step.queries, "Original surface/acquisition query order and cache cadence")
			if step.cached == null:
				h._check(motion.ground == null, "Static bodies do not acquire a moving surface cache")
			else:
				h._near(float(motion.ground), step.cached, "Original accumulated-LOD standing surface cache")
		world.free()
	for trace: Dictionary in fixtures.laneSurfaceProfiles:
		var profile := LaneSurfaceProfile.new()
		var calls: Array = []
		var ground := func(x: float, z: float): return x * .1 + z * .2
		var surface := func(point: Vector3):
			calls.append([point.x, point.z, point.y])
			return maxf(point.x * .1 + point.z * .2, 12.0 if point.y > 10 else 0.0)
		profile.configure(trace.paths, ground, surface)
		Helper.compare(h, profile.lanes, trace.lanes, "Original lane march spacing, endpoint exclusion and ordered duplicate segments")
		Helper.compare(h, calls, trace.queries, "Original sequential lane standing-surface seeds")
		for sample: Dictionary in trace.samples:
			var result: Variant = profile.at(sample.x, sample.z)
			if sample.result == null:
				h._check(result == null, "Original lane query excludes its exact radius and uncovered cells")
			else:
				h._near(float(result), sample.result, "Original strict nearest lane sample and stable cell/tie ordering")
	_live_binding(h)
	_owner_binding(h, fixtures)

static func _owner_binding(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("bodyAuthorityLocomotion") or fixtures.bodyAuthorityLocomotion.is_empty():
		h._check(false, "Regenerate original owner FPV/TPS body frame references")
		return
	var trace: Dictionary = fixtures.bodyAuthorityLocomotion[0]
	var profile: Dictionary = Content.balance.bodies[trace.key]
	var unit := BattleUnit.new()
	h.add_child(unit)
	unit.configure({"id": 1031, "peer": Session.player_id(), "character": profile.character,
		"kind": Content.heroes[profile.character].kind, "side": profile.side, "position": Vector3.ZERO})
	if unit.body_presentation == null:
		h._check(false, "Pack original local body frame scene")
		unit.free()
		return
	var entity := {"hero": true, "heroY": 0.0, "flies": false, "isSelf": true, "df": 0, "sp": 100}
	for index in range(2):
		var step: Dictionary = trace.steps[index]
		entity.merge(step.get("entity", {}), true)
		if step.has("shot"):
			unit.present_body_event({"type": "weapon_fire", "body_serial": index + 1, "slot": step.shot.slot}, step.now)
		unit.body_presentation.frame(step.delta, step.now, index + 1, BodyPose.vector(step.position), step.yaw,
			BodyPose.vector(step.position), entity, step.get("firstPerson", false))
		Helper.compare(h, unit.body_presentation.entity.get("fireFx"), step.fire, "Production owner binding retains original FPV fire history on first TPS entry")
	unit.free()

static func _live_binding(h: Node) -> void:
	var simulation := BattleSimulation.new()
	h.add_child(simulation)
	simulation.set_physics_process(false)
	simulation.authoritative = true
	simulation.world = FrameWorld.new()
	simulation.add_child(simulation.world)
	(simulation.world as FrameWorld).current = {"ground": 0.0, "surface": 4.0}
	var unit := simulation.spawn({"kind": "tank", "side": "STEEL", "position": Vector3(0, 4, 0), "yaw": 2.0, "special": {"body_view_fixture": true}})
	unit.presented_altitude = 0.0
	var camera := Camera3D.new()
	simulation.add_child(camera)
	var resources := [unit.hp, unit.power, unit.npc_cooldown, simulation.rng.state]
	unit.body_presentation.capture_snapshot({"position": unit.global_position, "yaw": unit.yaw, "hp": unit.hp,
		"shield": unit.shield, "hero_y": 0.0}, 10)
	simulation._prime_body_view(unit)
	h._check(unit.body.global_position == Vector3.ZERO and unit.body.global_basis.is_equal_approx(Basis.IDENTITY),
		"Fresh snapshot bodies retain the source ground placement and factory heading before their first rendered frame")
	simulation.present_bodies(.05, 10, 1, camera)
	unit.position.x = 5
	var physical := unit.global_transform
	simulation.present_bodies(.05, 10.03, 2, camera)
	h._check(unit.body.global_position.x == 0, "Offline body presentation cannot consume newer authority positions before its next shared snapshot")
	unit.body_presentation.capture_snapshot({"position": unit.global_position, "yaw": unit.yaw, "hp": unit.hp,
		"shield": unit.shield, "hero_y": 0.0}, 10.05)
	simulation.present_bodies(.05, 10.05, 3, camera)
	h._check(unit.global_transform == physical and unit.body.top_level and unit.body.global_position.x > 0 and unit.body.global_position.x < 5,
		"Source body interpolation moves only its independent rendered graph")
	h._check(resources == [unit.hp, unit.power, unit.npc_cooldown, simulation.rng.state], "Body interpolation and facing cannot settle combat or consume combat RNG")
	simulation.free()
