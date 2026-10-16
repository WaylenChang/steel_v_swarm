class_name BodyGaitJoints
extends RefCounted

static func flex_chain(poses: BodyPose, chain: Array, phase: float, amplitude: float, idle: float = 0.0,
		now: float = 0.0, load: float = 0.45, hold: float = 0.0, anatomy: Variant = null) -> void:
	for index in range(chain.size()):
		var joint: Dictionary = chain[index]
		var delay: float = joint.d
		var movement: float
		if anatomy is Dictionary:
			var cycle := GaitCurves.cycle(phase - delay)
			movement = GaitCurves.limb(anatomy.P, index, cycle, anatomy.duty, amplitude)
			if anatomy.get("P2") != null:
				movement += (GaitCurves.limb(anatomy.P2, index, cycle, anatomy.duty, amplitude) - movement) * float(anatomy.mix)
		else:
			var swing := maxf(0, -cos(phase - delay))
			var support := maxf(0, cos(phase - delay))
			movement = (swing * 1.3 + support * support * load) * amplitude * (1 + index * 0.25)
		var angle: float = float(joint.base) + float(joint.k) * (movement + hold + 0.06 * idle * sin(now * 1.6 - delay * 1.5))
		var axis: String = joint.get("axis", "x") if joint.get("axis") != null else "x"
		poses.set_axis(joint.g, axis if not axis.is_empty() else "x", angle)

static func idle(amplitude: float) -> float:
	return clampf(1 - amplitude / float(Content.balance.bodyRules.locomotion.idleAmplitude), 0, 1)

static func _field(spec: Dictionary, key: String, fallback: float) -> float:
	return fallback if spec.get(key) == null else float(spec[key])

static func or_number(spec: Dictionary, key: String, fallback: float) -> float:
	return float(spec[key]) if ControlPreferences.truthy(spec.get(key)) else fallback

static func flag(spec: Dictionary, key: String) -> bool:
	return ControlPreferences.truthy(spec.get(key))

static func add(poses: BodyPose, node: Node3D, axis: String, value: float) -> void:
	if node != null:
		poses.add_axis(node, axis, value)

static func lower(poses: BodyPose, node: Node3D, value: float) -> void:
	if node != null:
		poses.set_position_axis(node, "y", poses.position_axis(node, "y") - value)

static func acceleration_impulses(state: Dictionary, signature: Dictionary, delta: float) -> void:
	var reference: float = Content.balance.bodyRules.locomotion.accelerationReference
	state.srg = BodyMotionState.damp(_field(state, "srg", 0), clampf(float(state.accel) / reference, 0, 1) * float(signature.launch), 10 * float(signature.settle), delta)
	state.brk = BodyMotionState.damp(_field(state, "brk", 0), clampf(-float(state.accel) / reference, 0, 1) * float(signature.brake), 9 * float(signature.settle), delta)

static func gaze(poses: BodyPose, state: Dictionary, rig: Dictionary, yaw_rate: float, delta: float) -> void:
	state.gaze = BodyMotionState.damp(_field(state, "gaze", 0), clampf(yaw_rate * 0.28, -0.45, 0.45), 3, delta)
	if rig.get("head") != null:
		poses.add_axis(rig.head, "y", state.gaze)

static func ground_signature(owner: Dictionary) -> Dictionary:
	var spec: Dictionary = owner.moveSig if owner.get("moveSig") is Dictionary else {}
	var poise := _field(spec, "poise", 0.5)
	var freeze := maxf(0, poise - 0.5) * 2
	var restless := maxf(0, 0.5 - poise) * 2
	return {"iF": _field(spec, "idleF", 1), "idleK": (1 - 0.9 * freeze) * (1 + 1.2 * restless),
		"breathK": _field(spec, "idleA", 1), "launch": _field(spec, "launch", 0), "spool": _field(spec, "spool", 0),
		"brake": _field(spec, "brake", 0), "settle": _field(spec, "settle", 1)}

static func flight_signature(owner: Dictionary) -> Dictionary:
	var spec: Dictionary = owner.moveSig if owner.get("moveSig") is Dictionary else {}
	return {"hover": _field(spec, "hover", 0), "hoverF": _field(spec, "hoverF", 1), "hoverA": _field(spec, "hoverA", 1),
		"surge": _field(spec, "surge", 0), "flare": _field(spec, "flare", 0), "bank": _field(spec, "bank", 1)}

static func gun_pitch(poses: BodyPose, pivot: Variant, aiming: float, kick: float, charge: float, heavy: Dictionary) -> void:
	if not pivot is Dictionary:
		return
	var angle: float = float(pivot.rest) + (float(pivot.aim) - float(pivot.rest)) * aiming - kick * 0.14 + charge * _field(heavy, "gun", 0.05) * aiming
	poses.set_axis(pivot.g, "x", angle)

static func stabilize_head(poses: BodyPose, owner: Dictionary, accumulated: Array, idle_amount: float, now: float, strength: float = 0.85, scan: float = 1.0) -> void:
	var head: Node3D = owner.get("head")
	if head == null:
		return
	var neck: Node3D = owner.get("neck")
	var share := 0.45 if neck != null else 0.0
	if neck != null:
		poses.set_rotation(neck, [-float(accumulated[0]) * strength * share, -float(accumulated[1]) * strength * share, -float(accumulated[2]) * strength * share])
	poses.set_rotation(head, [-float(accumulated[0]) * strength * (1 - share),
		-float(accumulated[1]) * strength * (1 - share) + idle_amount * sin(now * 0.5) * 0.28 * scan,
		-float(accumulated[2]) * strength * (1 - share)])

static func whip_tail(poses: BodyPose, segments: Array, state: Dictionary, delta: float, amplitude: float, idle_amount: float,
		now: float, yaw_rate: float, base: float = 0.0, aim: Variant = null, curl: Variant = null, stiffness: float = 1.0, sway: Variant = null) -> void:
	state.tail = BodyMotionState.damp(_field(state, "tail", 0), clampf(-yaw_rate * 0.3, -0.55, 0.55), 3.5, delta)
	var pointing := clampf(or_number(aim, "p", 0), 0, 1) if aim is Dictionary else 0.0
	for index in range(segments.size()):
		var node: Node3D = segments[index]
		if sway is Dictionary:
			var phase: float = now * TAU * float(sway.frequency) - index * float(sway.delay)
			poses.set_axis(node, "y", float(state.tail) * (1 + index * 0.15) / segments.size() + sin(phase) * (float(sway.idle) + float(sway.travel) * amplitude))
			poses.set_axis(node, "x", (float(sway.pitch) if index == 0 else 0.0) + sin(phase - 0.8) * float(sway.pitchWave))
			continue
		var delay := index * 0.6
		var lag := 1 + index * 0.35
		poses.set_axis(node, "y", (float(state.tail) * lag * (1 - pointing) + sin(float(state.ph) - delay) * 0.1 * amplitude
			+ idle_amount * sin(now * 1.1 - delay) * 0.045) * stiffness)
		var angle := base if index == 0 else 0.0
		if curl is Dictionary:
			angle += (float(curl.rot0) + index * float(curl.rotD)) * (1 - pointing)
		if pointing != 0:
			angle += pointing * (float(aim.rot0) + index * float(aim.rotD))
		angle += (sin(float(state.ph) * 2 - delay) * 0.07 * amplitude + idle_amount * sin(now * 1.1 - delay) * 0.03) * (1 - pointing) * stiffness
		poses.set_axis(node, "x", angle)
