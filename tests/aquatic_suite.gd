extends RefCounted

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("aquaticPrograms"):
		h._check(false, "Regenerate original aquatic factory/motion/RNG programs")
		return
	for program: Dictionary in fixtures.aquaticPrograms:
		var root := Node3D.new()
		h.add_child(root)
		var saved := {}
		var saved_points: Array[ArrayMesh] = []
		for system: Dictionary in program.source.systems:
			if system.kind != "detritus":
				continue
			var node := AquaticDetritus.create_node(system)
			root.add_child(node)
			saved_points.append(node.mesh)
		for entry: Dictionary in program.initial.matrices:
			var node := MultiMeshInstance3D.new()
			node.multimesh = MultiMesh.new()
			node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
			node.multimesh.mesh = SphereMesh.new()
			node.multimesh.instance_count = entry.frames.size()
			for index in range(entry.frames.size()):
				node.multimesh.set_instance_transform(index, _matrix(entry.frames[index]))
			node.multimesh.visible_instance_count = int(entry.count)
			node.set_meta("source_aquatic_mesh", int(entry.id))
			root.add_child(node)
			saved[int(entry.id)] = node.multimesh
		var pivots := {}
		var motions: Array[SceneryMotion] = []
		for spec: Dictionary in program.motions:
			var anchor := SceneryMotion.create_anchor(spec)
			var parent: Node3D = pivots[int(spec.parentMotion)] if int(spec.parentMotion) > 0 else root
			parent.add_child(anchor)
			var pivot: Node3D = anchor.get_node("Pivot")
			pivots[int(spec.id)] = pivot
			var motion := SceneryMotion.new()
			h._check(motion.configure(pivot, spec), "Bind original cruising/moored/submersible vessel and nested wake pivots")
			motions.append(motion)
		var view := AquaticPresentation.new()
		var waves := MarineWaveSources.new()
		h._check(waves.configure(int(program.waveCapacity), program.initial.waves.sources, program.initial.waves.shapes),
			"Bind original accepted vessel source packets before the first motion frame")
		h._check(view.configure(root, program.source), "Bind original aquatic fish/jelly/bubble meshes and resume private bubble RNG")
		_compare(h, view, pivots, program.initial)
		for frame: Dictionary in program.frames:
			view.advance(frame.delta, frame.time)
			for motion: SceneryMotion in motions:
				motion.advance(frame.delta, frame.time, {"waveAmp": frame.waveAmp})
			waves.update_vessels(motions, float(frame.waveAmp) <= 0.001)
			preload("res://tests/marine_suite.gd").packets(h, waves.sources, frame.result.waves.sources,
				"Original moving/moored wave source order, local hull position, yaw, freeze and resume")
			preload("res://tests/marine_suite.gd").packets(h, waves.shapes, frame.result.waves.shapes,
				"Original submerged-vessel exclusion and immutable accepted hull dimensions")
			_compare(h, view, pivots, frame.result)
		for entry: Dictionary in program.initial.matrices:
			var original: MultiMesh = saved[int(entry.id)]
			for index in range(original.instance_count):
				h._check(original.get_instance_transform(index).is_equal_approx(_matrix(entry.frames[index])), "Aquatic updates preserve saved shared MultiMesh buffers")
		for mesh: ArrayMesh in saved_points:
			for system: Dictionary in program.source.systems:
				if system.kind != "detritus":
					continue
				var arrays := mesh.surface_get_arrays(0)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for index in range(vertices.size()):
					h._check(vertices[index] == Vector3(system.positions[index * 3], system.positions[index * 3 + 1], system.positions[index * 3 + 2]),
						"Suspended detritus updates preserve saved shared point buffers")
		root.free()

static func _matrix(values: Array) -> Transform3D:
	return preload("res://tests/quaternion_suite.gd").frame(values)

static func _compare(h: Node, view: AquaticPresentation, pivots: Dictionary, source: Dictionary) -> void:
	if source.detritus != null:
		for system: Dictionary in view.systems:
			if system.kind != "detritus":
				continue
			var motion: AquaticDetritus = system.motion
			for index in range(motion.positions.size()):
				h._check(absf(float(motion.positions[index]) - float(source.detritus.positions[index])) < .00001,
					"Original suspended detritus Float32 positions, two-axis drift, floor recycling and dormant points")
			for index in range(motion.particles.size()):
				h._check(absf(float(motion.particles[index].y) - float(source.detritus.particles[index].y)) < .00001,
					"Original suspended detritus scalar sinking and discarded overshoot")
	for entry: Dictionary in source.matrices:
		var mesh: MultiMesh = view.meshes[int(entry.id)].multimesh
		var count := mesh.instance_count if mesh.visible_instance_count < 0 else mesh.visible_instance_count
		h._check(count == int(entry.count), "Original aquatic active instance count, including constructor and dormant slots")
		for index in range(mesh.instance_count):
			_frame(h, mesh.get_instance_transform(index), _matrix(entry.frames[index]), "Original bubble expansion/wobble and fish/jelly school/pulse pose")
	for entry: Dictionary in source.pivots:
		_frame(h, pivots[int(entry.id)].global_transform, _matrix(entry.matrix), "Original vessel tangent/bounds/roll/pitch, frozen hold and nested wake scale")
	if source.bubbles != null:
		for system: Dictionary in view.systems:
			if system.kind != "bubble":
				continue
			h._check(int(system.draws) == int(source.bubbles.draws), "Original bubble-only random consumption through initialization and simultaneous surface resets")
			for index in range(system.particles.size()):
				var actual: Dictionary = system.particles[index]
				var expected: Dictionary = source.bubbles.particles[index]
				for key: String in ["y", "wobblePh"]:
					if expected.has(key):
						h._check(absf(float(actual[key]) - float(expected[key])) < .00001, "Original bubble surface-reset/discarded overshoot and independent RNG continuation")

static func _frame(h: Node, actual: Transform3D, expected: Transform3D, description: String) -> void:
	h._check(actual.origin.distance_to(expected.origin) < .002, description)
	for axis in range(3):
		h._check(actual.basis[axis].distance_to(expected.basis[axis]) < .002, description)
