extends "res://scripts/main.gd"

var elapsed := 0.0
var authority_ready := false
var carrier := 0
var stage := 0
var captured := false
var render_pip := false

func _ready() -> void:
	Controls.persist = false
	render_pip = OS.get_cmdline_user_args().has("--capture-pip")
	super._ready()
	network_test = false
	if not Session.active:
		Session.chosen_side = "STEEL"
		Session.chosen_character = "t01"
		var error := Session.host({"map_index": 0, "team_size": 1, "env": {"season": "summer", "time": "day", "weather": "clear", "lunarDay": 15}}, 8620, "offline")
		if error != OK:
			_fail("PIP_OFFLINE_ROOM")
			return
		Session.set_ready(true)
		Session.start_battle()

func _physics_process(delta: float) -> void:
	elapsed += delta
	if elapsed > 18:
		_fail("NETWORK_PIP_TIMEOUT stage=" + str(stage))
		return
	if simulation == null or not Session.launch_announced:
		return
	if Session.multiplayer.is_server() and not authority_ready:
		var owner: BattleUnit = simulation.pilots.get(Session.seats.host_id)
		if owner == null or owner.kind == "drone":
			_fail("NETWORK_PIP_OWNER")
			return
		simulation.set_physics_process(false)
		var point := owner.position + Vector3(0, 0, -180)
		point.y = simulation.world.ground_height(point.x, point.z)
		simulation._launch_carriers(owner, Content.ability(owner.character, "atk"), point, simulation._ability_origin(owner, "atk"))
		for id: int in owner.carrier_ids:
			if simulation.units[id].kind == "decoy":
				carrier = id
				break
		if carrier == 0:
			_fail("NETWORK_PIP_CARRIER")
			return
		authority_ready = true
	if Session.dedicated:
		return
	if pip_view.views.is_empty():
		return
	var slot: Dictionary = pip_view.views[0]
	if stage == 0 and slot.border.visible and slot.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS:
		var source: BattleUnit
		for actor: BattleUnit in simulation.units.values():
			if actor.kind == "decoy" and int(actor.special.get("owner_peer", 0)) == Session.player_id():
				source = actor
				break
		if source == null or slot.viewport.world_3d != simulation.get_world_3d() or (slot.camera.cull_mask & PipView.COCKPIT_MASK) != 0 or (slot.camera.cull_mask & PipView.SOURCE_MASKS[0]) != 0:
			_fail("NETWORK_PIP_NATIVE_VIEWPORT")
			return
		if render_pip and not captured:
			captured = true
			stage = -1
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://tests/pip.png")
		stage = 1
		_advance(1)
	elif stage == 1 and not slot.border.visible and slot.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and pip_view.layers.is_empty():
		stage = 2
		_advance(2)

func _advance(value: int) -> void:
	if Session.multiplayer.is_server():
		_set_stage(value)
	else:
		_report.rpc_id(1, value)

@rpc("any_peer", "call_remote", "reliable")
func _report(value: int) -> void:
	if not Session.dedicated or Session.seats.player_for(multiplayer.get_remote_sender_id()) != Session.seats.host_id:
		_fail("NETWORK_PIP_ROUTE")
		return
	_set_stage(value)

func _set_stage(value: int) -> void:
	if value == 1:
		simulation.units[carrier].special.lost = true
		simulation.carrier_states[carrier].lost = true
	elif value == 2:
		simulation._remove_carrier(carrier)
		if Session.dedicated:
			print("NETWORK_PIP_SERVER_PASS lost=true existingSimulation=true")
			_confirmed.rpc_id(Session.seats.transport_for(Session.seats.host_id))
		else:
			_confirmed()

@rpc("authority", "call_remote", "reliable")
func _confirmed() -> void:
	print("NETWORK_PASS peer=", Session.player_id())
	print("NETWORK_PIP_PASS sharedWorld=true ownedCarrier=true nativeCamera=true lostCleanup=true restoredMasks=true")
	Session.stop()
	get_tree().quit()

func _fail(reason: String) -> void:
	push_error(reason)
	get_tree().quit(1)
