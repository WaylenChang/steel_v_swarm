class_name BodyGaitQuad
extends RefCounted

const Joint = preload("res://scripts/body_gait_joints.gd")

static func step(poses: BodyPose, state: Dictionary, rig: Dictionary, delta: float, now: float, speed: float, yaw_rate: float) -> void:
	assert(rig.kind == "quad", "Quadruped motion requires the original quad rig")
	if Joint.flag(rig, "cephalopod"):
		_cephalopod(poses, state, rig, delta, now, speed, yaw_rate)
		return
	var stride := Joint.or_number(rig, "stride", 1.4) * Joint.or_number(rig, "s", 1)
	state.ph += speed * delta * PI / maxf(0.25, stride)
	state.amp = BodyMotionState.damp(state.amp, clampf(speed / Joint.or_number(rig, "top", 10), 0, 1.15), 6, delta)
	var amplitude: float = state.amp
	var phase: float = state.ph
	var gait: String = rig.gait if Joint.flag(rig, "gait") else "trot"
	var rotary := rig.get("gallopType") == "rotary"
	var gallop := 0.0
	var phases: Dictionary
	match gait:
		"walk":
			phases = {"FL": phase - PI * 0.5, "FR": phase + PI * 0.5, "HL": phase, "HR": phase + PI}
		"tripod":
			phases = {"FL": phase, "FR": phase + PI, "HL": phase, "HR": phase + PI}
		"crawl":
			phases = {"FL": phase, "FR": phase + PI, "HL": phase + PI * 0.5, "HR": phase - PI * 0.5}
		_:
			gallop = clampf((amplitude - 0.35) / 0.35, 0, 1) * Joint._field(rig, "gallop", 1)
			var trot := [0.0, -PI, -PI, 0.0]
			var running := [0.6 * PI, -PI, -2 * PI, -0.4 * PI] if rotary else [-PI, -1.4 * PI, -2 * PI, -0.4 * PI]
			phases = {}
			var keys := ["FL", "FR", "HL", "HR"]
			for index in range(keys.size()):
				phases[keys[index]] = phase + float(trot[index]) + (float(running[index]) - float(trot[index])) * gallop
	var leg_amplitude := 0.66 * amplitude * (1 + 0.35 * gallop) * Joint._field(rig, "legAmp", 1)
	var idle := Joint.idle(amplitude)
	var signature := Joint.ground_signature(rig)
	Joint.acceleration_impulses(state, signature, delta)
	var idle_gain := idle * float(signature.breathK)
	var idle_frequency: float = signature.iF
	if not Joint.flag(rig, "limbP"):
		rig.limbP = GaitCurves.profile(rig.get("limb"))
	var profile: Dictionary = rig.limbP
	var duty := GaitCurves.duty(gait, gallop)
	var fore_gain := 0.18 if profile.fore.role == "grasp" else 1.0
	var insect := Joint.flag(rig, "insectLegs")
	if insect:
		phases.ML = float(phases.FL) + PI
		phases.MR = float(phases.FR) + PI
		for leg: Dictionary in rig.insectLegs:
			var leg_phase: float = phases[leg.key]
			var cycle := GaitCurves.cycle(leg_phase)
			poses.set_axis(leg.root, "y", float(leg.side) * _hip(leg_phase, duty) * leg_amplitude * 0.65)
			poses.set_axis(leg.lift, "z", float(leg.side) * maxf(0, sin(PI * (cycle - duty) / (1 - duty))) * (0.32 * amplitude if cycle >= duty else 0.0))
			Joint.flex_chain(poses, leg.chain, leg_phase, amplitude, idle, now, 0.45, 0, {"P": profile.hind, "duty": duty})
	else:
		var base: Dictionary = rig.quadBase if Joint.flag(rig, "quadBase") else {}
		var keys := ["FL", "FR", "HL", "HR"]
		for index in range(keys.size()):
			var key: String = keys[index]
			poses.set_axis(rig["leg" + key], "x", Joint.or_number(base, key, 0) + _hip(phases[key], duty) * leg_amplitude * (fore_gain if index < 2 else 0.9)
				+ idle_gain * sin(now * 1.6 * idle_frequency + index * 1.5) * 0.025)
	if Joint.flag(rig, "chFL") and not insect:
		var keys := ["FL", "FR", "HL", "HR"]
		for index in range(keys.size()):
			var key: String = keys[index]
			if Joint.flag(rig, "soft"):
				soft_leg(poses, rig["ch" + key], float(phases[key]) + now * 0.7 * idle + index * 0.5, 2.2 * amplitude + 0.55 * idle, now + index * 1.3, 0.5 * amplitude)
			else:
				Joint.flex_chain(poses, rig["ch" + key], phases[key], amplitude * (1 + 0.3 * gallop), idle, now + index * 1.4, 0.45, 0,
					{"P": profile.fore if index < 2 else profile.hind, "duty": duty})
	if Joint.flag(rig, "midLegs") and not insect:
		assert(rig.midLegs.size() <= 2, "Source middle-leg phases only define a left/right pair")
		for index in range(rig.midLegs.size()):
			var leg_phase := phase + (PI if index == 0 else 0.0)
			var cycle := GaitCurves.cycle(leg_phase)
			var idle_phase := now * 1.6 * idle_frequency - index * 1.8
			poses.set_axis(rig.midLegs[index], "x", _hip(leg_phase, duty) * leg_amplitude * 0.9 + idle_gain * sin(idle_phase) * 0.025)
			if Joint.flag(rig, "midKnees"):
				poses.set_axis(rig.midKnees[index], "x", GaitCurves.limb(profile.hind, 0, cycle, duty, amplitude) * 0.45 + idle_gain * sin(idle_phase + 0.6) * 0.02)
			if Joint.flag(rig, "midTarsi"):
				poses.set_axis(rig.midTarsi[index], "x", GaitCurves.limb(profile.hind, 1, cycle, duty, amplitude) * 0.42 + idle_gain * sin(idle_phase + 1.2) * 0.15)
	if Joint.flag(rig, "tents"):
		for index in range(rig.tents.size()):
			tent_guard(poses, rig.tents[index], now, index, phase, amplitude)
	state.roll = BodyMotionState.damp(state.roll, clampf(yaw_rate * 0.22, -0.5, 0.5), 3.5, delta)
	var spine: Node3D = rig.spine
	var chest: Node3D = rig.chest
	var sway := Joint.or_number(rig, "rollSway", 0) * sin(phase + PI * 0.25) * amplitude
	poses.set_axis(spine, "z", -float(state.roll) * 0.14 + sway)
	poses.set_position_axis(spine, "x", sway * 1.4)
	var rider := Joint.flag(rig, "rider")
	var pitch_amplitude := Joint._field(rig, "pitchAmp", 0.05) * (1 + gallop * (0.55 if rider else 0.9 if rotary else 0.7))
	state.qacc = BodyMotionState.damp(Joint._field(state, "qacc", 0), clampf(float(state.accel) * 0.012, -0.08, 0.1), 5 * (1 - 0.6 * float(signature.spool)), delta)
	var gait_pitch := _axial_wave(phase, gallop) * pitch_amplitude * amplitude
	poses.set_axis(spine, "x", gait_pitch + float(state.qacc) + (float(state.srg) - float(state.brk)) * 0.02)
	poses.set_axis(chest, "x", _axial_wave(phase, gallop, 0.7) * pitch_amplitude * amplitude)
	poses.set_axis(chest, "y", 0)
	if not rider:
		var heavy: Dictionary = rig.hvy if Joint.flag(rig, "hvy") else {}
		poses.add_axis(chest, "x", Joint.or_number(rig, "_chg", 0) * Joint.or_number(heavy, "chest", 0)
			- maxf(maxf(Joint.or_number(rig, "_kickL", 0), Joint.or_number(rig, "_kickR", 0)), Joint.or_number(rig, "_kickB", 0)) * 0.05)
	poses.set_axis(spine, "y", sin(phase * 0.5) * 0.12 * amplitude + idle * sin(now * 0.6) * 0.04 if gait == "crawl" else 0.0)
	var bob := GaitCurves.bounce(phase, duty, gallop) * Joint.or_number(rig, "bob", 0.08) * amplitude * (1 + gallop * 0.8)
	poses.set_position_axis(spine, "y", float(rig.hipsY0) - bob + idle_gain * sin(now * 1.4 * idle_frequency + phase) * 0.02 - float(state.srg) * 0.03 - float(state.brk) * 0.03)
	if rider:
		_rider(poses, rig, phase, gallop, amplitude, idle, now, signature)
	else:
		var pitch := poses.axis(spine, "x") + poses.axis(chest, "x")
		poses.set_axis(rig.neck, "x", -pitch * 1.8 + _axial_wave(phase, gallop, 1.4) * 0.05 * amplitude)
		var head_arc := ((gait_pitch + poses.axis(chest, "x")) * Joint.or_number(rig, "headArm", 0) + poses.axis(rig.neck, "x") * Joint.or_number(rig, "headArmN", 0)) * 0.9
		poses.set_position_axis(rig.neck, "y", float(rig.neckY0) + bob * 0.55 + clampf(head_arc, -0.28, 0.28))
		Joint.stabilize_head(poses, {"head": rig.head}, [poses.axis(spine, "x") + poses.axis(chest, "x") + poses.axis(rig.neck, "x"),
			poses.axis(spine, "y"), poses.axis(spine, "z") + poses.axis(rig.neck, "z")], idle, now, 0.95, signature.idleK)
	Joint.gaze(poses, state, rig, yaw_rate, delta)
	var tail: Array = rig.tailSegs if rig.get("tailSegs") is Array else []
	if not tail.is_empty():
		Joint.whip_tail(poses, tail, state, delta, amplitude, idle, now, yaw_rate, Joint._field(rig, "tailBase", 0.12), null, null, Joint._field(rig, "tailStiffness", 1))
		poses.add_axis(tail[0], "x", Joint._field(rig, "tailUp", 0.12) * amplitude * Joint._field(rig, "tailStiffness", 1))

