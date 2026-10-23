extends "res://scripts/main.gd"

var server_fixture := false
var elapsed := 0.0
var expected: Dictionary = {}
var frozen := false
var sent_probe := false
var authority_battle: BattleSimulation

func _ready() -> void:
	Controls.persist = false
	server_fixture = OS.get_cmdline_user_args().has("--quick-restart")
	if server_fixture:
		var fixtures: Dictionary = Content.read_json("res://data/fixtures.json")
		var program: Dictionary = fixtures.quickRestartPrograms[0]
		var game: Dictionary = program.frames.filter(func(frame): return frame.phase == "game")[0]
		expected = MatchRecipe.capture(program.settings, game.players, 1)
		Session.deployment.values = {"lastSession": expected.duplicate(true)}
		Session.deployment.player_name = "Fixture_User"
	super._ready()
	network_test = false
	if server_fixture:
		ui.hide()

func _physics_process(delta: float) -> void:
	elapsed += delta
	if elapsed > 30:
		_fail("NETWORK_QUICK_RESTART_TIMEOUT")
		return
	if simulation == null or not Session.launch_announced:
		return
	if server_fixture:
		if not frozen:
			if Session.phase != "game" or simulation.pilots.size() != expected.bots.size() + 1 or Session.config.is_public or not Session.config.quick_restart:
				_fail("NETWORK_QUICK_RESTART_AUTHORITY")
				return
			var pilot: BattleUnit = simulation.pilots.get(1)
			if pilot == null or pilot.side != expected.player.side or pilot.character != expected.player.ch or Session.config.env.weather != expected.battleConfig.env.weather or int(Session.config.env.lunarDay) != int(expected.battleConfig.env.lunarDay):
				_fail("NETWORK_QUICK_RESTART_RECIPE")
				return
			var index := 0
			for player: int in Session.seats.bots:
				var actor: BattleUnit = simulation.pilots.get(player)
				if actor == null or actor.side != expected.bots[index].side or actor.character != expected.bots[index].ch:
					_fail("NETWORK_QUICK_RESTART_BOT_ORDER")
					return
				index += 1
			authority_battle = simulation
			simulation.set_physics_process(false)
			frozen = true
			print("QUICK_RESTART_READY")
		return
	super._physics_process(delta)
	if not sent_probe and not simulation.pilots.is_empty() and Session.local_member().get("mode") == "spectator":
		sent_probe = true
		_verify.rpc_id(1, simulation.pilots.size(), Session.config.env)

@rpc("any_peer", "call_remote", "reliable")
func _verify(count: int, environment: Dictionary) -> void:
	var peer := multiplayer.get_remote_sender_id()
	var player := Session.seats.player_for(peer)
	if not server_fixture or not frozen or simulation != authority_battle or player <= 1 or Session.seats.members[player].mode != "spectator" or count != simulation.pilots.size() or environment != Session.config.env:
		_fail("NETWORK_QUICK_RESTART_OBSERVER")
		return
	print("NETWORK_QUICK_RESTART_SERVER_PASS")
	_confirmed.rpc_id(peer)

@rpc("authority", "call_remote", "reliable")
func _confirmed() -> void:
	print("NETWORK_PASS peer=", Session.player_id(), " units=", simulation.units.size())
	print("NETWORK_QUICK_RESTART_PASS privateRoom=true exactRoster=true preservedEnvironment=true lateObserver=true")
	Session.stop()
	get_tree().quit()

func _fail(reason: String) -> void:
	push_error(reason)
	get_tree().quit(1)
