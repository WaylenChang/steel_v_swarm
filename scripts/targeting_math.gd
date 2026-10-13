class_name TargetingMath
extends RefCounted

# Preserve source acquisition independently of physical hit-volume and lock lifecycle queries.
static func cone_acquire(position: Vector3, eye: Vector3, forward: Vector3, reach: float,
		candidates: Array, keep_id: int = 0) -> int:
	var limit: float = Content.balance.targeting.coneAngle
	var best := 0
	var best_angle := INF
	for candidate: Dictionary in candidates:
		if not candidate.hero or not candidate.get("eligible", true):
			continue
		var point: Vector3 = candidate.point
		var body_x := float(point.x) - position.x
		var body_y := float(point.y) - position.y
		var body_z := float(point.z) - position.z
		if sqrt(body_x * body_x + body_y * body_y + body_z * body_z) > reach:
			continue
		var x := float(point.x) - eye.x
		var y := float(point.y) - eye.y
		var z := float(point.z) - eye.z
		var length := sqrt(x * x + y * y + z * z)
		var direction_length := sqrt(float(forward.x) * forward.x + float(forward.y) * forward.y + float(forward.z) * forward.z)
		var angle := PI / 2 if length * direction_length == 0 else acos(clampf(
			(x * forward.x + y * forward.y + z * forward.z) / (length * direction_length), -1, 1))
		if angle > limit or candidate.get("obstruction", INF) < length - Content.balance.targeting.obstructionTolerance:
			continue
		if int(candidate.id) == keep_id:
			return keep_id
		if angle < best_angle:
			best_angle = angle
			best = int(candidate.id)
	return best

static func launch_range(definition: Dictionary, position: Vector3, eye: Vector3, surface: float, target: Dictionary = {}) -> float:
	if target.is_empty():
		return definition.range
	var gap: float
	if target.hero:
		gap = eye.y - target.position.y - Content.constants.LOS.EYE_M
	else:
		var target_height: float = Content.constants.LOS.TOWER_EYE_M if target.kind in ["tower", "base"] else target.altitude + Content.constants.LOS.EYE_M if target.kind in ["heli", "decoy", "kami", "hyper"] else target.altitude + Content.constants.LOS.TGT_M
		gap = position.y - surface + Content.constants.LOS.EYE_M - target_height
	return definition.range * CombatMath.altitude_range(definition, gap)

static func maximum_range(definition: Dictionary) -> float:
	var heavy: bool = definition.get("id", definition.get("slot", "")) in ["heavy", "atk", "ult"]
	return definition.range * (1 + Content.constants.ALTITUDE.RANGE * (Content.constants.ALTITUDE.RANGE_HEAVY_MUL if heavy else 1.0))

static func lock_candidate(primary: Dictionary, flights: Array, keep_index: int) -> Dictionary:
	if not primary.is_empty() and primary.distance <= primary.reach:
		return {"id": primary.id, "index": keep_index}
	var candidates: Array[int] = []
	for flight: Dictionary in flights:
		if flight.distance <= flight.reach and not candidates.has(int(flight.id)):
			candidates.append(int(flight.id))
	if candidates.is_empty():
		return {"id": 0, "index": keep_index}
	var next := (keep_index + 1) % candidates.size()
	return {"id": candidates[next], "index": next}

static func aim_choice(position: Vector3, reach: float, precise: Dictionary, cone: int, lob: Dictionary = {}) -> int:
	if lob.get("on", false):
		return int(lob.get("target", 0)) if lob.get("ok", false) else 0
	if not precise.is_empty() and position.distance_to(precise.point) <= reach:
		return int(precise.id)
	return cone
