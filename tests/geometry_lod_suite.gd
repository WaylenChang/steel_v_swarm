extends RefCounted

const Helper = preload("res://tests/status_suite.gd")

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("geometryLodPrograms") or not Content.balance.has("geometryLod"):
		h._check(false, "Regenerate original geometry LOD transitions and source node flags")
		return
	var rules: Dictionary = Content.balance.geometryLod
	for program: Dictionary in fixtures.geometryLodPrograms:
		var nodes := _nodes(program.nodes)
		var root: Node3D = nodes[0]
		h.add_child(root)
		var state := GeometryLodState.new()
		for step: Dictionary in program.steps:
			root.visible = step.visible
			var blend := 0.0 if step.viewerDead else ScopeState.aim_blend(step.fov, step.base, step.zoom)
			h._near(blend, step.blend, "Original sniper blend extends geometry detail while death/spectating stays unextended")
			if not step.self and not step.dead and not step.garrison and step.visible:
				var result := state.observe(int(step.frame), program.id, step.d2, blend, rules)
				if not result.is_empty():
					GeometryLodState.apply(root, result.trim, result.outline)
			h._check(state.trim == step.trim and state.outline == step.outline,
				"Original first-sighting, staggered frames, signed frame wrap, zoom and hysteresis transitions")
			Helper.compare(h, nodes.map(func(node): return node.visible), step.visibility,
				"Original LOD touches only detail/outline nodes and honors geoKeep without pruning descendants")
		root.free()
		if String(program.id) == "13":
			_simulation(h, program)

static func _simulation(h: Node, program: Dictionary) -> void:
	var simulation := BattleSimulation.new()
	h.add_child(simulation)
	simulation.set_physics_process(false)
	var camera := Camera3D.new()
	simulation.add_child(camera)
	camera.position = Vector3(program.camera[0], program.camera[1], program.camera[2])
	var actor := BattleUnit.new()
	actor.entity_id = 13
	actor.peer_id = 13
	actor.character = "fixture"
	actor.kind = "robot"
	actor.side = "STEEL"
	simulation.add_child(actor)
	simulation.units[actor.entity_id] = actor
	var nodes := _nodes(program.nodes)
	actor.model = nodes[0]
	actor.add_child(actor.model)
	var combat_random := simulation.rng.state
	var projectile_random := simulation.projectile_rng.state
	var collision_mask := actor.collision_mask
	var collision_layer := actor.collision_layer
	for step: Dictionary in program.steps:
		actor.hp = 0 if step.dead else 100
		actor.special.garrison = step.garrison
		actor.geometry_override = {"height": step.height}
		actor.presentation_visible = step.visible
		actor.model.visible = step.visible
		actor.model.position = Vector3(step.point[0], step.point[1], step.point[2])
		simulation.present_geometry_lod(camera, int(step.frame), step.blend, 13 if step.self else 99)
		var state := actor.model.get_meta("source_geometry_lod", null) as GeometryLodState
		h._check((state.trim if state != null else null) == step.trim and (state.outline if state != null else null) == step.outline,
			"Native entity adapter retains the original model-centre 3D distance and eligibility gates")
		Helper.compare(h, nodes.map(func(node): return node.visible), step.visibility, "Native entity detail visibility matches executed source tick")
		h._check(actor.hp == (0 if step.dead else 100) and actor.collision_mask == collision_mask and actor.collision_layer == collision_layer,
			"Presentation LOD leaves combat resources, root visibility and native collision ownership intact")
	h._check(simulation.rng.state == combat_random and simulation.projectile_rng.state == projectile_random,
		"Geometry detail scheduling never consumes combat or projectile RNG")
	simulation.free()

static func _nodes(specs: Array) -> Array[Node3D]:
	var nodes: Array[Node3D] = []
	for spec: Dictionary in specs:
		var node := Node3D.new()
		node.visible = spec.visible
		for flag: String in spec.flags:
			node.set_meta(flag, spec.flags[flag])
		nodes.append(node)
		if int(spec.parent) >= 0:
			nodes[int(spec.parent)].add_child(node)
	return nodes
