extends "res://tests/run.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/scenery_rotor.json")
	_check(capture.get("formatVersion") == 1 and capture.get("source") is Dictionary and capture.get("programs") is Array,
		"Capture original edge rotor update methods")
	if failures > 0:
		_finish_rotor()
		return
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Rotor generator is current: " + path)
	for path: String in capture.source.sourceInputs:
		_check(provenance.get("inputs", {}).get(path) == capture.source.sourceInputs[path], "Rotor source matches imported provenance: " + path)
	if failures > 0:
		_finish_rotor()
		return
	preload("res://tests/scenery_motion_suite.gd").run(self, capture.referencePrograms)
	for program: Dictionary in capture.programs:
		var spec: Dictionary = program.motions[0]
		var anchor := SceneryMotion.create_anchor(spec)
		add_child(anchor)
		var pivot: Node3D = anchor.get_node("Pivot")
		var motion := SceneryMotion.new()
		_check(motion.configure(pivot, spec), "Bind the original rotor anchor and pivot")
		_compare(pivot, program.initial)
		for frame: Dictionary in program.frames:
			for index in range(int(frame.get("repeat", 1))):
				motion.advance(float(frame.delta), float(frame.now), frame.weather)
			_compare(pivot, frame)
		anchor.free()
	_finish_rotor()

func _compare(pivot: Node3D, frame: Dictionary) -> void:
	var expected: Transform3D = preload("res://tests/quaternion_suite.gd").frame(frame.matrix)
	_check(pivot.global_position.distance_to(expected.origin) < .001, "Original edge rotor parent frame and signed scale")
	for axis in range(3):
		_check(pivot.global_transform.basis[axis].distance_to(expected.basis[axis]) < .001,
			"Original rotor orientation retains fractional large angles and wind reversal")

func _finish_rotor() -> void:
	print("SCENERY_ROTOR assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
