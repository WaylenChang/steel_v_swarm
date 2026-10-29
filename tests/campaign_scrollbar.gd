extends "res://tests/run.gd"

const Helpers = preload("res://tests/campaign_crawl_insets.gd")
const Raster = preload("res://tests/raster_compare.gd")

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/campaign_scrollbar.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	var output := ""
	var probe := false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence-dir="):
			output = argument.trim_prefix("--evidence-dir=")
		elif argument == "--probe-native":
			probe = true
	if not output.is_empty():
		var absolute := ProjectSettings.globalize_path(output)
		_check(not DirAccess.dir_exists_absolute(absolute), "Preserve existing scrollbar evidence")
		if not DirAccess.dir_exists_absolute(absolute):
			_check(DirAccess.make_dir_recursive_absolute(absolute) == OK, "Create scrollbar evidence directory")
	_check(DisplayServer.get_name() != "headless", "Scrollbar pixels require a real display driver")
	_check(capture.get("formatVersion") == 1 and capture.get("programs") is Array and capture.programs.size() == 17,
		"Capture original cinematic scrollbar rasters")
	if failures == 0:
		for path: String in capture.source.inputs:
			var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(text.sha256_text() == capture.source.inputs[path], "Current scrollbar capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original scrollbar input: " + path)
	if failures == 0:
		await _check_programs(capture, output, probe)
	print("CAMPAIGN_SCROLLBAR assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_programs(capture: Dictionary, output: String, probe: bool) -> void:
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
		background.color = Color8(capture.background[0], capture.background[1], capture.background[2], capture.background[3])
		viewport.add_child(background)
		var view := Helpers.ProbeView.new()
		add_child(view)
		view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		view.size = Vector2(640, 360)
		view.play(Content.campaign.prologue.slice(0, 1), "Continue")
		view.set_process(false)
		await get_tree().process_frame
		view.scroll.get_parent().remove_child(view.scroll)
		viewport.add_child(view.scroll)
		view.scroll.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		view.scroll.position = Vector2.ZERO
		view.scroll.size = Vector2(viewport.size)
		for side in ["top", "right", "bottom", "left"]:
			view.crawl_margin.add_theme_constant_override("margin_" + side, 0)
		for child in view.column.get_children():
			view.column.remove_child(child)
			child.queue_free()
		view.sections.clear()
		var content := Control.new()
		content.custom_minimum_size.y = sample.contentHeight
		view.column.add_child(content)
		view.scroll.size = Vector2(viewport.size)
		await _settle()
		view.scroll.scroll_vertical = int(sample.requested)
		await _settle()
		var expected := Image.new()
		var actual := viewport.get_texture().get_image()
		var decoded := expected.load_png_from_buffer(Marshalls.base64_to_raw(sample.png)) == OK and expected.get_size() == actual.get_size()
		_check(decoded, "Original scrollbar raster has matching dimensions")
		if decoded:
			var result := Raster.compare(actual, expected)
			var entry := {"size": sample.size, "scroll": sample.scroll, "clientWidth": view.crawl_margin.size.x,
				"pixels": result.pixels, "maximum": result.maximum}
			_near(view.crawl_margin.size.x, sample.clientWidth, "Original scrollbar content width")
			_near(view.scroll.scroll_vertical, sample.scroll, "Original scrollbar scroll offset")
			_check(result.pixels == 0, "Original scrollbar size=%s scroll=%d pixels=%d maximum=%f" % [sample.size, sample.scroll, result.pixels, result.maximum])
			if not output.is_empty():
				Raster.diagnostic(actual).save_png(output + "/native_%d.png" % index)
				expected.save_png(output + "/source_%d.png" % index)
			if probe:
				_apply_native_candidate(view.scroll.get_v_scroll_bar(), capture.style)
				view.scroll.queue_sort()
				view.scroll.size = Vector2(viewport.size)
				await _settle()
				view.scroll.scroll_vertical = int(sample.requested)
				await _settle()
				var candidate := viewport.get_texture().get_image()
				var comparison := Raster.compare(candidate, expected)
				entry.candidateClientWidth = view.crawl_margin.size.x
				entry.candidatePixels = comparison.pixels
				entry.candidateMaximum = comparison.maximum
				print("NATIVE_SCROLLBAR_CANDIDATE size=", sample.size, " scroll=", sample.scroll,
					" width=", view.crawl_margin.size.x, " pixels=", comparison.pixels, " maximum=", comparison.maximum)
				if not output.is_empty():
					Raster.diagnostic(candidate).save_png(output + "/candidate_%d.png" % index)
			report.append(entry)
		view.dispose()
		view.free()
		viewport.free()
	if not output.is_empty():
		var file := FileAccess.open(output + "/report.json", FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report, "  "))
			file.close()

func _settle() -> void:
	for repeat in range(3):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

func _apply_native_candidate(bar: VScrollBar, style: Dictionary) -> void:
	bar.custom_minimum_size.x = float(style.width)
	var transparent := StyleBoxFlat.new()
	transparent.bg_color = Color.TRANSPARENT
	transparent.content_margin_left = float(style.width) / 2
	transparent.content_margin_right = float(style.width) / 2
	for name in ["scroll", "scroll_focus"]:
		bar.add_theme_stylebox_override(name, transparent)
	var thumb := StyleBoxFlat.new()
	thumb.bg_color = Color(95.0 / 255, 208.0 / 255, 242.0 / 255, .25)
	thumb.set_corner_radius_all(int(style.radius))
	thumb.content_margin_left = float(style.width) / 2
	thumb.content_margin_right = float(style.width) / 2
	for name in ["grabber", "grabber_highlight", "grabber_pressed"]:
		bar.add_theme_stylebox_override(name, thumb)
