class_name ReachabilityMath
extends RefCounted

# Advisory source geometry; damage and launch eligibility remain on the authority.
static func evaluate(definition: Dictionary, origin: Vector3, target: Dictionary, reach: float,
		collision: Callable) -> Dictionary:
	var rejected := {"ok": false, "warn": false}
	if not origin.is_finite() or not target.position.is_finite() or not is_finite(reach) or reach <= 0:
		return rejected
	var rule: Dictionary = definition.reachRule
	var aim: Vector3 = target.position + Vector3.UP * (target.get("top", target.height) - target.height / 2)
	var radius: float = target.radius
	var offset := aim - origin
	if rule.path == "arc" and not CombatMath.in_range(reach, offset, radius):
		return rejected
	var full := sqrt(float(offset.x) * offset.x + float(offset.y) * offset.y + float(offset.z) * offset.z)
	var surface := maxf(0, full - radius)
	if surface > reach:
		return rejected
	if rule.hit == "blast":
		var tolerance: float = definition.projectile.core + radius
		var miss := 0.0
		if rule.path == "arc":
			var anti_air := CombatMath.target_class(target.kind) == "air"
			var speed: float = definition.projectile.antiAirSpeed if anti_air else definition.projectile.speed
			var solution := LobFireControl.ladder(origin, aim, reach, speed, anti_air, collision, tolerance, false)
			if solution.arc.is_empty():
				return rejected
			miss = solution.arc.minimum_distance
		else:
			var hit: Dictionary = collision.call(origin, aim)
			if not hit.is_empty():
				miss = maxf(0, full - origin.distance_to(hit.position))
		if miss > tolerance:
			return rejected
		var minimum: float = definition.r * Content.constants.BALLISTIC.LOB_MIN_F if definition.trajectory == "lob" else 0.0
		var arm: float = definition.projectile.arm.get("m", 0) if rule.arm and definition.projectile.arm is Dictionary else 0.0
		return {"ok": true, "warn": (minimum > 0 and surface < minimum) or (arm > 0 and surface < arm)}
	var hit: Dictionary = collision.call(origin, aim)
	return {"ok": hit.is_empty() or origin.distance_to(hit.position) >= surface - Content.balance.reachability.SURF_TOL_M,
		"warn": false}
