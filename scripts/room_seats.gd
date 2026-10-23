class_name RoomSeats
extends RefCounted

var members: Dictionary = {}
var routes: Dictionary = {}
var host_id := 0
var serial := 0
var no_human_at := 0
var bots: Dictionary = {}
var next_bot_id := 0

static func join_mode(value: String) -> String:
	return "spectator" if value == "spectator" else "player"

func admission_error(mode: String, capacity: int, super_enabled: bool) -> String:
	if join_mode(mode) == "spectator":
		return ""
	var players := members.values().filter(func(member): return member.mode == "player").size()
	if super_enabled and players > 0:
		return "room_join_super_only"
	return "room_join_full_" + str(capacity * 2) if players + bots.size() >= capacity * 2 else ""

func add(player: int, transport: int, token: String, side: String = "", mode: String = "player", character: String = "", display_name: String = "") -> bool:
	if player <= 0 or transport <= 0 or token.is_empty() or members.has(player) or routes.has(transport):
		return false
	for member: Dictionary in members.values():
		if member.token == token:
			return false
	serial += 1
	members[player] = {"transport": transport, "token": token, "connected": true, "generation": serial,
		"side": side, "mode": mode, "character": character, "name": display_name, "ready": false, "loaded": false}
	routes[transport] = player
	if host_id == 0:
		host_id = player
	return true

func player_for(transport: int) -> int:
	var player := int(routes.get(transport, 0))
	var member: Dictionary = members.get(player, {})
	return player if member.get("connected", false) and int(member.get("transport", 0)) == transport else 0

func transport_for(player: int) -> int:
	var member: Dictionary = members.get(player, {})
	return int(member.get("transport", 0)) if member.get("connected", false) else 0

func is_host_transport(transport: int) -> bool:
	return host_id > 0 and player_for(transport) == host_id

func side_count(side: String) -> int:
	var count := 0
	for member: Dictionary in members.values():
		if member.side == side:
			count += 1
	for bot: Dictionary in bots.values():
		if bot.side == side:
			count += 1
	return count

func choose_side(player: int, requested: String, capacity: int, super_enabled: bool) -> bool:
	if not members.has(player) or members[player].mode != "player":
		return false
	var side := requested if requested in ["SWARM", "STEEL"] or requested == "SUPER" and super_enabled else ""
	var member: Dictionary = members[player]
	if not side.is_empty() and side != member.side:
		var limit := 1 if side == "SUPER" else capacity
		if side_count(side) >= limit:
			return false
	member.side = side
	member.ready = false
	member.character = ""
	return true

func choose_character(player: int, character: String, heroes: Dictionary) -> bool:
	if not members.has(player) or members[player].mode != "player":
		return false
	var member: Dictionary = members[player]
	if not character.is_empty() and (not heroes.has(character) or member.side.is_empty() or member.side != "SUPER" and heroes[character].side not in [member.side, "MERC"]):
		return false
	member.character = character
	return true

func add_bot(side: String, capacity: int, names: Array, fallback_prefix: String) -> int:
	if side_count(side) >= capacity:
		return 0
	next_bot_id += 1
	var used: Dictionary = {}
	for bot: Dictionary in bots.values():
		used[bot.name] = true
	var chosen := fallback_prefix + str(next_bot_id)
	for candidate: String in names:
		if not used.has(candidate):
			chosen = candidate
			break
	var player := -next_bot_id
	bots[player] = {"side": side, "name": chosen, "character": ""}
	return player

func set_bot_character(player: int, character: String, heroes: Dictionary) -> bool:
	if not bots.has(player):
		return false
	if not character.is_empty() and (not heroes.has(character) or heroes[character].side not in [bots[player].side, "MERC"]):
		return false
	bots[player].character = character
	return true

func set_ready(player: int, ready: bool) -> bool:
	if not members.has(player):
		return false
	members[player].ready = ready
	return true

func set_loaded(player: int) -> bool:
	if not members.has(player):
		return false
	members[player].loaded = true
	return true

func reset_loaded() -> void:
	for member: Dictionary in members.values():
		member.loaded = false

func all_ready() -> bool:
	return _all_players("ready")

func all_loaded() -> bool:
	return _all_players("loaded")

func _all_players(flag: String) -> bool:
	var players := 0
	for member: Dictionary in members.values():
		if member.mode != "player" or member.side.is_empty():
			continue
		players += 1
		if not member[flag]:
			return false
	return players > 0

func owner_for(token: String) -> int:
	if token.is_empty():
		return 0
	for player: int in members:
		if members[player].token == token:
			return player
	return 0

func claim(token: String, transport: int) -> Dictionary:
	if token.is_empty() or transport <= 0:
		return {}
	for player: int in members:
		var member: Dictionary = members[player]
		if member.token != token:
			continue
		if routes.has(transport) and int(routes[transport]) != player:
			return {}
		var previous := int(member.transport)
		routes.erase(previous)
		# Source drop timers retain the seat allocation across every reattach.
		member.transport = transport
		member.connected = true
		routes[transport] = player
		return {"player": player, "previous": previous}
	return {}

func detach(transport: int, hold: bool) -> Dictionary:
	var player := player_for(transport)
	if player == 0:
		return {}
	var member: Dictionary = members[player]
	routes.erase(transport)
	member.connected = false
	member.transport = 0
	var result := {"player": player, "generation": int(member.generation), "removed": not hold}
	if not hold:
		erase(player)
	return result

func expire(player: int, generation: int) -> bool:
	var member: Dictionary = members.get(player, {})
	if member.is_empty() or member.connected or int(member.generation) != generation:
		return false
	return erase(player)

func erase(player: int) -> bool:
	if not members.has(player):
		return false
	var member: Dictionary = members[player]
	routes.erase(int(member.transport))
	members.erase(player)
	if host_id == player:
		host_id = int(members.keys()[0]) if not members.is_empty() else 0
	return true

func abandoned(now: int, duration: float) -> bool:
	if duration <= 0:
		return false
	for member: Dictionary in members.values():
		if member.connected:
			no_human_at = 0
			return false
	if no_human_at == 0:
		no_human_at = now
		return false
	return now - no_human_at >= duration
