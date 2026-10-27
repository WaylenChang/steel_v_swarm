extends "res://tests/run.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/spectator_anchor.json")
	_check(capture.get("formatVersion") == 1 and capture.get("sequences") is Array and capture.sequences.size() == 5,
		"Capture original multi-frame spectator anchors")
	if failures > 0:
		_finish_anchor()
		return
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Spectator anchor capture input is current: " + path)
	for path: String in capture.source.sourceInputs:
		_check(provenance.get("inputs", {}).get(path) == capture.source.sourceInputs[path], "Spectator anchor source identity: " + path)
	_check(Content.balance.spectator.camera == capture.cameraRules, "Spectator camera settings match the captured source")
	if failures == 0:
		_check_sequences(capture.sequences)
		_check_anchor_reset()
	_finish_anchor()

func _check_sequences(sequences: Array) -> void:
	var report: Array = []
	for sequence: Dictionary in sequences:
		failure_scope = "spectator_anchor_" + String(sequence.name)
		var state := SpectatorState.new()
		state.configure(Content.balance.spectator, Vector3.ZERO, 10000, 68)
		state.pid = "17"
		state.anchor = Vector3(sequence.anchor[0], sequence.anchor[1], sequence.anchor[2])
		state.anchor_ok = sequence.anchorOk
		var actor := {"pid": "17", "side": "STEEL", "hero": true, "act": true, "ch": "", "dead": false,
			"position": Vector3.ZERO, "ry": 0.0, "heroY": 0.0}
		var surface := func(_point: Vector3) -> float: return -1000.0
		var pull := func(_start: Vector3, end: Vector3) -> Vector3: return end
		var mismatches := 0
		var precise_mismatches := 0
		var alpha_mismatches := 0
		var witnesses: Array = []
		var precise_witnesses: Array = []
		var alpha_witnesses: Dictionary = {}
		for index in sequence.frames.size():
			var frame: Dictionary = sequence.frames[index]
			if frame.has("setAnchorOk"):
				state.anchor_ok = frame.setAnchorOk
			state.mode = frame.view
			actor.position = Vector3(frame.point[0], frame.point[1], frame.point[2])
			var delta := str(frame.deltaBits).hex_decode().decode_double(0)
			var argument := -maxf(0.0, float(Content.balance.spectator.camera.POS_K)) * maxf(0.0, delta)
			var exponential := exp(argument)
			var alpha := 1.0 - exponential
			var alpha_bits := _double_bits(alpha)
			_check(_double_bits(argument) == frame.argumentBits and _double_bits(exponential) == frame.exponentialBits and alpha_bits == frame.alphaBits,
				"Source smoothing coefficient retains its double precision at frame " + str(index))
			var distance := sqrt(SpectatorState._distance_squared_xyz(state._anchor_x, state._anchor_y, state._anchor_z, actor.position))
			_check(_double_bits(distance) == frame.distanceBits, "Source anchor distance retains its double precision at frame " + str(index))
			if alpha_bits != String(frame.alphaBits):
				alpha_mismatches += 1
				if not alpha_witnesses.has(str(frame.delta)):
					alpha_witnesses[str(frame.delta)] = {"source": frame.alphaBits, "native": alpha_bits,
						"sourceValue": str(frame.alphaBits).hex_decode().decode_double(0), "nativeValue": alpha,
						"sourceArgument": frame.argumentBits, "nativeArgument": _double_bits(argument),
						"sourceExp": frame.exponentialBits, "nativeExp": _double_bits(exponential)}
			state.advance(delta, [actor], {"f": 0, "r": 0, "mag": 0, "boost": false}, false, false, surface, 10000, pull)
			var precise := [_double_bits(state._anchor_x), _double_bits(state._anchor_y), _double_bits(state._anchor_z)]
			var precise_same: bool = precise == frame.anchorBits
			if not precise_same:
				precise_mismatches += 1
				if precise_witnesses.size() < 5:
					precise_witnesses.append({"frame": index, "expected": frame.anchorBits, "actual": precise})
			_check(precise_same, "Source anchor retains its double precision at frame " + str(index))
			var actual := _vector_bits(state.anchor)
			var same: bool = actual == frame.anchorFloat32Bits
			if not same:
				mismatches += 1
				if witnesses.size() < 5:
					witnesses.append({"frame": index, "expected": frame.anchorFloat32Bits, "actual": actual})
			_check(same, "Source anchor reaches the same native Float32 position at frame " + str(index))
			_check(state.anchor_ok == frame.anchorOk, "Source anchor validity at frame " + str(index))
		report.append({"name": sequence.name, "frames": sequence.frames.size(), "mismatches": mismatches,
			"preciseMismatches": precise_mismatches, "preciseWitnesses": precise_witnesses,
			"alphaMismatches": alpha_mismatches, "alphaWitnesses": alpha_witnesses, "witnesses": witnesses})
	var suffix := "final" if OS.get_cmdline_user_args().has("--final") else "baseline"
	var report_dir := ProjectSettings.globalize_path("res://artifacts/terra")
	var directory_status := DirAccess.make_dir_recursive_absolute(report_dir)
	_check(directory_status == OK, "Create the multi-frame anchor evidence directory")
	if directory_status != OK:
		return
	var file := FileAccess.open("res://artifacts/terra/spectator-anchor-" + suffix + ".json", FileAccess.WRITE)
	_check(file != null, "Retain source/native multi-frame anchor witnesses")
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()

func _check_anchor_reset() -> void:
	failure_scope = "spectator_anchor_reset"
	var state := SpectatorState.new()
	state.configure(Content.balance.spectator, Vector3.ZERO, 10000, 68)
	state.pid = "17"
	state.anchor = Vector3(1024, 0, 0)
	state.anchor_ok = true
	var actor := {"pid": "17", "side": "STEEL", "hero": true, "act": true, "ch": "", "dead": false,
		"position": Vector3(1024.0001220703125, 0, 0), "ry": 0.0, "heroY": 0.0}
	var surface := func(_point: Vector3) -> float: return -1000.0
	var pull := func(_start: Vector3, end: Vector3) -> Vector3: return end
	state.mode = "orbit"
	state.advance(1.0 / 240.0, [actor], {"f": 0, "r": 0, "mag": 0, "boost": false}, false, false, surface, 10000, pull)
	_check(state._anchor_x != float(state.anchor.x), "Smoothing retains precision beyond the exposed Vector3")
	state.anchor = Vector3(2048, -4, 3)
	_check([state._anchor_x, state._anchor_y, state._anchor_z] == [2048.0, -4.0, 3.0],
		"Assigning an anchor replaces all retained coordinates")
	state.configure(Content.balance.spectator, Vector3.ZERO, 10000, 68)
	_check(state.anchor == Vector3.ZERO and not state.anchor_ok and [state._anchor_x, state._anchor_y, state._anchor_z] == [0.0, 0.0, 0.0],
		"Reconfiguration clears the exposed and retained anchor")

func _double_bits(value: float) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	return bytes.hex_encode()

func _vector_bits(value: Vector3) -> Array:
	var result: Array = []
	for component: float in [value.x, value.y, value.z]:
		var bytes := PackedByteArray()
		bytes.resize(4)
		bytes.encode_float(0, component)
		result.append(bytes.hex_encode())
	return result

func _finish_anchor() -> void:
	print("SPECTATOR_ANCHOR assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
