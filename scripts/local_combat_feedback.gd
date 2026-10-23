class_name LocalCombatFeedback
extends RefCounted

signal message(text: String)

var rules: Dictionary = {}
var last: Dictionary = {}

func configure(metadata: Dictionary) -> void:
	rules = metadata
	reset()
	if rules.is_empty():
		push_error("Missing original local combat notices; regenerate source controls")

func reset() -> void:
	last.clear()

func show_notice(id: String, now: float, values: Dictionary = {}) -> void:
	if not rules.has(id):
		push_error("Missing original local combat notice: " + id)
		return
	var definition: Dictionary = rules[id]
	if definition.cooldown != null:
		var previous := float(last.get(definition.clock, 0))
		if now - previous <= float(definition.cooldown):
			return
		last[definition.clock] = now
	message.emit(str(definition.text).format(values))
