class_name BodyGaitBiped
extends RefCounted

const Joint = preload("res://scripts/body_gait_joints.gd")

static func step(poses: BodyPose, state: Dictionary, rig: Dictionary, delta: float, now: float, speed: float, yaw_rate: float) -> void:
	assert(rig.kind == "biped", "Biped motion requires the original biped rig")
	if Joint.flag(rig, "hop"):
		_hop(poses, state, rig, delta, now, speed, yaw_rate)
		return
	var stride := Joint.or_number(rig, "stride", 0.9) * Joint.or_number(rig, "s", 1)
	state.ph += speed * delta * PI / maxf(0.2, stride)
	state.amp = BodyMotionState.damp(state.amp, clampf(speed / Joint.or_number(rig, "top", 8), 0, 1.2), 6, delta)
	var amplitude: float = state.amp
	var idle := Joint.idle(amplitude)
	var signature := Joint.ground_signature(rig)
	Joint.acceleration_impulses(state, signature, delta)
	var bound := Joint.or_number(rig, "bound", 0) * clampf((amplitude - 0.55) / 0.4, 0, 1)
	var phase: float = state.ph
	var right_phase := phase + PI * (1 - bound)
	var wave := sin(phase)
	var run_share := clampf((amplitude - 0.5) / 0.5, 0, 1)
	var leg_amplitude := 0.62 * amplitude * (1 + 0.45 * run_share)
	var leg_base := Joint.or_number(rig, "legBase", 0)
	var arm_base := Joint.or_number(rig, "armBase", 0)
	var stand: float = idle * float(signature.idleK) * sin(now * 0.9 * float(signature.iF) + phase) * 0.03
	var animal := Joint.flag(rig, "knuckle") or Joint.flag(rig, "primate") or Joint.flag(rig, "tuckArms") \
		or Joint.flag(rig, "tinyArms") or Joint.flag(rig, "grounded")
	var lean_gain := Joint._field(rig, "leanF", 1)
	if not Joint.flag(rig, "limbP"):
		var limb: Variant = rig.get("limb") if Joint.flag(rig, "limb") else ({} if animal or lean_gain < 1 else {"fore": "plantigrade", "hind": "plantigrade"})
		rig.limbP = GaitCurves.profile(limb)
	var profile: Dictionary = rig.limbP
	var duty := GaitCurves.duty("walk", run_share)
	var human_share := run_share if profile.hind.posture == "plantigrade" and not animal and lean_gain >= 1 else 0.0
	poses.set_axis(rig.legL, "x", leg_base + _leg_drive(phase, duty, human_share) * leg_amplitude + stand)
	poses.set_axis(rig.legR, "x", leg_base + _leg_drive(right_phase, duty, human_share) * leg_amplitude - stand)
	var right_offset := PI * bound
	var natural := Joint.flag(rig, "naturalArms")
	var tuck := Joint.flag(rig, "tuckArms") and not natural and not Joint.flag(rig, "knuckle")
	var tiny := Joint.flag(rig, "tinyArms") and not natural
	var gun := Joint.flag(rig, "gunArm")
	if tuck or tiny:
		var base := arm_base - 0.2 * amplitude if tuck else arm_base
		var gain := 0.035 if tuck else 0.05
		poses.set_axis(rig.armL, "x", base + sin(phase * 2) * gain * amplitude + idle * sin(now * 1.3) * 0.02)
		poses.set_axis(rig.armR, "x", base + sin(phase * 2 + 0.5) * gain * amplitude + idle * sin(now * 1.3 + 0.6) * 0.02)
	else:
		var swing: float = rig.armSwing if natural else 1.0 if Joint.flag(rig, "knuckle") or Joint.flag(rig, "primate") else 0.75
		poses.set_axis(rig.armL, "x", arm_base + _arm_drive(phase + PI, duty, human_share) * leg_amplitude * (swing + bound * 0.3)
			+ idle * sin(now * 1.3) * 0.025)
		poses.set_axis(rig.armR, "x", arm_base + _arm_drive(phase + right_offset, duty, human_share) * leg_amplitude
			* (0.25 + bound * 0.55 if gun and not natural else swing + bound * 0.3)
			+ idle * sin(now * 1.3 + 0.6) * (0.008 if gun else 0.025))
	if Joint.flag(rig, "legChainL"):
		var human_profile: Variant = profile.hind.duplicate() if human_share != 0 else null
		if human_profile != null:
			human_profile.role = "human"
		var anatomy := {"P": profile.hind, "P2": human_profile, "mix": human_share, "duty": duty}
		Joint.flex_chain(poses, rig.legChainL, phase, amplitude * (1 + 0.25 * run_share), idle, now, 0.45, 0, anatomy)
		Joint.flex_chain(poses, rig.legChainR, right_phase, amplitude * (1 + 0.25 * run_share), idle, now + 1.9, 0.45, 0, anatomy)
		if tuck or tiny:
			var gain := 0.1 if tuck else 0.15
			var hold := (0.35 if tuck else 0.15) * amplitude
			Joint.flex_chain(poses, rig.armChainL, phase, amplitude * gain, idle, now + 0.7, gain, hold)
			Joint.flex_chain(poses, rig.armChainR, phase + 0.4, amplitude * gain, idle, now + 2.6, gain, hold)
		elif (Joint.flag(rig, "knuckle") or Joint.flag(rig, "primate")) and not natural:
			var fore := {"P": profile.fore, "duty": duty}
			Joint.flex_chain(poses, rig.armChainL, phase + PI, amplitude * 1.05, idle, now + 0.7, 0.4, 0.12 * run_share, fore)
			Joint.flex_chain(poses, rig.armChainR, phase + right_offset, amplitude * 1.05, idle, now + 2.6, 0.4, 0.12 * run_share, fore)
		else:
			Joint.flex_chain(poses, rig.armChainL, phase + PI, amplitude, idle, now + 0.7, 0.15, 0.5 * run_share)
			var held := gun and not natural
			Joint.flex_chain(poses, rig.armChainR, phase + right_offset, amplitude * (0.45 + bound * 0.55 if held else 1.0),
				idle * (0.3 if held else 1.0), now + 2.6, 0.15, (0.2 if held else 0.5) * run_share)
	var aim := pose_aim(poses, rig, idle)
	var left_kick := Joint.or_number(rig, "_kickL", 0)
	var right_kick := Joint.or_number(rig, "_kickR", 0)
	var body_kick := Joint.or_number(rig, "_kickB", 0)
	var charge := Joint.or_number(rig, "_chg", 0)
	var heavy: Dictionary = rig.hvy if Joint.flag(rig, "hvy") else {}
	_recoil(poses, rig, left_kick, right_kick, charge, heavy)
	if Joint.flag(rig, "weap"):
		for side: String in ["L", "R"]:
			var chain: Variant = rig.get("armChain" + side)
			if chain is Array and not chain.is_empty():
				poses.add_axis(chain[0].g, "x", -(left_kick if side == "L" else right_kick) * 0.1)
	Joint.gun_pitch(poses, rig.get("gunR"), aim, maxf(right_kick, body_kick * 0.8), charge, heavy)
	Joint.gun_pitch(poses, rig.get("gunL"), aim, maxf(left_kick, body_kick * 0.8), charge, heavy)
	var hips: Node3D = rig.hips
	var bob := 1 - 0.55 * run_share if Joint.flag(rig, "grounded") else 1.0
	poses.set_position_axis(hips, "y", float(rig.hipsY0) - GaitCurves.bounce(phase, duty, bound) * Joint.or_number(rig, "bob", 0.06) * amplitude * bob
		+ idle * float(signature.breathK) * sin(now * 1.7 * float(signature.iF) + phase) * 0.012 - float(state.srg) * 0.03 - float(state.brk) * 0.025)
	if Joint.flag(rig, "primate"):
		poses.set_position_axis(hips, "y", poses.position_axis(hips, "y") - float(rig.primate.crouch) * amplitude)
	var brace := clampf(Joint.or_number(rig, "_aim", 0), 0, 1)
	poses.set_position_axis(hips, "x", wave * Joint.or_number(rig, "sway", 0.05) * amplitude * (1 - bound) * (1 - 0.6 * brace))
	poses.set_axis(hips, "z", -wave * 0.07 * amplitude * (1 - bound) * (1 - 0.7 * brace))
	poses.set_axis(hips, "y", -wave * 0.1 * amplitude * (1 - bound) * (1 - 0.8 * brace))
	state.lean = BodyMotionState.damp(state.lean, (0.22 * amplitude + bound * 0.14 + clampf(float(state.accel) * 0.015, -0.1, 0.15)) * lean_gain,
		5 * (1 - 0.6 * float(signature.spool)), delta)
	poses.set_axis(hips, "x", float(state.lean) + (float(state.srg) * 0.07 - float(state.brk) * 0.08) * lean_gain)
	if Joint.flag(rig, "primate"):
		poses.add_axis(hips, "x", float(rig.primate.lean) * amplitude)
	var waist: Node3D = rig.get("waist")
	if waist != null:
		poses.set_rotation(waist, [-sin(phase * 2) * 0.045 * run_share, wave * 0.04 * amplitude, -poses.axis(hips, "z") * 0.25])
	var chest: Node3D = rig.get("chest")
	if chest != null:
		poses.set_rotation(chest, [0.06 * amplitude + idle * float(signature.breathK) * sin(now * 1.5 * float(signature.iF)) * 0.02
			+ charge * Joint.or_number(heavy, "chest", 0) - (maxf(left_kick, right_kick) + body_kick) * 0.06,
			-poses.axis(hips, "y") * 0.9, -poses.axis(hips, "z") * 0.55])
	if rig.get("headY0") != null:
		poses.set_position_axis(rig.head, "y", float(rig.headY0) + (float(rig.hipsY0) - poses.position_axis(hips, "y")) * 0.5)
	var accumulated: Array = []
	for axis: String in ["x", "y", "z"]:
		accumulated.append(poses.axis(hips, axis) + (poses.axis(waist, axis) if waist != null else 0.0) + (poses.axis(chest, axis) if chest != null else 0.0))
	Joint.stabilize_head(poses, rig, accumulated, idle, now, 0.85 + 0.12 * brace, signature.idleK)
	Joint.gaze(poses, state, rig, yaw_rate, delta)
	if Joint.flag(rig, "tailSegs"):
		var tail_aim: Variant = null
		if Joint.flag(rig, "tailAim"):
			tail_aim = {"p": Joint.or_number(rig, "_aimH", 0)}
			tail_aim.merge(rig.tailAim, true)
		Joint.whip_tail(poses, rig.tailSegs, state, delta, amplitude, idle, now, yaw_rate, 0, tail_aim, rig.get("tailCurl"), 1, rig.get("tailSway"))
		if Joint.flag(rig, "tailSway"):
			poses.add_axis(rig.tailSegs[0], "x", -poses.axis(hips, "x"))
		poses.add_axis(rig.tailSegs[0], "x", Joint.or_number(rig, "tailUp", 0) * amplitude)
	brace_arms(poses, rig, aim)

