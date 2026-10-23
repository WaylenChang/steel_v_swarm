class_name BotRules
extends RefCounted

static func tactic_cross(tactics: Dictionary) -> void:
	var gap := float(Content.constants.BOT_LEARN.GAP)
	tactics.W_THREAT = maxf(float(tactics.W_THREAT), maxf(float(tactics.W_OUTPUT), float(tactics.W_EXEC)) + gap)
	tactics.KITE_FAR = minf(1, maxf(float(tactics.KITE_FAR), float(tactics.KITE_NEAR) + gap))
	tactics.KITE_NEAR = minf(float(tactics.KITE_NEAR), float(tactics.KITE_FAR) - gap)
	tactics.PULL_HP = maxf(float(tactics.PULL_HP), float(tactics.BASE_HP) + gap)

static func wrap_pi(angle: float) -> float:
	while angle > PI:
		angle -= TAU
	while angle < -PI:
		angle += TAU
	return angle

static func fov_half(kind: String, vertical: bool = false) -> float:
	var half := deg_to_rad(float(Content.constants.UNITS.get(kind, {}).get("fov", 68))) / 2
	return half if vertical else atan(tan(half) * float(Content.constants.BOT_VIEW.ASPECT))

static func threat_decay(age: float, tactics: Dictionary) -> float:
	return maxf(0, 1 - maxf(0, age) / float(tactics.THREAT_S))

static func threat_key(unit: BattleUnit) -> String:
	return "pilot:%d" % unit.peer_id if unit.is_hero() else "entity:%d" % unit.entity_id

static func salvo(definition: Dictionary, kind: String, tactics: Dictionary) -> float:
	return float(definition.dmg) * CombatMath.vs_multiplier(definition, kind) * float(definition.rate) * float(tactics.EXEC_S)

static func execution_weight(health: float, maximum: float, burst: float) -> float:
	if burst > 0 and health <= burst:
		return float(Content.constants.BOT_TACTIC.EXEC_MAX)
	return maxf(0, 1 - health / maximum) if maximum > 0 else 0.0

static func priority(threat: float, output: float, execution: float, tactics: Dictionary) -> float:
	return 1 + float(tactics.W_THREAT) * threat + float(tactics.W_OUTPUT) * output + float(tactics.W_EXEC) * execution

static func blood_uv(bearing: float, elevation: float, half_h: float, half_v: float) -> Vector2:
	var edge: float = Content.constants.BLOOD.EDGE
	return Vector2(edge + (0.5 + 0.5 * clampf(bearing / half_h if half_h > 0 else 0, -1, 1)) * (1 - 2 * edge),
		edge + (0.5 - 0.5 * clampf(elevation / half_v if half_v > 0 else 0, -1, 1)) * (1 - 2 * edge))

static func blood_direction(uv: Vector2, half_h: float, half_v: float) -> Vector2:
	var edge: float = Content.constants.BLOOD.EDGE
	var denominator := 1 - 2 * edge
	var u := (float(uv.x) - edge) / denominator if denominator > 0 else 0.5
	var v := (float(uv.y) - edge) / denominator if denominator > 0 else 0.5
	return Vector2(clampf((u - 0.5) * 2, -1, 1) * (half_h if half_h else 1.0),
		clampf((0.5 - v) * 2, -1, 1) * (half_v if half_v else 1.0))

static func project_lane(points: Array, distances: Array, x: float, z: float) -> float:
	var best := INF
	var progress := 0.0
	for index in range(1, points.size()):
		var ax: float = points[index - 1][0]
		var az: float = points[index - 1][1]
		var dx: float = float(points[index][0]) - ax
		var dz: float = float(points[index][1]) - az
		var length := dx * dx + dz * dz
		if length == 0:
			length = 1.0
		var fraction := clampf(((x - ax) * dx + (z - az) * dz) / length, 0, 1)
		var ex := x - (ax + dx * fraction)
		var ez := z - (az + dz * fraction)
		var squared := ex * ex + ez * ez
		if squared < best:
			best = squared
			progress = float(distances[index - 1]) + (float(distances[index]) - float(distances[index - 1])) * fraction
	return progress
