extends RefCounted

const Helper = preload("res://tests/status_suite.gd")
const SessionScript = preload("res://scripts/session.gd")
const FIELDS := ["load_started", "load_progress", "local_loaded", "last_snapshot", "last_frame", "disconnected_at", "hidden_at", "shown"]

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("fatalPrograms") or not fixtures.has("fatalReveals") or not fixtures.has("fatalRestarts") or not Content.balance.get("rooms", {}).has("fatal"):
		h._check(false, "Regenerate original fatal watchdog, visibility and UI references")
		return
	for program: Dictionary in fixtures.fatalPrograms:
		var watchdog := FatalWatchdog.new()
		watchdog.rules = Content.balance.rooms.fatal.duplicate(true)
		for key: String in FIELDS:
			watchdog.set(key, program.initial[key])
		var phase := "room"
		var connected := true
		var battle := true
		var displayed := ""
		for frame: Dictionary in program.frames:
			var operation: Array = frame.operation
			match operation[0]:
				"loading":
					phase = "loading"
					watchdog.loading(int(operation[1]))
				"set":
					for key: String in operation[1]:
						watchdog.set(key, operation[1][key])
				"phase": phase = operation[1]
				"connected": connected = operation[1]
				"battle": battle = operation[1]
				"hidden": watchdog.visibility(operation[1], int(operation[2]))
				"poll":
					var reason := watchdog.reason(phase, connected, battle, int(operation[1]))
					if not reason.is_empty() and watchdog.reveal(phase):
						displayed = reason
			for key: String in FIELDS:
				Helper.compare(h, watchdog.get(key), frame[key], "Original fatal clock/state: " + program.name + ": " + key)
			h._check(watchdog.hidden == frame.hidden and displayed == frame.reason, "Original strict timeout priority, phase gates and background suspension: " + program.name)
	for item: Dictionary in fixtures.fatalReveals:
		var watchdog := FatalWatchdog.new()
		var accepted := watchdog.reveal(item.phase, item.force)
		h._check(accepted == item.shown and watchdog.shown == item.shown, "Original fatal reveal phase/force gates")
		h._check(not watchdog.reveal(item.phase, item.force) or not item.shown, "An existing fatal reason cannot be replaced by a second failure")
		h._check(bool(item.restart) == (accepted and item.solo), "Original fatal restart is offered only in solo mode")
	for item: Dictionary in fixtures.fatalRestarts:
		h._check(item.cleared and item.hidden and bool(item.restarted) == (item.solo and item.saved) and bool(item.connected) == item.solo,
			"Original fatal restart always clears room/presentation state; only solo rebuilds transport and only a saved recipe replays")
	_failure_barrier(h)
	await _world_failure(h)

static func _failure_barrier(h: Node) -> void:
	var session := SessionScript.new()
	h.add_child(session)
	session.active = true
	session.started = true
	session.phase = "loading"
	session.round_id = 7
	var battle := BattleSimulation.new()
	h.add_child(battle)
	session.simulation = battle
	var received: Array[String] = []
	session.battle_failed.connect(func(reason): received.append(reason))
	session._receive_failure("old failure", 6)
	session._receive_failure("", 7)
	h._check(received.is_empty() and session.failure_reason.is_empty(), "Empty and stale-round failure packets cannot interrupt current preparation")
	session._receive_failure("original fixture failure", 7)
	session._receive_failure("second failure", 7)
	h._check(received == ["original fixture failure"] and not battle.is_physics_processing() and session.failure_reason == received[0],
		"The first current-round failure stops authority/replica stepping and preserves the original reason")
	session._dispose_match()
	h._check(session.failure_reason.is_empty(), "Disposing a failed match clears its failure barrier before another round")
	session.free()
	battle.free()

class RejectedWorld extends BattleWorld:
	func _build_failed(reason: String) -> void:
		build_error = reason

static func _world_failure(h: Node) -> void:
	var world := RejectedWorld.new()
	h.add_child(world)
	var map := Content.map_variant(0, int(Content.constants.TEAM.MIN))
	map.native_world = "res://assets/worlds/missing-fatal-fixture.res"
	await world.build(map, {"season": "summer", "time": "day", "weather": "clear"})
	h._check(not world.build_complete and not world.build_error.is_empty(), "A missing native world returns a recoverable preparation error without substituting terrain or terminating the app")
	world.free()
