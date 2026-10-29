extends "res://tests/run.gd"

class ProbeView extends CampaignCinematic:
	func _make_art_layer() -> Control:
		var layer := CampaignArtLayer.new()
		layer.texture_provider = func(_path: String, _mipmaps: bool): return null
		return layer

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/campaign_card.json")
	var data: Dictionary = Content.read_json("res://data/campaign_card.json")
	_check(capture.get("formatVersion") == 1 and capture.get("cases") is Array and capture.cases.size() == 15,
		"Capture original cinematic narrative card geometry")
	_check(data == {"formatVersion": capture.get("formatVersion"), "source": capture.get("source"), "rules": capture.get("rules")},
		"Runtime card data retains the original browser rules")
	if failures == 0:
		var provenance: Dictionary = Content.read_json("res://data/provenance.json")
		for path: String in capture.source.inputs:
			var source := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(source.sha256_text() == capture.source.inputs[path], "Current cinematic card capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.get("inputs", {}).get(path) == capture.source.sourceInputs[path], "Original cinematic card source identity: " + path)
	if failures == 0:
		await _check_cases(capture.cases)
	print("CAMPAIGN_CARD assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_cases(cases: Array) -> void:
	var view := ProbeView.new()
	add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(1024, 768)
	view.play([Content.campaign.prologue[0]], "Continue")
	view.set_process(false)
	await get_tree().process_frame
	for sample: Dictionary in cases:
		view.size = Vector2(float(sample.size[0]), float(sample.size[1]))
		view._layout()
		await get_tree().process_frame
		var expected := Rect2(float(sample.rect[0]), float(sample.rect[1]), float(sample.rect[2]), float(sample.rect[3]))
		var actual := Rect2(view.card.position, view.card.size)
		failure_scope = "campaign_card_" + str(sample.size)
		_check(actual == expected, "Original responsive narrative card at " + str(sample.size)
			+ " source=" + str(expected) + " native=" + str(actual))
		if sample.size[0] >= 320 and sample.size[1] >= 320:
			_check(view.card_panel.size == view.card.size, "The panel fits inside the captured card bounds")
			var scroll_rect := view.scroll.get_global_rect()
			var card_rect := view.card.get_global_rect()
			_check(scroll_rect.has_area() and card_rect.encloses(scroll_rect), "The crawl viewport remains accessible within the card")
			_check(view.tag.get_parent() == view.presentation_group and view.caption.get_parent() == view.presentation_group
				and view.buffer_status.get_parent() == view.presentation_group, "HUD labels remain outside the scrollable narrative card")
			_check(view.caption.position.y + view.caption.size.y <= view.size.y and view.tag.position.y >= 0,
				"HUD labels remain within the viewport: size=" + str(view.size) + " caption=" + str(view.caption.get_rect()) + " tag=" + str(view.tag.get_rect()))
			view.scroll.scroll_vertical = int(view.scroll.get_v_scroll_bar().max_value)
			await get_tree().process_frame
			_check(view._finish_target(view.finish_button.get_global_rect().get_center()), "The crawl finish button remains reachable")
			view.scroll.scroll_vertical = 0
	view.size = Vector2(320, 568)
	view.caption.text = view.buffer_rules.pendingHint
	view.buffer_status.text = String(view.buffer_rules.warning).replace("{percent}", "42")
	view.buffer_status.show()
	view._layout()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(view.caption.get_rect().end.y <= view.size.y and view.buffer_status.get_rect().end.y <= view.caption.position.y,
		"Wrapped buffering warnings and skip hints stay visible in portrait HUD order")
	view._layout_hud(Rect2(0, 24, view.size.x, view.size.y - 40), false)
	_check(view.tag.position.y == 24 + float(view.card_rules.chrome.portrait.top)
		and view.caption.position.y + view.caption.size.y == view.size.y - 16 - float(view.card_rules.chrome.portrait.bottom),
		"HUD placement retains captured spacing around supplied safe-area insets")
	view.dispose()
	view.free()
