extends "res://tests/run.gd"

class NativeLayoutView extends CampaignCinematic:
	func _make_art_layer() -> Control:
		var layer = preload("res://scripts/campaign_art_layer.gd").new()
		layer.texture_provider = func(_path: String, _mipmaps: bool): return null
		return layer

class ProbeView extends CampaignCinematic:
	var metrics: Dictionary

	func _make_art_layer() -> Control:
		var layer = preload("res://scripts/campaign_art_layer.gd").new()
		layer.texture_provider = func(_path: String, _mipmaps: bool): return null
		return layer

	func _layout() -> void:
		if scenes.is_empty():
			return
		for child in column.get_children():
			column.remove_child(child)
			child.queue_free()
		sections.clear()
		column.custom_minimum_size.y = metrics.scrollHeight
		column.size.y = metrics.scrollHeight
		for metric: Dictionary in metrics.sections:
			var section := Control.new()
			add_child(section)
			section.position.y = metric.top
			section.size.y = metric.height
			sections.append(section)

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/campaign_start.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Cinematic start capture is current")
	for path: String in capture.source.sourceInputs:
		_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Cinematic start retains original play and camera methods")
	if failures == 0:
		for start in [0, 1, 99]:
			var native := NativeLayoutView.new()
			add_child(native)
			native.play(capture.scenes, "Continue", start)
			native.set_process(false)
			_check(native.active == clampi(start, 0, capture.scenes.size() - 1), "Real initial layout preserves clamped source selection")
			for layer: Control in native.art_layers:
				_check(layer.pose_target == {"scale": 1.0, "x": 0.0, "y": 0.0}, "Real initial layout does not publish a camera target before the source frame callback")
			native.dispose()
			native.free()
		for program: Dictionary in capture.programs:
			var view := ProbeView.new()
			view.metrics = program.geometry
			add_child(view)
			view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
			view.size = Vector2(1000, 500) if program.landscape else Vector2(500, 1000)
			view.scroll.get_parent().remove_child(view.scroll)
			view.presentation_group.add_child(view.scroll)
			view.scroll.custom_minimum_size = Vector2.ZERO
			view.scroll.size = Vector2(program.geometry.width, program.geometry.height)
			view.column.custom_minimum_size.y = program.geometry.scrollHeight
			await get_tree().process_frame
			view.play(capture.scenes, "Continue", int(program.start))
			view.set_process(false)
			_check_state(view, program.initial, "Initial source selection")
			await get_tree().process_frame
			_check_state(view, program.jump, "Source deferred chapter jump")
			view.dispose()
			view.free()
	print("CAMPAIGN_START assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_state(view: CampaignCinematic, expected: Dictionary, label: String) -> void:
	_check(view.active == expected.active, label + " preserves requested chapter after focus reevaluation")
	_near(view.scroll.get_v_scroll_bar().value, expected.scroll, label + " uses clamped browser scroll")
	for index in range(expected.targets.size()):
		_check(view.art_layers[index].pose_target == expected.targets[index], label + " preserves each retained camera target")