static func _hop(poses: BodyPose, state: Dictionary, rig: Dictionary, delta: float, now: float, speed: float, yaw_rate: float) -> void:
	var stride := Joint.or_number(rig, "stride", 2.4) * Joint.or_number(rig, "s", 1)
	state.ph += speed * delta * TAU / maxf(0.3, stride)
	state.amp = BodyMotionState.damp(state.amp, clampf(speed / Joint.or_number(rig, "top", 10), 0, 1.15), 6, delta)
	var amplitude: float = state.amp
	var phase: float = state.ph
	var idle := Joint.idle(amplitude)
	var signature := Joint.ground_signature(rig)
	Joint.acceleration_impulses(state, signature, delta)
	var air := maxf(0, sin(phase))
	var drive := cos(phase) * 0.55 * amplitude
	var stand := idle * sin(now * 0.9) * 0.03
	poses.set_axis(rig.legL, "x", Joint.or_number(rig, "legBase", 0) + drive + stand)
	poses.set_axis(rig.legR, "x", Joint.or_number(rig, "legBase", 0) + drive * 0.96 - stand)
	var natural := Joint.flag(rig, "naturalArms")
	if Joint.flag(rig, "legChainL"):
		Joint.flex_chain(poses, rig.legChainL, phase, amplitude * 1.15, idle, now)
		Joint.flex_chain(poses, rig.legChainR, phase + 0.12, amplitude * 1.15, idle, now + 1.9)
		Joint.flex_chain(poses, rig.armChainL, phase + (PI if natural else 0.0), amplitude * (0.75 if natural else 0.2), idle * 0.3, now + 0.7)
		Joint.flex_chain(poses, rig.armChainR, phase, amplitude * (0.75 if natural else 0.2), idle * 0.3, now + 2.6)
	var arm_base := Joint.or_number(rig, "armBase", 0)
	poses.set_axis(rig.armL, "x", arm_base + (-sin(phase) * 0.55 * float(rig.armSwing) if natural else air * 0.12) * amplitude + idle * sin(now * 1.3) * 0.02)
	poses.set_axis(rig.armR, "x", arm_base + (sin(phase) * 0.55 * float(rig.armSwing) if natural else air * 0.12) * amplitude + idle * sin(now * 1.3 + 0.6) * 0.008)
	var aim := pose_aim(poses, rig, idle)
	var left_kick := Joint.or_number(rig, "_kickL", 0)
	var right_kick := Joint.or_number(rig, "_kickR", 0)
	var charge := Joint.or_number(rig, "_chg", 0)
	var heavy: Dictionary = rig.hvy if Joint.flag(rig, "hvy") else {}
	_recoil(poses, rig, left_kick, right_kick, charge, heavy)
	Joint.gun_pitch(poses, rig.get("gunR"), aim, right_kick, charge, heavy)
	Joint.gun_pitch(poses, rig.get("gunL"), aim, left_kick, charge, heavy)
	var hips: Node3D = rig.hips
	poses.set_position_axis(hips, "y", float(rig.hipsY0) + air * Joint.or_number(rig, "hopH", 0.5) * amplitude
		+ idle * float(signature.breathK) * sin(now * 1.7 * float(signature.iF)) * 0.012)
	poses.set_position_axis(hips, "x", 0)
	_sync_legs(poses, state, rig, hips)
	poses.set_axis(hips, "z", 0)
	poses.set_axis(hips, "y", 0)
	state.lean = BodyMotionState.damp(state.lean, Joint.or_number(rig, "hopLean", 0.85) * amplitude + clampf(float(state.accel) * 0.012, -0.08, 0.12),
		5 * (1 - 0.6 * float(signature.spool)), delta)
	poses.set_axis(hips, "x", float(state.lean) + cos(phase + 0.5) * 0.1 * amplitude
		+ (float(state.srg) * 0.06 - float(state.brk) * 0.07) * Joint._field(rig, "leanF", 0.5))
	var chest: Node3D = rig.get("chest")
	if chest != null:
		poses.set_rotation(chest, [0.05 * amplitude + idle * float(signature.breathK) * sin(now * 1.5 * float(signature.iF)) * 0.02
			+ charge * Joint.or_number(heavy, "chest", 0) - maxf(left_kick, right_kick) * 0.05, 0.0, 0.0])
	if rig.get("headY0") != null:
		poses.set_position_axis(rig.head, "y", float(rig.headY0) + maxf(0, float(rig.hipsY0) - poses.position_axis(hips, "y")) * 0.5)
	Joint.stabilize_head(poses, rig, [poses.axis(hips, "x") + (poses.axis(chest, "x") if chest != null else 0.0), 0.0, 0.0], idle, now, 0.9, signature.idleK)
	Joint.gaze(poses, state, rig, yaw_rate, delta)
	if Joint.flag(rig, "tailSegs"):
		Joint.whip_tail(poses, rig.tailSegs, state, delta, amplitude, idle, now, yaw_rate)
		for index in range(rig.tailSegs.size()):
			poses.add_axis(rig.tailSegs[index], "x", (-poses.axis(hips, "x") * 0.7 if index == 0 else 0.0)
				- sin(phase - index * 0.55) * (0.1 + index * 0.03) * amplitude)
	brace_arms(poses, rig, aim)

