extends "res://tests/run.gd"

var geometry_only := false

class ControlledWorld extends BattleWorld:
	var calls := 0
	func obstruction_hit(_start: Vector3, _end: Vector3, _include_slabs: bool = true) -> Dictionary:
		return {}
	func visual_surface(point: Vector3) -> float:
		calls += 1
		return 20.0 if point.z > 4 and point.z < 9 else -10000.0

class ControlledCamera extends SpectatorCamera:
	func refresh() -> void:
		pass

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/spectator_tps.json")
	_check(capture.get("formatVersion") == 1 and capture.get("cases") is Array and capture.cases.size() == 654
		and capture.get("sequence", {}).get("frames", []).size() == 48, "Capture original spectator third-person cameras")
	if failures > 0:
		_finish_tps()
		return
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Spectator TPS capture input is current: " + path)
	for path: String in capture.source.sourceInputs:
		_check(provenance.get("inputs", {}).get(path) == capture.source.sourceInputs[path], "Spectator TPS source identity: " + path)
	_check(Content.balance.spectator.camera == capture.cameraRules, "Spectator TPS camera settings match the captured source")
	for actor: Dictionary in capture.actors:
		var profile: Dictionary = Content.balance.spectator.profiles.get(actor.character, Content.balance.spectator.fallbacks.STEEL)
		_check(profile == actor.profile, "Controlled spectator profile matches imported data: " + str(actor.character))
	if failures == 0:
		_check_cases(capture.cases, capture.sequence)
		_check_camera_binding(capture.cases[631])
	_finish_tps()

func _check_cases(cases: Array, sequence: Dictionary) -> void:
	var camera := SpectatorCamera.new()
	add_child(camera)
	var report := {"clear": _counts(), "clip": _counts(), "moving": _counts()}
	for index in cases.size():
		var sample: Dictionary = cases[index]
		var state := camera.state
		state.configure(Content.balance.spectator, Vector3.ZERO, 10000, 68)
		state.mode = sample.view
		state.pid = "17"
		var yaw := str(sample.yawBits).hex_decode().decode_double(0)
		state.yaw = yaw
		state.follow_yaw = yaw
		state.pitch = str(sample.pitchBits).hex_decode().decode_double(0)
		var actor := {"pid": "17", "side": "STEEL", "hero": true, "act": true, "ch": sample.character,
			"dead": false, "position": Vector3(sample.point[0], sample.point[1], sample.point[2]), "ry": yaw, "heroY": 0.0}
		_check_frame(camera, state, actor, sample, 0.0, index, report[sample.kind])
	var state := camera.state
	state.configure(Content.balance.spectator, Vector3.ZERO, 10000, 68)
	state.mode = sequence.view
	state.pid = "17"
	state.anchor = Vector3(sequence.initial[0], sequence.initial[1], sequence.initial[2])
	state.anchor_ok = true
	var first: Dictionary = sequence.frames[0]
	state.yaw = str(first.yawBits).hex_decode().decode_double(0)
	state.pitch = str(first.pitchBits).hex_decode().decode_double(0)
	var actor := {"pid": "17", "side": "STEEL", "hero": true, "act": true, "ch": sequence.character,
		"dead": false, "position": Vector3(sequence.point[0], sequence.point[1], sequence.point[2]), "ry": 0.0, "heroY": 0.0}
	for index in sequence.frames.size():
		var sample: Dictionary = sequence.frames[index]
		var delta := str(sample.deltaBits).hex_decode().decode_double(0)
		_check_frame(camera, state, actor, sample, delta, index, report.moving)
	camera.free()
	var directory_status := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/terra"))
	_check(directory_status == OK, "Create spectator TPS evidence directory")
	if directory_status != OK:
		return
	var suffix := "geometry" if geometry_only else "final" if OS.get_cmdline_user_args().has("--final") else "baseline"
	var file := FileAccess.open("res://artifacts/terra/spectator-tps-" + suffix + ".json", FileAccess.WRITE)
	_check(file != null, "Retain original/native spectator TPS witnesses")
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()

func _counts() -> Dictionary:
	return {"frames": 0, "aim": 0, "before": 0, "samples": 0, "final": 0, "witnesses": []}

