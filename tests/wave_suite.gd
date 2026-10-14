extends RefCounted

const StatusHelper = preload("res://tests/status_suite.gd")

class WaveSimulation extends BattleSimulation:
	var recipes: Array = []

	func _spawn_lane_wave(lane: int, side: String, wave_id: int, lead: float) -> void:
		recipes.append({"lane": lane, "side": side, "wave": wave_id, "lead": lead})

static func run(h: Node, fixtures: Dictionary) -> void:
	for key: String in ["wavePolyline", "waveSpawn", "wavePrefill", "waveAnchors", "waveMovement"]:
		if not fixtures.has(key):
			h._check(false, "Regenerate original wave oracle: " + key)
			return
	for item: Dictionary in fixtures.wavePolyline:
		var cumulative := WaveRules.cumulative(item.points)
		StatusHelper.compare(h, cumulative, item.cumulative, "Original planar lane cumulative distances")
		var point := WaveRules.point_at(item.points, cumulative, item.distance)
		h._near(point.x, item.point.x, "Original clamped polyline x")
		h._near(point.z, item.point.z, "Original clamped polyline native z")
	for item: Dictionary in fixtures.waveSpawn:
		var random := SourceRng.new(42)
		var plan := WaveRules.spawn_plan(item.points, WaveRules.cumulative(item.points), item.side, item.lead, random)
		h._check(plan.size() == item.actors.size(), "Original fixed wave composition")
		for index in range(mini(plan.size(), item.actors.size())):
			var actor: Dictionary = plan[index]
			var expected: Dictionary = item.actors[index]
			h._check(actor.kind == expected.kind, "Original wave actor order")
			for property: String in ["x", "z", "progress"]:
				h._near(actor[property], expected[property], "Original wave jitter, mirrored coordinate and spawn floor: " + property)
			h._near(NpcRules.creep_multiplier(item.level), expected.multiplier, "Original spawn-time creep multiplier")
		var expected_random := SourceRng.new(42)
		for index in range(int(item.draws)):
			expected_random.next()
		h._check(random.state == expected_random.state, "Wave placement consumes exactly two combat RNG draws per actor")
	for item: Dictionary in fixtures.wavePrefill:
		var simulation := WaveSimulation.new()
		h.add_child(simulation)
		simulation.set_physics_process(false)
		simulation._prefill_lanes({"wave_prefill": item.calls})
		StatusHelper.compare(h, simulation.recipes, item.calls, "Native constructor consumes the original ordered side/lane prefill plan")
		simulation.free()
	for item: Dictionary in fixtures.waveAnchors:
		var simulation := WaveSimulation.new()
		h.add_child(simulation)
		simulation.set_physics_process(false)
		for id in range(1, 6):
			var character := "t05" if id == 4 else ""
			var unit := StatusHelper.actor(simulation, {"id": id, "character": character, "kind": "tank" if id == 2 else "soldier", "side": "SWARM" if id == 3 else "STEEL",
				"position": [0, 0, 0], "hp": 0 if id == 1 and item.dead else 100, "max_hp": 100})
			unit.has_lane = id != 5
			unit.lane = 0
			unit.npc_has_wave = true
			unit.npc_wave = -1 if id == 3 else 1
			unit.npc_progress = 30 if id == 1 else 60 if id == 2 else 40 if id == 3 else 1
			unit.npc_engaged = id == 1 and item.engaged
		StatusHelper.compare(h, simulation._wave_anchors(), item.result, "Only living unengaged lane members anchor their source wave")
		simulation.free()
	for item: Dictionary in fixtures.waveMovement:
		var state: Dictionary = item.input.duplicate(true)
		var controls := {"stun": item.status == "stun", "slow": "slow" in item.status, "slow_factor": 0.6, "confuse": "confuse" in item.status}
		var cumulative := WaveRules.cumulative(item.points)
		for step: Dictionary in item.steps:
			WaveRules.step(state, item.points, cumulative, Content.constants.UNITS.soldier.speed, step.delta, controls,
				float(item.anchor) if item.anchor != null else NAN, item.structures, item.blockers, item.allies)
			for property: String in ["x", "z", "progress"]:
				h._near(state[property], step[property], "Original wave cohesion, control and sequential push: " + property)
	for map_data: Dictionary in Content.maps:
		for key: String in map_data.variants:
			h._check(map_data.variants[key].has("wave_prefill"), "Every migrated map/team variant has an original prefill recipe")
	print("WAVE_REFERENCE_PASS polyline=", fixtures.wavePolyline.size(), " spawn=", fixtures.waveSpawn.size(),
		" prefill=", fixtures.wavePrefill.size(), " anchors=", fixtures.waveAnchors.size(), " movement=", fixtures.waveMovement.size())
