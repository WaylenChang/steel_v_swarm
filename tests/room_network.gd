extends "res://scripts/main.gd"

class QueueSimulation extends BattleSimulation:
	var replay_trace: Array = []
	var cast_points: Array = []
	func submit_input(player: int, command: Dictionary) -> void:
		if command.get("recovery_fixture", false):
			replay_trace.append(["input", command.yaw])
		super.submit_input(player, command)
	func action(player: int, type: String, argument: String = "") -> void:
		if type == "defend" and argument == "toggle":
			replay_trace.append(["action", float(pilots[player].input_state.get("yaw", 0))])
		super.action(player, type, argument)
	func cast_player_at(player: int, _slot: String, source_point: Vector2) -> bool:
		replay_trace.append(["cast", float(pilots[player].input_state.get("yaw", 0))])
		cast_points.append(source_point)
		return true

var elapsed := 0.0
var stage := 0
var next_probe := 0.0
var ready_for_probe := false
var retained_battle: BattleSimulation
var retained_pilot: BattleUnit
var retained_player := 0
var retained_token := ""
var retained_count := 0
var offline_seen := false
var disconnects := 0
# Server-side disconnects stay zero on the client; count its own transport recoveries.
var recoveries := 0
var private_notices := 0
var begins := 0
var retained_name := ""

func _ready() -> void:
	Session.battle_started.connect(func(_settings, _players): begins += 1)
	super._ready()
	network_test = false

func _create_simulation() -> BattleSimulation:
	return QueueSimulation.new()

func _physics_process(delta: float) -> void:
	elapsed += delta
	if elapsed > 18:
		_fail("NETWORK_ROOM_TIMEOUT stage=%d disconnects=%d" % [stage, disconnects])
		return
	if simulation == null or Session.simulation == null:
		return
	if Session.dedicated:
		if retained_player == 0:
			for unit: BattleUnit in simulation.pilots.values():
				if unit.peer_id > 1:
					retained_player = unit.peer_id
					retained_pilot = unit
					retained_battle = simulation
					retained_count = simulation.pilots.size()
					simulation.set_physics_process(false)
		if retained_player > 0:
			var connected: bool = Session.seats.members.get(retained_player, {}).get("connected", false)
			if not connected and not offline_seen:
				disconnects += 1
				offline_seen = true
			elif connected:
				offline_seen = false
		return
	if Session.reconnecting or not Session.started or elapsed < next_probe:
		return
	var pilot: BattleUnit = simulation.pilots.get(Session.player_id())
	if pilot == null:
		return
	if retained_player == 0:
		retained_player = Session.player_id()
		retained_token = Session.resume_token
		retained_name = Session.local_member().get("name", "")
		retained_pilot = pilot
		retained_battle = simulation
		ready_for_probe = true
	if not ready_for_probe:
		return
	if retained_player != Session.player_id() or retained_token != Session.resume_token or retained_pilot != pilot or retained_battle != simulation or begins != 1 or Session.local_member().get("name", "") != retained_name:
		_fail("NETWORK_ROOM_REBUILT_OR_CHANGED_IDENTITY stage=%d disconnects=%d recoveries=%d player=%s token=%s pilot=%s battle=%s begins=%d name=%s" % [stage, disconnects, recoveries, retained_player == Session.player_id(), retained_token == Session.resume_token, retained_pilot == pilot, retained_battle == simulation, begins, Session.local_member().get("name", "") == retained_name])
		return
	var heading := float(stage + 1) * 0.25
	var mode: String = Controls.rules.modeKeys[stage % Controls.rules.modeKeys.size()]
	if not Session.is_room_host() or not Session.set_control_mode(mode):
		_fail("NETWORK_ROOM_HOST_PERMISSION")
		return
	if not Session.set_room_info("Round_" + str(stage), stage % 2 == 0):
		_fail("NETWORK_ROOM_METADATA_PERMISSION")
		return
	Session.command({"move": Vector2.ZERO, "yaw": heading, "pitch": 0.0, "view_mode": "fpv"})
	Session.act("aim", "on:" + str(stage + 1))
	if simulation.weather_start.season != Session.config.env.season or simulation.weather_start.time != Session.config.env.time or simulation.weather_start.weather != Session.config.env.weather or int(simulation.weather_schedule.lunarDay) != int(Session.config.env.lunarDay):
		_fail("NETWORK_ROOM_RESOLVED_ENVIRONMENT")
		return
	_probe.rpc_id(1, stage, retained_player, heading, mode, Session.config.env)
	next_probe = elapsed + 0.2

