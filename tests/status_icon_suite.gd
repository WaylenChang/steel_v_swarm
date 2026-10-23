extends RefCounted

const Helper = preload("res://tests/status_suite.gd")

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("statusIcons") or not fixtures.has("statusIconRender") or not Content.balance.controls.has("statusIcons"):
		h._check(false, "Regenerate original status-icon composition and clock-renderer references")
		return
	var state := StatusIconState.new()
	state.configure(Content.balance.controls.statusIcons)
	for item: Dictionary in fixtures.statusIcons:
		state.burn_at = item.burnAt
		var actual := state.observe(item.values, item.now, item.spectating)
		Helper.compare(h, actual, item.result, "Original status combinations preserve poison/EMP tails, duplicate freeze IDs, positive stacks and stable equal-time order")
		Helper.compare(h, state.maximum, item.maximum, "Original status maxima extend only on longer remaining time, expire by ID and survive spectating")
	var strip := StatusIconStrip.new()
	for fixture: Dictionary in fixtures.statusIconRender:
		var actual := strip.presentation(fixture.item)
		for key: String in fixture.result:
			Helper.compare(h, actual[key], fixture.result[key], "Original status timer and rounded clockwise arc: " + key)
	strip.free()
	state.reset()
	h._check(state.maximum.is_empty() and state.burn_at == 0, "New matches clear local icon maxima and burn-event time without changing combat state")
