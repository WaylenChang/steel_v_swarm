extends "res://tests/run.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/campaign_hold_warning.json")
	_check(capture.get("formatVersion") == 1 and capture.get("frames") is Array and capture.frames.size() == 11,
		"Capture original buffered long-press cancellation and warning")
	if failures == 0:
		var provenance: Dictionary = Content.read_json("res://data/provenance.json")
		for path: String in capture.source.inputs:
			var source := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(source.sha256_text() == capture.source.inputs[path], "Current campaign hold warning capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.get("inputs", {}).get(path) == capture.source.sourceInputs[path], "Original campaign hold warning source identity: " + path)
	if failures == 0:
		_check_frames(capture.frames)
	print("CAMPAIGN_HOLD_WARNING assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_frames(frames: Array) -> void:
	var clock := {"now": 1000.0}
	var view = preload("res://tests/campaign_buffer.gd").BufferView.new()
	view.clock_msec = func(): return clock.now
	add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(1024, 768)
	view.play(Content.campaign.prologue, "Continue")
	view.set_process(false)
	var buffer: Variant = view.buffer_loader
	_check(buffer != null and not buffer.complete, "Hold warning starts with an incomplete prologue buffer")
	if buffer == null:
		view.dispose()
		view.free()
		return
	buffer.percent = 37
	view._render_buffer()
	for frame: Dictionary in frames:
		var operation: Dictionary = frame.operation
		clock.now = float(operation.time)
		match str(operation.type):
			"down", "up":
				var mouse := InputEventMouseButton.new()
				mouse.button_index = MOUSE_BUTTON_LEFT
				mouse.position = Vector2(100, 100)
				mouse.pressed = operation.type == "down"
				view._input(mouse)
			"frame": view._process(0.0)
			"ready":
				buffer.complete = true
				buffer.percent = 100
				buffer.progress.emit(buffer.total, buffer.total, 100, "models", true)
		failure_scope = "campaign_hold_warning_" + str(operation.type) + "_" + str(operation.time)
		_check(view.hold_indicator.active == bool(frame.active), "Original hold feedback active state")
		_check((view.held_at >= 0) == bool(frame.holding), "Original hold callback lifetime")
		_check(absf(view.hold_indicator.dash_target - float(frame.offset)) < 0.0000000001, "Original hold progress target")
		_check(view.buffer_warning_timers.size() == int(frame.warnings), "Original independent buffering warnings")
		_check(buffer.complete == bool(frame.ready) and view.closing == bool(frame.destroyed), "Original buffer gate and finish state")
		_check(view.buffer_status.text == str(frame.status), "Original buffering status text")
	view.dispose()
	view.free()
