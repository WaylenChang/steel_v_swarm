extends "res://tests/run.gd"

const Raster = preload("res://tests/raster_compare.gd")

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/pip_composition.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(DisplayServer.get_name() != "headless", "Authored PiP model isolation requires a real display driver")
	_check(capture.get("formatVersion") == 1 and capture.get("cases") is Array and capture.cases.size() == 8,
		"Retain the original PiP renderer capture")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Current PiP renderer capture: " + path)
	for path: String in capture.source.sourceInputs:
		_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original PiP renderer source: " + path)
	if failures == 0:
		await _isolation()
	print("PIP_MODEL_ISOLATION assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _isolation() -> void:
	var stage := SubViewport.new()
	stage.size = Vector2i(320, 180)
	stage.world_3d = World3D.new()
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.12, 0.17, 0.22)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 1.0
	stage.add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 9
	camera.position = Vector3(0, 2, 20)
	stage.add_child(camera)
	camera.current = true
	var bodies: Array[BodyRig] = []
	for index in range(2):
		var rig := BodyRig.new()
		stage.add_child(rig)
		var key := "steel_decoy" if index == 0 else "super_s01"
		_check(rig.configure(key, func(_index): return 0.0), "Load the authored PiP source body: " + key)
		rig.position.x = -3 if index == 0 else 3
		bodies.append(rig)
	var cockpit := CockpitRig.new()
	stage.add_child(cockpit)
	cockpit.configure("t01")
	cockpit.position = Vector3(0, 1, 5)
	_check(is_instance_valid(cockpit.source_root), "Load the authored cockpit")
	var roots: Array[Node3D] = [bodies[0], bodies[1], cockpit]
	var original_layers := {}
	var outlines: Array[GeometryInstance3D] = []
	for root: Node3D in roots:
		var count := 0
		for node: VisualInstance3D in root.find_children("*", "VisualInstance3D", true, false):
			original_layers[node.get_instance_id()] = {"node": node, "layers": node.layers}
			if node is GeometryInstance3D and node.material_override is ShaderMaterial \
					and node.material_override.get_meta("source_outline", false):
				outlines.append(node)
				count += 1
		_check(count > 0, "Authored body or cockpit has active source outline bindings")
	var pip := PipView.new()
	stage.add_child(pip)
	pip.hide()
	var full := await _image(stage)
	for root: Node3D in roots:
		root.hide()
		var without := await _image(stage)
		root.show()
		_check(Raster.compare(full, without, 0).pixels > 0, "Every authored body and cockpit contributes visible pixels")
	var expected: Array[Image] = []
	for index in range(2):
		bodies[index].hide()
		cockpit.hide()
		expected.append(await _image(stage))
		bodies[index].show()
		cockpit.show()
	_check(Raster.compare(full, expected[0], 0).pixels > 0 and Raster.compare(full, expected[1], 0).pixels > 0,
		"The original hide operations remove visible authored geometry")
	_check(Raster.compare(expected[0], expected[1], 0).pixels > 0,
		"Each original source selection leaves a distinct visible body")
	for index in range(2):
		pip._add_view()
		var slot: Dictionary = pip.views[index]
		slot.viewport.size = stage.size
		slot.viewport.world_3d = stage.world_3d
		slot.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		slot.camera.projection = camera.projection
		slot.camera.size = camera.size
		slot.camera.position = camera.position
		slot.camera.cull_mask = PipView.ALL_LAYERS & ~PipView.COCKPIT_MASK & ~PipView.SOURCE_MASKS[index]
		pip.pending_tags.append({"root": bodies[index], "mask": PipView.SOURCE_MASKS[index]})
	pip.pending_tags.append({"root": cockpit, "mask": PipView.COCKPIT_MASK})
	pip.show()
	pip._begin_frame()
	for outline: GeometryInstance3D in outlines:
		var material := outline.material_override as ShaderMaterial
		_check(int(material.get_shader_parameter("source_layers")) == outline.layers,
			"Authored outlines track the temporary source or cockpit layer")
	pip._end_frame()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	for index in range(2):
		var actual: Image = pip.views[index].viewport.get_texture().get_image()
		var result := Raster.compare(actual, expected[index], 0)
		_check(result.pixels == 0, "Native PiP hides only its authored source and cockpit: slot=" + str(index))
	var main := stage.get_texture().get_image()
	_check(Raster.compare(main, full, 0).pixels == 0, "Main camera retains both source bodies and the cockpit")
	for record: Dictionary in original_layers.values():
		_check(record.node.layers == record.layers, "Completed PiP frame restores authored model layers")
	for outline: GeometryInstance3D in outlines:
		var material := outline.material_override as ShaderMaterial
		_check(int(material.get_shader_parameter("source_layers")) == outline.layers,
			"Completed PiP frame restores authored outline layers")
	await _production_selection(stage, pip, bodies, cockpit)
	stage.free()

