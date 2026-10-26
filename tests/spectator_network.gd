extends "res://scripts/main.gd"

var observer := OS.get_cmdline_user_args().has("--observer") or OS.get_cmdline_user_args().has("--spectator")
var explicit_observer := OS.get_cmdline_user_args().has("--spectator")
var late_join := OS.get_cmdline_user_args().has("--late")
var elapsed := 0.0
var edit_sent := false
var authority_frozen := false
var exercised := false
var confirmed := false
var ready_printed := false
var authority_checkpoint: Array = []

func _ready() -> void:
	super._ready()
	network_test = false

func _receive_state(packet: Dictionary) -> void:
	if observer:
		if explicit_observer:
			var member := Session.local_member()
			if member.get("mode") != "spectator" or not String(member.side).is_empty():
				_fail("NETWORK_SPECTATOR_MODE_IDENTITY")
				return
		for actor: Dictionary in packet.units:
			for key: String in ActorSnapshot.OWNER_FIELDS:
				if actor.has(key):
					_fail("NETWORK_SPECTATOR_PRIVATE_FIELD " + key)
					return
			for key: String in ["iframe_cooldown_until", "phase_damage", "no_reload_until"]:
				if actor.get("status", {}).has(key):
					_fail("NETWORK_SPECTATOR_PRIVATE_STATUS " + key)
					return
		for event: Dictionary in packet.events:
			if event.get("type") == "weapon_fire" and (event.has("empty_heavy") or event.has("aim_request")):
				_fail("NETWORK_SPECTATOR_PRIVATE_FIRE_EVENT")
				return
	super._receive_state(packet)

func _deploy_when_ready() -> void:
	if not Session.active or Session.phase != "room":
		return
	var member := Session.local_member()
	if member.is_empty():
		return
	if observer:
		if not edit_sent:
			edit_sent = true
			if not Session.pick_side(""):
				_fail("NETWORK_SPECTATOR_UNSEAT_REJECTED")
			return
		if not String(member.side).is_empty():
			return
	elif not member.ready:
		Session.set_ready(true)
		return
	var humans := Session.roster.filter(func(row): return not row.get("bot", false))
	if late_join and not observer and Session.all_ready() and Session.is_room_host():
		Session.request_start_battle()
		return
	if humans.size() == 2 and humans.filter(func(row): return String(row.side).is_empty()).size() == 1 and Session.all_ready() and Session.is_room_host():
		Session.request_start_battle()

func _physics_process(delta: float) -> void:
	elapsed += delta
	if elapsed > (35 if late_join else 18):
		_fail("NETWORK_SPECTATOR_TIMEOUT")
		return
	if simulation == null:
		return
	if Session.dedicated:
		if Session.launch_announced and not authority_frozen:
			simulation.set_physics_process(false)
			authority_frozen = true
			authority_checkpoint = [simulation.pilots.size(), simulation.clock, simulation.rng.state, simulation.projectile_rng.state]
			for player: int in Session.seats.members:
				if simulation.pilots.has(player) != (not String(Session.seats.members[player].side).is_empty()):
					_fail("NETWORK_SPECTATOR_AUTHORITY_ROSTER")
		return
	super._physics_process(delta)
	if not Session.launch_announced:
		return
	if late_join and not observer and not ready_printed:
		ready_printed = true
		print("LATE_SPECTATOR_READY")
	if observer and not exercised:
		if not is_instance_valid(spectator_camera) or spectator_camera.rows.size() < 2:
			return
		if simulation.pilots.has(Session.player_id()) or get_viewport().get_camera_3d() != spectator_camera:
			_fail("NETWORK_SPECTATOR_CAMERA_OWNERSHIP")
			return
		var saved_command := Session.local_command.duplicate(true)
		_spectator_command("special")
		_advance_spectator(0)
		var target := spectator_camera.state.target(spectator_camera.rows.values())
		if target.is_empty() or spectator_camera.state.mode != "fpv" or target.unit.model.visible:
			_fail("NETWORK_SPECTATOR_FPV_BODY")
			return
		var info: Dictionary = spectator_camera.state.hud(spectator_camera.rows.values())
		if info.light.ammo != null or info.heavy.ammo != null or info.lift != null or info.mobil != null or not ammo_label.text.contains(Content.balance.spectator.unknownName):
			_fail("NETWORK_SPECTATOR_PRIVATE_HUD")
			return
		_spectator_command("special")
		_advance_spectator(0)
		if spectator_camera.state.mode != "tps" or not target.unit.model.visible:
			_fail("NETWORK_SPECTATOR_TPS_BODY_RESTORE")
			return
		_spectator_command("special")
		_advance_spectator(0)
		if spectator_camera.state.mode != "orbit":
			_fail("NETWORK_SPECTATOR_ORBIT")
			return
		_spectator_command("swap")
		_advance_spectator(0)
		if spectator_camera.state.pid == target.pid:
			_fail("NETWORK_SPECTATOR_CYCLE_TARGET")
			return
		_spectator_command("special")
		_advance_spectator(0)
		if spectator_camera.state.mode != "god" or not spectator_camera.state.pid.is_empty() or Session.local_command != saved_command:
			_fail("NETWORK_SPECTATOR_FREE_VIEW_SETTLEMENT")
			return
		exercised = true
		_observer_verified.rpc_id(1)
	if confirmed:
		print("NETWORK_PASS peer=", Session.player_id(), " units=", simulation.units.size())
		print("NETWORK_SPECTATOR_PASS observer=", observer, " camera=true privateHud=true bodyRestore=true noHero=true")
		Session.stop()
		get_tree().quit()

@rpc("any_peer", "call_remote", "reliable")
func _observer_verified() -> void:
	if not Session.dedicated or not authority_frozen:
		_fail("NETWORK_SPECTATOR_UNCONFIRMED_AUTHORITY")
		return
	var player := Session.seats.player_for(multiplayer.get_remote_sender_id())
	if player == 0 or not String(Session.seats.members[player].side).is_empty() or simulation.pilots.has(player):
		_fail("NETWORK_SPECTATOR_OBSERVER_IDENTITY")
		return
	if late_join and (Session.seats.members[player].mode != "spectator" or authority_checkpoint != [simulation.pilots.size(), simulation.clock, simulation.rng.state, simulation.projectile_rng.state]):
		_fail("NETWORK_SPECTATOR_LATE_JOIN_RESET_MATCH")
		return
	_finished.rpc()

@rpc("authority", "call_remote", "reliable")
func _finished() -> void:
	confirmed = true

func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
