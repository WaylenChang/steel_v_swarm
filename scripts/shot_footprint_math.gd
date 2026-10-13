class_name ShotFootprintMath
extends RefCounted

# Source client advisory geometry. These lists never settle damage or spend combat resources.
static func eligible(target: Dictionary) -> bool:
	return target.get("foe", true) and target.get("visible", true) and not target.get("self", false) and not target.get("dead", false) and not target.get("garrison", false)

static func centre(target: Dictionary) -> Vector3:
	return target.position + Vector3.UP * (target.get("top", target.height) - target.height / 2)

static func in_shot_range(definition: Dictionary, origin: Vector3, target: Dictionary, collision: Callable) -> bool:
	var aim := centre(target)
	var surface := maxf(0, origin.distance_to(aim) - target.radius)
	var limit: float = target.reach * (Content.constants.FAN_RANGE_CENTER_F if definition.area == "fan" else 1.0)
	if surface > limit:
		return false
	var hit: Dictionary = collision.call(origin, aim)
	return hit.is_empty() or origin.distance_to(hit.position) >= surface - Content.balance.reachability.SURF_TOL_M

static func evaluate(definition: Dictionary, origin: Vector3, forward: Vector3, targets: Array,
		crosshair: Dictionary, control: Dictionary, collision: Callable) -> Dictionary:
	var impact: Vector3 = crosshair.point
	var exact := {}
	for target: Dictionary in targets:
		if int(target.id) == int(crosshair.get("target", 0)) and eligible(target):
			exact = target
			break
	var warning := false
	if control.get("on", false):
		if not control.ok:
			return {}
		impact = control.impact if control.has_impact else control.aim
		warning = control.close
	elif definition.area not in ["fan", "line"]:
		if not exact.is_empty():
			# Source _reachable reuses _rgAim, overwriting _shotVictims' reticle impact with this centre.
			impact = centre(exact)
			var advice := ReachabilityMath.evaluate(definition, origin, exact, exact.reach, collision)
			if not advice.ok:
				return {}
			warning = advice.warn
		else:
			if definition.area != "blast" or origin.distance_to(impact) > definition.range:
				return {}
			var arm: float = definition.projectile.arm.get("m", 0) if definition.reachRule.arm and definition.projectile.arm is Dictionary else 0.0
			var minimum: float = definition.r * Content.constants.BALLISTIC.LOB_MIN_F if definition.trajectory == "lob" else 0.0
			var distance := origin.distance_to(impact)
			warning = (arm > 0 and distance < arm) or (minimum > 0 and distance < minimum)
	var hits: Array[int] = []
	match definition.area:
		"blast":
			for target: Dictionary in targets:
				if not eligible(target):
					continue
				var horizontal := maxf(0, Vector2(impact.x - target.position.x, impact.z - target.position.z).length() - target.radius)
				var top: float = target.position.y + target.get("top", target.height)
				var bottom: float = top - target.height
				var vertical := maxf(0, maxf(bottom - impact.y, impact.y - top))
				if CombatMath.blast_falloff(definition.r, sqrt(horizontal * horizontal + vertical * vertical)) > 0:
					hits.append(int(target.id))
		"fan":
			hits = fan_victims(definition, origin, forward, targets, collision)
		"line":
			var previous := 0
			for entry: Dictionary in lance_pierced(definition, origin, impact, targets):
				var target: Dictionary = entry.target
				if not eligible(target) or not in_shot_range(definition, origin, target, collision) or int(target.id) == previous:
					continue
				previous = int(target.id)
				hits.append(previous)
		_:
			if not exact.is_empty():
				hits.append(int(exact.id))
	return {} if hits.is_empty() else {"hits": hits, "warn": warning}

