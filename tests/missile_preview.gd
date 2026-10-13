extends "res://scripts/main.gd"

func _physics_process(_delta: float) -> void:
	pass

func _ready() -> void:
	super._ready()
	Session.chosen_character = "t08"
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
		get_tree().quit(1)
		return
	simulation.set_physics_process(false)
	var viewer: BattleUnit = simulation.pilots[1]
	var base: BattleUnit
	for unit: BattleUnit in simulation.units.values():
		if unit.kind == "base" and unit.side != viewer.side:
			base = unit
	var point := base.position + Vector3(0, 0, 70)
	point.y = simulation.world.ground_height(point.x, point.z) + 40
	viewer.position = point
	await get_tree().physics_frame
	simulation._tick_base_guns(base, Content.constants.UNITS.base.guns, 0.05)
	simulation._tick_missiles(0.2)
	if simulation.missiles.size() != 2:
		push_error("MISSILE_PREVIEW_LAUNCH_MISSING")
		get_tree().quit(1)
		return
	var body: MissileBody = simulation.missile_bodies[int(simulation.missiles[0].id)]
	viewer.camera.global_position = body.global_position + Vector3(4, 2, 0)
	viewer.camera.fov = 35
	viewer.camera.look_at(body.global_position, Vector3.UP)
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	if get_viewport().get_texture().get_image().save_png("res://tests/missile-preview.png") != OK:
		get_tree().quit(1)
		return
	print("MISSILE_PREVIEW_PASS missiles=", simulation.missiles.size(), " parts=", MissileBody.meshes.size())
	get_tree().quit()
