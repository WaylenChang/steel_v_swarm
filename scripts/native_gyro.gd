class_name NativeGyro
extends Node

signal look(change: Vector2)
signal status_changed(key: String)

var state: GyroState
var preferences: ControlPreferences
var status := "gyro_off"
var failure := ""
var focused := true
var enabled := false
var retired := false

static func supported() -> bool:
	return OS.get_name() in ["Android", "iOS"] and not Engine.is_editor_hint()

func configure(settings: ControlPreferences) -> void:
	if retired or is_queued_for_deletion() or state != null or not is_instance_valid(settings) or settings.is_queued_for_deletion():
		return
	preferences = settings
	state = GyroState.new(preferences.rules.look)
	state.look.connect(_on_look)
	state.failed.connect(_on_failed)
	preferences.changed.connect(refresh)
	refresh()

func _active() -> bool:
	return not retired and not is_queued_for_deletion() and is_instance_valid(preferences) and not preferences.is_queued_for_deletion()

func _on_look(change: Vector2) -> void:
	if _active():
		look.emit(change)

func _on_failed(reason: String) -> void:
	if not _active():
		return
	failure = reason
	_set_status(reason)
	if _active():
		preferences.set_value("gyro", false)

func retire() -> void:
	if retired:
		return
	retired = true
	enabled = false
	set_process(false)
	if state != null:
		# Existing viewport callbacks may still reset this stopped basis.
		state.stop()
		if state.look.is_connected(_on_look):
			state.look.disconnect(_on_look)
		if state.failed.is_connected(_on_failed):
			state.failed.disconnect(_on_failed)
	if is_instance_valid(preferences) and preferences.changed.is_connected(refresh):
		preferences.changed.disconnect(refresh)
	preferences = null

func _exit_tree() -> void:
	retire()

func refresh() -> void:
	if not _active() or state == null:
		return
	state.sensitivity = preferences.values.gyroSens
	state.invert = preferences.values.gyroInvert
	if not supported():
		state.stop()
		_set_status("gyro_unsupported")
		return
	var running := enabled and focused and preferences.scheme() == "pad" and bool(preferences.values.gyro)
	if not running:
		state.stop()
		_set_status(failure if not failure.is_empty() else ("gyro_remembered" if preferences.values.gyro else "gyro_off"))
		return
	if not state.active or state.preference != preferences.values.gyroSrc:
		state.start(preferences.values.gyroSrc, Time.get_ticks_msec())
		_set_status("gyro_waiting")

func set_enabled(on: bool) -> void:
	if _active() and enabled != on:
		enabled = on
		refresh()

func set_preference(on: bool) -> bool:
	if not _active():
		return false
	failure = ""
	if on and not supported():
		preferences.set_value("gyro", false)
		if _active():
			_set_status("gyro_unsupported")
		return false
	preferences.set_value("gyro", on)
	refresh()
	return on and _active()

func _process(delta: float) -> void:
	if not _active() or state == null or not state.active:
		return
	var now := float(Time.get_ticks_msec())
	if state.path == "orient":
		state.orientation(GyroState.sensor_forward(Input.get_gravity(), Input.get_magnetometer()), now)
	else:
		var rate := Input.get_gyroscope()
		# Godot has already rotated these axes into the screen frame. Its API
		# provides no sensor-present bit; initial zero samples remain unproven.
		state.motion(rate, delta, state.have or rate.length_squared() > 0)
	if not _active():
		return
	state.watchdog(now)
	if _active() and state.active:
		_set_status(state.note if not state.note.is_empty() else ("gyro_" + state.path if state.usable > 0 else "gyro_waiting"))

func _set_status(key: String) -> void:
	if _active() and status != key:
		status = key
		status_changed.emit(key)

func _notification(what: int) -> void:
	if _active() and (what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_IN):
		focused = what == NOTIFICATION_APPLICATION_FOCUS_IN
		refresh()
