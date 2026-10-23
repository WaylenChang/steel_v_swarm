extends RefCounted

const SessionScript = preload("res://scripts/session.gd")
const Helper = preload("res://tests/status_suite.gd")

class VisionSimulation extends Helper.SettlementSimulation:
	func visible_to_side(target: BattleUnit, side: String) -> bool:
		return target.side == side

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("roomMemberPrograms"):
		h._check(false, "Regenerate original room player selection and difficulty references")
		return
	for program: Dictionary in fixtures.roomMemberPrograms:
		var session := SessionScript.new()
		h.add_child(session)
		session.active = true
		session.config = {"team_size": int(program.capacity), "super": program.superMode, "env": {"bot_difficulty": Content.constants.DEFAULT_BOT_DIFF}}
		for index in program.definitions.size():
			var entry: Array = program.definitions[index]
			session.seats.add(int(entry[0]), 1000 + index, "test-" + str(index), entry[1], entry[2], entry[3])
			session.roster.append({"peer": int(entry[0]), "side": entry[1], "mode": entry[2], "character": entry[3], "bot": false})
		for side: String in program.bots:
			session.seats.add_bot(side, int(program.capacity), Content.constants.BOT_NAMES, Content.balance.rooms.botNamePrefix)
		compare(h, session, program.initial)
		for frame: Dictionary in program.frames:
			var operation: Array = frame.operation
			var transport := int(operation[1]) if operation[0] != "phase" else 0
			var player := session.seats.player_for(transport)
			match operation[0]:
				"side":
					var accepted := session._pick_side_for(transport, operation[2])
					if not accepted and not frame.errors.is_empty():
						var mode: String = session.seats.members[player].mode
						var capacity := 1 if operation[2] == Content.constants.SUPER_SIDE else int(program.capacity)
						var key: String = "room_spectator_side" if mode != "player" else "room_side_full_" + str(operation[2]) + "_" + str(capacity)
						h._check(Content.label(key) == frame.errors[0], "Original spectator/full-side notice comes from generated content")
				"character":
					if session.phase == "room":
						session.seats.choose_character(player, operation[2], Content.heroes)
					if not frame.errors.is_empty():
						h._check(Content.label("room_character_invalid") == frame.errors[0], "Original invalid faction/character notice comes from generated content")
				"ready": session.seats.set_ready(player, operation[2])
				"loaded": session.seats.set_loaded(player)
				"difficulty": session._set_bot_difficulty_for(transport, operation[2])
				"removeBot":
					if session.phase == "room" and session.seats.is_host_transport(transport):
						session.seats.bots.erase(int(operation[2]))
				"phase": session.phase = operation[1]
				"leave":
					session.seats.erase(player)
					session.roster = session.roster.filter(func(member): return int(member.peer) != player)
			compare(h, session, frame)
		session.free()
	_native_entry_guards(h)
	_live_vision(h)

static func compare(h: Node, session: Node, expected: Dictionary) -> void:
	h._check(session.seats.host_id == int(expected.host) and session.phase == expected.phase, "Original player selection phase and host continuity")
	h._check(session.config.env.bot_difficulty == expected.difficulty, "Original valid host-only room difficulty, including updates outside room phase")
	var members: Array = []
	for player: int in session.seats.members:
		var member: Dictionary = session.seats.members[player]
		members.append({"player": player, "side": member.side, "character": member.character,
			"mode": member.mode, "ready": member.ready, "loaded": member.loaded})
	Helper.compare(h, members, expected.members, "Original shared-side capacity, same-side reset, faction/mercenary/super picks and ready retention")
	for player: int in session.seats.members:
		h._check(session.seats.members[player].side == expected.vision[str(player)], "Original recipient vision follows live seat metadata in every phase")

