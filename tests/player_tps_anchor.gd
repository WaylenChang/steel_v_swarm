extends "res://tests/run.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/player_tps_anchor.json")
	_check(capture.get("formatVersion") == 1 and capture.get("cases") is Array and capture.cases.size() == 720,
		"Capture the original third-person camera anchor and floor branch")
	if failures == 0:
		var provenance: Dictionary = Content.read_json("res://data/provenance.json")
		for path: String in capture.source.inputs:
			var source := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(source.sha256_text() == capture.source.inputs[path], "Current TPS anchor capture input: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.get("inputs", {}).get(path) == capture.source.sourceInputs[path], "Original TPS anchor source identity: " + path)
		_check(Content.constants.PLAYER_TPS == capture.rules, "TPS anchor camera settings match the original")
		for actor: Dictionary in capture.actors:
			_check(float(Content.balance.cameraProfiles[actor.character].ground.height) == float(actor.height),
				"TPS anchor uses imported source height: " + str(actor.character))
	if failures == 0:
		_check_cases(capture)
	print("PLAYER_TPS_ANCHOR assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_cases(capture: Dictionary) -> void:
	var heights := {}
	for actor: Dictionary in capture.actors:
		heights[actor.character] = float(actor.height)
	var witnesses: Array = []
	var mismatch_count := 0
	failure_scope = "player_tps_anchor"
	for index in capture.cases.size():
		var sample: Dictionary = capture.cases[index]
		var calls: Array = []
		var surface := func(point: Vector3) -> float:
			calls.append(point)
			return NAN if sample.floor == null else float(sample.floor)
		var yaw := str(sample.yawBits).hex_decode().decode_double(0)
		var pitch := str(sample.pitchBits).hex_decode().decode_double(0)
		var point := Vector3(sample.point[0], sample.point[1], sample.point[2])
		var actual := CameraPose.third_person_anchor(point, heights[sample.character], yaw, pitch, surface)
		var actual_query := _vector_bits(calls[0]) if calls.size() == 1 else ""
		var expected_query := "".join(sample.queryBits)
		var actual_camera := _vector_bits(actual)
		var expected_camera := "".join(sample.cameraBits)
		if actual_query != expected_query or actual_camera != expected_camera:
			mismatch_count += 1
			if witnesses.size() < 12:
				witnesses.append({"index": index, "character": sample.character, "point": sample.point,
					"yawBits": sample.yawBits, "pitchBits": sample.pitchBits, "floor": sample.floor,
					"querySource": expected_query, "queryNative": actual_query,
					"cameraSource": expected_camera, "cameraNative": actual_camera})
		_check(actual_query == expected_query, "Original surface query retains native Float32 bits")
		_check(actual_camera == expected_camera, "Original camera anchor retains native Float32 bits")
	var report_path := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			report_path = argument.trim_prefix("--report=")
	if report_path.is_empty():
		return
	_check(not FileAccess.file_exists(report_path), "Preserve existing TPS anchor evidence")
	if FileAccess.file_exists(report_path):
		return
	var directory_status := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(report_path.get_base_dir()))
	_check(directory_status == OK, "Create the TPS anchor evidence directory")
	if directory_status != OK:
		return
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	_check(file != null, "Retain TPS anchor source/native witnesses")
	if file != null:
		file.store_string(JSON.stringify({"cases": capture.cases.size(), "mismatches": mismatch_count, "witnesses": witnesses}, "  "))
		file.close()

func _vector_bits(value: Vector3) -> String:
	return PackedFloat32Array([value.x, value.y, value.z]).to_byte_array().hex_encode()
