extends "res://tests/run.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/spectator_fpv_pose.json")
	_check(capture.get("formatVersion") == 1 and capture.get("cases") is Array and capture.cases.size() == 588,
		"Capture the original spectator FPV camera branch")
	if failures > 0:
		_finish_fpv()
		return
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Spectator FPV capture input is current: " + path)
	for path: String in capture.source.sourceInputs:
		_check(provenance.get("inputs", {}).get(path) == capture.source.sourceInputs[path], "Spectator FPV source identity: " + path)
	_check(Content.balance.spectator.camera == capture.camera, "Spectator camera settings match the captured source")
	for actor: Dictionary in capture.actors:
		var profile: Dictionary = Content.balance.spectator.profiles.get(actor.character, Content.balance.spectator.fallbacks.STEEL)
		_check(profile == actor.profile, "Controlled spectator profile matches imported data: " + str(actor.character))
	if failures == 0:
		_check_cases(capture.cases)
	_finish_fpv()

func _check_cases(cases: Array) -> void:
	var camera := SpectatorCamera.new()
	add_child(camera)
	var surface := func(_point: Vector3) -> float: return -1000.0
	var pull := func(_start: Vector3, end: Vector3) -> Vector3: return end
	var witnesses: Array = []
	var mismatches := 0
	for index in cases.size():
		var sample: Dictionary = cases[index]
		failure_scope = "spectator_fpv_" + str(sample.character)
		var state := camera.state
		state.configure(Content.balance.spectator, Vector3.ZERO, 10000, 68)
		state.mode = "fpv"
		state.pid = "17"
		var yaw := str(sample.yawBits).hex_decode().decode_double(0)
		state.follow_yaw = yaw
		var actor := {"pid": "17", "side": "STEEL", "hero": true, "act": true, "ch": sample.character,
			"dead": false, "position": Vector3(sample.point[0], sample.point[1], sample.point[2]),
			"ry": yaw, "heroY": sample.altitude}
		var commands := state.advance(0, [actor], {"f": 0, "r": 0, "mag": 0, "boost": false}, false, false, surface, 10000, pull)
		var actual := PackedFloat32Array([state.camera_position.x, state.camera_position.y, state.camera_position.z]).to_byte_array().hex_encode()
		var expected := "".join(sample.cameraFloat32Bits)
		var matches := actual == expected
		if not matches:
			mismatches += 1
			if witnesses.size() < 12:
				witnesses.append({"index": index, "character": sample.character, "point": sample.point, "yawBits": sample.yawBits,
					"altitude": sample.altitude, "source": expected, "native": actual})
		_check(matches, "Original FPV camera position retains native Float32 bits at case " + str(index))
		_check(state.yaw == yaw and state.position == actor.position, "FPV follows the supplied source heading and locked anchor")
		_check(state.hidden == actor and commands.size() == 1 and not commands[0].visible and sample.hidden and not sample.visible,
			"FPV owns and hides the living source actor")
		camera._apply_pose(state.camera_position)
		_check(camera.global_position == state.camera_position, "The native camera receives the spectator position")
	camera.free()
	var directory_status := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/terra"))
	_check(directory_status == OK, "Create the FPV pose evidence directory")
	if directory_status != OK:
		return
	var suffix := "final" if OS.get_cmdline_user_args().has("--final") else "baseline"
	var file := FileAccess.open("res://artifacts/terra/spectator-fpv-pose-" + suffix + ".json", FileAccess.WRITE)
	_check(file != null, "Retain source/native spectator FPV pose witnesses")
	if file != null:
		file.store_string(JSON.stringify({"cases": cases.size(), "mismatches": mismatches, "witnesses": witnesses}, "  "))
		file.close()

func _finish_fpv() -> void:
	print("SPECTATOR_FPV_POSE assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
