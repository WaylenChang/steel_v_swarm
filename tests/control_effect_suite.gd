extends RefCounted

const Helper = preload("res://tests/status_suite.gd")

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("controlEffectSteps") or not fixtures.has("controlEffectCurves") or not Content.balance.controls.has("controlEffects"):
		h._check(false, "Regenerate original control-status edges, white-flash envelopes and CSS output references")
		return
	var state := ControlStatusState.new()
	state.configure(Content.balance.controls.controlEffects)
	for fixture: Dictionary in fixtures.controlEffectCurves:
		state.left = fixture.left
		state.peak = fixture.peak
		h._near(state.alpha(), fixture.result, "Original control flash clamps peaks/time and reuses the exact splat smoothstep multiplication order")
	state.left = 0
	state.peak = 0
	var overlay := ControlFlashOverlay.new()
	h.add_child(overlay)
	var notices: Array = []
	var opacity: Array = []
	var painted: Array = []
	state.notice.connect(func(value): notices.append(value))
	state.opacity.connect(func(value):
		opacity.append(value)
		overlay.set_opacity(value)
		painted.append(overlay.self_modulate.a))
	for step: Dictionary in fixtures.controlEffectSteps:
		notices.clear()
		opacity.clear()
		painted.clear()
		match str(step.kind):
			"observe": state.observe(step.values)
			"trigger": state.trigger(step.peak)
			"advance": state.advance(step.delta)
			"clear": state.clear_flash()
		Helper.compare(h, notices, step.notices, "Original status notices fire only on rising edges and preserve source declaration order")
		Helper.compare(h, opacity, step.opacity, "Original overlapping CC flash keeps brighter current light, publishes final zero once and clears only the blind edge")
		Helper.compare(h, painted, step.painted, "Native ColorRect applies the original clamped toFixed(3) opacity")
		Helper.compare(h, {"left": state.left, "peak": state.peak, "flags": state.flags, "alpha": state.alpha()}, step.result,
			"Original status flags and flash clocks remain independent of authority damage and status expiry")
	h._check(overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE and overlay.z_index == int(state.rules.layer),
		"Control flash retains source pointer transparency and CSS layer below the HUD")
	overlay.free()
