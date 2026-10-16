class_name BodyCombatFx
extends RefCounted

const Joint = preload("res://scripts/body_gait_joints.gd")

static func step(body: BodyRig, entity: Dictionary, now: float, delta: float) -> void:
	if body == null or not body.forms.has(body.form) or delta <= 0:
		return
	var rig: Dictionary = body.forms[body.form]
	unit_motion(body.poses, rig, now)
	if not Joint.flag(entity, "cfx"):
		entity.cfx = {"aim": 0.0, "hA": 0.0, "kL": 0.0, "kR": 0.0, "kB": 0.0, "chg": 0.0,
			"lg": 0.0, "fireT": -1.0, "aimUntil": -1.0, "hUntil": -1.0}
	var state: Dictionary = entity.cfx
	var rules: Dictionary = Content.balance.bodyRules.combat
	var event: Variant = entity.get("fireFx")
	if Joint.flag(entity, "fireFx") and not is_same(event, state.get("fireEvent")):
		state.fireEvent = event
		state.fireT = float(event.t0)
		state.slot = event.slot if Joint.flag(event, "slot") else "light"
		var fired := body.fire(event)
		state.aimUntil = maxf(state.aimUntil, float(event.t0) + float(rules.AIM_HOLD_S))
		if event.get("slot") == "heavy":
			state.hUntil = maxf(Joint._field(state, "hUntil", -1), float(event.t0) + float(rules.AIM_HOLD_S))
		var amplitudes: Dictionary = rig.kickAmp if Joint.flag(rig, "kickAmp") else {}
		var amplitude := (1.0 if event.get("slot") == "heavy" else 0.45) * Joint._field(amplitudes, str(event.get("slot", "undefined")), 1)
		var weapons: Dictionary = rig.weap if Joint.flag(rig, "weap") else {}
		var hand: Variant = fired.get("side")
		if not ControlPreferences.truthy(hand):
			hand = weapons.get(event.get("slot"))
		if not ControlPreferences.truthy(hand):
			hand = "R"
		if hand in ["L", "B"]:
			state.kL = minf(1.3, float(state.kL) + amplitude)
		if hand in ["R", "B"]:
			state.kR = minf(1.3, float(state.kR) + amplitude)
		if hand == "N":
			state.kB = minf(1.3, Joint.or_number(state, "kB", 0) + amplitude)
		if event.get("slot") != "heavy":
			state.lg = 1.0
	var charge_target := 0.0
	var glow_target := 0.0
	var heavy: Variant = entity.get("heavyFx")
	if Joint.flag(entity, "heavyFx"):
		state.slot = "heavy"
		var elapsed := now - float(heavy.t0)
		if heavy.get("phase") == "charge":
			charge_target = minf(1, elapsed / float(rules.HEAVY_CHARGE_ASSUME_S))
			glow_target = charge_target
			state.aimUntil = maxf(state.aimUntil, now + 0.4)
			state.hUntil = maxf(Joint._field(state, "hUntil", -1), now + 0.4)
		elif elapsed <= float(rules.HEAVY_FIRE_HOLD_S):
			charge_target = -1
			glow_target = 2
		else:
			entity.heavyFx = null
	var response := 1 - BodyMotionState.friction(rules.FX_K, delta)
	state.chg += (charge_target - float(state.chg)) * response
	var aiming: bool = now < float(state.aimUntil)
	state.aim = BodyMotionState.damp(state.aim, 1.0 if aiming else 0.0, 9.0 if aiming else 3.5, delta)
	var heavy_aiming := now < Joint._field(state, "hUntil", -1)
	state.hA = BodyMotionState.damp(Joint.or_number(state, "hA", 0), 1.0 if heavy_aiming else 0.0, 6.0 if heavy_aiming else 3.0, delta)
	state.kL = BodyMotionState.damp(state.kL, 0, 7, delta)
	state.kR = BodyMotionState.damp(state.kR, 0, 7, delta)
	state.kB = BodyMotionState.damp(Joint.or_number(state, "kB", 0), 0, 7, delta)
	state.lg = BodyMotionState.damp(state.lg, 0, 10, delta)
	rig._aim = state.aim
	rig._aimH = state.hA
	rig._kickL = state.kL
	rig._kickR = state.kR
	rig._kickB = state.kB
	rig._chg = state.chg
	rig._fireAim = state.aim
	rig._aimSlot = state.slot if Joint.flag(state, "slot") else "light"
	rig._fireAge = maxf(0, now - float(state.fireT)) if float(state.fireT) >= 0 else INF
	var leads: Dictionary = rig.fireLead if rig.get("fireLead") is Dictionary else {}
	var lead: Variant = leads.get(state.get("slot"))
	if ControlPreferences.truthy(lead):
		state.lg = BodyMotionState.friction(10, float(rig._fireAge) - float(lead)) if float(rig._fireAge) >= float(lead) else 0.0
	if Joint.flag(rig, "heavy"):
		for glow: Dictionary in rig.heavy.glow:
			var target: float = float(glow.base) * (1 + glow_target * 1.6 if glow_target <= 1 else 2.6 + (glow_target - 1) * 3)
			var material := BodyMaterials.standard(glow.mesh)
			var intensity := BodyMaterials.emission(material)
			BodyMaterials.set_emission(material, intensity + (target - intensity) * response)
		var factor: float = state.chg if float(state.chg) >= 0 else float(state.chg) * 0.85
		for pivot: Dictionary in rig.heavy.pivot:
			for axis: String in ["x", "y", "z"]:
				var rest := _component(pivot.rest, axis)
				var target := rest + (_component(pivot.deploy, axis) - rest) * factor
				body.poses.add_axis(pivot.obj, axis, (target - body.poses.axis(pivot.obj, axis)) * response)
	if Joint.flag(rig, "lightGlow"):
		for glow: Dictionary in rig.lightGlow:
			BodyMaterials.set_emission(BodyMaterials.standard(glow.mesh), float(glow.base) + float(state.lg) * 3.2)
	if Joint.flag(rig, "blink"):
		for blink: Dictionary in rig.blink:
			var material := BodyMaterials.standard(blink.mesh)
			if blink.get("base") == null:
				blink.base = BodyMaterials.emission(material)
			var wave := 0.5 + 0.5 * sin(now * Joint.or_number(blink, "f", 4) + Joint.or_number(blink, "ph", 0))
			var low := Joint._field(blink, "lo", 0.18)
			BodyMaterials.set_emission(material, float(blink.base) * (low + (1 - low) * wave * wave * wave))
	if Joint.flag(rig, "flames"):
		var heavy_flame := 1.0 if glow_target > 1 else -float(state.chg) if float(state.chg) < -0.18 else 0.0
		for flame: Node3D in rig.flames.light:
			flame.visible = float(state.lg) > 0.22
			var size := 0.7 + float(state.lg) * 0.9 + sin(now * 87) * 0.16 if flame.visible else 0.01
			body.poses.set_scale(flame, Vector3.ONE * size)
		for flame: Node3D in rig.flames.heavy:
			flame.visible = heavy_flame > 0
			var size := 0.7 + heavy_flame * 1.1 + sin(now * 63) * 0.18 if flame.visible else 0.01
			body.poses.set_scale(flame, Vector3.ONE * size)