@rpc("any_peer", "call_remote", "reliable")
func _probe(request: int, player: int, heading: float, mode: String, environment: Dictionary) -> void:
	if not Session.dedicated or simulation == null or player != retained_player:
		return
	var sender := multiplayer.get_remote_sender_id()
	if Session.seats.player_for(sender) != player:
		_fail("NETWORK_ROOM_INBOUND_ROUTE")
		return
	if environment != Session.config.env or environment.season == "random" or environment.time == "random" or environment.weather == "random" or int(environment.lunarDay) < 1 or int(environment.lunarDay) > 30:
		_fail("NETWORK_ROOM_SHARED_ENVIRONMENT")
		return
	var pilot: BattleUnit = simulation.pilots.get(player)
	if pilot != retained_pilot or simulation != retained_battle or pilot.is_bot or simulation.pilots.size() != retained_count:
		_fail("NETWORK_ROOM_AUTHORITY_HERO_REPLACED")
		return
	if disconnects < request or absf(float(pilot.input_state.get("yaw", -1)) - heading) > 0.000001 or pilot.aim_request < request + 1 or Session.config.ctrl != mode:
		return
	if Session.config.get("room_name") != "Round_" + str(request) or Session.config.get("is_public") != (request % 2 == 0) or Session.seats.members[player].get("name", "") != "RoomClient_01":
		return
	var trace: Array = (simulation as QueueSimulation).replay_trace
	if trace.size() != request * 5:
		return
	for recovery in request:
		var first := 0.731 + float(recovery + 1)
		var second := -0.441 - float(recovery + 1)
		var expected: Array = [["input", first], ["action", first], ["cast", first], ["input", second], ["action", second]]
		for index in 5:
			if trace[recovery * 5 + index][0] != expected[index][0] or absf(float(trace[recovery * 5 + index][1]) - float(expected[index][1])) > 0.000001:
				_fail("NETWORK_ROOM_REPLAY_ORDER")
				return
		if (simulation as QueueSimulation).cast_points[recovery] != Vector2(recovery + 1.25, -recovery - 1.5):
			_fail("NETWORK_ROOM_CAST_POINT")
			return
	Session.notify_player(player, "waiting")
	_probe_result.rpc_id(sender, request, player, disconnects)

@rpc("authority", "call_remote", "reliable")
func _probe_result(request: int, player: int, count: int) -> void:
	if request != stage or not ready_for_probe:
		return
	if player != retained_player or count != stage or private_notices <= stage:
		_fail("NETWORK_ROOM_PRIVATE_ROUTE_OR_DISCONNECT_COUNT")
		return
	if stage == 2:
		ready_for_probe = false
		var unit_count := simulation.units.size()
		await Session.leave()
		if Session.active or Session.started or not Session.resume_token.is_empty():
			_fail("NETWORK_ROOM_EXPLICIT_LEAVE")
			return
		print("NETWORK_PASS peer=", retained_player, " units=", unit_count)
		print("NETWORK_ROOM_PASS reconnects=2 stableHero=true retainedScene=true input=true action=true queuedOrder=true host=true names=true roomInfo=true sharedEnvironment=true privateNotice=true explicitLeave=true")
		get_tree().quit()
		return
	stage += 1
	ready_for_probe = false
	Session.chosen_name = "Impersonated_" + str(stage)
	Session._server_disconnected()
	Session.command({"move": Vector2.ZERO, "yaw": 0.731 + float(stage), "pitch": 0.0, "recovery_fixture": true})
	Session.act("defend", "toggle")
	Session.cast_at("def", Vector2(stage + .25, -stage - .5))
	Session.command({"move": Vector2.ZERO, "yaw": -0.441 - float(stage), "pitch": 0.0, "recovery_fixture": true})
	Session.act("defend", "toggle")
	get_tree().create_timer(0.1).timeout.connect(func(): ready_for_probe = true)

func _status(key: String) -> void:
	if key == "waiting" and not Session.dedicated:
		private_notices += 1
	if key == "connecting" and Session.reconnecting and not Session.dedicated:
		recoveries += 1
	super._status(key)

func _room_cleared() -> void:
	if Session.dedicated:
		if not Session.active or Session.started or not Session.seats.members.is_empty() or Session.simulation != null:
			_fail("NETWORK_ROOM_LISTENER_OR_CLEAR_STATE")
			return
		print("NETWORK_ROOM_SERVER_CLEARED listener=true seats=0")
	super._room_cleared()

func _fail(reason: String) -> void:
	push_error(reason)
	get_tree().quit(1)
