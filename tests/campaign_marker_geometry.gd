extends "res://tests/run.gd"

const Helpers = preload("res://tests/campaign_crawl_insets.gd")

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/campaign_marker_geometry.json")
	var data: Dictionary = Content.read_json("res://data/campaign_marker_geometry.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(capture.get("formatVersion") == 1 and capture.get("programs") is Array and capture.programs.size() == 3,
		"Capture original section marker geometry")
	_check(data == {"formatVersion": capture.get("formatVersion"), "source": capture.get("source"), "rules": capture.get("rules")},
		"Native marker geometry resource retains original CSS")
	if failures == 0:
		for path: String in capture.source.inputs:
			var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(text.sha256_text() == capture.source.inputs[path], "Current marker geometry capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original marker geometry input: " + path)
	if failures == 0:
		await _check_programs(capture.programs, data.rules)
	print("CAMPAIGN_MARKER_GEOMETRY assertions=", assertions, " failures=", failures)
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
		for child in section.marker.get_children():
			section.marker.remove_child(child)
			child.queue_free()
		var marker_content := Control.new()
		marker_content.custom_minimum_size = Vector2(10, 20)
		section.marker.add_child(marker_content)
		for child in section.paragraphs.get_children():
			section.paragraphs.remove_child(child)
			child.queue_free()
		var paragraph := Control.new()
		paragraph.custom_minimum_size.y = 30 + index * 20
		section.paragraphs.add_child(paragraph)
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
		failure_scope = "marker_geometry_" + str(program.size)
		for index in range(view.sections.size()):
			var section = view.sections[index]
			var panel: Variant = section.get("marker_panel")
			_check(panel is PanelContainer, "Section marker has a bordered panel")
			if panel is PanelContainer:
				var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
				_check(style != null and style.border_width_bottom == int(rules.borderWidth)
					and style.content_margin_bottom == float(rules.bottomPadding) + float(rules.borderWidth),
					"Original marker bottom padding and border")
				if style != null:
					_check(style.border_width_top == 0 and style.border_width_left == 0 and style.border_width_right == 0
						and style.bg_color.a == 0, "The marker has only its source bottom border")
					var color := style.border_color
					var channels := [color.r, color.g, color.b, color.a]
					for channel in range(4):
						_near(channels[channel], rules.borderColor[channel], "Original marker border color")
				_near(panel.size.y, program.sections[index].markerHeight, "Original marker height")
			_near(section.paragraphs.position.y, program.sections[index].paragraphsTop, "Original paragraph starts after marker margin")
			_near(section.position.y, program.sections[index].top, "Original section top")
			_near(section.size.y, program.sections[index].height, "Original section height with marker geometry")
		_near(ending.position.y, program.endTop, "Original ending follows marker and section geometry")
		_near(view.scroll.get_v_scroll_bar().max_value, program.scrollHeight, "Original marker geometry determines scroll height")
		view.active = 0
		for frame: Dictionary in program.frames:
			view.scroll.scroll_vertical = int(frame.requested)
			view._update_scene()
			_check(view.scroll.scroll_vertical == int(frame.scroll) and view.active == int(frame.index), "Original marker geometry determines focus selection")
			var positions: Array = []
			for section: Control in view.sections:
				positions.append({"top": section.position.y, "height": section.size.y})
			var focus := CampaignRules.focus_section(view.scroll.scroll_vertical, view.scroll.size.y, positions, view.active)
			_near(float(focus.progress), float(frame.progress), "Original marker geometry determines focus progress")
		var empty = view.sections[2]
		for child in empty.paragraphs.get_children():
			empty.paragraphs.remove_child(child)
			child.queue_free()
		for repeat in range(4):
			await get_tree().process_frame
		_near(empty.size.y, program.emptySection.height, "An empty section retains original marker and bottom spacing")
		_near(empty.paragraphs.position.y, program.emptySection.paragraphsTop, "An empty paragraph group retains original marker margin")
		var restored := Control.new()
		restored.custom_minimum_size.y = 70
		empty.paragraphs.add_child(restored)
		for repeat in range(4):
			await get_tree().process_frame
	view.dispose()
	view.free()
