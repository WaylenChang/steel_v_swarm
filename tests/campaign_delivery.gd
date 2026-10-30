extends "res://tests/run.gd"

class ProbeView extends CampaignCinematic:
	var metrics_ready := false

	func _layout() -> void:
		pass

	func _make_art_layer() -> Control:
		var layer = preload("res://scripts/campaign_art_layer.gd").new()
		layer.texture_provider = func(_path: String, _mipmaps: bool): return null
		return layer

	func _update_scene() -> void:
		if metrics_ready:
			super._update_scene()

class ReentrantView extends ProbeView:
	var selection_action := Callable()
	func _set_scene(index: int) -> void:
		super._set_scene(index)
		if selection_action.is_valid():
			var action := selection_action
			selection_action = Callable()
			action.call()

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/campaign_delivery.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Cinematic delivery capture is current")
	for path: String in capture.source.sourceInputs:
		_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Cinematic delivery retains original controller and camera functions")
	if failures > 0:
		_finish_delivery()
		return
	for program: Dictionary in capture.programs:
		var clock := {"now": 1000.0}
		var view := ProbeView.new()
		view.clock_msec = func(): return clock.now
		add_child(view)
		view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		view.size = Vector2(1000, 500) if program.landscape else Vector2(500, 1000)
		view.play(capture.scenes, "Continue")
		view.set_process(false)
		await get_tree().process_frame
		view.scroll.get_parent().remove_child(view.scroll)
		view.presentation_group.add_child(view.scroll)
		view.scroll.custom_minimum_size = Vector2.ZERO
		view.scroll.size = Vector2(program.geometry.width, program.geometry.height)
		for child in view.column.get_children():
			view.column.remove_child(child)
			child.queue_free()
		view.sections.clear()
		view.column.custom_minimum_size.y = program.geometry.scrollHeight
		view.column.size.y = program.geometry.scrollHeight
		for metric: Dictionary in program.geometry.sections:
			var section := Control.new()
			view.add_child(section)
			section.position.y = metric.top
			section.size.y = metric.height
			view.sections.append(section)
		await get_tree().process_frame
		var bar := view.scroll.get_v_scroll_bar()
		_check(bar.max_value == program.geometry.scrollHeight and bar.page == program.geometry.height, "Native delivery probe retains declared scroll geometry")
		view.metrics_ready = true
		view._update_scene()
		for frame: Dictionary in program.frames:
			var operation: Dictionary = frame.operation
			clock.now = operation.time
			match operation.type:
				"frame": view._process(operation.delta)
				"scroll": bar.value = operation.value
				"wheel":
					var event := InputEventMouseButton.new()
					event.button_index = MOUSE_BUTTON_WHEEL_DOWN
					event.pressed = true
					view._scroll_input(event)
				"geometry":
					for index in range(operation.sections.size()):
						view.sections[index].position.y = operation.sections[index].top
						view.sections[index].size.y = operation.sections[index].height
			_near(bar.value, frame.scroll, "Original scroll position reaches native camera selection")
			_check(view.active == frame.active, "Original nearest section, gaps, shared boundaries and zero-height selection")
			for index in range(frame.targets.size()):
				_check(view.art_layers[index].pose_target == frame.targets[index], "Original frame/pause/scroll ordering delivers the serialized target to the matching retained scene")
		view.dispose()
		view.free()
	await _check_selection_reentrancy(capture.scenes)
	await _check_deferred_start_reentrancy(capture.scenes)
	await _check_art_selection_reentrancy(capture.scenes)
	_finish_delivery()

func _check_art_selection_reentrancy(scenes: Array) -> void:
	for operation in ["replace", "dispose", "ancestor", "select"]:
		var parent := Node.new()
		add_child(parent)
		var view := ProbeView.new()
		parent.add_child(view)
		view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		view.size = Vector2(1000, 500)
		view.play(scenes, "Continue")
		view.set_process(false)
		await get_tree().process_frame
		var layer: CampaignArtLayer = view.art_layers[1]
		var entered := {"value": false}
		var on_visibility := func():
			if entered.value or not layer.group.visible:
				return
			entered.value = true
			match operation:
				"replace": view.play([scenes[2]], "Continue")
				"dispose": view.dispose()
				"ancestor": parent.queue_free()
				"select": view._set_scene(2)
		layer.group.visibility_changed.connect(on_visibility)
		view._set_scene(1)
		_check(entered.value, "Art visibility emits a synchronous selection callback")
		_check(layer.tween == null or not layer.tween.is_valid(),
			"Retired or superseded art selection cannot start an obsolete opacity tween")
		match operation:
			"replace":
				_check(view.playing and view.scenes.size() == 1 and view.scenes[0].id == scenes[2].id
					and view.active == 0 and view.heading.text == scenes[2].title,
					"Retired art selection cannot overwrite replacement heading or selection")
			"dispose":
				_check(not view.playing and view.scenes.is_empty(), "Art selection can synchronously dispose playback")
			"ancestor":
				_check(parent.is_queued_for_deletion(), "Art selection can synchronously retire an ancestor")
			"select":
				_check(view.playing and view.active == 2 and view.heading.text == scenes[2].title
					and not layer.selected and (layer.tween == null or not layer.tween.is_valid()),
					"Nested selection retains the latest scene, heading and art transition")
		if operation == "ancestor":
			await get_tree().process_frame
		else:
			view.dispose()
			parent.free()

func _check_deferred_start_reentrancy(scenes: Array) -> void:
	var view := ReentrantView.new()
	add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(1000, 500)
	view.play(scenes, "Continue", 1)
	view.set_process(false)
	view.metrics_ready = true
	var called := {"value": false}
	view.selection_action = func():
		called.value = true
		view.play([scenes[1], scenes[0]], "Continue")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(called.value and view.playing and view.scenes[0].id == scenes[1].id,
		"A deferred chapter jump can synchronously replace playback")
	_check(view.active == 0, "The retired deferred jump cannot select a chapter in its replacement")
	view.dispose()
	view.free()

func _check_selection_reentrancy(scenes: Array) -> void:
	for operation in ["replace", "dispose", "ancestor"]:
		var parent := Node.new()
		add_child(parent)
		var view := ReentrantView.new()
		parent.add_child(view)
		view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		view.size = Vector2(1000, 500)
		view.play(scenes, "Continue")
		view.set_process(false)
		await get_tree().process_frame
		view.metrics_ready = true
		var previous_poses: Array = view.art_layers.map(func(layer): return layer.pose_target.duplicate())
		view.selection_action = func():
			match operation:
				"replace": view.play([scenes[1]], "Continue")
				"dispose": view.dispose()
				"ancestor": parent.queue_free()
		view._update_scene()
		match operation:
			"replace":
				_check(view.playing and view.scenes.size() == 1 and view.scenes[0].id == scenes[1].id,
					"Selection can synchronously replace the active cinematic")
				_check(view.art_layers[0].pose_target == {"scale": 1.0, "x": 0.0, "y": 0.0},
					"The retired scroll update cannot send its camera pose to the replacement")
				view.dispose()
				parent.free()
			"dispose":
				_check(not view.playing and view.scenes.is_empty(), "Selection can synchronously dispose the cinematic")
				parent.free()
			"ancestor":
				_check(parent.is_queued_for_deletion(), "Selection can synchronously queue a cinematic ancestor")
				_check(view.art_layers.map(func(layer): return layer.pose_target) == previous_poses,
					"A queued ancestor cannot receive a retired camera target")
				await get_tree().process_frame

func _finish_delivery() -> void:
	print("CAMPAIGN_DELIVERY assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
