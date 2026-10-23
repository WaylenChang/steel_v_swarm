extends "res://scripts/main.gd"

var elapsed := 0.0
var edit_phase := 0
var mercenary := ""
var blocker := 0
var full_seen := false
var authority_started := false
var difficulty_verified := false
var human_actor := 0
var bot_actor := 0
var authority_phase := 0
var live_phase := 0
var live_ack := -1

func _ready() -> void:
	super._ready()
	network_test = false
	for character: String in Content.heroes:
		if Content.heroes[character].side == "MERC":
			mercenary = character
			break

func _deploy_when_ready() -> void:
	if not Session.active or Session.phase != "room" or not Session.is_room_host() or mercenary.is_empty():
		return
	var member := Session.local_member()
	var bots: Array = Session.roster.filter(func(player): return player.get("bot", false))
	match edit_phase:
		0:
			edit_phase = 1
			Session.edit_bot("add", 0, "SWARM")
		1:
			if bots.size() != 1:
				return
			blocker = int(bots[0].peer)
			edit_phase = 2
			Session.set_ready(true)
		2:
			if not member.get("ready", false):
				return
			edit_phase = 3
			Session.pick_character(mercenary)
		3:
			if member.character != mercenary:
				return
			if not member.ready:
				_fail("NETWORK_ROOM_MEMBER_CHARACTER_CLEARED_READY")
				return
			edit_phase = 4
			Session.pick_side("SWARM")
		4:
			if not full_seen:
				return
			if member.side != "STEEL" or not member.ready or member.character != mercenary:
				_fail("NETWORK_ROOM_MEMBER_FULL_SIDE_MUTATED_STATE")
				return
			edit_phase = 5
			Session.edit_bot("remove", blocker)
		5:
			if not bots.is_empty():
				return
			edit_phase = 6
			Session.pick_side("SWARM")
		6:
			if member.side != "SWARM":
				return
			if member.ready or not String(member.character).is_empty():
				_fail("NETWORK_ROOM_MEMBER_SIDE_DID_NOT_CLEAR_SELECTION")
				return
			edit_phase = 7
			Session.pick_character(mercenary)
		7:
			if member.character != mercenary:
				return
			edit_phase = 8
			Session.set_bot_difficulty("high")
		8:
			if Session.config.get("env", {}).get("bot_difficulty") != "high":
				return
			edit_phase = 9
			super._deploy_when_ready()
		9: super._deploy_when_ready()

func _status(key: String) -> void:
	if key == "room_side_full_SWARM_1":
		full_seen = true
		_deploy_when_ready.call_deferred()
	super._status(key)

func _physics_process(delta: float) -> void:
	elapsed += delta
	if elapsed > 18:
		_fail("NETWORK_ROOM_MEMBER_TIMEOUT phase=" + str(edit_phase))
		return
	if simulation == null or not Session.launch_announced:
		return
	if Session.dedicated:
		var human: BattleUnit = simulation.pilots.get(Session.seats.host_id)
		var bot: BattleUnit = simulation.pilots.get(-2)
		if human == null or bot == null:
			_fail("NETWORK_ROOM_MEMBER_DEPLOYMENT")
			return
		var brain: BotBrain = simulation.bot_brains.get(bot.entity_id)
		if human.side != "SWARM" or human.character != mercenary or brain == null or brain.difficulty != Content.constants.BOT_DIFF.high or simulation.bot_difficulty != "high":
			_fail("NETWORK_ROOM_MEMBER_AUTHORITY_SELECTION_OR_DIFFICULTY")
			return
		var transport := Session.seats.transport_for(Session.seats.host_id)
		if authority_phase == 0:
			authority_phase = 1
			simulation.set_physics_process(false)
			simulation.vision_until.SWARM = 10000
			_started.rpc_id(transport, human.entity_id, bot.entity_id)
		elif authority_phase == 1 and Session.config.get("env", {}).get("bot_difficulty") == "novice":
			authority_phase = 2
			_difficulty_confirmed.rpc_id(transport)
		return
	super._physics_process(delta)
	if not authority_started or not difficulty_verified:
		return
	var pilot: BattleUnit = simulation.units.get(human_actor)
	var bot: BattleUnit = simulation.units.get(bot_actor)
	if pilot == null or bot == null:
		return
	if pilot.peer_id != Session.player_id() or pilot.side != "SWARM" or pilot.character != mercenary or Session.pick_character("t01"):
		_fail("NETWORK_ROOM_MEMBER_REPLICA_OR_IN_GAME_CHARACTER_EDIT")
		return
	var member := Session.local_member()
	match live_phase:
		0:
			live_phase = 1
			Session.pick_side("SWARM")
			_live_probe.rpc_id(1, 1)
			return
		1:
			if live_ack != 1 or member.side != "SWARM" or member.ready or not String(member.character).is_empty():
				return
			live_phase = 2
			Session.pick_side("")
			_live_probe.rpc_id(1, 2)
			return
		2:
			if live_ack != 2 or not String(member.side).is_empty() or hud_snapshot.get("vision_side", "pending") != "":
				return
			if not hud_snapshot.units.any(func(unit): return int(unit.id) == bot_actor):
				_fail("NETWORK_ROOM_MEMBER_GLOBAL_VISION")
				return
			live_phase = 3
			Session.pick_side("SWARM")
			_live_probe.rpc_id(1, 3)
			return
		3:
			if live_ack != 3 or member.side != "SWARM" or hud_snapshot.get("vision_side", "pending") != "SWARM":
				return
			live_phase = 4
			Session.pick_side("STEEL")
			_live_probe.rpc_id(1, 4)
			return
		4:
			if live_ack != 4 or member.side != "SWARM":
				return
	print("NETWORK_PASS peer=", Session.player_id(), " units=", simulation.units.size())
	print("NETWORK_ROOM_MEMBER_PASS sideCapacity=true sideReset=true characterKeepsReady=true mercenary=true hostDifficulty=true existingBrainUnchanged=true liveSeat=true globalVision=true existingHeroUnchanged=true")
	Session.stop()
	get_tree().quit()

@rpc("authority", "call_remote", "reliable")
func _started(human: int, bot: int) -> void:
	human_actor = human
	bot_actor = bot
	authority_started = true
	Session.set_bot_difficulty("novice")

@rpc("authority", "call_remote", "reliable")
func _difficulty_confirmed() -> void:
	difficulty_verified = true

@rpc("any_peer", "call_remote", "reliable")
func _live_probe(stage: int) -> void:
	if not Session.dedicated or simulation == null:
		return
	var transport := multiplayer.get_remote_sender_id()
	var player := Session.seats.player_for(transport)
	if player != Session.seats.host_id:
		_fail("NETWORK_ROOM_MEMBER_LIVE_ROUTE")
		return
	var member: Dictionary = Session.seats.members[player]
	var actor: BattleUnit = simulation.pilots.get(player)
	var expected := "" if stage == 2 else "SWARM"
	if actor == null or actor.side != "SWARM" or actor.character != mercenary or member.side != expected or member.ready or not String(member.character).is_empty():
		_fail("NETWORK_ROOM_MEMBER_LIVE_AUTHORITY_MUTATION")
		return
	_live_confirmed.rpc_id(transport, stage)

@rpc("authority", "call_remote", "reliable")
func _live_confirmed(stage: int) -> void:
	live_ack = stage

func _fail(reason: String) -> void:
	push_error(reason)
	get_tree().quit(1)
