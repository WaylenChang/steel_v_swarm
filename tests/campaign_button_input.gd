extends "res://tests/run.gd"

const ProbeView = preload("res://tests/campaign_chapter_status.gd").ProbeView

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/campaign_button_input.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(DisplayServer.get_name() != "headless", "Campaign button input requires a real display driver")
	_check(capture.get("formatVersion") == 1 and capture.get("programs") is Array and capture.programs.size() == 10,
		"Capture original Chromium button event programs")
	_check(bool(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch")),
		"Native button activation requires the project touch-to-mouse setting")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Current button input capture: " + path)
	for path: String in capture.source.sourceInputs:
		_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original cinematic button source: " + path)
	if failures == 0:
		await _check_programs(capture.programs)
		await _check_long_scroll()
	print("CAMPAIGN_BUTTON_INPUT assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_programs(programs: Array) -> void:
	for program: Dictionary in programs:
		var clock := {"now": 1000.0}
		var view := ProbeView.new()
		view.clock_msec = func(): return clock.now
		add_child(view)
		view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		view.size = Vector2(1024, 768)
		view.play([Content.campaign.prologue[0]] if program.ready else Content.campaign.prologue, "Continue")
		view.set_process(false)
		await get_tree().process_frame
		await get_tree().process_frame
		view.scroll.scroll_vertical = int(view.scroll.get_v_scroll_bar().max_value)
		await get_tree().process_frame
		var button_point := view.finish_button.get_global_rect().get_center()
		var outside_point := view.scroll.get_global_rect().position + Vector2(10, 10)
		_check(view._finish_target(button_point), "Button is within the scroll viewport: " + program.name)
		var finishes := {"count": 0}
		view.finishing.connect(func(): finishes.count += 1)
		var previous := button_point
		for frame: Dictionary in program.frames:
			clock.now = float(frame.time)
			var operation := str(frame.operation)
			var point := button_point if operation.ends_with("button") else outside_point
			if program.kind == "mouse":
				if operation.begins_with("move"):
					var motion := InputEventMouseMotion.new()
					motion.position = point
					motion.global_position = point
					motion.button_mask = MOUSE_BUTTON_MASK_LEFT
					get_viewport().push_input(motion, true)
				else:
					var mouse := InputEventMouseButton.new()
					mouse.position = point
					mouse.global_position = point
					mouse.button_index = MOUSE_BUTTON_LEFT
					mouse.pressed = operation.begins_with("down")
					mouse.button_mask = MOUSE_BUTTON_MASK_LEFT if mouse.pressed else 0
					get_viewport().push_input(mouse, true)
			elif operation.begins_with("move"):
				var drag := InputEventScreenDrag.new()
				drag.index = 0
				drag.position = point
				drag.relative = point - previous
				Input.parse_input_event(drag)
			else:
				var touch := InputEventScreenTouch.new()
				touch.index = 0
				touch.position = point
				touch.pressed = operation.begins_with("down")
				touch.canceled = operation.begins_with("cancel")
				Input.parse_input_event(touch)
			previous = point
			await get_tree().process_frame
			if program.kind == "touch" and not DisplayServer.is_touchscreen_available() \
					and frame.events.any(func(event): return event.type == "pointercancel"):
				# ScrollContainer emits these itself when a real touchscreen starts panning.
				view.scroll.propagate_notification(Control.NOTIFICATION_SCROLL_BEGIN)
				view.scroll.scroll_started.emit()
			_check(finishes.count == int(frame.finishes), "Original button completion: " + program.name + " " + operation)
			_check(view.buffer_warning_timers.size() == int(frame.warnings), "Original button bypasses buffering: " + program.name)
			_check(view.hold_indicator.active == bool(frame.holding), "Original button hold exclusion: " + program.name)
			_check(view.last_tap == float(frame.lastTap), "Original button touch exclusion: " + program.name)
		view.dispose()
		view.free()

func _check_long_scroll() -> void:
	var clock := {"now": 1000.0}
	var view := ProbeView.new()
	view.clock_msec = func(): return clock.now
	add_child(view)
	view.play(Content.campaign.prologue, "Continue")
	view.set_process(false)
	await get_tree().process_frame
	var touch := InputEventScreenTouch.new()
	touch.index = 9
	touch.position = Vector2(4, 4)
	touch.pressed = true
	view._input(touch)
	_check(view.hold_indicator.active, "The original pointer starts long-press feedback")
	view.scroll.scroll_started.emit()
	clock.now += float(Content.campaign.presentation.skip.hold) * 1000 + 1
	view._process(0)
	_check(not view.hold_indicator.active and view.held_at < 0 and view.buffer_warning_timers.is_empty() and not view.closing,
		"A continued scroll cannot trigger a retired long press or buffering warning")
	touch.pressed = false
	view._input(touch)
	_check(view.last_tap == clock.now and view.finish_touches.is_empty(), "Scroll cancellation retains the later touch-end clock")
	view.dispose()
	view.free()
