extends "res://tests/run.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/spectator_roster.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(capture.get("formatVersion") == 1 and capture.get("cases") is Array and capture.cases.size() == 4,
		"Capture original stable spectator roster programs")
	if failures == 0:
		for path: String in capture.source.inputs:
			var source := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(source.sha256_text() == capture.source.inputs[path], "Current spectator roster capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original spectator roster source: " + path)
	if failures == 0:
		for sample: Dictionary in capture.cases:
			var state := SpectatorState.new()
			state.configure(Content.balance.spectator, Vector3.ZERO, 10000, 68)
			state.position = Vector3.ZERO
			var rows: Array = []
			for source: Dictionary in sample.rows:
				var row := source.duplicate(true)
				row.position = Vector3(source.position[0], source.position[1], source.position[2])
				rows.append(row)
			var messages: Array = []
			state.notice.connect(func(message: String): messages.append(message))
			var order := state.roster(rows).map(func(row): return row.tag)
			_check(order == sample.ordered, "Original stable roster order: " + String(sample.name))
			state.follow(0, rows)
			var target := state.target(rows)
			_check(state.pid == sample.pid and target.get("tag") == sample.target,
				"Original nearest tie and followed entity: " + String(sample.name))
			_check(messages == sample.messages, "Original follow notice: " + String(sample.name))
	print("SPECTATOR_ROSTER assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
