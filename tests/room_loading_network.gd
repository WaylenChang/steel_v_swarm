extends "res://scripts/main.gd"

signal release_preparation

class HeldPreparation extends BattleSimulation:
	func setup(map_data: Dictionary, roster: Array, env: Dictionary, authority: bool, wait_for_launch: bool = false, prepared_world: BattleWorld = null) -> void:
		await super.setup(map_data, roster, env, authority, wait_for_launch, prepared_world)
		if not authority:
			var harness: Variant = get_parent()
			harness.geometry_built()
			if not harness.preparation_released:
				await harness.release_preparation

var elapsed := 0.0
var client_built := false
var preparation_released := false
var authority_checked := false
var started_checked := false
var client_actor := 0

func _ready() -> void:
	super._ready()
	network_test = false

func _create_simulation() -> BattleSimulation:
	return HeldPreparation.new()

func geometry_built() -> void:
	_client_geometry.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _client_geometry() -> void:
	if Session.dedicated and Session.seats.is_host_transport(multiplayer.get_remote_sender_id()):
		client_built = true

func _physics_process(delta: float) -> void:
	elapsed += delta
	if elapsed > 18:
		_fail("NETWORK_ROOM_LOADING_TIMEOUT")
		return
	if simulation == null:
		return
	if Session.dedicated:
		if not Session.world_prepared or not client_built:
			return
		var player := Session.seats.host_id
		var transport := Session.seats.transport_for(player)
		if not authority_checked:
			if Session.phase != "loading" or Session.launch_announced or not simulation.units.is_empty() or not simulation.pilots.is_empty() or simulation.clock != 0 or simulation.wave != 0 or simulation.is_physics_processing() or simulation.rng.state != SourceRng.new(42).state:
				_fail("NETWORK_ROOM_LOADING_PREMATURE_SETTLEMENT")
				return
			if Session.seats.members[player].loaded:
				_fail("NETWORK_ROOM_LOADING_UNCONFIRMED_CLIENT")
				return
			authority_checked = true
			_release.rpc_id(transport)
		elif Session.launch_announced and not started_checked:
			if not simulation.match_initialized or not Session.seats.members[player].loaded or not simulation.pilots.has(player):
				_fail("NETWORK_ROOM_LOADING_START_STATE")
				return
			simulation.set_physics_process(false)
			started_checked = true
			_started_verified.rpc_id(transport, simulation.pilots[player].entity_id)
		return
	super._physics_process(delta)
	if not started_checked or not preparation_released or not Session.launch_announced:
		return
	var pilot: BattleUnit = simulation.pilots.get(Session.player_id())
	if pilot == null:
		return
	if pilot.entity_id != client_actor or Session.phase != "game":
		_fail("NETWORK_ROOM_LOADING_CLIENT_IDENTITY")
		return
	print("NETWORK_PASS peer=", Session.player_id(), " units=", simulation.units.size())
	print("NETWORK_ROOM_LOADING_PASS ready=true heldClient=true noEarlySettlement=true rng=true oneLaunch=true")
	Session.stop()
	get_tree().quit()

@rpc("authority", "call_remote", "reliable")
func _release() -> void:
	if Session.phase != "loading" or Session.launch_announced or Session.world_prepared:
		_fail("NETWORK_ROOM_LOADING_CLIENT_BARRIER")
		return
	preparation_released = true
	release_preparation.emit()

@rpc("authority", "call_remote", "reliable")
func _started_verified(actor: int) -> void:
	client_actor = actor
	started_checked = true

func _fail(reason: String) -> void:
	push_error(reason)
	get_tree().quit(1)
