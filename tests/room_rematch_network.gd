extends "res://scripts/main.gd"

class RematchSimulation extends BattleSimulation:
	func finish_fixture() -> void:
		if not authoritative or over:
			return
		for unit: BattleUnit in units.values():
			if unit.kind == "base" and unit.side == "SWARM":
				damage(null, unit, {"pen": 9999.0}, 1e12, false, {"weather_weapon": false}, false)
				return

var elapsed := 0.0
var launches := 0
var first_round := -1
var first_registry: RoomSeats
var first_token := ""
var first_bots: Array = []
var ended_first := false
var returned := false
var requested_return := false
var sent_old_packets := false
var old_packets := 0
var snapshot_barrier := false
var event_barrier := false
var verified := false

func _ready() -> void:
	super._ready()
	network_test = false
	Session.room_returned.connect(_verify_return)
	Session.state_received.connect(func(state):
		if float(state.get("clock", 0)) == 99999.0:
			old_packets += 1)
	Session.body_event_received.connect(func(event):
		if event.get("rematch_fixture", false):
			old_packets += 1)

func _create_simulation() -> BattleSimulation:
	return RematchSimulation.new()

func _battle_launched() -> void:
	super._battle_launched()
	launches += 1
	if launches == 1:
		first_round = Session.round_id
		if Session.dedicated:
			first_registry = Session.seats
			first_token = Session.seats.members[Session.seats.host_id].token
			first_bots = Session.seats.bots.keys()

func _verify_return() -> void:
	returned = true
	if Session.started or Session.world_prepared or Session.launch_announced or not Session.pending_snapshot.is_empty() or not Session.local_command.is_empty():
		_fail("NETWORK_REMATCH_RESET")
		return
	if not Session.dedicated:
		return
	if Session.seats != first_registry or Session.seats.bots.keys() != first_bots or Session.seats.members[Session.seats.host_id].token != first_token:
		_fail("NETWORK_REMATCH_SEATS")
		return
	for member: Dictionary in Session.seats.members.values():
		if member.ready or member.loaded:
			_fail("NETWORK_REMATCH_FLAGS")

func _physics_process(delta: float) -> void:
	elapsed += delta
	if elapsed > 35:
		_fail("NETWORK_REMATCH_TIMEOUT")
		return
	if simulation == null or not Session.launch_announced:
		return
	if Session.dedicated:
		if launches == 1 and not ended_first:
			ended_first = true
			(simulation as RematchSimulation).finish_fixture()
		elif launches == 2 and not sent_old_packets:
			if not returned or Session.round_id <= first_round or not simulation.match_initialized or simulation.over:
				_fail("NETWORK_REMATCH_SECOND_LAUNCH")
				return
			simulation.set_physics_process(false)
			sent_old_packets = true
			var peer: int = Session.seats.transport_for(Session.seats.host_id)
			Session._snapshot.rpc_id(peer, {"_match": first_round, "clock": 99999.0, "units": []})
			Session._body_event.rpc_id(peer, {"rematch_fixture": true}, first_round)
			_snapshot_drained.rpc_id(peer)
			_event_drained.rpc_id(peer)
		return
	super._physics_process(delta)
	if launches == 1 and Session.phase == "over" and simulation.over and not requested_return:
		requested_return = true
		Session.request_return_to_room()
	elif launches == 2 and snapshot_barrier and event_barrier and not verified:
		if not simulation.pilots.has(Session.player_id()):
			return
		if not returned or old_packets != 0 or Session.round_id <= first_round or simulation.over or not simulation.pilots.has(Session.player_id()):
			_fail("NETWORK_REMATCH_STALE_PACKET")
			return
		verified = true
		_client_verified.rpc_id(1)

@rpc("authority", "call_remote", "reliable", 3)
func _snapshot_drained() -> void:
	snapshot_barrier = true

@rpc("authority", "call_remote", "reliable", 4)
func _event_drained() -> void:
	event_barrier = true

@rpc("any_peer", "call_remote", "reliable")
func _client_verified() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if not Session.dedicated or not Session.seats.is_host_transport(peer) or launches != 2 or not sent_old_packets:
		_fail("NETWORK_REMATCH_ACK")
		return
	print("NETWORK_REMATCH_SERVER_PASS")
	_confirmed.rpc_id(peer)

@rpc("authority", "call_remote", "reliable")
func _confirmed() -> void:
	print("NETWORK_PASS peer=", Session.player_id(), " units=", simulation.units.size())
	print("NETWORK_REMATCH_PASS launches=2 retainedSeats=true staleChannels=true")
	Session.stop()
	get_tree().quit()

func _fail(reason: String) -> void:
	push_error(reason)
	get_tree().quit(1)
