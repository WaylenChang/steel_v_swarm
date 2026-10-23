extends RefCounted

const Helper = preload("res://tests/status_suite.gd")

class RampWorld extends BattleWorld:
	var grade := 0.0
	func source_height(x: float, _z: float) -> float:
		return x * grade
	func ground_height(x: float, z: float) -> float:
		return source_height(x, z)

class RampSimulation extends BattleSimulation:
	func _movement_surface(point: Vector3) -> float:
		return world.source_height(point.x, point.z)
	func _update_fluid_state(unit: BattleUnit) -> void:
		unit.fluid_environment = {"code": 0, "air": unit.position.y - _movement_surface(unit.position) > float(Content.constants.AIR.OFF_GROUND)}
		unit.wet = 0

static func run(h: Node, fixtures: Dictionary) -> void:
	for key: String in ["traversalMath", "traversalQueries", "traversalSnap", "traversalSlides", "traversalWarnings"]:
		if not fixtures.has(key):
			h._check(false, "Regenerate original slope traversal references: " + key)
			return
	for item: Dictionary in fixtures.traversalMath:
		if item.has("angle"):
			h._near(MovementRules.slope_factor(item.angle), item.factor, "Original signed uphill/downhill speed curve")
			h._check(MovementRules.slope_blocked(item.angle) == item.blocked, "Original strict uphill-only block boundary")
		else:
			h._near(MovementRules.slope_snap_distance(item.run), item.snap, "Original bounded downhill support distance")
	for item: Dictionary in fixtures.traversalQueries:
		var log: Array = []
		var queries := query_context(item, log)
		var angle := MovementRules.slope_along(0, 0, 20, item.offset[0], item.offset[1], item.flag == "flying",
			item.flag == "air", .001 if item.flag == "rising" else 0.0, queries)
		h._near(angle, item.angle, "Original bare-terrain slope excludes bridge/tunnel/roof/airborne support")
		Helper.compare(h, log, item.angleQueries, "Original slope query order and early-return boundaries")
		log.clear()
		var factor := MovementRules.slope_speed(0, 0, 20, item.direction[0], item.direction[1], item.flag == "flying",
			item.flag == "air", .001 if item.flag == "rising" else 0.0, queries)
		h._near(factor, item.factor, "Original fixed-distance probe is independent of analog magnitude and frame delta")
		Helper.compare(h, log, item.speedQueries, "Original fixed-probe surface query order")
	for item: Dictionary in fixtures.traversalSnap:
		var foot: float = 10 + float(item.above)
		var surface: float = 10 - float(item.drop)
		var result := MovementRules.slope_ground(foot, 10, surface, item.run, item.vertical, item.low)
		Helper.compare(h, {"onGround": result.grounded, "position": surface if result.snap else foot,
			"vertical": 0.0 if result.snap else float(item.vertical)}, item.result,
			"Original descending support, jump/low-gravity exclusion and cliff-drop gate")
	for item: Dictionary in fixtures.traversalSlides:
		var query := func(x: float, z: float) -> float:
			return MovementRules.slope_degrees(x * float(item.grade[0]) + z * float(item.grade[1]), sqrt(x * x + z * z))
		var result := MovementRules.slope_step(item.offset[0], item.offset[1], query)
		h._check(result.valid and result.blocked == item.blocked, "Original terrain block classification")
		Helper.compare(h, {"position": [result.x, 10.0 if result.blocked else 12.0, result.z],
			"impulse": [0, 0] if result.blocked else [3, 4]}, item.result,
			"Original X-before-Z contour slide and blocked-frame impulse reset")
	var invalid := MovementRules.slope_step(1, 1, func(_x, _z): return NAN)
	h._check(not invalid.valid, "Missing captured terrain cannot become a fabricated flat walkable surface")
	for item: Dictionary in fixtures.traversalWarnings:
		var receiver := CombatFeedState.new()
		for step: Dictionary in item.steps:
			var stopped: bool = item.blocked and float(item.offset[0]) == 0 and float(item.offset[1]) == 0
			var messages := receiver.slope_notice(stopped, step.now, step.now)
			h._near(receiver.slope_warning_at, step.last, "Original strict steep-slope warning deadline")
			Helper.compare(h, messages, step.notices, "Contour slides and early/repeated blocks do not spam the original slope notice")
			h._check(receiver.slope_notice(stopped, float(step.now) + 100, step.now).is_empty(), "Old private movement feedback cannot renew a warning")
	await native_ramps(h)

