extends RefCounted

const Helper = preload("res://tests/status_suite.gd")

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("localDefense") or not fixtures.has("localDefenseDeadlines") or not Content.balance.controls.has("localFeedback"):
		h._check(false, "Regenerate original local defense stance and shield-depletion ordering references")
		return
	for fixture: Dictionary in fixtures.localDefenseDeadlines:
		h._near(ActorSnapshot.deadline_remaining(fixture.deadline, fixture.now), fixture.result,
			"Source private freeze publication rounds remaining time before testing the local input gate")
	for fixture: Dictionary in fixtures.localDefense:
		var state := LocalDefenseState.new()
		state.defending = fixture.initial
		state.feedback = LocalCombatFeedback.new()
		state.feedback.configure(Content.balance.controls.localFeedback)
		var notices: Array = []
		var sent: Array = []
		state.feedback.message.connect(func(value): notices.append(value))
		state.changed.connect(func(value): sent.append(value))
		for step: Dictionary in fixture.steps:
			notices.clear()
			sent.clear()
			match str(step.kind):
				"snapshot": state.observe_snapshot(step.frame, 10)
				"frame":
					state.frozen = step.frame.frozen
					state.observe_frame(step.frame, 10)
				"request":
					state.frozen = step.frame.frozen
					state.request(step.frame, 10, step.get("on"))
			Helper.compare(h, {"defending": state.defending, "frozen": state.frozen}, step.result,
				"Original local stance persists across death/respawn and consumes depletion before the new freeze flag")
			Helper.compare(h, notices, step.notices, "Original defense notices preserve repeated explicit-on and silent off/frozen gates")
			Helper.compare(h, sent, step.sent, "Defense commands carry explicit on/off intent rather than toggling a later authority state")
