extends "res://tests/run.gd"

const Status = preload("res://scripts/campaign_status_color.gd")
const ProbeView = preload("res://tests/campaign_chapter_status.gd").ProbeView

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/campaign_status_color.json")
	var data: Dictionary = Content.read_json("res://data/campaign_status_color.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(DisplayServer.get_name() != "headless", "Campaign status colors require a real display driver")
	_check(capture.get("formatVersion") == 1 and capture.get("programs") is Array and capture.programs.size() == 6,
		"Capture original status transitions")
	_check(data == {"formatVersion": capture.get("formatVersion"), "source": capture.get("source"), "rules": capture.get("rules")},
		"Status color resource retains original CSS")
	if failures == 0:
		for path: String in capture.source.inputs:
			var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(text.sha256_text() == capture.source.inputs[path], "Current status color capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original status color input: " + path)
	if failures == 0:
		_check_programs(capture.programs, data.rules)
		_check_view(data.rules)
		await _check_wall_time(data.rules)
	print("CAMPAIGN_STATUS_COLOR assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _status(rules: Dictionary) -> Status:
	var label := Status.new()
	label.rules = rules
	add_child(label)
	label.set_state(false, false, false)
	return label

func _check_programs(programs: Array, rules: Dictionary) -> void:
	for program: Dictionary in programs:
		var label := _status(rules)
		label.set_state(program.mode == "ready", program.mode != "ready", program.mode != "ready")
		_check(label.tween != null and label.tween.is_valid(), "Original status transition starts: " + String(program.mode))
		if label.tween == null:
			label.free()
			continue
		label.tween.pause()
		if program.mode in ["warning_progress", "reverse", "same_target", "double_reverse"]:
			label.tween.custom_step(.15)
			if program.mode == "warning_progress":
				label.set_state(false, true, false)
			elif program.mode == "same_target":
				label.set_state(false, true, false)
				var running := label.tween
				label.set_state(false, true, true)
				_check(label.tween == running, "Repeated warning preserves its current color transition")
			else:
				label.set_state(false, false, false)
				_check(absf(float(rules.duration) * label.shortening * 1000 - float(program.reverseDuration)) < .05,
					"Original color reversal shortens its duration")
				if label.tween != null:
					label.tween.pause()
				if program.mode == "double_reverse":
					label.tween.custom_step(.05)
					label.set_state(false, true, true)
					_check(absf(float(rules.duration) * label.shortening * 1000 - float(program.repeatedDuration)) < .05,
						"A repeated color reversal preserves the source shortening factor")
					if label.tween != null:
						label.tween.pause()
		var elapsed := 0.0
		if program.mode == "same_target":
			elapsed = .15
		for state: Dictionary in program.states:
			var seconds := float(state.ms) / 1000.0
			if program.mode != "warning_progress" and label.tween != null and label.tween.is_valid():
				label.tween.custom_step(maxf(0.0, seconds - elapsed))
			elapsed = seconds
			_check_color(label.current_color, state.color, "Original inherited color: " + String(program.mode))
			if program.mode == "warning":
				_check_color(label.get_theme_color("font_color"), state.child, "Original inline warning color")
			elif program.mode == "warning_progress":
				_check_color(label.get_theme_color("font_color"), state.color, "Progress text inherits the live warning transition")
		label.free()

func _check_color(actual: Color, channels: Array, description: String) -> void:
	var tolerance := 1.0 / 255.0
	_check(absf(actual.r - float(channels[0]) / 255.0) <= tolerance
		and absf(actual.g - float(channels[1]) / 255.0) <= tolerance
		and absf(actual.b - float(channels[2]) / 255.0) <= tolerance, description)

func _check_view(rules: Dictionary) -> void:
	var view := ProbeView.new()
	add_child(view)
	var clock := {"now": 1000.0}
	view.clock_msec = func(): return clock.now
	view.play(Content.campaign.prologue, "Continue")
	view.set_process(false)
	view._try_skip()
	_check(view.buffer_warning and view.buffer_status.warning_text and view.buffer_warning_timers.size() == 1,
		"Pending skip displays the inline warning and schedules its original deadline")
	view.buffer_status.tween.pause()
	view.buffer_status.tween.custom_step(.15)
	view.buffer_loader._settle(view.buffer_rules.assets[0], null, true)
	_check(view.buffer_warning and not view.buffer_status.warning_text,
		"Buffer progress replaces warning text while retaining the warning class")
	_check(view.buffer_status.get_theme_color("font_color").is_equal_approx(view.buffer_status.current_color),
		"Progress text inherits the running warning color")
	clock.now += float(view.buffer_rules.warningMsec)
	view.buffer_warning_timers[0].timeout.emit()
	_check(not view.buffer_warning and not view.buffer_status.warning_text,
		"Original warning expiry restores regular status text")
	view.dispose()
	view.free()
	var label := _status(rules)
	label.theme_changed.connect(func(): label.retire(), CONNECT_ONE_SHOT)
	label.set_state(true, false, false)
	_check(not label.initialized and label.tween == null,
		"Reentrant retirement cannot start a stale color tween")
	label.free()
	label = _status(rules)
	label.theme_changed.connect(func(): label.set_state(true, false, false), CONNECT_ONE_SHOT)
	label.set_state(true, false, false)
	_check(label.initialized and label.tween != null and label.tween.is_valid(),
		"A reentrant unchanged target retains the admitted color transition")
	label.free()
	view = ProbeView.new()
	add_child(view)
	view.play(Content.campaign.prologue, "Continue")
	view.set_process(false)
	var replacement := view
	view.buffer_status.theme_changed.connect(func():
		replacement.play([Content.campaign.prologue[0]], "Continue"), CONNECT_ONE_SHOT)
	view._try_skip()
	_check(view.playing and not view.closing and view.buffer_loader == null and view.buffer_warning_timers.is_empty(),
		"A status color callback can replace playback without starting a stale warning timer")
	view.dispose()
	view.free()

func _check_wall_time(rules: Dictionary) -> void:
	var label := _status(rules)
	var previous_scale := Engine.time_scale
	var previous_pause := get_tree().paused
	Engine.time_scale = 0
	get_tree().paused = true
	label.set_state(true, false, false)
	var deadline := Time.get_ticks_usec() + 400000
	while Time.get_ticks_usec() < deadline:
		await get_tree().process_frame
	var expected: Array = rules.colors.ready
	_check_color(label.current_color, expected.map(func(channel): return float(channel) * 255),
		"Status color transition follows wall time during pause and zero game speed")
	get_tree().paused = previous_pause
	Engine.time_scale = previous_scale
	label.free()
