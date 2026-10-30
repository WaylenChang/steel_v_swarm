extends RefCounted

const StatusHelper = preload("res://tests/status_suite.gd")

class FlatWorld extends BattleWorld:
	func ground_height(_x: float, _z: float) -> float:
		return 0.0

class ReferenceSimulation extends BattleSimulation:
	var actions: Array = []
	var hits: Array = []
	var blocked := false
	var buy_allowed := false
	var decisions := true

	func present_shot(_event: Dictionary) -> void:
		# The original server oracle records broadcasts without a Game renderer.
		# Keep report settlement observable without running unrelated local FX.
		pass

	func _missile_target_altitude(unit: BattleUnit) -> float:
		return unit.position.y

	func _height_reference(_unit: BattleUnit) -> float:
		return 0.0

	func _projectile_surface(_point: Vector3) -> float:
		return 0.0

	func camera_origin(unit: BattleUnit) -> Vector3:
		return unit.position + Vector3.UP * float(Content.constants.LOS.EYE_M)

	func _visible_from(_origin: Vector3, _target: BattleUnit) -> bool:
		return not blocked

	func visible_to_side(unit: BattleUnit, _side: String) -> bool:
		return not unit.get_meta("hidden", false)

	func _bot_clear_shot(_unit: BattleUnit, _target: BattleUnit) -> bool:
		return not blocked

	func _bot_move(unit: BattleUnit, destination: Vector2, _delta: float) -> float:
		unit.position = Vector3(destination.x, unit.position.y, destination.y)
		return 1.0

	func _bot_altitude(unit: BattleUnit, altitude: float) -> void:
		unit.position.y = altitude

	func _bot_aim(unit: BattleUnit, aiming: bool) -> void:
		actions.append({"type": "aim", "on": aiming})
		unit.input_state.aim = aiming

	func _bot_defend(unit: BattleUnit, defending: bool) -> void:
		actions.append({"type": "defend", "on": defending})
		unit.defending = defending

	func _bot_fire(unit: BattleUnit, target: BattleUnit, slot: String, mode: String = "direct") -> bool:
		if not decisions:
			return super._bot_fire(unit, target, slot, mode)
		actions.append({"type": "fire", "target": target.entity_id, "slot": slot, "mode": mode})
		return true

	func cast(_unit: BattleUnit, slot: String, requested_point: Vector3 = Vector3(INF, INF, INF)) -> bool:
		var aimed := requested_point.is_finite()
		actions.append({"type": "cast", "slot": slot, "aimed": aimed, "point": [requested_point.x, requested_point.z] if aimed else null})
		return false

	func buy(_unit: BattleUnit, item: String) -> bool:
		actions.append({"type": "buy", "item": item, "lane": null})
		return buy_allowed and item == "ar"

	func buy_creep(_unit: BattleUnit, lane: int) -> bool:
		actions.append({"type": "buy", "item": "creep", "lane": lane})
		return false

	func damage(attacker: BattleUnit, target: BattleUnit, definition: Dictionary, amount: float, _friendly: bool = false,
			_context: Dictionary = {}, attack_modifiers: bool = true) -> void:
		if attack_modifiers:
			_apply_hit_emp(definition, target)
			_apply_hit_elements(attacker, definition, target)
			amount *= _weapon_multiplier(attacker, target, definition)
		hits.append({"target": target.entity_id, "amount": amount})

