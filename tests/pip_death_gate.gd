extends "res://tests/run.gd"

const DeathState = preload("res://scripts/pip_death_state.gd")

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/pip_death_gate.json")
	var data: Dictionary = Content.read_json("res://data/pip_death_gate.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(capture.get("formatVersion") == 1 and capture.get("programs") is Array and capture.programs.size() == 13,
		"Capture original death-view gates and scissor geometry")
	_check(data == {"formatVersion": capture.formatVersion, "source": capture.source, "rules": capture.rules},
		"Native death-view border and threshold retain the source values")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Current death-view gate capture: " + path)
	for path: String in capture.source.sourceInputs:
		_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original death-view gate source: " + path)
	for sample: Dictionary in capture.programs:
		var ready := DeathState.can_prepare(bool(sample.dead), bool(sample.get("deathSeq", false)), bool(sample.get("gameOver", false)),
			String(sample.side), not bool(sample.get("missingConfig", false)), not bool(sample.get("missingFrame", false)), not bool(sample.get("hidden", false)))
		_check(ready == bool(sample.prepared), "Original death-view preparation gate: " + sample.name)
		if not ready:
			continue
		var viewport := DeathState.viewport(sample.frame, sample.canvas, float(sample.canvas.height), data.rules)
		_check(not viewport.is_empty() == bool(sample.rendered), "Original inset size gate: " + sample.name)
		if not viewport.is_empty():
			for index in 4:
				var actual: float = viewport[["x", "y", "width", "height"][index]]
				_check(_bits(actual) == sample.viewportBits[index], "Original scalar scissor boundary: " + sample.name)
	print("PIP_DEATH_GATE assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _bits(value: float) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	return bytes.hex_encode()
