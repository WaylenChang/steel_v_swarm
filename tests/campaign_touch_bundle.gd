extends "res://tests/run.gd"

const ProbeView = preload("res://tests/campaign_chapter_status.gd").ProbeView

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/campaign_touch_bundle.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(DisplayServer.get_name() != "headless", "Campaign touch event comparison requires a real display driver")
	_check(capture.get("formatVersion") == 1 and capture.get("programs") is Array and capture.programs.size() == 6,
		"Capture original Chromium touch event programs")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Current touch capture: " + path)
	for path: String in capture.source.sourceInputs:
		_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original cinematic touch input: " + path)
	if failures == 0:
		await _check_programs(capture.programs)
	print("CAMPAIGN_TOUCH_BUNDLE assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_programs(programs: Array) -> void:
	for program: Dictionary in programs:
		var clock := {"now": 1000.0}
		var view := ProbeView.new()
		view.clock_msec = func(): return clock.now
		add_child(view)
		view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		view.size = Vector2(1024, 768)
		view.play([Content.campaign.prologue[0]], "Continue")
		view.set_process(false)
		await get_tree().process_frame
		view.scroll.scroll_vertical = int(view.scroll.get_v_scroll_bar().max_value)
		await get_tree().process_frame
		var button_point := view.finish_button.get_global_rect().get_center()
		_check(view._finish_target(button_point), "Visible finish button has an input origin: " + program.name)
		for frame: Dictionary in program.frames:
			clock.now = float(frame.time)
			for original: Dictionary in frame.events:
				if original.type not in ["touchstart", "touchend", "touchcancel"]:
					continue
				for identifier: Variant in original.changed:
					var touch := InputEventScreenTouch.new()
					touch.index = int(identifier)
					touch.position = button_point if original.target == "prologueFinishBtn" else Vector2(4, 4)
					touch.pressed = original.type == "touchstart"
					touch.canceled = original.type == "touchcancel"
					view._input(touch)
			_check(view.hold_indicator.active == bool(frame.holding), "Original hold ownership: " + program.name)
			_check(view.last_tap == float(frame.lastTap), "Original touch-end tap time: " + program.name)
			_check(view.closing == not frame.skips.is_empty(), "Original ready skip decision: " + program.name)
		view.dispose()
		view.free()