static func query_context(item: Dictionary, log: Array) -> Dictionary:
	var height := func(x: float, z: float) -> float: return 10 + float(item.grade) * x + float(item.grade) * .5 * z
	var surface := func(x: float, z: float) -> float:
		match item.mode:
			"raised": return height.call(x, z) + float(Content.constants.SLOPE.STRUCT_M) + .0001
			"structBoundary": return height.call(x, z) + float(Content.constants.SLOPE.STRUCT_M)
			"deck", "tunnel", "tunnelBoundary": return 20.0
			"deckBoundary": return 20 + float(Content.balance.movement.slope.deckTolerance)
			"transition": return 20.0 if x > 0 else height.call(x, z)
		return height.call(x, z)
	return {
		"height": func(x, z):
			log.append(["height", x, z])
			return height.call(x, z),
		"surface": func(x, z, y):
			log.append(["surface", x, z, y])
			return surface.call(x, z),
		"tunnel": func(x, z):
			log.append(["tunnel", x, z])
			return {"ceil": 21} if item.mode == "tunnel" else {"ceil": 20} if item.mode == "tunnelBoundary" else {},
		"deck": func(x, z, margin):
			log.append(["deck", x, z, margin])
			return 20.0 if item.mode in ["deck", "deckBoundary", "transition"] else null}

static func native_ramps(h: Node) -> void:
	for uphill: bool in [true, false]:
		var simulation := RampSimulation.new()
		h.add_child(simulation)
		simulation.set_physics_process(false)
		var world := RampWorld.new()
		var degrees: float = float(Content.constants.SLOPE.BLOCK_DEG) + 4 if uphill else float(Content.constants.SLOPE.BLOCK_DEG) - 4
		world.grade = tan(deg_to_rad(degrees))
		simulation.world = world
		simulation.add_child(world)
		var floor_body := StaticBody3D.new()
		floor_body.rotation.z = deg_to_rad(degrees)
		floor_body.collision_layer = 1
		world.add_child(floor_body)
		var plane := PlaneMesh.new()
		plane.size = Vector2(200, 200)
		var collision := CollisionShape3D.new()
		collision.shape = plane.create_trimesh_shape()
		floor_body.add_child(collision)
		var unit := BattleUnit.new()
		simulation.add_child(unit)
		unit.configure({"id": 1, "peer": 1, "character": "t01", "kind": Content.heroes.t01.kind,
			"side": "STEEL", "position": Vector3(0, .02, 0)})
		simulation.units[1] = unit
		simulation.pilots[1] = unit
		unit.input_state = {"move": Vector2(1 if uphill else -1, 0), "yaw": 0.0, "pitch": 0.0, "jump_held": not uphill}
		var before := [unit.hp, unit.shield, unit.money, unit.ammo.duplicate(true), simulation.rng.state]
		await h.get_tree().physics_frame
		await h.get_tree().physics_frame
		for frame in range(20):
			simulation.clock += 1.0 / 60
			unit.simulate_movement(1.0 / 60)
			await h.get_tree().physics_frame
		if uphill:
			# Native penetration recovery may displace the initially touching cylinder
			# downhill. It cannot grant an uphill command or a source airborne bypass.
			h._check(unit.position.x < .01 and absf(unit.velocity.x) < .01 and unit.slope_blocked,
				"Native floor contact preserves the original uphill block: position=" + str(unit.position))
		else:
			h._check(unit.position.x < -.1 and unit.charge > .1 and unit.is_on_floor(), "Native downhill snap preserves contact and held jump charge")
		Helper.compare(h, [unit.hp, unit.shield, unit.money, unit.ammo, simulation.rng.state], before,
			"Native slope traversal does not settle health, ammo, credits or consume combat RNG")
		simulation.free()
		await h.get_tree().physics_frame
