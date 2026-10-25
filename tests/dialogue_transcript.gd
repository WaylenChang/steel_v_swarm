extends "res://tests/run.gd"

const Row = preload("res://scripts/dialogue_transcript_row.gd")
const Raster = preload("res://tests/raster_compare.gd")

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/dialogue_transcript.json")
	var data: Dictionary = Content.read_json("res://data/dialogue_transcript.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Transcript capture is current")
	for path: String in capture.source.sourceInputs:
		_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Transcript retains original scene, CSS and asset bindings")
	_check(data.source == capture.source and data.motion == capture.motion, "Transcript motion resource retains original CSS values")
	if failures > 0:
		_finish_transcript()
		return
	for program: Dictionary in capture.programs:
		var view := CampaignDialogue.new()
		var clock := {"now": 0.0}
		view.clock_msec = func(): return clock.now
		view.side = program.side
		view.art_mode = program.artMode
		add_child(view)
		var host := VBoxContainer.new()
		add_child(host)
		view.transcript(host, program.scene)
		var rows: Array = host.get_child(2).rows.get_children()
		_check(rows.size() == program.metadata.size(), "Every original transcript line creates one native row")
		for index in range(mini(rows.size(), program.metadata.size())):
			var expected: Dictionary = program.metadata[index]
			var content: HBoxContainer = rows[index].content if rows[index].get_script() == Row else rows[index]
			var portrait := content.get_child(1 if expected.flip else 0) as TextureRect
			var text := content.get_child(0 if expected.flip else 1) as VBoxContainer
			_check(portrait != null and text != null, "Original viewer-relative transcript direction")
			if portrait != null and text != null:
				_check(portrait.texture != null and portrait.texture.resource_path == "res://" + String(expected.portrait).trim_prefix("/"), "Original transcript avatar asset binding")
				_check(text.get_child(0).text == expected.speaker and text.get_child(1).get_parsed_text() == expected.text, "Original escaped plain transcript speaker and text")
		for frame: Dictionary in program.frames:
			clock.now = float(frame.time) * 1000
			match frame.action:
				"timer":
					_check(not view.timers.is_empty(), "Original transcript stagger timer remains pending")
					if not view.timers.is_empty():
						view.timers[0].timeout.emit()
				"clear":
					view.transcript(host, program.scene)
					view.clear()
			_check(view.timers.size() == frame.state.timers.size(), "Source clear cancels every pending transcript callback")
			for index in range(mini(view.timers.size(), frame.state.timers.size())):
				_near(view.timers[index].wait_time - clock.now / 1000, frame.state.timers[index], "Original absolute transcript stagger deadlines")
			for index in range(rows.size()):
				var revealed: bool = rows[index].revealed if rows[index].get_script() == Row else rows[index].modulate.a > 0
				_check(revealed == frame.state.visible[index], "Original transcript reveal order survives clear without hiding existing rows")
			if frame.action == "timer" and float(frame.time) == float(program.frames[1].time):
				var sample: Dictionary = capture.motion.frames[4]
				if rows[0].get_script() == Row:
					rows[0].motion.pause()
					rows[0].motion.custom_step(sample.time)
				var opacity: float = rows[0].layer.opacity if rows[0].get_script() == Row else rows[0].modulate.a
				_near(opacity, sample.opacity, "Every actual transcript binding uses the original continuous reveal rather than an immediate opacity switch")
		view.free()
		host.free()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(96, 80)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var ground := ColorRect.new()
	ground.size = Vector2(96, 80)
	ground.color = Color("#192b3c")
	viewport.add_child(ground)
	var row := Row.new()
	viewport.add_child(row)
	row.size = Vector2(96, 64)
	for layer: Dictionary in capture.layers:
		var panel := ColorRect.new()
		panel.position = Vector2(layer.rect[0], layer.rect[1])
		panel.size = Vector2(layer.rect[2], layer.rect[3])
		panel.color = Color(layer.color)
		row.layer.content.add_child(panel)
	row.reveal()
	row.motion.pause()
	var elapsed := 0.0
	var output := "res://build/dialogue_transcript"
	DirAccess.make_dir_recursive_absolute(output)
	var report: Array = []
	for frame: Dictionary in capture.motion.frames:
		if row.motion.is_valid():
			row.motion.custom_step(float(frame.time) - elapsed)
		elapsed = frame.time
		_near(row.layer.opacity, frame.opacity, "Original transcript ease-out opacity")
		_near(row.layer.position.y, frame.y, "Original transcript six-pixel ease-out translation")
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var actual := viewport.get_texture().get_image()
		var expected := Image.new()
		_check(expected.load_png_from_buffer(Marshalls.base64_to_raw(frame.png)) == OK, "Decode original transcript motion raster")
		var result := Raster.compare(actual, expected)
		report.append({"time": frame.time, "pixels": result.pixels, "maximum": result.maximum})
		_check(result.pixels == 0, "Original transcript reveal raster: time=%f pixels=%d maximum=%f" % [frame.time, result.pixels, result.maximum])
		Raster.diagnostic(actual).save_png(output + "/native_%d.png" % report.size())
		expected.save_png(output + "/source_%d.png" % report.size())
	var file := FileAccess.open(output + "/report.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	viewport.remove_child(row)
	_check(row.layer.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and not row.motion.is_valid(), "Detached transcript rows stop rendering and motion before deferred destruction")
	row.free()
	viewport.free()
	for program: Dictionary in capture.scrollPrograms:
		var scroll := ScrollContainer.new()
		scroll.size = Vector2(200, 100)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		add_child(scroll)
		var space := Control.new()
		space.custom_minimum_size = Vector2(100, 500)
		scroll.add_child(space)
		var target := Row.new()
		space.add_child(target)
		target.position.y = program.top
		target.size = Vector2(100, program.height)
		await get_tree().process_frame
		scroll.scroll_vertical = int(program.initial)
		target._scroll_nearest()
		_near(scroll.scroll_vertical, program.scroll, "Original transformed nearest scrolling, including oversized rows")
		scroll.free()
	for program: Dictionary in capture.nestedScrollPrograms:
		var outer := ScrollContainer.new()
		outer.size = Vector2(240, 120)
		outer.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		add_child(outer)
		var space := Control.new()
		space.custom_minimum_size = Vector2(200, 900)
		outer.add_child(space)
		var inner := ScrollContainer.new()
		inner.position.y = 200
		inner.size = Vector2(200, 100)
		inner.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		space.add_child(inner)
		var inner_space := Control.new()
		inner_space.custom_minimum_size = Vector2(100, 500)
		inner.add_child(inner_space)
		var target := Row.new()
		inner_space.add_child(target)
		target.position.y = program.top
		target.size = Vector2(100, program.height)
		await get_tree().process_frame
		outer.scroll_vertical = int(program.outerStart)
		inner.scroll_vertical = int(program.innerStart)
		target._scroll_nearest()
		_near(inner.scroll_vertical, program.inner, "Original inner nearest scroll before native layout applies changed ranges")
		_near(outer.scroll_vertical, program.outer, "Original outer nearest scroll consumes the inner scroll displacement")
		outer.free()
	var paused_row := Row.new()
	add_child(paused_row)
	var speed := Engine.time_scale
	Engine.time_scale = 0
	get_tree().paused = true
	paused_row.reveal()
	var bound := Time.get_ticks_msec() + 1000
	while paused_row.motion.is_valid() and Time.get_ticks_msec() < bound:
		await get_tree().process_frame
	_check(paused_row.layer.opacity == float(capture.motion.to) and paused_row.layer.position.y == float(capture.motion.toY), "Transcript CSS reveal completes while gameplay is paused at zero speed")
	get_tree().paused = false
	Engine.time_scale = speed
	paused_row.free()
	_finish_transcript()

func _finish_transcript() -> void:
	print("DIALOGUE_TRANSCRIPT assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
