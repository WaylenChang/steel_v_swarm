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
	_finish_delivery()

func _finish_delivery() -> void:
	print("CAMPAIGN_DELIVERY assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