static func run(h: Node, fixtures: Dictionary) -> void:
	for key: String in ["botMath", "botOperations", "botSequences", "botFire", "botHeavy", "botHurt", "botShotOrigins"]:
		if not fixtures.has(key):
			h._check(false, "Regenerate original bot oracle: " + key)
			return
	for item: Dictionary in fixtures.botMath:
		match item.type:
			"decay": h._near(BotRules.threat_decay(item.age, Content.constants.BOT_TACTIC), item.result, "Original bot threat fade")
			"execution": h._near(BotRules.execution_weight(item.hp, item.max, item.salvo), item.result, "Original bot elite execution weight")
			"blood":
				var uv := BotRules.blood_uv(item.bearing, item.elevation, item.halfH, item.halfV)
				var direction := BotRules.blood_direction(uv, item.halfH, item.halfV)
				h._check(uv.distance_to(Vector2(item.uv[0], item.uv[1])) < 0.000001, "Original blood-screen edge projection")
				h._check(direction.distance_to(Vector2(item.direction[0], item.direction[1])) < 0.000001, "Original elite alert direction inversion")
	h._near(BotRules.packed_reach({}), 15, "Source packed-target reach defaults a heavy without a blast radius")
	h._near(BotRules.packed_reach({"r": 0}), 15, "Source packed-target reach treats a zero radius as absent")
	h._near(BotRules.packed_reach({"r": 4}), 6, "Source packed-target reach scales an authored blast radius")
	for item: Dictionary in fixtures.botOperations:
		var simulation := context(h)
		var brain := BotBrain.new()
		brain.simulation = simulation
		brain.difficulty = Content.constants.BOT_DIFF[item.difficulty]
		for step: Dictionary in item.steps:
			simulation.clock = step.now
			h._check(brain.op(step.kind) == bool(step.result), "Original global/per-operation APM deadline " + item.difficulty)
			StatusHelper.compare(h, brain.op_at, step.op_at, "Original operation deadline ledger")
			h._near(brain.op_next, step.op_next, "Original global APM commit")
		simulation.free()
	for item: Dictionary in fixtures.botSequences:
		var simulation := context(h)
		simulation.blocked = item.blocked
		simulation.buy_allowed = item.buy
		simulation.world.lane_points = item.lanes.duplicate(true)
		for points: Array in item.lanes:
			simulation.world.lane_distances.append(WaveRules.cumulative(points))
		simulation.world.bases = {}
		for side: String in item.bases:
			var p: Array = item.bases[side]
			simulation.world.bases[side] = Vector3(p[0], 0, p[1])
		simulation.bot_tower_sites = item.tower_sites.duplicate(true)
		for input: Dictionary in item.inputs:
			actor(simulation, input)
		var owner: BattleUnit = simulation.units[1]
		if item.hold != null:
			simulation.bot_holds[owner.peer_id] = item.hold.duplicate(true)
		var brain := BotBrain.new()
		brain.configure(simulation, owner, item.difficulty)
		for step: Dictionary in item.steps:
			simulation.clock = step.now
			simulation.actions.clear()
			brain.update(0.125)
			var label: String = "Original BotBrain " + item.difficulty + "/" + item.name
			StatusHelper.compare(h, simulation.actions, step.actions, label + " ordered decisions")
			h._check(owner.position.distance_to(vector(step.actor.position)) < 0.001, label + " position/altitude")
			h._check(absf(owner.yaw - float(step.actor.yaw)) < 0.00001 and absf(owner.pitch - float(step.actor.pitch)) < 0.00001, label + " bounded view turn")
			h._check(bool(owner.input_state.get("aim", false)) == bool(step.actor.aiming) and owner.defending == bool(step.actor.defending), label + " aim/guard posture")
			StatusHelper.compare(h, owner.ammo, step.actor.ammo, label + " lazy heavy refill")
			StatusHelper.compare(h, owner.reload_at, step.actor.reload_at, label + " reload deadlines")
			compare_brain(h, brain, step.brain, label)
			StatusHelper.check_draws(h, simulation, int(step.draws))
		simulation.free()
	for item: Dictionary in fixtures.botFire:
		var simulation := context(h)
		simulation.decisions = false
		simulation.clock = 10
		simulation.blocked = item.gate == "blocked"
		var owner := actor(simulation, item.input)
		var enemy := actor(simulation, item.target)
		for extra: Dictionary in item.extras:
			actor(simulation, extra)
		h._check(simulation._bot_fire(owner, enemy, item.slot) == bool(item.accepted), "Original botFire authority gates " + item.character + "/" + item.gate)
		StatusHelper.compare(h, simulation.hits, item.hits, "Original botFire primary and no-repeat line damage")
		StatusHelper.compare(h, owner.ammo, item.after.ammo, "Original bot ammo settlement")
		StatusHelper.compare(h, owner.reload_at, item.after.reload_at, "Original bot reload deadlines")
		StatusHelper.compare(h, owner.last_fired_at, item.after.last_fired_at, "Original bot strict fire cadence")
		h._near(owner.power, item.after.power, "Original bot heavy power spend")
		h._check(owner.bot_shot_count == int(item.shot_count), "Original accepted-shot throttle counter")
		h._check(simulation.events.filter(func(event): return event.type == "shot").size() == int(item.shot_events), "Original every-third light / every-heavy shot broadcast")
		for key: String in item.target_after.status:
			StatusHelper.compare(h, enemy.status.get(key), item.target_after.status[key], "Original bot hit status " + key)
		for expected: Dictionary in item.extras_after:
			var target: BattleUnit = simulation.units[int(expected.id)]
			for key: String in expected.status:
				StatusHelper.compare(h, target.status.get(key), expected.status[key], "Original secondary line hit status " + key)
		StatusHelper.check_draws(h, simulation, int(item.draws))
		simulation.free()
	for item: Dictionary in fixtures.botHeavy:
		var simulation := context(h)
		simulation.decisions = false
		simulation.clock = 10
		var owner := actor(simulation, item.input)
		var enemy := actor(simulation, item.target)
		h._check(simulation._bot_fire(owner, enemy, "heavy", item.mode) == bool(item.accepted), "Original bot heavy report gates " + item.character + "/" + item.mode + "/" + item.gate)
		StatusHelper.compare(h, simulation.hits, item.hits, "Original bot blast/fan settlement")
		StatusHelper.compare(h, owner.ammo, item.after.ammo, "Original bot heavy magazine")
		StatusHelper.compare(h, owner.reload_at, item.after.reload_at, "Original bot report backdates empty/last-round reload")
		StatusHelper.compare(h, owner.last_fired_at, item.after.last_fired_at, "Original bot lenient heavy report cadence")
		h._near(owner.power, item.after.power, "Original bot heavy report power")
		var kinds: Array = []
		for event: Dictionary in simulation.events:
			if event.type in ["shot", "boom", "plasma"]:
				kinds.append(event.type)
		StatusHelper.compare(h, kinds, item.kinds, "Original bot firing/impact event order")
		for key: String in item.target_after.status:
			StatusHelper.compare(h, enemy.status.get(key), item.target_after.status[key], "Original bot fan/blast elemental status without direct-hit EMP " + key)
		StatusHelper.check_draws(h, simulation, int(item.draws))
		simulation.free()
	var hurt_simulation := context(h)
	var victim := actor(hurt_simulation, fixtures.botHurt[0].target)
	var attacker := actor(hurt_simulation, fixtures.botHurt[0].attacker)
	for item: Dictionary in fixtures.botHurt:
		hurt_simulation.clock = item.now
		hurt_simulation._record_bot_hurt(victim, attacker, item.value)
		StatusHelper.compare(h, victim.threat, item.threat, "Original bot threat expires and fades before accumulation")
		h._check(victim.bot_alert.point.distance_to(Vector2(item.alert.point[0], item.alert.point[1])) < 0.001, "Original bot source alert bearing")
		h._near(victim.bot_alert.altitude, item.alert.altitude, "Original bot alert height frame")
		h._near(victim.bot_alert.at, item.alert.at, "Original bot alert timestamp")
	hurt_simulation.free()
	for item: Dictionary in fixtures.botShotOrigins:
		var definition := Content.weapon(item.character, "heavy")
		var result := ShotHistory.origin(item.trail, item.now, Vector2(item.current[0], item.current[1]), Vector2(item.target[0], item.target[1]), definition, item.cap)
		h._check(result.point.distance_to(Vector2(item.point[0], item.point[1])) < 0.001, "Original bot impact report source-position history")
		h._near(result.back, item.back, "Original ballistic report reload backdating")
	await native_collision(h)
	print("BOT_REFERENCE_PASS sequences=", fixtures.botSequences.size(), " fire=", fixtures.botFire.size(), " ops=", fixtures.botOperations.size())

