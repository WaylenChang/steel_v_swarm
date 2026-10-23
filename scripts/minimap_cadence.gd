class_name MinimapCadence
extends RefCounted

var last := 0.0
var warm_until := 0.0

func configure(now: float) -> void:
	last = 0
	warm_until = now + float(Content.balance.minimap.cadence.warm)

func invalidate() -> void:
	last = 0

func advance(now: float) -> bool:
	var rules: Dictionary = Content.balance.minimap.cadence
	var gate := float(rules.warmGate if now < warm_until else rules.gate)
	if now - last < gate:
		return false
	last = now
	return true
