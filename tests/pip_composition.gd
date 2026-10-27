extends "res://tests/pip_native.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/pip.json")
	var composition: Dictionary = Content.read_json("res://tests/fixtures/pip_composition.json")
	_check(DisplayServer.get_name() != "headless", "PiP composition requires real rendered frames")
	_check(capture.get("pipFrames") is Array and capture.pipFrames.size() >= 6 and composition.get("cases") is Array and composition.cases.size() == 8,
		"PiP composition retains every captured source frame")
	if failures > 0:
		_finish_composition()
		return
	_check_pip_source_identity(capture, composition)
	if failures == 0:
		await _render_composition(capture.pipFrames, capture.rules, composition.cases)
	_finish_composition()

func _check_pip_source_identity(capture: Dictionary, composition: Dictionary) -> void:
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in capture.source.inputs:
		var source := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(source.sha256_text() == capture.source.inputs[path], "PiP reference generator is current: " + path)
	for path: String in composition.source.inputs:
		var source := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(source.sha256_text() == composition.source.inputs[path], "PiP composition generator is current: " + path)
	# These extracted render methods do not evaluate data.js RNG imports; pip_native keeps the full provenance gate.
	for path: String in composition.source.sourceInputs:
		var expected: String = composition.source.sourceInputs[path]
		_check(provenance.get("inputs", {}).get(path) == expected and capture.source.sourceInputs.get(path) == expected,
			"Both PiP captures retain their original rendering input: " + path)
	_check(capture.rules == Content.balance.get("pip") and composition.runtime.color == Content.side_info("STEEL").color,
		"PiP composition uses the original rules and faction color")
	_check(composition.runtime.webgl == "webgl2" and float(composition.runtime.deviceScaleFactor) == 1.0,
		"PiP composition retains its original WebGL and pixel-ratio capture")

func _finish_composition() -> void:
	print("PIP_COMPOSITION_NATIVE assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
