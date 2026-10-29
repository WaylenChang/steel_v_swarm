extends "res://tests/run.gd"

const Helpers = preload("res://tests/campaign_crawl_insets.gd")

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/campaign_finish_button.json")
	var data: Dictionary = Content.read_json("res://data/campaign_finish_button.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(DisplayServer.get_name() != "headless", "Finish-button content requires a real display driver")
	_check(capture.get("formatVersion") == 1 and capture.get("programs") is Array and capture.programs.size() == 9,
		"Capture original cinematic finish-button geometry")
	_check(data == {"formatVersion": capture.get("formatVersion"), "source": capture.get("source"), "rules": capture.get("rules")},
		"Native finish-button resource retains original CSS precedence")
	if failures == 0:
		for path: String in capture.source.inputs:
			var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(text.sha256_text() == capture.source.inputs[path], "Current finish-button capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original finish-button input: " + path)
	if failures == 0:
		await _check_programs(capture.programs, data.rules)
	print("CAMPAIGN_FINISH_BUTTON assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_programs(programs: Array, rules: Dictionary) -> void:
	var view := Helpers.ProbeView.new()
	add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(640, 360)
	view.play(Content.campaign.prologue.slice(0, 1), "Continue")
	view.set_process(false)
	await get_tree().process_frame
	var button := view.finish_button
	button.get_parent().remove_child(button)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(300, 100)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.add_child(button)
	button.text = ""
	button.position = Vector2.ZERO
	_check(button.get_theme_font_size("font_size") == int(rules.fontSize), "Original finish-button computed font size")
	_check(rules.cursor == "pointer" and button.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND,
		"Original finish-button pointer cursor")
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := button.get_theme_stylebox(state)
		_check(style != null, "Finish button has style for " + state)
		if style != null:
			for side in [SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM, SIDE_LEFT]:
				var key: String = ["left", "top", "right", "bottom"][side]
				_near(style.get_content_margin(side), float(rules.padding[key]) + float(rules.border[key]),
					"Original finish-button content inset " + state + ":" + key)
	for sample: Dictionary in programs:
		var icon := Image.create(int(sample.contentSize[0]), int(sample.contentSize[1]), false, Image.FORMAT_RGBA8)
		icon.fill(Color.MAGENTA)
		button.icon = ImageTexture.create_from_image(icon)
		button.reset_size()
		for repeat in range(3):
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
		failure_scope = "finish_button_" + str(sample.size) + "_" + str(sample.contentSize)
		_near(button.size.x, sample.button[0], "Original finish-button width with controlled content")
		_near(button.size.y, sample.button[1], "Original finish-button height with controlled content")
		var pixels := viewport.get_texture().get_image()
		var minimum := Vector2i(pixels.get_width(), pixels.get_height())
		var maximum := Vector2i(-1, -1)
		for y in range(pixels.get_height()):
			for x in range(pixels.get_width()):
				var color := pixels.get_pixel(x, y)
				if color.r > .9 and color.g < .1 and color.b > .9 and color.a > .9:
					minimum = Vector2i(mini(minimum.x, x), mini(minimum.y, y))
					maximum = Vector2i(maxi(maximum.x, x), maxi(maximum.y, y))
		var actual := Rect2i(minimum, maximum - minimum + Vector2i.ONE)
		var expected := Rect2i(int(sample.content[0]), int(sample.content[1]), int(sample.content[2]), int(sample.content[3]))
		_check(actual == expected, "Original finish-button content box: actual=" + str(actual) + " expected=" + str(expected))
	view.dispose()
	view.free()
	viewport.free()
