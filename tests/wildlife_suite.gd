extends RefCounted

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("wildlifePrograms") or not fixtures.has("wildlifeActivity"):
		h._check(false, "Regenerate original wildlife route/integration/batch programs")
		return
	for item: Dictionary in fixtures.wildlifeActivity:
		h._check(absf(WeatherRules.wildlife_activity(item.dyn) - float(item.value)) < .000001,
			"Original airborne wildlife activity follows resolved rain, snow, sand and wind strength")
	for program: Dictionary in fixtures.wildlifePrograms:
		for low: bool in [false, true]:
			_run_variant(h, program, low)

static func _run_variant(h: Node, program: Dictionary, low: bool) -> void:
	var root := Node3D.new()
	h.add_child(root)
	var originals := {}
	for variant: Dictionary in program.initial:
		for entry: Dictionary in variant.matrices:
			var node := MultiMeshInstance3D.new()
			node.multimesh = MultiMesh.new()
			node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
			node.multimesh.mesh = BoxMesh.new()
			node.multimesh.instance_count = entry.frames.size()
			for index in range(entry.frames.size()):
				node.multimesh.set_instance_transform(index, _matrix(entry.frames[index]))
			node.set_meta("source_wildlife_mesh", int(entry.id))
			root.add_child(node)
			originals[int(entry.id)] = node.multimesh
	var height := func(x: float, z: float): return _height(program.mode, x, z)
	var dry := func(_x: float, z: float): return absf(z) < 4
	var water := {"value": 0.0}
	var code := func(x: float, z: float): return EnvironmentRules.ground_code(height.call(x, z), water.value, [], dry.call(x, z))
	var view := WildlifePresentation.new()
	h._check(view.configure(root, program.source, low, height, code, dry, func(): return water.value), "Bind original full/low-power wildlife batches and habitats")
	for variant: Dictionary in program.initial:
		for entry: Dictionary in variant.matrices:
			h._check(view.meshes[int(entry.id)].visible == (bool(variant.low) == low), "Only the selected original wildlife roster is visible")
		if bool(variant.low) == low:
			_compare(h, view, variant)
	for item: Dictionary in program.habitat:
		h._check(view.habitat.occupied(item.x, item.z) == bool(item.occupied),
			"Original frozen footprint grid, strict circle/rotated-box tangency and zero-depth boxes")
		h._check(int(code.call(item.x, item.z)) == int(item.code) and bool(dry.call(item.x, item.z)) == bool(item.dry),
			"Wildlife uses the original terrain code and independent dry-band predicate")
		h._check(view.habitat.valid_at(item.x, item.z, 0) == bool(item.valid) and view.habitat.wet_at(item.x, item.z) == bool(item.wet),
			"Original wildlife dry/wet habitat admission")
	for frame: Dictionary in program.frames:
		water.value = frame.waterY
		if frame.snap:
			for state: WildlifeState in view.states:
				state.snap()
		view.advance(float(frame.delta) if frame.delta != null else NAN,
			float(frame.time) if frame.time != null else NAN, {"activity": frame.activity})
		for variant: Dictionary in frame.variants:
			if bool(variant.low) == low:
				_compare(h, view, variant)
	for variant: Dictionary in program.initial:
		for entry: Dictionary in variant.matrices:
			var saved: MultiMesh = originals[int(entry.id)]
			for index in range(saved.instance_count):
				h._check(saved.get_instance_transform(index).is_equal_approx(_matrix(entry.frames[index])), "Wildlife motion never changes the saved shared MultiMesh buffers")
	root.free()

static func _height(mode: String, x: float, z: float) -> float:
	if mode == "missing" and x > 0:
		return NAN
	if mode == "wet":
		return -4
	if mode == "split":
		return -4 if x < 0 else 4
	return 10 + x * 0.01 - z * 0.005

static func _matrix(value: Array) -> Transform3D:
	return preload("res://tests/quaternion_suite.gd").frame(value)

static func _compare(h: Node, view: WildlifePresentation, expected: Dictionary) -> void:
	h._check(view.states.size() == expected.states.size(), "Original wildlife route roster preserves budget and species order")
	for index in range(view.states.size()):
		var state := view.states[index]
		var sample: Dictionary = expected.states[index]
		h._check(absf(state.time - float(sample.t)) < .00001, "Original staggered wildlife route time and invalid-frame rejection")
		for j in range(state.positions.size()):
			h._check(absf(float(state.positions[j]) - float(sample.pos[j])) < .003
				and absf(float(state.velocities[j]) - float(sample.vel[j])) < .003,
				"Original Float32 weak-spring/noise/friction integrator, hitch accumulation and snap recovery")
	for entry: Dictionary in expected.matrices:
		var mesh: MultiMesh = view.meshes[int(entry.id)].multimesh
		for index in range(mesh.instance_count):
			var actual := mesh.get_instance_transform(index)
			var frame := _matrix(entry.frames[index])
			h._check(actual.origin.distance_to(frame.origin) < .003, "Original wildlife terrain/water/bounce height and invalid-position hiding")
			for axis in range(3):
				h._check(actual.basis[axis].distance_to(frame.basis[axis]) < .003,
					"Original wildlife activity/bounds/wet/occupied gates, heading, wing/tail/leg joint order")
