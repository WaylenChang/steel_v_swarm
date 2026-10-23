extends RefCounted

const StatusHelper = preload("res://tests/status_suite.gd")

class CompanionSimulation extends BattleSimulation:
	var recording := false
	var hits: Array = []
	var controls: Array = []
	var order: Array[int] = []

	func _place_solid(unit: BattleUnit, offset: Vector2) -> void:
		unit.position += Vector3(offset.x, 0, offset.y)

	func _missile_target_altitude(unit: BattleUnit) -> float:
		return unit.position.y

	func _unit_level(_unit: BattleUnit) -> int:
		return 0

	func damage(owner: BattleUnit, target: BattleUnit, definition: Dictionary, amount: float,
			friendly: bool = false, context: Dictionary = {}, attack_modifiers: bool = true) -> void:
		if recording:
			hits.append({"target": target.entity_id, "actor": order.find(owner.entity_id), "amount": amount, "pen": definition.get("pen", 0)})
		else:
			super.damage(owner, target, definition, amount, friendly, context, attack_modifiers)

	func _apply_cc(owner: BattleUnit, added: Dictionary, center: Vector3, radius: float) -> void:
		if recording:
			controls.append({"effect": added.fx, "duration": added.dur, "position": [center.x, 0, center.z], "radius": radius})
		else:
			super._apply_cc(owner, added, center, radius)

static func run(h: Node, fixtures: Dictionary) -> void:
	for key: String in ["companionClones", "companionTargeting", "companionSummons", "companionCombat", "companionDeaths", "companionGeometry", "companionFrames"]:
		if not fixtures.has(key):
			h._check(false, "Regenerate original companion oracle: " + key)
			return
	for item: Dictionary in fixtures.companionClones:
		var simulation := context(h)
		var owner := pilot(simulation, 1, item.character)
		owner.yaw = item.yaw
		owner.upgrades.atk = int(item.level) - 1
		var definition := Content.ability(item.character, "atk", int(item.level))
		simulation._cast_effect(owner, definition, owner.position, item.fraction)
		compare_roster(h, simulation, owner.clone_ids, item.first.actors, "Original clone spawn")
		compare_timers(h, owner, item.first.timers)
		for id: int in owner.clone_ids:
			var clone: BattleUnit = simulation.units[id]
			h._check(clone.is_hero() and not clone.is_pilot() and clone.camera == null and clone.weapon_pose == null,
				"Clone keeps hero damage rules without player input, camera or a respawn seat")
		h._check(simulation.pilots.size() == 1 and simulation.pilots[1] == owner, "Clone never replaces its owner's control binding")
		simulation._cast_effect(owner, definition, owner.position, item.fraction, false)
		compare_roster(h, simulation, owner.clone_ids, item.repeated.actors, "Once-only clone producer")
		compare_timers(h, owner, item.repeated.timers)
		simulation._cast_effect(owner, definition, owner.position, item.fraction)
		compare_roster(h, simulation, owner.clone_ids, item.recast.actors, "Original clone recast replacement")
		compare_timers(h, owner, item.recast.timers)
		simulation._tick_clones(0.1)
		compare_roster(h, simulation, owner.clone_ids, item.after, "Original recast timer clearing and immediate expiry")
		compare_timers(h, owner, item.afterTimers)
		simulation.free()
	for item: Dictionary in fixtures.companionTargeting:
		var simulation := context(h)
		var owner := pilot(simulation, 1, "t05")
		owner.last_hit_target = int(item.focus)
		var first := pilot(simulation, 2, "s09", "SWARM", Vector3(item.distance, 0, 0))
		if item.dead:
			first.hp = 0
		npc(simulation, 3, "tower", "SWARM", Vector3(120, 0, 0))
		npc(simulation, 4, "soldier", "SWARM", Vector3(40, 0, 0))
		pilot(simulation, 5, "s09", "SWARM", Vector3(item.distance, 0, 0))
		var unit := npc(simulation, 8, "main_battle_tank", "STEEL", Vector3.ZERO)
		unit.special = {"sight": item.sight}
		var target := simulation._auto_target(unit, owner)
		h._check((target.entity_id if target != null else 0) == int(item.target), "Original owner focus, additive priorities, sight boundary and stable ties")
		simulation.free()
	for item: Dictionary in fixtures.companionSummons:
		var simulation := context(h)
		var owner := pilot(simulation, 1, "t05")
		owner.upgrades.atk = int(item.level) - 1
		var definition := {"id": "atk", "unit": item.kind, "count": 2}
		simulation._spawn_autonomous_summons(owner, definition, Vector3(20, 0, 30), item.fraction,
			int(item.countOverride) if item.countOverride != null else -1)
		compare_roster(h, simulation, simulation.autonomous_summons, item.actors, "Original summon scaled stats, polar offsets and altitudes")
		StatusHelper.check_draws(h, simulation, int(item.draws))
		for id: int in simulation.autonomous_summons:
			h._check(simulation.units[id].path_follower == null and not simulation.units[id].has_lane, "Autonomous summons do not consume a creep lane slot")
		simulation.free()
	for item: Dictionary in fixtures.companionCombat:
		combat(h, item)
	for item: Dictionary in fixtures.companionDeaths:
		deaths(h, item)
	replica_binding(h)
	for item: Dictionary in fixtures.companionFrames:
		var simulation := context(h)
		var unit := BattleUnit.new()
		simulation.add_child(unit)
		unit.kind = item.kind
		unit.side = "STEEL"
		unit.position.y = item.altitude
		unit.special = {"role": "hologram" if item.kind == "decoy_beacon" else "summon"}
		unit.height = Content.balance.companions["steel_" + item.kind].height
		h._near(simulation._body_altitude(unit), item.span[0], "Original autonomous damage-body baseline is separate from flight altitude")
		h._near(simulation._body_altitude(unit) + unit.height, item.span[1], "Original autonomous damage-body top")
		h._near(simulation._relative_sight_height(unit), item.sight, "Original altitude modifier uses actual relative companion height")
		h._near(simulation._relative_origin(unit).y, item.eye, "Original source observer eye")
		h._near(simulation._relative_target(unit).y, item.target, "Original source LOS target band")
		h._near(unit.sight_target().y, item.target, "Native static and skill-plane LOS share the same source target sample")
		simulation.free()
	for item: Dictionary in fixtures.companionGeometry:
		var scene: PackedScene = load("res://assets/companions/%s.scn" % item.key)
		var root: Node3D = scene.instantiate()
		h.add_child(root)
		var meshes := root.find_children("*", "GeometryInstance3D", true, false).filter(func(node): return node is MeshInstance3D or node is MultiMeshInstance3D)
		h._check(meshes.size() == item.meshes.size(), "Original companion graph preserves all source body meshes")
		for index in range(mini(meshes.size(), item.meshes.size())):
			var node: Node3D = meshes[index]
			var local_bounds: AABB = node.multimesh.get_aabb() if node is MultiMeshInstance3D else node.get_aabb()
			var bounds: AABB = node.global_transform * local_bounds
			h._check(bounds.position.distance_to(vector(item.meshes[index].bounds[0])) < 0.0001 and bounds.end.distance_to(vector(item.meshes[index].bounds[1])) < 0.0001,
				"Original source-built companion mesh dimensions and hierarchy")
		root.free()
	print("COMPANION_REFERENCE_PASS clones=", fixtures.companionClones.size(), " targeting=", fixtures.companionTargeting.size(),
		" summons=", fixtures.companionSummons.size(), " combat=", fixtures.companionCombat.size(), " deaths=", fixtures.companionDeaths.size())

