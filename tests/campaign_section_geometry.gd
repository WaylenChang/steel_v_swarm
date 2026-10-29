extends "res://tests/run.gd"

const Helpers = preload("res://tests/campaign_crawl_insets.gd")

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/campaign_section_geometry.json")
	var data: Dictionary = Content.read_json("res://data/campaign_section_geometry.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(capture.get("formatVersion") == 1 and capture.get("programs") is Array and capture.programs.size() == 3,
		"Capture original section padding and focus geometry")
	_check(data == {"formatVersion": capture.get("formatVersion"), "source": capture.get("source"), "rules": capture.get("rules")},
		"Native section geometry resource retains original CSS")
	if failures == 0:
		for path: String in capture.source.inputs:
			var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(text.sha256_text() == capture.source.inputs[path], "Current section geometry capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original section geometry input: " + path)
	if failures == 0:
		await _check_programs(capture.programs, data.rules)
	print("CAMPAIGN_SECTION_GEOMETRY assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_programs(programs: Array, rules: Dictionary) -> void:
	var view = Helpers.ProbeView.new()
	add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(640, 360)
	view.play(Content.campaign.prologue.slice(0, 3), "Continue")
	view.set_process(false)
	await get_tree().process_frame
	view.scroll.get_parent().remove_child(view.scroll)
	view.presentation_group.add_child(view.scroll)
	view.scroll.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.scroll.position = Vector2.ZERO
	view.scroll.size = Vector2(320, 100)
	for index in range(view.sections.size()):
		var section = view.sections[index]
		section.marker.hide()
		for child in section.paragraphs.get_children():
			section.paragraphs.remove_child(child)
			child.queue_free()
		var fixed := Control.new()
		fixed.custom_minimum_size.y = float(programs[0].sections[index].height) - float(rules.bottomPadding) - float(rules.borderWidth)
		section.paragraphs.add_child(fixed)
	var previous_end: Node = view.column.get_child(view.column.get_child_count() - 1)
	view.column.remove_child(previous_end)
	previous_end.queue_free()
	var ending := Control.new()
	ending.custom_minimum_size.y = 40
	view.column.add_child(ending)
	for program: Dictionary in programs:
		view.size = Vector2(program.size[0], program.size[1])
		view._layout()
		await get_tree().process_frame
		view.scroll.size = Vector2(program.viewport[0], program.viewport[1])
		for side in ["top", "right", "bottom", "left"]:
			view.crawl_margin.add_theme_constant_override("margin_" + side, 0)
		view.crawl_top = 0
		for repeat in range(4):
			await get_tree().process_frame
		failure_scope = "section_geometry_" + str(program.size)
		_check(view.column.get_theme_constant("separation") == int(rules.marginBottom), "Original section bottom margin")
		for index in range(view.sections.size()):
			_near(view.sections[index].position.y, program.sections[index].top, "Original section top")
			_near(view.sections[index].size.y, program.sections[index].height, "Original section height includes bottom padding and border")
		_near(ending.position.y, program.endTop, "Original ending follows the final section margin")
		_near(view.scroll.get_v_scroll_bar().max_value, program.scrollHeight, "Original section geometry determines scroll height")
		view.active = 0
		for frame: Dictionary in program.frames:
			view.scroll.scroll_vertical = int(frame.requested)
			view._update_scene()
			_check(view.scroll.scroll_vertical == int(frame.scroll) and view.active == int(frame.index), "Original section geometry determines focus selection")
			var positions: Array = []
			for section: Control in view.sections:
				positions.append({"top": section.position.y, "height": section.size.y})
			var focus := CampaignRules.focus_section(view.scroll.scroll_vertical, view.scroll.size.y, positions, view.active)
			_near(float(focus.progress), float(frame.progress), "Original section geometry determines focus progress")
	view.dispose()
	view.free()
