extends RefCounted

const SessionScript = preload("res://scripts/session.gd")
const Helper = preload("res://tests/status_suite.gd")

class DeliverySession extends SessionScript:
	var delivered: Array = []
	var recovery_order: Array = []
	var delivery_owners: Array = []
	func _identity(player: int, token: String, character: String, side: String) -> void:
		super._identity(player, token, character, side)
		recovery_order.append({"t": "reattach", "token": token})
	func _combat_connected() -> bool:
		return active and not reconnecting and not leaving
	func _deliver_combat(message: Dictionary) -> bool:
		if int(message.get("match", -1)) == round_id and phase == "game":
			if delivered.is_empty():
				recovery_order.append({"t": "flush"})
			delivery_owners.append(local_player_id)
			delivered.append(message.duplicate(true))
		return true

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("roomCommandQueues") or not fixtures.has("roomReconnectOrder"):
		h._check(false, "Regenerate original disconnected transport queue references")
		return
	for program: Dictionary in fixtures.roomCommandQueues:
		var queue := RoomCommandQueue.new()
		queue.capacity = int(Content.balance.rooms.queueCapacity)
		var wire := {"budget": -1, "sent": []}
		var deliver := func(message: Dictionary) -> bool:
			if int(wire.budget) == 0:
				return false
			if int(wire.budget) > 0:
				wire.budget -= 1
			wire.sent.append(message.duplicate(true))
			return true
		for frame: Dictionary in program.frames:
			var operation: Array = frame.operation
			match operation[0]:
				"connected": queue.connected = operation[1]
				"budget": wire.budget = int(operation[1])
				"send": queue.send(operation[1], deliver)
				"now": queue.send(operation[1], deliver, true)
				"flush": queue.flush(deliver)
				"kill": queue.clear()
			h._check(queue.connected == bool(frame.connected), "Original send-race and partial-flush connected state")
			Helper.compare(h, queue.pending, frame.pending, "Original latest-N bounded queue, failed-head retention and immediate-send rules")
			Helper.compare(h, wire.sent, frame.sent, "Original disconnected input/action FIFO replay without resending successful prefix")
	_credential_files(h)
	_session_queue(h, fixtures.roomReconnectOrder)
	_session_credentials(h)

static func _credential_files(h: Node) -> void:
	var saved := RoomCredential.new()
	saved.persist = true
	saved.path = "user://room-credential-fixture-%d.cfg" % Time.get_ticks_usec()
	h._check(saved.load_save() == OK and saved.record.is_empty(), "Missing recovery file starts without a seat")
	h._check(saved.remember("wss://example.invalid:8620", 8620, "fixture-token") == OK, "Native ConfigFile stores endpoint and opaque seat credential")
	var restored := RoomCredential.new()
	restored.persist = true
	restored.path = saved.path
	h._check(restored.load_save() == OK and restored.record == saved.record, "New application state recovers the exact endpoint and credential")
	for invalid: Dictionary in [{}, {"address": "", "port": 8620, "token": "fixture"}, {"address": "localhost", "port": "8620", "token": "fixture"},
			{"address": "localhost", "port": 0, "token": "fixture"}, {"address": "localhost", "port": 65536, "token": "fixture"}, {"address": "localhost", "port": 8620, "token": false}]:
		h._check(not RoomCredential.valid(invalid), "Malformed saved endpoints and non-string credentials cannot start recovery")
	var incomplete := ConfigFile.new()
	incomplete.set_value("seat", "token", "fixture-token")
	h._check(incomplete.save(saved.path) == OK and restored.load_save() == ERR_INVALID_DATA and restored.record.is_empty(), "Partial credential files cannot reuse stale in-memory endpoints")
	h._check(saved.clear(true) == OK and restored.load_save() == OK and restored.record.is_empty(), "Explicit new-session selection clears malformed or older saved credentials")
	h._check(saved.remember("127.0.0.1", 8620, "fixture-token") == OK and restored.load_save() == OK, "A successor process loads the prior saved seat")
	h._check(restored.remember("127.0.0.1", 8620, "fixture-token") == OK and saved.clear() == OK, "A replaced process releases only its saved revision")
	var successor := RoomCredential.new()
	successor.persist = true
	successor.path = saved.path
	h._check(successor.load_save() == OK and successor.record.get("token") == "fixture-token", "Old-process revocation cannot erase the successor's credential")
	h._check(restored.clear() == OK and successor.load_save() == OK and successor.record.is_empty(), "Current owner explicitly leaves without retaining an expired token")
	h._check(DirAccess.remove_absolute(ProjectSettings.globalize_path(saved.path)) == OK, "Remove isolated recovery fixture file")

