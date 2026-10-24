extends RefCounted

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("wildlifeDensityPrograms"):
		h._check(false, "Regenerate original wildlife density/capacity constructor programs")
		return
	for program: Dictionary in fixtures.wildlifeDensityPrograms:
		for sample: Dictionary in program.cases:
			for low: bool in [false, true]:
				_case(h, program, sample, low)

static func _case(h: Node, program: Dictionary, sample: Dictionary, low: bool) -> void:
	var root := Node3D.new()
	h.add_child(root)
	var saved := {}
	for capture: Dictionary in program.catalogMeshes:
		var node := MultiMeshInstance3D.new()
		node.multimesh = MultiMesh.new()
		node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		node.multimesh.mesh = BoxMesh.new()
		node.multimesh.instance_count = capture.frames.size()
		for index in range(capture.frames.size()):
			node.multimesh.set_instance_transform(index, preload("res://tests/quaternion_suite.gd").frame(capture.frames[index]))
		node.set_meta("source_wildlife_mesh", int(capture.id))
		root.add_child(node)
		saved[int(capture.id)] = node.multimesh
	var water := {"value": 0.0}
	var height := func(x: float, z: float): return preload("res://tests/wildlife_suite.gd")._height(program.mode, x, z)
	var dry := func(_x: float, z: float): return absf(z) < 4
	var code := func(x: float, z: float): return EnvironmentRules.ground_code(height.call(x, z), water.value, [], dry.call(x, z))
	var view := WildlifePresentation.new()
	h._check(view.configure(root, program.source, low, height, code, dry, func(): return water.value, sample.densities,
		float(program.get("initialActivity", 1))),
		"Construct original density-specific private wildlife batches from route capacity records")
	for expected: Dictionary in sample.initial:
		if bool(expected.low) == low:
			_compare(h, view, expected)
	for frame: Dictionary in sample.frames:
		water.value = frame.waterY
		view.advance(frame.delta, frame.time, {"activity": frame.activity})
		for expected: Dictionary in frame.variants:
			if bool(expected.low) == low:
				_compare(h, view, expected)
	for capture: Dictionary in program.catalogMeshes:
		var original: MultiMesh = saved[int(capture.id)]
		h._check(original.instance_count == capture.frames.size(), "Density selection never resizes saved source MultiMesh capacities")
		for index in range(original.instance_count):
			h._check(original.get_instance_transform(index).is_equal_approx(preload("res://tests/quaternion_suite.gd").frame(capture.frames[index])),
				"Density-specific constructor/write/steps preserve saved source instance buffers")
	root.free()

static func _compare(h: Node, view: WildlifePresentation, expected: Dictionary) -> void:
	h._check(view.states.size() == expected.states.size() and view.batches.size() == expected.batches.size(),
		"Original ordered species/routes share the full/low-power animal budget")
	if view.states.size() != expected.states.size() or view.batches.size() != expected.batches.size():
		return
	var comparable := {"states": expected.states, "matrices": []}
	var total := 0
	for index in range(view.states.size()):
		var actual := view.states[index]
		var state: Dictionary = expected.states[index]
		h._check(int(actual.route.count) == int(state.count) and int(actual.route.seed) == int(state.seed) and actual.route.kind == state.kind,
			"Original per-route density rounding, at-least-one rule, cap, count and seed order")
		h._check(actual.positions.size() == state.pos.size(), "Original density-specific wildlife position buffer length")
		if actual.positions.size() != state.pos.size():
			return
		h._check(actual.speeds == PackedFloat32Array(state.spd) and actual.offsets == PackedFloat32Array(state.off) and actual.wings == PackedFloat32Array(state.wing),
			"Original per-animal RNG initialization is exactly the selected capacity prefix")
		total += int(actual.route.count)
	h._check(total <= int(view.profile.budget), "Original source density budget remains bounded for every preference combination")
	for index in range(view.batches.size()):
		var actual: Dictionary = view.batches[index]
		var batch: Dictionary = expected.batches[index]
		h._check(actual.species == batch.species and actual.animals.size() == batch.body.size() and actual.limbs.size() == batch.limbs.size(),
			"Original density-specific articulated batch composition and source species order")
		if actual.limbs.size() != batch.limbs.size() or actual.animals.size() != batch.body.size():
			return
		comparable.matrices.append({"id": actual.body, "frames": batch.body})
		for limb in range(actual.limbs.size()):
			comparable.matrices.append({"id": actual.limbs[limb].mesh, "frames": batch.limbs[limb]})
	preload("res://tests/wildlife_suite.gd")._compare(h, view, comparable)
