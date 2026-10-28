extends "res://tests/run.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/minimap_window_precision.json")
	_check(capture.get("formatVersion") == 1 and capture.get("cases") is Array and capture.cases.size() == 448,
		"Capture original minimap windows and projections")
	if failures == 0:
		var provenance: Dictionary = Content.read_json("res://data/provenance.json")
		for path: String in capture.source.inputs:
			var hash := FileAccess.get_sha256("res://" + path)
			if path.ends_with(".mjs"):
				hash = FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n").sha256_text()
			_check(hash == capture.source.inputs[path], "Current minimap precision input: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.get("inputs", {}).get(path) == capture.source.sourceInputs[path], "Original minimap source identity: " + path)
	if failures == 0:
		var window_mismatches := 0
		var projection_mismatches := 0
		var full_projection_mismatches := 0
		var crop_mismatches := 0
		var witnesses: Array = []
		for item: Dictionary in capture.cases:
			var terrain := {}
			for key: String in item.boundsBits:
				terrain[key] = str(item.boundsBits[key]).hex_decode().decode_double(0)
			var focus := _vector(item.focusBits)
			var expected := Rect2(_vector(item.windowBits.slice(0, 2)), _vector(item.windowBits.slice(2, 4)))
			var actual := MinimapWindow.bounds(terrain, item.near, focus, item.kind)
			var precise := MinimapWindow.components(terrain, item.near, focus, item.kind)
			var exact := true
			for index in 4:
				var key: String = ["x0", "z0", "x1", "z1"][index]
				exact = exact and _same_component(float(precise[key]), str(item.componentsBits[index]).hex_decode().decode_double(0))
			failure_scope = "components"
			_check(exact, "Original window edges retain their source double values")
			_check(MinimapWindow.label(item.near, float(precise.x1) - float(precise.x0)) == item.label,
				"Original minimap label rounds the double window width")
			var same := actual.position == expected.position and actual.size == expected.size
			if not same:
				window_mismatches += 1
				if witnesses.size() < 8:
					witnesses.append({"map": item.map, "kind": item.kind, "near": item.near,
						"focus": str(focus), "expected": str(expected), "actual": str(actual)})
			failure_scope = "window"
			_check(same, "Original window coordinates round once at the native boundary")
			var crop := MinimapWindow.texture_region(terrain, expected, Vector2(capture.canvas[0], capture.canvas[1]), precise)
			var wanted_crop := Rect2(_vector(item.cropBits.slice(0, 2)), _vector(item.cropBits.slice(2, 4)))
			same = _same_component(crop.position.x, wanted_crop.position.x) and _same_component(crop.position.y, wanted_crop.position.y) \
				and _same_component(crop.size.x, wanted_crop.size.x) and _same_component(crop.size.y, wanted_crop.size.y)
			if not same:
				crop_mismatches += 1
				if witnesses.size() < 8:
					witnesses.append({"map": item.map, "kind": item.kind, "near": item.near,
						"expected_crop": str(wanted_crop), "actual_crop": str(crop)})
			failure_scope = "crop"
			_check(same, "Original texture crop rounds once at the native boundary")
			for projection: Dictionary in item.projections:
				var projected := MinimapWindow.project(_vector(projection.pointBits), expected, Vector2(capture.canvas[0], capture.canvas[1]))
				var wanted := _vector(projection.resultBits)
				same = _same_component(projected.x, wanted.x) and _same_component(projected.y, wanted.y)
				if not same:
					projection_mismatches += 1
					if witnesses.size() < 8:
						witnesses.append({"map": item.map, "kind": item.kind, "near": item.near,
							"point": str(_vector(projection.pointBits)), "expected": str(wanted), "actual": str(projected)})
				failure_scope = "projection"
				_check(same, "Original window projection rounds once at the native boundary")
				var original := _vector(projection.originalBits)
				var point := _vector(projection.pointBits)
				var full_projected := MinimapWindow.project_components(float(point.x), float(point.y), precise, Vector2(capture.canvas[0], capture.canvas[1]))
				same = _same_component(full_projected.x, original.x) and _same_component(full_projected.y, original.y)
				if not same:
					full_projection_mismatches += 1
				failure_scope = "full-projection"
				_check(same, "Original full window projection matches native output")
			if item.reveal != null:
				var reveal_point := _vector(item.reveal.pointBits)
				var plan := MinimapRevealPlan.build([[reveal_point.x, reveal_point.y, item.reveal.radius]], [null],
					terrain, expected, Vector2(capture.canvas[0], capture.canvas[1]), precise)
				failure_scope = "reveal"
				_check(plan.size() == 2, "Original hard and soft reveals remain in the map")
				for entry: Dictionary in plan:
					var reference: Dictionary = item.reveal.soft if entry.soft else item.reveal.hard
					_check(entry.center == _vector(reference.centerBits), "Original reveal center reaches the mask boundary")
					_check(entry.radius == _vector(reference.radiusBits), "Original reveal radii reach the mask boundary")
		print("MINIMAP_WINDOW_PRECISION mismatches=", window_mismatches, " projections=", projection_mismatches, " crops=", crop_mismatches,
			" full_projections=", full_projection_mismatches, " witnesses=", JSON.stringify(witnesses))
		await _check_live_frame(capture)
	print("MINIMAP_WINDOW_PRECISION assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_live_frame(capture: Dictionary) -> void:
	var sample: Dictionary = {}
	for item: Dictionary in capture.cases:
		if item.map == "berlin" and item.kind == "robot" and item.near and item.projections[0].originalBits != item.projections[0].resultBits:
			sample = item
			break
	_check(not sample.is_empty(), "Capture includes a real-map frame with a meaningful precision boundary")
	if sample.is_empty():
		return
	var terrain := {}
	for key: String in sample.boundsBits:
		terrain[key] = str(sample.boundsBits[key]).hex_decode().decode_double(0)
	var canvas := Vector2(capture.canvas[0], capture.canvas[1])
	_check(canvas == Vector2(Content.balance.minimap.canvas[0], Content.balance.minimap.canvas[1]),
		"The live canvas retains the original HTML dimensions")
	var first := _vector(sample.projections[0].pointBits)
	var second := _vector(sample.projections[1].pointBits)
	var viewport := SubViewport.new()
	viewport.disable_3d = true
	viewport.size = Vector2i(canvas)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var view = preload("res://scripts/minimap.gd").new()
	viewport.add_child(view)
	view.configure({"bounds": terrain, "lanes": []}, "STEEL")
	view.near = true
	view.focus = _vector(sample.focusBits)
	view.hero_kind = sample.kind
	view.view_peer = 17
	view.cadence.warm_until = 0
	var position := Vector3(first.x, 0, first.y)
	view.state = {"units": [{"id": 7, "kind": "tower", "side": "STEEL", "character": "", "peer": 17,
		"hp": 1, "position": position, "special": {}}]}
	view.positions = {7: position}
	_check(view.lane_view.configure([{"grade": "ground", "lane": 0, "points": [[first.x, first.y], [second.x, second.y]]}]),
		"Bind the precise frame's source lane")
	_check(view.advance(100), "The precise source frame is due")
	terrain.minX = float(terrain.minX) + 123.75
	view.update_fog(100, [])
	await RenderingServer.frame_post_draw
	var expected_crop := Rect2(_vector(sample.cropBits.slice(0, 2)), _vector(sample.cropBits.slice(2, 4)))
	_check(view.fog_view.seen_region.region == expected_crop, "The live fog uses the committed source crop after terrain changes")
	var expected_first := _vector(sample.projections[0].originalBits)
	var expected_second := _vector(sample.projections[1].originalBits)
	var lane: PackedVector2Array = view.lane_view.lines[0].points
	_check(lane.size() == 2 and lane[0] == expected_first and lane[1] == expected_second,
		"The live lane uses the committed source window")
	var commands: Array = view._commands_for(view.draw_frame, view.draw_frame.positions)
	var towers := commands.filter(func(command): return command.shape == "rect" and command.rect[2] == 6)
	_check(towers.size() == 1, "The precise frame retains its source tower marker")
	if towers.size() == 1:
		_check(Vector2(float(towers[0].rect[0]) + 3, float(towers[0].rect[1]) + 3) == expected_first,
			"The live marker uses the committed source window")
	for index in 4:
		var key: String = ["x0", "z0", "x1", "z1"][index]
		_check(float(view.draw_frame.window_components[key]) == str(sample.componentsBits[index]).hex_decode().decode_double(0),
			"The scheduled frame retains its original double window edge")
	viewport.free()

func _vector(bits: Array) -> Vector2:
	return Vector2(str(bits[0]).hex_decode().decode_float(0), str(bits[1]).hex_decode().decode_float(0))

func _same_component(actual: float, expected: float) -> bool:
	return actual == expected or is_nan(actual) and is_nan(expected)
