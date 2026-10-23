extends "res://scripts/main.gd"

var elapsed := 0.0
var editor_phase := 0
var bot_player := 0
var bot_name := ""
var bot_character := ""
var verified_actor := 0
var authority_checked := false

func _ready() -> void:
	super._ready()
	network_test = false
	for character: String in Content.heroes:
		if Content.heroes[character].side == "MERC":
			bot_character = character
			break

func _deploy_when_ready() -> void:
	if not Session.active or Session.phase != "room" or not Session.is_room_host() or bot_character.is_empty():
		return
	var bots: Array = Session.roster.filter(func(player): return player.get("bot", false))
	match editor_phase:
		0:
			editor_phase = 1
			Session.edit_bot("add", 0, "SWARM")
		1:
			if bots.size() != 1:
				return
			bot_player = int(bots[0].peer)
			bot_name = bots[0].name
			editor_phase = 2
			Session.edit_bot("character", bot_player, bot_character)
		2:
			if bots.size() != 1 or bots[0].character != bot_character:
				return
			editor_phase = 3
			Session.edit_bot("remove", bot_player)
		3:
			if not bots.is_empty():
				return
			editor_phase = 4
			Session.edit_bot("add", 0, "SWARM")
		4:
			if bots.size() != 1:
				return
			if int(bots[0].peer) == bot_player or bots[0].name != bot_name:
				_fail("NETWORK_ROOM_ROSTER_ID_OR_NAME_REUSE")
				return
			bot_player = int(bots[0].peer)
			editor_phase = 5
			Session.edit_bot("character", bot_player, bot_character)
		5:
			if bots.size() != 1 or bots[0].character != bot_character:
				return
			editor_phase = 6
			super._deploy_when_ready()
		6: super._deploy_when_ready()

func _physics_process(delta: float) -> void:
	elapsed += delta
	if elapsed > 18:
		_fail("NETWORK_ROOM_ROSTER_TIMEOUT phase=" + str(editor_phase))
		return
	if simulation == null or not Session.launch_announced:
		return
	if Session.dedicated:
		if authority_checked:
			return
		var bot: BattleUnit = simulation.pilots.get(-2)
		if bot == null or not bot.is_bot or bot.character != bot_character or not simulation.bot_brains.has(bot.entity_id) or Session.seats.next_bot_id != 2:
			_fail("NETWORK_ROOM_ROSTER_AUTHORITY_ASSIGNMENT")
			return
		var transport := Session.seats.transport_for(Session.seats.host_id)
		if Session._edit_bot_for(transport, "remove", -2, "") or not Session.seats.bots.has(-2):
			_fail("NETWORK_ROOM_ROSTER_EDIT_AFTER_START")
			return
		authority_checked = true
		simulation.set_physics_process(false)
		simulation.vision_until.STEEL = 10000
		_server_verified.rpc_id(transport, bot.entity_id)
		return
	super._physics_process(delta)
	if verified_actor == 0:
		return
	var replica: BattleUnit = simulation.units.get(verified_actor)
	if replica == null:
		return
	if replica.peer_id != bot_player or replica.character != bot_character or Session.edit_bot("remove", bot_player):
		_fail("NETWORK_ROOM_ROSTER_REPLICA_OR_PHASE_GUARD")
		return
	print("NETWORK_PASS peer=", Session.player_id(), " units=", simulation.units.size())
	print("NETWORK_ROOM_ROSTER_PASS add=true remove=true nameReuse=true stableBotIds=true mercenary=true authority=true phaseGuard=true")
	Session.stop()
	get_tree().quit()

@rpc("authority", "call_remote", "reliable")
func _server_verified(actor: int) -> void:
	verified_actor = actor

func _fail(reason: String) -> void:
	push_error(reason)
	get_tree().quit(1)
