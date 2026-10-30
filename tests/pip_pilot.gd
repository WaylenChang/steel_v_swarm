extends "res://tests/pip_composition.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/pip_pilot.json")
	_check(capture.get("formatVersion") == 1 and capture.get("cases") is Array and capture.cases.size() == 4,
		"Capture original PiP pilot death and re-entry decisions")
	if failures == 0:
		var provenance: Dictionary = Content.read_json("res://data/provenance.json")
		for path: String in capture.source.inputs:
			var source := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(source.sha256_text() == capture.source.inputs[path], "Current PiP pilot capture input: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.get("inputs", {}).get(path) == capture.source.sourceInputs[path], "Original PiP pilot source identity: " + path)
		var alive: Array = capture.cases[0].selected
		var revived: Array = capture.cases[2].selected
		_check(alive.size() == 2 and int(alive[0]) == 7 and int(alive[1]) == 9
			and capture.cases[1].selected.is_empty() and revived.size() == 2
			and int(revived[0]) == 7 and int(revived[1]) == 9, "Original render re-evaluates pilot death and revival")
	if failures == 0:
		var original: Dictionary = Content.read_json("res://tests/fixtures/pip.json")
		var composition: Dictionary = Content.read_json("res://tests/fixtures/pip_composition.json")
		_check_pip_source_identity(original, composition)
		if failures == 0:
			_check_lifecycle()
			_check_owner_ancestors()
			_check_render_signals()
			failure_scope = "pip_existing_lifecycle"
			_lifecycle()
			_retiring_sources(original.pipFrames[0])
	print("PIP_PILOT assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _context() -> Dictionary:
	var battle := BattleSimulation.new()
	add_child(battle)
	battle.set_physics_process(false)
	battle.world = BattleWorld.new()
	battle.world.bounds = {"minX": -1000, "maxX": 1000, "minZ": -1000, "maxZ": 1000}
	battle.add_child(battle.world)
	var pilot := BattleUnit.new()
	pilot.peer_id = 17
	pilot.kind = "robot"
	pilot.hp = 1
	battle.add_child(pilot)
	pilot.cockpit = CockpitRig.new()
	pilot.add_child(pilot.cockpit)
	var cockpit_mesh := MeshInstance3D.new()
	cockpit_mesh.mesh = BoxMesh.new()
	pilot.cockpit.add_child(cockpit_mesh)
	var meshes: Array[MeshInstance3D] = []
	for id: int in [7, 9]:
		var actor := BattleUnit.new()
		actor.entity_id = id
		actor.peer_id = 17
		actor.kind = "decoy"
		actor.hp = 1
		actor.special = {"owner_peer": 17}
		battle.add_child(actor)
		actor.model = Node3D.new()
		actor.add_child(actor.model)
		var mesh := MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		actor.model.add_child(mesh)
		meshes.append(mesh)
		battle.units[id] = actor
	var view := PipView.new()
	add_child(view)
	return {"battle": battle, "pilot": pilot, "cockpit": cockpit_mesh, "meshes": meshes, "view": view}

func _select(context: Dictionary) -> void:
	context.view.update_view(context.battle, context.pilot, "STEEL")
	context.view._begin_frame()
	var active: bool = context.view.views.size() == 2
	for slot: Dictionary in context.view.views:
		active = active and slot.border.visible and slot.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS and slot.viewport.world_3d != null
	_check(active, "Original living pilot selects both PiP views")
	_check(context.cockpit.layers == PipView.COCKPIT_MASK and context.meshes[0].layers == PipView.SOURCE_MASKS[0]
		and context.meshes[1].layers == PipView.SOURCE_MASKS[1], "Selected PiP owns the temporary exclusion layers")

func _check_released(context: Dictionary, label: String) -> void:
	var stopped := true
	for slot: Dictionary in context.view.views:
		stopped = stopped and not slot.border.visible and slot.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and slot.viewport.world_3d == null
	_check(stopped, label + " disables viewports and releases the shared world")
	var cockpit_restored: bool = not is_instance_valid(context.cockpit) or context.cockpit.layers == 1
	var restored: bool = context.view.pending_tags.is_empty() and context.view.layers.is_empty() and cockpit_restored
	for mesh: MeshInstance3D in context.meshes:
		restored = restored and mesh.layers == 1
	_check(restored, label + " restores all temporary layers")

func _check_lifecycle() -> void:
	var saved_power: Variant = Controls.power_pref
	Controls.power_pref = "0"
	for action: String in ["death", "detach", "queue", "free", "battle_queue"]:
		failure_scope = "pip_pilot_" + action
		var context := _context()
		_select(context)
		match action:
			"death": context.pilot.hp = 0
			"detach": context.battle.remove_child(context.pilot)
			"queue": context.pilot.queue_free()
			"free": context.pilot.free()
			"battle_queue": context.battle.queue_free()
		context.view._begin_frame()
		_check_released(context, "Pilot " + action + " before the render boundary")
		if action == "queue":
			context.view.update_view(context.battle, context.pilot, "STEEL")
			_check_released(context, "A queued pilot cannot be selected again")
		elif action not in ["free", "battle_queue"]:
			if action == "detach":
				context.view.update_view(context.battle, context.pilot, "STEEL")
				_check_released(context, "A detached pilot cannot be selected again")
			if action == "death":
				context.pilot.hp = 1
			else:
				context.battle.add_child(context.pilot)
			context.view._begin_frame()
			_check_released(context, "Pilot recovery before a fresh selection")
			_select(context)
		context.view.free()
		context.battle.free()
	Controls.power_pref = saved_power

func _check_render_signals() -> void:
	var host := Control.new()
	add_child(host)
	var view := PipView.new()
	host.add_child(view)
	_check(RenderingServer.frame_pre_draw.is_connected(view._begin_frame)
		and RenderingServer.frame_post_draw.is_connected(view._end_frame), "Visible PiP subscribes to both render boundaries")
	for change in ["self", "ancestor", "detach"]:
		match change:
			"self": view.hide()
			"ancestor": host.hide()
			"detach": host.remove_child(view)
		_check(not RenderingServer.frame_pre_draw.is_connected(view._begin_frame)
			and not RenderingServer.frame_post_draw.is_connected(view._end_frame),
			"Inactive PiP releases global render callbacks: " + change)
		match change:
			"self": view.show()
			"ancestor": host.show()
			"detach": host.add_child(view)
		_check(RenderingServer.frame_pre_draw.is_connected(view._begin_frame)
			and RenderingServer.frame_post_draw.is_connected(view._end_frame),
			"Visible PiP restores its render callbacks: " + change)
		_check(view.pending_tags.is_empty() and view.layers.is_empty(), "Reactivation requires fresh PiP selection")
	view.free()
	host.free()
	var hidden_host := Control.new()
	hidden_host.hide()
	add_child(hidden_host)
	var hidden_view := PipView.new()
	hidden_host.add_child(hidden_view)
	_check(not RenderingServer.frame_pre_draw.is_connected(hidden_view._begin_frame)
		and not RenderingServer.frame_post_draw.is_connected(hidden_view._end_frame),
		"PiP first attached beneath a hidden ancestor does not subscribe")
	hidden_host.show()
	_check(RenderingServer.frame_pre_draw.is_connected(hidden_view._begin_frame)
		and RenderingServer.frame_post_draw.is_connected(hidden_view._end_frame),
		"First visibility subscribes a previously hidden PiP")
	hidden_host.free()

func _check_owner_ancestors() -> void:
	var saved_power: Variant = Controls.power_pref
	Controls.power_pref = "0"
	for sample: Array in [[true, "render"], [false, "render"], [true, "selection"], [false, "selection"]]:
		var queued_parent: bool = sample[0]
		var boundary: String = sample[1]
		failure_scope = ("pip_owner_parent_" if queued_parent else "pip_owner_ancestor_") + boundary
		var context := _context()
		var ancestor := Control.new()
		add_child(ancestor)
		var parent := Control.new()
		ancestor.add_child(parent)
		remove_child(context.view)
		parent.add_child(context.view)
		_select(context)
		var retiring: Control = parent if queued_parent else ancestor
		retiring.queue_free()
		if boundary == "render":
			context.view._begin_frame()
		else:
			context.view.update_view(context.battle, context.pilot, "STEEL")
		_check_released(context, "Queued PiP owner ancestor at " + boundary)
		context.view._begin_frame()
		context.view.update_view(context.battle, context.pilot, "STEEL")
		_check_released(context, "Queued PiP owner ancestor cannot select again")
		ancestor.free()
		context.battle.free()
	Controls.power_pref = saved_power
