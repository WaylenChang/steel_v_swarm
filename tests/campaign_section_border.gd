extends "res://tests/run.gd"

const Section = preload("res://scripts/campaign_crawl_section.gd")
const Raster = preload("res://tests/raster_compare.gd")

class DashProbe extends Control:
	var color: Color
	var dash := 0.0
	func _draw() -> void:
		draw_dashed_line(Vector2(0, size.y - .5), Vector2(size.x, size.y - .5), color, 1.0, dash, true, false)

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/campaign_section_border.json")
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
		_check(not DirAccess.dir_exists_absolute(absolute), "Preserve existing section-border evidence")
		if not DirAccess.dir_exists_absolute(absolute):
			_check(DirAccess.make_dir_recursive_absolute(absolute) == OK, "Create section-border evidence directory")
	_check(DisplayServer.get_name() != "headless", "Section border pixels require a real display driver")
	_check(capture.get("formatVersion") == 1 and capture.get("programs") is Array and capture.programs.size() == 5,
		"Capture original section border rasters")
	if failures == 0:
		for path: String in capture.source.inputs:
			var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(text.sha256_text() == capture.source.inputs[path], "Current section border capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original section border input: " + path)
	if failures == 0:
		await _check_programs(capture, output, probe)
	print("CAMPAIGN_SECTION_BORDER assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_programs(capture: Dictionary, output: String, probe: bool) -> void:
	var marker_rules: Dictionary = Content.read_json("res://data/campaign_section_marker.json").rules
	var marker_geometry: Dictionary = Content.read_json("res://data/campaign_marker_geometry.json").rules
	var geometry: Dictionary = Content.read_json("res://data/campaign_section_geometry.json").rules
	var opacity_rules: Dictionary = Content.read_json("res://data/campaign_section_opacity.json").rules
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
		var group := CanvasGroup.new()
		viewport.add_child(group)
		var section := Section.new()
		section.scene = {"badge": "", "title": "", "paragraphs": []}
		section.marker_rules = marker_rules
		section.marker_geometry_rules = marker_geometry
		section.geometry_rules = geometry
		section.opacity_rules = opacity_rules
		group.add_child(section)
		for child in section.content.get_children():
			section.content.remove_child(child)
			child.queue_free()
		section.size = Vector2(viewport.size)
		section.select(true, true)
		for repeat in range(3):
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
		var actual := viewport.get_texture().get_image()
		var expected := Image.new()
		var decoded := expected.load_png_from_buffer(Marshalls.base64_to_raw(sample.png)) == OK and expected.get_size() == actual.get_size()
		_check(decoded, "Original section-border raster has matching dimensions")
		if decoded:
			var result := Raster.compare(actual, expected)
			var entry := {"size": sample.size, "pixels": result.pixels, "maximum": result.maximum}
			_check(result.pixels == 0, "Original section border size=%s pixels=%d maximum=%f" % [sample.size, result.pixels, result.maximum])
			if not output.is_empty():
				Raster.diagnostic(actual).save_png(output + "/native_%d.png" % index)
				expected.save_png(output + "/source_%d.png" % index)
			if probe:
				var dash := DashProbe.new()
				dash.size = Vector2(viewport.size)
				var color: Array = geometry.borderColor
				dash.color = Color(color[0], color[1], color[2], color[3])
				dash.dash = float(capture.programs[0].runs[0].length)
				section.layer.content.add_child(dash)
				for repeat in range(3):
					await get_tree().process_frame
					await RenderingServer.frame_post_draw
				var candidate := viewport.get_texture().get_image()
				var comparison := Raster.compare(candidate, expected)
				entry.candidatePixels = comparison.pixels
				entry.candidateMaximum = comparison.maximum
				print("NATIVE_DASH_CANDIDATE size=", sample.size, " pixels=", comparison.pixels, " maximum=", comparison.maximum)
				if not output.is_empty():
					Raster.diagnostic(candidate).save_png(output + "/candidate_%d.png" % index)
			report.append(entry)
		viewport.free()
	if not output.is_empty():
		var file := FileAccess.open(output + "/report.json", FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report, "  "))
			file.close()
