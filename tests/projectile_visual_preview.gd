extends Node3D

func _ready() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("182633")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = 0.8
	environment.environment = settings
	add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8
	camera.position = Vector3(6, 7, 10)
	add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var profiles := ["t06-light-steel", "t03-heavy-steel", "t09-heavy-steel", "s05-heavy-swarm"]
	for index in range(profiles.size()):
		var model := ProjectileVisual.new()
		add_child(model)
		model.configure(profiles[index])
		model.place(Vector3((index % 2 - 0.5) * 3, 0, (index / 2 - 0.5) * 3), Vector3.BACK, 0.4, 260)
	await RenderingServer.frame_post_draw
	if get_viewport().get_texture().get_image().save_png("res://tests/projectile-visual-preview.png") != OK:
		get_tree().quit(1)
		return
	print("PROJECTILE_VISUAL_PREVIEW_PASS profiles=", profiles.size())
	get_tree().quit()