static func _native_entry_guards(h: Node) -> void:
	var session := SessionScript.new()
	h.add_child(session)
	session.active = true
	session.config = {"team_size": 2}
	session.seats.add(42, 1000, "test-alpha", "STEEL", "player", "t01")
	session.roster = [{"peer": 42, "side": "STEEL", "character": "t01", "bot": false}]
	h._check(session._pick_side_for(1000, "") and session.seats.members[42].side == "" and session.roster[0].character == "", "Authority publishes an unseated observer and clears the previous character")
	h._check(not session.all_ready(), "An unseated host cannot launch a room without any sided human")
	h._check(session._pick_side_for(1000, "SWARM") and session.roster[0].side == "SWARM" and session.roster[0].character == "", "Authority publishes the cleared character with a successful side change")
	h._check(not session._pick_character_for(1000, "t01"), "A stale faction dropdown cannot select the previous faction's character")
	session.phase = "loading"
	h._check(session._pick_side_for(1000, "STEEL") and session.roster[0].side == "STEEL" and not session._pick_character_for(1000, "s01"), "Loading side edits publish metadata while character selection remains room-only")
	h._check(not session._pick_side_for(9999, "SWARM"), "A missing or revoked transport cannot change live seat metadata")
	session.free()

static func _live_vision(h: Node) -> void:
	var session := SessionScript.new()
	h.add_child(session)
	session.active = true
	session.phase = "game"
	session.config = {"team_size": 2}
	session.seats.add(42, 1000, "live-player", "STEEL", "player", "t01")
	session.roster = [{"peer": 42, "side": "STEEL", "character": "t01", "mode": "player", "bot": false}]
	var battle := VisionSimulation.new()
	h.add_child(battle)
	battle.set_physics_process(false)
	session.simulation = battle
	var actor := BattleUnit.new()
	h.add_child(actor)
	actor.configure({"id": 99431, "peer": 42, "kind": Content.heroes.t01.kind, "side": "STEEL", "character": "t01", "position": Vector3.ZERO})
	var other := BattleUnit.new()
	h.add_child(other)
	other.configure({"id": 99432, "peer": 43, "kind": Content.heroes.s01.kind, "side": "SWARM", "character": "s01", "position": Vector3.ZERO})
	battle.units = {actor.entity_id: actor, other.entity_id: other}
	battle.pilots = {42: actor, 43: other}
	for side: String in ["STEEL", "SWARM", "", "STEEL"]:
		h._check(session._pick_side_for(1000, side), "Live side switch succeeds without a new deployment")
		var state := session._state_for(42)
		var ids: Array = state.units.map(func(unit): return int(unit.id))
		h._check(ids.has(actor.entity_id) == (side in ["", "STEEL"]) and ids.has(other.entity_id) == (side in ["", "SWARM"]), "Seat faction selects the current fog slice; unseated players receive the global slice")
		for unit: Dictionary in state.units:
			h._check(unit.has("ammo") == (int(unit.id) == actor.entity_id), "A changed vision side never acquires the other faction's private owner fields")
		h._check(battle.pilots[42] == actor and actor.side == "STEEL" and actor.character == "t01" and battle.units.size() == 2,
			"Live metadata edits retain the original authority body, faction and character")
	session.seats.add(44, 1002, "late-unseated-player", "", "player", "")
	session.roster.append({"peer": 44, "side": "", "character": "", "mode": "player", "bot": false})
	h._check(session._pick_side_for(1002, "SWARM"), "A late unseated player can select a free metadata seat")
	var late := session._state_for(44)
	h._check(late.units.size() == 1 and int(late.units[0].id) == other.entity_id and not late.units[0].has("ammo"),
		"A late player without a pilot receives its seat's fog slice without another pilot's private state")
	h._check(not battle.pilots.has(44) and battle.units.size() == 2, "Post-launch side selection never fabricates a late player's actor")
	session.simulation = null
	session.free()
	battle.units.clear()
	battle.pilots.clear()
	battle.free()
	actor.free()
	other.free()
