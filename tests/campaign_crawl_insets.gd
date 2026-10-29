extends "res://tests/run.gd"

class FakeLayer extends Control:
	var scene: Dictionary = {}
	var last_pose: Dictionary = {}
	func layout_art(_size: Vector2) -> void:
		pass
	func select(_value: bool) -> void:
		pass
	func set_pose(value: Dictionary) -> void:
		last_pose = value.duplicate()
	func cancel() -> void:
		pass

class ProbeView extends CampaignCinematic:
	func _make_art_layer() -> Control:
		return FakeLayer.new()

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/campaign_crawl_insets.json")
	var data: Dictionary = Content.read_json("res://data/campaign_crawl_insets.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(capture.get("formatVersion") == 1 and capture.get("programs") is Array and capture.programs.size() == 3,
		"Capture original responsive crawl insets")
	_check(data == {"formatVersion": capture.get("formatVersion"), "source": capture.get("source"), "rules": capture.get("rules")},
		"Native crawl inset resource retains original padding")
	if failures == 0:
		for path: String in capture.source.inputs:
			var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(text.sha256_text() == capture.source.inputs[path], "Current crawl inset capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original crawl inset input: " + path)
	if failures == 0:
		await _check_programs(capture.programs)
		await _check_gui_scroll()
	print("CAMPAIGN_CRAWL_INSETS assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_programs(programs: Array) -> void:
	var view := ProbeView.new()
	add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(640, 360)
	view.play(Content.campaign.prologue.slice(0, 3), "Continue")
	view.set_process(false)
	await get_tree().process_frame
	var margin: Variant = view.get("crawl_margin")
	_check(margin is MarginContainer, "Native crawl has a padded content container")
	if not margin is MarginContainer:
		view.dispose()
		view.free()
		return
	view.scroll.get_parent().remove_child(view.scroll)
	view.presentation_group.add_child(view.scroll)
	view.scroll.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.scroll.position = Vector2.ZERO
	view.scroll.size = Vector2(320, 100)
	for child in view.column.get_children():
		view.column.remove_child(child)
		child.queue_free()
	view.sections.clear()
	view.column.add_theme_constant_override("separation", int(programs[0].sectionGap))
	for height in [200, 160, 220]:
		var section := Control.new()
		section.custom_minimum_size.y = height
		view.column.add_child(section)
		view.sections.append(section)
	view.column.add_child(Control.new())
	for program: Dictionary in programs:
		view.size = Vector2(program.size[0], program.size[1])
		view._layout()
		view.scroll.size = Vector2(program.viewport[0], program.viewport[1])
		await get_tree().process_frame
		await get_tree().process_frame
		failure_scope = "crawl_insets_" + str(program.size)
		for side in ["top", "right", "bottom", "left"]:
			_check(margin.get_theme_constant("margin_" + side) == int(program.insets[side]), "Original crawl " + side + " padding")
		for index in range(view.sections.size()):
			_near(view.sections[index].position.y + view.column.position.y, program.sections[index].top, "Original section offset includes crawl padding")
			_near(view.sections[index].size.y, program.sections[index].height, "Original controlled section height")
		_near(view.scroll.get_v_scroll_bar().max_value, program.scrollHeight, "Original padded crawl scroll height")
		view.active = 0
		for frame: Dictionary in program.frames:
			view.scroll.scroll_vertical = int(frame.requested)
			view._update_scene()
			_check(view.scroll.scroll_vertical == int(frame.scroll) and view.active == int(frame.index), "Original padded scroll and focus selection")
			var positions: Array = []
			for section: Control in view.sections:
				positions.append({"top": section.position.y + view.crawl_top, "height": section.size.y})
			var focus := CampaignRules.focus_section(view.scroll.scroll_vertical, view.scroll.size.y, positions, view.active)
			_near(float(focus.progress), float(frame.progress), "Original padded focus progress")
			var layer: FakeLayer = view.art_layers[view.active]
			var pose := CampaignRules.camera_pose(view.scenes[view.active].camera, float(frame.progress), view.size.x >= view.size.y)
			_check(not layer.last_pose.is_empty() and not pose.is_empty(), "Original padded focus reaches the camera")
			if not layer.last_pose.is_empty() and not pose.is_empty():
				for key in ["scale", "x", "y"]:
					var digits := 3 if key == "scale" else 2
					_check(CssDecimal.fixed(float(layer.last_pose[key]), digits) == CssDecimal.fixed(float(pose[key]), digits),
						"Original serialized camera target from padded focus: " + key)
		view.play(Content.campaign.prologue.slice(0, 3), "Continue", 1)
		view.set_process(false)
		_check(view.scroll.scroll_vertical == int(program.jump.initial.scroll) and view.active == int(program.jump.initial.index),
			"Initial middle-chapter selection precedes the deferred padded jump")
		for child in view.column.get_children():
			view.column.remove_child(child)
			child.queue_free()
		view.sections.clear()
		for index in range(program.sections.size()):
			var section := Control.new()
			section.custom_minimum_size.y = float(program.sections[index].height)
			view.column.add_child(section)
			section.position.y = float(program.sections[index].top) - float(program.insets.top)
			section.size.y = float(program.sections[index].height)
			view.sections.append(section)
		view.column.add_child(Control.new())
		await get_tree().process_frame
		_check(view.scroll.scroll_vertical == int(program.jump.after.scroll) and view.active == int(program.jump.after.index),
			"Deferred middle-chapter jump includes source crawl padding")
	view.dispose()
	view.free()

func _check_gui_scroll() -> void:
	var view := ProbeView.new()
	var clock := {"now": 2000.0}
	view.clock_msec = func(): return clock.now
	add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(640, 360)
	view.play(Content.campaign.prologue.slice(0, 3), "Continue")
	view.set_process(false)
	for index in range(3):
		await get_tree().process_frame
	var point := view.scroll.get_global_rect().get_center()
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_WHEEL_DOWN
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	_check(view.paused_until == clock.now + float(Content.campaign.presentation.crawl.pause) * 1000,
		"Wheel input reaches the crawl viewport through its padded content")
	clock.now = 3000
	var touch := InputEventScreenTouch.new()
	touch.index = 7
	touch.position = point
	touch.pressed = true
	Input.parse_input_event(touch)
	await get_tree().process_frame
	_check(view.paused_until == clock.now + float(Content.campaign.presentation.crawl.pause) * 1000,
		"Touch input reaches the crawl viewport through its padded content")
	touch = InputEventScreenTouch.new()
	touch.index = 7
	touch.position = point
	touch.pressed = false
	Input.parse_input_event(touch)
	view.dispose()
	view.free()
