extends "res://tests/run.gd"

const Raster = preload("res://tests/raster_compare.gd")
const Minimap = preload("res://scripts/minimap.gd")

var painter: Control
var view: Control
var font_family := ""

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/minimap_label.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(DisplayServer.get_name() != "headless", "Minimap label pixels require a real display driver")
	_check(capture.get("formatVersion") == 1 and capture.get("cases") is Array and capture.cases.size() == 6,
		"Capture original minimap label rasters")
	var evidence := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence-dir="):
			evidence = argument.trim_prefix("--evidence-dir=")
		elif argument.begins_with("--font-family="):
			font_family = argument.trim_prefix("--font-family=")
	if not evidence.is_empty():
		var directory := ProjectSettings.globalize_path(evidence)
		_check(not DirAccess.dir_exists_absolute(directory), "Preserve existing minimap label evidence")
		if not DirAccess.dir_exists_absolute(directory):
			_check(DirAccess.make_dir_recursive_absolute(directory) == OK, "Create minimap label evidence directory")
	if failures == 0:
		for path: String in capture.source.inputs:
			var source := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(source.sha256_text() == capture.source.inputs[path], "Current minimap label capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original minimap label source: " + path)
	if failures == 0:
		await _check_cases(capture, evidence)
	print("MINIMAP_LABEL assertions=", assertions, " failures=", failures)
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
	painter = Control.new()
	painter.size = Vector2(viewport.size)
	painter.draw.connect(_draw_label)
	viewport.add_child(painter)
	view = Minimap.new()
	view.canvas = painter
	if not font_family.is_empty():
		view.mode_font = SystemFont.new()
		view.mode_font.font_names = PackedStringArray([font_family])
	var report: Array = []
	for sample: Dictionary in capture.cases:
		var text := MinimapWindow.label(sample.mode == "near", float(sample.width))
		_check(text == sample.text, "Original minimap label text: " + String(sample.text))
		view.draw_frame = {"near": sample.mode == "near", "window_components": {"x0": 0.0, "x1": sample.width},
			"size": Vector2(viewport.size)}
		painter.queue_redraw()
		for index in range(2):
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
		var actual := viewport.get_texture().get_image()
		var expected := Image.new()
		var decoded := expected.load_png_from_buffer(Marshalls.base64_to_raw(sample.png)) == OK and expected.get_size() == actual.get_size()
		_check(decoded, "Original minimap label raster dimensions")
		if not decoded:
			continue
		var result := Raster.compare(actual, expected, 4.0 / 255)
		var native_width: float = view.mode_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(Content.balance.minimap.labels.fontSize)).x
		report.append({"text": text, "source_width": sample.width,
			"source_text_width": sample.textWidth, "native_text_width": native_width,
			"pixels": result.pixels, "maximum": result.maximum})
		if not evidence.is_empty():
			var suffix := str(report.size())
			_check(actual.save_png(evidence.path_join("native-" + suffix + ".png")) == OK, "Save native minimap label evidence")
			_check(expected.save_png(evidence.path_join("source-" + suffix + ".png")) == OK, "Save source minimap label evidence")
		_check(result.pixels == 0, "Original minimap label pixels: " + text + " pixels=" + str(result.pixels) + " maximum=" + str(result.maximum))
	if not evidence.is_empty():
		var file := FileAccess.open(evidence.path_join("report.json"), FileAccess.WRITE)
		_check(file != null, "Write minimap label report")
		if file != null:
			file.store_string(JSON.stringify(report, "  "))
	view.free()
	viewport.free()

func _draw_label() -> void:
	view._draw_label()
