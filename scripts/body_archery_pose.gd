class_name BodyArcheryPose
extends RefCounted

const Joint = preload("res://scripts/body_gait_joints.gd")

static func step(poses: BodyPose, rig: Dictionary) -> void:
	if not Joint.flag(rig, "archery"):
		return
	var bow: Dictionary = rig.archery
	var weight := clampf(Joint.or_number(rig, "_bowAim", 0), 0, 1)
	var carry := SourceQuaternion.multiply(SourceQuaternion.inverse(poses.read(bow.bowHand).q), bow.bowCarry)
	poses.set_quaternion(bow.bow, SourceQuaternion.slerp(bow.bowRotation, carry, 1 - weight))
	carry = SourceQuaternion.multiply(SourceQuaternion.inverse(poses.read(bow.hand).q), bow.arrowCarry)
	poses.set_quaternion(bow.arrow, SourceQuaternion.slerp(bow.arrowRotation, carry, 1 - weight))
	var age := Joint._field(rig, "_fireAge", INF)
	var release := sin(PI * (age - 0.26) / 0.20) if age >= 0.26 and age < 0.46 else 0.0
	var draw: float = float(bow.restDraw) + (float(bow.fullDraw) - float(bow.restDraw)) * weight * (1 - release)
	poses.set_position_axis(bow.nock, "z", -draw)
	var height: float = bow.halfHeight
	var rest: float = bow.restDraw
	var string_scale := sqrt(draw * draw + height * height) / sqrt(rest * rest + height * height)
	for index in range(bow.strings.size()):
		poses.set_axis(bow.strings[index], "x", (-1.0 if index != 0 else 1.0) * (atan2(draw, height) - atan2(rest, height)))
		poses.set_scale(bow.strings[index], Vector3.ONE * string_scale)
	var recoil := BodyPose.named(bow.arrow, "gun_recoil")
	assert(recoil != null, "Missing original bow projectile recoil node")
	poses.set_scale(recoil, Vector3.ONE * (0.001 if weight > 0.0001 and release > 0.45 else 1.0))
	if weight <= 0.0001:
		return
	var group: Node3D = rig.anatomical.group
	var target := group.to_local(bow.head.global_position) + BodyPose.vector(bow.gripOffset)
	target = group.to_global(target)
	_place_arm(poses, bow.bowShoulder, bow.bowElbow, bow.bowHand, target, Vector3(-1, -0.1, 0.1), weight)
	BodyAimPose.forward(poses, rig)
	_place_arm(poses, bow.shoulder, bow.elbow, bow.hand, bow.nock.global_position, BodyPose.vector(bow.pole), weight)
	poses.set_rotation(bow.hand, [0.0, 0.0, 0.0])
	var arrow: Node3D = bow.arrow
	target = arrow.get_parent().to_local(bow.nock.global_position)
	poses.set_position(arrow, (poses.read(arrow).p as Vector3).lerp(target, weight))
	var rotation := SourceQuaternion.multiply(SourceQuaternion.inverse(SourceQuaternion.world(arrow.get_parent())), SourceQuaternion.world(group))
	poses.set_quaternion(arrow, SourceQuaternion.slerp(poses.read(arrow).q, rotation, weight))

static func _place_arm(poses: BodyPose, shoulder: Node3D, elbow: Node3D, hand: Node3D, target: Vector3, axis: Vector3, weight: float) -> void:
	var upper: Vector3 = poses.read(elbow).p
	var lower: Vector3 = poses.read(hand).p
	var upper_length := SourceQuaternion.vector_length(upper)
	var lower_length := SourceQuaternion.vector_length(lower)
	var delta: Vector3 = shoulder.get_parent().to_local(target) - (poses.read(shoulder).p as Vector3)
	var distance := maxf(absf(upper_length - lower_length) + 0.00001, minf(upper_length + lower_length - 0.00001, SourceQuaternion.vector_length(delta)))
	delta = SourceQuaternion.vector_normalized(delta)
	var reach := (upper_length * upper_length - lower_length * lower_length + distance * distance) / (2 * distance)
	var pole := SourceQuaternion.vector_normalized(axis + delta * -SourceQuaternion.vector_dot(axis, delta))
	var direction: Vector3 = delta * reach + pole * sqrt(maxf(0, upper_length * upper_length - reach * reach))
	var rotation := SourceQuaternion.from_unit_vectors(SourceQuaternion.vector_normalized(upper), SourceQuaternion.vector_normalized(direction))
	poses.set_quaternion(shoulder, SourceQuaternion.slerp(poses.read(shoulder).q, rotation, weight))
	direction = shoulder.to_local(target) - upper
	rotation = SourceQuaternion.from_unit_vectors(SourceQuaternion.vector_normalized(lower), SourceQuaternion.vector_normalized(direction))
	poses.set_quaternion(elbow, SourceQuaternion.slerp(poses.read(elbow).q, rotation, weight))
