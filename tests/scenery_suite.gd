extends RefCounted

const StatusHelper = preload("res://tests/status_suite.gd")

class FireSimulation extends BattleSimulation:
	var burns: Array = []

	func _missile_target_altitude(unit: BattleUnit) -> float:
		return float(unit.get_meta("relative_altitude", 0))

	func _fire_burn(unit: BattleUnit, amount: float) -> void:
		burns.append({"id": unit.entity_id, "amount": amount})

static func run(h: Node, fixtures: Dictionary) -> void:
	for key: String in ["sceneryHeights", "sceneryStrikes", "sceneryFires", "fireVisuals"]:
		if not fixtures.has(key):
			h._check(false, "Regenerate original scenery oracle: " + key)
			return
	for item: Dictionary in fixtures.sceneryHeights:
		var grid := EnvironmentRules.decode_height_grid(item.encoded)
		var height: Variant = EnvironmentRules.authority_height(grid, item.x, item.z)
		if item.result == null:
			h._check(height == null, "Original authority rejects incomplete/malformed height grids")
		else:
			h._near(float(height), item.result, "Original quantized cell-center bilinear authority height")
	for item: Dictionary in fixtures.sceneryStrikes:
		var slope: float = Content.balance.weather.surface.flatGrade
		var height := func(x, _z): return null if item.mode == "unknown" else x * slope if item.mode == "slope_limit" else x * (slope + 0.000001) if item.mode == "slope_over" else 0.0
		var wet := func(x, _z): return 1 if item.mode == "wet" or (item.mode == "wet_edge" and x > float(item.cx) + float(Content.balance.weather.surface.strikeR) - 0.01) else 0
		var level := func(x, _z): return 1 if item.mode == "slab" else 2 if item.mode == "slab_edge" and x > float(item.cx) + float(Content.balance.weather.surface.strikeR) - 0.01 else 0
		var random := SourceRng.new(int(item.seed))
		var plan := EnvironmentRules.surface_strike(random, item.bounds, height, wet, level, item.obstacles, item.dynamics, int(item.count))
		if item.result == null:
			h._check(plan.is_empty(), "Original scenery strike skips unknown/wet/slab centers")
		else:
			StatusHelper.compare(h, plan, item.result, "Original scenery strike object tops, boundaries, ring slope and fire gates")
			if item.ttl != null:
				h._near(24 / (float(Content.constants.DAYCLOCK.GAME_H) / float(Content.constants.DAYCLOCK.REAL_S)), item.ttl, "Original lightning fire lasts one game day")
				h._near(float(plan.radius) / float(Content.constants.HAZARDS.fire.r), item.scale, "Original lightning fire effect radius")
		var expected := SourceRng.new(int(item.seed))
		expected.next()
		expected.next()
		h._check(random.state == expected.state, "Scenery lightning consumes only two independent location draws")
	for item: Dictionary in fixtures.sceneryFires:
		var simulation := FireSimulation.new()
		h.add_child(simulation)
		simulation.set_physics_process(false)
		simulation.clock = 10
		simulation.weather_dynamics = item.weather.duplicate()
		simulation.next_id = 50
		for kind: String in ["fire", "forestfire", "grassfire", "factoryfire"]:
			simulation._spawn_fire(kind, Vector3.ZERO, 1, item.lifetime, item.lightning)
		for actor: Dictionary in item.actors:
			var unit := StatusHelper.actor(simulation, {"id": actor.id, "character": actor.ch, "kind": actor.kind, "side": "STEEL", "position": [0, 0, 0], "hp": 100, "relative_altitude": actor.y})
			simulation.pilots[int(actor.id)] = unit
		var random_state := simulation.rng.state
		for step: Dictionary in item.steps:
			simulation.clock = step.now
			simulation.burns.clear()
			simulation._tick_fires(step.delta)
			StatusHelper.compare(h, simulation.burns, step.burns, "Original fire DOT eligibility: jump exclusion, smoke altitude and wind/quench")
			var fires: Array = simulation.fire_fields.map(func(fire): return {"id": fire.id, "ttl": fire.ttl})
			StatusHelper.compare(h, fires, step.fires, "Original permanent/temporary/lightning fire lifetime")
			for report: Dictionary in step.reports:
				h._near(float(simulation.units[int(report.id)].status.get("burn_report", 0)), report.at, "Original two-second burn event throttling")
			for zone: Dictionary in step.avoid:
				var radius: float = zone.radius
				h._check(simulation._terrain_blocked(zone.x + radius + 1, zone.z), "Original neutral fire avoidance includes two-meter safety margin")
			h._check(simulation.rng.state == random_state, "Fire lifecycle never consumes combat RNG")
		simulation.free()
	var presentation := FirePresentation.new()
	h.add_child(presentation)
	presentation.set_process(false)
	for item: Dictionary in fixtures.fireVisuals:
		var profile: Dictionary = Content.balance.hazard_visuals[item.key]
		presentation.sync([{"id": 1, "kind": profile.kind, "lightning": item.key == "fire_lightning", "position": Vector3.ZERO,
			"scale": float(profile.radius) / float(Content.constants.HAZARDS[profile.kind].r)}], item.now, item.weather)
		if not presentation.entries.has(1):
			h._check(false, "Pack original fire scene before final visual reference validation: " + item.key)
			continue
		presentation._process(0)
		for expected: Dictionary in item.flames + item.smoke:
			var node: MeshInstance3D = presentation.entries[1].nodes["n_%d" % int(expected.id)]
			h._check(node.visible == expected.visible, "Original fire weather quench visibility")
			for property: String in ["position", "scale", "rotation"]:
				var actual: Vector3 = node.get(property)
				var value: Array = expected[property]
				h._check(actual.distance_to(Vector3(value[0], value[1], value[2])) < 0.0001, "Original flame/smoke flicker, drift and winding: " + property)
			var material: StandardMaterial3D = node.mesh.surface_get_material(0)
			h._near(material.albedo_color.a, expected.opacity, "Original flame/smoke opacity")
		# Each kind has its own original node roster; retain sequential hidden poses within a kind.
		var last := fixtures.fireVisuals.find(item)
		if last + 1 == fixtures.fireVisuals.size() or fixtures.fireVisuals[last + 1].key != item.key:
			presentation.sync([], item.now, item.weather)
	presentation.free()
	print("SCENERY_REFERENCE_PASS heights=", fixtures.sceneryHeights.size(), " strike=", fixtures.sceneryStrikes.size(), " fires=", fixtures.sceneryFires.size())
