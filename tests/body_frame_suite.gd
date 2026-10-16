extends RefCounted

const Helper = preload("res://tests/status_suite.gd")
const JointTests = preload("res://tests/body_joint_suite.gd")
const LaunchTests = preload("res://tests/body_launch_suite.gd")

static func run(h: Node, fixtures: Dictionary, baseline: Dictionary) -> void:
	for key: String in ["bodyReferenceMotion", "bodyLocomotion", "bodyCombatKeys"]:
		if not fixtures.has(key):
			h._check(false, "Regenerate original reference/shield/full-frame body oracle: " + key)
			return
	for item: Dictionary in fixtures.bodyCombatKeys:
		for step: Dictionary in item.steps:
			h._near(BodyReferenceMotion.sample_keys(item["keys"], step.time), step.value, "Original authored combat key boundaries and interpolation")
	for mode: String in ["bodyReferenceMotion", "bodyLocomotion", "bodyPresentationFrame"]:
		var items: Array = fixtures.bodyLocomotion if mode == "bodyPresentationFrame" else fixtures[mode]
		for item: Dictionary in items:
			var rig := BodyRig.new()
			h.add_child(rig)
			var initial_phase := func(index): return float(item.phases.get(str(index), 0)) / float(Content.balance.bodyRules.shield.timeWindow)
			if not rig.configure(item.key, initial_phase):
				h._check(false, "Pack original full-frame body scene: " + item.key)
				rig.free()
				continue
			var expected: Dictionary = baseline[item.key].duplicate(true)
			if not rig.morph.is_empty():
				h._check(is_same(rig.morph.ground.shield.state, rig.morph.air.shield.state), "Both morph shields retain the same mutable defense state")
			var entity: Dictionary = {} if mode == "bodyReferenceMotion" else {"id": item.entity, "hero": true, "heroY": 0.0, "flies": false, "df": 0, "sp": 100}
			if mode != "bodyReferenceMotion":
				entity.merge(item.get("initialState", {}), true)
			var presentation: BodyPresentation
			if mode == "bodyPresentationFrame":
				presentation = BodyPresentation.new()
				presentation.configure(rig, item.entity)
				presentation.entity = entity
				presentation.pending_snap = false
			for step: Dictionary in item.steps:
				if mode == "bodyReferenceMotion":
					_reference(rig, entity, step)
				else:
					_locomotion(rig, entity, step, presentation)
					Helper.compare(h, entity.get("loco"), step.loco, "Original complete frame motion state and weights")
					Helper.compare(h, entity.get("fireFx"), step.fire, "Original immutable body shot survives ordinary complete-frame pose updates")
					Helper.compare(h, entity.get("castFx"), step.cast, "Original cast overlay expiration before reference motion")
					Helper.compare(h, entity.get("heavyFx"), step.heavy, "Original heavy event lifecycle in the complete frame")
					LaunchTests.frame(h, rig, step)
					for field: String in ["loco", "castFx", "heavyFx"]:
						var reference: Variant = step.loco if field == "loco" else step.cast if field == "castFx" else step.heavy
						if reference == null:
							h._check(entity.get(field) == null, "Original absent/expired complete-frame state: " + field)
					var shield: Node3D = entity.get("shieldMesh")
					h._check(shield == null if step.shieldMesh == null else shield == rig.nodes[int(step.shieldMesh)], "Original active body defense-mesh binding")
					if step.morph != null:
						h._near(rig.morph.m, step.morph.m, "Original full-frame morph progress")
						h._near(rig.morph.k, step.morph.k, "Original full-frame morph rest blend")
						h._check(rig.morph.act == step.morph.act and rig.morph.air0 == step.morph.air, "Original morph activity/active-tree thresholds")
					h._check(rig.form == step.active, "Original current rig after locomotion morph swap")
				_states(h, rig, step.states)
				for uniform: Dictionary in step.uniforms:
					var material := rig.materials[int(uniform.id)] as ShaderMaterial
					h._near(float(material.get_shader_parameter("uTime")), uniform.time, "Original active-only defense material clock")
					h._near(float(material.get_shader_parameter("uFlash")), uniform.flash, "Original defense flash decay")
				for spec: Dictionary in step.nodes:
					expected[int(spec.id)] = spec
				for id: int in expected:
					JointTests.compare_frame(h, rig.nodes[id], expected[id], "Original complete ordered body frame: " + mode + "/" + item.key)
			rig.free()

