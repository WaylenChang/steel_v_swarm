extends RefCounted

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("petalPrograms") or not fixtures.has("petalTransitions") or not fixtures.has("petalRules"):
		h._check(false, "Regenerate original petal field/prewarm/render programs")
		return
	for program: Dictionary in fixtures.petalPrograms:
		for low: bool in [false, true]:
			_run_variant(h, program, low)
	var motion := PetalMotion.new()
	motion.rules = fixtures.petalRules
	for program: Dictionary in fixtures.petalTransitions:
		var part: Dictionary = program.initial.duplicate(true)
		for frame: Dictionary in program.frames:
			var delta: float = float(frame.delta) if frame.delta != null else INF if frame.deltaKind == "infinity" else NAN
			motion.advance(part, delta, float(frame.time) if frame.time != null else NAN, frame.dynamics)
			for key: String in frame.part:
				if BodyMotionState._finite(frame.part[key]):
					h._check(BodyMotionState._finite(part.get(key)) and absf(float(part[key]) - float(frame.part[key])) < .00001,
						"Original directed petal landing/expiry/re-lift thresholds and invalid wind/time/delta behavior")
				else:
					h._check(part.get(key) == frame.part[key], "Original directed petal boolean state")

static func _run_variant(h: Node, program: Dictionary, low: bool) -> void:
	var root := Node3D.new()
	h.add_child(root)
	var saved := {}
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for variant: Dictionary in program.initial:
		for entry: Dictionary in variant.matrices:
			var node := MultiMeshInstance3D.new()
			node.multimesh = MultiMesh.new()
			node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
			node.multimesh.mesh = QuadMesh.new()
			node.material_override = material
			node.multimesh.instance_count = entry.frames.size()
			for index in range(entry.frames.size()):
				node.multimesh.set_instance_transform(index, _matrix(entry.frames[index]))
			node.set_meta("source_petal_mesh", int(entry.id))
			root.add_child(node)
			saved[int(entry.id)] = node.multimesh
	var height := func(x: float, z: float): return _height(program.mode, x, z)
	var water: Variant = 0 if program.mode == "wet" else null
	var code := func(x: float, z: float): return EnvironmentRules.ground_code(height.call(x, z), water)
	var view := PetalPresentation.new()
	h._check(view.configure(root, program.source, program.season, low, height, code), "Bind source petal season/power mode and private native batches")
	for variant: Dictionary in program.initial:
		for entry: Dictionary in variant.matrices:
			h._check(view.meshes[int(entry.id)].visible == (bool(variant.low) == low), "Only the accepted original petal power mode is visible")
		if bool(variant.low) == low:
			_compare(h, view, variant)
	for frame: Dictionary in program.frames:
		var delta: float = float(frame.delta) if frame.delta != null else INF if frame.deltaKind == "infinity" else NAN
		view.advance(delta, frame.weather)
		for variant: Dictionary in frame.variants:
			if bool(variant.low) == low:
				_compare(h, view, variant)
	for variant: Dictionary in program.initial:
		for entry: Dictionary in variant.matrices:
			var original: MultiMesh = saved[int(entry.id)]
			for index in range(original.instance_count):
				h._check(original.get_instance_transform(index).is_equal_approx(_matrix(entry.frames[index])), "Petal animation leaves saved MultiMesh transforms intact")
	h._check(material.render_priority == 0, "Petal render ordering does not mutate the shared source material")
	root.free()

static func _height(mode: String, x: float, z: float) -> float:
	if mode == "missing" and x > 0:
		return NAN
	if mode == "slope":
		return x * 0.02 + z * 0.01
	return (-3.0 if x > 0 else float(Content.constants.WATER.SWAMP_BAND) + 1) if mode == "wet" else 0.0

static func _matrix(values: Array) -> Transform3D:
	return preload("res://tests/quaternion_suite.gd").frame(values)

static func _compare(h: Node, view: PetalPresentation, expected: Dictionary) -> void:
	h._check(absf(view.time - float(expected.time)) < .00001, "Original petal local clock clamps zero, negative, nonfinite and hitched deltas")
	h._check(view.parts.size() == expected.parts.size(), "Original accepted/prewarmed petal roster count")
	for index in range(view.parts.size()):
		var actual: Dictionary = view.parts[index]
		var part: Dictionary = expected.parts[index]
		for key: String in ["y", "a", "ang", "ox", "oz", "oy", "slowPhase", "fastPhase", "groundTime", "fade", "restY"]:
			if not part.has(key):
				continue
			var value: Variant = actual.get(key)
			if part[key] == null:
				h._check(not BodyMotionState._finite(value), "Original missing petal landing height remains unavailable")
			else:
				h._check(BodyMotionState._finite(value) and absf(float(value) - float(part[key])) < .00001,
					"Original petal orbit/spin/two-phase fall, landing hold/fade, expiry and wind re-lift")
		for key: String in ["wasGrounded", "lifted", "restDry"]:
			h._check(ControlPreferences.truthy(actual.get(key)) == ControlPreferences.truthy(part.get(key)), "Original petal landing edge and cached dry-state lifecycle")
	for entry: Dictionary in expected.matrices:
		var mesh: MultiMesh = view.meshes[int(entry.id)].multimesh
		for index in range(mesh.instance_count):
			var actual := mesh.get_instance_transform(index)
			var frame := _matrix(entry.frames[index])
			h._check(actual.origin.distance_to(frame.origin) < .001, "Original petal orbit-centre frame, actual landing height and missing/wet-ground hiding")
			for axis in range(3):
				h._check(actual.basis[axis].distance_to(frame.basis[axis]) < .001,
					"Original per-particle spin axis, grounded Euler orientation, aspect and fade-scaled visibility")
