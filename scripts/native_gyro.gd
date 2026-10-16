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

static func supported() -> bool:
	return OS.get_name() in ["Android", "iOS"] and not Engine.is_editor_hint()

func configure(settings: ControlPreferences) -> void:
	preferences = settings
	state = GyroState.new(preferences.rules.look)
	state.look.connect(func(change): look.emit(change))
	state.failed.connect(func(reason):
		failure = reason
		_set_status(reason)
		preferences.set_value("gyro", false))
	preferences.changed.connect(refresh)
	refresh()

func refresh() -> void:
	if state == null:
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
	if enabled != on:
		enabled = on
		refresh()

func set_preference(on: bool) -> bool:
	failure = ""
	if on and not supported():
		preferences.set_value("gyro", false)
		_set_status("gyro_unsupported")
		return false
	preferences.set_value("gyro", on)
	refresh()
	return on

func _process(delta: float) -> void:
	if state == null or not state.active:
		return
	var now := float(Time.get_ticks_msec())
	if state.path == "orient":
		state.orientation(GyroState.sensor_forward(Input.get_gravity(), Input.get_magnetometer()), now)
	else:
		var rate := Input.get_gyroscope()
		# Godot has already rotated these axes into the screen frame. Its API
		# provides no sensor-present bit; initial zero samples remain unproven.
		state.motion(rate, delta, state.have or rate.length_squared() > 0)
	state.watchdog(now)
	if state.active:
		_set_status(state.note if not state.note.is_empty() else ("gyro_" + state.path if state.usable > 0 else "gyro_waiting"))

func _set_status(key: String) -> void:
	if status != key:
		status = key
		status_changed.emit(key)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		focused = what == NOTIFICATION_APPLICATION_FOCUS_IN
		refresh()
