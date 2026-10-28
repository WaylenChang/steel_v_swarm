extends "res://tests/run.gd"

var evidence_dir := "res://artifacts/terra"

class Probe extends "res://scripts/minimap.gd":
	var observations: Array[Dictionary] = []
	var drawn: Array[Dictionary] = []
	var base_window := Rect2()

	func _draw_base() -> void:
		super._draw_base()
		if draw_enabled:
			base_window = window

	func _draw_map() -> void:
		drawn.clear()
		super._draw_map()
		if draw_enabled:
			observations.append({"window": window, "commands": drawn.duplicate(true),
				"lane": lane_view.lines[0].points.duplicate()})

	func _draw_marker(command: Dictionary) -> void:
		drawn.append(command.duplicate(true))
		super._draw_marker(command)

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence-dir="):
			evidence_dir = argument.trim_prefix("--evidence-dir=")
	_check(not evidence_dir.is_empty() and DirAccess.make_dir_recursive_absolute(evidence_dir) == OK,
		"Create the minimap frame evidence directory")
	var capture: Dictionary = Content.read_json("res://tests/fixtures/minimap_frame.json")
	_check(DisplayServer.get_name() != "headless", "Minimap frame order requires a real renderer")
	_check(capture.get("formatVersion") == 1 and capture.get("cases") is Array and capture.cases.size() == 5
		and capture.get("factionCases") is Array and capture.factionCases.size() == 3,
		"Capture the original minimap frame sequence")
	if failures > 0:
		_finish_frame()
		return
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Minimap frame capture input is current: " + path)
	for path: String in capture.source.sourceInputs:
		_check(provenance.get("inputs", {}).get(path) == capture.source.sourceInputs[path], "Minimap frame source identity: " + path)
	if failures > 0:
		_finish_frame()
		return
	await _check_frames(capture)
	await _check_faction_frames(capture)
	_finish_frame()

func _check_frames(capture: Dictionary) -> void:
	var viewport := SubViewport.new()
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.size = Vector2i(capture.canvas[0], capture.canvas[1])
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var view := Probe.new()
	viewport.add_child(view)
	await get_tree().process_frame
	var base := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	base.fill(Color8(40, 80, 120))
	view.configure({"bounds": capture.terrain, "lanes": []}, "", ImageTexture.create_from_image(base))
	_check(view.lane_view.configure([{"grade": "ground", "lane": 0, "points": [[0, 0], [800, 0]]}]),
		"Bind the original controlled lane")
	view.cadence.warm_until = 0
	view.focus = Vector2(800, 500)
	_set_tower(view, Vector3(900, 0, 300))
	view.markers.bunkers["400,300"] = {"point": Vector2(400, 300), "side": "STEEL"}
	_check(view.advance(100), "Initial source frame is due")
	view.update_fog(100, [])
	view.toggle_mode()
	view.focus = Vector2(1000, 600)
	_set_tower(view, Vector3(1000, 0, 0))
	view.markers.bunkers["400,300"].point = Vector2(-400, -300)
	await RenderingServer.frame_post_draw
	_check_observation(view, capture.cases[1], "Pending toggle and snapshot")
	var base_colour := viewport.get_texture().get_image().get_pixel(10, 10)
	_check(absf(base_colour.r - 40.0 / 255.0) < .01 and absf(base_colour.g - 80.0 / 255.0) < .01
		and absf(base_colour.b - 120.0 / 255.0) < .01, "The committed terrain texture reaches the native canvas")
	_check(view.advance(100.1), "Mode toggle invalidates the source deadline")
	view.update_fog(100.1, [])
	await RenderingServer.frame_post_draw
	_check_observation(view, capture.cases[2], "Near frame")
	view.focus = Vector2(-1000, -600)
	_set_tower(view, Vector3(-900, 0, -300))
	var retained_window: Rect2 = view.window
	view.marker_commands()
	_check(view.window == retained_window, "Live marker inspection does not change the retained draw window")
	var previous_count := view.observations.size()
	_check(not view.advance(100.15), "Source draw gate skips early movement")
	await RenderingServer.frame_post_draw
	_check(view.observations.size() == previous_count, "Gated movement retains the preceding canvas")
	_check_observation(view, capture.cases[3], "Gated frame")
	_check(view.advance(100.35), "Next source draw accepts moved focus and marker")
	view.update_fog(100.35, [])
	await RenderingServer.frame_post_draw
	_check_observation(view, capture.cases[4], "Moved frame")
	_check(view.advance(100.6), "A pending frame can be retired before drawing")
	view.clear()
	await RenderingServer.frame_post_draw
	_check(not view.draw_enabled and view.draw_frame.is_empty() and view.lane_view.lines.is_empty(),
		"Room retirement discards pending frame data and lane resources")
	var retired := viewport.get_texture().get_image().get_pixel(10, 10)
	_check(retired.a < .01, "Room retirement clears the previously drawn terrain")
	viewport.free()

