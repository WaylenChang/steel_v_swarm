class_name PlayerViewState
extends RefCounted

signal preference_changed(value: String)
signal aim_changed(on: bool)

var rules: Dictionary = {}
var preference := ""
var mode := ""
var body_yaw := 0.0
var aiming := false
var restore := ""

func configure(metadata: Dictionary, initial: String, yaw: float) -> void:
	rules = metadata
	preference = initial if initial in rules.modeKeys else str(rules.defaultMode)
	mode = preference
	body_yaw = yaw
	aiming = false
	restore = ""

func select_mode(value: String, yaw: float) -> float:
	if value not in rules.modeKeys or preference == value:
		return yaw
	preference = value
	preference_changed.emit(value)
	return _mode_changed(value, yaw)

func _mode_changed(value: String, yaw: float) -> float:
	if aiming and value == "tps":
		if restore.is_empty():
			restore = "tps"
		# Reentrant source notifications can reset yaw even while already in FPV.
		return select_mode("fpv", yaw)
	if value == "tps":
		body_yaw = yaw
	else:
		yaw = body_yaw
	mode = value
	return yaw

func set_aiming(on: bool, yaw: float, has_side: bool = true) -> float:
	if not has_side or aiming == on:
		return yaw
	if on and mode == "tps":
		body_yaw = yaw
		restore = mode
		yaw = select_mode("fpv", yaw)
	aiming = on
	aim_changed.emit(on)
	if not on and not restore.is_empty():
		var previous := restore
		restore = ""
		yaw = select_mode(previous, yaw)
	return yaw

func advance_body(delta: float, move: Vector3, yaw: float, defending: bool, firing: bool) -> void:
	if mode != "tps" or defending:
		body_yaw = yaw
		return
	if aiming or firing:
		body_yaw = CameraPose.angle_step(body_yaw, yaw, float(Content.constants.PLAYER_TPS.BODY_TURN_K), delta)
	elif move.length_squared() > float(rules.bodyMovingSquared):
		body_yaw = CameraPose.angle_step(body_yaw, atan2(-move.x, -move.z), float(Content.constants.PLAYER_TPS.BODY_TURN_K), delta)

func report_yaw(yaw: float, defending: bool) -> float:
	return body_yaw if mode == "tps" and not defending else yaw
