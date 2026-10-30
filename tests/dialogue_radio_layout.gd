extends "res://tests/run.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/dialogue_radio_layout.json")
	var data: Dictionary = Content.read_json("res://data/dialogue_radio_layout.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(DisplayServer.get_name() != "headless", "Radio layout requires a real display driver")
	_check(capture.get("formatVersion") == 1 and capture.get("programs") is Array and capture.programs.size() == 27,
		"Capture original responsive radio geometry")
	_check(data == {"formatVersion": capture.get("formatVersion"), "source": capture.get("source"), "rules": capture.get("rules")},
		"Runtime radio geometry retains original CSS")
	if failures == 0:
		for path: String in capture.source.inputs:
			var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(text.sha256_text() == capture.source.inputs[path], "Current radio layout capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original radio layout input: " + path)
	if failures == 0:
		await _geometry(capture.programs, data.rules)
	print("DIALOGUE_RADIO_LAYOUT assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _geometry(programs: Array, rules: Dictionary) -> void:
	var viewport := SubViewport.new()
	viewport.disable_3d = true
	viewport.size = Vector2i(320, 568)
	add_child(viewport)
	var view := CampaignDialogue.new()
	view.clock_msec = func(): return 0.0
	viewport.add_child(view)
	view.radio({"title": "", "note": "", "lines": [{"ch": "t06", "t": "First"}, {"ch": "s01", "t": "Second"}]})
	for i in range(4):
		await get_tree().process_frame
	_check(view.portraits.all(func(portrait: TextureRect): return portrait.size_flags_vertical == Control.SIZE_SHRINK_CENTER),
		"Real radio centers fixed-size portraits in taller rows")
	_check(view.radio_row.get_child(1).size_flags_vertical == Control.SIZE_SHRINK_CENTER,
		"Real radio centers its text in taller rows")
	view.line_label.text = "This deliberately long dialogue line exercises content-driven resizing. ".repeat(20)
	for i in range(8):
		await get_tree().process_frame
	_check(absf(view.bar.position.y + view.bar.size.y + float(rules.mobile.bottom) - view.size.y) < .000001,
		"A changing real dialogue line keeps the source bottom anchor")
	var source_width := floorf(viewport.size.x * float(rules.viewportRatio) * float(rules.layoutUnits)) / float(rules.layoutUnits)
	_check(absf(view.bar.size.x - source_width) < .000001, "A long real dialogue line retains the source responsive width")
	var column := view.bar.get_child(0) as VBoxContainer
	var live_note := column.get_child(0).get_child(1) as Label
	live_note.text = "戰場任務進度已更新，無線電記錄持續傳送。".repeat(8)
	for i in range(8):
		await get_tree().process_frame
	_check(absf(view.bar.size.x - source_width) < .000001, "A long real radio note retains the source responsive width")
	_check(live_note.get_line_count() > 1 and live_note.size.y >= live_note.get_minimum_size().y,
		"A long real radio note wraps without losing its visible lines")
	var old_note := column.get_child(0)
	column.remove_child(old_note)
	old_note.free()
	var note := Control.new()
	column.add_child(note)
	column.move_child(note, 0)
	var row := view.radio_row
	for child in row.get_children():
		child.hide()
	for program: Dictionary in programs:
		viewport.size = Vector2i(int(program.viewport[0]), int(program.viewport[1]))
		note.custom_minimum_size = Vector2(0, float(program.noteHeight))
		row.custom_minimum_size = Vector2(0, float(program.rowHeight))
		for i in range(5):
			await get_tree().process_frame
		var actual := Rect2(view.bar.position, view.bar.size)
		var expected := Rect2(program.box[0], program.box[1], program.box[2], program.box[3])
		_check(actual.is_equal_approx(expected), "Original responsive bar box: actual=" + str(actual) + " expected=" + str(expected))
		var style := view.bar.get_theme_stylebox("panel")
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			_check(absf(style.get_content_margin(side) - float(program.padding[side]) - float(program.border[side])) < .000001,
				"Original responsive content inset")
		_check(column.get_theme_constant("separation") == int(program.gap) and row.get_theme_constant("separation") == int(program.rowGap),
			"Original note and row gaps")
		for portrait in view.portraits:
			_check(portrait.custom_minimum_size == Vector2(float(program.avatar), float(program.avatar)), "Original responsive portrait size")
		_check(note.position.y == float(program.note[1]) - float(program.padding[1]) and row.position.y == float(program.row[1]) - float(program.padding[1]),
			"Original controlled content vertical flow")
	view.clear()
	viewport.free()