func _set_tower(view: Probe, point: Vector3) -> void:
	view.state = {"units": [{"id": 7, "kind": "tower", "side": "STEEL", "character": "", "peer": 1,
		"hp": 1, "position": point, "special": {}}]}
	view.positions = {7: point}

func _check_faction_frames(capture: Dictionary) -> void:
	var viewport := SubViewport.new()
	viewport.disable_3d = true
	viewport.size = Vector2i(capture.canvas[0], capture.canvas[1])
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var view := Probe.new()
	viewport.add_child(view)
	await get_tree().process_frame
	view.configure({"bounds": capture.terrain, "lanes": []}, "STEEL")
	_check(view.lane_view.configure([{"grade": "ground", "lane": 0, "points": [[0, 0], [800, 0]]}]),
		"Bind the faction frame lane")
	view.cadence.warm_until = 0
	view.vision.pulse_until = 1000
	view.focus = Vector2(800, 500)
	view.heading = -1.2
	view.missile_points = [Vector3(-1000, 0, 300)]
	_set_tower(view, Vector3(850, 0, 300))
	view.markers.bunkers["400,300"] = {"point": Vector2(400, 300), "side": "STEEL"}
	_check(view.advance(200), "Initial faction source frame is due")
	view.positions[7] = Vector3(900, 0, 300)
	view.update_fog(200, [])
	_check(view.fog_view.full_reveal.visible, "Captured faction pulse fills the explored map")
	view.state.units[0].special.neutral = true
	view.toggle_mode()
	view.side = "SWARM"
	view.focus = Vector2(1000, 600)
	view.heading = .4
	view.vision.pulse_until = 0
	view.missile_points = [Vector3(1300, 0, 600)]
	_set_tower(view, Vector3(1000, 0, 0))
	view.markers.bunkers["400,300"].point = Vector2(-400, -300)
	await RenderingServer.frame_post_draw
	_check_observation(view, capture.factionCases[1], "Pending faction frame")
	_check_faction_marks(view, viewport, capture.factionCases[1], "Pending faction frame")
	_check(view.fog_view.full_reveal.visible, "Later pulse changes do not rewrite the committed fog frame")
	view.vision.pulse_until = 1000
	_check(view.advance(200.1), "Next faction frame uses the invalidated deadline")
	view.update_fog(200.1, [])
	await RenderingServer.frame_post_draw
	_check_observation(view, capture.factionCases[2], "Next faction frame")
	_check_faction_marks(view, viewport, capture.factionCases[2], "Next faction frame")
	view.vision.pulse_until = 0
	_check(view.advance(200.35), "Normal fog frame is due after the pulse")
	view.update_fog(200.35, [])
	view.toggle_mode()
	view.side = ""
	await RenderingServer.frame_post_draw
	_check_observation(view, capture.factionCases[2], "Pending observer frame")
	_check_faction_marks(view, viewport, capture.factionCases[2], "Pending observer frame")
	var crop: Array = capture.factionCases[2].crop
	_check(view.fog_view.overlay.visible and not view.fog_view.full_reveal.visible
		and view.fog_view.seen_region.region.position.distance_to(Vector2(crop[0], crop[1])) < .002
		and view.fog_view.seen_region.region.size.distance_to(Vector2(crop[2], crop[3])) < .002,
		"Pending observer mode retains the committed faction fog crop")
	_check(view.advance(200.45), "Observer toggle invalidates the source deadline")
	view.update_fog(200.45, [])
	await RenderingServer.frame_post_draw
	_check(not view.fog_view.overlay.visible and not view.fog_view.full_reveal.visible
		and not view.observations.back().commands.any(func(command): return command.shape == "polygon"),
		"The next observer frame removes fog and its own-view arrow")
	viewport.free()

