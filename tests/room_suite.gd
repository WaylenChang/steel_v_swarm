extends RefCounted

const SessionScript = preload("res://scripts/session.gd")

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("roomSeatPrograms") or not fixtures.has("roomRetryDelays") or not fixtures.has("roomNoHumanPrograms") or not fixtures.has("roomOwnerPrograms") or not Content.balance.has("rooms"):
		h._check(false, "Regenerate original room lifecycle and retry references")
		return
	_owner_lifetimes(h, fixtures.roomOwnerPrograms)
	for program: Dictionary in fixtures.roomSeatPrograms:
		var seats := RoomSeats.new()
		var session := SessionScript.new()
		h.add_child(session)
		session.seats = seats
		session.active = true
		session.config = {"ctrl": program.initial.ctrl}
		var previous_mode: String = Controls.room
		seats.add(42, 1000, "test-alpha")
		seats.add(43, 1001, "test-beta")
		var leases: Dictionary = {}
		compare(h, seats, program.initial)
		for frame: Dictionary in program.frames:
			var operation: Array = frame.operation
			match operation[0]:
				"close":
					var transport := int(operation[1])
					var hold: bool = program.phase != "room" and float(Content.balance.rooms.dropMilliseconds) > 0
					var detached := seats.detach(transport, hold)
					if hold and not detached.is_empty():
						leases[transport] = detached
				"claim":
					var reclaimed := seats.claim(operation[1], int(frame.result.transport))
					h._check((not reclaimed.is_empty()) == bool(frame.result.success), "Original token reattach succeeds only for a retained seat")
					if not reclaimed.is_empty():
						h._check(int(reclaimed.player) == 42, "Reattach preserves the hero and host identity")
				"leave":
					seats.erase(seats.player_for(int(operation[1])))
				"mode":
					session._set_control_mode_for(int(operation[1]), operation[2])
				"wait":
					for transport: float in frame.expired:
						var lease: Dictionary = leases.get(int(transport), {})
						if not lease.is_empty():
							seats.expire(int(lease.player), int(lease.generation))
							leases.erase(int(transport))
			compare(h, seats, frame)
			h._check(session.config.ctrl == frame.ctrl, "Original host-only valid control changes survive reattach and host-seat transfer")
		Controls.set_room(previous_mode)
		session.free()
	for failure in fixtures.roomRetryDelays.size():
		h._near(Session.retry_delay(Content.balance.rooms, failure), float(fixtures.roomRetryDelays[failure]) / 1000.0, "Original connection retry backoff")
	_routes(h)
	for program: Dictionary in fixtures.roomNoHumanPrograms:
		var seats := RoomSeats.new()
		seats.add(42, 1000, "test-alpha")
		seats.add(43, 1001, "test-beta")
		for frame: Dictionary in program.frames:
			var operation: Array = frame.operation
			if operation[0] == "connected":
				var player := int(operation[1])
				if operation[2]:
					seats.claim("test-alpha" if player == 42 else "test-beta", 1000 if player == 42 else 1001)
				else:
					seats.detach(seats.transport_for(player), true)
			else:
				h._check(seats.abandoned(int(operation[1]), float(program.duration)) == bool(frame.abandoned), "Original no-human deadline includes every connected human and resets on recovery")
			h._check(seats.no_human_at == int(frame.since), "Original first-empty-tick timestamp and disabled no-human timeout")

static func compare(h: Node, seats: RoomSeats, expected: Dictionary) -> void:
	h._check(seats.host_id == int(expected.host), "Original host handoff includes retained offline seats")
	h._check(seats.members.size() == expected.members.size(), "Original phase-dependent disconnect and expiry membership")
	var index := 0
	for player: int in seats.members:
		if index >= expected.members.size():
			break
		var member: Dictionary = seats.members[player]
		var reference: Dictionary = expected.members[index]
		h._check(player == int(reference.player) and bool(member.connected) == bool(reference.connected), "Original seat order and reconnect/old-close interleaving")
		var transport := seats.transport_for(player)
		h._check((transport > 0) == bool(member.connected), "Only a connected seat has an outbound transport")
		if transport > 0:
			h._check(seats.player_for(transport) == player, "Inbound commands and private snapshots share the reclaimed seat route")
		index += 1

