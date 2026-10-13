extends "res://scripts/main.gd"

func _ready() -> void:
	super._ready()
	var character := _argument("--character", "m01")
	Session.chosen_character = character
	Session.chosen_side = Content.heroes[character].side
	if Session.chosen_side == "MERC":
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
		push_error("COCKPIT_PREVIEW_SETUP_TIMEOUT")
		get_tree().quit(1)
		return
	simulation.set_physics_process(false)
	var pilot: BattleUnit = simulation.pilots[1]
	pilot.position = Vector3(0, simulation.world.ground_height(0, 0) + 10, 0)
	yaw = 0
	pitch = -0.12
	pilot.rotation.y = yaw
	pilot.camera.rotation.x = pitch
	await get_tree().create_timer(0.4).timeout
	if OS.get_cmdline_user_args().has("--fire-feedback"):
		selected_slot = _argument("--feedback-slot", "light")
		pilot.input_state = {"aim": selected_slot == "heavy", "slot": selected_slot}
		simulation.fire(pilot, selected_slot)
		var events := simulation.events.filter(func(event): return event.type == "weapon_fire" and int(event.actor) == pilot.entity_id)
		if events.is_empty():
			push_error("COCKPIT_PREVIEW_FIRE_REJECTED")
			get_tree().quit(1)
			return
		pilot.cockpit.fire_feedback(events[-1])
		pilot.cockpit.update_view(pilot, selected_slot, false, 0, simulation.clock)
	if pilot.cockpit == null or not pilot.cockpit.visible or pilot.cockpit.gun.get_children().all(func(child): return not child.visible):
		push_error("COCKPIT_PREVIEW_GEOMETRY_MISSING")
		get_tree().quit(1)
		return
	if OS.get_cmdline_user_args().has("--capture-preview"):
		await RenderingServer.frame_post_draw
		var suffix := "-fire" if OS.get_cmdline_user_args().has("--fire-feedback") else ""
		if get_viewport().get_texture().get_image().save_png("res://tests/cockpit-%s%s.png" % [character, suffix]) != OK:
			get_tree().quit(1)
			return
	print("COCKPIT_PREVIEW_PASS character=", character)
	Session.stop()
	get_tree().quit()
