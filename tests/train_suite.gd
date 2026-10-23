extends RefCounted

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("trainPrograms"):
		h._check(false, "Regenerate original trainDriver programs")
		return
	var matrices = preload("res://tests/quaternion_suite.gd")
	for program: Dictionary in fixtures.trainPrograms:
		var root := Node3D.new()
		h.add_child(root)
		var path := SceneryTrainMotion.create_path(program.spec)
		root.add_child(path)
		var motion := SceneryTrainMotion.new()
		h._check(motion.configure(root, program.spec), "Bind original train to native Path3D/PathFollow3D")
		var initial: Transform3D = motion.follower.transform * motion.visual.transform
		h._check(initial.is_equal_approx(matrices.frame(program.spec.initialFrame)), "Original train retains its constructor pose before the first update")
		for frame: Dictionary in program.frames:
			motion.advance(frame.delta)
			var actual: Transform3D = motion.follower.transform * motion.visual.transform
			var expected: Transform3D = matrices.frame(frame.matrix)
			h._check(actual.origin.distance_to(expected.origin) < .001, "Original train distance clock, zero/hitched frames and discarded overshoot on native polyline")
			for axis in range(3):
				h._check(actual.basis[axis].distance_to(expected.basis[axis]) < .001,
					"Original positive-Z train lookahead, endpoint heading hold and vertical lookAt perturbation")
		root.free()
