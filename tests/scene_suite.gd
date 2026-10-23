extends RefCounted

const StatusHelper = preload("res://tests/status_suite.gd")

class SceneSimulation extends BattleSimulation:
	func _missile_target_altitude(target: BattleUnit) -> float:
		return float(target.get_meta("relative_altitude", 0))

	func _spawn_fire(kind: String, point: Vector3, scale_factor: float = 1.0, lifetime: Variant = null, lightning: bool = false) -> void:
		fire_fields.append({"kind": kind, "position": point, "scale": scale_factor, "ttl": lifetime, "lightning": lightning})

class ThreatSimulation extends SceneSimulation:
	var hits: Array = []
	var launched: Array = []

	func damage(_attacker: BattleUnit, target: BattleUnit, definition: Dictionary, amount: float, _friendly: bool = false,
			_context: Dictionary = {}, _attack_modifiers: bool = true) -> void:
		hits.append({"target": target.entity_id, "amount": amount, "pen": definition.pen})

	func _launch_missile(state: Dictionary) -> void:
		launched.append({"actor": state.actor, "side": state.side, "target": state.target,
			"position": [state.position.x, state.position.y, state.position.z], "speed": state.speed,
			"dmg": state.dmg, "pen": state.pen, "r": state.r, "hp": state.hp, "ttl": state.ttl, "range": state.range, "ambush": state.ambush})
		missiles.append(state)

	func _remove_field_unit(id: int, _report: bool = false) -> void:
		var unit: BattleUnit = units.get(id)
		if unit != null:
			units.erase(id)
			unit.free()

