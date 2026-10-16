extends RefCounted

const StatusHelper = preload("res://tests/status_suite.gd")
const BotTests = preload("res://tests/bot_suite.gd")

class BossSimulation extends BattleSimulation:
	func _missile_target_altitude(unit: BattleUnit) -> float:
		return unit.position.y

	func _height_reference(_unit: BattleUnit) -> float:
		return 0.0

	func _record_air_sink(_unit: BattleUnit, _amount: float) -> void:
		pass

	func _stamp_suppression(_unit: BattleUnit, _attacker: BattleUnit) -> void:
		pass

class ReferenceHud extends BossHud:
	var cover := 0.0

	func _obstruction_distance(origin: Vector3, point: Vector3) -> float:
		return origin.distance_to(point) - cover if cover > 0 else INF

static func run(h: Node, fixtures: Dictionary) -> void:
	for key: String in ["bossMath", "bossAnchors", "bossSync", "siegeGates", "siegeDeaths", "siegeDamage", "bossRevive", "bossView"]:
		if not fixtures.has(key):
			h._check(false, "Regenerate original siege/BOSS oracle: " + key)
			return
	for item: Dictionary in fixtures.bossMath:
		var result
		match item.kind:
			"segment": result = SiegeRules.segment_of(item.input)
			"fraction": result = SiegeRules.segment_fraction(item.input, int(item.segment))
			"scale": result = SiegeRules.body_scale(int(item.input))
			"invulnerability": result = SiegeRules.invulnerability(int(item.input))
			"talk": result = SiegeRules.talk_seconds(int(item.input))
			"slots": result = SiegeRules.slot_plan(int(item.input))
			"offset": result = SiegeRules.slot_offset(int(item.input))
			"open": result = SiegeRules.open_stage(item.input)
		StatusHelper.compare(h, result, item.result, "Original siege/BOSS helper " + item.kind)
	for item: Dictionary in fixtures.bossAnchors:
		var point := SiegeRules.anchor(item.side, int(item.stage), int(item.index), item.sites, item.lane, Vector2(item.base[0], item.base[1]))
		h._check(point.distance_to(Vector2(item.result[0], item.result[1])) < 0.001, "Original asymmetric BOSS tower-normal/base anchor")
	for item: Dictionary in fixtures.bossSync:
		var simulation := context(h)
		var unit := actor(simulation, item.initial)
		for step: Dictionary in item.steps:
			simulation.clock = step.now
			unit.hp = floorf(unit.max_hp * float(step.fraction) + 0.5)
			unit.shield = 0
			simulation.events.clear()
			simulation._boss_sync(unit)
			compare_body(h, unit, step.result, "Original BOSS eight-track segment upgrade " + unit.character)
			var segments: Array = simulation.events.filter(func(event): return event.type == "boss_segment").map(func(event): return event.segment)
			StatusHelper.compare(h, segments, step.events, "Original once-only monotonic segment event")
			var shape: CylinderShape3D = unit.movement_shape.shape
			var collider: Dictionary = Content.heroes[unit.character].colliders["air" if unit.flying else "ground"]
			h._near(shape.radius, float(collider.r) * SiegeRules.body_scale(int(unit.special.boss_segment)), "Native BOSS traversal cylinder follows source segment scale")
			if unit.model != null:
				h._check(unit.model.scale.distance_to(unit.model_base_scale * SiegeRules.body_scale(int(unit.special.boss_segment))) < 0.00001, "Native BOSS scene scale is absolute, without cumulative growth")
		simulation.free()
	var gates := context(h)
	var target := BattleUnit.new()
	gates.add_child(target)
	target.side = "STEEL"
	for item: Dictionary in fixtures.siegeGates:
		gates.siege = item.enabled
		gates.siege_open.STEEL = item.open
		gates.boss_left.STEEL = [item.left, item.left, item.left]
		gates.siege_talk_until.STEEL = [item.until, item.until, item.until]
		target.kind = "robot" if item.hero else "tower"
		target.character = "t01" if item.hero else ""
		target.special = {"siege_stage": int(item.stage)} if int(item.stage) >= 0 else {}
		h._check(gates.siege_locked(target) == bool(item.locked), "Original stage immunity gate")
		h._near(gates._siege_hp_floor(target), item.floor, "Original independent same-stage BOSS/dialogue HP floor")
	gates.free()
	for item: Dictionary in fixtures.siegeDeaths:
		var simulation := context(h)
		simulation.defending_side = item.side
		set_stages(simulation, item.initial)
		for step: Dictionary in item.steps:
			simulation.clock = step.now
			var input := fixture_body(item.side)
			input.id = simulation.next_id
			input.peer = -simulation.next_id
			input.stage = int(step.stage)
			var unit := actor(simulation, input)
			unit.hp = 0
			simulation.events.clear()
			simulation._kill_unit(unit, null)
			h._check(is_inf(unit.respawn_at) == bool(step.permanent_death), "Original BOSS death has no respawn/penalty")
			compare_stages(h, simulation, step.state)
			var events: Array = []
			for event: Dictionary in simulation.events:
				if event.type in ["siege", "siege_talk", "boss_down"]:
					events.append({"type": event.type, "stage": event.stage})
			StatusHelper.compare(h, events, step.events, "Original last BOSS in each stage starts dialogue before structure death")
		simulation.free()
	for item: Dictionary in fixtures.siegeDamage:
		var simulation := context(h)
		set_stages(simulation, item.initial_state)
		var unit := actor(simulation, item.input)
		var attacker: BattleUnit = actor(simulation, item.attacker) if item.attacker != null else null
		simulation.damage(attacker, unit, {}, item.amount, false, {}, false)
		compare_body(h, unit, item.result, "Original siege settlement " + item.kind + "/" + item.killer + "/" + item.gate)
		if attacker != null:
			h._near(attacker.damage_out, item.damage_out, "Original BOSS/structure allied-bot and NPC damage credit")
		simulation.free()
	for item: Dictionary in fixtures.bossRevive:
		var simulation := context(h)
		var unit := actor(simulation, fixture_body(item.side))
		unit.hp = 0
		unit.respawn_at = INF
		simulation._revive_body(unit, 0.5)
		simulation.respawn(unit)
		h._near(unit.hp, item.hp, "Original BOSS immunity to revival skills")
		h._check(is_inf(unit.respawn_at) == bool(item.permanent_death), "Revival cannot replace the BOSS permanent-death deadline")
		simulation.free()
	for item: Dictionary in fixtures.bossView:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1280, 720)
		h.add_child(viewport)
		var simulation := context(viewport)
		var camera := Camera3D.new()
		simulation.add_child(camera)
		camera.position = Vector3(0, 10, 0)
		camera.fov = 70
		camera.current = true
		var view := ReferenceHud.new()
		viewport.add_child(view)
		view.size = Vector2(500, 94)
		for step: Dictionary in item.steps:
			var present: Array = []
			for target_input: Dictionary in step.targets:
				var id: int = int(target_input.id)
				present.append(id)
				var unit: BattleUnit = simulation.units.get(id)
				if unit == null:
					var input := fixture_body("STEEL")
					input.id = id
					input.peer = -id
					input.character = target_input.character
					input.kind = Content.heroes[input.character].kind
					unit = actor(simulation, input)
				unit.special.boss = target_input.boss
				unit.special.boss_segment = 1
				unit.hp = target_input.hp
				unit.position = Vector3(target_input.position[0], target_input.position[1], target_input.position[2])
				unit.geometry_override = {"centre": 0.0}
			for id: int in simulation.units.keys():
				if not present.has(id):
					simulation.units[id].free()
					simulation.units.erase(id)
			view.cover = step.cover
			view.update_view(simulation, camera, step.now)
			h._check(view.active_id == int(step.result.active_id) and view.visible == bool(step.result.shown), "Original BOSS view selection/tie/obstacle/hysteresis " + item.name)
			if view.visible:
				h._check(int(view.active_unit.special.boss_segment) + 1 == int(step.result.phase), "Original BOSS HUD phase")
		viewport.free()
	print("BOSS_REFERENCE_PASS upgrades=", fixtures.bossSync.size(), " gates=", fixtures.siegeGates.size(), " damage=", fixtures.siegeDamage.size())

