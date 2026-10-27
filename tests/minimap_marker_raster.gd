extends "res://tests/run.gd"

const Raster = preload("res://tests/raster_compare.gd")
const MapView = preload("res://scripts/minimap.gd")

var painter: Control
var map_view: Control
var commands: Array = []
var rect_antialias := true

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/minimap_marker_raster.json")
	_check(DisplayServer.get_name() != "headless", "Minimap marker raster requires a real renderer")
	_check(capture.get("formatVersion") == 1 and capture.get("cases") is Array and capture.cases.size() == 12,
		"Capture original minimap marker rasters")
	if failures > 0:
		_finish_marker()
		return
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Minimap marker capture input is current: " + path)
	for path: String in capture.source.sourceInputs:
		_check(provenance.get("inputs", {}).get(path) == capture.source.sourceInputs[path], "Minimap marker source identity: " + path)
	if failures > 0:
		_finish_marker()
		return
	await _check_rasters(capture)
	_finish_marker()

func _check_rasters(capture: Dictionary) -> void:
	var viewport := SubViewport.new()
	viewport.disable_3d = true
	var samples := 0
	var supersample := 1
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--msaa2d="):
			samples = int(argument.trim_prefix("--msaa2d="))
		elif argument.begins_with("--supersample="):
			supersample = int(argument.trim_prefix("--supersample="))
		elif argument == "--rect-no-aa":
			rect_antialias = false
	if supersample not in [1, 2, 4, 8] or samples not in [0, 2, 4, 8]:
		_check(false, "Unsupported controlled antialiasing factor")
		viewport.free()
		return
	match samples:
		2: viewport.msaa_2d = Viewport.MSAA_2X
		4: viewport.msaa_2d = Viewport.MSAA_4X
		8: viewport.msaa_2d = Viewport.MSAA_8X
	viewport.size = Vector2i(capture.size[0], capture.size[1]) * supersample
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var background := ColorRect.new()
	background.size = Vector2(viewport.size)
	background.color = Color8(capture.background[0], capture.background[1], capture.background[2])
	viewport.add_child(background)
	painter = Control.new()
	painter.size = Vector2(capture.size[0], capture.size[1])
	painter.scale = Vector2.ONE * supersample
	painter.draw.connect(_draw_commands)
	viewport.add_child(painter)
	map_view = MapView.new()
	map_view.canvas = painter
	var directory := "res://artifacts/terra/minimap-markers/msaa%d-ss%d%s" % [samples, supersample, "" if rect_antialias else "-rect-no-aa"]
	DirAccess.make_dir_recursive_absolute(directory)
	var report: Array = []
	await get_tree().process_frame
	for sample: Dictionary in capture.cases:
		failure_scope = "minimap_marker_" + String(sample.name)
		commands.clear()
		commands.append_array(_commands(sample))
		painter.queue_redraw()
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		var actual := viewport.get_texture().get_image()
		var expected := Image.new()
		var error := expected.load_png_from_buffer(Marshalls.base64_to_raw(sample.png))
		_check(actual != null and error == OK, "Load the original and native marker raster")
		if actual == null or error != OK:
			continue
		if supersample > 1:
			actual.resize(int(capture.size[0]), int(capture.size[1]), Image.INTERPOLATE_LANCZOS)
		actual.convert(Image.FORMAT_RGBA8)
		expected.convert(Image.FORMAT_RGBA8)
		actual.save_png(directory + "/" + sample.name + "-native.png")
		expected.save_png(directory + "/" + sample.name + "-source.png")
		var result: Dictionary = Raster.compare(actual, expected, 4.0 / 255.0)
		var bytes := _byte_comparison(actual, expected)
		report.append({"name": sample.name, "pixels": result.pixels, "maximum": result.maximum,
			"bytePixels": bytes.pixels, "byteMaximum": bytes.maximum})
		_check(int(result.pixels) == 0, "Original marker raster: " + str(result))
	var file := FileAccess.open(directory + "/report.json", FileAccess.WRITE)
	_check(file != null, "Retain source/native minimap marker differences")
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	map_view.free()
	viewport.free()

func _commands(sample: Dictionary) -> Array:
	var rows: Array = []
	for row: Dictionary in sample.rows:
		rows.append({"kind": row.kind, "side": row.side, "hero": row.hero, "self": row.isSelf,
			"neutral": row.neutral, "point": Vector2(row.point[0], row.point[1])})
	var known: Array = []
	for bunker: Dictionary in sample.bunkers:
		known.append({"side": bunker.side, "point": Vector2(bunker.x, bunker.z)})
	var own: Variant = Vector2(sample.own[0], sample.own[1]) if sample.own is Array else null
	return MinimapMarkerState.commands(rows, sample.viewer, known, own, sample.yaw)

func _draw_commands() -> void:
	for command: Dictionary in commands:
		if not rect_antialias and command.shape == "rect":
			painter.draw_set_transform(Vector2(command.position[0], command.position[1]), float(command.rotation))
			var colour := Color(command.colour[0], command.colour[1], command.colour[2], command.colour[3])
			var width := float(command.width) if command.width != null else -1.0
			painter.draw_rect(Rect2(command.rect[0], command.rect[1], command.rect[2], command.rect[3]), colour, command.fill, width, false)
		else:
			map_view._draw_marker(command)
	painter.draw_set_transform(Vector2.ZERO)

func _byte_comparison(actual: Image, expected: Image) -> Dictionary:
	var a := actual.get_data()
	var b := expected.get_data()
	var count := 0
	var maximum := 0
	for offset in range(0, a.size(), 4):
		var delta := 0
		for channel in 4:
			delta = maxi(delta, absi(int(a[offset + channel]) - int(b[offset + channel])))
		maximum = maxi(maximum, delta)
		if delta > 4:
			count += 1
	return {"pixels": count, "maximum": maximum}

func _finish_marker() -> void:
	print("MINIMAP_MARKER_RASTER assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