static func _reference(rig: BodyRig, entity: Dictionary, step: Dictionary) -> void:
	rig.form = step.active
	if step.has("form"):
		rig.morph.gg.visible = step.active == "ground"
		rig.morph.ag.visible = step.active == "air"
	entity.merge(step.get("entity", {}), true)
	if step.has("cast"):
		entity.castFx = step.cast
	if step.has("shot"):
		entity.fireFx = step.shot
		rig.fire(step.shot)
	for owner: Dictionary in rig.forms.values():
		owner.merge(step.get("fields", {}), true)
		BodyReferenceMotion.reset_shield(rig.poses, owner.get("shield"))
	if not rig.morph.is_empty():
		BodyReferenceMotion.reset(rig.poses, rig.forms["air" if step.active == "ground" else "ground"])
	for update: Dictionary in step.updates:
		var node: Node3D = rig.nodes[int(update.id)]
		rig.poses.set_position(node, BodyPose.vector(update.position))
		rig.poses.set_rotation(node, update.rotation)
	rig.pose_reference(entity, INF if step.has("invalidDelta") else float(step.delta), NAN if step.has("invalidNow") else float(step.now), rig.morph.is_empty())
	if not rig.morph.is_empty():
		for owner: Dictionary in rig.forms.values():
			BodyReferenceMotion.pose_shield(rig.poses, owner.get("shield"), 0.6)
			BodyReferenceMotion.authored(rig.poses, owner, entity, NAN if step.has("invalidNow") else float(step.now))
			BodyReferenceMotion.clear_shield(rig.poses, owner)

static func _locomotion(rig: BodyRig, entity: Dictionary, step: Dictionary, presentation: BodyPresentation = null) -> void:
	rig.poses.set_position(rig.source_root, BodyPose.vector(step.position))
	rig.poses.set_axis(rig.source_root, "y", step.yaw)
	entity.merge(step.get("entity", {}), true)
	if step.has("shot"):
		entity.fireFx = step.shot
	if step.has("castInput"):
		entity.castFx = step.castInput
	if step.has("heavyInput"):
		entity.heavyFx = step.heavyInput.duplicate(true)
	if presentation != null:
		presentation.frame(step.delta, step.now, 1, BodyPose.vector(step.position), step.yaw, BodyPose.vector(step.position), entity, false)
	else:
		rig.step_combat(entity, step.now, step.delta)
		rig.step_locomotion(entity, step.delta, step.now, BodyPose.vector(step.previous), step.previousYaw)

static func _states(h: Node, rig: BodyRig, expected: Dictionary) -> void:
	for form: String in expected:
		var owner: Dictionary = rig.forms[form]
		var result: Dictionary = expected[form]
		for key: String in result.fields:
			Helper.compare(h, owner.get(key), result.fields[key], "Original reference-body field: " + key)
		if not result.fields.has("_bowAim"):
			h._check(not owner.has("_bowAim"), "Rejected reference steps preserve lazy bow aim initialization")
		if result.shield != null:
			var shield: Dictionary = owner.shield
			h._near(BodyReferenceMotion.phase(shield), result.shield.phase, "Original shared morph defense phase advances only once")
			Helper.compare(h, shield.get("posture"), result.shield.posture, "Original gait/aim-dependent shield posture")
			Helper.compare(h, shield.get("expand"), result.shield.expand, "Original local/remote defense expansion")
			Helper.compare(h, shield.get("state"), result.shield.state, "Original shared phase/expansion state identity")
