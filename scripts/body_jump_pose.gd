class_name BodyJumpPose
extends RefCounted

const Joint = preload("res://scripts/body_gait_joints.gd")

static func step(poses: BodyPose, state: Dictionary, rig: Dictionary, entity: Dictionary, delta: float) -> void:
	if entity.get("heroY") == null or rig.kind in ["aerial", "wheeled", "tracked"]:
		return
	if rig.kind == "morph" and Joint._field(state, "morph", 0) > 0.35:
		state.airY = 0.0
		state.aloft = false
		state.rawY = 0.0
		return
	var height := minf(Joint.or_number(entity, "heroY", 0), 6)
	var previous := Joint._field(state, "airY", 0)
	state.airY = BodyMotionState.damp(previous, height, 10, delta)
	var vertical_speed := (float(state.airY) - previous) / maxf(delta, 0.0001)
	var airborne := clampf(float(state.airY) / 1.1, 0, 1)
	var raw_fraction := clampf(height / 1.1, 0, 1)
	var raw_speed := (height - Joint._field(state, "rawY", height)) / maxf(delta, 0.0001)
	if raw_fraction > 0.3:
		state.aloft = true
	elif Joint.flag(state, "aloft") and raw_fraction < 0.12:
		var peak := clampf((Joint.or_number(state, "peakY", 0) - 1.4) / 3.4, 0, 1)
		state.landK = clampf((0.45 + maxf(0, -raw_speed) * 0.05) * (1 + 0.75 * peak), 0, 1.6)
		state.aloft = false
		state.peakY = 0.0
	state.rawY = height
	state.landK = BodyMotionState.damp(Joint._field(state, "landK", 0), 0, 5.5, delta)
	var landing: float = state.landK
	if airborne < 0.02 and landing < 0.02:
		return
	var rising := clampf(vertical_speed * 0.18, -1, 1)
	var up := maxf(0, rising) * airborne
	var fall := maxf(0, -rising) * airborne
	if raw_fraction > 0.3:
		state.peakY = maxf(Joint.or_number(state, "peakY", 0), height)
	var big_jump := clampf((Joint.or_number(state, "peakY", 0) - 1.4) / 3.4, 0, 1)
	var floating := airborne * clampf(1 - absf(rising) * 2.2, 0, 1) * (0.35 + 0.65 * big_jump)
	if rig.kind == "quad":
		if Joint.flag(rig, "insectLegs"):
			for leg: Dictionary in rig.insectLegs:
				Joint.add(poses, leg.lift, "z", float(leg.side) * (0.5 * up + 0.3 * fall))
		else:
			Joint.add(poses, rig.get("legFL"), "x", -(0.5 * up + 0.25 * fall))
			Joint.add(poses, rig.get("legFR"), "x", -(0.45 * up + 0.3 * fall))
			Joint.add(poses, rig.get("legHL"), "x", 0.5 * up - 0.2 * fall)
			Joint.add(poses, rig.get("legHR"), "x", 0.45 * up - 0.25 * fall)
		Joint.add(poses, rig.get("spine"), "x", -0.09 * up + 0.06 * fall + 0.1 * landing)
		Joint.lower(poses, rig.get("spine"), 0.2 * landing)
		if Joint.flag(rig, "chFL"):
			for key: String in ["chFL", "chFR", "chHL", "chHR"]:
				var chain: Variant = rig.get(key)
				if chain is Array and not chain.is_empty():
					var joint: Dictionary = chain[0]
					var axis: String = joint.axis if Joint.flag(joint, "axis") else "x"
					Joint.add(poses, joint.g, axis, float(joint.k) * (0.5 * fall + 0.55 * landing + 0.6 * floating))
		if Joint.flag(rig, "tailSegs") and not Joint.flag(rig, "cephalopod"):
			for index in range(rig.tailSegs.size()):
				Joint.add(poses, rig.tailSegs[index], "x", (0.1 * up - 0.06 * fall) * (1 + index * 0.2))
	else:
		var tuck := 0.35 * up - 0.5 * fall - 0.55 * floating
		Joint.add(poses, rig.get("legL"), "x", tuck * 1.1)
		Joint.add(poses, rig.get("legR"), "x", tuck * 0.85)
		var left: Variant = rig.get("legChainL")
		if left is Array and not left.is_empty():
			Joint.add(poses, left[0].g, "x", 0.55 * fall + 0.35 * up + 0.75 * landing + 0.85 * floating)
			Joint.add(poses, rig.legChainR[0].g, "x", 0.6 * fall + 0.3 * up + 0.7 * landing + 0.8 * floating)
			if left.size() > 1:
				Joint.add(poses, left[1].g, "x", -(0.3 * up + 0.25 * landing))
			if rig.legChainR.size() > 1:
				Joint.add(poses, rig.legChainR[1].g, "x", -(0.28 * up + 0.25 * landing))
		Joint.add(poses, rig.get("kneeL"), "x", 0.5 * fall + 0.3 * up + 0.65 * landing)
		Joint.add(poses, rig.get("kneeR"), "x", 0.55 * fall + 0.25 * up + 0.6 * landing)
		Joint.add(poses, rig.get("ankleL"), "x", -(0.25 * up + 0.2 * landing))
		Joint.add(poses, rig.get("ankleR"), "x", -(0.23 * up + 0.2 * landing))
		if not Joint.flag(rig, "tinyArms") and not Joint.flag(rig, "tuckArms"):
			Joint.add(poses, rig.get("armL"), "x", -(0.45 * fall + 0.15 * up + 0.35 * floating))
			Joint.add(poses, rig.get("armR"), "x", -(0.45 * fall + 0.15 * up + 0.35 * floating) * (0.35 if Joint.flag(rig, "gunArm") else 1.0))
		Joint.add(poses, rig.get("hips"), "x", 0.1 * up - 0.08 * fall + 0.1 * landing)
		Joint.add(poses, rig.get("chest"), "x", 0.08 * fall + 0.14 * landing)
		if not (Joint._field(state, "morph", 0) > 0.35):
			Joint.add(poses, rig.get("torso"), "x", 0.06 * fall + 0.12 * landing)
		Joint.lower(poses, rig.get("hips"), 0.3 * landing)
		Joint.lower(poses, rig.get("torso"), 0.22 * landing)
		if Joint.flag(rig, "tailSegs"):
			for index in range(rig.tailSegs.size()):
				Joint.add(poses, rig.tailSegs[index], "x", (0.12 * up - 0.08 * fall) * (1 + index * 0.2))
