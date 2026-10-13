class_name CombatMath
extends RefCounted

# Game-specific settlement cannot be replaced by the engine's physics solver.
static func armor_multiplier(armor: float, penetration: float = 0.0) -> float:
	var effective := maxf(0.0, armor - penetration)
	return 1.0 - effective / (effective + Content.constants.VITALS.AR_K)

static func shield_split(definition: Dictionary, damage: float, shield: float) -> Dictionary:
	var shield_multiplier: float = definition.get("vsSp", 1.0)
	var hp_multiplier: float = definition.get("vsHp", 1.0)
	var pierced: float = damage * definition.get("spPierce", 0.0)
	var budget := damage - pierced
	var spent := minf(budget, maxf(0.0, shield) / shield_multiplier) if shield_multiplier > 0 else budget
	return {"toSp": spent * shield_multiplier, "toHp": (pierced + budget - spent) * hp_multiplier}

static func damage_falloff(definition: Dictionary, distance: float) -> float:
	var c: Dictionary = Content.constants
	if definition.get("fan", false):
		var reach: float = definition.get("range", 0)
		return maxf(c.FAN_FLOOR, c.FAN_MUZZLE * (1.0 - distance / reach)) if reach > 0 else 1.0
	var floor_value: float = c.FALLOFF.FLOOR.get(definition.type, 0)
	if floor_value == 0:
		return 1.0
	var delta: float = distance - definition.get("range", 0) * c.FALLOFF.PLATEAU
	if delta <= 0:
		return 1.0
	var kinetic: bool = definition.type in ["gun", "rail"]
	var length_scale: float = definition.get("mv", 600) * c.FALLOFF.KIN_L if kinetic else c.FALLOFF.EXT[definition.type]
	return maxf(floor_value, exp(-(2.0 if kinetic else 1.0) * delta / length_scale))

static func blast_falloff(radius: float, distance: float) -> float:
	var bands: Dictionary = Content.constants.BLAST
	if distance <= radius * bands.CORE:
		return 1.0
	if radius <= 0 or distance >= radius * bands.EDGE:
		return 0.0
	return pow((radius * bands.EDGE - distance) / (radius * (bands.EDGE - bands.CORE)), bands.EXP)

static func max_horizontal(reach: float, height: float) -> float:
	var c: Dictionary = Content.constants
	if reach <= 0:
		return 0.0
	var transition: float = reach * c.WEAPON_TRANS_Y_F
	if height >= transition:
		var radius: float = reach * c.WEAPON_SPHERE_R_F
		return 0.0 if height >= radius else sqrt(radius * radius - height * height)
	return maxf(0.0, reach - height / c.SQRT3)

static func in_range(reach: float, delta: Vector3, radius: float = 0.0) -> bool:
	if reach <= 0 or delta.y > reach * Content.constants.WEAPON_SPHERE_R_F:
		return false
	return maxf(0.0, Vector2(delta.x, delta.z).length() - radius) <= max_horizontal(reach, delta.y)

static func direct_in_range(reach: float, delta: Vector3, radius: float) -> bool:
	return maxf(0, delta.length() - radius) <= reach or (delta.y < 0 and in_range(reach, delta, radius))

static func target_class(kind: String) -> String:
	return Content.constants.TARGET_CLASS.get(kind, "armor")

static func vs_multiplier(definition: Dictionary, kind: String) -> float:
	var factor: float = definition.get("vs", {}).get(target_class(kind), 1.0)
	return minf(1.0, factor) if target_class(kind) == "building" else factor

static func view_lock_step(difference: float, delta: float) -> float:
	var lock: Dictionary = Content.constants.VIEW_LOCK
	return clampf(difference * minf(1.0, lock.EASE * delta), -lock.W * delta, lock.W * delta)

static func fan_bin_distance(definition: Dictionary, bin: int, distance: float, angle: float, radius: float) -> float:
	if not is_finite(distance) or not is_finite(angle):
		return -1.0
	radius = maxf(0.0, radius)
	if distance <= 0:
		return 0.0
	var half_arc := deg_to_rad(definition.get("arc", 15))
	var width: float = half_arc * 2 / definition.fanSubs
	var low := -half_arc + bin * width
	var high := low + width
	if angle >= low and angle <= high:
		return maxf(0.0, distance - radius)
	var edge := low if angle < low else high
	var offset := angle - edge
	var lateral := distance * sin(offset)
	if absf(lateral) > radius:
		return -1.0
	return maxf(0.0, distance * cos(offset) - sqrt(radius * radius - lateral * lateral))

