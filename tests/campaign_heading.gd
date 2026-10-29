extends "res://tests/run.gd"

class ProbeView extends CampaignCinematic:
	func _make_art_layer() -> Control:
		var layer := CampaignArtLayer.new()
		layer.texture_provider = func(_path: String, _mipmaps: bool): return null
		return layer

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/campaign_heading.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(capture.get("formatVersion") == 1 and capture.get("frames") is Array and capture.frames.size() == 7,
		"Capture original cinematic heading updates")
	if failures == 0:
		for path: String in capture.source.inputs:
			var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(text.sha256_text() == capture.source.inputs[path], "Current cinematic heading capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original cinematic heading input: " + path)
		_check(capture.scenes.size() == Content.campaign.prologue.size(), "Original cinematic scene count is imported")
		for index in range(mini(capture.scenes.size(), Content.campaign.prologue.size())):
			var scene: Dictionary = Content.campaign.prologue[index]
			var source: Dictionary = capture.scenes[index]
			_check(scene.id == source.id and scene.tag == source.tag and scene.badge == source.badge and scene.title == source.title,
				"Original cinematic heading content is imported")
	if failures == 0:
		await _check_updates(capture.frames)
	print("CAMPAIGN_HEADING assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_updates(frames: Array) -> void:
	var view := ProbeView.new()
	add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(640, 360)
	view.play(Content.campaign.prologue.duplicate(), "Continue")
	view.set_process(false)
	await get_tree().process_frame
	for frame: Dictionary in frames:
		view._set_scene(int(frame.index))
		var badge: Variant = view.get("badge_label")
		_check(view.active == int(frame.active) and view.tag.text == frame.tag and view.heading.text == frame.title
			and badge is Label and badge.text == frame.badge,
			"Original cinematic badge, title and date update independently at index " + str(frame.index))
	for dimensions in [Vector2(320, 568), Vector2(568, 320)]:
		view.size = dimensions
		view._layout()
		await get_tree().process_frame
		await get_tree().process_frame
		var badge := view.badge_label.get_global_rect()
		var title := view.heading.get_global_rect()
		var card := view.card.get_global_rect()
		_check(view.badge_label.get_parent() == view.heading.get_parent() and not badge.intersects(title),
			"Badge and title retain separate horizontal fields at " + str(dimensions))
		_check(card.encloses(badge) and card.encloses(title) and view.scroll.get_global_rect().has_area(),
			"Heading and crawl stay within the captured narrative card at " + str(dimensions))
	view.dispose()
	view.free()
