extends RefCounted

const Helper = preload("res://tests/status_suite.gd")

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("localCast") or not Content.balance.controls.has("casting") or not Content.balance.controls.has("localFeedback"):
		h._check(false, "Regenerate original client ability preflight and windup references")
		return
	for fixture: Dictionary in fixtures.localCast:
		var state := LocalCastState.new()
		state.feedback = LocalCombatFeedback.new()
		state.feedback.configure(Content.balance.controls.localFeedback)
		var notices: Array = []
		state.feedback.message.connect(func(value): notices.append(value))
		state.configure(Content.balance.controls.casting)
		state.cooldowns = fixture.initial.cooldowns.duplicate()
		state.charges = fixture.initial.charges.duplicate(true) if fixture.initial.charges is Array else null
		state.cast_left = float(fixture.initial.castLeft)
		state.until = float(fixture.initial.until)
		var frame: Dictionary = fixture.frame.duplicate(true)
		h._check(state.request(fixture.definition, fixture.slot, 10, frame) == bool(fixture.ready),
			"Original client cast preflight retains freeze, existing windup, charges, rounded power, EMP and confirmed-target gates")
		Helper.compare(h, notices, fixture.notices, "Original cast rejection messages preserve power-before-EMP ordering, charge gates and localized number formatting")
		Helper.compare(h, {"cooldowns": state.cooldowns, "charges": state.charges, "castLeft": state.cast_left,
			"until": state.until, "shieldExpandUntil": state.shield_expand_until,
			"defJumpUntil": state.def_jump_until, "power": frame.power}, fixture.result,
			"Source optimistic cast timers and charge display preserve zero-cooldown readiness and never deduct power")
		if fixture.hud != null:
			for slot: String in ["def", "atk"]:
				var definition := Content.ability(fixture.character, slot, fixture.level)
				Helper.compare(h, state.hud(definition, slot, fixture.level, frame.power, frame.snow), fixture.hud[slot],
					"Original ability HUD retains unpublished charge defaults, ready gating, recharge metadata and snow-scaled cooldown maxima")
		var early := state.is_casting(10)
		h._check(early == (float(fixture.result.castLeft) > 0 or float(fixture.result.until) > 10),
			"Source immediate windup blocks local weapon presentation before any authority acknowledgement")