static func _session_queue(h: Node, source_order: Array) -> void:
	var session := DeliverySession.new()
	h.add_child(session)
	session.active = true
	session.started = true
	session.phase = "game"
	session.round_id = 7
	session.launch_announced = true
	session.reconnecting = true
	session.connection_address = "127.0.0.1"
	session.connection_port = 8620
	var battle := BattleSimulation.new()
	h.add_child(battle)
	battle.set_physics_process(false)
	session.simulation = battle
	var expected: Array = []
	for index in int(Content.balance.rooms.queueCapacity) + 5:
		if index % 3 == 0:
			session.act("aim", "on:" + str(index))
			expected.append({"kind": "action", "type": "aim", "argument": "on:" + str(index), "match": 7})
		elif index % 3 == 1:
			var point := Vector2(index + .25, -index - .5)
			session.cast_at("def", point)
			expected.append({"kind": "cast", "slot": "def", "point": point, "match": 7})
		else:
			var input := {"move": Vector2.ZERO, "yaw": float(index), "pitch": 0.0}
			session.command(input)
			expected.append({"kind": "input", "data": input.duplicate(), "match": 7})
			input.yaw = -1.0
		if expected.size() > int(Content.balance.rooms.queueCapacity):
			expected.pop_front()
	h._check(session.delivered.is_empty(), "Disconnected authority routes receive no speculative combat settlement")
	session._flush_commands()
	h._check(session.delivered.is_empty(), "Queue cannot flush before logical-seat reclaim completes")
	var recovery: Dictionary = source_order.filter(func(frame): return frame.token != null and not String(frame.token).is_empty())[0]
	session._identity(42, recovery.token, "t01", "STEEL")
	session._begin({}, [], "game", 7)
	Helper.compare(h, session.delivered, expected, "Session recovery flush preserves bounded input/action order and immutable accepted payloads")
	Helper.compare(h, session.recovery_order, recovery.order, "Original credential-first recovery order; native flush waits for reclaim confirmation")
	h._check(session.delivery_owners.all(func(player): return player == 42), "Queued commands use the reclaimed logical seat rather than transport identity")
	session.command_queue.connected = false
	session.command_queue.send({"kind": "action", "type": "reload", "argument": "light", "match": 6}, func(_message): return false)
	session._flush_commands()
	h._check(session.delivered.size() == expected.size() and session.command_queue.pending.is_empty(), "Previous-match actions are removed rather than replayed into a rematch")
	session.reconnecting = true
	session.act("reload", "light")
	session._dispose_match()
	h._check(session.command_queue.pending.is_empty(), "Returning to room cancels queued combat commands")
	session.free()
	battle.free()

static func _session_credentials(h: Node) -> void:
	var session := SessionScript.new()
	h.add_child(session)
	session.connection_address = "127.0.0.1"
	session.connection_port = 8620
	session._identity(42, "fixture-token", "t01", "STEEL")
	var remembered: Dictionary = session.credential_store.record.duplicate()
	session.stop()
	h._check(not remembered.is_empty() and session.credential_store.record == remembered and session.resume_token.is_empty(), "Transport shutdown preserves saved recovery while clearing live identity")
	session._reattach_failed()
	h._check(session.credential_store.record.is_empty(), "Expired seat rejection clears recovery instead of retrying forever")
	session.credential_store.remember("127.0.0.1", 8620, "fixture-token")
	session._replaced()
	h._check(session.credential_store.record.is_empty(), "Replaced native route cannot reclaim its revoked credential on restart")
	session.credential_store.remember("127.0.0.1", 8620, "fixture-token")
	session.leave()
	h._check(session.credential_store.record.is_empty(), "Explicit local leave clears durable credentials even while disconnected")
	session.free()