static func _owner_lifetimes(h: Node, programs: Array) -> void:
	for program: Dictionary in programs:
		var session := SessionScript.new()
		h.add_child(session)
		session.active = true
		session.started = true
		session.phase = "game"
		session.config = {"team_size": 1}
		session.seats.add(42, 1000, "owner", "STEEL", "player")
		session.seats.add(43, 1001, "observer", "", "spectator")
		session.roster = [{"peer": 42, "side": "STEEL", "character": "", "mode": "player", "bot": false},
			{"peer": 43, "side": "", "character": "", "mode": "spectator", "bot": false}]
		var battle := BattleSimulation.new()
		h.add_child(battle)
		battle.set_physics_process(false)
		session.simulation = battle
		var owner := BattleUnit.new()
		owner.entity_id = 991
		owner.peer_id = 42
		owner.clone_ids = [992]
		battle.add_child(owner)
		battle.pilots[42] = owner
		battle.units[991] = owner
		for id: int in [992, 993, 994]:
			var actor := BattleUnit.new()
			actor.entity_id = id
			battle.add_child(actor)
			battle.units[id] = actor
		battle.autonomous_summons = [993]
		battle.hologram_decoys = [994]
		var lease := {}
		for frame: Dictionary in program.frames:
			match frame.operation:
				"close": lease = session.seats.detach(1000, true)
				"expire": session.seats.expire(42, int(lease.generation))
				"leave": session.seats.erase(42)
				"last-leave": session.seats.erase(43)
			session._publish_membership()
			h._check(session.seats.members.keys() == frame.members.map(func(id): return int(id)), "Original owner departure and last observer membership")
			var active := session.simulation != null
			h._check(active == bool(frame.battleAlive), "Original battle survives an owner seat departure until the final human leaves")
			if active:
				h._check(battle.units.keys() == frame.actors.map(func(id): return int(id)) and battle.pilots.get(42) == owner and frame.ownerAlive,
					"Explicit leave and held-seat expiry retain the original owner and companion actors")
				h._check(owner.clone_ids.size() == int(frame.clones) and battle.autonomous_summons.size() == int(frame.summons) and battle.hologram_decoys.size() == int(frame.holograms),
					"Seat cleanup does not invent clone, summon or hologram despawn semantics")
			else:
				h._check(not battle.is_physics_processing(), "Final-human room cleanup stops authority simulation")
		session.simulation = null
		session.free()
		battle.free()

static func _routes(h: Node) -> void:
	var seats := RoomSeats.new()
	h._check(seats.add(42, 1000, "test-alpha") and seats.add(43, 1001, "test-beta"), "Distinct human seat allocation")
	h._check(not seats.add(44, 1000, "test-gamma") and not seats.add(44, 1002, "test-alpha"), "Transport and credential identities cannot be duplicated")
	h._check(seats.claim("unknown", 1002).is_empty() and seats.claim("test-alpha", 1001).is_empty(), "Invalid credential and occupied route do not take another seat")
	var replacement := seats.claim("test-alpha", 1002)
	h._check(int(replacement.get("previous", 0)) == 1000 and seats.player_for(1000) == 0 and seats.transport_for(42) == 1002, "Connected takeover revokes the replaced socket before accepting input")
	h._check(seats.detach(1000, true).is_empty() and seats.transport_for(42) == 1002, "A delayed replaced-socket close leaves the current connection intact")
	var lease := seats.detach(1002, true)
	seats.erase(42)
	seats.add(42, 1003, "test-gamma")
	seats.detach(1003, true)
	h._check(not seats.expire(42, int(lease.generation)) and seats.members.has(42), "An old timeout cannot expire a newly allocated seat with a recycled player ID")
