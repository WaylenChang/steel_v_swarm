extends "res://tests/run.gd"

const ProbeView = preload("res://tests/campaign_chapter_status.gd").ProbeView

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/campaign_status_persistence.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(DisplayServer.get_name() != "headless", "Campaign status lifetime requires a real display driver")
	_check(capture.get("formatVersion") == 1 and capture.get("programs") is Array and capture.programs.size() == 5,
		"Capture original campaign status lifetime")
	if failures == 0:
		for path: String in capture.source.inputs:
			var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(text.sha256_text() == capture.source.inputs[path], "Current status lifetime capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original status lifetime input: " + path)
	if failures == 0:
		await _check_programs(capture.programs)
	print("CAMPAIGN_STATUS_PERSISTENCE assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_programs(programs: Array) -> void:
	for program: Dictionary in programs:
		var clock := {"now": 1000.0}
		var view := ProbeView.new()
		view.clock_msec = func(): return clock.now
		add_child(view)
		view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		view.size = Vector2(640, 360)
		var old_timer: Timer
		var warning_deadline := 0.0
		for frame: Dictionary in program.records:
			match String(frame.action):
				"prologue":
					view.play(Content.campaign.prologue, "Continue")
					view.set_process(false)
				"replay":
					view.finish()
					clock.now = view.exit_deadline
					view._complete_exit(view.generation)
					view.play(Content.campaign.prologue, "Continue")
					view.set_process(false)
				"warning":
					view._try_skip()
					old_timer = view.buffer_warning_timers[0]
					warning_deadline = clock.now + float(view.buffer_rules.warningMsec)
				"ready":
					view.buffer_loader.percent = 100
					view.buffer_loader.complete = true
					view._buffer_progress(12, 12, 100, "models", true, view.generation)
				"expired":
					clock.now += float(view.buffer_rules.warningMsec)
					old_timer.timeout.emit()
				"finishing":
					if program.scenario == "warning_during_exit":
						clock.now = warning_deadline - 100
					view.finish()
				"late_during_fade":
					clock.now = warning_deadline
					old_timer.timeout.emit()
				"hidden":
					clock.now = view.exit_deadline
					view._complete_exit(view.generation)
				"chapter":
					view.play([Content.campaign.prologue[0]], "Continue")
					view.set_process(false)
				"late_warning": old_timer.timeout.emit()
			_check(view.buffer_warning == bool(frame.warning), "Original persistent warning class: " + String(program.scenario) + "/" + String(frame.action))
			if bool(frame.visible):
				_check(view.buffer_status.text == String(frame.status) and view.caption.text == String(frame.hint),
					"Original visible status and hint: " + String(program.scenario) + "/" + String(frame.action))
				var channels := String(frame.color).trim_prefix("rgb(").trim_suffix(")").split(",")
				var expected := Color8(int(channels[0]), int(channels[1]), int(channels[2]))
				_check(view.buffer_status.target_color.is_equal_approx(expected),
					"Original status class color: " + String(program.scenario) + "/" + String(frame.action))
		view.dispose()
		view.free()
	await get_tree().process_frame
