extends RefCounted

const Helper = preload("res://tests/status_suite.gd")

class FixtureWorld extends BattleWorld:
	func climb_query() -> Callable:
		return climb_index.at

static func run(h: Node, fixtures: Dictionary) -> void:
	for key: String in ["climbQueries", "climbPrograms", "climbArrows", "climbClearance", "climbRoll"]:
		if not fixtures.has(key):
			h._check(false, "Regenerate original climb references: " + key)
			return
	for item: Dictionary in fixtures.climbRoll:
		Helper.compare(h, MovementRules.camera_roll(item.current, item.lateral, item.speed, item.flying, item.delta), item.result, "Original flight bank/ground roll including zero/hitched frames")
	for item: Dictionary in fixtures.climbClearance:
		var accepted := ClimbIndex.after_camp_clearance(item.routes, item.camps, item.buildings)
		var ids: Array = accepted.map(func(route): return route.id)
		Helper.compare(h, ids, item.ids, "Original camp clearance keeps vegetation/OSM, strict radius boundaries and both route supports")
	for item: Dictionary in fixtures.climbQueries:
		var index := ClimbIndex.new()
		index.configure(item.routes)
		var route := index.at(item.point[0], item.point[2], item.point[1])
		h._check(int(route.get("id", 0)) == int(item.id), "Original grip cells, negative coordinates, vertical/radial bounds and last-route ties")
	for item: Dictionary in fixtures.climbPrograms:
		var state: Dictionary = item.initial.duplicate(true)
		var driver := ClimbState.new()
		var index := ClimbIndex.new()
		index.configure([item.route])
		for step: Dictionary in item.steps:
			if step.teleport != null:
				state.x = float(step.teleport)
			var nearest: Callable = index.at if step.input.available else Callable()
			var active := driver.advance(step.delta, step.now, state, step.input, nearest)
			var notices: Array = [Content.balance.movement.climb.notices[driver.entered_kind]] if driver.entered else []
			Helper.compare(h, {"state": state, "takeover": active, "route": driver.route.get("id", 0), "off": driver.off_until, "notices": notices},
				step.result, "Original climb latch, intent, zero/hitched step, release cooldown, CC, death/flight and teleport recovery: " + item.program)
	for item: Dictionary in fixtures.climbArrows:
		var root := arrow_root(item)
		var presentation := ClimbPresentation.new()
		h._check(presentation.configure(root, item.routes), "Bind original native climb arrow batches")
		for frame: Dictionary in item.frames:
			presentation.advance(frame.delta)
			var batches: Array = []
			for key: String in ["up", "down"]:
				if not presentation.batches.has(key):
					continue
				var matrices: Array = []
				var mesh: MultiMesh = presentation.batches[key].multimesh
				for index in range(mesh.instance_count):
					var transform := mesh.get_instance_transform(index)
					matrices.append([transform.basis.x.x, transform.basis.x.y, transform.basis.x.z, 0,
						transform.basis.y.x, transform.basis.y.y, transform.basis.y.z, 0,
						transform.basis.z.x, transform.basis.z.y, transform.basis.z.z, 0,
						transform.origin.x, transform.origin.y, transform.origin.z, 1])
				batches.append(matrices)
			compare_matrices(h, batches, frame.batches)
		root.free()
	await native_step(h, fixtures.climbPrograms[0])
	var unavailable := BattleWorld.new()
	h._check(not unavailable.climb_query().is_valid(), "A road-only world never invents climb routes")
	unavailable.free()

static func arrow_root(item: Dictionary) -> Node3D:
	var root := Node3D.new()
	if item.geometry == null:
		return root
	var vertices := PackedVector3Array()
	for index in range(0, item.geometry.positions.size(), 3):
		vertices.append(Vector3(item.geometry.positions[index], item.geometry.positions[index + 1], item.geometry.positions[index + 2]))
	var indices := PackedInt32Array(item.geometry.indices)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var geometry := ArrayMesh.new()
	geometry.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	for key: String in ["up", "down"]:
		var batch := MultiMeshInstance3D.new()
		batch.multimesh = MultiMesh.new()
		batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		batch.multimesh.mesh = geometry
		batch.multimesh.instance_count = item.routes.size() * int(Content.balance.movement.climb.arrows.N) * 2
		batch.set_meta("source_climb_arrow", key)
		root.add_child(batch)
	return root

static func compare_matrices(h: Node, actual: Array, expected: Array) -> void:
	h._check(actual.size() == expected.size(), "Original climb arrow batch count")
	for batch in range(mini(actual.size(), expected.size())):
		h._check(actual[batch].size() == expected[batch].size(), "Original climb arrow instance count")
		for index in range(mini(actual[batch].size(), expected[batch].size())):
			for element in range(16):
				h._check(absf(float(actual[batch][index][element]) - float(expected[batch][index][element])) < .00001,
					"Original arrow flow, orientation, first-frame pose and endpoint shrink")

static func native_step(h: Node, item: Dictionary) -> void:
	var simulation := BattleSimulation.new()
	h.add_child(simulation)
	simulation.set_physics_process(false)
	var world := FixtureWorld.new()
	simulation.world = world
	simulation.add_child(world)
	world.climb_index.configure([item.route])
	var unit := BattleUnit.new()
	simulation.add_child(unit)
	unit.configure({"id": 1, "peer": 1, "kind": Content.heroes.t01.kind, "character": "t01", "side": "STEEL",
		"position": Vector3(item.initial.x, item.initial.y, item.initial.z)})
	unit.impulse_velocity = Vector2(item.initial.impulse_x, item.initial.impulse_z)
	unit.velocity.y = item.initial.vertical
	unit.charge = item.initial.charge
	unit.low_gravity = item.initial.low_gravity
	unit.movement_roll = item.initial.roll
	var before := [unit.hp, unit.shield, unit.power, unit.lift, unit.money, unit.ammo.duplicate(true), simulation.rng.state]
	await h.get_tree().physics_frame
	await h.get_tree().physics_frame
	var step: Dictionary = item.steps[0]
	var active := unit._step_climb(simulation, step.delta, step.now, Vector3(step.input.move_x, 0, step.input.move_z),
		step.input.forward, step.input.jump, step.input.cc, step.input.jump_speed)
	var expected: Dictionary = step.result.state
	h._check(active == step.result.takeover and unit.position.distance_to(Vector3(expected.x, expected.y, expected.z)) < .00001,
		"Native collision sweeps apply the accepted original climb displacement")
	h._check(simulation.events.size() == 1 and simulation.events[0].type == "climb_grab" and int(simulation.events[0].only_peer) == 1,
		"Climb entry reports its original owner-only notice once")
	Helper.compare(h, [unit.hp, unit.shield, unit.power, unit.lift, unit.money, unit.ammo, simulation.rng.state], before,
		"Climbing cannot spend lift, health, power, ammo or combat RNG")
	simulation.free()
	await h.get_tree().physics_frame