static func native_collision(h: Node) -> void:
	var simulation := BattleSimulation.new()
	h.add_child(simulation)
	simulation.set_physics_process(false)
	simulation.world = FlatWorld.new()
	simulation.add_child(simulation.world)
	simulation.world.lane_points = [[[0, 0], [0, -200]]]
	simulation.world.lane_distances = [WaveRules.cumulative(simulation.world.lane_points[0])]
	simulation.world.bases = {"STEEL": Vector3.ZERO, "SWARM": Vector3(0, 0, -200)}
	simulation.world.hero_spawns = {"STEEL": [{"position": [0, 0], "direction": [0, -1]}]}
	simulation.bot_tower_sites = [[]]
	var owner := simulation.spawn({"id": 1, "peer": -1, "character": "t01", "kind": Content.heroes.t01.kind,
		"side": "STEEL", "position": Vector3(0, 20, 0), "bot": true})
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	wall.position = Vector3(0, 20, -10)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 100, 0.05)
	shape.shape = box
	wall.add_child(shape)
	simulation.add_child(wall)
	await h.get_tree().physics_frame
	await h.get_tree().physics_frame
	var ratio := simulation._bot_move(owner, Vector2(0, -30), 0.125)
	h._check(owner.position.z > -10 and ratio < 1, "Native bot body sweep cannot cross a thin wall")
	var brain := BotBrain.new()
	brain.configure(simulation, owner, "medium")
	for index in range(6):
		simulation.clock = index * 0.125
		brain.stuck(0, 0.125)
	h._check(brain.skirt_side == -1 and brain.skirt_until > simulation.clock, "Source stuck duration alternates a native wall-skirt intent")
	var location := owner.position
	var ammo: Dictionary = owner.ammo.duplicate(true)
	var power := owner.power
	simulation.authoritative = false
	h._near(simulation._bot_move(owner, Vector2(0, -100), 0.125), 0, "Replicas cannot settle bot movement")
	h._check(owner.position == location, "Replica bot movement rejection preserves body pose")
	h._check(not simulation._bot_fire(owner, owner, "light"), "Replicas cannot settle bot attacks")
	h._check(owner.ammo == ammo and owner.power == power, "Rejected bot command cannot spend ammunition/power")
	simulation.queue_free()
	await h.get_tree().process_frame

