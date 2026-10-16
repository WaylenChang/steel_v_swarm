class_name BodyAimPose
extends RefCounted

const Joint = preload("res://scripts/body_gait_joints.gd")

static func stabilize(poses: BodyPose, rig: Dictionary) -> void:
	if not Joint.flag(rig, "stab"):
		return
	for track: Dictionary in rig.stab:
		track.qa = SourceQuaternion.world(track.ref)
		track.qb = SourceQuaternion.world(track.g.get_parent())
		poses.set_quaternion(track.g, SourceQuaternion.multiply(SourceQuaternion.multiply(SourceQuaternion.inverse(track.qb), track.qa), track.q0))

static func forward(poses: BodyPose, rig: Dictionary, active: Variant = null) -> void:
	var state: Dictionary = rig if active == null else active
	var aiming := clampf(Joint.or_number(state, "_fireAim", 0), 0, 1)
	if not Joint.flag(rig, "aimForward"):
		return
	var slot: String = state._aimSlot if Joint.flag(state, "_aimSlot") else "light"
	for track: Dictionary in rig.aimForward:
		var always := Joint.flag(track, "alwaysForward")
		var weight := 1.0 if always else aiming
		if not always and (weight <= 0.0001 or slot not in track.slots):
			continue
		track.qa = SourceQuaternion.world(track.ref)
		track.qb = SourceQuaternion.world(track.g.get_parent())
		track.qc = SourceQuaternion.multiply(SourceQuaternion.multiply(SourceQuaternion.inverse(track.qb), track.qa), track.qf)
		var launcher: Dictionary = rig.launcher if rig.get("launcher") is Dictionary else {}
		if launcher.get("pivot") == track.g:
			var extension := clampf((poses.position_axis(launcher.lift, "y") / float(launcher.extension) - float(launcher.rotateStart)) / (1 - float(launcher.rotateStart)), 0, 1)
			track.qc = SourceQuaternion.slerp(track.qc, poses.read(track.g).q, 1 - extension)
		poses.set_quaternion(track.g, SourceQuaternion.slerp(poses.read(track.g).q, track.qc, weight))
