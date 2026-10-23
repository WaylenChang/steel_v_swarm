extends "res://scripts/main.gd"

var elapsed := 0.0
var next_probe := 0.0
var requested := false
var resumed := false
var retained_battle: BattleSimulation
var retained_pilot: BattleUnit
var retained_player := 0
var retained_token := ""
var retained_count := 0
var saw_drop := false
var begins := 0

func _ready() -> void:
	Session.battle_started.connect(func(_settings, _players): begins += 1)
	resumed = OS.get_cmdline_user_args().has("--resume")
	super._ready()
	network_test = false

func _physics_process(delta: float) -> void:
	elapsed += delta
	if elapsed > 25:
		_fail("NETWORK_RECOVERY_TIMEOUT")
		return
	if Session.dedicated:
		if simulation != null and Session.launch_announced and retained_battle == null:
			retained_player = Session.seats.host_id
			retained_token = Session.seats.members[retained_player].token
			retained_battle = simulation
			retained_pilot = simulation.pilots.get(retained_player)
			retained_count = simulation.pilots.size()
			simulation.set_physics_process(false)
		if retained_battle != null and not saw_drop and not Session.seats.members.get(retained_player, {}).get("connected", true):
			saw_drop = true
			print("NETWORK_RECOVERY_HELD")
		return
	if requested or simulation == null or not Session.launch_announced or Session.reconnecting or elapsed < next_probe:
		return
	var pilot: BattleUnit = simulation.pilots.get(Session.player_id())
	if pilot == null:
		return
	if begins != 1 or not Session.credential_store.persist or Session.credential_store.record.get("token") != Session.resume_token:
		_fail("NETWORK_RECOVERY_CLIENT_CREDENTIAL")
		return
	_stage_probe.rpc_id(1, 1 if resumed else 0)
	next_probe = elapsed + 0.2

@rpc("any_peer", "call_remote", "reliable")
func _stage_probe(stage: int) -> void:
	if not Session.dedicated or retained_battle == null:
		return
	var peer := multiplayer.get_remote_sender_id()
	var player := Session.seats.player_for(peer)
	if player != retained_player or simulation != retained_battle or simulation.pilots.get(player) != retained_pilot or simulation.pilots.size() != retained_count or Session.seats.members[player].token != retained_token or stage == 1 and not saw_drop:
		_fail("NETWORK_RECOVERY_REPLACED_AUTHORITY_HERO")
		return
	_stage_result.rpc_id(peer, stage, player)

@rpc("authority", "call_remote", "reliable")
func _stage_result(stage: int, player: int) -> void:
	if requested:
		return
	requested = true
	if player != Session.player_id() or stage != (1 if resumed else 0):
		_fail("NETWORK_RECOVERY_IDENTITY")
		return
	if not resumed:
		print("NETWORK_RECOVERY_FIRST_PASS")
		# Process exit closes only the transport; a held seat is the restart contract.
		get_tree().quit()
		return
	var unit_count := simulation.units.size()
	await Session.leave()
	if Session.credential_store.load_save() != OK or not Session.credential_store.record.is_empty():
		_fail("NETWORK_RECOVERY_LEAVE_PERSISTENCE")
		return
	print("NETWORK_PASS peer=", player, " units=", unit_count)
	print("NETWORK_RECOVERY_PASS freshProcess=true stableHero=true restoredCredential=true explicitLeave=true")
	get_tree().quit()

func _room_cleared() -> void:
	if Session.dedicated:
		if not saw_drop or Session.started or not Session.seats.members.is_empty():
			_fail("NETWORK_RECOVERY_SERVER_CLEAR")
			return
		print("NETWORK_RECOVERY_SERVER_PASS")
	super._room_cleared()

func _fail(reason: String) -> void:
	push_error(reason)
	get_tree().quit(1)
