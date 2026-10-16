class_name TargetingMath
extends RefCounted

static func foe(side: String, target_side: String, neutral: bool = false) -> bool:
	return not target_side.is_empty() and target_side != side and not neutral and not (side == Content.constants.SUPER_SIDE and Content.constants.THIRD.SIDES.has(target_side))

static func view_roster(position: Vector3, frame: Transform3D, projection: Projection, viewport: Vector2,
		candidates: Array, reach: float, keep_id: int, scoped: bool, scope_radius: float, obstruction: Callable = Callable()) -> Array:
	var result: Array = []
	var inverse := frame.affine_inverse()
	var canvas := Vector2(1 if viewport.x == 0 else viewport.x, 1 if viewport.y == 0 else viewport.y)
	var rules: Dictionary = Content.balance.view
	var order := 0
	for candidate: Dictionary in candidates:
		var index := order
		order += 1
		if not candidate.get("eligible", true):
			continue
		var point: Vector3 = candidate.point
		if position.distance_to(point) > reach:
			continue
		var local := inverse * point
		if local.z > -float(rules.near):
			continue
		var clip := projection * Vector4(local.x, local.y, local.z, 1)
		if clip.w == 0:
			continue
		var ndc := Vector2(clip.x, clip.y) / clip.w
		var off := Vector2(ndc.x * canvas.x, ndc.y * canvas.y).length() * 0.5 / maxf(1, scope_radius) if scoped else maxf(absf(ndc.x), absf(ndc.y))
		var limit: float = Content.constants.VIEW_LOCK.DROP if int(candidate.id) == keep_id else Content.constants.VIEW_LOCK.EDGE
		if not off <= limit:
			continue
		var cut: float = obstruction.call(frame.origin, point) if obstruction.is_valid() else candidate.get("obstruction", INF)
		if cut < frame.origin.distance_to(point) - float(Content.balance.targeting.obstructionTolerance):
			continue
		result.append({"id": int(candidate.id), "off": off, "x": ndc.x, "order": index})
	# Source JS sorting is stable; equal horizontal positions preserve map order.
	result.sort_custom(func(a, b): return a.order < b.order if a.x == b.x else a.x < b.x)
	return result

static func view_choice(roster: Array, keep_id: int) -> int:
	var best := {}
	for candidate: Dictionary in roster:
		if int(candidate.id) == keep_id:
			return keep_id
		if best.is_empty() or float(candidate.off) < float(best.off) or candidate.off == best.off and int(candidate.order) < int(best.order):
			best = candidate
	return int(best.id) if not best.is_empty() else 0

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
