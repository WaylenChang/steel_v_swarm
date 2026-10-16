extends RefCounted

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("hurtOpacity") or not fixtures.has("hurtReflash") or not Content.balance.has("hurtPresentation"):
		h._check(false, "Regenerate original hurt-vignette CSS timing and repeated-hit references")
		return
	var state := HurtFlashState.new()
	state.trigger(0)
	for step: Dictionary in fixtures.hurtOpacity:
		h._near(state.opacity(float(step.time)), float(step.value), "Original browser ease-out interpolation between hurtFlash keyframes")
	state = HurtFlashState.new()
	for step: Dictionary in fixtures.hurtReflash:
		if step.get("end", false):
			state.finish()
		else:
			state.trigger(float(step.at))
		h._check(state.active == step.active, "Original animation-end and repeated-hit admission")
		h._near(state.started, step.started, "Original active hurt flash is not restarted; stale animation gets one forced restart")
	var overlay := HurtOverlay.new()
	h.add_child(overlay)
	h._check(overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE and not overlay.visible, "Hurt vignette is initially hidden and cannot intercept native HUD input")
	overlay.flash()
	h._check(overlay.visible and overlay.state.active, "Published hurt notification activates the native vignette")
	var first := overlay.state.started
	overlay.shader_material.set_shader_parameter("opacity", .7)
	overlay.flash()
	h._check(overlay.state.started == first and float(overlay.shader_material.get_shader_parameter("opacity")) == .7,
		"A repeated active notification preserves the current visible flash instead of resetting it")
	overlay.clear()
	h._check(not overlay.visible and not overlay.state.active, "Room reset clears a previous battle's private hurt animation")
	overlay.free()
