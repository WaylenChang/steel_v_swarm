extends "res://tests/run.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/dialogue_radio_note.json")
	var data: Dictionary = Content.read_json("res://data/dialogue_radio_note.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(DisplayServer.get_name() != "headless", "Radio note layout requires a real display driver")
	_check(capture.get("formatVersion") == 1 and capture.get("programs") is Array and capture.programs.size() == 4,
		"Capture original radio title and note programs")
	_check(data == {"formatVersion": capture.get("formatVersion"), "source": capture.get("source"), "rules": capture.get("rules")},
		"Radio note rules retain original computed CSS")
	if failures == 0:
		for path: String in capture.source.inputs:
			var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(text.sha256_text() == capture.source.inputs[path], "Current radio note capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original radio note input: " + path)
	if failures == 0:
		await _programs(capture.programs, data.rules)
	print("DIALOGUE_RADIO_NOTE assertions=", assertions, " failures=", failures)
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
	for program: Dictionary in programs:
		var lines: Array = []
		for frame: Dictionary in program.frames:
			lines.append({"ch": frame.speaker, "t": "line"})
		view.radio({"title": program.title, "note": program.note, "lines": lines})
		for i in range(3):
			await get_tree().process_frame
		var row := view.bar.get_child(0).get_child(0) as HBoxContainer
		_check(row != null and row.get_child_count() == 2, "Title and description remain independent controls")
		if row == null or row.get_child_count() != 2:
			continue
		var title := row.get_child(0) as Label
		var note := row.get_child(1) as Label
		_check(title != null and note != null, "Both original note fields render as plain labels")
		if title == null or note == null:
			continue
		_check(row.get_theme_constant("separation") == int(rules.gap), "Original title and description gap")
		_check(title.get_theme_font_size("font_size") == int(rules.fontSize) and note.get_theme_font_size("font_size") == int(rules.fontSize),
			"Both fields retain the source font size")
		for i in range(program.frames.size()):
			var frame: Dictionary = program.frames[i]
			_check(title.text == frame.title and note.text == frame.note and title.text + note.text == frame.combined,
				"Original escaped text is displayed without a fabricated separator")
			_check(title.get_theme_color("font_color").is_equal_approx(_color(frame.titleColor)), "Title follows the current speaker faction")
			_check(note.get_theme_color("font_color").is_equal_approx(_color(frame.noteColor)), "Description retains the original neutral color")
			var border := view.bar.get_theme_stylebox("panel") as StyleBoxFlat
			_check(border.border_color.is_equal_approx(_color(frame.titleColor)), "Radio side border follows the current speaker faction")
			if i + 1 < program.frames.size():
				view._step()
	var long_text := "很長的標題與說明".repeat(30)
	view.radio({"title": long_text, "note": long_text, "lines": [{"ch": "t06", "t": "line"}]})
	for i in range(8):
		await get_tree().process_frame
	var expected_width := floorf(viewport.size.x * float(view.radio_layout_rules.viewportRatio) * float(view.radio_layout_rules.layoutUnits)) / float(view.radio_layout_rules.layoutUnits)
	_check(absf(view.bar.size.x - expected_width) < .000001, "Long title and description do not expand the source radio width")
	_check(view.radio_note_title.size.x > 0 and view.radio_note_title.get_line_count() > 1
		and view.radio_note_title.size.y >= view.radio_note_title.get_minimum_size().y,
		"Long titles retain visible wrapped lines")
	view.clear()
	viewport.free()
