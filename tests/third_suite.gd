extends RefCounted

const StatusHelper = preload("res://tests/status_suite.gd")

class ThirdSimulation extends BattleSimulation:
	var placement: Dictionary = {"bounds": {"minX": -1000, "maxX": 3000, "minZ": -1400, "maxZ": 1400}, "lanes": [[[0, 0], [2000, 0]]],
		"bases": {"SWARM": [0, 0], "STEEL": [2000, 0]}, "towers": [], "blockers": []}
	var spawns: Array = []
	var rewards: Array = []
	var capture_rewards := false
	var capture_release := false
	var released := 0
	var terrain_mode := "none"

	func spawn(info: Dictionary, _replica: bool = false) -> BattleUnit:
		var unit := BattleUnit.new()
		add_child(unit)
		unit.entity_id = next_id
		next_id += 1
		unit.kind = info.kind
		unit.side = info.side
		unit.special = info.special.duplicate(true)
		unit.position = info.position
		unit.hp = Content.constants.UNITS[unit.kind].hp
		unit.max_hp = unit.hp
		unit.hit_area = Area3D.new()
		unit.add_child(unit.hit_area)
		units[unit.entity_id] = unit
		spawns.append({"kind": unit.kind, "slot": unit.special.get("slot", 0)})
		return unit

	func _civilian_placement() -> Dictionary:
		return placement

	func _terrain_blocked(_x: float, z: float) -> bool:
		return terrain_mode == "all" or terrain_mode == "north" and z < 0

	func _set_scalar_point(unit: BattleUnit, point: Dictionary) -> void:
		unit.position = Vector3(point.x, 0, point.z)

	func _grant_reward(unit: BattleUnit, reward: String, multiplier: float) -> Dictionary:
		if capture_rewards:
			rewards.append({"peer": unit.peer_id, "reward": reward, "multiplier": multiplier})
			return {"reward": reward, "hp": 1, "shield": 2}
		return super._grant_reward(unit, reward, multiplier)

	func _free_camp_civilians(camp: Dictionary, attacker: BattleUnit) -> void:
		if capture_release:
			released += 1
		else:
			super._free_camp_civilians(camp, attacker)

