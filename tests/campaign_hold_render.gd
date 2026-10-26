extends "res://tests/run.gd"

const Raster = preload("res://tests/raster_compare.gd")

func _run() -> void:
	_check(DisplayServer.get_name() != "headless", "Hold raster qualification requires a rendered session")
	var capture: Dictionary = Content.read_json("res://tests/fixtures/campaign_hold.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Hold raster capture is current")
	for path: String in capture.source.sourceInputs:
		_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Hold raster retains original source identity")
	if failures > 0:
		_finish_render()
		return
	var output := "res://build/campaign_hold"
	_check(DirAccess.make_dir_recursive_absolute(output) == OK, "Create hold raster evidence directory")
	var report: Array = []
	for index in range(capture.rasters.size()):
		var item: Dictionary = capture.rasters[index]
		var viewport := SubViewport.new()
		viewport.size = Vector2i(128, 128)
		viewport.disable_3d = true
		viewport.transparent_bg = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		var hold = preload("res://scripts/campaign_hold.gd").new()
		var host: Node = viewport
		if OS.get_cmdline_user_args().has("--nested-presentation"):
			var presentation := CanvasGroup.new()
			viewport.add_child(presentation)
			host = presentation
		host.add_child(hold)
		hold.position = Vector2(64, 48)
		hold.opacity = item.opacity
		hold.dash_offset = item.offset
		hold.stroke.visible = item.stroke
		for frame in range(3):
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
		var actual := viewport.get_texture().get_image()
		var expected := Image.new()
		var valid := expected.load_png_from_buffer(Marshalls.base64_to_raw(item.png)) == OK and expected.get_size() == actual.get_size()
		_check(valid, "Original hold raster has matching dimensions")
		if valid:
			var result := Raster.compare(actual, expected)
			report.append({"case": index, "opacity": item.opacity, "offset": item.offset, "stroke": item.stroke, "pixels": result.pixels, "maximum": result.maximum,
				"nativeCenterAlpha": actual.get_pixel(64, 48).a, "sourceCenterAlpha": expected.get_pixel(64, 48).a})
			_check(result.pixels == 0, "Original hold ring, caption and group opacity: case=%d pixels=%d maximum=%f" % [index, result.pixels, result.maximum])
			Raster.diagnostic(actual).save_png(output + "/native_%d.png" % index)
			expected.save_png(output + "/source_%d.png" % index)
		viewport.free()
	var file := FileAccess.open(output + "/report.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	_finish_render()

func _finish_render() -> void:
	print("CAMPAIGN_HOLD_RENDER assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
