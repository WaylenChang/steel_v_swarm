class_name BodyAnatomicalPose
extends RefCounted

const Joint = preload("res://scripts/body_gait_joints.gd")

static func reset(poses: BodyPose, rig: Dictionary) -> void:
	if not Joint.flag(rig, "anatomical"):
		return
	var pose: Dictionary = rig.anatomical
	for control: Dictionary in pose.controls:
		poses.write(control.node, control.position, control.q, control["size"])
	if Joint.flag(rig, "archery"):
		var bow: Dictionary = rig.archery
		poses.set_quaternion(bow.bow, bow.bowRotation)
		poses.set_position(bow.arrow, bow.arrowRest)
		poses.set_quaternion(bow.arrow, bow.arrowRotation)
	if not Joint.flag(pose, "applied"):
		return
	for base: Dictionary in pose.bases:
		poses.set_quaternion(base.node, base.q)
	pose.applied = false

static func step(poses: BodyPose, rig: Dictionary, blend: float = 1.0) -> void:
	if not Joint.flag(rig, "anatomical"):
		return
	var pose: Dictionary = rig.anatomical
	for base: Dictionary in pose.bases:
		base.q = poses.read(base.node).q
	for control: Dictionary in pose.controls:
		poses.set_quaternion(control.node, control.q)
	pose.applied = true
	if Joint.flag(rig, "stance") and rig.kind == "biped":
		for side: String in ["L", "R"]:
			var sign_value := 1.0 if side == "L" else -1.0
			poses.set_axis(rig["leg" + side], "y", sign_value * float(rig.stance.toeOut))
			poses.set_axis(rig["leg" + side], "z", sign_value * float(rig.stance.hipSplay))
			if Joint.flag(rig.stance, "armSplay"):
				poses.set_axis(rig["arm" + side], "z", sign_value * (0.10 + float(rig.stance.armSplay)))
	var weight := clampf(Joint.or_number(rig, "_bowAim" if Joint.flag(rig, "archery") else "_fireAim", 0), 0, 1) * blend
	var slot: String = rig._aimSlot if Joint.flag(rig, "_aimSlot") else "light"
	var shot: Variant = pose.shots.get(slot)
	if shot != null and weight > 0.00001:
		var angle := -float(shot.sign) * 0.75 * weight
		for index in range(pose.body.size()):
			var share := 0.50
			if pose.body.size() == 1:
				share = 1.0
			elif pose.body.size() == 2:
				share = 0.60 if index != 0 else 0.40
			elif index == 0:
				share = 0.20
			elif index == 1:
				share = 0.30
			var node: Node3D = pose.body[index]
			poses.set_quaternion(node, SourceQuaternion.multiply(SourceQuaternion.axis_angle(Vector3.UP, angle * share), poses.read(node).q))
		for arm: Dictionary in pose.braces:
			if Joint.flag(arm, "bow") or (not is_same(arm, shot) and not Joint.flag(arm, "alwaysForward")):
				continue
			var group: Node3D = pose.group
			var point := group.to_local(arm.shoulder.global_position)
			var upper_length := SourceQuaternion.vector_length(poses.read(arm.elbow).p)
			var lower_length := SourceQuaternion.vector_length(poses.read(arm.hand).p)
			var inward := -signf(point.x) * minf(absf(point.x), upper_length * 0.28)
			var pole := point + Vector3(inward, -sqrt(upper_length * upper_length - inward * inward), 0)
			point = pole + Vector3(0, 0, lower_length)
			pole = arm.shoulder.get_parent().to_local(group.to_global(pole)) - (poses.read(arm.shoulder).p as Vector3)
			arm_to_point(poses, arm, group.to_global(point), pole, weight)
	if pose.get("head") == null or (not Joint.flag(pose, "bird") and (shot == null or weight <= 0.00001)):
		return
	var gaze_weight := blend if Joint.flag(pose, "bird") else weight
	var target := SourceQuaternion.multiply(SourceQuaternion.world(pose.group), pose.gaze)
	var neck: Node3D = pose.get("neck")
	if neck != null and neck != pose.head:
		var neck_local := SourceQuaternion.multiply(SourceQuaternion.inverse(SourceQuaternion.world(neck.get_parent())), target)
		poses.set_quaternion(neck, SourceQuaternion.slerp(poses.read(neck).q, neck_local, gaze_weight * 0.55))
	var head: Node3D = pose.head
	var head_local := SourceQuaternion.multiply(SourceQuaternion.inverse(SourceQuaternion.world(head.get_parent())), target)
	poses.set_quaternion(head, SourceQuaternion.slerp(poses.read(head).q, head_local, gaze_weight))

