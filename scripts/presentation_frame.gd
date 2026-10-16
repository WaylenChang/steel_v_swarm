class_name PresentationFrame
extends RefCounted

var remaining := 0.0
var pending: Array[Dictionary] = []
var last_serial := -1

func receive(event: Dictionary) -> void:
	var serial := int(event.get("death_serial", -1))
	if serial <= last_serial:
		return
	last_serial = serial
	pending.append(event.duplicate())

func advance(raw: float) -> float:
	if not is_finite(raw) or raw < 0:
		return 0.0
	var delta := minf(float(Content.balance.view.frameCap), raw)
	if remaining > 0:
		remaining -= delta
		delta = 0.0
	# Source applies queued snapshots after spending this frame's stop budget.
	for event: Dictionary in pending:
		var duration := float(Content.balance.presentationFrame.deathSeconds.get(event.get("kind", ""), 0))
		if duration > 0:
			remaining = maxf(remaining, duration)
	pending.clear()
	return delta

func hold(seconds: float) -> void:
	if is_finite(seconds) and seconds > 0:
		remaining = maxf(remaining, seconds)

func clear() -> void:
	remaining = 0.0
	pending.clear()
	last_serial = -1
