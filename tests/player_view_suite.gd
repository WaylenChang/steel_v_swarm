extends RefCounted

const Helper = preload("res://tests/status_suite.gd")
const ViewTests = preload("res://tests/view_suite.gd")
const ControlsTests = preload("res://tests/controls_suite.gd")
const OcclusionTests = preload("res://tests/view_occlusion_suite.gd")

class ReferenceSimulation extends BattleSimulation:
	func _weapon_surface(_point: Vector3) -> float:
		return 0.0

	func _unit_level(_unit: BattleUnit) -> int:
		return 0

class SpawnWorld extends BattleWorld:
	var reset_position := Vector3.ZERO
	var reset_heading := 0.0

	func spawn_position(_side: String, _slot: int = 0, _flying: bool = false) -> Vector3:
		return reset_position

	func spawn_heading(_side: String, _slot: int) -> float:
		return reset_heading

static func run(h: Node, fixtures: Dictionary) -> void:
	if not Content.balance.has("playerView"):
		h._check(false, "Regenerate original player-view metadata")
		return
	for key: String in ["cameraAngleSteps", "playerViewBodies", "playerViewModes", "playerViewFireModes", "playerViewHeights", "playerViewPlacements", "playerViewCameras", "playerViewColliders"]:
		if not fixtures.has(key):
			h._check(false, "Regenerate original player-view oracle: " + key)
			return
	for item: Dictionary in fixtures.cameraAngleSteps:
		h._near(CameraPose.angle_step(item.current, item.target, item.rate, item.delta), item.result,
			"Original frame-independent camera turn including negative half-turn endpoint")
	for item: Dictionary in fixtures.playerViewColliders:
		Helper.compare(h, CameraPose.entity_collider(item.kind, item.scale, item.collapsed), item.result,
			"Original view-collider radius/height, fixed AA/relay radii, zero scale and rubble")
	for item: Dictionary in fixtures.playerViewBodies:
		var state := PlayerViewState.new()
		state.configure(Content.balance.playerView, item.mode, item.yaw)
		state.body_yaw = item.body_yaw
		state.aiming = item.aiming
		for step: Dictionary in item.steps:
			state.advance_body(step.delta, h._reference_vector(item.move), item.yaw, item.defending, item.firing)
			h._near(state.body_yaw, step.result, "Original idle/moving/firing/aiming/defending body-heading trace")
			h._near(state.report_yaw(item.yaw, item.defending), step.report, "Original reported body-versus-view heading selection")
	for item: Dictionary in fixtures.playerViewModes:
		var state := PlayerViewState.new()
		state.configure(Content.balance.playerView, item.initial, item.yaw)
		state.body_yaw = item.body_yaw
		var yaw: float = item.yaw
		var has_side := true
		var saved: Array = []
		var aim_events: Array = []
		state.preference_changed.connect(func(value): saved.append(value))
		state.aim_changed.connect(func(on): aim_events.append(on))
		for step: Dictionary in item.steps:
			saved.clear()
			aim_events.clear()
			if step.has("yaw"):
				yaw = step.yaw
			if step.has("side"):
				has_side = step.side
			if step.has("mode"):
				yaw = state.select_mode(step.mode, yaw)
			if step.has("aim"):
				yaw = state.set_aiming(step.aim, yaw, has_side)
			Helper.compare(h, {"preference": state.preference, "mode": state.mode, "yaw": yaw, "body_yaw": state.body_yaw,
				"aiming": state.aiming, "restore": state.restore}, step.result, "Original reentrant view preference/aim restoration")
			Helper.compare(h, saved, step.saved, "Original persisted temporary FPV and nested mode notifications")
			Helper.compare(h, aim_events, step.aimEvents, "Original immediate aim event and no-side/same-mode guards")
	for item: Dictionary in fixtures.playerViewFireModes:
		var simulation := BattleSimulation.new()
		var unit := BattleUnit.new()
		h.add_child(simulation)
		simulation.add_child(unit)
		unit.view_mode = item.initial
		unit.yaw = item.yaw
		unit.player_view.configure(Content.balance.playerView, item.initial, unit.yaw)
		unit.player_view.body_yaw = item.body_yaw
		unit.ammo[item.slot] = item.ammo
		unit.input_state = {"aim": false, "view_restore": item.before.restore}
		if item.before.aiming:
			simulation._set_human_aim(unit, true)
		Helper.compare(h, {"mode": unit.view_mode, "yaw": unit.yaw, "body_yaw": unit.player_view.body_yaw,
			"aiming": unit.input_state.aim, "restore": unit.input_state.get("view_restore", "")}, item.before,
			"Authority aim entry preserves source mode preference and body heading")
		h._check(simulation._shot_view_mode(unit, item.slot) == item.result.mode,
			"Original last-heavy shot selects its restored TPS port before marking fire")
		if item.slot == "heavy" and item.before.aiming and float(item.ammo) <= 1:
			simulation._set_human_aim(unit, false)
		Helper.compare(h, {"mode": unit.view_mode, "yaw": unit.yaw, "body_yaw": unit.player_view.body_yaw,
			"aiming": unit.input_state.aim, "restore": unit.input_state.get("view_restore", "")}, item.result,
			"Original empty-heavy aim restoration preserves mode, heading and nonempty/light guards")
		h._check(unit.player_view.mode == unit.view_mode and unit.player_view.preference == unit.view_mode,
			"Authority view notifications retain a consistent preference after forced FPV and TPS restoration")
		simulation.free()
	for item: Dictionary in fixtures.playerViewPlacements:
		var simulation := BattleSimulation.new()
		h.add_child(simulation)
		simulation.set_physics_process(false)
		var world := SpawnWorld.new()
		simulation.add_child(world)
		simulation.world = world
		world.reset_position = BodyPose.vector(item.result.position)
		world.reset_heading = atan2(-float(item.direction[0]), -float(item.direction[1]))
		var unit := BattleUnit.new()
		simulation.add_child(unit)
		unit.configure({"id": 1, "peer": 1, "character": item.character, "side": item.side,
			"kind": Content.heroes[item.character].kind, "position": Vector3.ZERO})
		unit.yaw = 2
		unit.pitch = 1
		unit.charge = 1
		unit.low_gravity = true
		unit.view_mode = "tps"
		unit.player_view.configure(Content.balance.playerView, "tps", -1)
		var serial := unit.view_reset
		simulation.respawn(unit)
		Helper.compare(h, {"position": [unit.position.x, unit.position.y, unit.position.z], "yaw": unit.yaw,
			"body_yaw": unit.player_view.body_yaw, "pitch": unit.pitch, "charge": unit.charge,
			"low_gravity": unit.low_gravity, "flight": unit.flying}, item.result,
			"Original source placement resets camera/body heading, pitch, charge and flight")
		h._check(unit.view_reset == serial + 1 and unit.view_mode == "tps",
			"Respawn transports a camera-reset generation while preserving the view preference")
		simulation.free()
	for item: Dictionary in fixtures.playerViewHeights:
		for flight: bool in [false, true]:
			h._near(CameraPose.body_height(item.character, flight, SuperRules.body_scale(item.level)), item.result,
				"Original heroTargetH camera ruler with absolute Super scale: " + item.character)
	for item: Dictionary in fixtures.playerViewCameras:
		var position: Vector3 = h._reference_vector(item.position)
		var surface := func(_point: Vector3) -> float: return NAN if item.ground == null else float(item.ground)
		var camera := CameraPose.third_person_anchor(position, item.height, item.yaw, item.pitch, surface)
		var recoil := RecoilState.new()
		recoil.view_pitch = float(item.recoil[0]) + float(item.shake[0])
		recoil.view_yaw = float(item.recoil[1]) + float(item.shake[1])
		recoil.shake.z = item.shake[2]
		var basis := recoil.third_person_basis(item.yaw, item.pitch, item.roll)
		compare_frame(h, Transform3D(basis, camera), ViewTests.frame(item.raw), "Original TPS shoulder/floor/local-axis recoil: " + item.name)
		var entities: Array = item.entities.duplicate(true)
		for entity: Dictionary in entities:
			entity.position = h._reference_vector(entity.position)
		var collision := func(start: Vector3, end: Vector3) -> Dictionary:
			return {} if item.hit == null else {"position": start + (end - start).normalized() * float(item.hit)}
		camera = CameraPose.clip(position, camera, float(item.height) * float(Content.balance.playerView.pullHeight), item.blockers,
			entities, false, 0, collision, surface)
		var frame := Transform3D(basis, camera)
		compare_frame(h, frame, ViewTests.frame(item.clipped), "Original TPS midpoint-anchor 3D pull and dynamic de-clip: " + item.name)
		if item.ringY != null:
			frame = CameraPose.frame_ring(frame, ViewTests.matrix(item.projection), Vector3(position.x, item.ringY, position.z))
		compare_frame(h, frame, ViewTests.frame(item.result), "Original post-clip team-ring composition and singularity guard: " + item.name)
	integration(h)
	OcclusionTests.run(h, fixtures)