static func combat(h: Node, item: Dictionary) -> void:
	var simulation := context(h)
	simulation.recording = true
	var owner := pilot(simulation, 1, item.character)
	var target := pilot(simulation, 2, "s09", "SWARM", vector(item.target))
	owner.upgrades.lw = int(item.level) - 1
	owner.buffs = [{"until": 30.0, "mul": {"dmg": 1.3}}]
	if item.scenario == "approach":
		owner.last_hit_target = 2
	match item.role:
		"clone":
			simulation._spawn_clones(owner)
			owner.status.clones_until = 20
			simulation.order = owner.clone_ids.duplicate()
		"summon":
			simulation._spawn_autonomous_summons(owner, {"id": "atk", "unit": "main_battle_tank", "count": 2}, Vector3.ZERO)
			simulation.order = simulation.autonomous_summons.duplicate()
		"hologram":
			simulation._cast_effect(owner, Content.ability("t04", "def"), owner.position)
			simulation.order = simulation.hologram_decoys.duplicate()
	compare_roster(h, simulation, simulation.order, item.initial, "Original independent actor initial state")
	simulation.rng = SourceRng.new(42)
	simulation.clock = item.now
	if item.scenario == "owner_dead":
		owner.hp = 0
	if item.scenario == "swap":
		for id: int in simulation.order:
			simulation.units[id].hp = 600
		simulation.units[simulation.order[0]].shield = 42
		simulation.units[simulation.order[0]].position.x = 30
	for step: Dictionary in item.steps:
		match item.role:
			"clone": simulation._tick_clones(step.delta)
			"summon": simulation._tick_summons(step.delta)
			"hologram": simulation._tick_holograms(step.delta)
		compare_roster(h, simulation, simulation.order, step.actors, "Original autonomous movement, cadence and expiry")
		h._check(owner.position.distance_to(vector(step.owner.position)) < 0.001, "Original clone expiry transfer chooses a stable highest-HP body")
		h._near(owner.hp, step.owner.hp, "Original companion owner HP")
		h._near(owner.shield, step.owner.shield, "Original companion owner shield")
		h._check(simulation.hits.size() == step.hits.size(), "Original autonomous shot count")
		for index in range(mini(simulation.hits.size(), step.hits.size())):
			var hit: Dictionary = simulation.hits[index]
			var expected: Dictionary = step.hits[index]
			h._check(hit.actor == int(expected.actor) and hit.target == int(expected.target), "Original companion attacker/target order")
			h._check(absf(hit.amount - expected.amount) < maxf(0.00001, absf(expected.amount) * 0.000001), "Original autonomous damage within native position precision")
			h._near(hit.pen, expected.pen, "Original companion authored penetration")
		StatusHelper.compare(h, simulation.controls, step.controls, "Original hologram detonation applies confusion")
		var shots: Array = simulation.events.filter(func(event): return event.type == "shot")
		h._check(shots.size() == step.shots.size(), "Original companion shots publish entity events independently of player volleys")
		for index in range(mini(shots.size(), step.shots.size())):
			var shot: Dictionary = shots[index]
			var expected: Dictionary = step.shots[index]
			h._check(simulation.order.find(int(shot.actor)) == int(expected.actor) and shot.kind == expected.kind
				and shot.get("pid") == expected.pid and shot.get("slot") == expected.slot,
				"Original clone/summon firing identity cannot broadcast a player-wide body event")
			h._check(shot.has("body_serial"), "Every supported companion body receives its independent reliable presentation event")
		simulation.events.clear()
		simulation.hits.clear()
		simulation.controls.clear()
	StatusHelper.check_draws(h, simulation, int(item.draws))
	h._check(target.status.get("element_buildup", {}).is_empty(), "Autonomous actor shots do not fabricate weapon elemental buildup")
	simulation.free()

