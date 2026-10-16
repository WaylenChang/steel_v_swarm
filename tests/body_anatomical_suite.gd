extends RefCounted

const JointTests = preload("res://tests/body_joint_suite.gd")
const QuaternionTests = preload("res://tests/quaternion_suite.gd")

static func run(h: Node, fixtures: Dictionary, baseline: Dictionary) -> void:
	if not fixtures.has("bodyAnatomy"):
		h._check(false, "Regenerate original anatomical/hand/equipment/bow body references")
		return
	for item: Dictionary in fixtures.bodyAnatomy:
		var rig := BodyRig.new()
		h.add_child(rig)
		if not rig.configure(item.key):
			h._check(false, "Pack original anatomical body scene: " + item.key)
			rig.free()
			continue
		var owner: Dictionary = rig.forms[item.form]
		var expected: Dictionary = baseline[item.key].duplicate(true)
		for step: Dictionary in item.steps:
			BodyAnatomicalPose.reset(rig.poses, owner)
			h._check(owner.anatomical.applied == step.resetApplied, "Original overlay reset latch")
			for spec: Dictionary in step.resetNodes:
				expected[int(spec.id)] = spec
			for id: int in expected:
				JointTests.compare_frame(h, rig.nodes[id], expected[id], "Original control/archery/base reset before the next frame")
			for update: Dictionary in step.updates:
				var node: Node3D = rig.nodes[int(update.id)]
				if update.has("rotation"):
					rig.poses.set_rotation(node, update.rotation)
				if update.has("position"):
					rig.poses.set_position(node, BodyPose.vector(update.position))
				if update.has("scale"):
					rig.poses.set_scale(node, BodyPose.vector(update.scale))
			owner.merge(step.fields, true)
			if step.has("hair"):
				owner.hairFlick.merge(step.hair, true)
			BodyAimPose.stabilize(rig.poses, owner)
			BodyAnatomicalPose.step(rig.poses, owner, step.blend)
			BodyAimPose.forward(rig.poses, owner)
			BodyAnatomicalPose.hair(rig.poses, owner, step.now)
			BodyArcheryPose.step(rig.poses, owner)
			BodyEquipmentPose.step(rig.poses, owner, step.get("shared"))
			h._check(owner.anatomical.applied == step.applied, "Original anatomical overlay marks captured bases even at zero blend")
			for index in range(step.bases.size()):
				QuaternionTests.compare(h, owner.anatomical.bases[index].q, step.bases[index].q, "Original pre-overlay quaternion cache", .00001)
			for spec: Dictionary in step.nodes:
				expected[int(spec.id)] = spec
			for id: int in expected:
				JointTests.compare_frame(h, rig.nodes[id], expected[id], "Original complete anatomical/gaze/hair/bow/equipment pose: " + item.key)
		rig.free()
