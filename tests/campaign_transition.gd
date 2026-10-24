extends "res://tests/run.gd"

const LifecycleView = preload("res://tests/campaign_lifecycle.gd").LifecycleView
const Raster = preload("res://tests/raster_compare.gd")

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/campaign_transition.json")
	var data: Dictionary = Content.read_json("res://data/campaign_transition.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(DisplayServer.get_name() != "headless", "Cinematic fade qualification requires a rendered session")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Cinematic exit capture is current")
	for path: String in capture.source.sourceInputs:
		_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Cinematic exit retains original CSS and finish method identity")
	_check(data.source == capture.source and data.rules == capture.rules, "Dedicated cinematic transition resource retains source configuration")
	_check(Content.campaign.presentation.skip.fade == capture.rules.exit.duration, "Imported cinematic exit duration equals original CSS and timeout")
	if not failures.is_empty():
		_finish_transition()
		return
	var view := LifecycleView.new()
	var clock := {"now": 1000.0}
	view.clock_msec = func(): return clock.now
	add_child(view)
	view.play([Content.campaign.prologue[0]], "Continue")
	view.set_process(false)
	await get_tree().process_frame
	var signals := {"finished": 0}
	view.finished.connect(func(): signals.finished += 1)
	view.finish()
	view.finish()
	view.exit_tween.pause()
	var elapsed := 0.0
	for frame: Dictionary in capture.frames:
		view.exit_tween.custom_step(float(frame.time) - elapsed)
		elapsed = frame.time
		clock.now = 1000 + float(frame.time) * 1000
		view.exit_timer.timeout.emit()
		var group := view.get_node_or_null("Presentation") as CanvasGroup
		var presented: float = group.self_modulate.a if group != null else view.modulate.a
		_near(presented, frame.opacity, "Original cinematic cubic-bezier exit curve")
		_check(view.visible == frame.visible and signals.finished == int(frame.completed), "Original once-only exit deadline and visibility")
	view.dispose()
	view.free()
	await _wall_deadline(capture.rules.exit.duration)
	var output := "res://build/campaign_transition"
	_check(DirAccess.make_dir_recursive_absolute(output) == OK, "Create cinematic transition evidence directory")
	var report: Array = []
	for index in range(capture.composition.rasters.size()):
		var item: Dictionary = capture.composition.rasters[index]
		var viewport := SubViewport.new()
		viewport.size = Vector2i(capture.composition.width, capture.composition.height)
		viewport.disable_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		_add_rect(viewport, [0, 0, viewport.size.x, viewport.size.y], capture.composition.background)
		var probe := LifecycleView.new()
		viewport.add_child(probe)
		probe.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		probe.size = Vector2(viewport.size)
		probe.play([Content.campaign.prologue[0]], "Continue")
		probe.set_process(false)
		await get_tree().process_frame
		var group := probe.get_node_or_null("Presentation") as CanvasGroup
		var host: Node = group if group != null else probe
		for child in host.get_children():
			if child is CanvasItem:
				child.hide()
		for layer: Dictionary in capture.composition.layers:
			_add_rect(host, layer.rect, layer.rgba)
		probe.finish()
		probe.exit_tween.pause()
		probe.exit_tween.custom_step(item.time)
		for frame in range(3):
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
		var actual := viewport.get_texture().get_image()
		var expected := Image.new()
		var decoded := expected.load_png_from_buffer(Marshalls.base64_to_raw(item.png)) == OK and expected.get_size() == actual.get_size()
		_check(decoded, "Original cinematic opacity raster has matching dimensions")
		if decoded:
			var result := Raster.compare(actual, expected)
			report.append({"time": item.time, "pixels": result.pixels, "maximum": result.maximum})
			_check(result.pixels == 0, "Original complete-group cinematic exit: time=%f pixels=%d maximum=%f" % [item.time, result.pixels, result.maximum])
			Raster.diagnostic(actual).save_png(output + "/native_%d.png" % index)
			expected.save_png(output + "/source_%d.png" % index)
		probe.dispose()
		viewport.free()
	var file := FileAccess.open(output + "/report.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	_finish_transition()

func _wall_deadline(duration: float) -> void:
	var view := LifecycleView.new()
	add_child(view)
	view.play([Content.campaign.prologue[0]], "Continue")
	view.set_process(false)
	await get_tree().process_frame
	var observed := {"at": 0.0, "count": 0}
	view.finished.connect(func(): observed.at = view._now_msec(); observed.count += 1)
	var before := view._now_msec()
	view.finish()
	# Advancing the visual animation must not settle the independent source timer.
	view.exit_tween.pause()
	view.exit_tween.custom_step(duration + 1)
	_check(view.playing and view.visible and observed.count == 0, "Cinematic visual completion cannot fire the source wall deadline early")
	var deadline := before + (duration + .1) * 1000
	while observed.count == 0 and view._now_msec() < deadline:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	_check(observed.count == 1 and observed.at - before >= duration * 1000 and not view.visible,
		"Actual native timer waits the complete original wall duration and completes exactly once: count=%d elapsed=%f observed=%f visible=%s" %
		[observed.count, view._now_msec() - before, observed.at - before, view.visible])
	view.queue_free()
	await get_tree().process_frame

func _add_rect(host: Node, rect: Array, colour: Variant) -> void:
	var panel := ColorRect.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = Vector2(rect[0], rect[1])
	panel.size = Vector2(rect[2], rect[3])
	panel.color = ScopeOverlay.color_value(colour) if colour is Array else Color(colour)
	host.add_child(panel)

func _finish_transition() -> void:
	print("CAMPAIGN_TRANSITION assertions=", assertions, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