static func context(h: Node) -> BossSimulation:
	var simulation := BossSimulation.new()
	h.add_child(simulation)
	simulation.set_physics_process(false)
	simulation.siege = true
	simulation.defending_side = "STEEL"
	simulation.clock = 10
	simulation.world = BotTests.FlatWorld.new()
	simulation.add_child(simulation.world)
	simulation._setup_siege_counts()
	return simulation

static func actor(simulation: BattleSimulation, input: Dictionary) -> BattleUnit:
	var unit := BattleUnit.new()
	simulation.add_child(unit)
	var special := {"boss": input.boss, "boss_segment": int(input.segment)}
	if int(input.stage) >= 0:
		special.siege_stage = int(input.stage)
	unit.configure({"id": int(input.id), "peer": int(input.peer), "side": input.side, "kind": input.kind,
		"character": input.character if input.hero else "", "position": Vector3(input.position[0], input.position[1], input.position[2]),
		"bot": input.is_bot, "special": special})
	for key: String in ["hp", "max_hp", "shield", "max_shield", "armor", "money", "score", "power", "damage_out"]:
		unit.set(key, float(input[key]))
	if not input.upgrades.is_empty():
		unit.upgrades = input.upgrades.duplicate()
	unit.ammo = input.ammo.duplicate()
	unit.reload_at = input.reload_at.duplicate()
	unit.status.inv_until = input.inv_until
	unit.respawn_at = INF if input.permanent_death else 0.0
	simulation.units[unit.entity_id] = unit
	simulation.next_id = maxi(simulation.next_id, unit.entity_id + 1)
	if unit.is_pilot():
		simulation.pilots[unit.peer_id] = unit
	return unit

