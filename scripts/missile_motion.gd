class_name MissileMotion
extends RefCounted

const NATIVE_HEIGHT_TOLERANCE := 0.001

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
		if distance <= maxf(Content.balance.missile.fuseDistance, step):
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
