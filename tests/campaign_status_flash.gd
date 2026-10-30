extends "res://tests/run.gd"

const Status = preload("res://scripts/campaign_status_color.gd")
const ProbeView = preload("res://tests/campaign_chapter_status.gd").ProbeView

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/campaign_status_flash.json")
	var data: Dictionary = Content.read_json("res://data/campaign_status_flash.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(DisplayServer.get_name() != "headless", "Campaign status flash requires a real display driver")
	_check(capture.get("formatVersion") == 1 and capture.get("programs") is Array and capture.programs.size() == 6,
		"Capture original status flash programs")
	_check(data == {"formatVersion": capture.get("formatVersion"), "source": capture.get("source"), "rules": capture.get("rules")},
		"Status flash resource retains original CSS")
	if failures == 0:
		for path: String in capture.source.inputs:
			var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(text.sha256_text() == capture.source.inputs[path], "Current status flash capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original status flash input: " + path)
	if failures == 0:
		_check_programs(capture.programs)
		_check_view()
		_check_ancestor_visibility()
		_check_reentrant()
		await _check_rendering()
		await _check_wall_time()
	print("CAMPAIGN_STATUS_FLASH assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _status() -> Status:
	var label := Status.new()
	label.rules = Content.read_json("res://data/campaign_status_color.json").rules
	add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	label.size = Vector2(200, 30)
	label.set_state(false, false, false)
	return label

func _check_programs(programs: Array) -> void:
	for program: Dictionary in programs:
		var label := _status()
		label.set_state(false, true, true)
		_check(label.flash_tween != null and label.flash_tween.is_valid(), "Original flash starts: " + String(program.mode))
		if label.flash_tween == null:
			label.free()
			continue
		label.flash_tween.pause()
		var elapsed := 0.0
		if program.mode == "completed_repeat":
			var old := label.flash_tween
			label.flash_tween.custom_step(.701)
			label.set_state(false, true, true)
			_check(label.flash_started and label.flash_tween == old and not old.is_running(),
				"A repeated warning cannot restart an already completed flash")
			elapsed = .701
		if program.mode in ["repeat", "progress", "expire", "reopen"]:
			label.flash_tween.custom_step(.2)
			elapsed = .2
			if program.mode == "repeat":
				var running := label.flash_tween
				label.set_state(false, true, true)
				_check(label.flash_tween == running, "Repeated warning does not restart the flash")
			elif program.mode == "progress":
				var running := label.flash_tween
				label.set_state(false, true, false)
				_check(label.flash_tween == running, "Buffer progress does not restart the flash")
			elif program.mode == "expire":
				label.set_state(false, false, false)
				_check(label.flash_tween == null and not label.flash_class, "Warning expiry cancels flash immediately")
			else:
				var old := label.flash_tween
				label.hide()
				_check(label.flash_tween == null and label.flash_class, "Hiding retires the animation but preserves its class")
				label.show()
				_check(label.flash_tween != null and label.flash_tween != old, "Showing the retained class restarts the source flash")
				label.flash_tween.pause()
				elapsed = 0.0
		for state: Dictionary in program.states:
			var seconds := float(state.ms) / 1000.0
			if label.flash_tween != null and label.flash_tween.is_valid():
				label.flash_tween.custom_step(maxf(0.0, seconds - elapsed))
			elapsed = seconds
			_check(absf(label.modulate.a - float(state.opacity)) < .0001, "Original flash opacity: " + String(program.mode) + "/" + str(state.ms))
			_check(absf(label.scale.x - float(state.scale)) < .0001 and absf(label.scale.y - float(state.scale)) < .0001,
				"Original centered flash scale: " + String(program.mode) + "/" + str(state.ms))
			_check(label.pivot_offset == label.size / 2, "Flash scales around the original center")
		label.free()

func _check_view() -> void:
	var clock := {"now": 1000.0}
	var view := ProbeView.new()
	view.clock_msec = func(): return clock.now
	add_child(view)
	view.play(Content.campaign.prologue, "Continue")
	view.set_process(false)
	view._try_skip()
	var old := view.buffer_status.flash_tween
	_check(old != null and old.is_valid(), "A buffering warning starts the source flash")
	old.pause()
	old.custom_step(.2)
	view.finish()
	clock.now = view.exit_deadline
	view._complete_exit(view.generation)
	_check(view.buffer_status.flash_tween == null and view.buffer_warning, "Finishing stops the flash but keeps the warning class")
	view.play([Content.campaign.prologue[0]], "Continue")
	view.set_process(false)
	_check(view.buffer_status.flash_tween != null and view.buffer_status.flash_tween != old,
		"A later chapter restarts the retained warning flash")
	view.dispose()
	view.free()

func _check_reentrant() -> void:
	var label := _status()
	label.theme_changed.connect(func(): label.retire(), CONNECT_ONE_SHOT)
	label.set_state(false, true, true)
	_check(not label.initialized and label.flash_tween == null and label.tween == null,
		"Retirement during a flash cannot leave old animations running")
	label.free()

func _check_ancestor_visibility() -> void:
	var ancestor := Control.new()
	add_child(ancestor)
	var label := Status.new()
	label.rules = Content.read_json("res://data/campaign_status_color.json").rules
	ancestor.add_child(label)
	label.set_state(false, false, false)
	label.set_state(false, true, true)
	var old := label.flash_tween
	ancestor.hide()
	_check(label.flash_tween == null and label.flash_class, "A hidden ancestor stops the source flash")
	ancestor.show()
	_check(label.flash_tween != null and label.flash_tween != old, "Showing an ancestor restarts the retained flash")
	ancestor.free()

func _check_rendering() -> void:
	var stage := SubViewport.new()
	stage.disable_3d = true
	stage.world_2d = World2D.new()
	stage.size = Vector2i(240, 100)
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(stage)
	var background := ColorRect.new()
	background.color = Color8(16, 32, 48)
	background.size = Vector2(stage.size)
	stage.add_child(background)
	var label := Status.new()
	label.rules = Content.read_json("res://data/campaign_status_color.json").rules
	stage.add_child(label)
	label.position = Vector2(40, 20)
	label.size = Vector2(100, 40)
	var fill := ColorRect.new()
	fill.color = Color8(180, 60, 40)
	fill.size = label.size
	label.add_child(fill)
	label.set_state(false, false, false)
	label.set_state(false, true, true)
	label.flash_tween.pause()
	label.flash_tween.custom_step(float(label.flash_rules.duration) / 2)
	for frame in range(2):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var pixel := stage.get_texture().get_image().get_pixel(90, 40)
	var expected := background.color.lerp(fill.color, float(label.flash_rules.peakOpacity))
	_check(absf(pixel.r - expected.r) <= 2.0 / 255 and absf(pixel.g - expected.g) <= 2.0 / 255
		and absf(pixel.b - expected.b) <= 2.0 / 255, "Flash opacity reaches the real composed viewport")
	stage.free()

func _check_wall_time() -> void:
	var label := _status()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var previous_scale := Engine.time_scale
	var previous_pause := get_tree().paused
	Engine.time_scale = 0
	get_tree().paused = true
	label.set_state(false, true, true)
	var observed := false
	var finished := label.flash_tween
	var deadline := Time.get_ticks_usec() + 800000
	while Time.get_ticks_usec() < deadline:
		await get_tree().process_frame
		observed = observed or label.modulate.a < .9
	_check(observed, "Status flash follows wall time during pause and zero game speed")
	_check(not finished.is_valid(), "The flash completes after its two wall-time cycles")
	label.set_state(false, true, true)
	_check(label.flash_tween == finished and label.modulate.a == 1.0 and label.scale == Vector2.ONE,
		"A repeated warning cannot restart a flash that finished in the scene tree")
	get_tree().paused = previous_pause
	Engine.time_scale = previous_scale
	label.free()
