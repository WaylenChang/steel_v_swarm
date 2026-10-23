class_name LocalDefenseState
extends RefCounted

signal changed(on: bool)

var defending := false
var frozen := false
var feedback: LocalCombatFeedback

func request(frame: Dictionary, now: float, on: Variant = null) -> bool:
	if frame.get("frozen", false):
		return false
	var next := not defending if on == null else ControlPreferences.truthy(on)
	if next:
		if frame.get("side", "").is_empty() or frame.get("dead", false) or frame.get("shop", false) or float(frame.get("shield", 0)) <= 0:
			if float(frame.get("shield", 0)) <= 0 and feedback != null:
				feedback.show_notice("defense_empty", now)
			return false
		defending = true
		if feedback != null:
			feedback.show_notice("defense_on", now)
	else:
		if not defending:
			return false
		defending = false
		if feedback != null:
			feedback.show_notice("defense_off", now)
	changed.emit(defending)
	return true

func observe_snapshot(frame: Dictionary, now: float) -> void:
	# Source consumes shield depletion before replacing its published freeze flag.
	if defending and float(frame.get("shield", 0)) <= 0:
		var previous := frame.duplicate()
		previous.frozen = frozen
		request(previous, now, false)
	frozen = frame.get("frozen", false)

func observe_frame(frame: Dictionary, now: float) -> void:
	if not frame.get("dead", false) and defending and float(frame.get("shield", 0)) <= 0:
		request(frame, now, false)
