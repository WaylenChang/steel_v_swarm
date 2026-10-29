extends "res://tests/run.gd"

const Raster = preload("res://tests/raster_compare.gd")

class ProbeView extends CampaignCinematic:
	# Declared color layers isolate source transition/composition from unavailable story art.
	func _make_art_layer() -> Control:
		var layer = preload("res://scripts/campaign_art_layer.gd").new()
		layer.texture_provider = func(_path: String, _mipmaps: bool): return null
		return layer

	func _update_scene() -> void:
		pass

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/campaign_art.json")
	var data: Dictionary = Content.read_json("res://data/campaign_art.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(DisplayServer.get_name() != "headless", "Cinematic art qualification requires a rendered session")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Cinematic art capture is current")
	for path: String in capture.source.sourceInputs:
		_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Cinematic art retains original construction, scene selection and CSS identity")
	_check(data.source == capture.source and data.rules == capture.rules, "Native cinematic art transition resource equals source capture")
	_check(capture.rules.duration == Content.campaign.presentation.art.fade, "Native art duration retains imported source CSS value")
	if failures > 0:
		_finish_art()
		return
	var output := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence-dir="):
			output = argument.trim_prefix("--evidence-dir=")
	if not output.is_empty():
		var absolute := ProjectSettings.globalize_path(output)
		_check(not DirAccess.dir_exists_absolute(absolute), "Preserve existing cinematic art evidence")
		if failures > 0:
			_finish_art()
			return
		_check(DirAccess.make_dir_recursive_absolute(absolute) == OK, "Create cinematic art evidence directory")
	var report: Array = []
	for program_index in range(capture.programs.size()):
		var program: Dictionary = capture.programs[program_index]
		var viewport := SubViewport.new()
		viewport.size = Vector2i(96, 64)
		viewport.disable_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		var view := ProbeView.new()
		viewport.add_child(view)
		view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		view.size = Vector2(viewport.size)
		view.play(capture.scenes, "Continue", int(program.frames[0].index))
		view.set_process(false)
		_pause_art(view)
		await get_tree().process_frame
		view.card.hide()
		view.tag.hide()
		view.buffer_status.hide()
		view.caption.hide()
		view.hold_indicator.hide()
		var identities: Array = []
		for index in range(view.art_layers.size()):
			var layer = view.art_layers[index]
			identities.append(layer.get_instance_id())
			layer.background.hide()
			layer.frame.hide()
			for item: Dictionary in capture.layers[index]:
				var panel := ColorRect.new()
				panel.position = Vector2(item.rect[0], item.rect[1])
				panel.size = Vector2(item.rect[2], item.rect[3])
				panel.color = ScopeOverlay.color_value(item.rgba)
				panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
				layer.content.add_child(panel)
		for frame_index in range(program.frames.size()):
			var sample: Dictionary = program.frames[frame_index]
			if sample.select:
				view._set_scene(int(sample.index))
			_pause_art(view)
			for index in range(view.art_layers.size()):
				var layer = view.art_layers[index]
				if layer.tween != null and layer.tween.is_valid():
					layer.tween.custom_step(sample.delta)
				_near(layer.opacity, sample.opacity[index], "Original independent art opacity, unchanged targets and CSS reversal shortening")
				_check(layer.name == sample.order[index] and layer.get_instance_id() == identities[index] and layer.get_index() == index,
					"Original scene construction order and every fading layer survive rapid three-way changes")
				_check(absf(layer.group.self_modulate.a - layer.opacity) < .000001,
					"Each art background and foreground share one complete-group opacity")
			if sample.has("png"):
				for frame in range(1):
					await get_tree().process_frame
					await RenderingServer.frame_post_draw
				var actual := viewport.get_texture().get_image()
				var expected := Image.new()
				var decoded := expected.load_png_from_buffer(Marshalls.base64_to_raw(sample.png)) == OK
				_check(decoded and expected.get_size() == actual.get_size(), "Original art transition raster has matching dimensions")
				if decoded and expected.get_size() == actual.get_size():
					var result := Raster.compare(actual, expected)
					report.append({"program": program_index, "frame": frame_index, "pixels": result.pixels, "maximum": result.maximum,
						"opaqueBytes": preload("res://tests/opaque_canvas_witness.gd").compare(actual, expected)})
					_check(result.pixels == 0, "Original layered art transition: frame=%d pixels=%d maximum=%f" % [frame_index, result.pixels, result.maximum])
					if not output.is_empty():
						Raster.diagnostic(actual).save_png(output + "/native_%d.png" % frame_index)
						expected.save_png(output + "/source_%d.png" % frame_index)
		var retired := view.art_layers.duplicate()
		view.dispose()
		_check(view.art_layers.is_empty() and view.art_host.get_child_count() == 0, "Cinematic replacement releases every retained art layer")
		for layer in retired:
			_check(layer.tween == null or not layer.tween.is_valid(), "Retired art cannot continue a pending opacity transition")
			_check(layer.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Retired art stops its isolated render target")
		viewport.free()
	if not output.is_empty():
		var file := FileAccess.open(output + "/report.json", FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report, "  "))
			file.close()
	_finish_art()

func _pause_art(view: CampaignCinematic) -> void:
	for layer in view.art_layers:
		if layer.tween != null and layer.tween.is_valid():
			layer.tween.pause()

func _finish_art() -> void:
	print("CAMPAIGN_ART assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
