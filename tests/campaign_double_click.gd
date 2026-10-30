extends "res://tests/run.gd"

const ProbeView = preload("res://tests/campaign_chapter_status.gd").ProbeView

class ReentrantHold extends CampaignHold:
	var callback := Callable()
	func cancel() -> void:
		super.cancel()
		if callback.is_valid():
			var action := callback
			callback = Callable()
			action.call()

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/campaign_double_click.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(DisplayServer.get_name() != "headless", "Cinematic double click requires a real display driver")
	_check(capture.get("formatVersion") == 1 and capture.get("programs") is Array and capture.programs.size() == 4,
		"Capture original cinematic double-click timing")
	if failures == 0:
		for path: String in capture.source.inputs:
			var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(text.sha256_text() == capture.source.inputs[path], "Current double-click capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original cinematic input: " + path)
	if failures == 0:
		await _check_programs(capture.programs)
		await _check_replacement()
	print("CAMPAIGN_DOUBLE_CLICK assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _mouse(pressed: bool, double_click: bool = false, button: MouseButton = MOUSE_BUTTON_LEFT, mask: int = -1) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = Vector2(4, 4)
	event.button_index = button
	event.button_mask = (MOUSE_BUTTON_MASK_LEFT if pressed else 0) if mask < 0 else mask
	event.pressed = pressed
	event.double_click = double_click
	return event

func _check_programs(programs: Array) -> void:
	for program: Dictionary in programs:
		var clock := {"now": 1000.0}
		var view := ProbeView.new()
		view.clock_msec = func(): return clock.now
		add_child(view)
		view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		view.size = Vector2(320, 240)
		view.play([Content.campaign.prologue[0]] if program.ready else Content.campaign.prologue, "Continue")
		view.set_process(false)
		await get_tree().process_frame
		var mask := 0
		for frame: Dictionary in program.frames:
			var wheel: bool = frame.action == "wheel"
			var pressed: bool = frame.action != "up"
			var button := MOUSE_BUTTON_WHEEL_DOWN if wheel else MOUSE_BUTTON_LEFT if frame.button == "left" else MOUSE_BUTTON_RIGHT
			if not wheel:
				var flag := MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
				mask = (mask | flag) if pressed else (mask & ~flag)
			view._input(_mouse(pressed, pressed and int(frame.clickCount) == 2, button, mask))
			_check(view.closing == (int(frame.finished) > 0), "Original double-click finish timing")
			_check(view.buffer_warning_timers.size() == int(frame.warnings), "Original double-click warning timing")
			_check(view.hold_indicator.active == bool(frame.holding), "Original double-click pointer lifetime")
			clock.now += 100.0
		view.dispose()
		view.free()

func _check_replacement() -> void:
	var view := ProbeView.new()
	add_child(view)
	view.play(Content.campaign.prologue, "Continue")
	view.set_process(false)
	await get_tree().process_frame
	view._input(_mouse(true))
	view._input(_mouse(false))
	view._input(_mouse(true, true))
	view.play([Content.campaign.prologue[0]], "Continue")
	view.set_process(false)
	view._input(_mouse(false))
	_check(view.playing and not view.closing, "A retired mouse press cannot skip its replacement")
	view.dispose()
	view.free()
	view = ProbeView.new()
	add_child(view)
	var old_hold: Control = view.hold_indicator
	view.presentation_group.remove_child(old_hold)
	old_hold.free()
	var hold := ReentrantHold.new()
	view.presentation_group.add_child(hold)
	view.hold_indicator = hold
	view.play([Content.campaign.prologue[0]], "Continue")
	view.set_process(false)
	view._input(_mouse(true))
	view._input(_mouse(false))
	view._input(_mouse(true, true))
	var replacing_view := view
	hold.callback = func(): replacing_view.play([Content.campaign.prologue[1]], "Continue")
	view._input(_mouse(false))
	_check(view.playing and not view.closing and view.scenes[0].id == Content.campaign.prologue[1].id,
		"Hold cancellation cannot deliver an old double click into a replacement")
	view.dispose()
	view.free()
	view = ProbeView.new()
	add_child(view)
	view.play([Content.campaign.prologue[0]], "Continue")
	view.set_process(false)
	view.finishing.connect(func(): view.play([Content.campaign.prologue[1]], "Continue"), CONNECT_ONE_SHOT)
	view._input(_mouse(true))
	view._input(_mouse(false))
	view._input(_mouse(true, true))
	view._input(_mouse(false))
	_check(view.playing and not view.closing and not view.mouse_double_pending
		and view.scenes[0].id == Content.campaign.prologue[1].id,
		"A double-click finish callback cannot overwrite a replacement cinematic")
	view.dispose()
	view.free()