static func _rider(poses: BodyPose, rig: Dictionary, phase: float, gallop: float, amplitude: float, idle: float, now: float, signature: Dictionary) -> void:
	var pitch := poses.axis(rig.spine, "x") + poses.axis(rig.chest, "x")
	var roll := poses.axis(rig.spine, "z")
	poses.set_axis(rig.neck, "x", -pitch * 0.4 + _axial_wave(phase, gallop, 0.6) * 0.03 * amplitude)
	poses.set_axis(rig.neck, "z", -roll * 0.5)
	poses.set_position_axis(rig.neck, "y", rig.neckY0)
	poses.set_position_axis(rig.neck, "x", 0)
	var kick := maxf(Joint.or_number(rig, "_kickL", 0), Joint.or_number(rig, "_kickR", 0))
	var charge := Joint.or_number(rig, "_chg", 0)
	var heavy: Dictionary = rig.hvy if Joint.flag(rig, "hvy") else {}
	var chest: Node3D = rig.get("humChest")
	var neck: Node3D = rig.get("humNeck")
	if chest != null:
		poses.set_axis(chest, "x", -pitch * 0.4 + _axial_wave(phase, gallop, 1.3) * 0.022 * amplitude
			+ idle * float(signature.breathK) * sin(now * 1.5) * 0.015 + charge * Joint.or_number(heavy, "chest", 0) - kick * 0.06)
		poses.set_axis(chest, "z", -roll * 0.3)
	if neck != null:
		poses.set_axis(neck, "x", -pitch * 0.15)
		poses.set_axis(neck, "z", -roll * 0.12)
	var accumulated_pitch := pitch + poses.axis(rig.neck, "x") + (poses.axis(chest, "x") if chest != null else 0.0) + (poses.axis(neck, "x") if neck != null else 0.0)
	var accumulated_roll := roll + poses.axis(rig.neck, "z") + (poses.axis(chest, "z") if chest != null else 0.0) + (poses.axis(neck, "z") if neck != null else 0.0)
	poses.set_axis(rig.head, "x", -accumulated_pitch * 0.95)
	poses.set_axis(rig.head, "z", -accumulated_roll * 0.9)
	poses.set_axis(rig.head, "y", idle * float(signature.idleK) * sin(now * 0.5) * 0.28)
	if Joint.flag(rig, "armSh"):
		for index in range(rig.armSh.size()):
			var shoulder: Node3D = rig.armSh[index]
			var elbow: Node3D = rig.armEl[index]
			var base: Dictionary = rig.armBase[index]
			poses.set_axis(shoulder, "x", float(base.shX) + idle * 0.02 * sin(now * 1.6 - index * 1.8) + charge * Joint.or_number(heavy, "armR", 0) - kick * 0.08)
			poses.set_axis(shoulder, "z", float(base.shZ) + idle * 0.015 * sin(now * 1.6 - index * 1.8 + 1.2))
			if Joint.flag(rig, "archery"):
				poses.set_axis(shoulder, "y", Joint.or_number(base, "shY", 0))
			poses.set_axis(elbow, "x", float(base.elX) + idle * 0.025 * sin(now * 1.6 - index * 1.8 + 0.6))
	Joint.gun_pitch(poses, rig.get("gunR"), minf(1, idle + Joint.or_number(rig, "_fireAim", 0)), kick, charge, heavy)

