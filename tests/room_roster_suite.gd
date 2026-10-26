extends RefCounted

const SessionScript = preload("res://scripts/session.gd")
const Helper = preload("res://tests/status_suite.gd")

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("roomHeroSelection") or not fixtures.has("roomBotPrograms") or not fixtures.has("roomHeroDeployment") or not Content.balance.get("rooms", {}).has("heroPools"):
		h._check(false, "Regenerate original hero assignment and room roster references")
		return
	for item: Dictionary in fixtures.roomHeroSelection:
		var draws := {"count": 0}
		var result := RoomRoles.choose(item.side, item.requested, item.previous, func():
			draws.count += 1
			return item.draw)
		h._check(result == item.result, "Original per-faction random hero pool, explicit repetition and exhaustion fallback: " + item.name)
		h._check(int(draws.count) == int(item.draws), "Original explicit hero selection does not consume random draws: " + item.name)
	for program: Dictionary in fixtures.roomBotPrograms:
		var session := SessionScript.new()
		h.add_child(session)
		session.active = true
		session.config = {"team_size": int(program.capacity)}
		for index in program.sides.size():
			session.seats.add(42 + index, 1000 + index, "test-" + str(index), program.sides[index])
			session.roster.append({"peer": 42 + index, "side": program.sides[index], "character": "", "bot": false})
		_compare_bots(h, session, program.initial)
		for frame: Dictionary in program.frames:
			var operation: Array = frame.operation
			if operation[0] == "phase":
				session.phase = operation[1]
			elif operation[0] == "leave":
				var player := session.seats.player_for(int(operation[1]))
				session.seats.erase(player)
				session.roster = session.roster.filter(func(entry): return int(entry.peer) != player)
			else:
				var player := int(operation[2]) if operation[0] != "add" else 0
				var value: String = operation[2] if operation[0] == "add" else operation[3] if operation[0] == "character" else ""
				session._edit_bot_for(int(operation[1]), operation[0], player, value)
			_compare_bots(h, session, frame)
		session.free()
	for item: Dictionary in fixtures.roomHeroDeployment:
		var battle := BattleSimulation.new()
		h.add_child(battle)
		battle.set_physics_process(false)
		battle.world = BattleWorld.new()
		battle.add_child(battle.world)
		var map_data := Content.map_variant(0, int(item.teamSize))
		map_data.erase("native_world")
		var roster: Array = item.roster.duplicate(true)
		await battle.world.build(map_data, {"time": "day", "weather": "clear", "season": "summer"})
		battle.bot_tower_sites = map_data.get("tower_sites", []).duplicate(true)
		battle.bot_difficulty = Content.constants.DEFAULT_BOT_DIFF
		h._check(battle._populate_heroes(map_data, roster), "Native roster initializes from prepared source geometry")
		for index in item.heroes.size():
			var expected: Dictionary = item.heroes[index]
			var unit: BattleUnit = battle.pilots.get(int(expected.peer))
			h._check(unit != null and unit.character == expected.character and unit.side == expected.side,
				"Original human-before-bot role allocation, same-side explicit repetition and random stream order")
		for expected: Dictionary in item.brains:
			var unit: BattleUnit = battle.pilots.get(int(expected.peer))
			var brain: BotBrain = battle.bot_brains.get(unit.entity_id) if unit != null else null
			h._check(brain != null, "Every source room bot owns an authority brain")
			if brain != null:
				h._check(brain.lane == int(expected.lane), "Original global room-bot insertion index assigns lanes across both factions")
				h._near(brain.cruise_altitude, float(expected.alt), "Original role selection and BotBrain constructor random draw interleaving")
				h._check(brain.jitter.distance_to(Vector2(expected.jitter[0], expected.jitter[1])) < 0.00001, "Original constructor jitter with native Z mirroring")
		h._near(battle.rng.next(), float(item.next), "Original room hero/brain construction consumes the same total RNG budget")
		battle.free()

static func _compare_bots(h: Node, session: Node, expected: Dictionary) -> void:
	h._check(session.seats.host_id == int(expected.host) and session.seats.next_bot_id == int(expected.nextBot), "Original bot ownership and monotonic per-room IDs")
	for side: String in expected.counts:
		h._check(session.seats.side_count(side) == int(expected.counts[side]), "Original shared human/bot side capacity")
	var actual: Array = []
	for player: int in session.seats.bots:
		var bot: Dictionary = session.seats.bots[player]
		actual.append({"player": player, "side": bot.side, "name": bot.name, "character": bot.character})
	Helper.compare(h, actual, expected.bots, "Original bot insertion order, name reuse/exhaustion, faction picks and phase guards")
