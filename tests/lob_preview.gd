extends "res://scripts/main.gd"

func _ready() -> void:
	super._ready()
	Session.chosen_character = "t03"
	Session.chosen_side = "STEEL"
	var error := Session.host({"map_index": 0, "team_size": 1, "env": {"time": "day", "weather": "clear"}})
	if error != OK:
		get_tree().quit(1)
		return
	Session.start_battle()
	for frame in range(600):
		await get_tree().physics_frame
		if simulation != null and simulation.pilots.has(1):
			break
	if simulation == null or not simulation.pilots.has(1):
		push_error("LOB_PREVIEW_SETUP_TIMEOUT")
		get_tree().quit(1)
		return
	selected_slot = "heavy"
	pitch = -0.15
	Input.action_press("aim")
	Input.action_press("fire")
	await get_tree().create_timer(2).timeout
	var control: Dictionary = simulation.snapshot(1).fire_control
	if control.is_empty() or not simulation.world.arc_preview.visible:
		push_error("LOB_PREVIEW_MISSING")
		get_tree().quit(1)
		return
	if OS.get_cmdline_user_args().has("--capture-preview"):
		await RenderingServer.frame_post_draw
		if get_viewport().get_texture().get_image().save_png("res://tests/lob-preview.png") != OK:
			get_tree().quit(1)
			return
	print("LOB_PREVIEW_PASS points=", control.points.size(), " ok=", control.ok, " aa=", control.aa)
	Input.action_release("aim")
	Input.action_release("fire")
	get_tree().quit()
