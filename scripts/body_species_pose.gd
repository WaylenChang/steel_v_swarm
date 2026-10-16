class_name BodySpeciesPose
extends RefCounted

const Joint = preload("res://scripts/body_gait_joints.gd")

static func aim_held(poses: BodyPose, rig: Dictionary) -> void:
	var held: Array = rig.heldWeapons if rig.get("heldWeapons") is Array else []
	if rig.kind == "aerial" and not held.is_empty() and Joint.or_number(rig, "_fireAim", 0) > 0.0001:
		BodyGaitBiped.pose_aim(poses, rig, 0)

static func step(poses: BodyPose, state: Dictionary, rig: Dictionary, delta: float, now: float, speed: float) -> void:
	if Joint.flag(rig, "predatory") and rig.kind == "biped":
		var pose: Dictionary = rig.predatory
		var rest := 1 - clampf(speed / float(rig.top), 0, 1) if Joint.flag(rig, "knuckle") else 1.0
		poses.set_axis(pose.hunch, "x", pose.pitch)
		for side: String in ["L", "R"]:
			var sign_value := 1.0 if side == "L" else -1.0
			var shoulder: Node3D = rig["arm" + side]
			var elbow: Node3D = rig["armChain" + side][0].g
			var wrist: Node3D = rig["armChain" + side][1].g
			poses.add_axis(shoulder, "x", (float(pose.shoulder) + sin(now * 2 + sign_value) * 0.025 - poses.axis(shoulder, "x")) * rest)
			poses.set_axis(shoulder, "y", 0)
			poses.set_axis(shoulder, "z", sign_value * float(pose.splay) * rest)
			poses.add_axis(elbow, "x", (float(pose.elbow) - poses.axis(elbow, "x")) * rest)
			poses.add_axis(wrist, "x", (float(pose.wrist) - poses.axis(wrist, "x")) * rest)
		poses.add_axis(rig.head, "x", -float(pose.pitch))
	if Joint.flag(rig, "groundWings"):
		state.wingSpread = BodyMotionState.damp(Joint.or_number(state, "wingSpread", 0), clampf((speed / Joint.or_number(rig, "top", 10) - 0.3) / 0.3, 0, 1), 7, delta)
		for wing: Dictionary in rig.groundWings:
			var nodes := [wing.w, wing.outer, wing.hand]
			for index in range(nodes.size()):
				poses.set_rotation(nodes[index], [0.0, float(wing.sgn) * (float(wing.fold[index]) + (float(wing.run[index]) - float(wing.fold[index])) * float(state.wingSpread)), 0.0])
			poses.set_axis(wing.w, "z", float(wing.sgn) * (-0.30 + 0.58 * float(state.wingSpread)))
			poses.set_axis(wing.w, "x", sin(now * 7) * 0.045 * float(state.wingSpread))
			poses.set_axis(wing.outer, "x", sin(now * 7 - 0.6) * 0.035 * float(state.wingSpread))
	if Joint.flag(rig, "tentacleWaves"):
		for wave: Dictionary in rig.tentacleWaves:
			var convergence := clampf(Joint.or_number(rig, "_fireAim", 0) / Joint.or_number(wave, "convergeAt", 1), 0, 1) if wave.get("slot") == rig.get("_aimSlot") else 0.0
			var travel: Array = wave.travel if wave.get("travel") is Array else []
			for index in range(wave.chain.size()):
				var angles: Array = []
				for component in range(3):
					var gain := float(travel[component]) if component < travel.size() and ControlPreferences.truthy(travel[component]) else 0.0
					var amplitude := float(wave.swing[component]) + gain * clampf(state.amp, 0, 1)
					angles.append(amplitude * (1 - convergence) * sin(now * TAU * float(wave.frequency) + float(wave.phase) + float(state.ph) - index * 0.36 + component * 1.2)
						+ (Joint.or_number(wave, "convergeYaw", 0) * convergence if index == 0 and component == 1 else 0.0))
				poses.set_rotation(wave.chain[index], angles)