static func run(h: Node, fixtures: Dictionary) -> void:
	for key: String in ["campClearance", "campClearCache", "campSeeds", "campHomes", "campBehavior", "campAggro", "campMoves", "campTimers", "campDeaths", "campRelease", "thirdDamage", "civilianBodies", "civilianPoints", "civilianWander", "civilianMoves", "civilianSpawns", "civilianSeeds", "civilianRespawns", "civilianInteractions", "civilianTicks", "civilianDeaths"]:
		if not fixtures.has(key):
			h._check(false, "Regenerate original third-party/civilian references before final verification: " + key)
			return
	for item: Dictionary in fixtures.campClearance:
		var clearance := CampRules.clearance(item.obstacles, item.camps)
		StatusHelper.compare(h, clearance.removed, item.result.removed, "Original camp clearance uses legacy pillar centres and whole keyed-building bounds")
		StatusHelper.compare(h, clearance.buildings.keys(), item.result.buildings, "Camp clearance removes every volume of a grouped building")
		var kept: Array = []
		for index in range(item.obstacles.size()):
			if index not in clearance.removed:
				kept.append(item.obstacles[index])
		StatusHelper.compare(h, kept, item.result.kept, "Original normalized weather/LOS obstacles after camp clearance")
	for item: Dictionary in fixtures.campClearCache:
		var world := BattleWorld.new()
		h.add_child(world)
		var data := NativeWorldData.new()
		data.water_profile = {"obstacles": []}
		data.columns = [{"x": 0, "z": 0, "r": 12}, {"x": 2, "z": 2, "r": 1}]
		world.native_data = data
		for point: Array in item.points:
			world.clear_camp_columns([{"x": point[0], "z": point[1]}])
		StatusHelper.compare(h, world.cleared_camps, item.calls.map(func(call): return {"x": call.x, "z": call.z}), "Original client bunker discovery cache keeps first point per rounded position, including negative half ties")
		h._check(world.active_columns.size() == data.columns.size(), "Client clearance preserves unkeyed bridge and vegetation collision")
		world.free()
	for item: Dictionary in fixtures.campSeeds:
		var random := SourceRng.new(int(item.seed))
		var blocked := func(_x, z): return item.terrain == "all" or item.terrain == "north" and z < 0
		StatusHelper.compare(h, CampRules.seed(random, item.state, blocked), item.result, "Original two-round camp sampling, topology/structure clearance and stable best candidate")
		check_draws(h, random, int(item.seed), int(item.draws))
	for item: Dictionary in fixtures.campHomes:
		StatusHelper.compare(h, CampRules.home(item.camp, int(item.slot)), item.result, "Original camp slot arc preserves the exit side")
	for item: Dictionary in fixtures.campBehavior:
		StatusHelper.compare(h, CampRules.behavior(item.state, item.camp, int(item.occupancy), 0.125), item.result, "Original camp garrison capacity/healing, half-health entry, tether and home boundaries")
	for item: Dictionary in fixtures.campAggro:
		h._check(CampRules.aggro_valid(item.state, item.target, 10) == item.result, "Original aggro deadline, death, faction and stealth invalidation")
	for item: Dictionary in fixtures.campMoves:
		var blocked := func(x, _z): return item.terrain == "inside" or item.terrain == "enter" and x != 50
		StatusHelper.compare(h, CampRules.move(item.state, item.camp, item.profile, item.target, 0.125, blocked, item.blockers), item.result, "Original third-party retreat/seek/chase/home priority, CC and ground-only avoidance")
	for item: Dictionary in fixtures.campTimers:
		var simulation := create(h)
		simulation.camps.append({"side": "GUER", "lane": 0, "x": 0, "z": 0, "exit_angle": 0.3, "bunker": 50 if item.bunker else 0,
			"bunker_remaining": 0.2, "pool": [{"kind": "soldier", "slot": 2, "remaining": 0.1}, {"kind": "tank", "slot": 4, "remaining": 0.3}]})
		for step: Dictionary in item.steps:
			simulation.spawns.clear()
			simulation._tick_camps(step.delta)
			var camp: Dictionary = simulation.camps[0]
			h._check(bool(camp.bunker) == step.bunker, "Bunker rebuild is independent of member respawn timers")
			h._near(camp.bunker_remaining, step.remaining, "Original bunker deadline")
			StatusHelper.compare(h, camp.pool, step.pool, "Member countdown pauses without a bunker, including its rebuild tick")
			StatusHelper.compare(h, simulation.spawns, step.spawns, "Original reverse respawn pool order")
		simulation.free()
	for item: Dictionary in fixtures.campDeaths:
		var simulation := create(h)
		simulation.capture_release = true
		simulation.camps.append({"side": "GUER", "lane": 0, "x": 0, "z": 0, "exit_angle": 0.3, "bunker": 50, "bunker_remaining": 0.0, "pool": [], "freed": item.freed})
		var dead := simulation._spawn_camp_unit(0, item.kind, 1)
		simulation.units.erase(dead.entity_id)
		if not item.cleared:
			var member := simulation._spawn_camp_unit(0, "soldier", 1)
			member.special.garrison = true
			member.hp = 50
			member.max_hp = 100
		simulation._on_third_death(dead, null)
		var camp: Dictionary = simulation.camps[0]
		h._check(bool(camp.bunker) == item.result.bunker and camp.freed == item.result.freed and simulation.released == int(item.result.released), "First complete camp clear releases civilians only once")
		h._near(camp.bunker_remaining, item.result.remaining, "Source third-party death schedules bunker rebuild")
		StatusHelper.compare(h, camp.pool, item.result.pool, "Source member death retains kind and slot")
		if not item.cleared:
			var member: BattleUnit = simulation.units.values()[0]
			h._check(bool(member.special.garrison) == item.result.roster[0].garrison, "Destroyed bunker forcibly ungarrisons surviving members")
			StatusHelper.compare(h, {"x": member.position.x, "z": member.position.z}, {"x": item.result.roster[0].x, "z": item.result.roster[0].z}, "Forced ungarrison returns to its source slot")
		simulation.free()
	for item: Dictionary in fixtures.campRelease:
		var simulation := create(h)
		var first := hero(simulation, 1, "STEEL", item.owner == "none")
		first.position.x = 10
		var second := hero(simulation, 2, "SWARM", item.owner == "none")
		second.position.x = 20
		var attacker: BattleUnit = second if item.owner == "hero" else null
		if item.owner == "dead":
			attacker = hero(simulation, 3, "SWARM", true)
		elif item.owner == "npc":
			attacker = StatusHelper.actor(simulation, {"id": 3, "character": "", "kind": "soldier", "side": "STEEL", "position": [0, 0, 0], "hp": 100})
		simulation.next_id = 100
		simulation._free_camp_civilians({"x": 0, "z": 0}, attacker)
		var civilians: Array = []
		for unit: BattleUnit in simulation.units.values():
			if unit.special.get("role") == "civilian":
				civilians.append({"side": unit.special.civil_side, "spy": unit.special.spy, "profession": unit.special.profession,
					"x": unit.position.x, "z": unit.position.z, "follow": unit.special.follow_peer, "noRespawn": unit.special.no_respawn,
					"home": [unit.special.home.x, unit.special.home.y], "pause": unit.special.pause})
		StatusHelper.compare(h, civilians, item.result, "Original liberated civilian side/profession/pause draws, no-respawn flag and owner fallback")
		if item.event == null:
			h._check(simulation.events.is_empty(), "No living owner means no source civilian-release message")
		else:
			StatusHelper.compare(h, simulation.events[0], item.event, "Liberated civilians report their source owner")
		check_draws(h, simulation.rng, 42, int(item.draws))
		simulation.free()
	for item: Dictionary in fixtures.thirdDamage:
		var simulation := create(h)
		var attacker: BattleUnit
		if item.attackerSide == "STEEL":
			attacker = hero(simulation, 1, "STEEL")
		else:
			attacker = simulation.spawn({"kind": "soldier", "side": item.attackerSide, "position": Vector3.ZERO, "special": {}})
		attacker.special.neutral = item.neutral
		var target := simulation.spawn({"kind": item.kind, "side": item.targetSide, "position": Vector3(10, 0, 0),
			"special": {"third": item.targetSide in ["GUER", "MILI"], "garrison": item.garrison, "aggro_id": 0, "aggro_at": 0.0}})
		target.hp = 100
		target.armor = 0
		simulation.damage(attacker, target, {}, 10, true, {}, false)
		StatusHelper.compare(h, {"hp": target.hp, "aggro": target.special.aggro_id, "aggro_at": target.special.aggro_at,
			"assists": target.assists.keys(), "focus": attacker.last_hit_target}, item.result, "Original garrison and super/third immunity precedes aggro, assists and focus; incidental third/third damage remains valid")
		simulation.free()
	for item: Dictionary in fixtures.civilianBodies:
		StatusHelper.compare(h, CivilianRules.body(int(item.seed)), item.body, "Per-entity civilian body RNG is separate from appearance and combat")
		StatusHelper.compare(h, CivilianRules.appearance(int(item.seed), int(item.profession)), item.appearance, "Original civilian appearance draw order and age/gender short circuits")
		var body := CivilianRules.body(int(item.seed))
		h._near(float(Content.constants.TARGET_R.civ) * float(body.radiusScale), item.radius, "Original civilian body hit radius")
		h._near(float(Content.constants.TARGET_H.civ) * float(body.heightScale), item.height, "Original civilian body hit height")
	for item: Dictionary in fixtures.civilianSpawns:
		var simulation := create(h)
		simulation.next_id = int(item.result.id)
		var civilian := simulation._spawn_civilian(item.side, item.spy, int(item.profession), {"x": 10, "z": -100})
		StatusHelper.compare(h, civilian_state(civilian), item.result, "Original civilian spawn fields and one initial pause draw")
		h._check(civilian.special.waypoint == null, "New civilians have no fabricated first waypoint")
		h._near(CivilianRules.speed(item.spy), item.speed, "Original spy and civilian speed")
		check_draws(h, simulation.rng, 42, int(item.draws))
		simulation.free()
	for item: Dictionary in fixtures.civilianSeeds:
		var simulation := create(h)
		simulation.placement = item.state.duplicate(true)
		simulation.terrain_mode = item.terrain
		simulation.rng = SourceRng.new(int(item.seed))
		if not item.result.is_empty():
			simulation.next_id = int(item.result[0].id)
		simulation._seed_civilians()
		StatusHelper.compare(h, simulation.units.values().map(civilian_state), item.result, "Original side-first civilian roster, spy slots and placement/profession/pause draw order")
		check_draws(h, simulation.rng, int(item.seed), int(item.draws))
		simulation.free()
	for item: Dictionary in fixtures.civilianRespawns:
		var simulation := create(h)
		simulation.terrain_mode = item.terrain
		simulation.civilian_respawns = [{"side": "STEEL", "spy": true, "at": 10}, {"side": "SWARM", "spy": false, "at": 11}, {"side": "SWARM", "spy": true, "at": 9}]
		if not item.result.actors.is_empty():
			simulation.next_id = int(item.result.actors[0].id)
		simulation._tick_civilians(0.125)
		StatusHelper.compare(h, simulation.units.values().map(civilian_state), item.result.actors, "Original respawn keeps spy/allegiance, rerolls profession and ticks fresh civilians immediately")
		StatusHelper.compare(h, simulation.civilian_respawns, item.result.pending, "Expired placement failures stay in original queue order for the next tick")
		check_draws(h, simulation.rng, 42, int(item.draws))
		simulation.free()
	for item: Dictionary in fixtures.civilianPoints:
		var random := SourceRng.new(int(item.seed))
		var blocked := func(_x, z): return item.terrain == "all" or item.terrain == "north" and z < 0
		var point := CivilianRules.point(random, item.state, blocked)
		if item.result == null:
			h._check(point.is_empty(), "Civilian placement keeps failure explicit")
		else:
			StatusHelper.compare(h, point, item.result, "Original civilian placement clearance and terrain gate")
		check_draws(h, random, int(item.seed), int(item.draws))
	for item: Dictionary in fixtures.civilianWander:
		var random := SourceRng.new(int(item.seed))
		var blocked := func(_x, z): return item.terrain == "all" or item.terrain == "north" and z < 0
		StatusHelper.compare(h, CivilianRules.wander(random, item.state, Vector2(item.home[0], item.home[1]), blocked), item.result, "Original twelve-attempt civilian wander returns home on exhaustion")
		check_draws(h, random, int(item.seed), int(item.draws))
	for item: Dictionary in fixtures.civilianMoves:
		var blocked := func(x, _z): return item.terrain == "all" or item.terrain == "enter" and x != 0
		var point := CivilianRules.move({"x": 0, "z": 0}, Vector2(item.goal[0], item.goal[1]), 100, 10, item.bounds, blocked, item.away)
		h._check(not point.is_empty() == item.moved, "Original civilian movement retains the near-zero and hazard-edge gates")
		if not point.is_empty():
			StatusHelper.compare(h, point, item.result, "Original civilian away direction, planar yaw and four-meter boundary clamp")
	for item: Dictionary in fixtures.civilianInteractions:
		var simulation := create(h)
		var owner := hero(simulation, 1, "STEEL", item.dead)
		var civilian := simulation._spawn_civilian("SWARM", false, 0, {"x": item.distance, "z": 0})
		civilian.special.follow_peer = 2
		civilian.special.follow_time = 100.0
		civilian.special.flee = true
		civilian.special.flee_ttl = 3.0
		civilian.special.flee_point = Vector2(1, -2)
		simulation._civilian_interact(owner, civilian.entity_id, item.action)
		var state: Dictionary = civilian.special
		StatusHelper.compare(h, {"follow": state.follow_peer, "follow_time": state.follow_time, "flee": state.flee, "flee_ttl": state.flee_ttl,
			"flee_point": [state.flee_point.x, state.flee_point.y]}, item.result, "Original civilian interaction radius, dead gate and follow/away reset")
		StatusHelper.compare(h, simulation.events, item.events, "Original civilian interaction reports")
		simulation.free()
	for item: Dictionary in fixtures.civilianTicks:
		var simulation := create(h)
		simulation.capture_rewards = true
		var owner := hero(simulation, 1, "STEEL", item.mode == "dead")
		owner.position.x = 300 if item.mode == "lost" else 30
		simulation.next_id = 50
		var civilian := simulation._spawn_civilian("SWARM" if item.mode == "enemy" else "STEEL", false, 0, {"x": 0, "z": -100})
		simulation.rng = SourceRng.new(42)
		civilian.special.pause = 0.0
		civilian.special.follow_peer = 1 if item.mode in ["follow", "enemy", "lost", "dead", "aid"] else 0
		civilian.special.follow_time = float(Content.constants.CIVILIAN.FOLLOW_REWARD_S) - 0.1 if item.mode == "aid" else 0.0
		civilian.special.flee = item.mode.begins_with("flee")
		civilian.special.flee_ttl = 0.05 if item.mode == "fleeExpired" else 1.0
		civilian.special.flee_point = Vector2(20, -100)
		simulation._tick_civilians(0.125)
		var actors: Array = []
		for unit: BattleUnit in simulation.units.values():
			if unit.special.get("role") == "civilian":
				var state: Dictionary = unit.special
				actors.append({"id": unit.entity_id, "x": unit.position.x, "z": unit.position.z, "yaw": unit.yaw, "follow": state.follow_peer,
					"follow_time": state.follow_time, "flee": state.flee, "flee_ttl": state.flee_ttl, "pause": state.pause,
					"waypoint": {"x": state.waypoint.x, "z": state.waypoint.y} if state.waypoint != null else null})
		StatusHelper.compare(h, actors, item.result.actors, "Original civilian flee/follow/lost-owner/wander priority")
		StatusHelper.compare(h, simulation.rewards, item.result.rewards, "Only allied followers receive periodic profession rewards")
		StatusHelper.compare(h, simulation.events, item.result.events, "Civilian aid event owner and profession")
		check_draws(h, simulation.rng, 42, int(item.draws))
		simulation.free()
	for item: Dictionary in fixtures.civilianDeaths:
		var simulation := create(h)
		var killer := hero(simulation, 1, "STEEL")
		killer.money = 10
		var civilian := simulation._spawn_civilian(item.side, item.spy, 0, {"x": 0, "z": 0})
		civilian.special.no_respawn = item.noRespawn
		simulation._kill_civilian(civilian, killer)
		h._near(killer.money, item.result.money, "Original civilian/spy kill credits clamp money without battle score")
		StatusHelper.compare(h, simulation.civilian_respawns, item.result.respawns, "Civilian respawn keeps allegiance and spy identity; liberated civilians remain gone")
		StatusHelper.compare(h, simulation.events.map(func(event): return "die" if event.type == "die" else event.type), item.result.events, "Original die then civilian-identity reveal ordering")
		var reports: Array = simulation.events.filter(func(event): return event.type == "civkill")
		h._near(reports[0].value, item.result.value, "Original signed civilian kill rounding")
		simulation.free()
	var privacy := create(h)
	var civilian := privacy._spawn_civilian("SWARM", true, 3, {"x": 0, "z": 0})
	var wire: Dictionary = bytes_to_var(var_to_bytes(civilian.snapshot()))
	h._check(not wire.special.has("spy") and not wire.special.has("home") and not wire.special.has("waypoint"), "Civilian wire snapshots never expose spy or private AI state")
	privacy.authoritative = false
	var owner := hero(privacy, 2, "STEEL")
	privacy._civilian_interact(owner, civilian.entity_id, "follow")
	h._check(civilian.special.follow_peer == 0 and privacy.events.is_empty(), "Replica cannot settle civilian interaction")
	var state := civilian_state(civilian)
	var draws := privacy.rng.state
	privacy._tick_civilians(10)
	privacy._seed_civilians()
	privacy._free_camp_civilians({"x": 0, "z": 0}, owner)
	privacy.camps.append({"bunker": 0, "bunker_remaining": 0.1, "pool": []})
	privacy._tick_camps(10)
	StatusHelper.compare(h, civilian_state(civilian), state, "Replica cannot advance civilian AI or reward clocks")
	h._check(privacy.units.size() == 2 and privacy.rng.state == draws and privacy.camps[0].bunker_remaining == 0.1, "Replica cannot generate civilian rosters or respawn camp members")
	privacy.free()
	var garrison := BattleUnit.new()
	h.add_child(garrison)
	garrison.kind = "soldier"
	garrison.hp = 100
	garrison.radius = 1
	garrison.height = 2
	garrison.movement_shape = CollisionShape3D.new()
	garrison.add_child(garrison.movement_shape)
	garrison.hit_area = Area3D.new()
	garrison.add_child(garrison.hit_area)
	garrison.special.garrison = true
	garrison.refresh_collision()
	h._check(garrison.movement_shape.shape != null and garrison.collision_layer == 0 and garrison.hit_area.collision_layer == 0, "First-seen garrison has a shape while its body and hit layers remain disabled")
	garrison.special.garrison = false
	garrison.refresh_collision()
	h._check(garrison.hit_area.collision_layer == 2, "Ungarrison restores its source hit layer")
	garrison.free()
	print("THIRD_REFERENCE_PASS seed=", fixtures.campSeeds.size(), " behavior=", fixtures.campBehavior.size(), " move=", fixtures.campMoves.size(), " civilians=", fixtures.civilianTicks.size())