static func context(h: Node) -> ReferenceSimulation:
	var simulation := ReferenceSimulation.new()
	h.add_child(simulation)
	simulation.set_physics_process(false)
	simulation.rng = SourceRng.new(42)
	simulation.world = FlatWorld.new()
	simulation.add_child(simulation.world)
	return simulation

static func actor(simulation: BattleSimulation, input: Dictionary) -> BattleUnit:
	var unit := BattleUnit.new()
	simulation.add_child(unit)
	unit.entity_id = int(input.id)
	unit.peer_id = int(input.peer)
	unit.character = input.character
	unit.kind = input.kind
	unit.side = input.side
	unit.position = vector(input.position)
	unit.yaw = input.yaw
	unit.pitch = input.pitch
	unit.is_bot = input.is_bot
	unit.input_state = {"aim": input.aiming, "slot": "light"}
	unit.defending = input.defending
	unit.special = input.special.duplicate(true)
	unit.status = input.status.duplicate(true)
	unit.ammo = input.ammo.duplicate(true)
	unit.reload_at = input.reload_at.duplicate(true)
	unit.last_fired_at = input.last_fired_at.duplicate(true)
	unit.cooldowns = input.cooldowns.duplicate(true)
	unit.upgrades = input.upgrades.duplicate(true) if not input.upgrades.is_empty() else unit.upgrades
	unit.set_meta("hidden", input.hidden)
	for property: String in ["hp", "max_hp", "shield", "max_shield", "power", "max_power", "armor", "money", "score", "damage_out", "damaged_at"]:
		unit.set(property, float(input[property]))
	if not input.alert.is_empty():
		unit.bot_alert = input.alert.duplicate()
		unit.bot_alert.point = Vector2(input.alert.point[0], input.alert.point[1])
	var volume: Dictionary = Content.heroes[unit.character] if unit.is_hero() else Content.balance.unitVolumes[unit.kind][unit.side]
	unit.radius = volume.radius
	unit.height = volume.height
	simulation.units[unit.entity_id] = unit
	if unit.is_hero():
		simulation.pilots[unit.peer_id] = unit
	return unit

static func compare_brain(h: Node, brain: BotBrain, expected: Dictionary, label: String) -> void:
	for property: String in ["state", "target_id", "role", "op_at"]:
		StatusHelper.compare(h, brain.get(property), expected[property], label + "/" + property)
	for property: String in ["progress", "aim_at", "op_next", "stuck_time", "skirt_until", "skirt_side", "rally_progress", "wanted_pitch"]:
		h._check(absf(float(brain.get(property)) - float(expected[property])) < 0.001, label + "/" + property)
	if expected.wanted_yaw == null:
		h._check(not is_finite(brain.wanted_yaw), label + "/absent view intention")
	else:
		h._check(absf(brain.wanted_yaw - float(expected.wanted_yaw)) < 0.00001, label + "/wanted yaw")
	if expected.rally_point == null:
		h._check(not brain.rally_point.is_finite(), label + "/absent rally point")
	else:
		h._check(brain.rally_point.distance_to(Vector2(expected.rally_point[0], expected.rally_point[1])) < 0.001, label + "/captured rally destination")

static func vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])
