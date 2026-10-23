extends "res://scripts/main.gd"

var elapsed := 0.0
var prepared := false
var permitted := false
var exercised := false
var checkpoint: Dictionary = {}

func _ready() -> void:
	Controls.persist = false
	if Content.initialize_local_balance(false) != OK:
		_fail("NETWORK_BALANCE_METADATA")
		return
	Content.balance_preferences.set_value("stat_dmg", 3 if OS.get_cmdline_user_args().has("--server") else 2)
	super._ready()
	network_test = false
	if not Session.active:
		Session.chosen_side = "STEEL"
		Session.chosen_character = "t01"
		if Session.host({"map_index": 0, "team_size": 1, "env": {"season": "summer", "time": "day", "weather": "clear", "lunarDay": 15}}, 8620, "offline") != OK:
			_fail("NETWORK_BALANCE_OFFLINE_ROOM")
			return
		Session.set_ready(true)
		Session.start_battle()

func _physics_process(delta: float) -> void:
	elapsed += delta
	if elapsed > 18:
		_fail("NETWORK_BALANCE_TIMEOUT")
		return
	if simulation == null or not Session.launch_announced:
		return
	if Session.multiplayer.is_server() and not prepared:
		prepared = true
		simulation.set_physics_process(false)
		var offline := Session.multiplayer.multiplayer_peer is OfflineMultiplayerPeer
		if simulation.balance_profile != (Content.local_balance if offline else null):
			_fail("NETWORK_BALANCE_AUTHORITY_CONTEXT")
			return
		for pilot: BattleUnit in simulation.pilots.values():
			var level := pilot.combat_level("light")
			var factory := Content.weapon(pilot.character, "light", level)
			var actual := simulation.weapon_definition(pilot.character, "light", level)
			if not is_equal_approx(float(actual.dmg), float(factory.dmg) * (2 if offline else 1)):
				_fail("NETWORK_BALANCE_AUTHORITY_DAMAGE")
				return
		checkpoint = _authority_state()
		if Session.dedicated:
			_permit.rpc_id(Session.seats.transport_for(Session.seats.host_id))
		else:
			permitted = true
	if Session.dedicated or not permitted or exercised:
		return
	exercised = true
	if simulation.balance_profile != Content.local_balance:
		_fail("NETWORK_BALANCE_CLIENT_CONTEXT")
		return
	var factory := Content.weapon("t01", "light")
	if not is_equal_approx(float(Content.local_weapon("t01", "light").dmg), float(factory.dmg) * 2):
		_fail("NETWORK_BALANCE_LOCAL_PREVIEW")
		return
	var pilot: BattleUnit = simulation.pilots.get(Session.player_id())
	if pilot == null:
		_fail("NETWORK_BALANCE_LOCAL_PILOT")
		return
	var cached_damage := float(simulation.client_weapon_definition(pilot, "light").dmg)
	Content.balance_preferences.set_value("stat_dmg", 4)
	if not is_equal_approx(float(Content.local_weapon("t01", "light").dmg), float(factory.dmg) * 4):
		_fail("NETWORK_BALANCE_LIVE_LOCAL_CHANGE")
		return
	if float(simulation.client_weapon_definition(pilot, "light").dmg) != cached_damage:
		_fail("NETWORK_BALANCE_UNEXPECTED_OWN_CACHE_REFRESH")
		return
	if Session.multiplayer.is_server() and not is_equal_approx(float(simulation.weapon_definition(pilot.character, "light").dmg), float(factory.dmg) * 4):
		_fail("NETWORK_BALANCE_OFFLINE_LIVE_AUTHORITY")
		return
	if Session.multiplayer.is_server():
		_accept()
	else:
		_report.rpc_id(1)

func _authority_state() -> Dictionary:
	var actors := {}
	for unit: BattleUnit in simulation.units.values():
		actors[unit.entity_id] = [unit.hp, unit.shield, unit.ammo.duplicate(), unit.money, unit.respawn_at]
	return {"rng": simulation.rng.state, "actors": actors}

@rpc("authority", "call_remote", "reliable")
func _permit() -> void:
	permitted = true

@rpc("any_peer", "call_remote", "reliable")
func _report() -> void:
	if not Session.dedicated or Session.seats.player_for(multiplayer.get_remote_sender_id()) != Session.seats.host_id:
		_fail("NETWORK_BALANCE_REPORT_ROUTE")
		return
	_accept()

func _accept() -> void:
	if _authority_state() != checkpoint:
		_fail("NETWORK_BALANCE_RETROACTIVE_SETTLEMENT")
		return
	if Session.dedicated:
		print("NETWORK_BALANCE_SERVER_PASS localPreferencesIsolated=true")
		_confirmed.rpc_id(Session.seats.transport_for(Session.seats.host_id))
	else:
		_confirmed()

@rpc("authority", "call_remote", "reliable")
func _confirmed() -> void:
	print("NETWORK_PASS peer=", Session.player_id())
	print("NETWORK_BALANCE_PASS localPreview=true liveTuning=true authorityContext=true")
	Session.stop()
	get_tree().quit()

func _fail(reason: String) -> void:
	push_error(reason)
	get_tree().quit(1)
