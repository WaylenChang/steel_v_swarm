extends "res://tests/run.gd"

const DeathState = preload("res://scripts/pip_death_state.gd")

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/pip_death_selection.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(capture.get("formatVersion") == 1 and capture.get("programs") is Array and capture.programs.size() == 19,
		"Capture original death-view selection and visibility gates")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Current death-view capture: " + path)
	for path: String in capture.source.sourceInputs:
		_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original death-view source identity: " + path)
	for program: Dictionary in capture.programs:
		_check(bool(program.restored), "The original restores source and cockpit visibility: " + program.name)
		if not program.rendered:
			continue
		var rows: Array = []
		for original: Dictionary in program.rows:
			var row := original.duplicate(true)
			row.mesh = bool(row.get("mesh", true))
			row.position = Vector3(_coordinate(row.position[0]), _coordinate(row.position[1]), _coordinate(row.position[2]))
			rows.append(row)
		var selected: Variant = DeathState.source(rows, program.side, Vector2(program.enemy[0], program.enemy[1]))
		var identifier: Variant = selected.id if selected != null else null
		_check(identifier == program.selected, "Original stable frontline tower/base selection: " + program.name)
	_check(DeathState.source([{"kind": "tower", "side": "STEEL", "position": Vector3.ZERO}], "STEEL", Vector2.ZERO) == null,
		"A missing model-availability field cannot create an unsupported camera source")
	print("PIP_DEATH_SELECTION assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _coordinate(value: Variant) -> float:
	if value is String:
		if value == "NaN":
			return NAN
		if value == "Infinity":
			return INF
	return float(value)
