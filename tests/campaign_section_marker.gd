extends "res://tests/run.gd"

class ProbeView extends CampaignCinematic:
	func _make_art_layer() -> Control:
		var layer := CampaignArtLayer.new()
		layer.texture_provider = func(_path: String, _mipmaps: bool): return null
		return layer

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/campaign_section_marker.json")
	var data: Dictionary = Content.read_json("res://data/campaign_section_marker.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(capture.get("formatVersion") == 1 and capture.get("programs") is Array and capture.programs.size() == 3,
		"Capture original prologue and chapter section markers")
	_check(data == {"formatVersion": capture.get("formatVersion"), "source": capture.get("source"), "rules": capture.get("rules")},
		"Native section marker resource retains original prefix and gap")
	if failures == 0:
		for path: String in capture.source.inputs:
			var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(text.sha256_text() == capture.source.inputs[path], "Current section marker capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original section marker input: " + path)
	if failures == 0:
		await _check_programs(capture.programs, data.rules)
	print("CAMPAIGN_SECTION_MARKER assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_programs(programs: Array, rules: Dictionary) -> void:
	var view := ProbeView.new()
	add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(640, 360)
	for program: Dictionary in programs:
		var sequence: Array = Content.campaign.prologue.duplicate() if program.kind == "prologue" else Content.campaign.scenes.ch1[String(program.kind).to_upper()]
		view.play(sequence, "Continue")
		view.set_process(false)
		await get_tree().process_frame
		_check(view.sections.size() == program.markers.size(), "Original section marker count for " + String(program.kind))
		for index in range(mini(view.sections.size(), program.markers.size())):
			var section: Control = view.sections[index]
			var marker: Dictionary = program.markers[index]
			var row: Variant = section.get("marker")
			_check(row is HBoxContainer and row.get_child_count() == 2, "Original section marker retains separate fields")
			if row is HBoxContainer and row.get_child_count() == 2:
				var badge := row.get_child(0) as Label
				var title := row.get_child(1) as Label
				_check(badge != null and title != null and badge.text == marker.badge and title.text == marker.title
					and row.get_theme_constant("separation") == int(rules.gap) and sequence[index].id == marker.id,
					"Original section badge, title prefix and gap for " + String(marker.id))
		for dimensions in [Vector2(320, 568), Vector2(568, 320)]:
			view.size = dimensions
			view._layout()
			await get_tree().process_frame
			await get_tree().process_frame
			var row := view.sections[0].get("marker") as HBoxContainer
			if row != null and row.get_child_count() == 2:
				var bounds := row.get_global_rect()
				var badge := (row.get_child(0) as Control).get_global_rect()
				var title := (row.get_child(1) as Control).get_global_rect()
				_check(bounds.encloses(badge) and bounds.encloses(title) and not badge.intersects(title),
					"Section marker remains readable within its row at " + str(dimensions))
	view.dispose()
	view.free()
