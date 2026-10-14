class_name AbilityFieldRules
extends RefCounted

static func covers(field: Dictionary, point: Vector2, now: float) -> bool:
	var center: Vector2 = field.center
	return float(field.until) > now and center.distance_to(point) <= float(field.radius)

static func observer_factor(fogs: Array, point: Vector2, side: String, now: float) -> float:
	for fog: Dictionary in fogs:
		if fog.side != side and covers(fog, point, now):
			return 0.333
	return 1.0

static func protecting_fog(fogs: Array, point: Vector2, side: String, now: float) -> Dictionary:
	for fog: Dictionary in fogs:
		if fog.side == side and covers(fog, point, now):
			return fog
	return {}

static func slab_hit(start: Vector3, end: Vector3, slabs: Array) -> float:
	var dx := float(end.x) - start.x
	var dz := float(end.z) - start.z
	var nearest := INF
	for slab: Dictionary in slabs:
		if slab.get("dead", false) or float(slab.hp) <= 0:
			continue
		var center: Vector2 = slab.center
		var angle: float = float(slab.angle) + PI / 2
		# Source planar north becomes negative native Z; renderer rotation is a separate contract.
		var sx := float(center.x) - cos(angle) * 1.75
		var sz := float(center.y) + sin(angle) * 1.75
		var sdx := cos(angle) * 3.5
		var sdz := -sin(angle) * 3.5
		var denominator := dx * sdz - dz * sdx
		if absf(denominator) <= 0.000001:
			continue
		var fraction := ((sx - start.x) * sdz - (sz - start.z) * sdx) / denominator
		var across := ((sx - start.x) * dz - (sz - start.z) * dx) / denominator
		var height := float(start.y) + fraction * (float(end.y) - start.y)
		if fraction >= 0 and fraction <= 1 and across >= 0 and across <= 1 and height >= 0 and height <= float(slab.get("height", 6)):
			nearest = minf(nearest, fraction)
	return nearest
