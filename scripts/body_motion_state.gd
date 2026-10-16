class_name BodyMotionState
extends RefCounted

var values: Dictionary = {}
var kinematics: Dictionary = {}
var source_identity := ""
var configured := false

static func phase_of(source_id: String) -> float:
	var rules: Dictionary = Content.balance.bodyRules.locomotion
	return float(hash_of(source_id) % int(rules.phaseModulus)) / float(rules.phaseDivisor)

static func hash_of(source_id: String) -> int:
	var rules: Dictionary = Content.balance.bodyRules.locomotion
	var value: int = rules.phaseSeed
	for index in range(source_id.length()):
		var code := source_id.unicode_at(index)
		if code > 0xffff:
			var pair := code - 0x10000
			value = ((value ^ (0xd800 + (pair >> 10))) * int(rules.phasePrime)) & 0xffffffff
			code = 0xdc00 + (pair & 0x3ff)
		value = ((value ^ code) * int(rules.phasePrime)) & 0xffffffff
	return value

func configure(source_id: String) -> void:
	source_identity = source_id
	configured = true
	values.clear()
	kinematics.clear()

func advance(position: Vector3, yaw: float, previous: Vector3, previous_yaw: float, delta: float) -> bool:
	var rules: Dictionary = Content.balance.bodyRules.locomotion
	if delta < float(rules.minimumStep):
		return false
	assert(configured, "Configure the original source identity before body motion")
	if values.is_empty():
		values = {"vx": 0.0, "vz": 0.0, "speed": 0.0, "accel": 0.0, "roll": 0.0, "pitch": 0.0,
			"amp": 0.0, "lean": 0.0, "ts": 0.0, "ph": phase_of(source_identity)}
	values.vx = damp(values.vx, (float(position.x) - previous.x) / delta, rules.velocityRate, delta)
	values.vz = damp(values.vz, (float(position.z) - previous.z) / delta, rules.velocityRate, delta)
	var speed := sqrt(float(values.vx) * float(values.vx) + float(values.vz) * float(values.vz))
	values.accel = damp(values.accel, (speed - float(values.speed)) / delta, rules.accelerationRate, delta)
	values.speed = speed
	var difference := yaw - previous_yaw
	kinematics = {"speed": speed, "yaw_rate": atan2(sin(difference), cos(difference)) / delta,
		"forward": float(values.vx) * sin(yaw) + float(values.vz) * cos(yaw),
		"lateral": float(values.vx) * cos(yaw) - float(values.vz) * sin(yaw)}
	return true

func walk_rate(delta: float, reference: float = 0.0) -> float:
	var rules: Dictionary = Content.balance.bodyRules.locomotion
	var speed: float = values.speed
	var denominator: float = rules.walkReference if reference == 0 or is_nan(reference) else reference
	var wanted := 0.0 if speed < float(rules.walkMinimumSpeed) else clampf(speed / denominator, float(rules.walkMinimumRate), float(rules.walkMaximumRate))
	values.ts = damp(values.ts, wanted, rules.walkRate, delta)
	return values.ts

static func damp(current: float, target: float, rate: float, delta: float) -> float:
	return current + (target - current) * (1 - friction(rate, delta))

static func friction(rate: float, delta: float) -> float:
	return exp(-maxf(0, rate) * maxf(0, delta))

static func _finite(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func _first(candidates: Array) -> float:
	for value: Variant in candidates:
		if _finite(value):
			return float(value)
	return 0.0

static func weights(state: Variant = null, owner: Variant = null, options: Variant = null) -> Dictionary:
	var motion: Dictionary = state if state is Dictionary else {}
	var rig: Dictionary = owner if owner is Dictionary else {}
	var opts: Dictionary = options if options is Dictionary else {}
	var rules: Dictionary = Content.balance.bodyRules.locomotion.weights
	var top := _first([opts.get("top"), rig.get("top")])
	var amplitude := float(motion.amp) if _finite(motion.get("amp")) else _first([motion.get("speed")]) / top if top > 0 else 0.0
	amplitude = clampf(amplitude, 0, 1)
	var run_share := clampf((amplitude - float(rules.RUN_LO)) / (float(rules.RUN_HI) - float(rules.RUN_LO)), 0, 1)
	var run := amplitude * run_share
	var ground := _first([opts.get("groundY")])
	var altitude := _first([opts.get("y")])
	var air: float
	if ControlPreferences.truthy(opts.get("flies")):
		air = 1
	elif ground > 0:
		air = clampf((altitude - ground * (1 - float(rules.AIR_BAND_F))) / (ground * 2 * float(rules.AIR_BAND_F)), 0, 1)
	else:
		air = 1.0 if altitude > 0 else 0.0
	var raw := {"idle": 1 - amplitude, "walk": amplitude - run, "run": run, "air": air,
		"land": clampf(_first([motion.get("landK")]), 0, 1), "aim": clampf(_first([opts.get("aim"), rig.get("_aim")]), 0, 1),
		"charge": clampf(absf(_first([opts.get("charge"), rig.get("_chg"), motion.get("act")])), 0, 1),
		"morph": clampf(_first([motion.get("morph")]), 0, 1), "surge": clampf(_first([motion.get("srg")]), 0, 1),
		"brake": clampf(_first([motion.get("brk")]), 0, 1)}
	var result: Dictionary = {}
	for key: String in rules.keyOrder:
		result[key] = _first([raw.get(key)])
	return result
