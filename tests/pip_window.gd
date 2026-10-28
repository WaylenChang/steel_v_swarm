extends "res://tests/run.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/pip_window.json")
	_check(DisplayServer.get_name() != "headless", "PiP window tests require an actual display driver")
	_check(DisplayServer.screen_get_scale() == 1.0, "Simulated source pixel ratios require a scale-1 native display")
	_check(capture.get("formatVersion") == 1 and capture.get("cases") is Array and capture.cases.size() == 8,
		"Capture original PiP window and pixel-ratio geometry")
	if failures == 0:
		var provenance: Dictionary = Content.read_json("res://data/provenance.json")
		for path: String in capture.source.inputs:
			var source := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(source.sha256_text() == capture.source.inputs[path], "Current PiP window capture input: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.get("inputs", {}).get(path) == capture.source.sourceInputs[path], "Original PiP window source identity: " + path)
	if failures == 0:
		await _check_cases(capture.cases)
	print("PIP_WINDOW assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_cases(cases: Array) -> void:
	var evidence_dir := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence-dir="):
			evidence_dir = argument.trim_prefix("--evidence-dir=")
	if not evidence_dir.is_empty():
		var absolute_dir := ProjectSettings.globalize_path(evidence_dir)
		_check(not DirAccess.dir_exists_absolute(absolute_dir), "Preserve existing PiP window evidence")
		if DirAccess.dir_exists_absolute(absolute_dir):
			return
		var directory_status := DirAccess.make_dir_recursive_absolute(absolute_dir)
		_check(directory_status == OK, "Create the PiP window evidence directory")
		if directory_status != OK:
			return
	var saved_size := get_window().size
	var saved_power: Variant = Controls.power_pref
	Controls.power_pref = "0"
	var battle := BattleSimulation.new()
	add_child(battle)
	battle.set_physics_process(false)
	battle.world = BattleWorld.new()
	battle.world.bounds = {"minX": -1000, "maxX": 1000, "minZ": -1000, "maxZ": 1000}
	battle.add_child(battle.world)
	var pilot := BattleUnit.new()
	pilot.peer_id = 17
	pilot.kind = "robot"
	pilot.hp = 1
	battle.add_child(pilot)
	var actor := BattleUnit.new()
	actor.entity_id = 7
	actor.peer_id = 17
	actor.kind = "decoy"
	actor.hp = 1
	actor.special = {"owner_peer": 17}
	battle.add_child(actor)
	actor.model = Node3D.new()
	actor.add_child(actor.model)
	battle.units[actor.entity_id] = actor
	var backdrop := ColorRect.new()
	backdrop.color = Color.BLACK
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var host := Control.new()
	add_child(host)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var view := PipView.new()
	host.add_child(view)
	var witnesses: Array = []
	failure_scope = "pip_window"
	for index in cases.size():
		var sample: Dictionary = cases[index]
		var expected_size := Vector2i(sample.backing[0], sample.backing[1])
		get_window().size = expected_size
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		view.update_view(battle, pilot, "STEEL")
		await RenderingServer.frame_post_draw
		_check(get_window().size == expected_size, "Actual window uses the source framebuffer dimensions")
		_check(view.views.size() == 1 and view.views[0].border.visible, "Actual PiP consumer presents the source slot")
		if view.views.size() != 1 or not view.views[0].border.visible:
			continue
		var local: Rect2 = view.views[0].border.get_global_rect()
		var transform := get_window().get_screen_transform()
		var geometry := Rect2(transform * local.position, local.size * transform.get_scale())
		var image := get_window().get_texture().get_image()
		var color := Color8(sample.borderColor[0], sample.borderColor[1], sample.borderColor[2], sample.borderColor[3])
		_check(Color(Content.side_info("STEEL").color).to_rgba32() == color.to_rgba32(), "Native PiP uses the original border color")
		var pixels := _border_bounds(image, color)
		var native := Rect2i(pixels.position + Vector2i(roundi(transform.origin.x), roundi(transform.origin.y)), pixels.size)
		var expected := Rect2i(sample.borderPixels[0], sample.borderPixels[1], sample.borderPixels[2], sample.borderPixels[3])
		if native != expected:
			witnesses.append({"index": index, "size": sample.size, "dpr": sample.dpr, "window": [get_window().size.x, get_window().size.y],
				"native": [native.position.x, native.position.y, native.size.x, native.size.y],
				"source": sample.borderPixels, "geometry": [geometry.position.x, geometry.position.y, geometry.size.x, geometry.size.y],
				"visible": [view.get_viewport_rect().size.x, view.get_viewport_rect().size.y]})
			if not evidence_dir.is_empty():
				_check(image.save_png(evidence_dir.path_join("pip-window-%d.png" % index)) == OK, "Retain the actual PiP window image")
		_check(pixels.size.x > 0 and pixels.size.y > 0, "Read the actual PiP border pixels")
		_check(native == expected, "Actual PiP border pixel bounds match the original at case " + str(index))
	view.free()
	battle.free()
	backdrop.free()
	host.free()
	Controls.power_pref = saved_power
	get_window().size = saved_size
	if evidence_dir.is_empty():
		return
	var file := FileAccess.open(evidence_dir.path_join("pip-window-report.json"), FileAccess.WRITE)
	_check(file != null, "Retain PiP window geometry witnesses")
	if file != null:
		file.store_string(JSON.stringify({"cases": cases.size(), "mismatches": witnesses.size(), "witnesses": witnesses}, "  "))
		file.close()

func _border_bounds(image: Image, color: Color) -> Rect2i:
	if image == null or image.is_empty():
		return Rect2i()
	image.convert(Image.FORMAT_RGBA8)
	var bytes := image.get_data()
	var width := image.get_width()
	var minimum := Vector2i(width, image.get_height())
	var maximum := Vector2i(-1, -1)
	var red := roundi(color.r * 255)
	var green := roundi(color.g * 255)
	var blue := roundi(color.b * 255)
	for index in range(0, bytes.size(), 4):
		if bytes[index] == red and bytes[index + 1] == green and bytes[index + 2] == blue and bytes[index + 3] == 255:
			var pixel := index / 4
			var point := Vector2i(pixel % width, pixel / width)
			minimum = Vector2i(mini(minimum.x, point.x), mini(minimum.y, point.y))
			maximum = Vector2i(maxi(maximum.x, point.x), maxi(maximum.y, point.y))
	if maximum.x < 0:
		return Rect2i()
	return Rect2i(minimum, maximum - minimum + Vector2i.ONE)
