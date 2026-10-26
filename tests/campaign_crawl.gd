extends "res://tests/run.gd"

class ProbeView extends "res://tests/campaign_lifecycle.gd".LifecycleView:
	# Real native scrolling with declared geometry; narrative layout and art are separate gates.
	func _layout() -> void:
		pass

	func _update_scene() -> void:
		pass

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/campaign_crawl.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Cinematic crawl capture is current")
	for path: String in capture.source.sourceInputs:
		_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Cinematic crawl retains original controller and DOM identity")
	var scales: Array = []
	for program: Dictionary in capture.programs:
		if not scales.has(program.deviceScaleFactor):
			scales.append(program.deviceScaleFactor)
	_check(scales == [1.0, 1.25, 1.5, 2.0], "Crawl source quantization covers desktop and high-density browser scales")
	if failures > 0:
		_finish_crawl()
		return
	for program: Dictionary in capture.programs:
		var clock := {"now": 1000.0}
		var view := ProbeView.new()
		view.clock_msec = func(): return clock.now
		add_child(view)
		view.play([Content.campaign.prologue[0]], "Continue")
		view.set_process(false)
		await get_tree().process_frame
		view.scroll.get_parent().remove_child(view.scroll)
		view.presentation_group.add_child(view.scroll)
		view.scroll.custom_minimum_size = Vector2.ZERO
		view.scroll.size = Vector2(program.geometry.width, program.geometry.height)
		for child in view.column.get_children():
			view.column.remove_child(child)
			child.queue_free()
		view.sections.clear()
		view.column.custom_minimum_size.y = program.geometry.scrollHeight
		view.column.size.y = program.geometry.scrollHeight
		await get_tree().process_frame
		var bar := view.scroll.get_v_scroll_bar()
		_check(bar.max_value == program.geometry.scrollHeight and bar.page == program.geometry.height,
			"Native scroll bounds equal declared source DOM geometry")
		for frame: Dictionary in program.frames:
			var operation: Dictionary = frame.operation
			clock.now = operation.time
			match operation.type:
				"frame": view._process(operation.delta)
				"scroll": bar.value = operation.value
				"wheel":
					var event := InputEventMouseButton.new()
					event.button_index = MOUSE_BUTTON_WHEEL_DOWN
					event.pressed = true
					view._scroll_input(event)
			_near(bar.value, frame.scroll, "Original per-frame DOM scroll write/read, quantization and maximum clamp")
			_near(view.paused_until, frame.pauseUntil, "Original strict crawl pause deadline")
			_near(view.last_frame_at, frame.lastFrame, "Original wall frame clock advances while paused and at maximum scroll")
		view.play([Content.campaign.prologue[0]], "Continue")
		view.set_process(false)
		_near(bar.value, program.replay.scroll, "Fresh source playback resets the retained viewport scroll position")
		_near(view.last_frame_at, program.replay.lastFrame, "Fresh source playback starts a new wall frame clock")
		view.dispose()
		view.free()
	_finish_crawl()

func _finish_crawl() -> void:
	print("CAMPAIGN_CRAWL assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
