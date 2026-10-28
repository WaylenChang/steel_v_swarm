extends "res://tests/pip_composition.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/pip_selection.json")
	_check(capture.get("formatVersion") == 1 and capture.get("scenarios") is Array and capture.scenarios.size() == 2,
		"Capture original PiP selection changes at render time")
	if failures == 0:
		var provenance: Dictionary = Content.read_json("res://data/provenance.json")
		for path: String in capture.source.inputs:
			var source := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(source.sha256_text() == capture.source.inputs[path], "Current PiP selection capture input: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.get("inputs", {}).get(path) == capture.source.sourceInputs[path], "Original PiP selection source identity: " + path)
	if failures == 0:
		var original: Dictionary = Content.read_json("res://tests/fixtures/pip.json")
		var composition: Dictionary = Content.read_json("res://tests/fixtures/pip_composition.json")
		_check_pip_source_identity(original, composition)
		_check_scenarios(capture.scenarios)
		if failures == 0:
			await _check_late_render(original, composition)
	print("PIP_SELECTION assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_scenarios(scenarios: Array) -> void:
	var saved_power: Variant = Controls.power_pref
	for scenario: Dictionary in scenarios:
		failure_scope = "pip_selection_drone" if scenario.drone else "pip_selection_decoy"
		var battle := BattleSimulation.new()
		add_child(battle)
		battle.set_physics_process(false)
		battle.world = BattleWorld.new()
		battle.world.bounds = {"minX": -1000, "maxX": 1000, "minZ": -1000, "maxZ": 1000}
		battle.add_child(battle.world)
		var pilot := BattleUnit.new()
		pilot.peer_id = 17
		pilot.kind = "drone" if scenario.drone else "robot"
		pilot.hp = 1
		battle.add_child(pilot)
		var view := PipView.new()
		add_child(view)
		var actors := {}
		var revisions := {}
		for index in scenario.steps.size():
			var frame: Dictionary = scenario.steps[index]
			Controls.power_pref = "1" if frame.low else "0"
			var retained := {}
			for row: Dictionary in frame.rows:
				var id := int(row.id)
				retained[id] = true
				if not actors.has(id):
					var actor := BattleUnit.new()
					actor.entity_id = id
					actor.peer_id = 17
					actor.kind = "drone" if row.hero else "decoy"
					actor.character = "s01" if row.hero else ""
					actor.special = {"owner_peer": 17}
					battle.add_child(actor)
					actor.model = MeshInstance3D.new()
					actor.model.mesh = BoxMesh.new()
					actor.add_child(actor.model)
					battle.units[id] = actor
					actors[id] = actor
					revisions[id] = int(row.modelRevision)
				var actor: BattleUnit = actors[id]
				if revisions[id] != int(row.modelRevision):
					var old := actor.model
					actor.remove_child(old)
					old.free()
					actor.model = MeshInstance3D.new()
					actor.model.mesh = BoxMesh.new()
					actor.add_child(actor.model)
					revisions[id] = int(row.modelRevision)
				actor.hp = 0 if row.dead else 1
				actor.special.lost = bool(row.lost)
				actor.yaw = float(row.yaw)
				actor.model.position = Vector3(row.position[0], row.position[1], row.position[2])
			for id: int in actors.keys():
				if not retained.has(id):
					battle.units.erase(id)
					actors[id].queue_free()
					actors.erase(id)
					revisions.erase(id)
			if index == 0:
				view.update_view(battle, pilot, "STEEL")
			view._begin_frame()
			var selected: Array = frame.selected
			for slot_index in view.views.size():
				var slot: Dictionary = view.views[slot_index]
				var active := slot_index < selected.size()
				_check(slot.border.visible == active and (slot.viewport.world_3d != null) == active
					and slot.viewport.render_target_update_mode == (SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED),
					"Original source availability reaches the correct PiP slot: " + str(frame.phase))
				if active:
					var draw: Dictionary = frame.draws[slot_index]
					var expected := Vector3(draw.position[0], draw.position[1], draw.position[2])
					_check(slot.camera.global_position == expected, "Original current source position reaches the PiP camera: " + str(frame.phase))
					var yaw := float(draw.yaw)
					var forward := Vector3(-sin(yaw), 0, -cos(yaw))
					_check((-slot.camera.global_basis.z).distance_to(forward) < 0.000001,
						"Original current source heading reaches the PiP camera: " + str(frame.phase))
			for id: int in actors:
				var expected_mask := 1
				for slot_index in selected.size():
					if int(selected[slot_index]) == id:
						expected_mask = PipView.SOURCE_MASKS[slot_index]
				_check(actors[id].model.layers == expected_mask, "Only current source bodies receive exclusion layers: " + str(frame.phase))
			view._end_frame()
		view.free()
		battle.free()
	Controls.power_pref = saved_power

func _check_late_render(original: Dictionary, composition: Dictionary) -> void:
	_check(DisplayServer.get_name() != "headless", "Late PiP selection requires a real rendered frame")
	if DisplayServer.get_name() == "headless":
		return
	var saved_power: Variant = Controls.power_pref
	Controls.power_pref = "0"
	var stage := SubViewport.new()
	stage.size = Vector2i(320, 568)
	stage.world_3d = World3D.new()
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLUE
	stage.add_child(environment)
	var battle := BattleSimulation.new()
	stage.add_child(battle)
	battle.set_physics_process(false)
	battle.world = BattleWorld.new()
	battle.world.bounds = {"minX": -1000, "maxX": 1000, "minZ": -1000, "maxZ": 1000}
	battle.add_child(battle.world)
	var pilot := BattleUnit.new()
	pilot.peer_id = 17
	pilot.kind = "robot"
	pilot.hp = 1
	battle.add_child(pilot)
	var actors: Array[BattleUnit] = []
	for id: int in [7, 9]:
		var actor := BattleUnit.new()
		actor.entity_id = id
		actor.kind = "decoy"
		actor.hp = 1
		actor.special = {"owner_peer": 17}
		battle.add_child(actor)
		actor.model = Node3D.new()
		actor.add_child(actor.model)
		battle.units[id] = actor
		actors.append(actor)
	var background := ColorRect.new()
	background.color = Color.BLACK
	background.size = Vector2(stage.size)
	stage.add_child(background)
	var view := PipView.new()
	stage.add_child(view)
	var overlay := ColorRect.new()
	overlay.color = Color.RED
	overlay.position = Vector2(20, 65)
	overlay.size = Vector2(8, 8)
	stage.add_child(overlay)
	view.update_view(battle, pilot, "STEEL")
	await RenderingServer.frame_post_draw
	_check_composite(stage, original.pipFrames[0], original.rules, Color.BLUE, "full", composition.cases[0])
	actors[0].special.lost = true
	environment.environment.background_color = Color.GREEN
	await RenderingServer.frame_post_draw
	_check(view.pending_tags.size() == 1 and view.pending_tags[0].root == actors[1].model,
		"Late loss promotes the surviving source before the actual render")
	# The controlled scene has one uniform green view in both source cases.
	_check_composite(stage, original.pipFrames[1], original.rules, Color.GREEN, "low", composition.cases[1])
	actors[1].special.lost = true
	await RenderingServer.frame_post_draw
	_check_composite(stage, {"draws": []}, original.rules, Color.GREEN, "late-lost")
	actors[0].special.lost = false
	await RenderingServer.frame_post_draw
	_check(view.pending_tags.size() == 1 and view.pending_tags[0].root == actors[0].model,
		"A recovered source is selected before the actual render")
	_check_composite(stage, original.pipFrames[1], original.rules, Color.GREEN, "low", composition.cases[1])
	var world := battle.world
	battle.remove_child(world)
	await RenderingServer.frame_post_draw
	_check(view.pending_tags.is_empty() and view.views.all(func(slot): return slot.viewport.world_3d == null),
		"Detaching the active world releases every PiP before rendering")
	battle.add_child(world)
	await RenderingServer.frame_post_draw
	_check(view.pending_tags.is_empty() and view.views.all(func(slot): return slot.viewport.world_3d == null),
		"World reattachment waits for a fresh PiP selection")
	view.update_view(battle, pilot, "STEEL")
	await RenderingServer.frame_post_draw
	_check_composite(stage, original.pipFrames[1], original.rules, Color.GREEN, "low", composition.cases[1])
	world.queue_free()
	await RenderingServer.frame_post_draw
	_check(view.pending_tags.is_empty() and view.views.all(func(slot): return slot.viewport.world_3d == null),
		"A retiring world releases every PiP before rendering")
	view.free()
	stage.free()
	Controls.power_pref = saved_power
