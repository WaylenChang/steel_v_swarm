class_name BodyLocomotion
extends RefCounted

const Joint = preload("res://scripts/body_gait_joints.gd")

static func step(body: BodyRig, entity: Dictionary, delta: float, now: float, previous: Vector3, previous_yaw: float, frame: Dictionary = {}) -> void:
	if delta < float(Content.balance.bodyRules.locomotion.minimumStep) or not body.forms.has(body.form):
		return
	body.reset_anatomical()
	body.step_morph(delta, Joint.or_number(entity, "heroY", 0))
	var rig: Dictionary = body.forms[body.form]
	if rig.kind == "static":
		return
	if not body.motion.configured:
		body.begin_motion(str(entity.id))
	if entity.get("loco") is Dictionary:
		body.motion.values = entity.loco
	body.sample_motion(delta, frame.get("position", body.poses.read(body.source_root).p), frame.get("yaw", body.poses.axis(body.source_root, "y")), previous, previous_yaw)
	entity.loco = body.motion.values
	if not body.morph.is_empty():
		for owner: Dictionary in body.forms.values():
			BodyReferenceMotion.reset_shield(body.poses, owner.get("shield"))
		BodyReferenceMotion.reset(body.poses, body.forms["air" if body.form == "ground" else "ground"])
	elif rig.kind == "biped":
		BodyReferenceMotion.reset_shield(body.poses, rig.get("shield"))
	match rig.kind:
		"biped":
			body.pose_biped_motion(delta, now)
		"aerial":
			body.pose_aerial_motion(delta, now)
		"quad":
			body.pose_quad_motion(delta, now)
		"morph":
			assert(false, "Legacy root-fold rigs require their original driver; use the captured per-part morph bodies")
			return
		_:
			body.pose_vehicle_motion(delta, now)
	BodySpeciesPose.aim_held(body.poses, rig)
	body.pose_cast(entity, now)
	body.pose_jump(entity, delta)
	body.pose_species(delta, now)
	body.stabilize_pose()
	var posture := Joint.idle(body.motion.values.amp) * (1 - clampf(Joint.or_number(rig, "_fireAim", 0), 0, 1))
	if Joint.flag(rig, "shield"):
		rig.shield.posture = posture if rig.kind == "biped" else 0.0
	body.pose_reference(entity, delta, now, body.morph.is_empty())
	body.pose_morph()
	if not body.morph.is_empty() and Joint.flag(body.morph.ground, "shield") and Joint.flag(body.morph.ground.shield, "state"):
		var shield_posture := (1 - BodyMorph.ease(body.morph.m)) * posture
		for owner: Dictionary in [body.morph.ground, body.morph.air]:
			BodyReferenceMotion.pose_shield(body.poses, owner.shield, shield_posture)
		for owner: Dictionary in [body.morph.ground, body.morph.air]:
			BodyReferenceMotion.authored(body.poses, owner, entity, now)
	if Joint.flag(entity, "hero") and Joint.flag(rig, "combat"):
		entity.shieldMesh = rig.shield.barrier
	if not body.morph.is_empty() and body.morph.act:
		var blend := BodyMorph.ease(body.morph.m)
		body.pose_anatomical(1 - blend, "ground")
		_copy_pairs(body.poses, body.morph.plan.g, body.morph.plan.a)
		body.pose_anatomical(blend, "air")
		_copy_pairs(body.poses, body.morph.plan.a, body.morph.plan.g)
		body.aim_forward("ground", rig)
		body.aim_forward("air", rig)
		_copy_pairs(body.poses, body.morph.plan.g if body.form == "ground" else body.morph.plan.a,
			body.morph.plan.a if body.form == "ground" else body.morph.plan.g)
	else:
		body.pose_anatomical()
		body.aim_forward()
	for form: String in body.forms:
		BodyAnatomicalPose.hair(body.poses, body.forms[form], now)
		body.pose_payloads(now, form)
	body.pose_archery()
	if not body.morph.is_empty():
		body.pose_equipment("ground", rig)
		body.pose_equipment("air", rig)
		body.clear_morph_shields()
	else:
		body.pose_equipment()
	body.finish_motion(Joint.or_number(entity, "heroY", 0), Joint.flag(entity, "flies"))

static func _copy_pairs(poses: BodyPose, source: Dictionary, target: Dictionary) -> void:
	assert(source.pairs.size() == target.pairs.size(), "Original morph pair correspondence is required")
	for index in range(source.pairs.size()):
		poses.set_quaternion(target.pairs[index].n, poses.read(source.pairs[index].n).q)
