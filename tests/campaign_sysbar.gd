extends "res://tests/run.gd"

const Raster = preload("res://tests/raster_compare.gd")

class BarProbe extends CampaignCinematic:
	var fixed_bar := false
	func _layout_hud(safe: Rect2, landscape: bool) -> void:
		if not fixed_bar:
			super._layout_hud(safe, landscape)

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/campaign_sysbar.json")
	var data: Dictionary = Content.read_json("res://data/campaign_sysbar.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	var evidence := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence-dir="):
			evidence = argument.trim_prefix("--evidence-dir=")
	if not evidence.is_empty():
		var directory := ProjectSettings.globalize_path(evidence)
		_check(not DirAccess.dir_exists_absolute(directory), "Preserve existing system bar evidence")
		if not DirAccess.dir_exists_absolute(directory):
			_check(DirAccess.make_dir_recursive_absolute(directory) == OK, "Create system bar evidence directory")
	_check(DisplayServer.get_name() != "headless", "System bar raster requires a real driver")
	_check(data == {"formatVersion": capture.get("formatVersion"), "source": capture.get("source"), "rules": capture.get("rules")},
		"System bar resource retains original browser styling")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Current system bar capture: " + path)
	for path: String in capture.source.sourceInputs:
		_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original system bar input: " + path)
	if failures == 0:
		await _check_rasters(capture.cases, evidence)
	print("CAMPAIGN_SYSBAR assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_rasters(cases: Array, evidence: String) -> void:
	for sample: Dictionary in cases:
		var stage := SubViewport.new()
		stage.disable_3d = true
		stage.size = Vector2i(sample.size[0], sample.size[1])
		stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(stage)
		var ground := ColorRect.new()
		ground.color = Color8(66, 100, 130)
		ground.size = Vector2(stage.size)
		stage.add_child(ground)
		var view := BarProbe.new()
		stage.add_child(view)
		view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		view.size = Vector2(stage.size)
		view.show()
		view.shade.hide()
		view.art_host.hide()
		view.card.hide()
		view.caption.hide()
		view.buffer_status.hide()
		view.hold_indicator.hide()
		view.system_bar_content.hide()
		view.fixed_bar = true
		view.system_bar.position = Vector2.ZERO
		view.system_bar.size = Vector2(stage.size)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		_check(view.system_bar.position == Vector2.ZERO and view.system_bar.size == Vector2(stage.size),
			"The isolated native system bar retains the captured raster geometry")
		var expected := Image.new()
		_check(expected.load_png_from_buffer(Marshalls.base64_to_raw(sample.png)) == OK, "Decode original system bar raster")
		var actual := stage.get_texture().get_image()
		var result := Raster.compare(actual, expected)
		if not evidence.is_empty():
			_check(actual.save_png(evidence.path_join("native_%d.png" % int(sample.size[0]))) == OK, "Save native system bar evidence")
			_check(expected.save_png(evidence.path_join("source_%d.png" % int(sample.size[0]))) == OK, "Save original system bar evidence")
		_check(result.pixels == 0, "Original system bar pixels at %s: mismatches=%d maximum=%f" % [sample.size, result.pixels, result.maximum])
		stage.free()
