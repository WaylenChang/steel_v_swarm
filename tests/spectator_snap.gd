extends "res://tests/run.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/spectator_snap.json")
	_check(capture.get("formatVersion") == 1 and capture.get("cases") is Array and capture.cases.size() == 16,
		"Capture the original spectator anchor branch")
	if failures > 0:
		_finish_snap()
		return
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Spectator snap capture input is current: " + path)
	for path: String in capture.source.sourceInputs:
		_check(provenance.get("inputs", {}).get(path) == capture.source.sourceInputs[path], "Spectator snap source identity: " + path)
	_check(Content.balance.spectator.camera == capture.cameraRules, "Spectator camera settings match the captured source")
	if failures == 0:
		_check_cases(capture.cases)
	_finish_snap()

func _check_cases(cases: Array) -> void:
	for sample: Dictionary in cases:
		failure_scope = "spectator_snap_" + String(sample.name)
		var state := SpectatorState.new()
		state.configure(Content.balance.spectator, Vector3.ZERO, 10000, 68)
		state.mode = sample.view
		state.pid = "17"
		state.anchor = Vector3(sample.anchor[0], sample.anchor[1], sample.anchor[2])
		state.anchor_ok = sample.anchorOk
		var point := Vector3(sample.point[0], sample.point[1], sample.point[2])
		var source_distance := sqrt(SpectatorState._distance_squared(state.anchor, point))
		var bytes := PackedByteArray()
		bytes.resize(8)
		bytes.encode_double(0, source_distance)
		_check(bytes.hex_encode() == sample.distanceBits, "Original anchor distance retains its double precision")
		if sample.name == "above-by-small-y":
			_check(state.anchor.distance_to(point) == float(Content.balance.spectator.camera.SNAP_M),
				"The native Vector3 distance rounds this source-above threshold to equality")
		var actor := {"pid": "17", "side": "STEEL", "hero": true, "act": true, "ch": "", "dead": false,
			"position": point, "ry": 0.0, "heroY": 0.0}
		var surface := func(_point: Vector3) -> float: return -1000.0
		var pull := func(_start: Vector3, end: Vector3) -> Vector3: return end
		state.advance(float(sample.get("delta", 0)), [actor], {"f": 0, "r": 0, "mag": 0, "boost": false}, false, false, surface, 10000, pull)
		var expected := Vector3(sample.result.anchor[0], sample.result.anchor[1], sample.result.anchor[2])
		var matches := state.anchor == expected if sample.result.snap or not sample.has("delta") else state.anchor.distance_to(expected) < .000001
		_check(matches and state.anchor_ok == sample.result.anchorOk,
			"The original strict snap or smoothing branch is selected")
		_check(state.position == state.anchor, "Observer position follows the committed source anchor")

func _finish_snap() -> void:
	print("SPECTATOR_SNAP assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
