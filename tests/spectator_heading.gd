extends "res://tests/run.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/spectator_heading.json")
	_check(capture.get("formatVersion") == 1 and capture.get("cases") is Array and capture.cases.size() == 300,
		"Capture the original spectator heading branch")
	if failures == 0:
		var provenance: Dictionary = Content.read_json("res://data/provenance.json")
		for path: String in capture.source.inputs:
			var source := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(source.sha256_text() == capture.source.inputs[path], "Current spectator heading capture input: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.get("inputs", {}).get(path) == capture.source.sourceInputs[path], "Original spectator heading source identity: " + path)
		_check(Content.balance.spectator.camera == capture.rules, "Spectator camera settings match the original")
	if failures == 0:
		_check_cases(capture.cases)
	print("SPECTATOR_HEADING assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_cases(cases: Array) -> void:
	var surface := func(_point: Vector3) -> float: return -1000.0
	var pull := func(_start: Vector3, end: Vector3) -> Vector3: return end
	var witnesses: Array = []
	var mismatch_count := 0
	failure_scope = "spectator_heading"
	for index in cases.size():
		var sample: Dictionary = cases[index]
		var state := SpectatorState.new()
		state.configure(Content.balance.spectator, Vector3.ZERO, 10000, 68)
		state.mode = sample.mode
		state.pid = "17"
		state.follow_yaw = str(sample.initialBits).hex_decode().decode_double(0)
		var actor := {"pid": "17", "side": "STEEL", "hero": true, "act": true, "ch": "t01",
			"dead": false, "position": Vector3.ZERO, "heroY": 0.0}
		if sample.kind == "null":
			actor.ry = null
		elif sample.targetBits != null:
			actor.ry = str(sample.targetBits).hex_decode().decode_double(0)
		var delta := str(sample.deltaBits).hex_decode().decode_double(0)
		var commands: Variant = state.advance(delta, [actor], {"f": 0, "r": 0, "mag": 0, "boost": false}, false, false, surface, 10000, pull)
		var actual := _bits(state.follow_yaw)
		if not commands is Array or actual != sample.resultBits:
			mismatch_count += 1
			if witnesses.size() < 12:
				witnesses.append({"index": index, "mode": sample.mode, "kind": sample.kind,
					"initialBits": sample.initialBits, "deltaBits": sample.deltaBits,
					"targetBits": sample.targetBits, "source": sample.resultBits, "native": actual,
					"completed": commands is Array})
		_check(commands is Array, "Spectator heading accepts original missing or null target")
		_check(actual == sample.resultBits, "Original spectator heading retains double bits")
		_check(state.position == actor.position, "Following continues after resolving the target heading")
	var report_path := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			report_path = argument.trim_prefix("--report=")
	if report_path.is_empty():
		return
	_check(not FileAccess.file_exists(report_path), "Preserve existing spectator heading evidence")
	if FileAccess.file_exists(report_path):
		return
	var directory_status := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(report_path.get_base_dir()))
	_check(directory_status == OK, "Create the spectator heading evidence directory")
	if directory_status != OK:
		return
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	_check(file != null, "Retain original spectator heading witnesses")
	if file != null:
		file.store_string(JSON.stringify({"cases": cases.size(), "mismatches": mismatch_count, "witnesses": witnesses}, "  "))
		file.close()

func _bits(value: float) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	return bytes.hex_encode()
