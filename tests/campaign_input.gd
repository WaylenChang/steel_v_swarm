extends "res://tests/run.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/campaign_input.json")
	_check(capture.get("formatVersion") == 1 and capture.get("source") is Dictionary and capture.get("programs") is Array,
		"Capture original cinematic input handlers")
	if not failures.is_empty():
		_finish_input()
		return
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Cinematic input capture is current")
	for path: String in capture.source.sourceInputs:
		_check(provenance.get("inputs", {}).get(path) == capture.source.sourceInputs[path], "Cinematic input oracle matches imported source")
	if not failures.is_empty():
		_finish_input()
		return
	for program: Dictionary in capture.programs:
		var clock := {"now": 0.0}
		var view = preload("res://tests/campaign_lifecycle.gd").LifecycleView.new()
		view.clock_msec = func(): return clock.now
		add_child(view)
		view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		view.size = Vector2(1024, 768)
		view.play([Content.campaign.prologue[0]], "Continue")
		view.set_process(false)
		await get_tree().process_frame
		var clipped_center: Vector2 = view.finish_button.get_global_rect().get_center()
		_check(not view.scroll.get_global_rect().has_point(clipped_center), "Original scene places the finish button below the initial crawl viewport")
		_check(not view._finish_target(clipped_center), "A clipped finish button cannot capture root gestures")
		view.scroll.scroll_vertical = int(view.scroll.get_v_scroll_bar().max_value)
		await get_tree().process_frame
		var button_center: Vector2 = view.finish_button.get_global_rect().get_center()
		_check(view._finish_target(button_center), "Visible finish-button geometry excludes root gestures")
		view.finish_button.hide()
		_check(not view._finish_target(button_center), "A hidden finish button cannot capture root gestures")
		view.finish_button.show()
		for frame: Dictionary in program.frames:
			var operation: Dictionary = frame.operation
			clock.now = float(operation.time)
			if operation.type == "raf":
				view._process(.016)
			else:
				var event: InputEvent
				var point: Vector2 = view.finish_button.get_global_rect().get_center() if operation.get("button", false) else Vector2(4, 4)
				match operation.type:
					"down", "up", "cancel":
						var touch := InputEventScreenTouch.new()
						touch.index = int(operation.get("id", 0))
						touch.position = point
						touch.pressed = operation.type == "down"
						touch.canceled = operation.type == "cancel"
						event = touch
					"drag":
						var drag := InputEventScreenDrag.new()
						drag.position = point
						event = drag
					"wheel", "mouse_down", "mouse_up", "double_click":
						var mouse := InputEventMouseButton.new()
						mouse.position = point
						mouse.button_index = MOUSE_BUTTON_WHEEL_DOWN if operation.type == "wheel" else MOUSE_BUTTON_LEFT
						mouse.pressed = operation.type != "mouse_up"
						mouse.double_click = operation.type == "double_click"
						event = mouse
				if event != null:
					view._input(event)
					if operation.get("scroll", false):
						view._scroll_input(event)
			_check(view.closing == bool(frame.state.closing), "Original cinematic skip/cancel/button and strict timer boundaries")
			_check((view.held_at >= 0) == bool(frame.state.holding), "Original pointer release/cancel ends the active hold")
			_check(view.hold_indicator.active == bool(frame.state.holding), "Cinematic pointer ownership starts and cancels the native hold feedback")
			_near(view.paused_until, frame.state.pausedUntil, "Only original wheel/touch-start/move events pause automatic crawl")
			_near(view.last_tap, frame.state.lastTap, "Original tap clock retains cancel/button exclusion and zero-clock behavior")
			if view.exit_tween != null and view.exit_tween.is_valid():
				view.exit_tween.pause()
		view.dispose()
		view.free()
	await _replacement_input()
	_finish_input()

func _replacement_input() -> void:
	var clock := {"now": 1000.0}
	var view = preload("res://tests/campaign_lifecycle.gd").LifecycleView.new()
	view.clock_msec = func(): return clock.now
	add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(1024, 768)
	view.play([Content.campaign.prologue[0]], "Continue")
	view.set_process(false)
	await get_tree().process_frame
	view.finishing.connect(func(): view.play([Content.campaign.prologue[1]], "Continue"), CONNECT_ONE_SHOT)
	for time in [1000.0, 1200.0]:
		clock.now = time
		for pressed in [true, false]:
			var touch := InputEventScreenTouch.new()
			touch.position = Vector2(4, 4)
			touch.pressed = pressed
			view._input(touch)
	_check(view.playing and not view.closing and view.scenes[0].id == Content.campaign.prologue[1].id,
		"A touch skip can synchronously replace the cinematic")
	_check(view.last_tap == 0 and view.held_at == -1 and view.finish_touches.is_empty(),
		"Retired touch input cannot stamp a replacement cinematic's clocks or pointer ownership")
	_check(not view.hold_indicator.active and view.hold_indicator.opacity == 0 and view.hold_indicator.opacity_transition.is_empty(),
		"Replacement cinematics release retired hold feedback and pending fades")
	view.dispose()
	view.free()

func _finish_input() -> void:
	print("CAMPAIGN_INPUT assertions=", assertions, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