static func compare_body(h: Node, unit: BattleUnit, expected: Dictionary, label: String) -> void:
	for key: String in ["hp", "max_hp", "shield", "max_shield", "armor", "money", "score", "power", "radius", "height"]:
		h._near(unit.get(key), expected[key], label + "/" + key)
	if expected.hero:
		StatusHelper.compare(h, unit.upgrades, expected.upgrades, label + "/eight tracks")
	StatusHelper.compare(h, unit.ammo, expected.ammo, label + "/new-tier lazy magazines")
	StatusHelper.compare(h, unit.reload_at, expected.reload_at, label + "/reload")
	h._near(unit.status.get("inv_until", 0), expected.inv_until, label + "/transition invulnerability")
	h._check(int(unit.special.get("boss_segment", 0)) == int(expected.segment), label + "/segment")

static func set_stages(simulation: BattleSimulation, input: Dictionary) -> void:
	simulation.siege_left = input.siege_left.duplicate(true)
	simulation.siege_open = input.siege_open.duplicate()
	simulation.boss_left = input.boss_left.duplicate(true)
	simulation.siege_talk_until = input.talk_until.duplicate(true)

static func compare_stages(h: Node, simulation: BattleSimulation, expected: Dictionary) -> void:
	StatusHelper.compare(h, simulation.siege_left, expected.siege_left, "Original combined structure/BOSS stage roster")
	StatusHelper.compare(h, simulation.siege_open, expected.siege_open, "Original next available siege stage")
	StatusHelper.compare(h, simulation.boss_left, expected.boss_left, "Original per-stage surviving BOSS count")
	StatusHelper.compare(h, simulation.siege_talk_until, expected.talk_until, "Original fixed dialogue unlock deadline and immediate base unlock")

static func fixture_body(side: String) -> Dictionary:
	return {"id": 1, "peer": -1, "hero": true, "character": "t01" if side == "STEEL" else "s01", "kind": "robot" if side == "STEEL" else "drone",
		"side": side, "position": [0, 0, 0], "is_bot": true, "hp": 100, "max_hp": 100, "shield": 0, "max_shield": 0,
		"armor": 0, "money": 0, "score": 0, "power": 0, "damage_out": 0, "upgrades": {}, "ammo": {}, "reload_at": {},
		"inv_until": 0, "segment": 0, "boss": true, "stage": 0, "permanent_death": false}