static func fan_hits(definition: Dictionary, origin: Vector3, direction: Vector3, targets: Array) -> Array:
	var count := int(definition.fanSubs)
	var bins: Array = []
	bins.resize(count)
	var axis := Vector2(direction.x, direction.z)
	# Scalar intermediates avoid amplifying Vector3 float32 rounding through acos.
	var horizontal_axis := sqrt(float(direction.x) * direction.x + float(direction.z) * direction.z)
	var magnitude := sqrt(horizontal_axis * horizontal_axis + float(direction.y) * direction.y)
	if magnitude <= 0:
		return []
	var half_arc := deg_to_rad(definition.get("arc", 15))
	var width := half_arc * 2 / count
	for target: Dictionary in targets:
		var offset: Vector3 = target.position - origin
		var flat := Vector2(offset.x, offset.z)
		var horizontal := sqrt(float(offset.x) * offset.x + float(offset.z) * offset.z)
		var ray_y := origin.y + direction.y / (horizontal_axis if horizontal_axis > 0 else 1.0) * horizontal
		var nearest_y := clampf(ray_y, target.position.y, target.position.y + target.height)
		var vertical := nearest_y - origin.y
		var distance := sqrt(horizontal * horizontal + vertical * vertical)
		var surface := maxf(0, distance - target.radius)
		var reach: float = definition.range * target.get("range_factor", 1.0)
		if surface > reach * Content.constants.FAN_RANGE_CENTER_F:
			continue
		var dot := (float(offset.x) * direction.x + vertical * direction.y + float(offset.z) * direction.z) / ((distance if distance > 0 else 1.0) * magnitude)
		if dot <= 0:
			continue
		var angle := acos(clampf(dot, -1, 1)) if distance > 8 else 0.0
		if distance > 8 and angle > half_arc + atan2(maxf(0, target.radius), maxf(1, distance)):
			continue
		var phi := axis.angle_to(flat) if axis.length_squared() > 0 else 0.0
		var angular_radius := atan2(target.radius, maxf(1, horizontal))
		var first := clampi(floori((phi - angular_radius) / width + count / 2.0), 0, count - 1)
		var last := clampi(floori((phi + angular_radius) / width + count / 2.0), 0, count - 1)
		var horizontal_surface := maxf(0, horizontal - target.radius)
		for bin in range(first, last + 1):
			var near := fan_bin_distance(definition, bin, horizontal, phi, target.radius)
			if near < 0 or surface + near - horizontal_surface > reach * definition.fanRangeFactors[bin]:
				continue
			# Strict replacement preserves source insertion order on equal distances.
			if bins[bin] == null or distance < bins[bin].distance:
				bins[bin] = {"target": target, "distance": distance, "angle": angle, "bin": bin}
	var wins := bins.filter(func(win): return win != null)
	wins.sort_custom(func(a, b): return a.angle < b.angle if a.angle != b.angle else a.bin < b.bin)
	var building_hits := {}
	var hits: Array = []
	for win in wins:
		var target: Dictionary = win.target
		if target_class(target.kind) == "building":
			var used := int(building_hits.get(target.id, 0))
			if used >= int(definition.fanMaxBuildingHits):
				continue
			building_hits[target.id] = used + 1
		var factor: float = 1.0 - (1.0 - Content.constants.AOE_EDGE) * clampf(win.angle / half_arc, 0, 1)
		hits.append({"id": target.id, "amount": definition.dmg * Content.constants.FAN_SUB_F * factor})
	return hits

static func altitude_range(definition: Dictionary, height_gap: float) -> float:
	if height_gap <= 0:
		return 1.0
	var altitude: Dictionary = Content.constants.ALTITUDE
	var tier: float = Content.constants.TARGET_H.tower
	var strength := clampf((height_gap - tier) / (tier * (altitude.TIERS - 1)), 0, 1)
	var heavy: bool = definition.get("id", definition.get("slot", "")) in ["heavy", "atk", "ult"]
	return 1.0 + altitude.RANGE * (altitude.RANGE_HEAVY_MUL if heavy else 1.0) * strength

