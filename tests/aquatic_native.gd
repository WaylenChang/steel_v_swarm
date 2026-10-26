extends "res://tests/run.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/aquatic_native.json")
	_check(DisplayServer.get_name() != "headless", "Aquatic native buffer qualification requires a real renderer")
	_check(capture.get("formatVersion") == 1 and capture.get("source") is Dictionary and capture.get("aquaticPrograms") is Array,
		"Capture original aquatic factories and frame programs")
	if failures > 0:
		_finish_aquatic()
		return
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Aquatic capture input is current: " + path)
	for path: String in capture.source.sourceInputs:
		_check(provenance.get("inputs", {}).get(path) == capture.source.sourceInputs[path], "Aquatic oracle matches imported source: " + path)
	if failures == 0:
		preload("res://tests/aquatic_suite.gd").run(self, capture)
	_finish_aquatic()

func _finish_aquatic() -> void:
	print("AQUATIC_NATIVE assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