static func create(h: Node) -> ThirdSimulation:
	var simulation := ThirdSimulation.new()
	h.add_child(simulation)
	simulation.set_physics_process(false)
	simulation.clock = 10
	simulation.authority_bounds = simulation.placement.bounds
	return simulation

static func hero(simulation: BattleSimulation, id: int, side: String, dead: bool = false) -> BattleUnit:
	return StatusHelper.actor(simulation, {"id": id, "character": "t05", "kind": "robot", "side": side, "position": [0, 0, 0], "hp": 0 if dead else 100})

static func civilian_state(unit: BattleUnit) -> Dictionary:
	var state: Dictionary = unit.special
	return {"id": unit.entity_id, "x": unit.position.x, "z": unit.position.z, "yaw": unit.yaw,
		"follow": state.follow_peer, "follow_time": state.follow_time, "flee": state.flee, "flee_ttl": state.flee_ttl, "pause": state.pause,
		"waypoint": {"x": state.waypoint.x, "z": state.waypoint.y} if state.waypoint != null else null,
		"side": state.civil_side, "spy": state.spy, "profession": state.profession, "hp": unit.hp, "max_hp": unit.max_hp,
		"home": [state.home.x, state.home.y], "neutral": bool(state.neutral), "public_side": unit.side}

static func check_draws(h: Node, random: SourceRng, seed_value: int, count: int) -> void:
	var expected := SourceRng.new(seed_value)
	for index in range(count):
		expected.next()
	h._check(random.state == expected.state, "Original third-party/civilian RNG draw count")
