extends RefCounted

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("sceneryMotionPrograms") or not fixtures.has("waterfallMotionPrograms"):
		h._check(false, "Regenerate original part/edge scenery motion programs")
		return
	for program: Dictionary in fixtures.sceneryMotionPrograms:
		SceneryPresentation.wind_time = 0
		SceneryPresentation.wind_phase = 0
		SceneryPresentation.wave_phase = 0
		SceneryPresentation.gust_phase = 0
		var root := Node3D.new()
		h.add_child(root)
		var nodes := {}
		for spec: Dictionary in program.motions:
			var anchor := SceneryMotion.create_anchor(spec)
			var parent: Node3D = nodes[int(spec.parentMotion)] if int(spec.parentMotion) > 0 else root
			parent.add_child(anchor)
			var pivot: Node3D = anchor.get_node("Pivot")
			pivot.set_meta("source_motion_id", int(spec.id))
			nodes[int(spec.id)] = pivot
		var presentation := SceneryPresentation.new()
		h._check(presentation.configure(root, [], program.motions), "Bind captured native scenery motion hierarchy")
		_compare(h, nodes, program.initial)
		for frame: Dictionary in program.frames:
			for motion: SceneryMotion in presentation.motions:
				motion.paused = frame.paused
			presentation.advance(frame.delta, frame.weather)
			h._check(absf(SceneryPresentation.wind_time - float(frame.now)) < .00001, "Original shared scenery wind clock clamps negative and hitched frames")
			var phases := [SceneryPresentation.wind_phase, SceneryPresentation.wave_phase, SceneryPresentation.gust_phase]
			var wind := WeatherRules.wind_profile(frame.weather)
			var water := WeatherRules.water_profile(frame.weather)
			for axis in range(3):
				h._check(absf(phases[axis] - float(frame.phases[axis])) < .00001,
					"Original wind/wave/gust phases integrate rate changes and frozen intervals without phase jumps")
			for axis in range(4):
				h._check(absf(wind[axis] - float(frame.windShape[axis])) < .00001 and absf(water[axis] - float(frame.waterShape[axis])) < .00001,
					"Original clamped weather shape profiles for wind, swell, chop and whitecaps")
			_compare(h, nodes, frame.matrices)
		root.free()
	_waterfalls(h, fixtures.waterfallMotionPrograms)

static func _waterfalls(h: Node, programs: Array) -> void:
	for program: Dictionary in programs:
		var root := Node3D.new()
		h.add_child(root)
		var nodes := {}
		var motions: Array[SceneryMotion] = []
		var shared := {}
		for spec: Dictionary in program.motions:
			var anchor := SceneryMotion.create_anchor(spec)
			root.add_child(anchor)
			var pivot: Node3D = anchor.get_node("Pivot")
			nodes[int(spec.id)] = pivot
			if spec.kind == "waterfall_sheet":
				var index := int(spec.index)
				if not shared.has(index):
					var material := StandardMaterial3D.new()
					material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					material.albedo_color.a = 0.85 if index == 0 else 0.55
					shared[index] = material
				var mesh := MeshInstance3D.new()
				mesh.name = "SheetVisual"
				mesh.mesh = QuadMesh.new()
				mesh.material_override = shared[index]
				pivot.add_child(mesh)
			var motion := SceneryMotion.new()
			h._check(motion.configure(pivot, spec), "Bind original waterfall sheet/foam clock and native material")
			motions.append(motion)
		_compare(h, nodes, program.initial)
		for frame: Dictionary in program.frames:
			for motion: SceneryMotion in motions:
				motion.advance(frame.delta, 0, {})
			_compare(h, nodes, frame.matrices)
		for index: int in shared:
			h._check(absf(shared[index].albedo_color.a - (0.85 if index == 0 else 0.55)) < .00001,
				"Waterfall opacity never mutates shared imported materials")
		root.free()

static func _compare(h: Node, nodes: Dictionary, frames: Array) -> void:
	var matrices = preload("res://tests/quaternion_suite.gd")
	for frame: Dictionary in frames:
		var actual: Transform3D = nodes[int(frame.id)].global_transform
		var expected: Transform3D = matrices.frame(frame.matrix)
		h._check(actual.origin.distance_to(expected.origin) < .001, "Original scenery bind/pivot/waterline position and wind/wave displacement")
		for axis in range(3):
			h._check(actual.basis[axis].distance_to(expected.basis[axis]) < .001,
				"Original source Euler order, signed spin, swing, paused joints, rotor heading/reversal and frozen floats")
		if frame.has("opacity"):
			var mesh: MeshInstance3D = nodes[int(frame.id)].get_node("SheetVisual")
			h._check(absf(mesh.get_active_material(0).albedo_color.a - float(frame.opacity)) < .00001,
				"Original waterfall layers retain independent opacity pulses and first-update phase")
