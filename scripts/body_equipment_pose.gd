class_name BodyEquipmentPose
extends RefCounted

const Joint = preload("res://scripts/body_gait_joints.gd")

static func step(poses: BodyPose, rig: Dictionary, active: Variant = null) -> void:
	var state: Dictionary = rig if active == null else active
	if Joint.flag(rig, "dorsalMount"):
		poses.set_position_axis(rig.dorsalMount.node, "y", rig.dorsalMount.height)
	if Joint.flag(rig, "dorsalLift"):
		var lift: Dictionary = rig.dorsalLift
		var weight := clampf(Joint.or_number(state, "_aimH", 0), 0, 1)
		poses.set_position_axis(lift.node, "y", float(lift.rest) + float(lift.height) * weight)
	if not Joint.flag(rig, "anatomical"):
		return
	var pose: Dictionary = rig.anatomical
	for held: Dictionary in pose.grips:
		place_grip(poses, held)
	if pose.controls.is_empty():
		return
	var aiming := clampf(Joint.or_number(state, "_fireAim", 0), 0, 1)
	var floor_height := INF
	for foot: Node3D in pose.feet:
		floor_height = minf(floor_height, _sole_floor(foot))
	var slot: String = state._aimSlot if Joint.flag(state, "_aimSlot") else "light"
	for control: Dictionary in pose.controls:
		var weight := aiming if slot == control.slot else 0.0
		var node: Node3D = control.node
		var original: Quaternion = poses.read(node).q
		var target: Quaternion = control.stow
		if Joint.flag(control, "carry"):
			target = SourceQuaternion.multiply(SourceQuaternion.inverse(SourceQuaternion.world(node.get_parent())),
				SourceQuaternion.multiply(SourceQuaternion.world(pose.group), control.carry))
		poses.set_quaternion(node, SourceQuaternion.slerp(target, original, weight))
		poses.set_scale(node, (control["size"] as Vector3) * (float(control.scale) + (1 - float(control.scale)) * weight))
		var held: Variant = null
		for grip: Dictionary in pose.grips:
			if grip.node == node:
				held = grip
				break
		if held != null:
			place_grip(poses, held)
		var minimum := _minimum(control, rig)
		var clearance: float = floor_height + float(control.clearance)
		if not is_finite(floor_height) or minimum >= clearance:
			continue
		if held != null:
			var arm: Variant = null
			for candidate: Dictionary in pose.braces:
				if candidate.hand == node.get_parent():
					arm = candidate
					break
			if arm == null:
				continue
			var orientation := SourceQuaternion.world(node)
			var point: Vector3 = arm.hand.global_position
			point.y += clearance - minimum
			var pole: Vector3 = arm.shoulder.get_parent().to_local(arm.elbow.global_position) - (poses.read(arm.shoulder).p as Vector3)
			BodyAnatomicalPose.arm_to_point(poses, arm, point, pole, 1)
			poses.set_quaternion(node, SourceQuaternion.multiply(SourceQuaternion.inverse(SourceQuaternion.world(node.get_parent())), orientation))
			place_grip(poses, held)
			minimum = _minimum(control, rig)
			if minimum < clearance and weight > 0 and weight < 0.95:
				poses.set_quaternion(node, SourceQuaternion.multiply(SourceQuaternion.inverse(SourceQuaternion.world(node.get_parent())), SourceQuaternion.world(pose.group)))
				place_grip(poses, held)
			continue
		var position := node.global_position
		position.y += clearance - minimum
		poses.set_position(node, node.get_parent().to_local(position))

static func place_grip(poses: BodyPose, held: Dictionary) -> void:
	var state := poses.read(held.node)
	poses.set_position(held.node, -SourceQuaternion.rotate(state.q, held.anchor) + (held.contact as Vector3))
	poses.set_position(held.grip, (held.anchor as Vector3) / (state.s as Vector3))
	poses.set_scale(held.grip, Vector3.ONE / (state.s as Vector3))

static func _minimum(control: Dictionary, rig: Dictionary) -> float:
	var result := INF
	for envelope: Dictionary in control.envelopes:
		for corner: Vector3 in envelope.corners:
			result = minf(result, _world_y(envelope.mesh, corner))
	var muzzle: Node3D = rig.wpn[control.slot].muz
	return minf(result, muzzle.global_position.y)

static func _sole_floor(node: Node3D) -> float:
	var result := INF
	var geometry: Mesh
	if not node.get_meta("presentationEffect", false) and not node.get_meta("isOutline", false):
		if node is MeshInstance3D:
			geometry = node.mesh
		elif node is MultiMeshInstance3D:
			geometry = node.multimesh.mesh
	if geometry != null:
		var box := geometry.get_aabb()
		for x: float in [box.position.x, box.end.x]:
			for y: float in [box.position.y, box.end.y]:
				for z: float in [box.position.z, box.end.z]:
					result = minf(result, _world_y(node, Vector3(x, y, z)))
	for child: Node3D in node.get_children():
		result = minf(result, _sole_floor(child))
	return result

static func _world_y(node: Node3D, local: Vector3) -> float:
	var frame := node.global_transform
	return float(frame.basis.x.y) * local.x + float(frame.basis.y.y) * local.y + float(frame.basis.z.y) * local.z + frame.origin.y