static func run(h: Node, fixtures: Dictionary) -> void:
	for key: String in ["sceneMath", "sceneGeneration", "sceneCollapse", "sceneLoot", "scenePickups", "sceneMines", "sceneAmbush", "sceneRelays", "lootVisuals", "mineVisuals", "sceneCollapsePoses"]:
		if not fixtures.has(key):
			h._check(false, "Regenerate original scene references before final verification: " + key)
			return
	for item: Dictionary in fixtures.sceneMath:
		h._near(SceneRules.hash_value(item.x, item.z, item.kind), item.hash, "Original scene hash preserves negative coordinate rounding")
		h._check(SceneRules.physical(item.kind) == item.physical, "Original destructible scene roster")
		var health := SceneRules.hp(item.kind, item.radius, item.scale, item.x, item.z)
		h._near(health, item.hp, "Original scene HP type, radius, scale, jitter and cap")
		h._near(SceneRules.armor(item.kind, health), item.armor, "Original scene armor cap")
		h._check(SceneRules.electric_vehicle(item.x, item.z) == item.electric, "Original deterministic EV placement")
		h._near(SceneRules.fire_seconds(health), item.fire, "Original rubble fire duration")
		h._near(SceneRules.vehicle_fire_seconds(item.electric), item.vehicleFire, "Original EV fire duration")
	for item: Dictionary in fixtures.sceneGeneration:
		var cumulative: Array = []
		for lane: Array in item.lanes:
			cumulative.append(WaveRules.cumulative(lane))
		var state := {"lanes": item.lanes, "cumulative": cumulative, "turns": item.turns, "bases": item.bases, "bounds": item.bounds, "towers": item.towers}
		var wet := func(x, z): return 1 if item.wet and x > 1100 and z < -650 else 0
		var random := SourceRng.new(42)
		SceneRules.seed_mines(random, state)
		SceneRules.seed_hazards(random, state, wet, item.mix)
		SceneRules.seed_vehicles(random, state, wet)
		SceneRules.ensure_connectivity(state)
		SceneRules.seed_field_sites(random, state)
		SceneRules.prune_corridors(state, item.corridors)
		StatusHelper.compare(h, state.actors, item.result.actors, "Original hazard and parked vehicle generation order")
		StatusHelper.compare(h, state.blockers, item.result.blockers, "Original lane connectivity removal and stale footprints")
		StatusHelper.compare(h, state.mines, item.result.mines, "Original mine cut-turn distribution and tunnel-only pruning")
		StatusHelper.compare(h, state.relays, item.result.relays, "Original corridor prune retains the relay capture roster")
		check_draws(h, random, 42, int(item.draws))
	for item: Dictionary in fixtures.sceneCollapse:
		var simulation := SceneSimulation.new()
		h.add_child(simulation)
		simulation.set_physics_process(false)
		var unit := BattleUnit.new()
		simulation.add_child(unit)
		unit.kind = item.kind
		unit.entity_id = 1
		unit.hp = 0
		unit.max_hp = item.maxHp
		unit.position = Vector3(12, 0, -8)
		unit.special = {"role": "hazard", "scale": item.scale, "electric": item.electric}
		simulation.hazard_blockers = [{"x": 12, "z": -8, "radius": float(Content.constants.HAZARDS[item.kind].r) * float(item.scale)},
			{"x": 12, "z": -8, "radius": 100}]
		if item.capped:
			for index in range(40):
				simulation.fire_fields.append({"kind": "fire"})
		var random_state := simulation.rng.state
		simulation._collapse_scene(unit)
		h._check(unit.special.collapsed == item.collapsed and unit.visible, "Destroyed physical scenery retains visible rubble")
		StatusHelper.compare(h, simulation.hazard_blockers, item.blockers, "Collapse changes only the first co-located blocker")
		var fires: Array = []
		if not item.capped:
			for fire: Dictionary in simulation.fire_fields:
				fires.append({"kind": fire.kind, "scale": fire.scale, "ttl": fire.ttl})
		StatusHelper.compare(h, fires, item.fires, "Original collapsed scenery and vehicle fire cap")
		h._check(simulation.rng.state == random_state, "Collapse presentation and fire use no combat randomness")
		simulation.free()
	for item: Dictionary in fixtures.sceneLoot:
		var random := SourceRng.new(int(item.seed))
		StatusHelper.compare(h, SceneRules.loot_plan(random, 12, -8, item.treasure), item.result, "Original loot tiers, rare overflow and mirrored scatter")
		check_draws(h, random, int(item.seed), int(item.draws))
	for item: Dictionary in fixtures.scenePickups:
		var simulation := SceneSimulation.new()
		h.add_child(simulation)
		simulation.set_physics_process(false)
		simulation.clock = 10
		var loot := {"id": 50, "position": Vector3.ZERO, "ttl": item.lifetime}
		if item.reward == "ammo":
			loot.ammo = true
		elif item.reward == "cash":
			loot.value = 50
		else:
			loot.affix = item.reward
		simulation.loots.append(loot)
		for id in [1, 2]:
			var unit := StatusHelper.actor(simulation, {"id": id, "character": "t05", "kind": "robot", "side": "STEEL" if id == 1 else "SWARM",
				"position": [0, 0, 0], "hp": 100, "relative_altitude": item.altitude if id == 1 else 0,
				"ammo": {"light": 0, "heavy": 0}, "reload_at": {"light": 20, "heavy": 20}})
			unit.money = 0
			if Content.constants.AFFIXES.has(item.reward):
				unit.buffs.append({"affix": item.reward, "until": 11, "mul": {}})
		var random_state := simulation.rng.state
		simulation._tick_loots(0.125)
		h._check(simulation.loots.size() == int(item.remaining), "Loot expiration precedes source pickup eligibility")
		var reports: Array = simulation.events.filter(func(event): return event.type == "loot")
		h._check((0 if reports.is_empty() else int(reports[0].actor)) == int(item.winner), "Original insertion-order pickup and inclusive altitude ceiling")
		for expected: Dictionary in item.actors:
			var unit: BattleUnit = simulation.units[int(expected.id)]
			h._near(unit.money, expected.money, "Loot credits the first eligible pilot across factions")
			var buffs := {}
			for buff: Dictionary in unit.buffs:
				if buff.has("affix"):
					buffs[buff.affix] = buff.until
			StatusHelper.compare(h, buffs, expected.buffs, "Same affix refreshes its source deadline without stacking")
			for slot: String in ["light", "heavy"]:
				var capacity: float = Content.weapon(unit.character, slot).mag
				h._near(float(unit.ammo.get(slot, capacity)), capacity if expected.ammoCleared else 0, "Ammo loot uses the source lazy-refill magazine result")
			h._check(unit.reload_at.is_empty() == expected.reloadCleared, "Ammo loot cancels both reloads")
		h._check(simulation.rng.state == random_state, "Loot pickup does not roll combat randomness")
		simulation.free()
	for item: Dictionary in fixtures.sceneMines:
		var simulation := ThreatSimulation.new()
		h.add_child(simulation)
		simulation.set_physics_process(false)
		simulation.clock = 10
		var hero := StatusHelper.actor(simulation, {"id": 1, "character": item.character, "kind": item.kind, "side": "STEEL", "position": [0, 0, 0], "relative_altitude": item.altitude})
		hero.status.third_cooldown_until = item.cooldown
		StatusHelper.actor(simulation, {"id": 2, "character": "", "kind": "soldier", "side": "SWARM", "position": [12, 0, 0]})
		var drone: String = Content.heroes.keys().filter(func(id): return Content.heroes[id].kind == "drone")[0]
		StatusHelper.actor(simulation, {"id": 3, "character": drone, "kind": "drone", "side": "SWARM", "position": [0, 0, 0], "relative_altitude": float(Content.constants.GAME.MINES.R) + 0.001})
		simulation.mines = [{"id": 6, "x": 0, "z": 0}, {"id": 7, "x": 0, "z": 0}]
		var random_state := simulation.rng.state
		simulation._tick_mines()
		StatusHelper.compare(h, simulation.hits, item.hits, "Original mine planar blast has no body-radius expansion or airborne hero coverage")
		StatusHelper.compare(h, simulation.mines, item.remaining, "One latest mine triggers per eligible pilot")
		h._near(float(hero.status.third_cooldown_until), item.until, "Mine and AA ambush share the source threat cooldown")
		var reports: Array = simulation.events.filter(func(event): return event.type == "mine_blast")
		h._check((0 if reports.is_empty() else int(reports[0].mine)) == int(item.mine), "Source reverse-order mine trigger")
		h._check(simulation.rng.state == random_state, "Mine triggers consume no combat randomness")
		simulation.free()
	for item: Dictionary in fixtures.sceneAmbush:
		var simulation := ThreatSimulation.new()
		h.add_child(simulation)
		simulation.set_physics_process(false)
		simulation.clock = 10
		simulation.rng = SourceRng.new(int(item.seed))
		simulation.world = BattleWorld.new()
		simulation.add_child(simulation.world)
		simulation.world.lane_points = [[[0, 0], [1400, 0]]]
		var hero := StatusHelper.actor(simulation, {"id": 1, "character": item.character, "kind": item.kind, "side": "STEEL", "position": [500, 0, 0 if item.gate == "corridor" else -200], "relative_altitude": item.altitude})
		if item.gate == "cooldown":
			hero.status.third_cooldown_until = 11
		if item.gate == "stealth":
			hero.status.stealth_until = 11
		if item.gate != "noSite":
			for id in [50, 51]:
				var site := BattleUnit.new()
				simulation.add_child(site)
				site.kind = "aasite"
				site.entity_id = id
				site.hp = Content.constants.FIELD.AA_SITE.hp
				site.position = Vector3(500, 0, -200)
				simulation.units[id] = site
		if item.gate == "full":
			simulation.missiles.append({"ambush": true})
		simulation._tick_ambush(1)
		h._near(float(hero.status.get("third_cooldown_until", 0)), item.result.until, "Original AA height, corridor, cooldown and stealth gates")
		StatusHelper.compare(h, simulation.launched, item.result.launched, "Original AA site stable ties and shared interceptable missile launch")
		check_draws(h, simulation.rng, int(item.seed), int(item.draws))
		simulation.free()
	for item: Dictionary in fixtures.sceneRelays:
		var simulation := ThreatSimulation.new()
		h.add_child(simulation)
		simulation.set_physics_process(false)
		for id in [1, 2]:
			StatusHelper.actor(simulation, {"id": id, "character": "t05", "kind": "robot", "side": "STEEL" if id == 1 else "SWARM", "position": [0, 0, 0]})
		for id in [50, 51]:
			simulation.relay_states.append({"id": id, "position": Vector3.ZERO, "charge": 0.0, "side": ""})
			if not item.pruned:
				var relay := BattleUnit.new()
				simulation.add_child(relay)
				relay.kind = "relay"
				relay.entity_id = id
				simulation.units[id] = relay
		var random_state := simulation.rng.state
		for step: Dictionary in item.steps:
			simulation.clock = step.now
			simulation.events.clear()
			for index in range(2):
				simulation.units[index + 1].position.x = step.positions[index]
			simulation._tick_relays(step.delta)
			var relays: Array = simulation.relay_states.map(func(relay): return {"id": relay.id, "charge": relay.charge, "side": relay.side})
			StatusHelper.compare(h, relays, step.relays, "Original relay contested decay, side-switch reset and reverse capture order")
			StatusHelper.compare(h, simulation.vision_until, step.vision, "One-time relay grants source whole-team vision deadline")
			StatusHelper.compare(h, simulation.events, step.events, "Relay capture event ordering")
			h._check(simulation.units.size() - 2 == int(step.entities), "Captured relay disappears, including a previously pruned source actor")
			h._check(simulation.rng.state == random_state, "Relay capture consumes no combat randomness")
		simulation.free()
	print("SCENE_REFERENCE_PASS math=", fixtures.sceneMath.size(), " generation=", fixtures.sceneGeneration.size(), " collapse=", fixtures.sceneCollapse.size(), " loot=", fixtures.sceneLoot.size(), " pickup=", fixtures.scenePickups.size(), " mines=", fixtures.sceneMines.size(), " ambush=", fixtures.sceneAmbush.size(), " relays=", fixtures.sceneRelays.size())
	var presentation := LootPresentation.new()
	h.add_child(presentation)
	presentation.set_process(false)
	var current_kind := ""
	for item: Dictionary in fixtures.lootVisuals:
		if current_kind != item.kind:
			presentation.sync([], 0)
			current_kind = item.kind
			var state := {"id": 1, "position": Vector3(12, 7, -8)}
			if item.kind == "ammo":
				state.ammo = true
			elif item.kind == "affix":
				state.affix = "fixture"
			presentation.sync([state], 0)
			if presentation.entries.has(1):
				preload("res://tests/outline_suite.gd").check_deferred(h, presentation.entries[1].root)
		if not presentation.entries.has(1):
			h._check(false, "Pack original loot scenes before final presentation verification")
			continue
		presentation.clock = float(item.now) - float(item.delta)
		presentation._process(item.delta)
		var entry: Dictionary = presentation.entries[1]
		var rotation: Vector3 = entry.root.rotation
		var body: Vector3 = entry.body.position
		h._check(rotation.distance_to(Vector3(item.rotation[0], item.rotation[1], item.rotation[2])) < 0.000001, "Original loot rotation preserves cumulative frame time")
		h._check(body.distance_to(Vector3(item.body[0], item.body[1], item.body[2])) < 0.000001, "Original first-child loot float leaves its halo anchored")
	presentation.sync([], 12)
	h._check(presentation.entries.is_empty(), "Picked-up loot is removed from native presentation")
	presentation.free()
	for item: Dictionary in fixtures.sceneCollapsePoses:
		var pose := SceneRules.collapse_pose(int(item.id), Vector3(item.scale[0], item.scale[1], item.scale[2]), Vector3(item.rotation[0], item.rotation[1], item.rotation[2]), item.progress)
		for property: String in ["scale", "rotation"]:
			var expected: Array = item.result[property]
			var actual: Vector3 = pose[property]
			h._check(actual.distance_to(Vector3(expected[0], expected[1], expected[2])) < 0.000001, "Original rubble pose, ID parity and quadratic remaining-time curve")
		h._near(12 * float(Content.constants.SCENE_STRUCT.RUBBLE_F), item.radius, "Original collapse radius multiplier")
		h._near(6 * 0.35, item.height, "Original collapse height multiplier")
	var mine_view := MinePresentation.new()
	h.add_child(mine_view)
	mine_view.sync([{"id": 1, "position": Vector3(0, 0.05, 0)}])
	for item: Dictionary in fixtures.mineVisuals:
		if not mine_view.entries.has(1):
			h._check(false, "Pack original mine scene before final visual verification")
			continue
		mine_view.update_view(Vector3(item.observer[0], item.observer[1], item.observer[2]), item.now)
		var visual: MeshInstance3D = mine_view.entries[1]
		h._check(visual.visible == item.visible, "Original mine distance visibility preserves the 0.12-second throttle")
		var material: StandardMaterial3D = visual.mesh.surface_get_material(0)
		h._check(absf(material.albedo_color.a - float(item.opacity)) < 0.00001, "Original mine opacity uses full 3D distance and inclusive clear boundary")
	mine_view.sync([])
	h._check(mine_view.entries.is_empty(), "Triggered mine is removed from native presentation")
	mine_view.free()

static func check_draws(h: Node, random: SourceRng, seed_value: int, count: int) -> void:
	var expected := SourceRng.new(seed_value)
	for index in range(count):
		expected.next()
	h._check(random.state == expected.state, "Original independent generation or combat loot draw count")
