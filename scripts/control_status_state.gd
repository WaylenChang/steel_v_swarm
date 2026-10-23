class_name ControlStatusState
extends RefCounted

signal notice(text: String)
signal opacity(value: float)

var rules: Dictionary = {}
var flags: Dictionary = {}
var left := 0.0
var peak := 0.0

func configure(metadata: Dictionary) -> void:
	rules = metadata
	if rules.is_empty():
		push_error("Missing original control-status presentation metadata; regenerate source controls")

func observe(values: Dictionary) -> void:
	if rules.is_empty():
		return
	for edge: Dictionary in rules.edges:
		if not values.has(edge.field):
			continue
		var on := VisualPreferences._number(values[edge.field]) > 0
		if on and not flags.get(edge.id, false):
			notice.emit(edge.text)
			if edge.peak != null:
				trigger(float(edge.peak))
		flags[edge.id] = on

func alpha() -> float:
	if rules.is_empty():
		return 0
	var value := 0.0 if is_nan(peak) else clampf(peak, 0, 1)
	return BloodSplatState.envelope(left, rules.flash, value)

func trigger(value: float) -> void:
	if rules.is_empty() or not value > 0:
		return
	if value >= alpha():
		left = float(rules.duration)
		peak = value

func advance(delta: float) -> void:
	if left <= 0:
		return
	left = maxf(0, left - delta)
	opacity.emit(alpha())

func clear_flash() -> void:
	left = 0
	peak = 0
	flags["_blindOn"] = false
	opacity.emit(0)

func reset() -> void:
	flags.clear()
	clear_flash()
