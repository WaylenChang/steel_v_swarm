extends RefCounted

static func run(h: Node, fixtures: Dictionary) -> void:
	var maximum_error := 0.0
	for fixture: Dictionary in fixtures.cameraAnchors:
		var actual := CameraPose.anchor(fixture.character, h._reference_vector(fixture.position), fixture.yaw, fixture.flight, fixture.charge)
		var error: float = actual.distance_to(h._reference_vector(fixture.result))
		maximum_error = maxf(maximum_error, error)
		h._check(error < 0.0001, "Original heroView eye and forward anchor: " + fixture.character)
		h._near(CameraPose.eye_height(fixture.character, fixture.flight, fixture.charge), fixture.eye, "Original eye-height crouch and flight semantics")
	for fixture: Dictionary in fixtures.cameraClips:
		var entities: Array = fixture.entities.duplicate(true)
		for entity: Dictionary in entities:
			entity.position = h._reference_vector(entity.position)
		var collision := func(start: Vector3, end: Vector3) -> Dictionary:
			return {} if fixture.hit == null else {"position": start + (end - start).normalized() * fixture.hit}
		var surface := func(point: Vector3) -> float:
			if fixture.ground == null:
				return NAN
			return 5.0 if fixture.ridge and Vector2(point.x, point.z).length() > 3 else fixture.ground
		var actual := CameraPose.clip(Vector3.ZERO, h._reference_vector(fixture.camera), fixture.eye, fixture.blockers,
			entities, fixture.onDeck, fixture.surface, collision, surface)
		var error: float = actual.distance_to(h._reference_vector(fixture.result))
		maximum_error = maxf(maximum_error, error)
		h._check(error < 0.0001, "Original camera de-clip skin, height and 3D pull: " + fixture.name)
	print("CAMERA_REFERENCE_PASS anchors=", fixtures.cameraAnchors.size(), " clips=", fixtures.cameraClips.size(), " maximum_error=", maximum_error)
	await integration(h)

static func integration(h: Node) -> void:
	var sim := BattleSimulation.new()
	h.add_child(sim)
	sim.set_physics_process(false)
	var map_data := Content.map_variant(0, 1)
	map_data.erase("native_world")
	sim.world = BattleWorld.new()
	sim.add_child(sim.world)
	await sim.world.build(map_data, {"time": "day", "weather": "clear"})
	var actor := sim.spawn({"peer": 991, "side": "STEEL", "character": "t04", "kind": Content.heroes.t04.kind, "bot": false, "position": Vector3(0, 80, 0)})
	sim.pilots[991] = actor
	actor.position = Vector3(0, 80, 0)
	actor.yaw = .7
	actor.pitch = -.2
	actor.sync_view_camera()
	var expected := CameraPose.anchor(actor.character, actor.position, actor.yaw, actor.flying)
	h._check(actor.camera.global_position.distance_to(expected) < 0.0001 and actor.aim_transform().origin.distance_to(expected) < 0.0001,
		"Local camera and authority ray share the original body-forward anchor")
	h._check(actor.camera.global_basis.z.distance_to(-actor.aim_direction()) < 0.0001, "Spawn/paused authority yaw still reaches the actual camera")
	var hp := actor.hp
	var ammo := actor.ammo.duplicate()
	var rng_state := sim.rng.state
	var spread_state := sim.projectile_rng.state
	var first := sim.camera_origin(actor)
	h._check(sim.camera_origin(actor) == first and actor.hp == hp and actor.ammo == ammo and sim.rng.state == rng_state and sim.projectile_rng.state == spread_state,
		"Repeated camera queries cannot spend combat state or RNG")
	var replica := BattleUnit.new()
	h.add_child(replica)
	replica.configure({"id": 9981, "kind": actor.kind, "character": actor.character, "side": actor.side, "position": actor.position})
	replica.apply_snapshot(actor.snapshot(), true)
	h._check(replica.camera.global_position.distance_to(actor.camera.global_position) < 0.0001, "Snapshot replica retains the authority clipped camera offset")
	var state := actor.snapshot()
	state.view_offset = Vector3.ZERO
	replica.apply_snapshot(state, true)
	h._check(replica.view_origin() == replica.position, "A zero flight-camera offset is a valid snapshot, never a missing value")
	replica.free()
	actor.yaw = 0
	var point := CameraPose.anchor(actor.character, actor.position, 0, false)
	var wall := StaticBody3D.new()
	wall.position = point
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.1, 2, 0.01)
	collider.shape = shape
	wall.add_child(collider)
	sim.add_child(wall)
	await h.get_tree().physics_frame
	await h.get_tree().physics_frame
	var clipped := sim.camera_origin(actor)
	var body_eye := actor.position + Vector3.UP * actor.view_eye_height()
	h._check(clipped.distance_to(body_eye) < 0.0001, "Native static collision pulls the FPV camera back to its eye anchor")
	actor.sync_view_camera()
	h._check(actor.camera.global_position.distance_to(clipped) < 0.0001, "Renderer uses the same clipped origin as authority fire control")
	sim.queue_free()
	await h.get_tree().process_frame
