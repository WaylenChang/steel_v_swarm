extends Node

signal lobby_changed
signal battle_started(config: Dictionary, roster: Array)
signal state_received(state: Dictionary)
signal body_event_received(event: Dictionary)
signal status_changed(key: String)

var roster: Array = []
var config: Dictionary = {}
var simulation: BattleSimulation
var chosen_character := "t01"
var chosen_side := "STEEL"
var active := false
var started := false
var dedicated := false
var snapshot_timer: Timer
var join_timer: Timer
var local_command := {}
var room_random := RandomNumberGenerator.new()

func _ready() -> void:
	room_random.randomize()
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): status_changed.emit("failed"); stop())
	multiplayer.server_disconnected.connect(func(): status_changed.emit("disconnected"); stop())
	multiplayer.peer_disconnected.connect(_on_disconnected)
	snapshot_timer = Timer.new()
	snapshot_timer.wait_time = 0.125
	snapshot_timer.timeout.connect(_broadcast_state)
	add_child(snapshot_timer)
	join_timer = Timer.new()
	join_timer.one_shot = true
	join_timer.wait_time = 8.0
	join_timer.timeout.connect(func():
		if active and not started and not multiplayer.is_server():
			status_changed.emit("failed")
			stop())
	add_child(join_timer)

func host(settings: Dictionary, port: int = 8620, transport: String = "offline") -> Error:
	if OS.has_feature("solo_web") and transport != "offline":
		return ERR_UNAVAILABLE
	stop()
	config = settings.duplicate(true)
	var control_mode: String = settings.get("ctrl", Controls.pref)
	if config.has("campaign"):
		var selection: Dictionary = config.campaign
		config = CampaignRules.settings(int(selection.get("index", -1)), selection.get("side", ""), selection.get("pilot", ""), room_random.randf() < 0.5)
		if config.is_empty() or not Content.campaign_available(int(config.campaign.index), config.campaign.side):
			return ERR_UNAVAILABLE
		chosen_side = config.campaign.side
		chosen_character = config.campaign.pilot
	config["ctrl"] = control_mode if control_mode in Controls.rules.get("modeKeys", []) else Controls.pref
	config["super"] = bool(config.get("super", false)) and not config.has("campaign")
	if config["super"]:
		if not Content.super_available():
			return ERR_UNAVAILABLE
		chosen_side = Content.constants.SUPER_SIDE
	elif chosen_side == Content.constants.SUPER_SIDE:
		return ERR_INVALID_PARAMETER
	var peer: MultiplayerPeer
	if transport == "offline":
		peer = OfflineMultiplayerPeer.new()
	elif transport == "websocket":
		var socket := WebSocketMultiplayerPeer.new()
		var error := socket.create_server(port)
		if error != OK:
			return error
		peer = socket
	else:
		var enet := ENetMultiplayerPeer.new()
		var error := enet.create_server(port, 10)
		if error != OK:
			return error
		peer = enet
	multiplayer.multiplayer_peer = peer
	active = true
	Controls.set_room(config.ctrl)
	if not dedicated:
		roster.append({"peer": 1, "side": chosen_side, "character": chosen_character, "bot": false})
	lobby_changed.emit()
	return OK

func join(address: String, port: int) -> Error:
	if OS.has_feature("solo_web"):
		return ERR_UNAVAILABLE
	stop()
	var peer: MultiplayerPeer
	if address.begins_with("ws://") or address.begins_with("wss://"):
		var socket := WebSocketMultiplayerPeer.new()
		var error := socket.create_client(address)
		if error != OK:
			return error
		peer = socket
	else:
		var enet := ENetMultiplayerPeer.new()
		var error := enet.create_client(address, port)
		if error != OK:
			return error
		peer = enet
	multiplayer.multiplayer_peer = peer
	active = true
	join_timer.start()
	status_changed.emit("connecting")
	return OK

func stop() -> void:
	if snapshot_timer != null:
		snapshot_timer.stop()
	if join_timer != null:
		join_timer.stop()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	roster.clear()
	config.clear()
	simulation = null
	active = false
	started = false
	local_command.clear()
	Controls.set_room("")
	lobby_changed.emit()

func set_control_mode(mode: String) -> bool:
	if not active or not multiplayer.is_server() or mode not in Controls.rules.get("modeKeys", []):
		return false
	config["ctrl"] = mode
	Controls.set_room(mode)
	if not multiplayer.get_peers().is_empty():
		_sync_lobby.rpc(config, roster)
	lobby_changed.emit()
	return true

func start_battle() -> void:
	if not active or not multiplayer.is_server() or started:
		return
	if config.has("campaign"):
		if roster.size() != 1:
			return
		var player: Dictionary = roster[0]
		roster = CampaignRules.roster(int(config.campaign.index), config.campaign.side, player.character, int(player.peer))
		if roster.is_empty():
			return
		config.campaign.pilot = player.character
	else:
		if config.get("super", false) and (roster.size() != 1 or roster[0].side != Content.constants.SUPER_SIDE):
			return
		var bot_peer := -1
		for side in ["SWARM", "STEEL"]:
			var count := roster.filter(func(player): return player.side == side).size()
			var used: Array = roster.map(func(player): return player.character)
			var available: Array = Content.heroes.keys().filter(func(id): return Content.heroes[id].side in [side, "MERC"] and not used.has(id))
			for slot in range(count, int(config.team_size)):
				if available.is_empty():
					break
				var character: String = available.pop_front()
				roster.append({"peer": bot_peer, "side": side, "character": character, "bot": true, "lane": slot % ceili(config.team_size / 2.0)})
				bot_peer -= 1
	started = true
	if not multiplayer.get_peers().is_empty():
		_begin.rpc(config, roster)
	battle_started.emit(config, roster)
	snapshot_timer.start()