static func arm_to_point(poses: BodyPose, arm: Dictionary, target: Vector3, pole: Vector3, weight: float) -> void:
	var shoulder: Node3D = arm.shoulder
	var elbow: Node3D = arm.elbow
	var hand: Node3D = arm.hand
	var upper: Vector3 = poses.read(elbow).p
	var lower: Vector3 = poses.read(hand).p
	var upper_length := SourceQuaternion.vector_length(upper)
	var lower_length := SourceQuaternion.vector_length(lower)
	var delta: Vector3 = shoulder.get_parent().to_local(target) - (poses.read(shoulder).p as Vector3)
	var distance := maxf(absf(upper_length - lower_length) + 0.00001, minf(upper_length + lower_length - 0.00001, SourceQuaternion.vector_length(delta)))
	delta = SourceQuaternion.vector_normalized(delta)
	var reach := (upper_length * upper_length - lower_length * lower_length + distance * distance) / (2 * distance)
	pole += delta * -SourceQuaternion.vector_dot(pole, delta)
	if SourceQuaternion.vector_dot(pole, pole) < 0.0000000001:
		pole = Vector3.BACK + delta * -float(delta.z)
	pole = SourceQuaternion.vector_normalized(pole)
	var direction: Vector3 = delta * reach + pole * sqrt(maxf(0, upper_length * upper_length - reach * reach))
	var local := SourceQuaternion.from_unit_vectors(SourceQuaternion.vector_normalized(upper), SourceQuaternion.vector_normalized(direction))
	poses.set_quaternion(shoulder, SourceQuaternion.slerp(poses.read(shoulder).q, local, weight))
	direction = shoulder.to_local(target) - upper
	local = SourceQuaternion.from_unit_vectors(SourceQuaternion.vector_normalized(lower), SourceQuaternion.vector_normalized(direction))
	poses.set_quaternion(elbow, SourceQuaternion.slerp(poses.read(elbow).q, local, weight))

static func hair(poses: BodyPose, rig: Dictionary, now: float) -> void:
	if not Joint.flag(rig, "hairFlick") or not Joint.flag(rig, "anatomical") or not is_finite(now):
		return
	var flick: Dictionary = rig.hairFlick
	var pose: Dictionary = rig.anatomical
	var age := now - float(flick.firedAt)
	var elapsed := now - float(flick.startedAt)
	var active: bool = age >= 0 and age < float(flick.burstGap)
	poses.set_scale(flick.tuft, Vector3.ONE * (1.0 if active and elapsed >= float(flick.pluckDuration) * 0.4 else 0.001))
	poses.set_axis(flick.index, "x", 0)
	poses.set_axis(flick.middle, "x", pow(sin(PI * minf(1, age / 0.11)), 2) * 1.2 if active and elapsed >= float(flick.pluckDuration) else 1.1 if active else 0.0)
	poses.set_axis(flick.thumb, "z", -0.55 if active else 0.0)
	if not active:
		return
	var point: Vector3 = rig.chest.to_global(Vector3(0.45, 0.40, 1.15))
	if elapsed < float(flick.pluckDuration):
		var pickup: Vector3 = flick.head.to_global(Vector3(0.30, 0.55, 0.24))
		point = point.lerp(pickup, sin(PI * maxf(0, elapsed / float(flick.pluckDuration))))
	arm_to_point(poses, flick, point, Vector3(1, 0, 0.2), 1)
	var parent := SourceQuaternion.world(flick.hand.get_parent())
	var group := SourceQuaternion.world(pose.group)
	var finger := SourceQuaternion.axis_angle(Vector3.RIGHT, -poses.axis(flick.middle, "x"))
	poses.set_quaternion(flick.hand, SourceQuaternion.multiply(SourceQuaternion.multiply(SourceQuaternion.inverse(parent), group), finger))
