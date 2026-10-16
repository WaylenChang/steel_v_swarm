class_name BodyReferenceMotion
extends RefCounted

const Joint = preload("res://scripts/body_gait_joints.gd")

static func step(poses: BodyPose, rig: Dictionary, entity: Dictionary, delta: float, now: float, apply_shield: bool = true) -> void:
	if not Joint.flag(rig, "referenceMotion") or not is_finite(delta) or delta <= 0 or not is_finite(now):
		return
	var motion: Dictionary = rig.referenceMotion
	var kick := maxf(Joint.or_number(rig, "_kickL", 0), maxf(Joint.or_number(rig, "_kickR", 0), Joint.or_number(rig, "_kickB", 0)))
	var event: Variant = entity.get("castFx")
	var slot: Variant = event.get("slot") if event is Dictionary else null
	var combat: Dictionary = rig.combat if rig.get("combat") is Dictionary else {}
	var duration: float = combat.get("clips", {}).get(slot, {}).get("duration", Content.balance.bodyRules.cast.duration.atk if slot == "atk" else Content.balance.bodyRules.cast.duration.other)
	var age := (now - Joint._field(event, "t0", NAN)) / duration if event is Dictionary else -1.0
	var casting := age >= 0 and age < 1
	var cast := pow(sin(PI * age), 2) if casting else 0.0
	var defending: bool = Joint.flag(entity, "visualDefense") if Joint.flag(entity, "isSelf") else Joint.flag(entity, "df") and (entity.get("sp") == null or float(entity.sp) > 0)
	rig._bowAim = clampf(Joint.or_number(rig, "_fireAim", 0), 0, 1) if Joint.flag(rig, "archery") and rig.get("_aimSlot") == "light" and not casting and not defending and not Joint.flag(entity, "dead") else 0.0
	for key: String in ["fire", "charge", "cast"]:
		var weight: float = kick if key == "fire" else maxf(0, Joint.or_number(rig, "_chg", 0)) if key == "charge" else cast
		for track: Dictionary in motion[key]:
			var pulse: float = maxf(0, maxf(Joint.or_number(rig, "_chg", 0), Joint.or_number(rig, "_aimH", 0))) if track.get("trigger") == "heavy" else weight
			var emitters: Array = track.get("emitters", []) if key == "fire" else []
			if not emitters.is_empty():
				pulse = 0.0
				for emitter: Dictionary in emitters:
					var elapsed := now - float(emitter.entry.firedAt)
					if elapsed >= 0 and is_finite(elapsed):
						pulse = maxf(pulse, BodyMotionState.friction(7, elapsed) * (1.0 if emitter.slot == "heavy" else 0.45))
			var alternating: Dictionary = rig.alternating if rig.get("alternating") is Dictionary else {}
			var active: bool = not emitters.is_empty() or track.get("barrel") == null or track.barrel == alternating.get("index")
			poses.set_channel(track.node, track.channel, track.axis, float(track.rest) + float(track.amplitude) * (pulse if active else 0.0))
	if Joint.flag(rig, "launcher"):
		poses.set_rotation(rig.launcher.pivot, [0.0, 0.0, 0.0])
		poses.set_channel(rig.launcher.lift, "scale", "y", 1)
		var spread := clampf(Joint.or_number(rig, "_aimH", 0), 0, 1)
		for pod: Dictionary in rig.launcher.get("pods", []):
			poses.set_position_axis(pod.node, "x", float(pod.rest) + (float(pod.deploy) - float(pod.rest)) * spread)
	if Joint.flag(motion, "fireSpin"):
		var spinner: Dictionary = motion.fireSpin
		poses.set_axis(spinner.node, spinner.axis, fmod(poses.axis(spinner.node, spinner.axis) + delta * float(spinner.rate) * maxf(kick, Joint.or_number(rig, "_fireAim", 0)), TAU))
	authored(poses, rig, entity, now)
	if not Joint.flag(rig, "shield"):
		return
	var shield: Dictionary = rig.shield
	var target := not Joint.flag(entity, "dead") and (defending or (Joint.flag(rig, "combat") and slot == "def" and casting))
	var value := clampf(phase(shield) + (1.0 if target else -1.0) * delta / float(shield.duration), 0, 1)
	if Joint.flag(entity, "dead") and Joint.flag(rig, "combat"):
		value = 0
	shield.phase = value
	shield.expand = Joint.flag(entity, "visualShieldExpand") if Joint.flag(entity, "isSelf") else entity.get("df") == 2
	if Joint.flag(shield, "state"):
		shield.state.phase = value
		shield.state.expand = shield.expand
	if apply_shield:
		pose_shield(poses, shield, Joint._field(shield, "posture", 1))
	if Joint.flag(shield, "combat") and shield.barrier.visible:
		ShieldPresentation.step(shield.material, delta)

static func phase(shield: Dictionary) -> float:
	return float(shield.state.phase) if Joint.flag(shield, "state") else float(shield.phase)

static func reset_shield(poses: BodyPose, shield: Variant) -> void:
	if not shield is Dictionary:
		return
	for track: Dictionary in shield.get("pose", []):
		poses.set_quaternion(track.node, track.rest)

