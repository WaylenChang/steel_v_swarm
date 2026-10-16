class_name BodyGaitAerial
extends RefCounted

const Joint = preload("res://scripts/body_gait_joints.gd")

static func step(poses: BodyPose, state: Dictionary, rig: Dictionary, delta: float, now: float, forward: float, lateral: float, yaw_rate: float) -> void:
	assert(rig.kind == "aerial", "Aerial motion requires the original aerial rig")
	var top := Joint.or_number(rig, "top", 20)
	var signature := Joint.flight_signature(rig)
	var speed := sqrt(forward * forward + lateral * lateral)
	var response := 4.5 * (1 + float(signature.surge))
	state.roll = BodyMotionState.damp(state.roll, clampf(-lateral / top, -1, 1) * 0.26 * float(signature.bank), response, delta)
	var pitch := 0.0 if Joint.flag(rig, "level") else clampf(forward / top, -1, 1) * Joint._field(rig, "pitchTop", 0.2) + clampf(float(state.accel) * 0.006, -0.07, 0.07)
	state.pitch = BodyMotionState.damp(state.pitch, pitch, response, delta)
	var acceleration_reference: float = Content.balance.bodyRules.locomotion.accelerationReference
	state.flr = BodyMotionState.damp(Joint._field(state, "flr", 0), clampf(-float(state.accel) / acceleration_reference, 0, 1) * float(signature.flare), 6, delta)
	var tilt: Node3D = rig.tilt
	poses.set_axis(tilt, "z", state.roll)
	poses.set_axis(tilt, "x", float(state.pitch) - float(state.flr) * 0.14)
	var attack := clampf(Joint.or_number(rig, "_aim", 0), 0, 1)
	poses.add_axis(tilt, "x", attack * 0.09)
	var hover := clampf(1 - speed / 3, 0, 1) * float(signature.hover) * (1 - 0.65 * attack)
	poses.add_axis(tilt, "x", sin(now * 7 * float(signature.hoverF)) * 0.014 * hover)
	poses.add_axis(tilt, "z", sin(now * 6.1 * float(signature.hoverF) + 1.1) * 0.016 * hover)
	poses.set_position_axis(tilt, "y", Joint.or_number(rig, "tiltY0", 0) + sin(now * 2.2 * float(signature.hoverF) + float(state.ph)) * Joint.or_number(rig, "bob", 0.08) * float(signature.hoverA))
	var kick := Joint.or_number(rig, "_kickB", 0)
	var charge := Joint.or_number(rig, "_chg", 0)
	if kick > 0.01 or absf(charge) > 0.01:
		var heavy: Dictionary = rig.hvy if rig.get("hvy") is Dictionary else {}
		poses.add_axis(tilt, "x", -kick * 0.05 + charge * Joint._field(heavy, "chest", 0.03))
		if charge > 0:
			poses.set_position_axis(tilt, "y", poses.position_axis(tilt, "y") - charge * 0.05)
	if Joint.flag(rig, "jets"):
		var thrust := clampf(speed / Joint.or_number(rig, "top", 30), 0, 1)
		for index in range(rig.jets.size()):
			var jet: Dictionary = rig.jets[index]
			jet.g.visible = thrust > 0.03 or Joint.flag(jet, "idle")
			var flicker := 1 + sin(now * 31 + index * 2.1 + float(state.ph)) * 0.1
			var length_factor: Dictionary = jet.lenF if jet.get("lenF") is Dictionary else {}
			var low := 0.35 * Joint._field(length_factor, "hold", 1)
			var high := 1.85 * Joint._field(length_factor, "run", 1)
			poses.set_scale(jet.g, Vector3(1, (low + (high - low) * thrust) * flicker, 1))
			BodyMaterials.set_opacity(jet.m1, (0.2 + 0.4 * thrust) * flicker)
			BodyMaterials.set_opacity(jet.m2, 0.4 + 0.5 * thrust)
			var material := jet.m1 as BaseMaterial3D
			assert(material != null, "Source jet emission requires an imported standard material")
			BodyMaterials.set_emission(material, 1.2 + 2.2 * thrust)
	if Joint.flag(rig, "wings"):
		var travel := clampf(speed / top, 0, 1)
		if Joint.flag(rig, "insect"):
			state.flap = Joint.or_number(state, "flap", 0) + delta * (30 + travel * 16)
			var amplitude := (0.3 + travel * 0.12 + float(state.flr) * 0.3) * (1 - 0.25 * attack)
			for spec: Dictionary in rig.wings:
				var phase: float = float(state.flap) - (0.5 if Joint.flag(spec, "pair") else 0.0)
				poses.set_axis(spec.w, "z", float(spec.sgn) * sin(phase) * amplitude)
				poses.set_axis(spec.w, "y", float(spec.sgn) * cos(phase) * 0.55)
				poses.set_axis(spec.w, "x", cos(phase) * 0.8)
				poses.set_axis(spec.outer, "z", float(spec.sgn) * sin(phase - 0.35) * amplitude * 0.8)
		else:
			state.flap = Joint.or_number(state, "flap", 0) + delta * (3.2 + travel * 9) * (1 - 0.8 * attack)
			var amplitude := (0.24 + travel * 0.34 + float(state.flr) * 0.5) * (1 - 0.85 * attack)
			var axial: Dictionary = rig.axialWave if rig.get("axialWave") is Dictionary else {}
			if not Joint.flag(axial, "stableHead"):
				poses.set_position_axis(tilt, "y", poses.position_axis(tilt, "y") + cos(float(state.flap) + float(state.ph)) * amplitude * 0.06)
				poses.add_axis(tilt, "x", sin(float(state.flap) + float(state.ph) - 0.4) * amplitude * 0.035)
			for spec: Dictionary in rig.wings:
				wing(poses, spec, float(state.flap) + float(state.ph), amplitude, attack)
	if Joint.flag(rig, "tailSegs"):
		var amplitude := clampf(speed / Joint.or_number(rig, "top", 30), 0, 1)
		Joint.whip_tail(poses, rig.tailSegs, state, delta, amplitude, Joint.idle(amplitude), now, yaw_rate, 0, null, rig.get("tailCurl"))
	if Joint.flag(rig, "axialWave"):
		var axial: Dictionary = rig.axialWave
		if Joint.flag(axial, "stableHead"):
			poses.set_rotation(tilt, [0.0, 0.0, 0.0])
			poses.set_position_axis(tilt, "y", rig.tiltY0)
		for index in range(axial.chain.size()):
			var node: Node3D = axial.chain[index]
			if Joint.flag(axial, "stableHead"):
				poses.set_rotation(node, [0.0, 0.0, 0.0])
			poses.set_axis(node, "y", float(axial.amplitude) * sin(now * TAU * float(axial.frequency) - index * float(axial.delay)) - clampf(yaw_rate * float(axial.turn), -0.12, 0.12))
	var rotor_wings: Array = rig.rotorWings if Joint.flag(rig, "rotorWings") else []
	for spec: Dictionary in rotor_wings:
		var phase: float = now * TAU * float(spec.frequency) + float(spec.phase)
		poses.set_rotation(spec.node, [float(spec.twist) * sin(phase + PI / 2), float(spec.sign) * float(spec.sweep) * cos(phase), float(spec.sign) * float(spec.lift) * sin(phase)])
	if Joint.flag(rig, "flightAxial"):
		var axial: Dictionary = rig.flightAxial
		poses.set_rotation(axial.waist, [sin(now * 2) * float(axial.bend), clampf(yaw_rate * 0.04, -0.08, 0.08), 0.0])
		poses.set_axis(axial.chest, "x", -poses.axis(axial.waist, "x") * 0.6)
		poses.set_axis(axial.neck, "x", -poses.axis(tilt, "x") - poses.axis(axial.waist, "x") - poses.axis(axial.chest, "x"))
	if Joint.flag(rig, "swim"):
		var swim: Dictionary = rig.swim
		var phase: float = now * TAU * float(swim.frequency)
		var amplitude := 0.35 + 0.65 * clampf(speed / top, 0, 1)
		poses.set_axis(swim.body, "x", float(swim.bodyAmp) * sin(phase) * amplitude)
		for index in range(swim.tail.size()):
			poses.set_rotation(swim.tail[index], [float(swim.tailAmp) * sin(phase - index * float(swim.delay)) * amplitude,
				clampf(-yaw_rate * 0.035, -0.08, 0.08) * (index + 1) / swim.tail.size(), 0.0])
		for index in range(swim.fins.size()):
			poses.set_axis(swim.fins[index], "z", (-1.0 if index != 0 else 1.0) * float(swim.finAmp) * sin(phase - 0.7) * amplitude)

