extends "res://tests/run.gd"

class VisibilityBody extends Node3D:
	var model: Node3D
	var living := true
	func alive() -> bool:
		return living

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/spectator_native.json")
	_check(capture.get("formatVersion") == 1 and capture.get("source") is Dictionary and capture.get("spectatorPrograms") is Array,
		"Capture original spectator methods and actual camera quaternions")
	if failures > 0:
		_finish_spectator()
		return
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Spectator capture input is current: " + path)
	for path: String in capture.source.sourceInputs:
		_check(provenance.get("inputs", {}).get(path) == capture.source.sourceInputs[path], "Spectator oracle matches imported source: " + path)
	_check(Content.balance.get("spectator") == capture.get("metadata"), "Native spectator profiles and localized templates match original source")
	if failures == 0:
		preload("res://tests/spectator_suite.gd").run(self, capture)
		_camera_pose(capture.spectatorPrograms)
		_exit_lifecycle()
	_finish_spectator()

func _camera_pose(programs: Array) -> void:
	var camera := SpectatorCamera.new()
	add_child(camera)
	for program: Dictionary in programs:
		for frame: Dictionary in program.steps:
			if not frame.operation.has("delta"):
				continue
			camera.state.yaw = float(frame.result.yaw)
			camera.state.pitch = float(frame.result.pitch)
			var point: Array = frame.result.camera
			camera._apply_pose(Vector3(point[0], point[1], point[2]))
			var q: Array = frame.cameraRotation
			var expected := SourceQuaternion.basis(Quaternion(q[0], q[1], q[2], q[3]))
			for axis in range(3):
				_check(camera.global_basis[axis].distance_to(expected[axis]) < .000001,
					"Original spectator Y-then-X rendered orientation at native precision")
	camera.free()

func _exit_lifecycle() -> void:
	# Visibility probes isolate camera ownership; they do not substitute actor models.
	for living: bool in [true, false]:
		var body := VisibilityBody.new()
		body.living = living
		body.model = Node3D.new()
		body.add_child(body.model)
		add_child(body)
		body.model.hide()
		var camera := SpectatorCamera.new()
		add_child(camera)
		camera.state.hidden = {"unit": body}
		camera.rows[1] = camera.state.hidden
		remove_child(camera)
		_check(body.model.visible == living, "Spectator exit restores a living FPV body and retains a dead body hide")
		_check(camera.state.hidden.is_empty() and camera.rows.is_empty(), "Detached spectator releases hidden-body ownership and retained rows")
		camera.free()
		body.free()
	var body := VisibilityBody.new()
	body.model = Node3D.new()
	body.add_child(body.model)
	add_child(body)
	var camera := SpectatorCamera.new()
	add_child(camera)
	camera.state.hidden = {"unit": body}
	body.free()
	remove_child(camera)
	_check(camera.state.hidden.is_empty(), "A removed FPV body cannot leave a dangling camera owner")
	camera.free()

func _finish_spectator() -> void:
	print("SPECTATOR_NATIVE assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
