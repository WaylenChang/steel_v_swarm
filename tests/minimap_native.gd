extends "res://tests/run.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/minimap_native.json")
	_check(DisplayServer.get_name() != "headless", "Native minimap mask qualification requires a real renderer")
	_check(capture.get("formatVersion") == 1 and capture.get("source") is Dictionary and capture.get("minimapFog") is Dictionary,
		"Capture original minimap decision and canvas programs")
	if not failures.is_empty():
		_finish_minimap()
		return
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Minimap capture input is current: " + path)
	for path: String in capture.source.sourceInputs:
		_check(provenance.get("inputs", {}).get(path) == capture.source.sourceInputs[path], "Minimap oracle matches imported source: " + path)
	_check(Content.balance.get("minimap") == capture.get("metadata"), "Native minimap rules and canvas defaults match original source")
	if failures.is_empty():
		preload("res://tests/minimap_suite.gd").run(self, capture)
		preload("res://tests/minimap_vision_suite.gd").run(self, capture)
		preload("res://tests/minimap_mask_suite.gd").run(self, capture)
	_finish_minimap()

func _finish_minimap() -> void:
	print("MINIMAP_NATIVE assertions=", assertions, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
