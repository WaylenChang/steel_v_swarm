extends "res://scripts/main.gd"

var elapsed := 0.0
var target_id := 0
var stage := 0
var previous_bar: WeakRef
var capture_bars := false

func _ready() -> void:
	Controls.persist = false
	capture_bars = OS.get_cmdline_user_args().has("--capture-vital-bars")
	super._ready()
	network_test = false
	if not Session.active:
		Session.chosen_side = "STEEL"
		Session.chosen_character = "t01"
		if Session.host({"map_index": 0, "team_size": 1, "env": {"season": "summer", "time": "day", "weather": "clear", "lunarDay": 15}}, 8620, "offline") != OK:
			_fail("VITAL_BAR_OFFLINE_ROOM")
			return
		Session.set_ready(true)
		Session.start_battle()

func _physics_process(delta: float) -> void:
	elapsed += delta
	if elapsed > 18:
		_fail("NETWORK_VITAL_BAR_TIMEOUT stage=" + str(stage))
		return
	if simulation == null or not Session.launch_announced:
		return
	if Session.multiplayer.is_server() and target_id == 0:
		simulation.set_physics_process(false)
		var owner: BattleUnit = simulation.pilots.get(Session.seats.host_id)
		if owner == null:
			return
		var forward := Vector2(-sin(owner.facing_yaw()), -cos(owner.facing_yaw())) * 18
		var point := owner.position + Vector3(forward.x, 0, forward.y)
		point.y = simulation.world.ground_height(point.x, point.z)
		var created := simulation.spawn({"kind": "soldier", "side": owner.side, "position": point})
		target_id = created.entity_id
		simulation.damage(null, created, {"pen": 1000}, created.max_hp * .3, false, {"weather_weapon": false}, false)
		if created.hp >= created.max_hp or not created.alive():
			_fail("NETWORK_VITAL_BAR_AUTHORITY_DAMAGE")
			return
		if Session.dedicated:
			_target.rpc_id(Session.seats.transport_for(Session.seats.host_id), target_id)
	if Session.dedicated or target_id == 0:
		return
	var target: BattleUnit = simulation.units.get(target_id)
	if stage == 2 and target == null:
		var retained: Variant = previous_bar.get_ref()
		if is_instance_valid(retained) and retained.visible:
			_fail("NETWORK_VITAL_BAR_VISIBLE_ON_RETIRED_BODY")
			return
		stage = 3
		_advance(3)
		return
	if target == null or not is_instance_valid(target.vital_bar) or target.vital_bar.group == null:
		return
	var bar := target.vital_bar
	if stage == 0 and target.hp < target.max_hp:
		stage = -1
		var fill: MeshInstance3D = bar.nodes[int(bar.template.fills[0])]
		if absf(fill.scale.x - target.hp / target.max_hp) > .000001 or not bar.group.visible:
			_fail("NETWORK_VITAL_BAR_PUBLIC_RATIO")
			return
		previous_bar = weakref(bar.group)
		if capture_bars:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://tests/vital-bars.png")
		stage = 1
		_advance(1)
	elif stage == 1 and target.hp == target.max_hp:
		if previous_bar.get_ref() != bar.group or not bar.group.visible:
			_fail("NETWORK_VITAL_BAR_HEAL_RECREATED_OR_REMOVED")
			return
		stage = 2
		_advance(2)

@rpc("authority", "call_remote", "reliable")
func _target(id: int) -> void:
	target_id = id

func _advance(value: int) -> void:
	if Session.multiplayer.is_server():
		_set_stage(value)
	else:
		_report.rpc_id(1, value)

@rpc("any_peer", "call_remote", "reliable")
func _report(value: int) -> void:
	if not Session.dedicated or Session.seats.player_for(multiplayer.get_remote_sender_id()) != Session.seats.host_id:
		_fail("NETWORK_VITAL_BAR_ROUTE")
		return
	_set_stage(value)

func _set_stage(value: int) -> void:
	if value == 1:
		var target: BattleUnit = simulation.units[target_id]
		simulation._heal_body(target, target.max_hp)
	elif value == 2:
		var target: BattleUnit = simulation.units[target_id]
		simulation.damage(null, target, {"pen": 1000}, target.max_hp * 10, false, {"weather_weapon": false}, false)
		simulation._prune_dead_creeps()
	elif value == 3:
		if Session.dedicated:
			print("NETWORK_VITAL_BAR_SERVER_PASS authorityDamage=true authorityHeal=true authorityDeath=true")
			_confirmed.rpc_id(Session.seats.transport_for(Session.seats.host_id))
		else:
			_confirmed()

@rpc("authority", "call_remote", "reliable")
func _confirmed() -> void:
	print("NETWORK_PASS peer=", Session.player_id())
	print("NETWORK_VITAL_BAR_PASS publicRatio=true healedBarRetained=true retiredBarHidden=true")
	Session.stop()
	get_tree().quit()

func _fail(reason: String) -> void:
	push_error(reason)
	get_tree().quit(1)
