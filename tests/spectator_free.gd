extends "res://tests/run.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/spectator_free.json")
	_check(capture.get("formatVersion") == 1 and capture.get("sequences") is Array and capture.sequences.size() == 5,
		"Capture original multi-frame free spectator movement")
	if failures > 0:
		_finish_free()
		return
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Spectator free-camera capture input is current: " + path)
	for path: String in capture.source.sourceInputs:
		_check(provenance.get("inputs", {}).get(path) == capture.source.sourceInputs[path], "Spectator free-camera source identity: " + path)
	_check(Content.balance.spectator.camera == capture.cameraRules, "Spectator free-camera settings match the captured source")
	_check(Content.balance.spectator.fallbacks.STEEL == capture.profile, "Controlled spectator profile matches imported data")
	if failures == 0:
		_check_sequences(capture.sequences)
		_check_resets()
	_finish_free()

func _check_sequences(sequences: Array) -> void:
	var camera := SpectatorCamera.new()
	add_child(camera)
	var report: Array = []
	for sequence: Dictionary in sequences:
		failure_scope = "spectator_free_" + str(sequence.name)
		var state := camera.state
		state.configure(Content.balance.spectator, Vector3.ZERO, 10000, 68)
		state.position = Vector3(sequence.position[0], sequence.position[1], sequence.position[2])
		var environment := {"surface": -1000.0, "ceiling": 10000.0}
		var surface := func(_point: Vector3) -> float: return environment.surface
		var pull := func(_start: Vector3, end: Vector3) -> Vector3: return end
		var actors: Dictionary = {}
		var mismatches := 0
		var precise_mismatches := 0
		var selections := 0
		var witnesses: Array = []
		var precise_witnesses: Array = []
		for index in sequence.frames.size():
			var frame: Dictionary = sequence.frames[index]
			var operation: Dictionary = frame.operation
			if operation.has("add"):
				var actor: Dictionary = operation.add.duplicate(true)
				actor.position = Vector3(actor.position[0], actor.position[1], actor.position[2])
				actors[actor.pid] = actor
			if operation.has("update"):
				var row: Dictionary = operation.update
				actors[row.pid].position = Vector3(row.position[0], row.position[1], row.position[2])
			if operation.has("surface"):
				environment.surface = float(operation.surface)
			if operation.has("ceiling"):
				environment.ceiling = float(operation.ceiling)
			if operation.has("yaw"):
				state.yaw = str(frame.yawBits).hex_decode().decode_double(0)
			if operation.has("select"):
				state.select_mode(operation.select, actors.values())
			if operation.has("follow"):
				state.follow(operation.follow, actors.values())
			if operation.has("advance"):
				var axis: Dictionary = operation.get("axis", {"f": 0, "r": 0, "mag": 0, "boost": false}).duplicate()
				if frame.magBits != null:
					axis.mag = str(frame.magBits).hex_decode().decode_double(0)
				var delta := str(frame.deltaBits).hex_decode().decode_double(0)
				for command: Dictionary in state.advance(delta, actors.values(), axis, operation.get("up", false),
						operation.get("down", false) or operation.get("ctrl", false), surface, environment.ceiling, pull):
					command.actor.visible = command.visible
				if state.mode == "god":
					_check(state.camera_position == state.position, "Free camera publishes the current position")
					camera._apply_pose(state.camera_position)
					_check(camera.global_position == state.position, "Native camera receives the free position")
			var actual := PackedFloat32Array([state.position.x, state.position.y, state.position.z]).to_byte_array().hex_encode()
			var expected := "".join(frame.positionFloat32Bits)
			var bytes := PackedByteArray()
			bytes.resize(24)
			bytes.encode_double(0, state._position_x)
			bytes.encode_double(8, state._position_y)
			bytes.encode_double(16, state._position_z)
			var precise := bytes.hex_encode()
			var source_precise := "".join(frame.positionBits)
			if precise != source_precise:
				precise_mismatches += 1
				if precise_witnesses.size() < 5:
					precise_witnesses.append({"frame": index, "source": source_precise, "native": precise})
			_check(precise == source_precise, "Original free spectator position retains double bits at frame " + str(index))
			if actual != expected:
				mismatches += 1
				if witnesses.size() < 5:
					witnesses.append({"frame": index, "source": expected, "native": actual})
			_check(actual == expected, "Original free spectator position retains native Float32 bits at frame " + str(index))
			if state.mode != frame.mode or state.pid != frame.pid:
				selections += 1
			_check(state.mode == frame.mode and state.pid == frame.pid, "Original free/follow selection at frame " + str(index))
		report.append({"name": sequence.name, "frames": sequence.frames.size(), "mismatches": mismatches,
			"preciseMismatches": precise_mismatches, "preciseWitnesses": precise_witnesses,
			"selectionMismatches": selections, "witnesses": witnesses})
	camera.free()
	var directory_status := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/terra"))
	_check(directory_status == OK, "Create the free spectator evidence directory")
	if directory_status != OK:
		return
	var suffix := "final" if OS.get_cmdline_user_args().has("--final") else "baseline"
	var file := FileAccess.open("res://artifacts/terra/spectator-free-" + suffix + ".json", FileAccess.WRITE)
	_check(file != null, "Retain source/native free spectator witnesses")
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()

func _check_resets() -> void:
	failure_scope = "spectator_free_reset"
	var state := SpectatorState.new()
	var center := Vector3(1, 1.0 / 65536.0, 3)
	state.configure(Content.balance.spectator, center, 10000, 68)
	_check(state._position_y == float(center.y) + float(Content.balance.spectator.startHeight)
		and state._position_y != float(state.position.y), "Initial height is added before native Vector3 storage")
	state.position = Vector3(1024, 0, 0)
	var surface := func(_point: Vector3) -> float: return -1000.0
	var pull := func(_start: Vector3, end: Vector3) -> Vector3: return end
	state.advance(1.0 / 240.0, [], {"f": 0, "r": 1.0 / 32768.0, "mag": 1.0 / 32768.0, "boost": false},
		false, false, surface, 10000, pull)
	_check(state._position_x != float(state.position.x), "Free motion retains precision beyond the exposed Vector3")
	state.position = Vector3(-5, -4, 3)
	_check([state._position_x, state._position_y, state._position_z] == [-5.0, -4.0, 3.0],
		"Assigning the free position replaces all retained coordinates")
	state.position.y = 42
	_check(state._position_x == -5.0 and state._position_y == 42.0 and state._position_z == 3.0,
		"Writing a position component updates its retained coordinate")
	state.configure(Content.balance.spectator, Vector3.ZERO, 10000, 68)
	_check(state._position_x == 0.0 and state._position_y == float(Content.balance.spectator.startHeight)
		and state._position_z == 0.0, "Reconfiguration replaces all retained free coordinates")

func _finish_free() -> void:
	print("SPECTATOR_FREE assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
