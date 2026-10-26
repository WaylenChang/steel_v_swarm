extends "res://scripts/main.gd"

var elapsed := 0.0
var stage := 0
var original_battle := 0
var expected: Dictionary = {}
var with_recipe := true
var render_fatal := false

func _ready() -> void:
	Controls.persist = false
	with_recipe = not OS.get_cmdline_user_args().has("--without-recipe")
	render_fatal = OS.get_cmdline_user_args().has("--capture-fatal")
	var fixtures: Dictionary = Content.read_json("res://data/fixtures.json", ["quickRestartPrograms"])
	var program: Dictionary = fixtures.quickRestartPrograms[0]
	var game: Dictionary = program.frames.filter(func(frame): return frame.phase == "game")[0]
	expected = MatchRecipe.capture(program.settings, game.players, 1)
	Session.deployment.values = {"lastSession": expected.duplicate(true)}
	Session.deployment.player_name = "Fixture_User"
	super._ready()
	network_test = false
	if not Session.active:
		_quick_restart()

func _physics_process(delta: float) -> void:
	elapsed += delta
	if elapsed > 35:
		_fail("FATAL_RESTART_TIMEOUT")
		return
	if simulation == null or not Session.launch_announced:
		return
	if stage == 0:
		stage = 1
		original_battle = simulation.get_instance_id()
		if not with_recipe:
			Session.deployment.values.clear()
		Session.fail_battle("fixture solo failure")
		if not fatal_watchdog.shown or not _solo_session():
			_fail("FATAL_RESTART_NOT_SOLO_OR_NOT_SHOWN")
			return
		if render_fatal:
			if not fatal_dialog.visible or not fatal_restart_button.visible or fatal_dialog.title != Content.label("fatal_title"):
				_fail("FATAL_DIALOG_NATIVE_UI")
				return
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://tests/fatal.png")
			print("FATAL_DIALOG_RENDER_READY")
			Session.stop()
			get_tree().quit()
			return
		await _fatal_restart()
		if not with_recipe:
			if Session.active or simulation != null or not lobby.visible or fatal_watchdog.shown:
				_fail("FATAL_RESTART_WITHOUT_RECIPE")
				return
			print("FATAL_RESTART_PASS noRecipe=true returnedLobby=true cleanAuthority=true")
			get_tree().quit()
			return
		stage = 2
		return
	if stage != 2:
		return
	var pilot: BattleUnit = simulation.pilots.get(1)
	if simulation.get_instance_id() == original_battle or not Session.failure_reason.is_empty() or fatal_watchdog.shown or not simulation.is_physics_processing() or pilot == null or pilot.side != expected.player.side or pilot.character != expected.player.ch or simulation.pilots.size() != expected.bots.size() + 1 or Session.config.env.weather != expected.battleConfig.env.weather:
		_fail("FATAL_RESTART_DIRTY_MATCH_OR_CHANGED_RECIPE")
		return
	print("FATAL_RESTART_PASS newAuthority=true originalRecipe=true clearedFailure=true")
	Session.stop()
	get_tree().quit()

func _show_fatal(reason: String, force: bool = false) -> void:
	if render_fatal:
		super._show_fatal(reason, force)
	else:
		fatal_watchdog.reveal(_fatal_phase(), force)

func _fail(reason: String) -> void:
	push_error(reason)
	get_tree().quit(1)
