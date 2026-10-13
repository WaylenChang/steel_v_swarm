class_name LobFireControl
extends RefCounted

# Native collision supplies the source solver's geometry seams. No combat state is changed here.
static func friendly_impact(definition: Dictionary, origin: Vector3, impact: Vector3) -> bool:
	var x := float(impact.x) - origin.x
	var z := float(impact.z) - origin.z
	return definition.trajectory == "lob" and sqrt(x * x + z * z) < definition.r * Content.constants.BALLISTIC.LOB_MIN_F

static func solve(origin: Vector3, aim: Vector3, speed: float) -> Dictionary:
	var x := float(aim.x) - origin.x
	var z := float(aim.z) - origin.z
	var length := sqrt(x * x + z * z)
	if length == 0:
		length = 0.001
	var height := float(aim.y) - origin.y
	var gravity: float = Content.constants.BALLISTIC.G
	var squared := speed * speed
	var discriminant := squared * squared - gravity * (gravity * length * length + 2 * height * squared)
	if discriminant < 0:
		return {"ok": false, "lo": 1.0, "hi": 1.0, "length": length, "x": x, "z": z}
	var root := sqrt(discriminant)
	return {"ok": true, "lo": (squared - root) / (gravity * length),
		"hi": (squared + root) / (gravity * length), "length": length, "x": x, "z": z}

static func velocity(origin: Vector3, aim: Vector3, speed: float) -> Vector3:
	var solution := solve(origin, aim, speed)
	var tangent: float = solution.lo
	var horizontal := speed / sqrt(1 + tangent * tangent)
	return Vector3(solution.x / solution.length * horizontal, horizontal * tangent, solution.z / solution.length * horizontal)

static func velocity_45(origin: Vector3, aim: Vector3, maximum_speed: float) -> Dictionary:
	var x := float(aim.x) - origin.x
	var z := float(aim.z) - origin.z
	var length := sqrt(x * x + z * z)
	var height := float(aim.y) - origin.y
	if length <= maxf(height, 0.001):
		return {}
	var speed := sqrt(Content.constants.BALLISTIC.G * length * length / (length - height))
	if speed > maximum_speed:
		return {}
	var component := speed / sqrt(2)
	return {"velocity": Vector3(x / length * component, component, z / length * component)}

static func trace(origin: Vector3, initial_velocity: Vector3, reach: float, aim: Vector3, collision: Callable) -> Dictionary:
	var points := PackedVector3Array([origin])
	var point := origin
	var motion := initial_velocity
	var step := minf(0.03, 3 / maxf(1, initial_velocity.length()))
	var aim_distance := maxf(0.001, origin.distance_to(aim))
	var axis := (aim - origin) / aim_distance
	var nearest := aim_distance
	var impact := Vector3.ZERO
	var reason := ""
	var has_impact := false
	for index in range(int(Content.balance.projectilePreview.maxPoints) - 1):
		var previous := point
		motion.y -= Content.constants.BALLISTIC.G * step
		point += motion * step
		var hit: Dictionary = collision.call(previous, point)
		if not hit.is_empty():
			point = hit.position
		points.append(point)
		nearest = minf(nearest, point.distance_to(aim))
		var projection := (point - origin).dot(axis)
		var spent := point.distance_to(origin)
		if not hit.is_empty() or spent >= reach or projection >= aim_distance:
			impact = point
			has_impact = true
			reason = "block" if not hit.is_empty() else "range" if spent >= reach else "pass"
			break
	return {"points": points, "impact": impact, "has_impact": has_impact, "minimum_distance": nearest, "cut": reason}

static func ladder(origin: Vector3, aim: Vector3, reach: float, base_speed: float, anti_air: bool, collision: Callable,
		tolerance: float = NAN, best_effort: bool = true) -> Dictionary:
	if not is_finite(tolerance):
		tolerance = Content.constants.BALLISTIC.LOB_TOL
	if not anti_air:
		var fixed := velocity_45(origin, aim, base_speed)
		if not fixed.is_empty():
			var arc := trace(origin, fixed.velocity, reach, aim, collision)
			return {"ok": arc.minimum_distance <= tolerance, "speed": fixed.velocity.length(),
				"velocity": fixed.velocity, "arc": arc, "high": false}
	var result := {"ok": false, "speed": base_speed, "velocity": Vector3.ZERO, "arc": {}, "high": false}
	var charges: Array = Content.constants.BALLISTIC.LOB_CHARGE
	for index in range(charges.size()):
		var speed: float = base_speed * charges[index]
		if not solve(origin, aim, speed).ok:
			break
		var motion := velocity(origin, aim, speed)
		var arc := trace(origin, motion, reach, aim, collision)
		result = {"ok": arc.minimum_distance <= tolerance, "speed": speed,
			"velocity": motion, "arc": arc, "high": index > 0}
		if result.ok or arc.cut != "block":
			break
	if result.arc.is_empty() and best_effort:
		# Source still fires its best-effort low solution when no charge can reach the point.
		result.velocity = velocity(origin, aim, base_speed)
		result.arc = trace(origin, result.velocity, reach, aim, collision)
	return result

static func prepare(definition: Dictionary, origin: Vector3, requested_aim: Vector3, reach: float,
		anti_air: bool, ground: Callable, collision: Callable) -> Dictionary:
	var aim := requested_aim
	var cut := false
	var minimum_range: float = definition.r * Content.constants.BALLISTIC.LOB_MIN_F
	if not anti_air:
		var limit := maxf(1, reach - minf(definition.projectile.core, reach * 0.5))
		var horizontal := Vector2(aim.x - origin.x, aim.z - origin.z)
		var length := horizontal.length()
		if origin.distance_to(aim) > reach or length > CombatMath.max_horizontal(reach, aim.y - origin.y):
			var distance := minf(length, limit)
			if length > 0:
				var direction := horizontal / length
				for iteration in range(3):
					var height: float = ground.call(origin.x + direction.x * distance, origin.z + direction.y * distance)
					if not is_finite(height):
						return {}
					distance = minf(length, maxf(1, CombatMath.max_horizontal(limit, height - origin.y)))
				var point := Vector3(origin.x + direction.x * distance, 0, origin.z + direction.y * distance)
				point.y = ground.call(point.x, point.z)
				if not is_finite(point.y):
					return {}
				if origin.distance_to(point) >= minimum_range:
					aim = point
					cut = true
	var speed: float = definition.projectile.antiAirSpeed if anti_air else definition.projectile.speed
	var result := ladder(origin, aim, reach, speed, anti_air, collision)
	result.ok = result.ok and not cut
	result.aim = aim
	result.range = reach
	result.aa = anti_air
	result.clamped = cut
	result.close = minimum_range > 0 and origin.distance_to(result.arc.impact if result.arc.has_impact else aim) < minimum_range
	return result
