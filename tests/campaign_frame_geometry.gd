extends "res://tests/run.gd"

const Raster = preload("res://tests/raster_compare.gd")
const OpaqueWitness = preload("res://tests/opaque_canvas_witness.gd")

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/campaign_frame_geometry.json")
	var data: Dictionary = Content.read_json("res://data/campaign_frame_geometry.json")
	var evidence_dir := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence-dir="):
			evidence_dir = argument.trim_prefix("--evidence-dir=")
	if not evidence_dir.is_empty():
		var absolute_dir := ProjectSettings.globalize_path(evidence_dir)
		_check(not DirAccess.dir_exists_absolute(absolute_dir), "Preserve existing cinematic frame evidence")
		if not DirAccess.dir_exists_absolute(absolute_dir):
			_check(DirAccess.make_dir_recursive_absolute(absolute_dir) == OK, "Create cinematic frame evidence directory")
	_check(DisplayServer.get_name() != "headless", "Cinematic frame pixels require a real display driver")
	_check(capture.get("formatVersion") == 1 and capture.get("cases") is Array and capture.cases.size() == 17,
		"Capture original cinematic foreground frame geometry")
	_check(data == {"formatVersion": capture.get("formatVersion"), "source": capture.get("source"), "rules": capture.get("rules")},
		"Runtime foreground data retains the original browser rules")
	if failures == 0:
		var provenance: Dictionary = Content.read_json("res://data/provenance.json")
		for path: String in capture.source.inputs:
			var source := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(source.sha256_text() == capture.source.inputs[path], "Current cinematic frame capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.get("inputs", {}).get(path) == capture.source.sourceInputs[path], "Original cinematic frame source identity: " + path)
		_check(float(Content.campaign.presentation.art.inset) == float(capture.rules.inset), "Original foreground inset is imported")
	if failures == 0:
		await _check_cases(capture.cases, evidence_dir)
	print("CAMPAIGN_FRAME_GEOMETRY assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_cases(cases: Array, evidence_dir: String) -> void:
	var stage := SubViewport.new()
	stage.disable_3d = true
	stage.world_2d = World2D.new()
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(stage)
	var backdrop := ColorRect.new()
	backdrop.color = Color("#05070a")
	stage.add_child(backdrop)
	var layer := CampaignArtLayer.new()
	stage.add_child(layer)
	layer.background.hide()
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color8(48, 144, 208))
	layer.image.texture = ImageTexture.create_from_image(image)
	layer.image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.selected = true
	layer.opacity = 1
	layer.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for sample: Dictionary in cases:
		var size := Vector2(float(sample.size[0]), float(sample.size[1]))
		stage.size = Vector2i(size)
		backdrop.size = size
		layer.pose = {"scale": 1.0, "x": 0.0, "y": 0.0}
		layer.layout_art(size)
		var expected_frame := Rect2(float(sample.frame[0]), float(sample.frame[1]), float(sample.frame[2]), float(sample.frame[3]))
		var expected_image := Rect2(float(sample.image[0]), float(sample.image[1]), float(sample.image[2]), float(sample.image[3]))
		var actual_frame := layer.frame.get_global_rect()
		var actual_image := layer.image.get_global_rect()
		failure_scope = "campaign_frame_" + str(sample.size)
		_check(actual_frame == expected_frame, "Original foreground clipping frame at " + str(sample.size)
			+ " source=" + str(expected_frame) + " native=" + str(actual_frame))
		_check(actual_image == expected_image, "Original foreground image box at " + str(sample.size)
			+ " source=" + str(expected_image) + " native=" + str(actual_image))
		if sample.has("png"):
			for index in range(3):
				await get_tree().process_frame
				await RenderingServer.frame_post_draw
			var actual := stage.get_texture().get_image()
			var expected := Image.new()
			var decoded := expected.load_png_from_buffer(Marshalls.base64_to_raw(sample.png)) == OK and expected.get_size() == actual.get_size()
			_check(decoded, "Original controlled frame raster has matching dimensions")
			if decoded:
				var result := Raster.compare(actual, expected)
				if result.pixels > 0:
					print("CAMPAIGN_FRAME_WITNESS ", JSON.stringify({"size": sample.size,
						"pixels": result.pixels, "maximum": result.maximum,
						"opaqueBytes": OpaqueWitness.compare(actual, expected)}))
				if not evidence_dir.is_empty():
					var suffix := "%dx%d" % [int(size.x), int(size.y)]
					_check(actual.save_png(evidence_dir.path_join("native-" + suffix + ".png")) == OK, "Retain native frame evidence")
					_check(expected.save_png(evidence_dir.path_join("source-" + suffix + ".png")) == OK, "Retain original frame evidence")
				_check(result.pixels == 0, "Original controlled frame pixels at " + str(sample.size)
					+ " pixels=" + str(result.pixels) + " maximum=" + str(result.maximum))
		for pose: Dictionary in sample.poses:
			layer.pose = pose.target.duplicate()
			layer._apply_pose()
			var transform := layer.image.get_global_transform()
			var corner := transform * Vector2.ZERO
			var opposite := transform * layer.image.size
			var actual_pose := Rect2(corner, opposite - corner)
			var expected_pose := Rect2(float(pose.image[0]), float(pose.image[1]), float(pose.image[2]), float(pose.image[3]))
			_check(actual_pose.position.distance_to(expected_pose.position) < .001 and actual_pose.size.distance_to(expected_pose.size) < .001,
				"Original transformed image bounds at " + str(sample.size) + " progress=" + str(pose.progress)
				+ " source=" + str(expected_pose) + " native=" + str(actual_pose))
	layer.cancel()
	stage.free()