static func reset(poses: BodyPose, rig: Dictionary) -> void:
	if not Joint.flag(rig, "referenceMotion"):
		return
	for key: String in ["fire", "charge", "cast"]:
		for track: Dictionary in rig.referenceMotion[key]:
			poses.set_channel(track.node, track.channel, track.axis, track.rest)

static func pose_shield(poses: BodyPose, shield: Variant, posture: float = 1.0) -> void:
	if not shield is Dictionary:
		return
	var progress := phase(shield)
	var weight := progress * progress * (3 - 2 * progress)
	for hinge: Dictionary in shield.hinges:
		poses.set_axis(hinge.node, hinge.axis, float(hinge.rest) + (float(hinge.deploy) - float(hinge.rest)) * weight)
	if Joint.flag(shield, "arm"):
		for key: String in ["shoulder", "elbow", "wrist"]:
			var current := poses.axis(shield.arm[key], "x")
			poses.set_axis(shield.arm[key], "x", current + (float(shield.arm[key + "X"]) - current) * weight)
	if weight * posture > 0:
		for track: Dictionary in shield.get("pose", []):
			poses.set_quaternion(track.node, SourceQuaternion.slerp(track.rest, track.deploy, weight * posture))
	var projection := clampf((weight - 0.18) / 0.82, 0, 1)
	shield.barrier.visible = projection > 0
	var size := maxf(0.001, projection)
	var expanded: bool = Joint.flag(shield.state, "expand") if Joint.flag(shield, "state") and shield.state.get("expand") != null else Joint.flag(shield, "expand")
	poses.set_scale(shield.barrier, Vector3(size * (float(Content.balance.bodyRules.shield.expand) if expanded else 1.0), size, size))
	if Joint.flag(shield, "combat"):
		poses.set_position(shield.barrier, BodyPose.vector(shield.combat.shield.center))

static func authored(poses: BodyPose, rig: Dictionary, entity: Dictionary, now: float) -> void:
	if not Joint.flag(rig, "combat") or not is_finite(now):
		return
	var combat: Dictionary = rig.combat
	for joint: Array in combat.joints:
		if joint[0] == combat.shield.node:
			continue
		var node: Node3D = combat.nodes[joint[0]]
		node.visible = false
		poses.set_scale(node, Vector3.ONE * 0.001)
		poses.set_position(node, BodyPose.vector(joint[2]))
		poses.set_rotation(node, [0.0, 0.0, 0.0])
	if Joint.flag(entity, "dead"):
		return
	for slot: String in combat.clips:
		var event: Variant = entity.get("fireFx" if slot in ["light", "heavy"] else "castFx")
		if not event is Dictionary or event.get("slot") != slot or not _finite_number(event.get("t0")):
			continue
		var clip: Dictionary = combat.clips[slot]
		var time := (now - float(event.t0) - Joint.or_number(rig.get("fireLead", {}), slot, 0)) / float(clip.duration)
		if time < 0 or time >= 1:
			continue
		for track: Dictionary in clip.tracks:
			if track.node in combat.get("transported", []):
				continue
			poses.set_channel(track.target, track.channel, track.axis, sample_keys(track.keys, time))
			track.target.visible = true
	var charge := clampf(Joint.or_number(rig, "_chg", 0), 0, 1)
	if charge > 0:
		for name: String in combat.get("charging", []):
			var node: Node3D = combat.nodes[name]
			node.visible = true
			poses.set_scale(node, Vector3(1, 0.45 + 0.55 * charge, 0.45 + 0.55 * charge))

static func clear_shield(poses: BodyPose, rig: Dictionary) -> void:
	if not Joint.flag(rig, "combat"):
		return
	var combat: Dictionary = rig.combat
	if combat.hull.is_empty() or not combat.guard.visible or not combat.group.visible:
		return
	var inverse: Transform3D = combat.group.global_transform.affine_inverse()
	var front := -INF
	for part: Dictionary in combat.hull:
		var local: Transform3D = inverse * part.node.global_transform
		var center: Vector3 = part.center
		var half: Vector3 = part.half
		front = maxf(front, float(local.basis.x.z) * float(center.x) + float(local.basis.y.z) * float(center.y) + float(local.basis.z.z) * float(center.z) + float(local.origin.z)
			+ absf(local.basis.x.z) * float(half.x) + absf(local.basis.y.z) * float(half.y) + absf(local.basis.z.z) * float(half.z))
	poses.set_position_axis(combat.guard, "z", maxf(float(combat.shield.center[2]), front + float(combat.shield.clearance)))

static func sample_keys(keys: Array, time: float) -> float:
	if time <= float(keys[0][0]):
		return float(keys[0][1])
	for index in range(1, keys.size()):
		if time > float(keys[index][0]):
			continue
		var previous: Array = keys[index - 1]
		var current: Array = keys[index]
		return float(previous[1]) + (float(current[1]) - float(previous[1])) * (time - float(previous[0])) / (float(current[0]) - float(previous[0]))
	return float(keys.back()[1])

static func _finite_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))