static func unit_motion(poses: BodyPose, rig: Dictionary, now: float) -> void:
	if not is_finite(now):
		return
	for mechanism: Dictionary in _tracks(rig, "mechanisms"):
		_channel(poses, mechanism, float(mechanism.rest) + sin(now * float(mechanism.frequency) + float(mechanism.phase)) * float(mechanism.amplitude))
	for attack: Dictionary in _tracks(rig, "attacks"):
		var age := now - float(attack.firedAt)
		var kick := 0.0
		if age >= 0 and age < 0.55:
			kick = age / 0.035 if age < 0.035 else pow(1 - (age - 0.035) / 0.515, 3)
		poses.set_position_axis(attack.node, "z", -float(attack.travel) * kick)
		poses.set_axis(attack.node, "x", -float(attack.lift) * kick)
		for mechanism: Dictionary in _tracks(attack, "cycle"):
			var progress := 0.0 if age < 0 or age >= 0.55 else pow(sin(PI * minf(1, age / 0.55)), 2)
			_channel(poses, mechanism, float(mechanism.rest) + float(mechanism.amplitude) * progress)

static func fire_unit_motion(rig: Dictionary, muzzle: Node3D, now: float) -> void:
	if not is_finite(now):
		return
	for attack: Dictionary in _tracks(rig, "attacks"):
		if muzzle in attack.muzzles:
			attack.firedAt = now
			return

static func _channel(poses: BodyPose, track: Dictionary, value: float) -> void:
	poses.set_channel(track.node, track.channel, track.axis, value)

static func _tracks(spec: Dictionary, key: String) -> Array:
	return spec[key] if Joint.flag(spec, key) else []

static func _component(value: Variant, axis: String) -> float:
	if value is Vector3:
		return value[WeaponPresentation.axis_index(axis)]
	assert(value is Dictionary, "Unsupported source combat pivot vector")
	if value.get("angles") is Vector3:
		return value.angles[WeaponPresentation.axis_index(axis)]
	return float(value[axis])
