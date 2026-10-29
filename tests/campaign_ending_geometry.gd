extends "res://tests/run.gd"

const Helpers = preload("res://tests/campaign_crawl_insets.gd")

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/campaign_ending_geometry.json")
	var data: Dictionary = Content.read_json("res://data/campaign_ending_geometry.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(capture.get("formatVersion") == 1 and capture.get("programs") is Array and capture.programs.size() == 3,
		"Capture original cinematic ending geometry")
	_check(data == {"formatVersion": capture.get("formatVersion"), "source": capture.get("source"), "rules": capture.get("rules")},
		"Native ending geometry resource retains original CSS")
	if failures == 0:
		for path: String in capture.source.inputs:
			var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(text.sha256_text() == capture.source.inputs[path], "Current ending geometry capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original ending geometry input: " + path)
	if failures == 0:
		await _check_programs(capture.programs)
	print("CAMPAIGN_ENDING_GEOMETRY assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_programs(programs: Array) -> void:
	var view := Helpers.ProbeView.new()
	add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(640, 360)
	view.play(Content.campaign.prologue.slice(0, 1), "Continue")
	view.set_process(false)
	await get_tree().process_frame
	view.scroll.get_parent().remove_child(view.scroll)
	view.presentation_group.add_child(view.scroll)
	view.scroll.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.scroll.position = Vector2.ZERO
	view.scroll.size = Vector2(320, 100)
	var section = view.sections[0]
	section.marker_panel.hide()
	for child in section.paragraphs.get_children():
		section.paragraphs.remove_child(child)
		child.queue_free()
	var paragraph := Control.new()
	paragraph.custom_minimum_size.y = float(programs[0].section.height) - float(view.section_geometry_rules.bottomPadding) - float(view.section_geometry_rules.borderWidth)
	section.paragraphs.add_child(paragraph)
	var ending: Control = view.column.get_child(view.column.get_child_count() - 1)
	view.end_divider.text = ""
	view.end_divider.custom_minimum_size.y = 20
	view.end_note.text = ""
	view.end_note.custom_minimum_size.y = 20
	view.finish_button.text = ""
	view.finish_button.custom_minimum_size = Vector2(240, 40)
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
		failure_scope = "ending_geometry_" + str(program.size)
		_near(section.position.y, program.section.top, "Original section top")
		_near(section.size.y, program.section.height, "Controlled original section height")
		_near(ending.position.y, program.endingTop, "Original ending follows section margin")
		_near(ending.size.y, program.inline.height, "Original ending includes vertical padding and gaps")
		for item in [[view.end_divider, program.inline.divider], [view.end_note, program.inline.note], [view.finish_button, program.inline.button]]:
			var node: Control = item[0]
			var expected: Dictionary = item[1]
			_near(node.get_global_rect().position.y - ending.get_global_rect().position.y, expected.top, "Original ending element top")
			_near(node.size.y, expected.height, "Controlled original ending element height")
		_near(view.scroll.get_v_scroll_bar().max_value, program.inline.scrollHeight, "Original ending geometry determines scroll height")
		view.active = 0
		for frame: Dictionary in program.frames:
			view.scroll.scroll_vertical = int(frame.requested)
			view._update_scene()
			_check(view.scroll.scroll_vertical == int(frame.scroll) and view.active == int(frame.index), "Original ending geometry determines focus selection")
			var focus := CampaignRules.focus_section(view.scroll.scroll_vertical, view.scroll.size.y,
				[{"top": section.position.y, "height": section.size.y}], view.active)
			_near(float(focus.progress), float(frame.progress), "Original ending geometry determines focus progress")
		await get_tree().process_frame
		_check(view._finish_target(view.finish_button.get_global_rect().get_center()), "Finish button remains reachable at the end of the scroll")
	view.dispose()
	view.free()
