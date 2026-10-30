extends "res://tests/run.gd"

const Raster = preload("res://tests/raster_compare.gd")

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/minimap_lane_raster.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(DisplayServer.get_name() != "headless", "Minimap lane pixels require a real display driver")
	_check(capture.get("formatVersion") == 1 and capture.get("cases") is Array and capture.cases.size() == 10,
		"Capture original minimap lane strokes and rasters")
	var evidence := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence-dir="):
			evidence = argument.trim_prefix("--evidence-dir=")
	if not evidence.is_empty():
		var directory := ProjectSettings.globalize_path(evidence)
		_check(not DirAccess.dir_exists_absolute(directory), "Preserve existing minimap lane evidence")
		if not DirAccess.dir_exists_absolute(directory):
			_check(DirAccess.make_dir_recursive_absolute(directory) == OK, "Create minimap lane evidence directory")
	if failures == 0:
		for path: String in capture.source.inputs:
			var source := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(source.sha256_text() == capture.source.inputs[path], "Current minimap lane capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original minimap lane source: " + path)
	if failures == 0:
		await _check_cases(capture, evidence)
	print("MINIMAP_LANE_RASTER assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_cases(capture: Dictionary, evidence: String) -> void:
	var viewport := SubViewport.new()
	viewport.disable_3d = true
	viewport.world_2d = World2D.new()
	viewport.size = Vector2i(capture.size[0], capture.size[1])
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var background := ColorRect.new()
	background.size = Vector2(viewport.size)
	background.color = Color8(capture.background[0], capture.background[1], capture.background[2])
	viewport.add_child(background)
	var lines := MinimapLanes.new()
	viewport.add_child(lines)
	var report: Array = []
	for sample: Dictionary in capture.cases:
		var groups := MinimapLaneState.groups(sample.lanes, sample.ids)
		_check(groups.size() == sample.strokes.size(), "Original lane segmentation: " + String(sample.name))
		if groups.size() != sample.strokes.size():
			continue
		_check(lines.configure(groups), "Configure native original lane groups")
		lines.update_window(Rect2(0, 0, viewport.size.x, viewport.size.y), Vector2(viewport.size))
		for index in groups.size():
			var reference: Dictionary = sample.strokes[index]
			var line: Line2D = lines.lines[index]
			var points := []
			for point: Vector2 in line.points:
				points.append([float(point.x), float(point.y)])
			var style: Dictionary = Content.balance.minimap.lanes.styles[groups[index].grade]
			_check(points == reference.points and style.dash == reference.dash,
				"Original lane points and dash sequence: " + String(sample.name))
			var expected := Color(reference.color)
			_check(absf(line.width - float(reference.width)) < .000001 and absf(line.default_color.a - float(reference.alpha)) < .000001
				and absf(line.default_color.r - expected.r) < .000001 and absf(line.default_color.g - expected.g) < .000001
				and absf(line.default_color.b - expected.b) < .000001, "Original lane color, width and alpha")
		for frame in range(2):
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
		var actual := viewport.get_texture().get_image()
		var expected := Image.new()
		var decoded := expected.load_png_from_buffer(Marshalls.base64_to_raw(sample.png)) == OK and expected.get_size() == actual.get_size()
		_check(decoded, "Original minimap lane raster dimensions")
		if not decoded:
			continue
		var result := Raster.compare(actual, expected, 4.0 / 255)
		var bytes := _opaque_difference(actual, expected)
		report.append({"name": sample.name, "pixels": result.pixels, "maximum": result.maximum, "bytes": bytes})
		if not evidence.is_empty():
			_check(actual.save_png(evidence.path_join("native-" + String(sample.name) + ".png")) == OK, "Save native lane evidence")
			_check(expected.save_png(evidence.path_join("source-" + String(sample.name) + ".png")) == OK, "Save source lane evidence")
		_check(result.pixels == 0, "Original minimap lane pixels: " + String(sample.name) + " pixels=" + str(result.pixels)
			+ " maximum=" + str(result.maximum))
	if not evidence.is_empty():
		var file := FileAccess.open(evidence.path_join("report.json"), FileAccess.WRITE)
		_check(file != null, "Write minimap lane report")
		if file != null:
			file.store_string(JSON.stringify(report, "  "))
	lines.clear()
	viewport.free()

func _opaque_difference(actual: Image, expected: Image) -> Dictionary:
	var first := {}
	var maximum := 0
	var pixels := 0
	for y in actual.get_height():
		for x in actual.get_width():
			var a := actual.get_pixel(x, y)
			var b := expected.get_pixel(x, y)
			var native := [roundi(a.r * 255), roundi(a.g * 255), roundi(a.b * 255), roundi(a.a * 255)]
			var source := [roundi(b.r * 255), roundi(b.g * 255), roundi(b.b * 255), roundi(b.a * 255)]
			if native[3] != 255 or source[3] != 255:
				return {}
			var error := maxi(absi(native[0] - source[0]), maxi(absi(native[1] - source[1]), absi(native[2] - source[2])))
			maximum = maxi(maximum, error)
			if error > 4:
				pixels += 1
				if first.is_empty():
					first = {"x": x, "y": y, "source": source, "native": native}
	return {"pixelsOverFourBytes": pixels, "maximumChannelBytes": maximum, "first": first}