static func deaths(h: Node, item: Dictionary) -> void:
	var simulation := context(h)
	var owner := pilot(simulation, 1, "t05")
	var enemy := pilot(simulation, 2, "s09", "SWARM", Vector3(0, 0, -15))
	var victim := npc(simulation, 3, "soldier", "SWARM", Vector3(10, 0, 0))
	victim.hp = 1
	victim.armor = 0
	simulation._spawn_clones(owner)
	owner.status.clones_until = 20
	var first: BattleUnit = simulation.units[owner.clone_ids[0]]
	first.hp = 600
	first.shield = 42
	first.position.x = 30
	simulation.units[owner.clone_ids[1]].hp = 600
	var initial_money := owner.money
	match item.scenario:
		"owner_lethal": simulation.damage(enemy, owner, {"type": "gun"}, 10000, false, {}, false)
		"clone_lethal": simulation.damage(enemy, first, {"type": "gun"}, 10000, false, {}, false)
		"clone_kill": simulation.damage(first, victim, {"type": "gun"}, 10, false, {}, false)
		"summon_kill":
			simulation._spawn_autonomous_summons(owner, {"id": "atk", "unit": "main_battle_tank", "count": 1}, Vector3.ZERO)
			simulation.damage(simulation.units[simulation.autonomous_summons[0]], victim, {"type": "gun"}, 10, false, {}, false)
		"clone_interrupt":
			owner.hp = 50
			owner.shield = 0
			first.shield = 0
			owner.cast_state = {"start": 9.0, "duration": 2.0, "definition": Content.ability("t05", "def"), "point": Vector3.ZERO, "level": 1}
			simulation.damage(enemy, first, {"type": "gun"}, 1, false, {}, false)
	compare_roster(h, simulation, owner.clone_ids, item.clones, "Original clone kill and donor removal")
	h._check(owner.position.distance_to(vector(item.owner.position)) < 0.0001, "Original lethal clone transfer bypasses horizontal collision")
	h._near(owner.hp, item.owner.hp, "Original lethal/interruption owner HP")
	h._near(owner.shield, item.owner.shield, "Original lethal/interruption owner shield")
	h._near(owner.money - initial_money, item.owner.earned, "Proxy kills pay the source owner assist only; clone kills do not pay the owner")
	h._near(owner.score, item.owner.score, "Original proxy assist score")
	h._check(owner.last_hit_target == int(item.owner.focus), "Summon focus is assigned to its owner while clone focus stays independent")
	h._check((not owner.cast_state.is_empty()) == bool(item.owner.cast), "Hits to clones interrupt the owner's cast")
	h._check(simulation.units.has(first.entity_id) == bool(item.targetPresent), "Clone removal never enters the player respawn lifecycle")
	h._near(enemy.money, item.enemy.money, "Destroying a clone gives no bounty")
	h._near(victim.hp, item.victim.hp, "Original proxy damage settles at the authority")
	simulation.free()