func _check_faction_marks(view: Probe, viewport: SubViewport, expected: Dictionary, description: String) -> void:
	if view.observations.is_empty():
		return
	var arrows: Array = view.observations.back().commands.filter(func(command): return command.shape == "polygon")
	_check(arrows.size() == 1, description + " draws one own-view arrow")
	if arrows.size() == 1:
		var point: Array = expected.arrow.point
		_check(Vector2(arrows[0].position[0], arrows[0].position[1]).distance_to(Vector2(point[0], point[1])) < .002
			and absf(float(arrows[0].rotation) - float(expected.arrow.rotation)) < .000001,
			description + " retains the original arrow position and heading")
	var image := viewport.get_texture().get_image()
	_check(image != null, description + " renders its missile marker")
	if image != null:
		image.save_png(evidence_dir.path_join("minimap-frame-" + ("near" if expected.name == "faction-near" else "full") + ".png"))
		var point: Array = expected.missiles[0]
		var colour := image.get_pixel(int(floorf(point[0])), int(floorf(point[1])))
		var source_colour := Color(String(expected.missileColour))
		_check(absf(colour.r - source_colour.r) < .02 and absf(colour.g - source_colour.g) < .02
			and absf(colour.b - source_colour.b) < .02,
			description + " retains the original missile position")
		var green_pixels := 0
		var neutral_pixels := 0
		for y in range(image.get_height() - 16, image.get_height() - 1):
			for x in range(3, mini(90, image.get_width())):
				var pixel := image.get_pixel(x, y)
				if pixel.g > .15 and pixel.g > pixel.r + .05 and pixel.g > pixel.b + .08:
					green_pixels += 1
				if pixel.r > .15 and absf(pixel.r - pixel.g) < .04 and absf(pixel.g - pixel.b) < .05:
					neutral_pixels += 1
		_check(green_pixels > 0 if String(expected.label).begins_with("周遭") else green_pixels == 0 and neutral_pixels > 0,
			description + " retains the original full/near legend colour")

func _check_observation(view: Probe, expected: Dictionary, description: String) -> void:
	_check(not view.observations.is_empty(), description + " draws a minimap canvas")
	if view.observations.is_empty():
		return
	var actual: Dictionary = view.observations.back()
	var rect := Rect2(Vector2(expected.window.x0, expected.window.z0),
		Vector2(expected.window.x1 - expected.window.x0, expected.window.z1 - expected.window.z0))
	_check((actual.window.position as Vector2).distance_to(rect.position) < .002 and (actual.window.size as Vector2).distance_to(rect.size) < .002,
		description + " uses the original committed window")
	_check(view.base_window.position.distance_to(rect.position) < .002 and view.base_window.size.distance_to(rect.size) < .002,
		description + " keeps the terrain crop in the same window")
	var crop := MinimapWindow.texture_region(view.map_data.bounds, view.base_window, view.size)
	var source_crop: Array = expected.crop
	_check(crop.position.distance_to(Vector2(source_crop[0], source_crop[1])) < .002
		and crop.size.distance_to(Vector2(source_crop[2], source_crop[3])) < .002, description + " retains the original terrain crop")
	var lane: PackedVector2Array = actual.lane
	_check(lane.size() == 2, description + " keeps both original lane points")
	if lane.size() == 2:
		for index in lane.size():
			var point: Array = expected.lanes[0][index]
			_check(lane[index].distance_to(Vector2(point[0], point[1])) < .002, description + " keeps lane and terrain projections together")
	var towers: Array = actual.commands.filter(func(command): return command.shape == "rect" and command.rect[2] == 6)
	_check(towers.size() == 1, description + " draws one source tower")
	if towers.size() == 1:
		var marker := Vector2(float(towers[0].rect[0]) + 3, float(towers[0].rect[1]) + 3)
		var point: Array = expected.markers[0]
		_check(marker.distance_to(Vector2(point[0], point[1])) < .002, description + " keeps marker and terrain projections together")
	var bunkers: Array = actual.commands.filter(func(command): return command.shape == "rect" and command.fill and command.rect[2] == 5)
	_check(bunkers.size() == 1, description + " draws one remembered bunker")
	if bunkers.size() == 1:
		var marker := Vector2(float(bunkers[0].rect[0]) + 2.5, float(bunkers[0].rect[1]) + 2.5)
		var point: Array = expected.bunkers[0]
		_check(marker.distance_to(Vector2(point[0], point[1])) < .002, description + " retains the original bunker frame")

func _finish_frame() -> void:
	print("MINIMAP_FRAME assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
