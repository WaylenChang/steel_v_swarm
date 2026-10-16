extends RefCounted

const Helper = preload("res://tests/status_suite.gd")
const JointTests = preload("res://tests/body_joint_suite.gd")
const FrameTests = preload("res://tests/body_frame_suite.gd")
const LaunchTests = preload("res://tests/body_launch_suite.gd")

static func run(h: Node, fixtures: Dictionary, baseline: Dictionary) -> void:
	if not fixtures.has("bodyAuthorityLocomotion") or not fixtures.has("bodyTpsMuzzleFallback"):
		h._check(false, "Regenerate original owner TPS authority-body frames and fallback directions")
		return
	for item: Dictionary in fixtures.bodyTpsMuzzleFallback:
		var result := BodyLaunchPose.resolve(null, item.slot, BodyPose.vector(item.position), item.eye, item.bodyYaw,
			BodyPose.vector(item.camera), item.reach, null if item.direction == null else BodyPose.vector(item.direction))
		LaunchTests.compare(h, result, item.result, "Original absent-rig TPS fallback, including zero-length convergence")
	for item: Dictionary in fixtures.bodyAuthorityLocomotion:
		var metadata: Dictionary = Content.balance.bodies[item.key]
		var authority := AuthorityBodyPose.new()
		h.add_child(authority)
		var initial_phase := func(index): return float(item.phases.get(str(index), 0)) / float(Content.balance.bodyRules.shield.timeWindow)
		if not authority.configure(metadata.character, metadata.side, item.entity, initial_phase):
			h._check(false, "Pack original authority body scene: " + item.key)
			authority.free()
			continue
		var rig := authority.body
		var entity := {"id": item.entity, "hero": true, "heroY": 0.0, "flies": false, "df": 0, "sp": 100, "isSelf": true}
		authority.presentation.entity = entity
		var expected: Dictionary = baseline[item.key].duplicate(true)
		for step: Dictionary in item.steps:
			entity.merge(step.get("entity", {}), true)
			entity.isSelf = true
			if step.has("shot"):
				entity.fireFx = step.shot
				rig.fire(step.shot)
			if step.has("castInput"):
				entity.castFx = step.castInput
			if step.has("heavyInput"):
				entity.heavyFx = step.heavyInput.duplicate(true)
			authority.advance(step.delta, step.now, BodyPose.vector(step.position), float(step.yaw) - PI, 1,
				entity, step.get("firstPerson", false))
			Helper.compare(h, entity.get("loco"), step.loco, "Original owner body displacement/weights across FPV freezes")
			for key: String in ["castFx", "heavyFx"]:
				var value: Variant = step.cast if key == "castFx" else step.heavy
				if value == null:
					h._check(entity.get(key) == null, "Original owner body canceled/expired event: " + key)
				else:
					Helper.compare(h, entity.get(key), value, "Original owner body event age: " + key)
			FrameTests._states(h, rig, step.states)
			for uniform: Dictionary in step.uniforms:
				var material := rig.materials[int(uniform.id)] as ShaderMaterial
				h._near(float(material.get_shader_parameter("uTime")), uniform.time, "Authority body retains source defense material advancement")
				h._near(float(material.get_shader_parameter("uFlash")), uniform.flash, "Authority body retains source defense flash decay")
			for spec: Dictionary in step.nodes:
				expected[int(spec.id)] = spec
			for id: int in expected:
				JointTests.compare_frame(h, rig.nodes[id], expected[id], "Original private owner body complete pose")
			LaunchTests.frame(h, rig, step)
			h._check(not authority.visible, "Authority body posing never renders a second actor")
		authority.free()
