extends Node

const Helper = preload("res://tests/status_suite.gd")
var assertions := 0
var failures := 0

func _ready() -> void:
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error(label)

func _settings() -> ControlPreferences:
	var settings := ControlPreferences.new()
	settings.persist = false
	settings.configure(Content.balance.mobile)
	settings.values.gyro = true
	return settings

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/gyro_owner.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(capture.get("formatVersion") == 1 and capture.get("programs") is Array,
		"Capture original gyro start/stop and event programs")
	for path: String in capture.source.inputs:
		_check(FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n").sha256_text() == capture.source.inputs[path],
			"Gyro capture producer remains current: " + path)
	for path: String in capture.source.sourceInputs:
		_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original gyro dependency matches imported content: " + path)
	_check(capture.rules == Content.balance.mobile.look, "Gyro lifecycle uses the original imported sensor rules")
	if failures == 0:
		_replay(capture.programs)
		_detachment()
		_reentrant_failure()
		_reentrant_look()
		_configuration()
		await _queued_owner()
	print("GYRO_RETIREMENT assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _replay(programs: Array) -> void:
	for program: Dictionary in programs:
		var state := GyroState.new(Content.balance.mobile.look)
		var outputs := []
		state.look.connect(func(change): outputs.append([change.x, change.y]))
		for step: Dictionary in program.steps:
			outputs.clear()
			match step.action:
				"start": state.start(program.source, 1000)
				"stop": state.stop()
				"sample": state.motion(Vector3(30, -20, 0) * PI / 180.0, 0.016)
			_check(state.active == step.active and state.have == step.have and state.events == int(step.events) and state.usable == int(step.usable),
				"Original gyro start/stop suppresses stopped sensor events")
			Helper.compare(self, outputs, step.outputs, "Original source motion dispatch")
			Helper.compare(self, [state.accumulated.x, state.accumulated.y], step.accumulated, "Original gyro restart resets accumulation")
			if step.action == "stop":
				_check(step.listeners.is_empty() and int(step.timers) == 0, "Original stop releases listeners and watchdog")

func _detachment() -> void:
	var settings := _settings()
	var owner := NativeGyro.new()
	add_child(owner)
	owner.configure(settings)
	var state := owner.state
	state.start("motion", 1000)
	var outputs := []
	owner.look.connect(func(change): outputs.append(change))
	state.look.emit(Vector2.ONE)
	_check(outputs == [Vector2.ONE], "An admitted owner forwards current sensor input")
	outputs.clear()
	remove_child(owner)
	_check(not state.active and not state.have, "Detachment stops the retained sensor state")
	_check(not settings.changed.is_connected(owner.refresh), "Detachment disconnects the preference publisher")
	state.look.emit(Vector2.ONE)
	state.failed.emit("gyro_motion_missing")
	_check(outputs.is_empty() and settings.values.gyro, "Retired sensor callbacks cannot aim or rewrite preferences")
	_check(owner.preferences == null, "Retirement releases the borrowed preferences")
	add_child(owner)
	owner.set_enabled(true)
	owner.set_preference(false)
	owner.configure(settings)
	owner.refresh()
	_check(owner.preferences == null and not owner.enabled and not state.active and settings.values.gyro,
		"Reattachment and late commands cannot revive the old owner")
	owner.free()
	settings.free()

func _reentrant_failure() -> void:
	var settings := _settings()
	var owner := NativeGyro.new()
	add_child(owner)
	owner.configure(settings)
	owner.status_changed.connect(func(_key):
		if owner.get_parent() != null:
			remove_child(owner))
	owner.state.failed.emit("gyro_motion_missing")
	_check(settings.values.gyro, "Retirement during failure notification cancels the old preference write")
	_check(owner.preferences == null and not settings.changed.is_connected(owner.refresh), "Reentrant retirement completes signal cleanup")
	owner.free()
	settings.free()

func _reentrant_look() -> void:
	var settings := _settings()
	var owner := NativeGyro.new()
	add_child(owner)
	owner.configure(settings)
	var state := owner.state
	state.start("auto", 1000)
	state.orientation(Vector3.FORWARD, 1000)
	owner.look.connect(func(_change): remove_child(owner))
	state.orientation(Vector3(0, sin(0.2), -cos(0.2)), 1020)
	_check(owner.retired and not state.active and state.note.is_empty() and state.events == 2,
		"Retirement during look dispatch cancels the pending sensor fallback")
	owner.free()
	settings.free()

func _configuration() -> void:
	var first := _settings()
	var second := _settings()
	var owner := NativeGyro.new()
	add_child(owner)
	owner.configure(first)
	var state := owner.state
	owner.configure(second)
	_check(owner.state == state and owner.preferences == first and not second.changed.is_connected(owner.refresh),
		"Configured owners cannot acquire another state or preference subscription")
	owner.free()
	_check(first.changed.get_connections().is_empty(), "Native owner deletion releases its subscription")
	first.free()
	second.free()

func _queued_owner() -> void:
	var settings := _settings()
	var owner := NativeGyro.new()
	add_child(owner)
	owner.configure(settings)
	var outputs := []
	owner.look.connect(func(change): outputs.append(change))
	owner.state.start("motion", 1000)
	owner.queue_free()
	owner.state.look.emit(Vector2.ONE)
	owner.state.failed.emit("gyro_motion_missing")
	owner.set_preference(false)
	_check(outputs.is_empty() and settings.values.gyro, "Queued owners reject sensor and preference commands before native deletion")
	await get_tree().process_frame
	settings.free()
