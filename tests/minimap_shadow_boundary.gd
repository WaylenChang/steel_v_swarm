extends "res://tests/run.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/minimap_shadow_boundary.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(DisplayServer.get_name() != "headless", "Minimap shadow boundary requires a real display driver")
	_check(capture.get("formatVersion") == 1 and capture.get("cases") is Array and capture.cases.size() == 7,
		"Capture original minimap shadow boundary cases")
	if failures == 0:
		for path: String in capture.source.inputs:
			var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(text.sha256_text() == capture.source.inputs[path], "Current shadow capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original shadow input: " + path)
	if failures == 0:
		for sample: Dictionary in capture.cases:
			var point := Vector2(sample.point[0], sample.point[1])
			var actual: Variant = MinimapVision.shadows(point, float(sample.sight), sample.blockers)
			if sample.shadows == null:
				_check(actual == null, "Original absent blocker list: " + sample.name)
				continue
			_check(actual is Array and actual.size() == sample.shadows.size(), "Original shadow boundary: " + sample.name)
			if not actual is Array or actual.size() != sample.shadows.size():
				continue
			for i in actual.size():
				for vertex in 4:
					for axis in 2:
						_check(absf(float(actual[i][vertex][axis]) - float(sample.shadows[i][vertex][axis])) < 0.000001,
							"Original tangent geometry: " + sample.name)
	print("MINIMAP_SHADOW_BOUNDARY assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
