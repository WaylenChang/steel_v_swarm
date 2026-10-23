extends RefCounted

const SessionScript = preload("res://scripts/session.gd")
const Helper = preload("res://tests/status_suite.gd")

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("roomNames") or not fixtures.has("roomMetadataCreations") or not fixtures.has("roomMetadataPrograms"):
		h._check(false, "Regenerate original room name/privacy references")
		return
	for item: Dictionary in fixtures.roomNames:
		h._check(RoomMetadata.sanitize(item.input) == item.result, "Original ASCII/CJK allowlist, whitespace stripping, length cap and fallback name")
	for item: Dictionary in fixtures.roomMetadataCreations:
		h._check(RoomMetadata.sanitize(item.name) == item.roomName and RoomMetadata.public_at_creation(item.visibility) == bool(item.isPublic), "Original room creation name fallback and literal-false visibility semantics")
	for program: Dictionary in fixtures.roomMetadataPrograms:
		var session := SessionScript.new()
		h.add_child(session)
		session.active = true
		session.dedicated = true
		session.phase = program.phase
		session.config = {"team_size": 1, "room_name": "start", "is_public": true, "env": {"weather": "clear"}}
		session.seats.add(42, 1000, "fixture-a", "STEEL", "player", "t01", "Alpha")
		session.seats.add(43, 1001, "fixture-b", "", "spectator", "", "Beta")
		session.roster = [{"peer": 42, "name": "Alpha", "side": "STEEL", "character": "t01", "mode": "player", "bot": false},
			{"peer": 43, "name": "Beta", "side": "", "character": "", "mode": "spectator", "bot": false}]
		for frame: Dictionary in program.frames:
			var operation: Array = frame.operation
			var transport := 1000 + int(operation[1])
			if operation[0] == "leave":
				var player := session.seats.player_for(transport)
				session.seats.erase(player)
				session.roster = session.roster.filter(func(member): return int(member.peer) != player)
				session._publish_membership()
			else:
				session._set_room_info_for(transport, operation[2], operation[3])
			h._check(session.config.room_name == frame.roomName and session.config.is_public == bool(frame.isPublic) and session.seats.host_id == int(frame.host), "Original metadata permissions in every phase, including former and transferred host")
			h._check(session.config.env == {"weather": "clear"} and session.phase == program.phase, "Room metadata edits cannot reset battle phase or environment")
			var members: Array = []
			for player: int in session.seats.members:
				members.append({"id": player, "name": session.seats.members[player].name})
			Helper.compare(h, members, frame.members, "Room rename/privacy changes preserve human and spectator names")
			var published: Array = []
			for member: Dictionary in session.roster:
				published.append({"id": int(member.peer), "name": member.get("name", "")})
			Helper.compare(h, published, frame.members, "Canonical names remain public across every room phase")
		session.free()
