extends "res://scripts/main.gd"

func _ready() -> void:
	super._ready()
	Session.chosen_character = "t09"
	Session.chosen_side = "STEEL"
	if Session.host({"map_index": 0, "team_size": 1, "env": {"time": "day", "weather": "clear"}}) != OK:
		get_tree().quit(1)
		return
	Session.set_ready(true)
	Session.start_battle()
	for frame in range(600):
		await get_tree().physics_frame
		if simulation != null and simulation.pilots.has(1):
			break
	if simulation == null or not simulation.pilots.has(1):
		push_error("REACHABILITY_PREVIEW_SETUP_TIMEOUT")
		get_tree().quit(1)
		return
	simulation.set_physics_process(false)
	var actor: BattleUnit = simulation.pilots[1]
	actor.position = Vector3(0, simulation.world.ground_height(0, 0) + 100, 0)
	var target := simulation.spawn({"kind": "morph", "character": "m08", "side": "SWARM",
		"position": actor.position + Vector3(0, 0, -100)})
	var offset := target.aim_point() - actor.eye()
	yaw = atan2(-offset.x, -offset.z)
	pitch = atan2(offset.y, Vector2(offset.x, offset.z).length())
	actor.yaw = yaw
	actor.pitch = pitch
	actor.rotation.y = yaw
	selected_slot = "heavy"
	Input.action_press("aim")
	await get_tree().create_timer(0.5).timeout
	var advice: Dictionary = simulation.snapshot(1).reachability
	if advice.is_empty() or not advice.ok or advice.warn or not ammo_label.text.contains(Content.label("reach_clear")):
		push_error("REACHABILITY_PREVIEW_HUD_MISSING")
		get_tree().quit(1)
		return
	if OS.get_cmdline_user_args().has("--capture-preview"):
		await RenderingServer.frame_post_draw
		if get_viewport().get_texture().get_image().save_png("res://tests/reachability-preview.png") != OK:
			get_tree().quit(1)
			return
	print("REACHABILITY_PREVIEW_PASS target=", advice.target, " hud=true")
	Input.action_release("aim")
	get_tree().quit()