static func pose_aim(poses: BodyPose, rig: Dictionary, idle: float) -> float:
	var slot: String = rig._aimSlot if Joint.flag(rig, "_aimSlot") else "light"
	if Joint.flag(rig, "anatomical") and not Joint.flag(rig.anatomical.shots, slot):
		return 0.0
	var allow_idle := not (rig.get("aimWhileIdle") is bool and rig.aimWhileIdle == false)
	var aim := minf(1, (idle if allow_idle else 0.0) + Joint.or_number(rig, "_fireAim", 0))
	if not Joint.flag(rig, "aimPose"):
		return aim
	var pose: Dictionary = rig.aimPose
	for side: String in ["R", "L"]:
		var prefix := side.to_lower()
		if pose.get(prefix + "ShoulderX") == null:
			continue
		var arm: Node3D = rig["arm" + side]
		poses.add_axis(arm, "x", (float(pose[prefix + "ShoulderX"]) - poses.axis(arm, "x")) * aim)
		poses.set_axis(arm, "y", Joint.or_number(pose, prefix + "ShoulderY", 0) * aim)
		if Joint.flag(rig, "naturalArms"):
			poses.set_axis(arm, "z", (0.10 if side == "L" else -0.10) * (1 - aim))
		var chain: Variant = rig.get("armChain" + side)
		if chain is Array and not chain.is_empty():
			poses.add_axis(chain[0].g, "x", (float(pose[prefix + "ElbowX"]) - poses.axis(chain[0].g, "x")) * aim)
	return aim

