class_name ProjectileMotion
extends RefCounted

# Source flight laws; collision queries and all damage remain on the simulation authority.
static func launch(definition: Dictionary, origin: Vector3, direction: Vector3, surface_height: float,
		spread_angle: float, spread_amount: float, aim: Vector3, target_id: int = 0) -> Dictionary:
	var spec: Dictionary = definition.projectile
	var up := Vector3.RIGHT if absf(direction.y) > 0.9 else Vector3.UP
	var lateral := direction.cross(up).normalized()
	var vertical := direction.cross(lateral).normalized()
	var spread := tan(spread_amount * spec.arm.spread)
	direction = (direction + lateral * spread * cos(spread_angle * TAU) + vertical * spread * sin(spread_angle * TAU)).normalized()
	var lift := launch_lift(definition, origin, direction, surface_height, spec.speed)
	return {"position": origin, "origin": origin, "velocity": lift.velocity, "age": 0.0,
		"range": definition.range, "launch_distance": lift.distance,
		"target": target_id, "guide_point": aim, "chase": false, "last_known": false,
		"home_point": Vector3.ZERO, "home_radius": 0.0, "dud": false}

static func launch_lift(definition: Dictionary, origin: Vector3, direction: Vector3, surface_height: float, speed: float) -> Dictionary:
	if definition.trajectory not in ["guide", "fnf"]:
		return {"velocity": direction * speed, "distance": 0.0, "guided": false}
	var launch_config: Dictionary = Content.constants.GUIDED_LAUNCH
	var base_pitch: float = launch_config.PITCH_DEG_FNF if definition.trajectory == "fnf" else launch_config.PITCH_DEG
	var pitch := deg_to_rad(base_pitch * maxf(0, 1 - maxf(0, origin.y - surface_height) / (Content.constants.TARGET_H.tower * launch_config.ZERO_PITCH_TOWER_F)))
	var velocity: Vector3 = direction * speed
	if pitch > 0:
		var flat := Vector3(direction.x, 0, direction.z)
		if flat.length_squared() <= 0.000001:
			flat = Vector3.BACK
		velocity = flat.normalized() * speed * cos(pitch) + Vector3.UP * speed * sin(pitch)
	return {"velocity": velocity, "distance": definition.projectile.launchDistance if pitch > 0 else 0.0, "guided": pitch > 0}

static func ballistic(origin: Vector3, velocity: Vector3, reach: float) -> Dictionary:
	return {"position": origin, "origin": origin, "velocity": velocity, "age": 0.0,
		"range": reach, "launch_distance": 0.0, "target": 0, "guide_point": Vector3.ZERO,
		"chase": false, "last_known": false, "home_point": Vector3.ZERO, "home_radius": 0.0, "dud": false}

static func advance(state: Dictionary, definition: Dictionary, delta: float, target: Dictionary = {}) -> Vector3:
	var previous: Vector3 = state.position
	state.age += delta
	var homing: bool = definition.trajectory == "fnf"
	if homing and not target.is_empty():
		state.chase = true
	var distance := previous.distance_to(state.origin)
	var arming: Dictionary = definition.projectile.arm if definition.projectile.arm is Dictionary else {}
	var armed: bool = distance >= arming.get("m", 0)
	var climbing: bool = state.launch_distance > 0 and distance < state.launch_distance
	var steering := false
	var aim := Vector3.ZERO
	if not climbing and armed:
		if homing and not target.is_empty():
			aim = target.position + Vector3.UP * 1.5
			state.home_point = aim
			state.home_radius = target.radius
			state.last_known = true
			steering = true
		elif definition.trajectory == "guide":
			aim = state.guide_point
			steering = true
		elif homing and state.chase and state.last_known:
			aim = state.home_point
			steering = true
	var velocity: Vector3 = state.velocity
	if steering:
		var current := velocity.normalized()
		var desired := (aim - previous).normalized()
		var angle := current.angle_to(desired)
		var speed: float = definition.projectile.speed
		var turn := maxf(Content.constants.SEEK.HOME_W, speed / Content.constants.SEEK.R_M)
		if angle > 0.0001:
			current = current.lerp(desired, minf(1, turn * delta / angle)).normalized()
		velocity = current * speed
		state.vertical_speed = float(velocity.y)
	else:
		# GDScript scalars retain source double precision across long dud flights.
		# Vector3 is float32 and remains the native physics/query boundary.
		state.vertical_speed = float(state.get("vertical_speed", velocity.y)) - Content.constants.BALLISTIC.G * delta
		velocity.y = state.vertical_speed
	state.velocity = velocity
	var components: Array = state.get("position_components", [float(previous.x), float(previous.y), float(previous.z)])
	components[0] += float(velocity.x) * delta
	components[1] += float(state.vertical_speed) * delta
	components[2] += float(velocity.z) * delta
	state.position_components = components
	state.position = Vector3(components[0], components[1], components[2])
	return previous

static func proximity(state: Dictionary, definition: Dictionary, previous: Vector3, target: Dictionary = {}) -> Dictionary:
	var aim: Vector3
	var radius: float = definition.projectile.core
	if not target.is_empty():
		aim = target.position
		radius += target.radius
	elif definition.trajectory == "guide":
		aim = state.guide_point
	elif state.chase and state.last_known:
		aim = state.home_point
		radius += state.home_radius
	else:
		return {}
	var segment: Vector3 = state.position - previous
	var length_squared := segment.length_squared()
	var fraction := clampf((aim - previous).dot(segment) / length_squared, 0, 1) if length_squared > 0.000000001 else 0.0
	var point := previous + segment * fraction
	return {"position": point} if point.distance_to(aim) < radius else {}

static func finish(state: Dictionary, definition: Dictionary, hit: bool) -> bool:
	if definition.trajectory == "flat":
		return hit or state.position.distance_to(state.origin) >= state.range
	# A collision in the boundary frame wins; crossing alone permanently disarms the warhead.
	if not hit and (state.age >= definition.projectile.fuel if state.chase else state.position.distance_to(state.origin) >= state.range):
		state.dud = true
	return hit or (state.dud and state.age >= definition.projectile.fuel)
