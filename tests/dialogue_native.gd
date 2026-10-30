extends "res://tests/run.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/dialogue_native.json")
	_check(capture.get("formatVersion") == 1 and capture.get("source") is Dictionary and capture.get("programs") is Array,
		"Capture original automatic dialogue methods")
	if failures > 0:
		_finish_dialogue()
		return
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Dialogue capture input is current")
	for path: String in capture.source.sourceInputs:
		_check(provenance.get("inputs", {}).get(path) == capture.source.sourceInputs[path], "Dialogue oracle matches imported source: " + path)
	_check(Content.campaign.get("talk") == capture.get("talk"), "Imported campaign radio scenarios match original source content")
	if failures > 0:
		_finish_dialogue()
		return
	for program: Dictionary in capture.programs:
		var view := CampaignDialogue.new()
		var clock := {"now": 0.0}
		view.clock_msec = func(): return clock.now
		view.side = program.side
		view.art_mode = program.artMode
		add_child(view)
		view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		view.size = Vector2(1024, 768)
		for frame: Dictionary in program.frames:
			match frame.action:
				"radio": view.radio(frame.scene)
				"empty": view.radio({"lines": []})
				"clear": view.clear()
				"timer":
					_check(not view.timers.is_empty(), "Original dialogue timer remains scheduled before delivery")
					if not view.timers.is_empty():
						clock.now += view.timers[0].wait_time * 1000
						view.timers[0].timeout.emit()
			_compare(view, frame.state)
		view.free()
	_finish_dialogue()

func _compare(view: CampaignDialogue, expected: Dictionary) -> void:
	_check(view.at == int(expected.at) and view.total == int(expected.total), "Original automatic dialogue progress and clear/replacement state")
	_check(is_instance_valid(view.bar) == bool(expected.bar), "Original radio expiry and empty-scene behavior")
	_check(view.timers.size() == expected.timers.size(), "Old radio timers cannot survive a replacement or clear")
	for index in range(mini(view.timers.size(), expected.timers.size())):
		_near(view.timers[index].wait_time, expected.timers[index], "Original UTF-16 duration clamp and fade deadline")
	if not expected.bar or not is_instance_valid(view.bar):
		return
	_check(view.line_label.get_parsed_text() == expected.text and view.speaker.text == expected.speaker,
		"Original dialogue is rendered as plain text with the original speaker name")
	_check(view.speaker.get_theme_color("font_color").to_html(false) == Color(expected.color).to_html(false),
		"Original speaker faction and mercenary colors")
	_check((view.fade != null and view.fade.is_valid()) == bool(expected.fading), "Original radio begins fading only after the final line deadline")
	for index in range(2):
		var portrait: Dictionary = expected.portraits[index]
		_check(view.portrait_ids[index] == portrait.id and view.portraits[index].visible == bool(portrait.visible),
			"Original viewer-relative portrait assignment and one-speaker hidden endpoint")
		_check((float(view.portraits[index].get("target_opacity")) == 1) == bool(portrait.active), "Original speaker highlight endpoint and guest borrowing")
		if not String(portrait.id).is_empty():
			var texture: Texture2D = view.portraits[index].texture
			_check(texture != null and texture.resource_path == "res://" + String(portrait.src).trim_prefix("/"),
				"Native portrait binding loads the exact original character/mech asset")

func _finish_dialogue() -> void:
	print("DIALOGUE_NATIVE assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
