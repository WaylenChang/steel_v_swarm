class_name BodyCastPose
extends RefCounted

const Joint = preload("res://scripts/body_gait_joints.gd")

static func drive(phase: float) -> float:
	if phase >= 1:
		return 0.0
	if phase < 0.3:
		return -0.6 * sin(phase / 0.3 * PI / 2)
	var progress := (phase - 0.3) / 0.7
	return sin(minf(1, progress * 2.4) * PI) * (1 - 0.5 * progress)

static func step(poses: BodyPose, state: Dictionary, rig: Dictionary, entity: Dictionary, now: float) -> void:
	if not Joint.flag(entity, "castFx"):
		return
	var event: Dictionary = entity.castFx
	var rules: Dictionary = Content.balance.bodyRules.cast
	var attack: bool = event.get("slot") == "atk"
	var combat: Dictionary = rig.combat if rig.get("combat") is Dictionary else {}
	var clips: Dictionary = combat.clips if combat.get("clips") is Dictionary else {}
	var clip: Dictionary = clips.get(event.get("slot"), {})
	var duration := Joint._field(clip, "duration", rules.duration.atk if attack else rules.duration.other)
	var phase := (now - float(event.t0)) / duration
	if phase >= 1 or phase < 0:
		entity.castFx = null
		return
	var signature: Dictionary = rig.castSig if Joint.flag(rig, "castSig") else rules.defaults.get(rig.kind, rules.defaults.biped)
	var directional := Joint.flag(event, "dir")
	var signature_key := "dir" if directional else "omni"
	var archetype: String = signature[signature_key] if Joint.flag(signature, signature_key) else "jab" if directional else "stomp"
	var gain := 1.0 if attack else 0.7
	var envelope := sin(minf(1, phase * 1.15) * PI) * gain
	var movement := drive(phase)
	var lift := maxf(0, -movement) * gain
	var hit := maxf(0, movement) * gain
	var air: bool = rig.kind == "morph" and Joint._field(state, "morph", 0) > 0.5
	match archetype:
		"roar":
			_rotate(poses, rig, "head", "x", -0.55 * envelope)
			_rotate(poses, rig, "neck", "x", -0.35 * envelope)
			_rotate(poses, rig, "chest", "x", -0.2 * envelope)
			_rotate(poses, rig, "hips", "x", -0.08 * envelope)
			_rotate(poses, rig, "spine", "x", -0.14 * envelope)
			if not air:
				_rotate(poses, rig, "torso", "x", -0.16 * envelope)
				if rig.kind != "quad":
					_rotate(poses, rig, "armL", "x", -0.55 * envelope)
					_rotate(poses, rig, "armR", "x", -0.55 * envelope)
			if Joint.flag(rig, "trunk"):
				_rotate(poses, rig, "trunk", "x", -0.8 * envelope)
				_rotate(poses, rig, "trunkTip", "x", -0.5 * envelope)
			if Joint.flag(rig, "tailSegs") and not Joint.flag(rig, "cephalopod"):
				for index in range(rig.tailSegs.size()):
					Joint.add(poses, rig.tailSegs[index], "x", 0.08 * envelope * (1 + index * 0.25))
		"stomp":
			if rig.kind == "quad":
				_rotate(poses, rig, "spine", "x", -0.3 * lift + 0.1 * hit)
				if Joint.flag(rig, "insectLegs"):
					for leg: Dictionary in rig.insectLegs:
						if leg.key == "FL":
							Joint.add(poses, leg.lift, "z", float(leg.side) * (0.95 * lift + 0.15 * hit))
						if leg.key == "FR":
							Joint.add(poses, leg.lift, "z", float(leg.side) * (0.75 * lift + 0.1 * hit))
				else:
					_rotate(poses, rig, "legFL", "x", -(0.95 * lift + 0.15 * hit))
					_rotate(poses, rig, "legFR", "x", -(0.75 * lift + 0.1 * hit))
				_rotate(poses, rig, "neck", "x", 0.22 * lift)
				Joint.lower(poses, rig.get("spine"), 0.14 * hit)
			else:
				_rotate(poses, rig, "legR", "x", -1.05 * lift)
				_first(poses, rig, "legChainR", 0.9 * lift)
				_rotate(poses, rig, "kneeR", "x", 0.7 * lift)
				_rotate(poses, rig, "hips", "x", 0.1 * hit - 0.06 * lift)
				_rotate(poses, rig, "torso", "x", 0.0 if air else 0.1 * hit - 0.06 * lift)
				_rotate(poses, rig, "chest", "x", 0.1 * hit)
				Joint.lower(poses, rig.get("hips"), 0.16 * hit)
				if not air:
					Joint.lower(poses, rig.get("torso"), 0.12 * hit)
		"dance":
			var sway := sin(phase * PI * 4) * envelope
			_rotate(poses, rig, "hips", "y", sway * 0.35)
			_rotate(poses, rig, "spine", "y", sway * 0.22)
			if not air:
				_rotate(poses, rig, "torso", "y", sway * 0.3)
			_rotate(poses, rig, "chest", "y", -sway * 0.25)
			_rotate(poses, rig, "head", "y", sway * 0.2)
			_rotate(poses, rig, "head", "x", -absf(sin(phase * PI * 8)) * 0.05 * envelope)
			if not air:
				_rotate(poses, rig, "armL", "x", (-0.55 - sway * 0.45) * envelope)
				_rotate(poses, rig, "armR", "x", (-0.55 + sway * 0.45) * envelope)
			Joint.lower(poses, rig.get("hips"), absf(sway) * 0.05)
			if Joint.flag(rig, "tents"):
				for index in range(rig.tents.size()):
					for link in range(rig.tents[index].size()):
						Joint.add(poses, rig.tents[index][link].g, "x", sin(phase * PI * 4 - link * 0.5 + index * 1.6) * 0.25 * envelope)
		"spin":
			var angle := phase * phase * (3 - 2 * phase) * TAU
			if rig.kind == "aerial":
				_rotate(poses, rig, "tilt", "z", angle)
			elif air:
				_rotate(poses, rig, "torso", "z", angle)
			else:
				for key: String in ["hips", "spine", "torso"]:
					_rotate(poses, rig, key, "y", angle)
				if rig.kind != "quad":
					_rotate(poses, rig, "armL", "x", -0.5 * envelope)
					_rotate(poses, rig, "armR", "x", -0.5 * envelope)
		"tailwhip":
			var sway := sin(minf(1, phase * 1.2) * TAU) * gain
			if Joint.flag(rig, "tailSegs"):
				for index in range(rig.tailSegs.size()):
					Joint.add(poses, rig.tailSegs[index], "y", sin(minf(1, maxf(0, phase * 1.2 - index * 0.06)) * TAU) * gain * (0.5 + index * 0.35))
			_rotate(poses, rig, "spine", "y", -sway * 0.28)
			_rotate(poses, rig, "hips", "y", -sway * 0.3)
			if not air:
				_rotate(poses, rig, "torso", "y", -sway * 0.3)
			_rotate(poses, rig, "head", "y", sway * 0.2)
		"beat":
			var beat := sin(phase * PI * 10) * envelope
			_rotate(poses, rig, "armL", "x", (-1.05 - beat * 0.3) * envelope)
			_rotate(poses, rig, "armR", "x", (-1.05 + beat * 0.3) * envelope)
			_first(poses, rig, "armChainL", -(0.9 + beat * 0.3) * envelope)
			_first(poses, rig, "armChainR", -(0.9 - beat * 0.3) * envelope)
			_rotate(poses, rig, "chest", "x", -0.18 * envelope)
			_rotate(poses, rig, "head", "x", -0.3 * envelope)
			Joint.lower(poses, rig.get("hips"), absf(beat) * 0.03)
		"flare":
			for pair: Array in [["wings", 0.65, 0.5], ["flapWings", 0.6, 0.45]]:
				if not Joint.flag(rig, pair[0]):
					continue
				for wing: Dictionary in rig[pair[0]]:
					Joint.add(poses, wing.w, "z", float(wing.sgn) * float(pair[1]) * envelope)
					Joint.add(poses, wing.outer, "z", float(wing.sgn) * float(pair[2]) * envelope)
			_rotate(poses, rig, "tilt", "x", -0.28 * envelope)
			if air:
				_rotate(poses, rig, "torso", "x", -0.2 * envelope)
		"swing":
			_rotate(poses, rig, "armR", "x", 0.9 * lift - 1.5 * hit)
			_first(poses, rig, "armChainR", -(0.5 * lift - 0.3 * hit))
			_rotate(poses, rig, "elbowR", "x", -(0.5 * lift - 0.3 * hit))
			_rotate(poses, rig, "hips", "y", 0.25 * lift - 0.4 * hit)
			_rotate(poses, rig, "chest", "y", 0.2 * lift - 0.3 * hit)
			if not air:
				_rotate(poses, rig, "torso", "y", 0.22 * lift - 0.35 * hit)
			_rotate(poses, rig, "chest", "x", -0.1 * lift + 0.2 * hit)
			if Joint.flag(rig, "trunk"):
				_rotate(poses, rig, "trunk", "x", -0.7 * lift + 0.9 * hit)
				_rotate(poses, rig, "trunkTip", "x", -0.5 * lift + 0.6 * hit)
			if rig.kind == "quad":
				_rotate(poses, rig, "spine", "x", -0.12 * lift + 0.1 * hit)
				if Joint.flag(rig, "tents"):
					for chain: Array in rig.tents:
						for index in range(chain.size()):
							Joint.add(poses, chain[index].g, "x", (0.5 * lift - 0.7 * hit) * (0.4 + index * 0.25))
		"jab":
			if rig.kind == "quad" or (Joint.flag(rig, "tinyArms") and not Joint.flag(rig, "armR")):
				_rotate(poses, rig, "spine", "x", -0.1 * lift + 0.16 * hit)
				_rotate(poses, rig, "neck", "x", -0.3 * lift + 0.5 * hit)
				_rotate(poses, rig, "head", "x", -0.2 * lift + 0.3 * hit)
				Joint.lower(poses, rig.get("spine"), 0.1 * hit)
			else:
				_rotate(poses, rig, "armR", "x", 0.5 * lift - 1.45 * hit)
				_first(poses, rig, "armChainR", -(0.8 * lift - 0.15 * hit))
				_rotate(poses, rig, "elbowR", "x", -(0.8 * lift - 0.15 * hit))
				_rotate(poses, rig, "chest", "x", -0.08 * lift + 0.14 * hit)
				_rotate(poses, rig, "chest", "y", 0.18 * lift - 0.3 * hit)
				_rotate(poses, rig, "hips", "y", 0.12 * lift - 0.22 * hit)
				if not air:
					_rotate(poses, rig, "torso", "y", 0.15 * lift - 0.25 * hit)
				if Joint.flag(rig, "tinyArms"):
					_rotate(poses, rig, "neck", "x", -0.25 * lift + 0.45 * hit)
					_rotate(poses, rig, "head", "x", -0.15 * lift + 0.25 * hit)
		"kick":
			_rotate(poses, rig, "legR", "x", 0.5 * lift - 1.5 * hit)
			_first(poses, rig, "legChainR", 0.9 * lift - 0.2 * hit)
			_rotate(poses, rig, "kneeR", "x", 0.9 * lift - 0.2 * hit)
			_rotate(poses, rig, "hips", "x", -0.12 * lift + 0.18 * hit)
			_rotate(poses, rig, "chest", "x", 0.1 * lift - 0.15 * hit)
			if not air:
				_rotate(poses, rig, "torso", "x", -0.1 * lift + 0.15 * hit)
			Joint.lower(poses, rig.get("hips"), 0.08 * hit)
			if Joint.flag(rig, "tailSegs"):
				for index in range(rig.tailSegs.size()):
					Joint.add(poses, rig.tailSegs[index], "x", (0.15 * hit - 0.08 * lift) * (1 + index * 0.2))
		"lunge":
			_rotate(poses, rig, "tilt", "x", -0.2 * lift + 0.4 * hit)
			Joint.lower(poses, rig.get("tilt"), 0.25 * hit)
			if air or rig.kind == "morph":
				_rotate(poses, rig, "torso", "x", -0.15 * lift + 0.3 * hit)
			if Joint.flag(rig, "wings"):
				for wing: Dictionary in rig.wings:
					Joint.add(poses, wing.w, "z", float(wing.sgn) * 0.3 * lift)

static func _rotate(poses: BodyPose, rig: Dictionary, key: String, axis: String, value: float) -> void:
	Joint.add(poses, rig.get(key), axis, value)

static func _first(poses: BodyPose, rig: Dictionary, key: String, value: float) -> void:
	var chain: Variant = rig.get(key)
	if chain is Array and not chain.is_empty():
		Joint.add(poses, chain[0].g, "x", value)
