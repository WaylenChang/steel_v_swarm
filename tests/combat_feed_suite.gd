extends RefCounted

const Helper = preload("res://tests/status_suite.gd")
const ControlsTests = preload("res://tests/controls_suite.gd")

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("combatFeed") or not Content.balance.has("combatFeed"):
		h._check(false, "Regenerate original combat feed branches before final verification")
		return
	for item: Dictionary in fixtures.combatFeed:
		var source: Dictionary = item.event
		var event := {"type": source.e, "actor": 71 if item.own else 72, "peer": 17 if item.own else 18}
		for key: String in ["kind", "side"]:
			if source.has(key):
				event[key] = source[key]
		if source.has("ev"):
			event.electric = source.ev
		if source.has("mul"):
			event.factor = source.mul
		if source.has("pts"):
			event.points = source.pts.duplicate(true)
		if source.has("item"):
			event.item = source.item
		if source.has("lvl"):
			event.level = source.lvl
		if source.has("lane"):
			event.type = "creep_upgrade"
			event.lane = source.lane
		if source.has("v"):
			event.amount = source.v
		if source.has("n"):
			event.wave = source.n
		if source.has("ch"):
			event.character = source.ch
			event.slot = source.slot
		if source.has("dur"):
			event.duration = source.dur
		if source.has("frac"):
			event.fraction = source.frac
			event.interrupted = source.interrupted
		Helper.compare(h, CombatFeedState.messages(event, 71, 17), item.messages,
			"Original death/collapse and private environment feed admission and text")
	var receiver := CombatFeedState.new()
	h._check(not receiver.accept({"type": "die"}), "Unidentified events cannot replay a notice")
	for serial: int in [1, 3, 4]:
		h._check(receiver.accept({"notice_serial": serial}), "Fresh ordered publication admits a notice")
		h._check(not receiver.accept({"notice_serial": serial}), "Repeated snapshot cannot repeat a notice")
		h._check(not receiver.accept({"notice_serial": serial - 1}), "Older cross-channel delivery cannot rewind notice state")
	receiver.clear()
	h._check(receiver.accept({"notice_serial": 1}), "New match resets only its own publication watermark")
	var event := {"type": "die", "actor": 90, "peer": 0, "notice_peer": 17, "kind": "decoy", "side": "STEEL"}
	h._check(not CombatFeedState.messages(event, 71, 17).is_empty(), "Carrier owner receives its original interception notice")
	h._check(CombatFeedState.messages(event, 71, 18).is_empty(), "Other observers cannot receive the owner's carrier notice")
	var simulation := ControlsTests.context(h)
	var unit := ControlsTests.actor(simulation, "t01")
	var before := [unit.hp, unit.shield, unit.power, unit.money, unit.ammo.duplicate(true), simulation.rng.state]
	simulation._report_death(unit)
	var first := simulation.snapshot()
	var second := simulation.snapshot()
	h._check(int(first.events[0].notice_serial) == int(second.events[0].notice_serial), "Repeated publication retains one notice identity for a queued event")
	var first_serial := int(first.events[0].notice_serial)
	simulation.events.clear()
	simulation.events.append({"type": "freeze", "actor": unit.entity_id})
	var next := simulation.snapshot()
	h._check(int(next.events[0].notice_serial) > first_serial, "Next same-clock batch cannot reuse the previous notice identity")
	Helper.compare(h, [unit.hp, unit.shield, unit.power, unit.money, unit.ammo, simulation.rng.state], before,
		"Notice publication cannot settle health, power, ammo, credits or consume combat RNG")
	simulation.events.clear()
	unit.money = float(Content.constants.ECON.UPG_STEPS[0].price)
	unit.score = float(Content.constants.ECON.UPG_STEPS[0].score)
	h._check(simulation.buy(unit, "hp"), "Accepted authority purchase produces its original report")
	h._check(simulation.events.size() == 1 and simulation.events[0].type == "buy" and int(simulation.events[0].level) == 1,
		"Accepted ordinary upgrade reports the purchased step rather than the displayed combat tier")
	unit.money = 0
	h._check(not simulation.buy(unit, "sp") and simulation.events.size() == 1, "Rejected purchase cannot fabricate another success notice")
	simulation.free()
