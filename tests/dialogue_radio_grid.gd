extends "res://tests/run.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/dialogue_radio_grid.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(DisplayServer.get_name() != "headless", "Radio grid requires a real display driver")
	_check(capture.get("formatVersion") == 1 and capture.get("programs") is Array and capture.programs.size() == 48,
		"Capture original radio grids with one or two visible portraits")
	if failures == 0:
		for path: String in capture.source.inputs:
			var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(text.sha256_text() == capture.source.inputs[path], "Current radio grid capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original radio grid input: " + path)
	if failures == 0:
		await _programs(capture.programs)
	print("DIALOGUE_RADIO_GRID assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _rect(values: Array) -> Rect2:
	return Rect2(values[0], values[1], values[2], values[3])

func _programs(programs: Array) -> void:
	var viewport := SubViewport.new()
	viewport.disable_3d = true
	viewport.size = Vector2i(360, 640)
	add_child(viewport)
	var view := CampaignDialogue.new()
	view.clock_msec = func(): return 0.0
	viewport.add_child(view)
	view.radio({"title": "", "note": "", "lines": [{"ch": "t06", "t": "One"}, {"ch": "s01", "t": "Two"}]})
	for i in range(4):
		await get_tree().process_frame
	var row := view.radio_row
	var left := view.portraits[0]
	var right := view.portraits[1]
	var existing_text := row.get_child(1) as Control
	existing_text.hide()
	row.get_parent().remove_child(row)
	viewport.add_child(row)
	var text := Control.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(text)
	row.move_child(text, 1)
	for sample: Dictionary in programs:
		viewport.size = Vector2i(int(sample.viewport[0]), int(sample.viewport[1]))
		left.custom_minimum_size = Vector2(float(sample.avatar), float(sample.avatar))
		right.custom_minimum_size = Vector2(float(sample.avatar), float(sample.avatar))
		right.visible = bool(sample.hasRight)
		text.custom_minimum_size = Vector2(0, float(sample.textHeight))
		row.size = Vector2(float(sample.rowWidth), 80)
		for i in range(4):
			await get_tree().process_frame
		_check(Rect2(left.position, left.size).is_equal_approx(_rect(sample.left)), "Original left portrait grid rectangle")
		_check(Rect2(text.position, text.size).is_equal_approx(_rect(sample.text)),
			"Original text grid rectangle with right=" + str(sample.hasRight) + " actual=" + str(Rect2(text.position, text.size)) + " expected=" + str(_rect(sample.text)))
		if sample.hasRight:
			_check(Rect2(right.position, right.size).is_equal_approx(_rect(sample.right)), "Original right portrait grid rectangle")
	view.clear()
	row.free()
	view.radio({"title": "", "note": "", "lines": [{"ch": "t06", "t": "One"}]})
	for i in range(5):
		await get_tree().process_frame
	var single := view.radio_row
	var single_text := single.get_child(1) as Control
	var vacant := single.get_node_or_null("AbsentPortraitColumn") as Control
	_check(not view.portraits[1].visible and vacant != null and vacant.visible, "A real single-speaker radio keeps its empty third grid column")
	_check(absf(single.size.x - single_text.position.x - single_text.size.x - float(single.get_theme_constant("separation"))) < .000001,
		"A real single-speaker radio keeps the source trailing grid gap")
	view.clear()
	viewport.free()
