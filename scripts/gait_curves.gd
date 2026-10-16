class_name GaitCurves
extends RefCounted

static func cycle(phase: float) -> float:
	var value := (phase + PI / 2) / TAU
	return value - floor(value)

static func duty(key: String, gallop: float = 0.0) -> float:
	var rules: Dictionary = Content.balance.bodyRules.gait
	var base: float = rules.duties.get(key, rules.duties.trot)
	return clampf(base + (float(rules.duties.gallop) - base) * clampf(gallop, 0, 1), float(rules.dutyMin), float(rules.dutyMax))

static func _duty(value: float) -> float:
	var epsilon: float = Content.balance.bodyRules.gait.dutyEpsilon
	return epsilon if value <= 0 else 1 - epsilon if value >= 1 else value

static func hip(cycle_position: float, support: float) -> float:
	var length := _duty(support)
	if cycle_position >= length:
		var swing := (cycle_position - length) / (1 - length)
		return 1 - 2 * (0.5 - 0.5 * cos(PI * swing))
	var position := cycle_position / length
	var edge: float = Content.balance.bodyRules.gait.hipEase
	var integral: float
	if position <= edge:
		integral = position * position / (2 * edge)
	elif position < 1 - edge:
		integral = edge / 2 + (position - edge)
	else:
		var remaining := 1 - position
		integral = 1 - edge - remaining * remaining / (2 * edge)
	return -1 + 2 * clampf(integral / (1 - edge), 0, 1)

static func table(knots: Array, position: float) -> float:
	assert(not knots.is_empty(), "Missing original gait curve knots")
	var value := clampf(position, 0, 1)
	for index in range(1, knots.size()):
		if value <= float(knots[index][0]):
			var first: Array = knots[index - 1]
			var second: Array = knots[index]
			var span := float(second[0]) - float(first[0])
			var fraction := 0.0 if span <= 0 else (value - float(first[0])) / span
			var eased := fraction * fraction * (3 - 2 * fraction)
			return float(first[1]) + (float(second[1]) - float(first[1])) * eased
	return knots[-1][1]

static func _curves(role: String) -> Array:
	var rules: Dictionary = Content.balance.bodyRules.gait.curves
	return rules.get(role, rules.hind)

static func _phase(curve: Dictionary, cycle_position: float, support: float) -> float:
	var length := _duty(support)
	return table(curve.st, cycle_position / length) if cycle_position < length else table(curve.sw, (cycle_position - length) / (1 - length))

static func joint(role: String, index: int, cycle_position: float, support: float) -> float:
	var curves := _curves(role)
	var value := _phase(curves[clampi(index, 0, curves.size() - 1)], cycle_position, support)
	return value * pow(float(Content.balance.bodyRules.gait.distalGain), index - curves.size() + 1) if index >= curves.size() else value

static func rest(role: String, index: int) -> float:
	var curves := _curves(role)
	return table(curves[clampi(index, 0, curves.size() - 1)].st, 0.5)

static func profile(specification: Variant = null) -> Dictionary:
	var spec: Dictionary = specification if specification is Dictionary else {}
	var postures: Dictionary = Content.balance.bodyRules.gait.postures
	var result: Dictionary = {}
	for side: String in ["fore", "hind"]:
		var role: String = spec.get(side + "Role", "") if spec.get(side + "Role") != null else ""
		if role.is_empty():
			role = side
		var posture: String = spec.get(side, "") if spec.get(side) != null else ""
		if posture.is_empty():
			posture = role if postures.has(role) else "digitigrade"
		var source: Dictionary = postures.get(posture, postures.digitigrade)
		var reach: Array = []
		for value: float in source.reach:
			reach.append(value * _factor(spec, "reachF"))
		result[side] = {"role": role, "posture": posture, "reach": reach,
			"lock": float(source.lock) * _factor(spec, "lockF"), "bounce": float(source.bounce) * _factor(spec, "bounceF")}
	return result

static func _factor(spec: Dictionary, key: String) -> float:
	return 1.0 if spec.get(key) == null else float(spec[key])

static func limb(profile_data: Dictionary, index: int, cycle_position: float, support: float, amplitude: float) -> float:
	var raw := joint(profile_data.role, index, cycle_position, support)
	var reach: float = profile_data.reach[clampi(index, 0, profile_data.reach.size() - 1)]
	var locked: float = profile_data.lock if cycle_position < support and index >= 1 else 0.0
	var standing := rest(profile_data.role, index)
	var value := raw * (1 - locked) + standing * locked
	return (value - standing) * clampf(amplitude, 0, 1) * reach * float(Content.balance.bodyRules.gait.flexGain)

static func bounce(phase: float, support: float, asymmetric: float = 0.0) -> float:
	var midpoint := -PI / 2 + _duty(support) * PI
	var symmetric := 0.5 + 0.5 * cos((phase - midpoint) * 2)
	var single := 0.5 + 0.5 * cos(phase - midpoint)
	return symmetric + (single - symmetric) * clampf(asymmetric, 0, 1)

static func human(cycle_position: float, support: float) -> Dictionary:
	var rules: Dictionary = Content.balance.bodyRules.gait
	return {"hip": _phase(rules.humanHip, cycle_position, support), "arm": _phase(rules.humanArm, cycle_position, support)}
