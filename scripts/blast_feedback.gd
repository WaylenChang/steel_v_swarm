class_name BlastFeedback
extends RefCounted

const REPORT_TYPES := ["boom", "mine_blast", "missile_blast", "missile_intercept", "missile_deflect"]

static func reaction(point: Vector3, radius: float, position: Vector3, eye: Vector3, height: float,
		yaw: float, flying: bool, trauma: float, has_side: bool = true, dead: bool = false) -> Dictionary:
	var result := {"trauma": trauma, "velocity": Vector3.ZERO, "lift": 0.0}
	if not has_side or dead:
		return result
	var reach := radius * float(Content.constants.SHAKE.BLAST_F)
	if not reach > 0:
		return result
	var energy := clampf(radius / 12, .4, 1.6)
	var cx := float(eye.x) - float(point.x)
	var cy := float(eye.y) - float(point.y)
	var cz := float(eye.z) - float(point.z)
	var camera_distance := sqrt(cx * cx + cy * cy + cz * cz)
	if camera_distance <= reach:
		var weight := 1 - camera_distance / reach
		result.trauma = minf(1, trauma + weight * weight * energy * .8)
	var body_height := height if ControlPreferences.truthy(height) else 2.0
	var dx := float(position.x) - float(point.x)
	var dy := float(position.y) + body_height * .5 - float(point.y)
	var dz := float(position.z) - float(point.z)
	var squared := dx * dx + dy * dy + dz * dz
	var distance := sqrt(squared)
	if distance <= reach:
		var weight := 1 - distance / reach
		var power := weight * weight * energy * (55 if flying else 26)
		if squared < .04:
			dx = sin(yaw)
			dy = .35
			dz = cos(yaw)
		var length := sqrt(dx * dx + dy * dy + dz * dz)
		result.velocity = Vector3(dx / length * power, dy / length * power, dz / length * power)
		if not flying:
			result.lift = weight * weight * energy * 10
	return result

static func point(event: Dictionary, ground: float) -> Vector3:
	var position: Vector3 = event.position
	if event.type == "mine_blast":
		position.y = ground + 2
	return position

static func sam(event: Dictionary) -> bool:
	return bool(event.get("sam", false)) or str(event.type) in ["missile_blast", "missile_intercept"]

static func local_point(position: Vector3, ground: float, tunnel: Dictionary) -> Vector3:
	var covered := not tunnel.is_empty() and not tunnel.open and position.y < float(tunnel.ceil)
	var floor_y := float(tunnel.floor) if covered else ground
	return Vector3(position.x, maxf(position.y, floor_y + 1), position.z)

static func local_radius(value: Variant) -> float:
	return float(value) if ControlPreferences.truthy(value) else 12.0