static func compare_frame(h: Node, actual: Transform3D, expected: Transform3D, label: String) -> void:
	h._check(actual.origin.distance_to(expected.origin) < 0.0002, label + "/position")
	h._check(actual.basis.x.distance_to(expected.basis.x) < 0.00001 and actual.basis.y.distance_to(expected.basis.y) < 0.00001
		and actual.basis.z.distance_to(expected.basis.z) < 0.00001, label + "/orientation")

static func integration(h: Node) -> void:
	var simulation := ReferenceSimulation.new()
	h.add_child(simulation)
	simulation.set_physics_process(false)
	var unit := ControlsTests.actor(simulation, "t01")
	unit.position = Vector3(0, 80, 0)
	var before := [unit.hp, unit.shield, unit.power, unit.money, unit.ammo.duplicate(true), unit.lock_target,
		simulation.rng.state, simulation.projectile_rng.state, unit.yaw, unit.pitch]
	var projection := Projection.create_perspective(68, 1.6, .5, 3500)
	var frame := simulation.third_person_camera(unit, .7, -.18, projection, unit.position.y + .18)
	h._check(frame.origin.is_finite() and before == [unit.hp, unit.shield, unit.power, unit.money, unit.ammo, unit.lock_target,
		simulation.rng.state, simulation.projectile_rng.state, unit.yaw, unit.pitch],
		"TPS presentation helper never settles resources, rotates authority aim or consumes either combat RNG")
	var original_height := unit.height
	unit.height *= 2
	h._check(simulation.third_person_camera(unit, .7, -.18, projection, unit.position.y + .18) == frame,
		"TPS ruler follows source visual height rather than the damage cylinder")
	unit.height = original_height
	var obstacle := BattleUnit.new()
	simulation.add_child(obstacle)
	obstacle.kind = "aasite"
	obstacle.special = {"role": "hazard", "scale": 2.0}
	obstacle.position = Vector3(unit.position.x, 0, unit.position.z - 2)
	obstacle.hp = 1
	obstacle.hit_area = Area3D.new()
	obstacle.add_child(obstacle.hit_area)
	obstacle.movement_shape = CollisionShape3D.new()
	obstacle.add_child(obstacle.movement_shape)
	obstacle.refresh_collision()
	simulation.units[2] = obstacle
	var colliders := simulation._camera_colliders()
	h._check(colliders.size() == 1 and colliders[0].position == obstacle.position,
		"Camera roster includes source obstacle entities and excludes ordinary hero bodies")
	var shape := obstacle.movement_shape.shape as CylinderShape3D
	h._near(shape.radius, float(colliders[0].colR), "Native AA movement/camera radius remains fixed despite visual scale")
	h._near(shape.height, float(colliders[0].colH), "Native AA movement/camera height remains fixed despite visual scale")
	simulation.world = BattleWorld.new()
	simulation.add_child(simulation.world)
	var clear := simulation.camera_origin(unit)
	obstacle.position.y = clear.y
	var clipped := simulation.camera_origin(unit)
	h._check(clipped != clear, "Dynamic obstacle movement invalidates an otherwise identical same-frame camera cache")
	obstacle.special.collapsed = true
	obstacle.refresh_collision()
	var rubble := simulation._camera_colliders()
	h._check(float(rubble[0].colR) < float(colliders[0].colR) and float(rubble[0].colH) < float(colliders[0].colH),
		"Collapsed hazards remain camera obstacles using original reduced dimensions")
	shape = obstacle.movement_shape.shape as CylinderShape3D
	h._near(shape.radius, float(rubble[0].colR), "Native rubble movement/camera radii remain identical")
	h._near(shape.height, float(rubble[0].colH), "Native rubble movement/camera heights remain identical")
	for kind: String in Content.balance.playerView.colliders:
		if float(Content.balance.playerView.colliders[kind].radius) == 0:
			obstacle.kind = kind
			obstacle.refresh_collision()
			h._check(obstacle.collision_layer == 0 and obstacle.movement_shape.disabled, "Nonblocking hazard does not create an invalid zero-radius collision cylinder")
			break
	simulation.free()
