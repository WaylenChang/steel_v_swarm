extends "res://tests/run.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/player_view_body.json")
	_check(capture.get("formatVersion") == 1 and capture.get("cases") is Array and capture.cases.size() == 15,
		"Capture the original third-person body-turn program")
	if failures == 0:
		var provenance: Dictionary = Content.read_json("res://data/provenance.json")
		for path: String in capture.source.inputs:
			var source := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(source.sha256_text() == capture.source.inputs[path], "Current body-turn capture input: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.get("inputs", {}).get(path) == capture.source.sourceInputs[path], "Original body-turn source identity: " + path)
		_check(float(Content.balance.playerView.bodyMovingSquared) == float(capture.threshold), "Original movement threshold is imported")
		_check(float(Content.constants.PLAYER_TPS.BODY_TURN_K) == float(capture.rate), "Original body-turn rate is imported")
	if failures == 0:
		for sample: Dictionary in capture.cases:
			failure_scope = "player_view_body_" + String(sample.name)
			var move := Vector3(sample.move[0], sample.move[1], sample.move[2])
			if sample.name == "below-float-rounds-up":
				_check(move.length_squared() > float(capture.threshold) and float(sample.movementSquared) < float(capture.threshold),
					"Native vector rounding crosses the threshold above the original")
			elif sample.name == "above-float-rounds-down":
				_check(move.length_squared() < float(capture.threshold) and float(sample.movementSquared) > float(capture.threshold),
					"Native vector rounding crosses the threshold below the original")
			var state := PlayerViewState.new()
			state.configure(Content.balance.playerView, sample.get("mode", "tps"), float(sample.yaw))
			state.body_yaw = float(sample.initialYaw)
			state.aiming = sample.get("aiming", false)
			for expected: float in sample.frames:
				state.advance_body(float(sample.delta), move, float(sample.yaw), sample.get("defending", false), sample.get("firing", false))
				_check(absf(state.body_yaw - expected) < 0.00000000001, "Original body heading and branch across consecutive frames")
	print("PLAYER_VIEW_BODY assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
