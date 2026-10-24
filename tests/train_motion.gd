extends "res://tests/run.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/train_motion.json")
	_check(capture.get("formatVersion") == 1 and capture.get("source") is Dictionary and capture.get("trainPrograms") is Array,
		"Capture original train driver and seasonal paths")
	if not failures.is_empty():
		_finish_train()
		return
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Train source capture input is current: " + path)
	for path: String in capture.source.sourceInputs:
		_check(provenance.get("inputs", {}).get(path) == capture.source.sourceInputs[path], "Train oracle matches imported source: " + path)
	if failures.is_empty():
		preload("res://tests/train_suite.gd").run(self, capture)
		for program: Dictionary in capture.trainPrograms:
			_reload(program)
	_finish_train()

func _reload(program: Dictionary) -> void:
	var source := Node3D.new()
	var path := SceneryTrainMotion.create_path(program.spec)
	source.add_child(path)
	for node: Node in source.find_children("*", "", true, false):
		node.owner = source
	var packed := PackedScene.new()
	var packed_ok := packed.pack(source) == OK
	_check(packed_ok, "Pack the original train polyline and constructor frame")
	source.free()
	if not packed_ok:
		return
	var output := "user://sol_train_motion.scn"
	var saved := ResourceSaver.save(packed, output) == OK
	_check(saved, "Save native train path for a disk reload")
	if not saved:
		return
	var loaded := ResourceLoader.load(output, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	_check(loaded != null, "Reload train resources independently of the live scene")
	if loaded == null:
		DirAccess.remove_absolute(output)
		return
	var root := loaded.instantiate() as Node3D
	add_child(root)
	var motion := SceneryTrainMotion.new()
	var configured := motion.configure(root, program.spec)
	_check(configured, "Rebind the packed native path, follower and train visual")
	if configured:
		var matrices = preload("res://tests/quaternion_suite.gd")
		_check((motion.follower.transform * motion.visual.transform).is_equal_approx(matrices.frame(program.spec.initialFrame)),
			"Reload retains the original constructor pose before the first update")
		for frame: Dictionary in program.frames:
			motion.advance(frame.delta)
			var actual: Transform3D = motion.follower.transform * motion.visual.transform
			var expected: Transform3D = matrices.frame(frame.matrix)
			_check(actual.origin.distance_to(expected.origin) < .001, "Reloaded train retains the source distance clock and endpoint reversal")
			for axis in range(3):
				_check(actual.basis[axis].distance_to(expected.basis[axis]) < .001,
					"Reloaded native curve retains the original source lookahead orientation")
	root.free()
	_check(DirAccess.remove_absolute(output) == OK, "Release temporary train resource after replay")

func _finish_train() -> void:
	print("TRAIN_MOTION assertions=", assertions, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
