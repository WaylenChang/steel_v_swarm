extends RefCounted

const StatusSuite = preload("res://tests/status_suite.gd")

static func run(h: Node, fixtures: Dictionary) -> void:
	var models: Dictionary = {}
	var meshes := 0
	for fixture: Dictionary in fixtures.projectileGeometry:
		var model := ProjectileVisual.new()
		h.add_child(model)
		model.configure(fixture.key)
		models[fixture.key] = model
		var graph: Dictionary = Content.read_json("res://data/projectiles/%s.json" % fixture.key)
		h._check(model.nodes.size() == fixture.nodes.size(), "Deferred outline shells preserve original projectile animation IDs")
		preload("res://tests/outline_suite.gd").check_deferred(h, model.source_root)
		for spec: Dictionary in fixture.nodes:
			var node: Node3D = model.nodes[int(spec.id)]
			var expected := CockpitSuite.matrix(spec.matrix)
			h._check(node.transform.origin.distance_to(expected.origin) < 0.00001 and CockpitSuite.basis_error(node.transform.basis, expected.basis) < 0.00001,
				"Original projectile local transform: " + fixture.key)
			if not spec.has("mesh"):
				continue
			meshes += 1
			var mesh := node as MeshInstance3D
			var bounds := mesh.mesh.get_aabb()
			var world_bounds := mesh.global_transform * bounds
			h._check(world_bounds.position.distance_to(h._reference_vector(spec.worldBounds[0])) < 0.0001 and world_bounds.end.distance_to(h._reference_vector(spec.worldBounds[1])) < 0.0001,
				"Original projectile mesh bounds: " + fixture.key)
			var source_mesh: Dictionary = graph.meshes[int(spec.mesh)]
			var arrays := mesh.mesh.surface_get_arrays(0)
			for index in range(0, source_mesh.position.size(), 3):
				var vertex := Vector3(source_mesh.position[index], source_mesh.position[index + 1], source_mesh.position[index + 2])
				h._check(arrays[Mesh.ARRAY_VERTEX][index / 3].distance_to(vertex) < 0.000001, "Original authored projectile vertex")
	for fixture: Dictionary in fixtures.projectileFx:
		var model: ProjectileVisual = models[fixture.key]
		model.step_fx(fixture.age, fixture.speed)
		for expected: Dictionary in fixture.nodes:
			var node: MeshInstance3D = model.nodes[int(expected.id)]
			h._check(node.position.distance_to(h._reference_vector(expected.position)) < 0.00001 and node.scale.distance_to(h._reference_vector(expected.scale)) < 0.00001,
				"Original age/speed tail animation: " + fixture.key)
			var material := node.get_active_material(0) as StandardMaterial3D
			h._near(material.albedo_color.a, expected.opacity, "Original authored opacity pulse")
	for model: ProjectileVisual in models.values():
		model.free()
	print("PROJECTILE_VISUAL_GEOMETRY_PASS profiles=", fixtures.projectileGeometry.size(), " meshes=", meshes, " fx_cases=", fixtures.projectileFx.size())
	var maximum_error := 0.0
	var frames := 0
	var shell_view := ProjectilePresentation.new()
	h.add_child(shell_view)
	for fixture: Dictionary in fixtures.visualShells:
		var definition := Content.weapon(fixture.character, fixture.slot, int(fixture.level))
		var state := VisualShellMotion.launch(definition, h._reference_vector(fixture.origin), h._reference_vector(fixture.target),
			fixture.ground, fixture.surface, NAN if fixture.speed == null else fixture.speed)
		h._check(state.velocity.distance_to(h._reference_vector(fixture.initial.velocity)) < 0.001, "Original visual launch priority, AA and 45-degree throw")
		h._near(state.range, fixture.initial.range, "Original visual range stops at the target sphere")
		h._check(state.guided == fixture.initial.guided and state.launch_distance == fixture.initial.launch_distance, "Original visual launch lift before steering")
		var key: String = "%s-%s-steel" % [fixture.character, fixture.slot]
		var rendered_state := state.duplicate(true)
		shell_view.spawn_shell(rendered_state, key)
		var model: ProjectileVisual = rendered_state.model
		var initial_fx: Array = fixtures.projectileFx.filter(func(item): return item.key == key and item.age == 0 and item.speed == 0)
		if not initial_fx.is_empty():
			for part: Dictionary in initial_fx[0].nodes:
				var node := model.nodes[int(part.id)] as MeshInstance3D
				h._check(node.position.distance_to(h._reference_vector(part.position)) < .00001 and node.scale.distance_to(h._reference_vector(part.scale)) < .00001,
					"Visual shell factory frame retains source zero-age/zero-speed tails before the first flight step")
		var impacts: Array = []
		for index in range(fixture.steps.size()):
			frames += 1
			var collision := func(start: Vector3, end: Vector3) -> Dictionary:
				return {"position": start.lerp(end, 0.6)} if index == int(fixture.hitFrame) else {}
			var actual := VisualShellMotion.advance(state, fixture.delta, collision)
			shell_view.advance(fixture.delta, collision, func(point, radius, color):
				impacts.append({"position": [point.x, point.y, point.z], "radius": radius, "color": color}))
			var expected: Dictionary = fixture.steps[index]
			var error: float = maxf(state.position.distance_to(h._reference_vector(expected.position)), state.velocity.distance_to(h._reference_vector(expected.velocity)))
			maximum_error = maxf(maximum_error, error)
			h._check(error < 0.001, "Original visual flight: %s/%s/%s frame=%d error=%s" % [fixture.character, fixture.slot, fixture.name, index, error])
			h._check(actual.terminal == expected.terminal and actual.hit == expected.hit, "Original collision precedes silent range expiry; small segments skip collision")
			if expected.get("impact") != null:
				h._check(not impacts.is_empty(), "Original visual-shell collision produces its contact star")
				if not impacts.is_empty():
					StatusSuite.compare(h, impacts[-1], expected.impact, "Original visual-shell collision star position, radius and colour")
			else:
				h._check(impacts.is_empty(), "Visual-shell range expiry remains silent")
			h._check(model.visible != bool(expected.terminal), "Actual visual shell returns to its pool at the source terminal boundary")
			h._check(rendered_state.position.distance_to(h._reference_vector(expected.position)) < .001, "Rendered visual shell follows the source collision endpoint")
		for remaining: Dictionary in shell_view.shells:
			shell_view._drop(remaining.model, remaining.key)
		shell_view.shells.clear()
	shell_view.free()
	print("VISUAL_SHELL_REFERENCE_PASS sequences=", fixtures.visualShells.size(), " frames=", frames, " maximum_error=", maximum_error)
	for fixture: Dictionary in fixtures.tracerPresentation:
		var presentation := ProjectilePresentation.new()
		h.add_child(presentation)
		presentation.tracer(Vector3(1, 2, 3), Vector3(-4, 5, -6), Color.hex((int(fixture.color) << 8) | 0xff), fixture.ttl)
		var line: MeshInstance3D = presentation.traces[0].line
		presentation.advance(fixture.delta, func(_start, _end): return {})
		h._near(line.material_override.albedo_color.a, fixture.opacity, "Original _tracer and _updateEffects fade")
		h._check(line.visible == fixture.visible, "Original tracer TTL boundary and return")
		var vertices: PackedVector3Array = line.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		h._check(vertices == PackedVector3Array([Vector3(1, 2, 3), Vector3(-4, 5, -6)]), "Original thin tracer endpoint geometry")
		presentation.free()
	await integration(h)

