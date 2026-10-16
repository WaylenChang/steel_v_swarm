extends RefCounted

const Helper = preload("res://tests/status_suite.gd")
const JointTests = preload("res://tests/body_joint_suite.gd")

static func run(h: Node, fixtures: Dictionary, baseline: Dictionary) -> void:
	for key: String in ["bodyMorphs", "morphScalars", "morphQuaternions"]:
		if not fixtures.has(key):
			h._check(false, "Regenerate original per-part morph oracle: " + key)
			return
	for item: Dictionary in fixtures.morphScalars:
		var expected := item.duplicate()
		expected.erase("progress")
		Helper.compare(h, {"ease": BodyMorph.ease(item.progress), "rest": BodyMorph.rest_weight(item.progress), "ground": BodyMorph.alpha(item.progress, false),
			"air": BodyMorph.alpha(item.progress, true), "active": BodyMorph.active(item.progress), "shrink": BodyMorph.shrink(item.progress)}, expected,
			"Original morph easing/rest/fade/shrink/endpoint rules")
	for item: Dictionary in fixtures.morphQuaternions:
		var value := BodyMorph.slerp(BodyPose.quaternion(item.first), BodyPose.quaternion(item.second), item.weight)
		var expected := BodyPose.quaternion(item.result)
		h._check(Vector4(value.x, value.y, value.z, value.w).distance_to(Vector4(expected.x, expected.y, expected.z, expected.w)) < .000001,
			"Original morph quaternion shortest path and near-linear normalization")
	for item: Dictionary in fixtures.bodyMorphs:
		var rig := BodyRig.new()
		h.add_child(rig)
		if not rig.configure(item.key):
			h._check(false, "Pack original morph body: " + item.key)
			rig.free()
			continue
		var expected_states: Dictionary = baseline[item.key].duplicate(true)
		for step: Dictionary in item.steps:
			if step.has("set"):
				rig.morph.m = float(step.set)
			rig.step_morph(step.delta, step.altitude)
			for id: float in step.disturbed:
				var node: Node3D = rig.nodes[int(id)]
				var state := rig.poses.read(node)
				var spec := {"rotation": [.11, -.03, .05], "order": "XYZ"}
				var rotation := (state.q as Quaternion) * WeaponPresentation.source_rotation(spec)
				var size: Vector3 = state.s
				size.x *= 1.05
				rig.poses.write(node, state.p + Vector3(.07, 0, 0), rotation, size)
			rig.pose_morph()
			Helper.compare(h, {"m": rig.morph.m, "k": rig.morph.k, "air": rig.morph.air0, "act": rig.morph.act,
				"groundVisible": rig.morph.gg.visible, "airVisible": rig.morph.ag.visible}, step.result, "Original morph swap/settle/reverse/end trace")
			h._check(rig.form == ("air" if step.result.air else "ground"), "Active native rig and visible morph tree switch on the same edge")
			for form: String in ["ground", "air"]:
				var side: Dictionary = rig.morph.plan.g if form == "ground" else rig.morph.plan.a
				var values: Array = []
				for entry: Dictionary in side.fade:
					values.append(entry.a)
				Helper.compare(h, values, step.fades[form], "Original per-part fade cache and endpoint no-op")
			for row: Dictionary in step.nodes:
				expected_states[int(row.id)] = row
			for row: Dictionary in expected_states.values():
				var node: Node3D = rig.nodes[int(row.id)]
				var expected := Transform3D(Basis(BodyPose.quaternion(row.quaternion)).scaled_local(BodyPose.vector(row.scale)), BodyPose.vector(row.position))
				h._check(node.transform.origin.distance_to(expected.origin) < .0002 and node.basis.x.distance_to(expected.basis.x) < .0002
					and node.basis.y.distance_to(expected.basis.y) < .0002 and node.basis.z.distance_to(expected.basis.z) < .0002,
					"Original signed per-part morph/settle transform: " + item.key)
				h._check(node.visible == row.visible, "Original morph part/outline visibility")
				h._check(int(node.get_parent().get_meta("source_id", -1)) == int(row.parent), "Original morph hierarchy remains attached to its authored parents")
				if row.has("instances"):
					JointTests.compare_instances(h, node, row.instances, "Per-part morph retains all body instance matrices")
			for row: Dictionary in step.materials:
				var material: Material = rig.materials[int(row.id)]
				var opacity: float
				var transparent: bool
				var depth: bool
				if material is BaseMaterial3D:
					var native := material as BaseMaterial3D
					opacity = native.albedo_color.a
					transparent = native.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
					depth = native.depth_draw_mode != BaseMaterial3D.DEPTH_DRAW_DISABLED
				else:
					opacity = material.get_meta("source_opacity")
					transparent = material.get_meta("source_transparent")
					depth = material.get_meta("source_depth_write")
				Helper.compare(h, {"opacity": opacity, "transparent": transparent, "depth": depth},
					{"opacity": row.opacity, "transparent": row.transparent, "depth": row.depth}, "Original morph material alpha/transparency/depth restoration")
		rig.free()
