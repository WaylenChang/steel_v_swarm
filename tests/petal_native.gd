extends "res://tests/run.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/petal_native.json")
	_check(DisplayServer.get_name() != "headless", "Petal instance-buffer qualification requires a real renderer")
	_check(capture.get("formatVersion") == 1 and capture.get("source") is Dictionary and capture.get("petalPrograms") is Array,
		"Capture original petal planning, constructor and frame programs")
	if failures > 0:
		_finish_petals()
		return
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Petal capture input is current: " + path)
	for path: String in capture.source.sourceInputs:
		_check(provenance.get("inputs", {}).get(path) == capture.source.sourceInputs[path], "Petal oracle matches imported source: " + path)
	if failures == 0:
		preload("res://tests/petal_suite.gd").run(self, capture)
	_finish_petals()

func _finish_petals() -> void:
	print("PETAL_NATIVE assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
