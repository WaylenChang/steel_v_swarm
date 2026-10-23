extends "res://scripts/main.gd"

var elapsed := 0.0
var prepared := false
var permitted := false
var exercised := false
var checkpoint: Dictionary = {}
var capture_map := false

func _ready() -> void:
	Controls.persist = false
	capture_map = OS.get_cmdline_user_args().has("--capture-minimap")
	super._ready()
	network_test = false
	if not Session.active:
		Session.chosen_side = "STEEL"
		Session.chosen_character = "t01"
		if Session.host({"map_index": 0, "team_size": 1, "env": {"season": "summer", "time": "day", "weather": "clear", "lunarDay": 15}}, 8620, "offline") != OK:
			_fail("MINIMAP_OFFLINE_ROOM")
			return
		Session.set_ready(true)
		Session.start_battle()

func _physics_process(delta: float) -> void:
	elapsed += delta
	if elapsed > 18:
		_fail("NETWORK_MINIMAP_TIMEOUT")
		return
	if simulation == null or not Session.launch_announced:
		return
	if Session.multiplayer.is_server() and not prepared:
		prepared = true
		simulation.set_physics_process(false)
		checkpoint = _authority_state()
		if Session.dedicated:
			_permit.rpc_id(Session.seats.transport_for(Session.seats.host_id))
		else:
			permitted = true
	if Session.dedicated or not permitted or exercised or not minimap.draw_enabled or minimap.own_id == 0 or minimap.state.get("units", []).is_empty():
		return
	exercised = true
	if minimap.base_texture == null or minimap.base_texture != simulation.world.native_data.minimap_base:
		_fail("NETWORK_MINIMAP_ORIGINAL_TERRAIN_TEXTURE")
		return
	if minimap.lane_view.lines.is_empty() or not minimap.lane_view.visible or minimap.lane_view.get_parent() != minimap.base_canvas or minimap.base_canvas.get_index() >= minimap.canvas.get_index():
		_fail("NETWORK_MINIMAP_NATIVE_LANE_LAYER")
		return
	var fog: MinimapFog = minimap.fog_view
	var pulse := float(Time.get_ticks_msec()) / 1000.0 < minimap.vision.pulse_until
	if not fog.configured or fog.get_parent() != minimap.base_canvas or fog.get_index() >= minimap.lane_view.get_index() or fog.explored.get_parent() != fog.current:
		_fail("NETWORK_MINIMAP_NATIVE_FOG_LAYERS")
		return
	if fog.overlay.visible != (not minimap.side.is_empty() and not pulse):
		_fail("NETWORK_MINIMAP_FOG_PULSE_OR_OBSERVER_BYPASS")
		return
	var original_size: Vector2 = minimap.size
	var key := InputEventAction.new()
	key.action = "map"
	key.pressed = true
	_unhandled_input(key)
	if not minimap.near or not touch_controls.map_near or minimap.size != original_size:
		_fail("NETWORK_MINIMAP_KEYBOARD_MODE")
		return
	touch_controls.command.emit("map", true)
	if minimap.near or touch_controls.map_near or minimap.size != original_size:
		_fail("NETWORK_MINIMAP_TOUCH_MODE")
		return
	_unhandled_input(key)
	var commands: Array = minimap.marker_commands()
	if commands.is_empty() or commands[-1].shape != "polygon" or not commands.any(func(command): return command.shape == "rect"):
		_fail("NETWORK_MINIMAP_PUBLIC_MARKERS")
		return
	var arrow: Dictionary = commands[-1]
	if not is_equal_approx(float(arrow.rotation), -minimap.heading):
		_fail("NETWORK_MINIMAP_ARROW_YAW")
		return
	if capture_map:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/minimap.png")
	if Session.multiplayer.is_server():
		_accept()
	else:
		_report.rpc_id(1)

func _authority_state() -> Dictionary:
	var actors := {}
	for unit: BattleUnit in simulation.units.values():
		actors[unit.entity_id] = [unit.hp, unit.shield, unit.ammo.duplicate(), unit.money]
	return {"rng": simulation.rng.state, "actors": actors}

@rpc("authority", "call_remote", "reliable")
func _permit() -> void:
	permitted = true

@rpc("any_peer", "call_remote", "reliable")
func _report() -> void:
	if not Session.dedicated or Session.seats.player_for(multiplayer.get_remote_sender_id()) != Session.seats.host_id:
		_fail("NETWORK_MINIMAP_ROUTE")
		return
	_accept()

func _accept() -> void:
	if _authority_state() != checkpoint:
		_fail("NETWORK_MINIMAP_CHANGED_COMBAT_STATE")
		return
	if Session.dedicated:
		print("NETWORK_MINIMAP_SERVER_PASS presentationOnly=true combatRngUntouched=true")
		_confirmed.rpc_id(Session.seats.transport_for(Session.seats.host_id))
	else:
		_confirmed()

@rpc("authority", "call_remote", "reliable")
func _confirmed() -> void:
	print("NETWORK_PASS peer=", Session.player_id())
	print("NETWORK_MINIMAP_PASS sharedKeyboardTouch=true fixedPanel=true publicMarkers=true arrowYaw=true")
	Session.stop()
	get_tree().quit()

func _fail(reason: String) -> void:
	push_error(reason)
	get_tree().quit(1)
