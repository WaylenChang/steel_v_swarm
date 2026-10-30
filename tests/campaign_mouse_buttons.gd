extends "res://tests/run.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/campaign_mouse_buttons.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(DisplayServer.get_name() != "headless", "Cinematic mouse input requires a real display driver")
	_check(capture.get("formatVersion") == 1 and capture.get("programs") is Array and capture.programs.size() == 8,
		"Capture original mouse pointer lifetimes")
	if failures == 0:
		for path: String in capture.source.inputs:
			var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(text.sha256_text() == capture.source.inputs[path], "Current mouse pointer capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original cinematic input: " + path)
	if failures == 0:
		await _check_programs(capture.programs)
	print("CAMPAIGN_MOUSE_BUTTONS assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_programs(programs: Array) -> void:
	var buttons := {"left": MOUSE_BUTTON_LEFT, "right": MOUSE_BUTTON_RIGHT, "middle": MOUSE_BUTTON_MIDDLE,
		"back": MOUSE_BUTTON_XBUTTON1, "forward": MOUSE_BUTTON_XBUTTON2}
	var masks := {"left": MOUSE_BUTTON_MASK_LEFT, "right": MOUSE_BUTTON_MASK_RIGHT, "middle": MOUSE_BUTTON_MASK_MIDDLE,
		"back": 1 << (MOUSE_BUTTON_XBUTTON1 - 1), "forward": 1 << (MOUSE_BUTTON_XBUTTON2 - 1)}
	for program: Dictionary in programs:
		var clock := {"now": 1000.0}
		var view = preload("res://tests/campaign_lifecycle.gd").LifecycleView.new()
		view.clock_msec = func(): return clock.now
		add_child(view)
		view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		view.size = Vector2(320, 240)
		view.play([Content.campaign.prologue[0]], "Continue")
		view.set_process(false)
		await get_tree().process_frame
		var mask := 0
		var initial: float = clock.now
		for frame: Dictionary in program.frames:
			var wheel: bool = frame.action == "wheel"
			var down: bool = frame.action != "up"
			if not wheel:
				var flag: int = masks[frame.button]
				mask = (mask | flag) if down else (mask & ~flag)
			var event := InputEventMouseButton.new()
			event.position = Vector2(4, 4)
			event.button_index = MOUSE_BUTTON_WHEEL_DOWN if wheel else buttons[frame.button]
			event.button_mask = mask
			event.pressed = down
			view._input(event)
			_check((view.held_at >= 0) == bool(frame.holding), "Original mouse hold lifetime: " + String(program.name))
			_check(view.hold_indicator.active == bool(frame.holding), "Original mouse hold feedback: " + String(program.name))
			if frame.holding:
				_check(view.held_at == initial, "Additional buttons do not restart the original mouse hold")
			clock.now += 100.0
		view.dispose()
		view.free()