static func integration(h: Node) -> void:
	var sim := BattleSimulation.new()
	h.add_child(sim)
	var map_data := Content.map_variant(0, 2)
	map_data.erase("native_world")
	sim.authoritative = true
	sim.set_physics_process(false)
	sim.world = BattleWorld.new()
	sim.add_child(sim.world)
	await sim.world.build(map_data, {"time": "day", "weather": "clear"})
	sim.pilots[993] = sim.spawn({"kind": Content.heroes.t06.kind, "peer": 993, "side": "STEEL", "character": "t06", "bot": false, "position": Vector3(0, 100, 0), "yaw": 0.0})
	sim.pilots[994] = sim.spawn({"kind": Content.heroes.s01.kind, "peer": 994, "side": "SWARM", "character": "s01", "bot": false, "position": Vector3(0, 100, 10), "yaw": 0.0})
	sim.pilots[1] = sim.spawn({"kind": Content.heroes.t08.kind, "peer": 1, "side": "STEEL", "character": "t08", "bot": false, "position": Vector3(5, 100, 40), "yaw": 0.0})
	var actor: BattleUnit = sim.pilots[993]
	actor.position = Vector3(0, 100, 0)
	actor.input_state = {"slot": "light"}
	sim.fire(actor, "light")
	var view: Array = sim.snapshot(993).projectile_view
	h._check(view.size() == 1 and sim.snapshot(994).projectile_view.is_empty() and sim.snapshot().projectile_view.is_empty(), "Owner-only native projectile poses do not expose other launches or allocate global server meshes")
	var captured := view.duplicate(true)
	var presentation := sim.world.ensure_projectile_visuals()
	presentation.sync_rounds(view)
	var live: ProjectileVisual = presentation.rounds[view[0].id].model
	h._check(live.position == view[0].position and (live.quaternion * Vector3.BACK).distance_to(view[0].velocity.normalized()) < 0.000001, "Native authority-view mesh preserves source velocity orientation")
	sim._tick_projectiles(1.0 / 240)
	presentation.sync_rounds(sim.projectile_view(actor))
	h._check(sim.projectile_view(actor)[0].position == live.position and captured[0].position != live.position, "Native mesh follows current authority position without mutating captured snapshots")
	presentation.sync_rounds([])
	h._check(not live.visible and presentation.rounds.is_empty(), "Terminal snapshots recycle owner meshes")
	presentation.sync_rounds(view)
	h._check(presentation.rounds[view[0].id].model == live, "Source projectile models reuse the matching variant pool")
	presentation.retire_round(view[0].id, 10)
	h._check(not live.visible and presentation.rounds.is_empty(), "An immediate terminal notification removes the owner mesh before the next snapshot")
	presentation.sync_rounds(view, 9.9)
	h._check(presentation.rounds.is_empty(), "A pre-impact snapshot cannot recreate a retired projectile")
	presentation.sync_rounds([], 10)
	presentation.sync_rounds(view, 10)
	h._check(presentation.rounds.is_empty() and presentation.retired_rounds.has(view[0].id), "Same-clock publications cannot clear the terminal guard early")
	presentation.sync_rounds([], 10.1)
	h._check(not presentation.retired_rounds.has(view[0].id), "A newer authoritative absence releases the terminal guard")
	actor.ensure_cockpit()
	actor.cockpit.echo_fired.connect(sim.present_echo.bind(actor))
	var event: Dictionary = sim.events.filter(func(item): return item.type == "weapon_fire" and int(item.actor) == actor.entity_id)[0]
	actor.cockpit.fire_feedback(event)
	var hp := actor.hp
	var ammo := actor.ammo.duplicate()
	var power := actor.power
	var combat_rng := sim.rng.state
	var spread_rng := sim.projectile_rng.state
	var events := sim.events.size()
	var definition := Content.weapon(actor.character, "light")
	sim.clock = event.clock + definition.burst.gap
	actor.cockpit.update_view(actor, "heavy", false, 1.0 / 240, sim.clock)
	h._check(presentation.shells.size() == 1 and sim.projectiles.size() == 1, "Actual cockpit echo spawns only the source visual shell")
	var shell: Dictionary = presentation.shells[0]
	var first_model: ProjectileVisual = shell.model
	var start: Vector3 = shell.position
	presentation.advance(1.0 / 240, sim.world.visual_collision)
	h._check(first_model.position != start and shell.velocity.y < 0, "Actual source echo advances with gravity")
	h._check(actor.hp == hp and actor.power == power and actor.ammo == ammo and sim.events.size() == events and sim.rng.state == combat_rng and sim.projectile_rng.state == spread_rng,
		"Mesh, flight and material presentation cannot change combat resources, events or RNG")
	var shell_count := presentation.shells.size()
	sim.present_echo(definition, Vector3(1000000000, 100, 0), actor)
	h._check(presentation.shells.size() == shell_count + 1, "Flat visual shells do not require unused target terrain or launch-surface samples")
	var second_model := ProjectileVisual.new()
	h.add_child(second_model)
	second_model.configure(shell.key)
	var id := int(first_model.profile.authored[0])
	var first_material: StandardMaterial3D = first_model.animated_materials[id]
	var alpha := first_material.albedo_color.a
	second_model.step_fx(2, 900)
	h._check(first_material.albedo_color.a == alpha and second_model.animated_materials[id] != first_material, "Simultaneous source opacity animations cannot alter another pooled projectile")
	second_model.free()
	for index in range(1000):
		if presentation.shells.is_empty():
			break
		presentation.advance(1.0 / 60, func(_start, _end): return {})
	h._check(presentation.shells.is_empty() and not first_model.visible, "Range-expired visual shells recycle silently")
	var wall := StaticBody3D.new()
	wall.position = Vector3(0, 50, -1)
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 4, 0.01)
	collider.shape = box
	wall.add_child(collider)
	sim.add_child(wall)
	await h.get_tree().physics_frame
	await h.get_tree().physics_frame
	var native := VisualShellMotion.launch(definition, Vector3(0, 50, 0), Vector3(0, 50, -100), 0, 0)
	var collision := VisualShellMotion.advance(native, 1.0 / 60, sim.world.visual_collision)
	h._check(collision.hit and collision.terminal and absf(native.position.z + 0.995) < 0.001, "Source visual shell uses a native swept segment against a thin static wall")
	presentation.tracer(Vector3.ZERO, Vector3(1, 2, 3), Color.WHITE)
	presentation.advance(0.1, func(_start, _end): return {})
	var line: MeshInstance3D = presentation.traces[0].line
	h._near(line.material_override.albedo_color.a, 0.9 * (0.35 - 0.1) / 0.35, "Source thin tracer linear opacity fade")
	presentation.advance(0.25, func(_start, _end): return {})
	h._check(presentation.traces.is_empty() and not line.visible, "Source tracer inclusive expiry and pool return")
	var beam: BattleUnit = sim.pilots[1]
	beam.position = Vector3(5, 100, 40)
	beam.input_state = {"aim": true, "slot": "light"}
	sim.fire(beam, "light")
	var beam_events: Array = sim.events.filter(func(item): return item.type == "shot" and int(item.actor) == beam.entity_id)
	h._check(not beam_events.is_empty(), "Authority accepts the supported FPV light beam fixture")
	if beam_events.is_empty():
		sim.queue_free()
		await h.get_tree().process_frame
		return
	var beam_event: Dictionary = beam_events[0]
	sim.present_shot(beam_event)
	var color: Color = presentation.traces[0].line.material_override.albedo_color
	h._check(beam_event.weapon_type == "beam" and is_equal_approx(color.r, sim._fpv_tracer_color("beam", "STEEL").r) and presentation.traces[0].duration == 0.35,
		"Actual accepted FPV light beam uses the same original thin tracer and color family as its echoes")
	sim.queue_free()
	await h.get_tree().process_frame