static func _hip(phase: float, duty: float) -> float:
	return GaitCurves.hip(GaitCurves.cycle(phase), duty)

static func _cephalopod(poses: BodyPose, state: Dictionary, rig: Dictionary, delta: float, now: float, speed: float, yaw_rate: float) -> void:
	state.amp = BodyMotionState.damp(state.amp, clampf(speed / float(rig.top), 0, 1), 6, delta)
	state.ph += speed * delta / maxf(0.2, float(rig.stride) * Joint.or_number(rig, "s", 1))
	poses.set_position_axis(rig.spine, "y", float(rig.hipsY0) + sin(now * 0.9) * float(rig.bob))
	poses.set_rotation(rig.spine, [0.025 * float(state.amp), clampf(-yaw_rate * 0.035, -0.10, 0.10), 0.0])
	for node: Node3D in [rig.chest, rig.neck, rig.head]:
		poses.set_rotation(node, [0.0, 0.0, 0.0])

static func _axial_wave(phase: float, gallop: float, shift: float = 0.0) -> float:
	return sin(phase * 2 - shift) * (1 - gallop) + sin(phase - shift) * gallop

static func soft_leg(poses: BodyPose, chain: Array, phase: float, amplitude: float, now: float, quest: float) -> void:
	assert(not chain.is_empty(), "Source soft-leg chains must contain a joint")
	var swing := maxf(0, -cos(phase))
	for index in range(chain.size()):
		var joint: Dictionary = chain[index]
		var fraction := float(index) / maxi(1, chain.size() - 1)
		poses.set_axis(joint.g, "x", float(joint.base) + float(joint.k) * (sin(phase - float(joint.d)) * amplitude - swing * quest * cos(fraction * PI) * 2.4
			+ swing * quest * sin(now * 6 - float(joint.d) * 2.2) * 1.1 * fraction))

static func tent_guard(poses: BodyPose, chain: Array, now: float, index: int, phase: float, amplitude: float) -> void:
	assert(not chain.is_empty(), "Source guard tentacle chains must contain a joint")
	var cock := 0.55 + 0.3 * sin(now * 0.4 + index * 1.7)
	for link in range(chain.size()):
		var joint: Dictionary = chain[link]
		var fraction := float(link) / maxi(1, chain.size() - 1)
		poses.set_axis(joint.g, "x", float(joint.base) - cos(fraction * PI) * 0.4 * cock + sin(now * 0.9 - float(joint.d) + index * 2.1) * 0.12
			+ sin(now * 7 - float(joint.d) * 3) * 0.06 * fraction * fraction + sin(phase - float(joint.d)) * 0.12 * amplitude)