func _production_selection(stage: SubViewport, pip: PipView, bodies: Array[BodyRig], cockpit: CockpitRig) -> void:
	var previous_power: Variant = Controls.power_pref
	Controls.power_pref = "0"
	pip.hide()
	for slot: Dictionary in pip.views:
		slot.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	var battle := BattleSimulation.new()
	stage.add_child(battle)
	battle.set_physics_process(false)
	battle.world = BattleWorld.new()
	battle.world.bounds = {"minX": -1000, "maxX": 1000, "minZ": -1000, "maxZ": 1000}
	battle.add_child(battle.world)
	var pilot := BattleUnit.new()
	pilot.peer_id = 17
	pilot.hp = 1
	battle.add_child(pilot)
	cockpit.reparent(pilot)
	pilot.cockpit = cockpit
	var actors: Array[BattleUnit] = []
	for index in range(2):
		var actor := BattleUnit.new()
		actor.entity_id = 7 + index
		actor.peer_id = pilot.peer_id
		actor.hp = 1
		actor.kind = "decoy" if index == 0 else "drone"
		actor.character = "" if index == 0 else "s01"
		actor.special = {"owner_peer": pilot.peer_id}
		battle.add_child(actor)
		bodies[index].reparent(actor)
		actor.model = bodies[index]
		battle.units[actor.entity_id] = actor
		actors.append(actor)
	var reference := SubViewport.new()
	reference.world_3d = stage.world_3d
	reference.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(reference)
	var camera := Camera3D.new()
	reference.add_child(camera)
	camera.current = true
	for index in range(2):
		pilot.kind = "tank" if index == 0 else "drone"
		bodies[index].global_position = Vector3(0, 0, 5)
		bodies[1 - index].global_position = Vector3(0, 0, -8)
		cockpit.global_position = Vector3(0, 1, 4)
		pip.show()
		pip.update_view(battle, pilot, "STEEL")
		_check(pip.pending_tags.any(func(tag): return tag.root == bodies[index]),
			"Production PiP selects the authored decoy or drone")
		var slot: Dictionary = pip.views[0]
		reference.size = slot.viewport.size
		camera.global_transform = slot.camera.global_transform
		camera.fov = slot.camera.fov
		camera.near = slot.camera.near
		camera.far = slot.camera.far
		pip.hide()
		var full := await _image(reference)
		bodies[index].hide()
		var without_source := await _image(reference)
		cockpit.hide()
		var expected := await _image(reference)
		_check(Raster.compare(full, without_source, 0).pixels > 0,
			"The selected authored body would be visible without PiP exclusion")
		_check(Raster.compare(without_source, expected, 0).pixels > 0,
			"The authored cockpit would be visible without PiP exclusion")
		bodies[1 - index].hide()
		var background := await _image(reference)
		_check(Raster.compare(expected, background, 0).pixels > 0,
			"Production PiP camera sees the other authored body")
		bodies[1 - index].show()
		bodies[index].show()
		cockpit.show()
		pip.show()
		pip.update_view(battle, pilot, "STEEL")
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var actual: Image = pip.views[0].viewport.get_texture().get_image()
		_check(Raster.compare(actual, expected, 0).pixels == 0,
			"Production PiP pixels match original source and cockpit hiding")
		_check(pip.layers.is_empty(), "Production render restores the authored source layers")
		pip.hide()
	reference.free()
	Controls.power_pref = previous_power

func _image(stage: SubViewport) -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return stage.get_texture().get_image()
