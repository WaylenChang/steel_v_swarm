class_name MissileMotion
extends RefCounted

const NATIVE_HEIGHT_TOLERANCE := 0.001

static func attracted_target(state: Dictionary, side: String, decoys: Array, kamis: Array = []) -> int:
	var target := int(state.target)
	if state.get("lost", false) or decoys.is_empty() and kamis.is_empty():
		return target
	var position: Array = state.get("components", [float(state.position.x), float(state.position.y), float(state.position.z)])
	var best_distance: float = Content.balance.missile.decoyRadius
	for decoy: Dictionary in decoys:
		if decoy.hp <= 0 or decoy.get("dead", false) or decoy.side != side:
			continue
		var point: Vector3 = decoy.position
		var dx: float = position[0] - float(point.x)
		var dy: float = position[1] - float(point.y)
		var dz: float = position[2] - float(point.z)
		var distance := sqrt(dx * dx + dy * dy + dz * dz)
		if distance < best_distance:
			target = int(decoy.id)
			best_distance = distance
	# Source attack carriers remain in the drone owner's kami roster. They override holograms.
	best_distance = INF
	for carrier: Dictionary in kamis:
		if carrier.hp <= 0:
			continue
		var point: Vector3 = carrier.position
		var dx: float = position[0] - float(point.x)
		var dy: float = position[1] - float(point.y)
		var dz: float = position[2] - float(point.z)
		var distance := sqrt(dx * dx + dy * dy + dz * dz)
		if distance < best_distance:
			target = int(carrier.id)
			best_distance = distance
	return target

# Server missiles use height above terrain, unlike the hero's absolute flight vectors.
static func advance(state: Dictionary, delta: float, target: Dictionary = {}, obstruction: Callable = Callable()) -> Dictionary:
	state.ttl -= delta
	if state.ttl <= 0:
		return {"remove": true}
	var p: Array = state.get("components", [float(state.position.x), float(state.position.y), float(state.position.z)])
	var previous := Vector3(p[0], p[1], p[2])
	var step: float = state.speed * delta
	if not state.get("lost", false):
		if target.is_empty():
			return {"remove": true}
		var point: Vector3 = target.position
		var dx: float = float(point.x) - p[0]
		var dy: float = float(point.y) - p[1]
		var dz: float = float(point.z) - p[2]
		var distance := sqrt(dx * dx + dy * dy + dz * dz)
		if distance == 0:
			distance = 1.0
		if target.get("phase", false):
			state.lost = true
			state.velocity_components = [dx / distance * state.speed, dy / distance * state.speed, dz / distance * state.speed]
		elif distance <= maxf(Content.balance.missile.fuseDistance, step):
			if target.get("reflect", false):
				var yaw: float = target.get("yaw", 0.0)
				var fx := -sin(yaw)
				var fz := -cos(yaw)
				var ax: float = p[0] - float(point.x)
				var az: float = p[2] - float(point.z)
				var planar_distance := sqrt(ax * ax + az * az)
				var arc: float = target.get("reflect_arc", deg_to_rad(120.0))
				if arc == 0:
					arc = deg_to_rad(120.0)
				if planar_distance > 0.01 and (fx * ax + fz * az) / planar_distance >= cos(arc / 2):
					var shift: float = Content.balance.missile.reflectOffset
					return {"remove": true, "deflected": true, "target": state.target,
						"reflection": previous, "flash": previous + Vector3(fx * shift, 0, fz * shift)}
			return {"remove": true, "blast": point, "target": state.target}
		var origin: Vector3 = state.origin
		var ox := float(point.x) - origin.x
		var oy := float(point.y) - origin.y
		var oz := float(point.z) - origin.z
		if sqrt(ox * ox + oy * oy + oz * oz) > state.range:
			state.lost = true
			state.velocity_components = [dx / distance * state.speed, dy / distance * state.speed, dz / distance * state.speed]
		else:
			p[0] += dx / distance * step
			p[1] += dy / distance * step
			p[2] += dz / distance * step
			# Phase marks permanent loss but still takes this source guided step when inside range.
			state.components = p
			state.position = Vector3(p[0], p[1], p[2])
			if obstruction.is_valid() and obstruction.call(previous, state.position):
				return {"remove": true, "blast": state.position}
			return {}
	if state.get("lost", false):
		var velocity: Array = state.get("velocity_components", [0.0, 0.0, 0.0])
		for axis in range(3):
			p[axis] += velocity[axis] * delta
	state.components = p
	state.position = Vector3(p[0], p[1], p[2])
	if obstruction.is_valid() and obstruction.call(previous, state.position):
		# Source detonates at the step endpoint, rather than the ray's wall intersection.
		return {"remove": true, "blast": state.position}
	return {}

static func line_contains(definition: Dictionary, origin: Vector3, direction: Vector3, length: float, point: Vector3) -> bool:
	var offset := point - origin
	var along := clampf(offset.dot(direction), 0, length)
	return (offset - direction * along).length() <= definition.lanceRadius and offset.length() <= definition.range * Content.constants.RANGE_TOL

static func snapshot_position(state: Dictionary) -> Vector3:
	var p: Array = state.get("components", [float(state.position.x), float(state.position.y), float(state.position.z)])
	var scale: float = Content.balance.missile.snapshotScale
	# JavaScript half ties round toward +infinity in the source north-positive frame.
	return Vector3(floorf(float(p[0]) * scale + 0.5) / scale,
		floorf(float(p[1]) * scale + 0.5) / scale, -floorf(-float(p[2]) * scale + 0.5) / scale)
