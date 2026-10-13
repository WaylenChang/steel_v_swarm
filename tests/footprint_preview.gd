extends "res://scripts/main.gd"

func _ready() -> void:
	super._ready()
	Session.chosen_character = "t09"
	Session.chosen_side = "STEEL"
	if Session.host({"map_index": 0, "team_size": 1, "env": {"time": "day", "weather": "clear"}}) != OK:
		get_tree().quit(1)
		return
	Session.start_battle()
	for frame in range(600):
		await get_tree().physics_frame
		if simulation != null and simulation.pilots.has(1):
			break
	if simulation == null or not simulation.pilots.has(1):
		push_error("FOOTPRINT_PREVIEW_SETUP_TIMEOUT")
		get_tree().quit(1)
		return
	simulation.set_physics_process(false)
	var actor: BattleUnit = simulation.pilots[1]
	for unit: BattleUnit in simulation.units.values():
		if unit != actor:
			unit.hp = 0
	actor.position = Vector3(0, simulation.world.ground_height(0, 0) + 100, 0)
	var front := simulation.spawn({"kind": "soldier", "side": "SWARM", "position": actor.position + Vector3(0, 0, -30)})
	simulation.spawn({"kind": "soldier", "side": "SWARM", "position": actor.position + Vector3(3, 0, -33)})
	var offset := front.aim_point() - actor.eye()
	yaw = atan2(-offset.x, -offset.z)
	pitch = atan2(offset.y, Vector2(offset.x, offset.z).length())
	actor.yaw = yaw
	actor.pitch = pitch
	actor.rotation.y = yaw
	actor.camera.rotation.x = pitch
	selected_slot = "heavy"
	Input.action_press("aim")
	await get_tree().create_timer(0.5).timeout
	var footprint: Dictionary = simulation.snapshot(1).footprint
	if footprint.is_empty() or not footprint.warn or footprint.hits.size() != 2 or simulation.footprint_glows.active.size() != 2:
		push_error("FOOTPRINT_PREVIEW_GLOWS_MISSING")
		get_tree().quit(1)
		return
	if OS.get_cmdline_user_args().has("--capture-preview"):
		await RenderingServer.frame_post_draw
		if get_viewport().get_texture().get_image().save_png("res://tests/footprint-preview.png") != OK:
			get_tree().quit(1)
			return
	print("FOOTPRINT_PREVIEW_PASS victims=2 warning=true glows=2")
	Input.action_release("aim")
	get_tree().quit()
