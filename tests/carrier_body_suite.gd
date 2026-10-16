extends RefCounted

const ViewTests = preload("res://tests/view_suite.gd")

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("carrierBodyMotion"):
		h._check(false, "Regenerate original carrier heading/pitch references")
		return
	for trace: Dictionary in fixtures.carrierBodyMotion:
		var motion := CarrierBodyMotion.new()
		motion.place(BodyPose.vector(trace.initial))
		for step: Dictionary in trace.steps:
			motion.advance(BodyPose.vector(step.position), step.yaw, step.delta, trace.kind == "hyper", step.snap)
			h._near(motion.yaw, step.rotation[1], "Original shortest-path carrier heading including wrap and snap")
			h._near(motion.pitch, step.rotation[0], "Original hypersonic pitch derives from presented displacement and retains stationary attitude")
			var actual := Transform3D(Basis.from_euler(Vector3(motion.pitch, motion.yaw, 0), EULER_ORDER_YXZ), BodyPose.vector(step.position))
			h._check(actual.is_equal_approx(ViewTests.frame(step.matrix)), "Original local-axis hypersonic pitch at arbitrary headings")
	for key: String in Content.balance.bodies:
		var profile: Dictionary = Content.balance.bodies[key]
		if not profile.get("carrier", false):
			continue
		var unit := BattleUnit.new()
		h.add_child(unit)
		unit.configure({"id": 1, "side": profile.side, "kind": profile.kind, "position": Vector3.ZERO,
			"special": {"role": "carrier", "model_key": key, "hp": Content.balance.carrier.hp[profile.kind]}})
		h._check(unit.body != null and unit.body_presentation != null and unit.body.profile == profile,
			"Every source faction/character carrier binds its captured body graph without a replacement chassis")
		if unit.body != null:
			h._check(unit.body.forms.is_empty() == (profile.kind != "kami"), "Source bomber/hypersonic bodies retain the absence of a locomotion rig")
			unit.body_presentation.frame(.016, 10, 1, Vector3.ZERO, 0, Vector3.ZERO,
				{"hero": false, "heroY": 0.0, "flies": true, "dead": false}, false)
		unit.free()
