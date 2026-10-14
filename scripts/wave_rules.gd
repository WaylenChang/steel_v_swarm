class_name WaveRules
extends RefCounted

static func cumulative(points: Array) -> Array[float]:
	var distances: Array[float] = [0.0]
	for index in range(1, points.size()):
		var dx: float = float(points[index][0]) - points[index - 1][0]
		var dz: float = float(points[index][1]) - points[index - 1][1]
		distances.append(distances[-1] + sqrt(dx * dx + dz * dz))
	return distances

static func point_at(points: Array, distances: Array, progress: float) -> Dictionary:
	if progress <= 0:
		return {"x": float(points[0][0]), "z": float(points[0][1])}
	if progress >= float(distances[-1]):
		return {"x": float(points[-1][0]), "z": float(points[-1][1])}
	var index := 1
	while float(distances[index]) < progress:
		index += 1
	var length: float = float(distances[index]) - distances[index - 1]
	var fraction: float = (progress - distances[index - 1]) / (length if length else 1.0)
	return {"x": float(points[index - 1][0]) + (float(points[index][0]) - points[index - 1][0]) * fraction,
		"z": float(points[index - 1][1]) + (float(points[index][1]) - points[index - 1][1]) * fraction}

static func spawn_plan(points: Array, distances: Array, side: String, lead: float, random: SourceRng) -> Array:
	var rules: Dictionary = Content.balance.wave_rules
	var plan: Array = []
	for index in range(rules.composition.size()):
		var jitter_x: float = (random.next() - 0.5) * rules.jitter
		var jitter_z: float = -(random.next() - 0.5) * rules.jitter
		var progress := maxf(lead - index * float(rules.tail_spacing), Content.constants.GAME.WAVE_SPAWN_OFF_M)
		var distance := progress if side == "SWARM" else float(distances[-1]) - progress
		var point := point_at(points, distances, clampf(distance, 0, distances[-1]))
		plan.append({"kind": rules.composition[index], "progress": progress, "x": point.x + jitter_x, "z": point.z + jitter_z})
	return plan

static func step(state: Dictionary, points: Array, distances: Array, speed: float, delta: float,
		controls: Dictionary, anchor: float = NAN, structures: Array = [], blockers: Array = [], allies: Array = [], weather: float = 1.0) -> void:
	var rules: Dictionary = Content.balance.wave_rules
	var hold := is_finite(anchor) and state.progress > anchor + Content.constants.GAME.WAVE_COHESION_M
	var factor := 0.0 if controls.get("stun", false) else 1.0
	if factor:
		if controls.get("slow", false):
			factor *= float(controls.get("slow_factor", 0.6))
		if controls.get("confuse", false):
			factor *= -0.5
	if not hold and factor != 0:
		state.progress = maxf(0, float(state.progress) + speed * factor * weather * delta)
	var distance: float = state.progress if state.side == "SWARM" else float(distances[-1]) - state.progress
	var point := point_at(points, distances, clampf(distance, 0, distances[-1]))
	state.x = point.x + (float(state.x) - point.x) * rules.convergence
	state.z = point.z + (float(state.z) - point.z) * rules.convergence
	for structure: Dictionary in structures:
		push_circle(state, structure.x, structure.z, rules.structure_radius[structure.kind], false)
	for blocker: Dictionary in blockers:
		push_circle(state, blocker.x, blocker.z, blocker.radius, false)
	for ally: Dictionary in allies:
		push_circle(state, ally.x, ally.z, rules.unit_push, true)

static func push_circle(state: Dictionary, x: float, z: float, radius: float, half: bool) -> void:
	var dx: float = state.x - x
	var dz: float = state.z - z
	var distance := sqrt(dx * dx + dz * dz)
	if distance >= radius or distance == 0:
		return
	var displacement := (radius - distance) * (0.5 if half else 1.0)
	state.x += dx / distance * displacement
	state.z += dz / distance * displacement
