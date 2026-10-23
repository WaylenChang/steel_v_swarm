extends RefCounted

const SessionScript = preload("res://scripts/session.gd")
const Helper = preload("res://tests/status_suite.gd")
const PreparationTests = preload("res://tests/match_preparation_suite.gd")

class GateSimulation extends BattleSimulation:
	var launches := 0

	func begin_match(_map_data: Dictionary, _roster: Array) -> bool:
		launches += 1
		match_initialized = true
		return true

static func run(h: Node, fixtures: Dictionary) -> void:
	await PreparationTests.run(h, fixtures)
	if not fixtures.has("roomLoadingPrograms"):
		h._check(false, "Regenerate original room ready/load barrier references")
		return
	for program: Dictionary in fixtures.roomLoadingPrograms:
		var session := SessionScript.new()
		h.add_child(session)
		session.dedicated = true
		session.active = true
		session.config = {"team_size": 1, "ctrl": Controls.rules.defaultMode}
		var battle := GateSimulation.new()
		h.add_child(battle)
		battle.set_physics_process(false)
		for index in program.definitions.size():
			var definition: Array = program.definitions[index]
			var player := int(definition[0])
			var side: String = definition[3] if definition[3] != null else ""
			session.seats.add(player, 1000 + index, definition[1], side, definition[2])
			if definition[2] == "player" and not side.is_empty():
				session.roster.append({"peer": player, "side": side, "character": "t01" if side == "STEEL" else "s01", "bot": false})
		compare(h, session, battle, program.initial)
		for frame: Dictionary in program.frames:
			var operation: Array = frame.operation
			match operation[0]:
				"ready":
					session.seats.set_ready(session.seats.player_for(int(operation[1])), operation[2])
				"start":
					if session.seats.is_host_transport(int(operation[1])):
						session.start_battle()
				"loaded":
					session._set_loaded_for(int(operation[1]))
				"server_prepared":
					session.simulation = battle
					session.prepare_complete(battle, {})
				"maybe": session._maybe_launch()
				"claim": session.seats.claim(operation[1], int(frame.transport))
				"close":
					var detached := session.seats.detach(int(operation[1]), session.phase != "room")
					if detached.get("removed", false):
						var player := int(detached.player)
						session.roster = session.roster.filter(func(entry): return int(entry.peer) != player)
				"leave":
					var player := session.seats.player_for(int(operation[1]))
					session.seats.erase(player)
					session.roster = session.roster.filter(func(entry): return int(entry.peer) != player)
			compare(h, session, battle, frame)
		session.snapshot_timer.stop()
		session.free()
		battle.free()
	_server_world_gate(h)
	await _native_preparation(h)

static func compare(h: Node, session: Node, battle: GateSimulation, expected: Dictionary) -> void:
	h._check(session.phase == expected.phase and battle.launches == int(expected.launches), "Original ready cancellation, host launch and complete-player loaded barrier")
	h._check(session.seats.all_ready() == bool(expected.allReady) and session.seats.all_loaded() == bool(expected.allLoaded), "Original spectators/unseated exclusion and nonempty sided-player set")
	var members: Array = []
	for player: int in session.seats.members:
		var member: Dictionary = session.seats.members[player]
		members.append({"player": player, "ready": member.ready, "loaded": member.loaded, "connected": member.connected})
	Helper.compare(h, members, expected.members, "Original ready/loaded reset, held disconnected player and reattach state")

static func _server_world_gate(h: Node) -> void:
	var session := SessionScript.new()
	h.add_child(session)
	session.active = true
	session.dedicated = true
	session.config = {"team_size": 1}
	session.seats.add(42, 1000, "test-alpha", "STEEL")
	session.seats.set_ready(42, true)
	session.roster = [{"peer": 42, "side": "STEEL", "character": "t01", "bot": false}]
	var battle := GateSimulation.new()
	h.add_child(battle)
	battle.set_physics_process(false)
	session.start_battle()
	session._set_loaded_for(1000)
	h._check(session.phase == "loading" and battle.launches == 0, "Client readiness cannot bypass unfinished native server geometry")
	session.simulation = battle
	session.prepare_complete(battle, {})
	h._check(session.phase == "game" and battle.launches == 1, "Final native server preparation releases already-loaded players exactly once")
	session._maybe_launch()
	h._check(battle.launches == 1, "Duplicate completion cannot initialize a second authority match")
	session.snapshot_timer.stop()
	session.free()
	battle.free()

static func _native_preparation(h: Node) -> void:
	var battle := BattleSimulation.new()
	h.add_child(battle)
	var map_data := Content.map_variant(0, 1)
	var roster := [{"peer": 42, "side": "STEEL", "character": "t01", "bot": false},
		{"peer": 43, "side": "SWARM", "character": "s01", "bot": false}]
	var combat_seed := battle.rng.state
	await battle.setup(map_data, roster, {"time": "day", "season": "summer", "weather": "clear"}, true, true)
	await h.get_tree().physics_frame
	await h.get_tree().physics_frame
	h._check(battle.world != null and battle.units.is_empty() and battle.pilots.is_empty() and battle.clock == 0 and battle.wave == 0,
		"Native geometry preparation produces no authority units, waves or elapsed match time")
	h._check(not battle.is_physics_processing() and battle.rng.state == combat_seed,
		"Waiting for loaded players preserves authority physics and the combat RNG stream")
	h._check(battle.setup_complete, "Populated loading acceptance requires a complete authored native world: " + battle.setup_error)
	if not battle.setup_complete:
		battle.free()
		return
	h._check(battle.begin_match(map_data, roster) and battle.match_initialized and battle.pilots.size() == roster.size(),
		"One final loading barrier initializes the original authority population")
	battle.set_physics_process(false)
	var count := battle.units.size()
	var initialized_rng := battle.rng.state
	h._check(not battle.begin_match(map_data, roster) and battle.units.size() == count and battle.rng.state == initialized_rng,
		"Repeated launch cannot duplicate units or spend a second combat RNG budget")
	battle.free()
