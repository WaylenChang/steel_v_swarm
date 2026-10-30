extends "res://tests/run.gd"

class ProbeView extends CampaignCinematic:
	func _make_art_layer() -> Control:
		var layer := CampaignArtLayer.new()
		layer.texture_provider = func(_path: String, _mipmaps: bool): return null
		return layer

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/campaign_header.json")
	var data: Dictionary = Content.read_json("res://data/campaign_header.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(capture.get("formatVersion") == 1 and capture.get("cases") is Array and capture.cases.size() == 8,
		"Capture original responsive cinematic header")
	_check(data == {"formatVersion": capture.get("formatVersion"), "source": capture.get("source"), "rules": capture.get("rules")},
		"Native cinematic header resource retains original CSS")
	if failures == 0:
		for path: String in capture.source.inputs:
			var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(text.sha256_text() == capture.source.inputs[path], "Current cinematic header capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original cinematic header input: " + path)
	if failures == 0:
		await _check_cases(capture.cases)
	print("CAMPAIGN_HEADER assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_cases(cases: Array) -> void:
	var view := ProbeView.new()
	add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(640, 360)
	view.play(Content.campaign.prologue.slice(0, 2), "Continue")
	view.set_process(false)
	await get_tree().process_frame
	var panel: Variant = view.get("header_panel")
	_check(panel is PanelContainer, "Native cinematic header has its own padded panel")
	if not panel is PanelContainer:
		view.dispose()
		view.free()
		return
	for sample: Dictionary in cases:
		view.size = Vector2(sample.size[0], sample.size[1])
		view._layout()
		await get_tree().process_frame
		await get_tree().process_frame
		_check(view.badge_label.get_theme_font_size("font_size") == int(round(float(sample.fontSizes.badge))),
			"Badge font size follows the source viewport rule at native integer precision")
		_check(view.heading.get_theme_font_size("font_size") == int(round(float(sample.fontSizes.title))),
			"Title font size follows the source viewport rule at native integer precision")
		_check(view.badge_label.get_theme_color("font_color").is_equal_approx(_color(sample.colours.badge))
			and view.heading.get_theme_color("font_color").is_equal_approx(_color(sample.colours.title)),
			"Header badge and title retain their distinct source colors")
		for section: Control in view.sections:
			var marker: HBoxContainer = section.marker
			_check((marker.get_child(0) as Label).get_theme_font_size("font_size") == int(round(float(sample.fontSizes.section)))
				and (marker.get_child(1) as Label).get_theme_font_size("font_size") == int(round(float(sample.fontSizes.sectionTitle))),
				"Each section marker follows the source viewport rule at native integer precision")
			_check((marker.get_child(0) as Label).get_theme_color("font_color").is_equal_approx(_color(sample.colours.sectionBadge))
				and (marker.get_child(1) as Label).get_theme_color("font_color").is_equal_approx(_color(sample.colours.sectionTitle)),
				"Each section marker retains distinct source badge and title colors")
		var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
		_check(style != null, "Native cinematic header uses a flat source-color panel")
		if style == null:
			continue
		var border := int(sample.borderWidth)
		_check(style.border_width_bottom == border and style.border_width_top == 0 and style.border_width_left == 0 and style.border_width_right == 0,
			"Original header has only its bottom border")
		for side in ["top", "right", "bottom", "left"]:
			var expected := float(sample.padding[side]) + (float(border) if side == "bottom" else 0.0)
			_near(float(style.get("content_margin_" + side)), expected, "Original header content margin: " + side)
		var background := style.bg_color
		var line := style.border_color
		var background_values := [background.r, background.g, background.b, background.a]
		var line_values := [line.r, line.g, line.b, line.a]
		for channel in range(4):
			_near(background_values[channel], sample.background[channel], "Original header background channel")
			_near(line_values[channel], sample.border[channel], "Original header border channel")
		var header := view.badge_label.get_parent() as Control
		_check(header != null and header.get_parent() == panel and view.heading.get_parent() == header,
			"Original badge and title remain inside the header panel")
		if header != null:
			_near(header.position.x, sample.padding.left, "Header row begins after source left padding")
			_near(header.position.y, sample.padding.top, "Header row begins after source top padding")
			_near(panel.size.x - header.position.x - header.size.x, sample.padding.right, "Header row retains source right padding")
		_check(view.scroll.get_global_rect().has_area() and view.card.get_global_rect().encloses(view.scroll.get_global_rect()),
			"The padded header leaves a usable crawl viewport")
	view.dispose()
	view.free()

func _color(channels: Array) -> Color:
	return Color(channels[0], channels[1], channels[2], channels[3])
