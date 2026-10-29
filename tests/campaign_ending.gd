extends "res://tests/run.gd"

const Buffer = preload("res://scripts/campaign_buffer.gd")

class ControlledBuffer extends Buffer:
	func _request(_name: String, _path: String) -> void:
		pass
	func _process(_delta: float) -> void:
		pass

class ProbeView extends CampaignCinematic:
	func _make_buffer() -> Buffer:
		return ControlledBuffer.new()
	func _make_art_layer() -> Control:
		var layer := CampaignArtLayer.new()
		layer.texture_provider = func(_path: String, _mipmaps: bool): return null
		return layer

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/campaign_ending.json")
	var data: Dictionary = Content.read_json("res://data/campaign_ending.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(capture.get("formatVersion") == 1 and capture.get("cases") is Array and capture.cases.size() == 6,
		"Capture original cinematic ending cases")
	_check(data == {"formatVersion": capture.get("formatVersion"), "source": capture.get("source"), "rules": capture.get("rules")},
		"Native cinematic ending resource retains original text")
	if failures == 0:
		for path: String in capture.source.inputs:
			var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(text.sha256_text() == capture.source.inputs[path], "Current cinematic ending capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original cinematic ending input: " + path)
	if failures == 0:
		await _check_cases(capture.cases)
	print("CAMPAIGN_ENDING assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_cases(cases: Array) -> void:
	var view := ProbeView.new()
	add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(640, 360)
	for sample: Dictionary in cases:
		var sequence: Array = Content.campaign.prologue if sample.kind == "prologue" else [Content.campaign.prologue[0]]
		var requested := "" if sample.finishText == null else String(sample.finishText)
		view.play(sequence, requested)
		view.set_process(false)
		await get_tree().process_frame
		var divider: Variant = view.get("end_divider")
		var note: Variant = view.get("end_note")
		_check(divider is Label and divider.text == sample.divider and note is Label and note.text == sample.note
			and view.finish_button.text == sample.button,
			"Original ending text and button selection for " + str(sample.kind) + " / " + str(sample.finishText))
		view.scroll.scroll_vertical = int(view.scroll.get_v_scroll_bar().max_value)
		await get_tree().process_frame
		var visible := view.scroll.get_global_rect().intersection(view.finish_button.get_global_rect())
		_check(visible.has_area() and view._finish_target(visible.get_center()), "Visible ending button stays reachable in the crawl viewport")
		if visible.has_area():
			for pressed in [true, false]:
				var click := InputEventMouseButton.new()
				click.position = visible.get_center()
				click.global_position = click.position
				click.button_index = MOUSE_BUTTON_LEFT
				click.pressed = pressed
				Input.parse_input_event(click)
				await get_tree().process_frame
			_check(view.closing, "Visible ending button receives a real GUI click")
	view.dispose()
	view.free()
