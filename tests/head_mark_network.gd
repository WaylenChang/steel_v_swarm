extends "res://scripts/main.gd"

var elapsed := 0.0
var fixture_id := 0
var stage := 0
var original_mark := 0
var capture_mark := false

func _ready() -> void:
	Controls.persist = false
	capture_mark = OS.get_cmdline_user_args().has("--capture-head-marks")
	super._ready()
	network_test = false
	if not Session.active:
		Session.chosen_side = "STEEL"
		Session.chosen_character = "t01"
		if Session.host({"map_index": 0, "team_size": 1, "env": {"season": "summer", "time": "day", "weather": "clear", "lunarDay": 15}}, 8620, "offline") != OK:
			_fail("HEAD_MARK_OFFLINE_ROOM")
			return
		Session.set_ready(true)
		Session.start_battle()

func _physics_process(delta: float) -> void:
	elapsed += delta
	if elapsed > 18:
		_fail("NETWORK_HEAD_MARK_TIMEOUT stage=" + str(stage))
		return
	if simulation == null or not Session.launch_announced:
		return
	if Session.multiplayer.is_server() and fixture_id == 0:
		simulation.set_physics_process(false)
		var owner: BattleUnit = simulation.pilots.get(Session.seats.host_id)
		if owner == null:
			return
		var forward := Vector2(-sin(owner.facing_yaw()), -cos(owner.facing_yaw())) * 18
		var civilian := simulation._spawn_civilian("STEEL", true, 0, {"x": owner.position.x + forward.x, "z": owner.position.z + forward.y})
		fixture_id = civilian.entity_id
		civilian.special.follow_peer = owner.peer_id
	if Session.dedicated:
		return
	var civilian: BattleUnit
	for actor: BattleUnit in simulation.units.values():
		if actor.special.get("role") == "civilian" and actor.special.get("civil_side") == "STEEL" and (actor.special.get("following", false) or actor.special.get("follow_peer", 0) != 0 or actor.entity_id == fixture_id):
			civilian = actor
			break
	if civilian == null:
		if fixture_id > 0:
			civilian = simulation.units.get(fixture_id)
	if civilian == null or not is_instance_valid(civilian.head_marks) or not civilian.head_marks.marks.has("civilian"):
		return
	if fixture_id == 0:
		fixture_id = civilian.entity_id
	var view: Dictionary = civilian.head_marks.marks.civilian
	if not Session.multiplayer.is_server() and civilian.special.has("spy"):
		_fail("NETWORK_HEAD_MARK_SPY_DISCLOSURE")
		return
	if stage == 0 and view.state.opacity >= float(Content.balance.headMarks.rules.civilian.followOpacity):
		stage = -1
		original_mark = view.node.get_instance_id()
		if capture_mark:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://tests/head-marks.png")
		stage = 1
		_advance(1)
	elif stage == 1 and not civilian.special.get("following", civilian.special.get("follow_peer", 0) != 0):
		if absf(view.state.opacity - float(Content.balance.headMarks.rules.civilian.opacity)) > 0.000001:
			return
		if view.node.get_instance_id() != original_mark or civilian.head_marks.marks.size() != 1:
			_fail("NETWORK_HEAD_MARK_RECREATED_OR_SPY_MARK")
			return
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
		_fail("NETWORK_HEAD_MARK_ROUTE")
		return
	_set_stage(value)

func _set_stage(value: int) -> void:
	if value == 1:
		simulation.units[fixture_id].special.follow_peer = 0
	elif value == 2:
		if Session.dedicated:
			print("NETWORK_HEAD_MARK_SERVER_PASS sourceCivilian=true followReset=true")
			_confirmed.rpc_id(Session.seats.transport_for(Session.seats.host_id))
		else:
			_confirmed()

@rpc("authority", "call_remote", "reliable")
func _confirmed() -> void:
	print("NETWORK_PASS peer=", Session.player_id())
	print("NETWORK_HEAD_MARK_PASS publicFaction=true spyHidden=true originalTexture=true followBrightness=true stableNode=true")
	Session.stop()
	get_tree().quit()

func _fail(reason: String) -> void:
	push_error(reason)
	get_tree().quit(1)
