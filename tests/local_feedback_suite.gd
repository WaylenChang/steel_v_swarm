extends RefCounted

const Helper = preload("res://tests/status_suite.gd")

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("localFeedback") or not Content.balance.controls.has("localFeedback"):
		h._check(false, "Regenerate original combat notices and shared warning-clock references")
		return
	var feedback := LocalCombatFeedback.new()
	feedback.configure(Content.balance.controls.localFeedback)
	var notices: Array = []
	feedback.message.connect(func(value): notices.append(value))
	for step: Dictionary in fixtures.localFeedback:
		notices.clear()
		feedback.show_notice(step.id, step.now)
		Helper.compare(h, notices, step.notices, "Original fire/cast warnings share one strict clock and keep their distinct text")
		h._near(feedback.last.get("cast", 0), step.last, "Suppressed warning calls never advance the original shared timestamp")
	feedback.reset()
	h._check(feedback.last.is_empty(), "A new battle resets the source client's warning timestamps")
