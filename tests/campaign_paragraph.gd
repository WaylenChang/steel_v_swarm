extends "res://tests/run.gd"

class ProbeView extends CampaignCinematic:
	func _make_art_layer() -> Control:
		var layer := CampaignArtLayer.new()
		layer.texture_provider = func(_path: String, _mipmaps: bool): return null
		return layer

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/campaign_paragraph.json")
	var data: Dictionary = Content.read_json("res://data/campaign_paragraph.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(capture.get("formatVersion") == 1 and capture.get("programs") is Array and capture.programs.size() == 3,
		"Capture original prologue and chapter paragraphs")
	_check(data == {"formatVersion": capture.get("formatVersion"), "source": capture.get("source"), "rules": capture.get("rules")},
		"Native paragraph resource retains original responsive margins")
	if failures == 0:
		for path: String in capture.source.inputs:
			var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(text.sha256_text() == capture.source.inputs[path], "Current paragraph capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original paragraph input: " + path)
	if failures == 0:
		await _check_programs(capture.programs, data.rules, capture.cases)
	print("CAMPAIGN_PARAGRAPH assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_programs(programs: Array, rules: Dictionary, cases: Array) -> void:
	var view := ProbeView.new()
	add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(640, 360)
	for program: Dictionary in programs:
		var sequence: Array = Content.campaign.prologue.duplicate() if program.kind == "prologue" else Content.campaign.scenes.ch1[String(program.kind).to_upper()]
		view.play(sequence, "Continue")
		view.set_process(false)
		await get_tree().process_frame
		_check(view.sections.size() == program.sections.size(), "Original paragraph section count for " + String(program.kind))
		for index in range(mini(view.sections.size(), program.sections.size())):
			var section: Control = view.sections[index]
			var source: Dictionary = program.sections[index]
			_check(sequence[index].id == source.id and sequence[index].paragraphs == source.paragraphs,
				"Original paragraph content is imported for " + String(source.id))
			var paragraphs: Variant = section.get("paragraphs")
			_check(paragraphs is VBoxContainer and paragraphs.get_child_count() == source.paragraphs.size(),
				"Original paragraphs remain distinct for " + String(source.id))
			if paragraphs is VBoxContainer and paragraphs.get_child_count() == source.paragraphs.size():
				for paragraph in range(source.paragraphs.size()):
					var label := paragraphs.get_child(paragraph) as RichTextLabel
					_check(label != null and label.text == source.paragraphs[paragraph], "Original paragraph text remains unchanged")
		for sample: Dictionary in cases:
			var dimensions := Vector2(sample.size[0], sample.size[1])
			view.size = dimensions
			view._layout()
			await get_tree().process_frame
			await get_tree().process_frame
			var paragraphs: Variant = view.sections[0].get("paragraphs")
			var expected := int(rules.landscapeGap) if dimensions.x > dimensions.y else int(rules.portraitGap)
			_check(paragraphs is VBoxContainer and paragraphs.get_theme_constant("separation") == expected,
				"Original paragraph gap at " + str(dimensions))
			for section: Control in view.sections:
				var section_paragraphs: VBoxContainer = section.paragraphs
				for text: RichTextLabel in section_paragraphs.get_children():
					var color: Array = rules.colour
					_check(text.get_theme_font_size("normal_font_size") == int(round(float(sample.fontSize)))
						and text.get_theme_color("default_color").is_equal_approx(Color(color[0], color[1], color[2], color[3])),
						"Every source paragraph follows the viewport font size and color at native precision")
			if paragraphs is VBoxContainer:
				var content := view.sections[0].get("content") as Control
				_check(content != null and Rect2(Vector2.ZERO, content.size).encloses(paragraphs.get_rect()),
					"The isolated section surface contains every paragraph at " + str(dimensions))
				for index in range(paragraphs.get_child_count()):
					var label := paragraphs.get_child(index) as Control
					var separated := label != null and label.size.y > 0
					if separated and index > 0:
						var previous := paragraphs.get_child(index - 1) as Control
						separated = label.position.y >= previous.position.y + previous.size.y + expected
					_check(separated, "Paragraph controls remain visible and separated at " + str(dimensions))
	view.dispose()
	view.free()
