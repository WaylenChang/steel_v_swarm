extends "res://scripts/main.gd"

const FAILURE := "fixture preparation failure"
var elapsed := 0.0
var requested := false
var failed := false
var finishing := false
var displayed := ""
var display_count := 0

func _ready() -> void:
	Controls.persist = false
	super._ready()
	network_test = false

func _physics_process(delta: float) -> void:
	elapsed += delta
	if elapsed > 18:
		_fail("NETWORK_FATAL_TIMEOUT")
		return
	if Session.dedicated:
		return
	if not displayed.is_empty() and not finishing:
		finishing = true
		if display_count != 1 or displayed != Content.label("fatal_battle") % FAILURE or _solo_session() or simulation == null or simulation.is_physics_processing() or Session.failure_reason != FAILURE:
			_fail("NETWORK_FATAL_REASON_OR_RESTART_POLICY")
			return
		await _fatal_restart()
		if Session.active or simulation != null or fatal_watchdog.shown or not Session.resume_token.is_empty():
			_fail("NETWORK_FATAL_CLOSE")
			return
		print("NETWORK_PASS fatalClose=true")
		print("NETWORK_FATAL_PASS currentRound=true firstReason=true remoteRestartHidden=true cleanClose=true")
		get_tree().quit()
		return
	if simulation == null or not Session.launch_announced:
		return
	super._physics_process(delta)
	if smoke_state_seen and not requested:
		requested = true
		_request_failure.rpc_id(1)

func _show_fatal(reason: String, force: bool = false) -> void:
	if fatal_watchdog.reveal(_fatal_phase(), force):
		display_count += 1
		displayed = reason

func _battle_failed(detail: String) -> void:
	if Session.dedicated:
		if detail != FAILURE:
			_fail("NETWORK_FATAL_AUTHORITY_REASON")
		return
	super._battle_failed(detail)

@rpc("any_peer", "call_remote", "reliable")
func _request_failure() -> void:
	if not Session.dedicated or failed or not Session.launch_announced:
		return
	var player := Session.seats.player_for(multiplayer.get_remote_sender_id())
	if player != Session.seats.host_id:
		_fail("NETWORK_FATAL_ROUTE")
		return
	failed = true
	Session.fail_battle(FAILURE)
	Session.fail_battle("second failure")
	if Session.failure_reason != FAILURE or simulation.is_physics_processing():
		_fail("NETWORK_FATAL_AUTHORITY_BARRIER")

func _room_cleared() -> void:
	if Session.dedicated:
		if not failed or not Session.active or Session.started or Session.simulation != null or not Session.failure_reason.is_empty():
			_fail("NETWORK_FATAL_LISTENER_CLEANUP")
			return
		print("NETWORK_FATAL_SERVER_PASS listener=true errorCleared=true seats=0")
	super._room_cleared()

func _fail(reason: String) -> void:
	push_error(reason)
	get_tree().quit(1)
