extends "res://tests/run.gd"

const Raster = preload("res://tests/raster_compare.gd")

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/dialogue_motion.json")
	var data: Dictionary = Content.read_json("res://data/dialogue_motion.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Radio motion capture is current")
	for path: String in capture.source.sourceInputs:
		_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Radio motion retains original CSS and removal method")
	_check(DisplayServer.get_name() != "headless", "Radio motion pixels require a real renderer")
	_check(data.source == capture.source and data.rules == capture.rules, "Native radio motion resource retains original animation rules")
	_near(Content.campaign.presentation.radioFade, capture.rules.exit.removal, "Original radio removal remains independent of its animation duration")
	var output := "res://build/dialogue_motion"
	DirAccess.make_dir_recursive_absolute(output)
	var report: Array = []
	if failures.is_empty():
		for program: Dictionary in capture.programs:
			var viewport := SubViewport.new()
			viewport.size = Vector2i(96, 80)
			viewport.disable_3d = true
			viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			add_child(viewport)
			var ground := ColorRect.new()
			ground.size = Vector2(96, 80)
			ground.color = Color("#192b3c")
			viewport.add_child(ground)
			var view := CampaignDialogue.new()
			var clock := {"now": 1000.0}
			view.clock_msec = func(): return clock.now
			viewport.add_child(view)
			var scene: Dictionary = Content.campaign.talk.values()[0].values()[0].values()[0].duplicate(true)
			scene.lines = scene.lines.slice(0, 1)
			view.radio(scene)
			var group := view.get_node_or_null("RadioPresentation") as Sprite2D
			var animation: Tween
			if group != null:
				animation = view.entrance
			var base_y := view.bar.position.y
			if program.phase == "exit":
				view._step()
				animation = view.fade
			if animation != null and animation.is_valid():
				animation.pause()
			view.bar.hide()
			for layer: Dictionary in capture.layers:
				var panel := ColorRect.new()
				panel.position = Vector2(layer.rect[0], layer.rect[1])
				panel.size = Vector2(layer.rect[2], layer.rect[3])
				panel.color = Color(layer.color)
				(group.content if group != null else view).add_child(panel)
			var elapsed := 0.0
			for index in range(program.frames.size()):
				var frame: Dictionary = program.frames[index]
				if animation != null and animation.is_valid():
					animation.custom_step(float(frame.time) - elapsed)
				elapsed = frame.time
				var opacity: float = group.opacity if group != null else view.bar.modulate.a
				var y := group.position.y if group != null else view.bar.position.y - base_y
				_near(opacity, frame.opacity, "Original whole-radio animation opacity")
				_near(y, frame.y, "Original radio animation translation")
				await get_tree().process_frame
				await RenderingServer.frame_post_draw
				var actual := viewport.get_texture().get_image()
				var expected := Image.new()
				_check(expected.load_png_from_buffer(Marshalls.base64_to_raw(frame.png)) == OK, "Decode original radio animation raster")
				var result := Raster.compare(actual, expected)
				report.append({"phase": program.phase, "frame": index, "time": frame.time, "pixels": result.pixels, "maximum": result.maximum})
				_check(result.pixels == 0, "Original radio animation raster: %s frame=%d pixels=%d maximum=%f" % [program.phase, index, result.pixels, result.maximum])
				Raster.diagnostic(actual).save_png(output + "/native_%s_%d.png" % [program.phase, index])
				expected.save_png(output + "/source_%s_%d.png" % [program.phase, index])
			if program.phase == "exit":
				var timer: Timer = view.timers[-1]
				clock.now += float(capture.rules.exit.duration) * 1000
				timer.timeout.emit()
				_check(is_instance_valid(view.bar), "Completing the CSS animation does not shorten the separate source removal deadline")
				clock.now = 1000 + float(capture.rules.exit.removal) * 1000
				timer.timeout.emit()
				_check(view.bar == null, "The original removal callback retires its bar at 420 ms")
			view.clear()
			_check(animation == null or not animation.is_valid(), "Clear cancels the current radio animation")
			if group != null:
				_check(group.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and not group.visible, "Retired radio stops drawing immediately before deferred destruction")
			view.radio(scene)
			var replacement := view.radio_group
			view.hide()
			_check(replacement.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Ancestor visibility loss stops the isolated radio renderer")
			view.show()
			_check(replacement.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "Visible radio resumes its isolated renderer")
			var retired_entrance := view.entrance
			view.radio(scene)
			_check(not retired_entrance.is_valid() and replacement.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Replacement cancels old motion and rendering before deferred destruction")
			view.clear()
			viewport.free()
	var file := FileAccess.open(output + "/report.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	print("DIALOGUE_MOTION assertions=", assertions, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