static func fan_victims(definition: Dictionary, origin: Vector3, forward: Vector3, targets: Array, collision: Callable) -> Array[int]:
	var horizontal := sqrt(float(forward.x) * forward.x + float(forward.z) * forward.z)
	if horizontal == 0:
		horizontal = 1.0
	var axis_x := float(forward.x) / horizontal
	var axis_z := float(forward.z) / horizontal
	var count := int(definition.fanSubs)
	var bins: Array = []
	bins.resize(count)
	var half: float = deg_to_rad(definition.arc)
	var width := half * 2 / count
	for target: Dictionary in targets:
		if not eligible(target):
			continue
		var x := float(target.position.x) - origin.x
		var z := float(target.position.z) - origin.z
		var planar := sqrt(x * x + z * z)
		var top: float = target.position.y + target.get("top", target.height)
		var y := clampf(origin.y + forward.y / horizontal * planar, top - target.height, top) - origin.y
		var distance := sqrt(x * x + y * y + z * z)
		var dot := (x * forward.x + y * forward.y + z * forward.z) / (distance if distance > 0 else 1.0)
		if dot <= 0:
			continue
		if distance > 8 and acos(clampf(dot, -1, 1)) > half + atan2(target.radius, maxf(1, distance)):
			continue
		if not in_shot_range(definition, origin, target, collision):
			continue
		var angle := atan2(x * axis_z - z * axis_x, x * axis_x + z * axis_z)
		var angular_radius := atan2(target.radius, maxf(1, planar))
		var first := clampi(floori((angle - angular_radius) / width + count / 2.0), 0, count - 1)
		var last := clampi(floori((angle + angular_radius) / width + count / 2.0), 0, count - 1)
		var surface := maxf(0, origin.distance_to(centre(target)) - target.radius)
		var horizontal_surface := maxf(0, planar - target.radius)
		for bin in range(first, last + 1):
			var near := CombatMath.fan_bin_distance(definition, bin, planar, angle, target.radius)
			if near < 0 or surface + near - horizontal_surface > target.reach * definition.fanRangeFactors[bin]:
				continue
			if bins[bin] == null or distance < bins[bin].distance:
				bins[bin] = {"id": int(target.id), "distance": distance}
	var hits: Array[int] = []
	var previous := 0
	for win: Variant in bins:
		if win == null or int(win.id) == previous:
			continue
		previous = int(win.id)
		hits.append(previous)
	return hits

static func lance_pierced(definition: Dictionary, origin: Vector3, endpoint: Vector3, targets: Array) -> Array:
	var dx := float(endpoint.x) - origin.x
	var dy := float(endpoint.y) - origin.y
	var dz := float(endpoint.z) - origin.z
	var length := sqrt(dx * dx + dy * dy + dz * dz)
	if length == 0:
		length = 1.0
	dx /= length
	dy /= length
	dz /= length
	var vertical := absf(dy) > 0.99
	var ex := 0.0 if vertical else -dz
	var ey := dz if vertical else 0.0
	var ez := -dy if vertical else dx
	var magnitude := sqrt(ex * ex + ey * ey + ez * ez)
	if magnitude > 0:
		ex /= magnitude
		ey /= magnitude
		ez /= magnitude
	var fx := dy * ez - dz * ey
	var fy := dz * ex - dx * ez
	var fz := dx * ey - dy * ex
	var candidates: Array = []
	for target: Dictionary in targets:
		if target.get("self", false) or target.get("ally", false) or not target.get("visible", true):
			continue
		var x := float(target.position.x) - origin.x
		var y := float(target.position.y) - origin.y
		var z := float(target.position.z) - origin.z
		var along := x * dx + y * dy + z * dz
		var projected := clampf(along, 0, length)
		x -= dx * projected
		y -= dy * projected
		z -= dz * projected
		var distance := sqrt(x * x + y * y + z * z)
		var radius: float = definition.lanceRadius + target.radius
		if distance > radius:
			continue
		var section := Vector2(x * ex + y * ey + z * ez, x * fx + y * fy + z * fz)
		for zone in CombatMath.lance_zones(section, target.radius, definition.lanceRadius):
			candidates.append({"target": target, "along": along, "zone": zone, "order": candidates.size()})
	candidates.sort_custom(func(a, b):
		if a.along != b.along:
			return a.along < b.along
		return a.zone < b.zone if a.zone != b.zone else a.order < b.order)
	var budgets := {}
	var shut := {}
	var kept: Array = []
	for entry: Dictionary in candidates:
		var zone: int = entry.zone
		if shut.has(zone):
			continue
		if not budgets.has(zone):
			budgets[zone] = definition.lancePen * (3.0 if zone == 0 else 1.0) / 9
		var radius: float = entry.target.radius
		budgets[zone] -= entry.target.get("penetration_cost", PI * radius * radius)
		kept.append(entry)
		if budgets[zone] < 0:
			shut[zone] = true
	return kept
