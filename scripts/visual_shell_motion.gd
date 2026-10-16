class_name VisualShellMotion
extends RefCounted

static func launch(definition: Dictionary, origin: Vector3, target: Vector3, ground: float, surface: float, speed: float = NAN) -> Dictionary:
	var aa: bool = definition.type == "launcher" and target.y - ground > Content.constants.BALLISTIC.AA_ALT
	if not is_finite(speed) or speed == 0:
		speed = definition.projectile.antiAirSpeed if aa else definition.projectile.speed
	var direction := (target - origin).normalized()
	var x := float(target.x) - origin.x
	var y := float(target.y) - origin.y
	var z := float(target.z) - origin.z
	var distance := sqrt(x * x + y * y + z * z)
	var lift := ProjectileMotion.launch_lift(definition, origin, direction, surface, speed)
	var velocity: Vector3 = lift.velocity
	if not lift.guided and definition.type == "launcher":
		var fixed := LobFireControl.velocity_45(origin, target, definition.projectile.speed) if not aa else {}
		velocity = LobFireControl.velocity(origin, target, speed) if fixed.is_empty() else fixed.velocity
	return {"position": origin, "origin": origin, "target": target, "velocity": velocity,
		"pierce": definition.area == "line",
		"guided": lift.guided, "launch_distance": lift.distance, "age": 0.0,
		"range": maxf(0.01, minf((definition.range if definition.range else 300.0) * 1.35, distance))}

static func advance(state: Dictionary, delta: float, collision: Callable) -> Dictionary:
	var previous: Vector3 = state.position
	state.age += delta
	var velocity: Vector3 = state.velocity
	var climbing: bool = state.guided and previous.distance_to(state.origin) < state.launch_distance
	if not state.guided or climbing:
		state.vertical_speed = float(state.get("vertical_speed", velocity.y)) - Content.constants.BALLISTIC.G * delta
		velocity.y = state.vertical_speed
	else:
		var desired: Vector3 = state.target - previous
		if desired.length_squared() > 0.000001:
			desired = desired.normalized()
			var current := velocity.normalized()
			var angle := current.angle_to(desired)
			var speed := velocity.length()
			if angle > 0.0001:
				var turn := maxf(Content.constants.SEEK.RIDE_W, speed / Content.constants.SEEK.R_M)
				current = current.lerp(desired, minf(1, turn * delta / angle)).normalized()
			velocity = current * speed
			state.vertical_speed = float(velocity.y)
	state.velocity = velocity
	var components: Array = state.get("components", [float(previous.x), float(previous.y), float(previous.z)])
	components[0] += float(velocity.x) * delta
	components[1] += float(state.get("vertical_speed", velocity.y)) * delta
	components[2] += float(velocity.z) * delta
	state.components = components
	state.position = Vector3(components[0], components[1], components[2])
	var segment: Vector3 = state.position - previous
	var hit: Dictionary = collision.call(previous, state.position) if segment.length() > 0.01 else {}
	if not hit.is_empty():
		state.position = hit.position
	return {"previous": previous, "hit": not hit.is_empty(), "terminal": not hit.is_empty() or state.position.distance_to(state.origin) >= state.range}