static func lance_zones(offset: Vector2, radius: float, beam_radius: float) -> Array[int]:
	var core: float = beam_radius * Content.constants.LANCE.CORE_F
	var distance := offset.length()
	var zones: Array[int] = []
	if distance - radius <= core:
		zones.append(0)
	if distance + radius > core:
		if distance <= radius:
			for bin in range(1, 7):
				zones.append(bin)
		else:
			var angle := atan2(offset.y, offset.x)
			var half := asin(minf(1.0, radius / distance))
			var segment := TAU / 6
			var first := floori((angle - half + PI) / segment)
			var last := floori((angle + half + PI) / segment)
			for bin in range(first, last + 1):
				zones.append(posmod(bin, 6) + 1)
	zones.sort()
	return zones

static func line_hits(definition: Dictionary, origin: Vector3, direction: Vector3, length: float, targets: Array) -> Array:
	var horizontal := sqrt(float(direction.x) * direction.x + float(direction.z) * direction.z)
	var vertical := horizontal < 0.15
	var axis_x := float(direction.x) / horizontal if not vertical else 0.0
	var axis_z := float(direction.z) / horizontal if not vertical else 0.0
	var slope := float(direction.y) / horizontal if not vertical else 0.0
	var maximum := length if vertical else length * horizontal
	var radius: float = definition.lanceRadius
	var band: float = radius * Content.constants.LANCE.VBAND_F
	var candidates: Array = []
	for target: Dictionary in targets:
		var x := float(target.position.x) - origin.x
		var z := float(target.position.z) - origin.z
		var y: float = target.get("relative_y", float(target.sample_y) - origin.y)
		var along := y * (1.0 if direction.y >= 0 else -1.0) if vertical else x * axis_x + z * axis_z
		var clamped := clampf(along, 0, maximum)
		var offset_x := x if vertical else x - axis_x * clamped
		var offset_z := z if vertical else z - axis_z * clamped
		if not vertical:
			var ray_y := float(origin.y) + slope * clamped
			var outside := maxf(0, maxf(target.position.y - ray_y, ray_y - target.position.y - target.height))
			if outside > band:
				continue
		var deviation := sqrt(offset_x * offset_x + offset_z * offset_z + (along - clamped) * (along - clamped))
		var combined: float = radius + target.radius
		if deviation > combined:
			continue
		var distance := sqrt(x * x + z * z + y * y)
		# Source zones use north-positive Z; Godot world Z points south.
		for zone in lance_zones(Vector2(offset_x, -offset_z), target.radius, radius):
			candidates.append({"target": target, "along": along, "distance": distance,
				"zone": zone, "off": minf(1, deviation / combined), "order": candidates.size()})
	candidates.sort_custom(func(a, b):
		if a.along != b.along:
			return a.along < b.along
		if a.zone != b.zone:
			return a.zone < b.zone
		return a.order < b.order)
	var budgets := {}
	var counts := {}
	var seen := {}
	var hits: Array = []
	for candidate in candidates:
		var zone: int = candidate.zone
		var target: Dictionary = candidate.target
		if float(budgets.get(zone, 0)) < 0:
			continue
		if not budgets.has(zone):
			budgets[zone] = definition.lancePen * (3.0 if zone == 0 else 1.0) / 9.0
		budgets[zone] -= PI * target.radius * target.radius
		var rank: int = counts.get(zone, 0)
		counts[zone] = rank + 1
		var repeat: int = seen.get(target.id, 0)
		seen[target.id] = repeat + 1
		# Even an out-of-range body consumes penetration before the honest damage gate.
		if candidate.along - target.radius > definition.range * target.get("range_factor", 1.0):
			continue
		var off_factor: float = 1.0 - (1.0 - Content.constants.AOE_EDGE) * candidate.off
		var amount: float = definition.dmg * damage_falloff(definition, candidate.distance) * off_factor
		amount *= pow(Content.constants.LANCE.DECAY, rank) * (Content.constants.LANCE.REHIT_F if repeat > 0 else 1.0)
		hits.append({"id": target.id, "zone": zone, "rank": rank, "repeat": repeat, "amount": amount})
	return hits