static func wing(poses: BodyPose, spec: Dictionary, phase: float, amplitude: float, attack: float, additive: bool = false) -> void:
	var sign_value: float = spec.sgn
	var membrane := Joint.flag(spec, "membrane")
	_wing_axis(poses, spec.w, "z", sign_value * ((0.0 if additive else Joint.or_number(spec, "dihedral", 0)) + sin(phase) * amplitude - 0.10 * attack), additive)
	_wing_axis(poses, spec.w, "x", cos(phase) * amplitude * 0.18, additive)
	if spec.get("hand") == null:
		_wing_axis(poses, spec.outer, "z", sign_value * (sin(phase - 0.7) * amplitude * 1.4 - 0.18 * attack), additive)
		return
	var elbow := pow(maxf(0, cos(phase)), 2)
	var wrist := pow(maxf(0, cos(phase - 0.32)), 2)
	var folding := 0.35 if membrane else 1.0
	_wing_axis(poses, spec.w, "y", sign_value * sin(phase - 0.25) * amplitude * 0.16, additive)
	_wing_axis(poses, spec.outer, "x", cos(phase - 0.22) * amplitude * 0.12, additive)
	_wing_axis(poses, spec.outer, "y", sign_value * ((0.0 if additive else Joint.or_number(spec, "elbowSweep", 0)) + elbow * amplitude * 1.25 * folding + 0.25 * attack), additive)
	_wing_axis(poses, spec.outer, "z", sign_value * sin(phase - 0.30) * amplitude * 0.24, additive)
	_wing_axis(poses, spec.hand, "y", sign_value * ((0.0 if additive else Joint.or_number(spec, "wristSweep", 0)) + wrist * amplitude * 0.95 * folding + 0.18 * attack), additive)
	_wing_axis(poses, spec.hand, "z", sign_value * sin(phase - 0.62) * amplitude * 0.18, additive)
	_wing_axis(poses, spec.hand, "x", cos(phase - 0.45) * amplitude * (0.16 if membrane else 0.38), additive)

static func _wing_axis(poses: BodyPose, node: Node3D, axis: String, value: float, additive: bool) -> void:
	poses.set_axis(node, axis, value + (poses.axis(node, axis) if additive else 0.0))

