extends "res://tests/run.gd"

const Raster = preload("res://tests/raster_compare.gd")

class ProbeView extends CampaignCinematic:
	func _make_art_layer() -> Control:
		var layer := CampaignArtLayer.new()
		layer.texture_provider = func(_path: String, _mipmaps: bool): return null
		return layer
	func _update_scene() -> void:
		pass

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/campaign_crawl_mask.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	var output := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence-dir="):
			output = argument.trim_prefix("--evidence-dir=")
	if not output.is_empty():
		var absolute := ProjectSettings.globalize_path(output)
		_check(not DirAccess.dir_exists_absolute(absolute), "Preserve existing crawl-mask evidence")
		if not DirAccess.dir_exists_absolute(absolute):
			_check(DirAccess.make_dir_recursive_absolute(absolute) == OK, "Create crawl-mask evidence directory")
	_check(DisplayServer.get_name() != "headless", "Crawl mask pixels require a real display driver")
	_check(capture.get("formatVersion") == 1 and capture.get("programs") is Array and capture.programs.size() == 6,
		"Capture original crawl mask and unmasked controls")
	if failures == 0:
		for path: String in capture.source.inputs:
			var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(text.sha256_text() == capture.source.inputs[path], "Current crawl mask capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original crawl mask input: " + path)
	if failures == 0:
		await _check_programs(capture, output)
	print("CAMPAIGN_CRAWL_MASK assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_programs(capture: Dictionary, output: String) -> void:
	var report: Array = []
	for index in range(capture.programs.size()):
		var sample: Dictionary = capture.programs[index]
		var viewport := SubViewport.new()
		viewport.size = Vector2i(sample.size[0], sample.size[1])
		viewport.disable_3d = true
		viewport.transparent_bg = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		var background := ColorRect.new()
		background.size = Vector2(viewport.size)
		background.color = Color(capture.backdrop[0], capture.backdrop[1], capture.backdrop[2], capture.backdrop[3])
		viewport.add_child(background)
		var group := CanvasGroup.new()
		viewport.add_child(group)
		var view := ProbeView.new()
		viewport.add_child(view)
		view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		view.size = Vector2(viewport.size)
		view.play([Content.campaign.prologue[0]], "Continue")
		view.set_process(false)
		view.scroll.get_parent().remove_child(view.scroll)
		group.add_child(view.scroll)
		view.hide()
		view.scroll.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		view.scroll.position = Vector2.ZERO
		view.scroll.custom_minimum_size = Vector2.ZERO
		view.scroll.size = Vector2(viewport.size)
		view.scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		view.scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		for side in ["top", "right", "bottom", "left"]:
			view.crawl_margin.add_theme_constant_override("margin_" + side, 0)
		for child in view.column.get_children():
			view.column.remove_child(child)
			child.queue_free()
		view.sections.clear()
		var surface := Control.new()
		surface.custom_minimum_size = Vector2(viewport.size)
		view.column.add_child(surface)
		for item: Dictionary in sample.layers:
			var panel := ColorRect.new()
			panel.position = Vector2(item.rect[0], item.rect[1])
			panel.size = Vector2(item.rect[2], item.rect[3])
			panel.color = Color(item.rgba[0], item.rgba[1], item.rgba[2], item.rgba[3])
			surface.add_child(panel)
		for repeat in range(3):
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
		var actual := viewport.get_texture().get_image()
		var expected := Image.new()
		var decoded := expected.load_png_from_buffer(Marshalls.base64_to_raw(sample.png)) == OK and expected.get_size() == actual.get_size()
		_check(decoded, "Original crawl mask raster has matching dimensions")
		if decoded:
			var result := Raster.compare(actual, expected)
			var source_pixel := expected.get_pixel(expected.get_width() - 1, 0)
			var native_pixel := actual.get_pixel(actual.get_width() - 1, 0)
			report.append({"size": sample.size, "enabled": sample.enabled, "pixels": result.pixels, "maximum": result.maximum,
				"sourceTop": [source_pixel.r8, source_pixel.g8, source_pixel.b8, source_pixel.a8],
				"nativeTop": [native_pixel.r8, native_pixel.g8, native_pixel.b8, native_pixel.a8]})
			_check(result.pixels == 0, "Original crawl mask enabled=%s size=%s pixels=%d maximum=%f" % [sample.enabled, sample.size, result.pixels, result.maximum])
			if not output.is_empty():
				Raster.diagnostic(actual).save_png(output + "/native_%d.png" % index)
				expected.save_png(output + "/source_%d.png" % index)
		view.dispose()
		view.free()
		viewport.free()
	if not output.is_empty():
		var file := FileAccess.open(output + "/report.json", FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report, "  "))
			file.close()