static func context(h: Node) -> CompanionSimulation:
	var simulation := CompanionSimulation.new()
	h.add_child(simulation)
	simulation.set_physics_process(false)
	simulation.clock = 10
	simulation.world = BattleWorld.new()
	simulation.add_child(simulation.world)
	return simulation

static func replica_binding(h: Node) -> void:
	var authority := context(h)
	var owner := pilot(authority, 1, "t05")
	authority._spawn_clones(owner)
	var records: Array = [owner.snapshot()]
	for id: int in owner.clone_ids:
		records.append(authority.units[id].snapshot())
	var replica := context(h)
	replica.authoritative = false
	replica.world.hero_spawns = Content.map_variant(0, 1).hero_spawns
	var packet := {"clock": 10.0, "wave": 0, "units": records, "events": [], "over": false, "winner": ""}
	replica.apply_snapshot(bytes_to_var(var_to_bytes(packet)))
	h._check(replica.pilots.size() == 1 and replica.pilots[1].entity_id == owner.entity_id,
		"Native wire encoding preserves a single pilot when clone records share its peer ID")
	for id: int in owner.clone_ids:
		var clone: BattleUnit = replica.units[id]
		h._check(not clone.is_pilot() and clone.camera == null and clone.peer_id == 1, "Replica clone cannot become a locally controlled camera")
		h._near(clone.effect_radius, authority.units[id].effect_radius, "Replica preserves explicit effect radius separately from hero hit volumes")
	packet.units = [records[0]]
	replica.apply_snapshot(packet)
	h._check(replica.pilots.has(1) and replica.pilots[1].entity_id == owner.entity_id and replica.units.size() == 1,
		"Despawned clone snapshots cannot erase their owner's pilot binding")
	var before: float = owner.power
	owner.status.clones_until = 20
	authority.fire(owner, "heavy")
	h._near(owner.power, before, "Clone active window rejects heavy fire before resource spending")
	authority.free()
	replica.free()

static func pilot(simulation: BattleSimulation, id: int, character: String, side: String = "STEEL", point: Vector3 = Vector3.ZERO) -> BattleUnit:
	var unit := StatusHelper.actor(simulation, {"id": id, "character": character, "side": side, "position": [point.x, point.y, point.z],
		"hp": 400, "max_hp": 1000, "shield": 80, "max_shield": 500, "power": 1000, "max_power": 1000, "armor": 12})
	unit.yaw = 0.4
	unit.money = 100
	return unit

static func npc(simulation: BattleSimulation, id: int, kind: String, side: String, point: Vector3) -> BattleUnit:
	return StatusHelper.actor(simulation, {"id": id, "character": "", "kind": kind, "side": side, "position": [point.x, point.y, point.z], "hp": 100, "max_hp": 100})

static func compare_timers(h: Node, owner: BattleUnit, expected: Dictionary) -> void:
	for key: String in expected:
		if expected[key] == null:
			h._check(not owner.status.has(key), "Original clone expiry removes its timer: " + key)
		else:
			h._near(float(owner.status.get(key, 0)), float(expected[key]), "Original clone timer: " + key)

static func compare_roster(h: Node, simulation: BattleSimulation, ids: Array, expected: Array, label: String) -> void:
	var live: Array = ids.filter(func(id): return simulation.units.has(int(id)) and simulation.units[int(id)].alive())
	h._check(live.size() == expected.size(), label + " actor count")
	for index in range(mini(live.size(), expected.size())):
		var unit: BattleUnit = simulation.units[int(live[index])]
		var state: Dictionary = expected[index]
		h._check(unit.position.distance_to(vector(state.position)) < 0.001, label + " native position tolerance")
		for property: String in ["hp", "max_hp", "shield", "max_shield", "armor", "speed", "radius", "height", "effect_radius"]:
			h._near(float(unit.get(property)), float(state[property]), label + " " + property)
		for property: String in ["cd", "range", "rate", "sight", "until"]:
			if state[property] != null:
				h._near(float(unit.special.get(property, 0)), float(state[property]), label + " " + property)
		if state.damage != null:
			h._near(unit.special.dmg, state.damage, label + " per-shot damage")
		if state.wid != null:
			h._check(unit.special.wid == state.wid, label + " authored NPC weapon")
		if state.offset != null:
			h._check(unit.special.offset.distance_to(Vector2(state.offset[0], state.offset[1])) < 0.0001, label + " formation offset")

static func vector(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])