static func brace_arms(poses: BodyPose, rig: Dictionary, weight: float) -> void:
	if not Joint.flag(rig, "naturalArms") or weight <= 0:
		return
	for arm: Node3D in [rig.armL, rig.armR]:
		var pitch := 0.0
		var parent: Node3D = arm.get_parent()
		while parent != null and parent != rig.hips.get_parent():
			pitch += poses.axis(parent, "x")
			parent = parent.get_parent()
		poses.add_axis(arm, "x", -pitch * weight)

static func _leg_drive(phase: float, duty: float, human: float) -> float:
	var cycle := GaitCurves.cycle(phase)
	var walk := GaitCurves.hip(cycle, duty)
	return walk + (float(GaitCurves.human(cycle, duty).hip) - walk) * human

static func _arm_drive(phase: float, duty: float, human: float) -> float:
	var wave := sin(phase)
	return wave + (float(GaitCurves.human(GaitCurves.cycle(phase), duty).arm) - wave) * human

static func _recoil(poses: BodyPose, rig: Dictionary, left: float, right: float, charge: float, heavy: Dictionary) -> void:
	if Joint.flag(rig, "weap"):
		poses.add_axis(rig.armR, "x", -right * 0.15 + charge * Joint.or_number(heavy, "armR", 0))
		poses.add_axis(rig.armL, "x", -left * 0.15 + charge * Joint.or_number(heavy, "armL", 0))

static func _sync_legs(poses: BodyPose, state: Dictionary, rig: Dictionary, hips: Node3D) -> void:
	if rig.get("legL") == null or rig.legL.get_parent() == hips:
		return
	if state.get("legYL") == null:
		state.legYL = poses.position_axis(rig.legL, "y")
		state.legYR = poses.position_axis(rig.legR, "y")
	var offset := poses.position_axis(hips, "y") - float(rig.hipsY0)
	poses.set_position_axis(rig.legL, "y", float(state.legYL) + offset)
	poses.set_position_axis(rig.legR, "y", float(state.legYR) + offset)