func _check_frame(camera: SpectatorCamera, state: SpectatorState, actor: Dictionary,
		sample: Dictionary, delta: float, index: int, report: Dictionary) -> void:
	failure_scope = "spectator_tps_" + str(sample.kind)
	var observation := {"active": false, "samples": 0, "aim": Vector3.ZERO, "before": Vector3.ZERO, "published": Vector3.ZERO,
		"rawAim": [], "hit": null, "hitDistance": null}
	var surface := func(point: Vector3) -> float:
		if observation.active:
			observation.samples += 1
		return 20.0 if sample.ridge and point.z > 4 and point.z < 9 else -10000.0
	var collision := func(start: Vector3, end: Vector3) -> Dictionary:
		if sample.hit == null:
			return {}
		var point := start + start.direction_to(end) * float(sample.hit)
		observation.hit = point
		var ax: float = observation.rawAim[0]
		var ay: float = observation.rawAim[1]
		var az: float = observation.rawAim[2]
		var dx := float(point.x) - ax
		var dy := float(point.y) - ay
		var dz := float(point.z) - az
		observation.hitDistance = sqrt(dx * dx + dy * dy + dz * dz)
		return {"position": point}
	var pull := func(start: Vector3, end: Vector3) -> Vector3:
		observation.aim = start
		observation.before = end
		observation.active = true
		var result := CameraPose._pull(start, end, collision, surface)
		observation.active = false
		return result
	var precise_pull := func(start: Array, end: Array) -> Array:
		observation.rawAim = start
		observation.aim = Vector3(start[0], start[1], start[2])
		observation.before = Vector3(end[0], end[1], end[2])
		observation.published = state.camera_position
		observation.active = true
		var result := CameraPose._pull_components(start, end, collision, surface)
		observation.active = false
		return result
	state.advance(delta, [actor], {"f": 0, "r": 0, "mag": 0, "boost": false}, false, false, surface, 10000, pull, precise_pull)
	var aim := _vector_bytes(observation.aim)
	var before := _vector_bytes(observation.before)
	var final := _vector_bytes(state.camera_position)
	_check(_vector_bytes(observation.published) == "".join(sample.beforeFloat32Bits),
		"Original camera candidate is published before the segment pull")
	var checks := {"aim": aim == "".join(sample.aimFloat32Bits), "before": before == "".join(sample.beforeFloat32Bits),
		"samples": observation.samples == int(sample.samples), "final": final == "".join(sample.finalFloat32Bits)}
	report.frames += 1
	for key: String in checks:
		if not checks[key]:
			report[key] += 1
			if report.witnesses.size() < 8:
				report.witnesses.append({"index": index, "kind": key, "character": sample.character,
					"view": sample.view, "point": sample.point, "yawBits": sample.yawBits, "pitchBits": sample.pitchBits,
					"hit": sample.hit, "ridge": sample.ridge, "sourceAim": sample.aimFloat32Bits, "nativeAim": aim,
					"sourceBefore": sample.beforeFloat32Bits, "nativeBefore": before,
					"sourceFinal": sample.finalFloat32Bits, "nativeFinal": final,
					"sourceSamples": sample.samples, "nativeSamples": observation.samples,
					"nativeHit": _vector_bytes(observation.hit) if observation.hit != null else "",
					"nativeHitDistance": observation.hitDistance})
		if not geometry_only or key != "final" or sample.hit == null:
			_check(checks[key], "Original spectator third-person " + key + " at case " + str(index))
	camera._apply_pose(state.camera_position)
	_check(camera.global_position == state.camera_position, "Native camera receives the third-person result")

func _vector_bytes(value: Vector3) -> String:
	return PackedFloat32Array([value.x, value.y, value.z]).to_byte_array().hex_encode()

func _check_camera_binding(sample: Dictionary) -> void:
	failure_scope = "spectator_tps_camera_binding"
	_check(sample.kind == "clip" and sample.hit == null and sample.ridge and sample.yaw == 0 and sample.pitch == 0,
		"Use the original controlled ridge case for the native camera binding")
	var simulation := BattleSimulation.new()
	var world := ControlledWorld.new()
	world.ceiling = 10000
	simulation.world = world
	var camera := ControlledCamera.new()
	add_child(camera)
	camera.simulation = simulation
	camera.state.configure(Content.balance.spectator, Vector3.ZERO, world.ceiling, 68)
	camera.state.mode = "orbit"
	camera.state.pid = "17"
	camera.rows["controlled"] = {"pid": "17", "side": "STEEL", "hero": true, "act": true, "ch": sample.character,
		"dead": false, "position": Vector3(sample.point[0], sample.point[1], sample.point[2]), "ry": 0.0, "heroY": 0.0}
	camera.advance(0, Vector2.ZERO, {"f": 0, "r": 0, "mag": 0, "boost": false}, false, false)
	_check(_vector_bytes(camera.global_position) == "".join(sample.finalFloat32Bits),
		"SpectatorCamera advances through the precise pull and applies the original ridge result")
	_check(world.calls == int(sample.samples) + 1, "SpectatorCamera queries the segment and final floor in source order")
	camera.free()
	world.free()
	simulation.free()

func _finish_tps() -> void:
	print("SPECTATOR_TPS_GEOMETRY" if geometry_only else "SPECTATOR_TPS", " assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