func _on_connected() -> void:
	_register.rpc_id(1, chosen_character, chosen_side)

@rpc("any_peer", "call_remote", "reliable")
func _register(character: String, side: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 1 or not Content.heroes.has(character) or side not in ["SWARM", "STEEL", "SUPER"]:
		return
	if side == Content.constants.SUPER_SIDE and not config.get("super", false):
		return
	if side != Content.constants.SUPER_SIDE and Content.heroes[character].side not in [side, "MERC"]:
		return
	if roster.any(func(player): return int(player.peer) == sender):
		return
	if config.get("super", false) and (not roster.is_empty() or side != Content.constants.SUPER_SIDE):
		_notice.rpc_id(sender, "full")
		return
	if config.has("campaign") and (not roster.is_empty() or side != config.campaign.side or not CampaignRules.valid_selection(int(config.campaign.index), side, character)):
		_notice.rpc_id(sender, "full")
		return
	if started or roster.filter(func(player): return player.side == side).size() >= int(config.team_size):
		_notice.rpc_id(sender, "full")
		return
	roster.append({"peer": sender, "side": side, "character": character, "bot": false})
	_sync_lobby.rpc(config, roster)
	lobby_changed.emit()
	if dedicated and not started:
		get_tree().create_timer(2.0).timeout.connect(start_battle)

@rpc("authority", "call_remote", "reliable")
func _sync_lobby(settings: Dictionary, players: Array) -> void:
	config = settings
	roster = players
	Controls.set_room(config.get("ctrl", ""))
	join_timer.stop()
	lobby_changed.emit()
	status_changed.emit("ready")

@rpc("authority", "call_remote", "reliable")
func _begin(settings: Dictionary, players: Array) -> void:
	config = settings
	roster = players
	Controls.set_room(config.get("ctrl", ""))
	started = true
	join_timer.stop()
	battle_started.emit(config, roster)

@rpc("authority", "call_remote", "reliable")
func _notice(key: String) -> void:
	status_changed.emit(key)

func command(data: Dictionary) -> void:
	if simulation == null or not started:
		return
	local_command = data
	if multiplayer.is_server():
		simulation.submit_input(1, data)
	else:
		_receive_input.rpc_id(1, data)

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _receive_input(data: Dictionary) -> void:
	if multiplayer.is_server() and simulation != null:
		simulation.submit_input(multiplayer.get_remote_sender_id(), data)

func act(type: String, argument: String = "") -> void:
	if not started or simulation == null:
		return
	if multiplayer.is_server():
		simulation.action(1, type, argument)
	else:
		_action.rpc_id(1, type, argument)

@rpc("any_peer", "call_remote", "reliable", 2)
func _action(type: String, argument: String) -> void:
	if not multiplayer.is_server() or simulation == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	simulation.action(sender, type, argument)

func _broadcast_state() -> void:
	if simulation == null or not multiplayer.is_server():
		return
	simulation.flush_blood_hurt()
	simulation.flush_blast_feedback()
	for peer in multiplayer.get_peers():
		_snapshot.rpc_id(peer, simulation.snapshot(peer))
	state_received.emit(simulation.snapshot(1))
	simulation.events.clear()

func broadcast_body_event(event: Dictionary) -> void:
	if simulation == null or not multiplayer.is_server():
		return
	var actor: BattleUnit = simulation.units.get(int(event.actor))
	if actor == null:
		return
	for peer: int in multiplayer.get_peers():
		if event.has("only_peer") and int(event.only_peer) != peer:
			continue
		var viewer: BattleUnit = simulation.pilots.get(peer)
		if viewer == null or simulation.visible_to_side(actor, viewer.side):
			_body_event.rpc_id(peer, event)

# Short tactical notifications must not wait behind fragmented full snapshots.
@rpc("authority", "call_remote", "reliable", 4)
func _body_event(event: Dictionary) -> void:
	if simulation != null:
		simulation.receive_body_events([event], simulation.presentation_time())
		body_event_received.emit(event)

# Full snapshots exceed ENet's MTU; native reliable fragmentation stays off the input/action channels.
@rpc("authority", "call_remote", "reliable", 3)
func _snapshot(data: Dictionary) -> void:
	if simulation != null:
		simulation.apply_snapshot(data)
		state_received.emit(data)

func _on_disconnected(peer: int) -> void:
	if not multiplayer.is_server():
		return
	if started and simulation != null and simulation.pilots.has(peer):
		var unit: BattleUnit = simulation.pilots[peer]
		unit.is_bot = true
	else:
		roster = roster.filter(func(player): return int(player.peer) != peer)
		if active and not multiplayer.get_peers().is_empty():
			_sync_lobby.rpc(config, roster)
		lobby_changed.emit()
