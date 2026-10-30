extends "res://tests/run.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/dialogue_radio_text.json")
	var data: Dictionary = Content.read_json("res://data/dialogue_radio_text.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(DisplayServer.get_name() != "headless", "Radio text requires a real display driver")
	_check(capture.get("formatVersion") == 1 and capture.get("programs") is Array and capture.programs.size() == 4,
		"Capture original responsive radio text programs")
	_check(data == {"formatVersion": capture.get("formatVersion"), "source": capture.get("source"), "rules": capture.get("rules")},
		"Radio text rules retain original computed CSS")
	if failures == 0:
		for path: String in capture.source.inputs:
			var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(text.sha256_text() == capture.source.inputs[path], "Current radio text capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original radio text input: " + path)
	if failures == 0:
		await _programs(capture.programs, data.rules)
	print("DIALOGUE_RADIO_TEXT assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _color(values: Array) -> Color:
	return Color(values[0], values[1], values[2], values[3])

func _programs(programs: Array, rules: Dictionary) -> void:
	var viewport := SubViewport.new()
	viewport.disable_3d = true
	viewport.size = Vector2i(320, 568)
	add_child(viewport)
	var view := CampaignDialogue.new()
	view.clock_msec = func(): return 0.0
	viewport.add_child(view)
	_check(view.radio_layout_rules.mobileMaxWidth == rules.mobileMaxWidth, "Radio text and layout share the original breakpoint")
	for program: Dictionary in programs:
		viewport.size = Vector2i(int(program.viewport[0]), int(program.viewport[1]))
		var lines: Array = []
		for frame: Dictionary in program.frames:
			lines.append({"ch": frame.speaker, "t": frame.input})
		view.radio({"title": "", "note": "", "lines": lines})
		for i in range(5):
			await get_tree().process_frame
		var text_column := view.radio_row.get_child(1) as VBoxContainer
		_check(text_column != null and text_column.get_theme_constant("separation") == int(rules.gap),
			"Original speaker-to-line gap")
		for i in range(program.frames.size()):
			var frame: Dictionary = program.frames[i]
			_check(view.speaker.text == frame.name and view.line_label.get_parsed_text() == frame.text,
				"Original speaker and literal dialogue text")
			_check(view.speaker.get_theme_font_size("font_size") == int(frame.speakerFont), "Original speaker font size")
			_check(view.line_label.get_theme_font_size("normal_font_size") == int(frame.lineFont), "Original responsive dialogue font size")
			_check(view.speaker.get_theme_color("font_color").is_equal_approx(_color(frame.speakerColor)), "Original speaker faction color")
			_check(view.line_label.get_theme_color("default_color").is_equal_approx(_color(frame.lineColor)), "Original dialogue text color")
			if i + 1 < program.frames.size():
				view._step()
	var previous_pause := get_tree().paused
	var previous_scale := Engine.time_scale
	get_tree().paused = true
	Engine.time_scale = 0.0
	viewport.size = Vector2i(720, 900)
	for i in range(5):
		await get_tree().process_frame
	_check(view.line_label.get_theme_font_size("normal_font_size") == int(rules.mobileLineFont), "A paused dialogue updates across the mobile breakpoint")
	viewport.size = Vector2i(721, 900)
	for i in range(5):
		await get_tree().process_frame
	_check(view.line_label.get_theme_font_size("normal_font_size") == int(rules.desktopLineFont), "A paused dialogue restores desktop text after resizing")
	get_tree().paused = previous_pause
	Engine.time_scale = previous_scale
	var replacement := {"title": "Replacement", "note": "", "lines": [{"ch": "s01", "t": "new"}]}
	var replaced := {"done": false}
	view.line_label.theme_changed.connect(func():
		replaced.done = true
		view.radio(replacement), CONNECT_ONE_SHOT)
	view.radio_layout_mode = ""
	view._apply_radio_layout()
	_check(replaced.done and view.lines == replacement.lines and view.bar != null,
		"A font-change callback can replace the radio without an old layout continuation")
	for i in range(5):
		await get_tree().process_frame
	var cancelled := {"done": false}
	view.bar.resized.connect(func():
		cancelled.done = true
		view.clear(), CONNECT_ONE_SHOT)
	viewport.size = Vector2i(600, 900)
	for i in range(5):
		await get_tree().process_frame
	_check(cancelled.done and view.bar == null and view.timers.is_empty(),
		"A resize callback can cancel the radio without an old layout continuation")
	view.clear()
	viewport.free()
