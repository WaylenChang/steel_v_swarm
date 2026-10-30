extends "res://tests/run.gd"

const DeathState = preload("res://scripts/pip_death_state.gd")

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/pip_death_pose.json")
	var data: Dictionary = Content.read_json("res://data/pip_death_pose.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(capture.get("formatVersion") == 1 and capture.get("cases") is Array and capture.cases.size() == 48,
		"Capture original source and fallback death-view eye positions")
	_check(data == {"formatVersion": capture.formatVersion, "source": capture.source, "rules": capture.rules},
		"Native eye constants retain the original camera branches")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Current death-view eye capture: " + path)
	for path: String in capture.source.sourceInputs:
		_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original death-view eye source: " + path)
	for sample: Dictionary in capture.cases:
		var point := Vector3(sample.point[0], sample.point[1], sample.point[2])
		var parameter: Variant = NAN if sample.parameter is String and sample.parameter == "NaN" else sample.parameter
		var source: Variant = point if sample.mode == "source" else null
		var top: Variant = parameter if sample.mode == "source" else null
		var ground := 0.0 if sample.mode == "source" else float(parameter)
		var actual: Vector3 = DeathState.eye_position(source, top, Vector2(point.x, point.z), ground, data.rules)
		var expected := Vector3(str(sample.eyeFloat32Bits[0]).hex_decode().decode_float(0),
			str(sample.eyeFloat32Bits[1]).hex_decode().decode_float(0), str(sample.eyeFloat32Bits[2]).hex_decode().decode_float(0))
		_check(actual == expected, "Original source/fallback eye rounds only at native storage: " + str(sample))
		_check(int(sample.surfaceCalls) == (0 if sample.mode == "source" else 1), "Original ground query is used only for the no-source fallback")
	print("PIP_DEATH_POSE assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
