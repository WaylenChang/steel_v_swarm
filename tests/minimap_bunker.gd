extends "res://tests/run.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/minimap_bunker.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(DisplayServer.get_name() != "headless", "Bunker memory requires a real display driver")
	_check(capture.get("formatVersion") == 1 and capture.get("frames") is Array and capture.frames.size() == 7,
		"Capture original bunker memory snapshot sequences")
	if failures == 0:
		for path: String in capture.source.inputs:
			var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(text.sha256_text() == capture.source.inputs[path], "Current bunker capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original bunker input: " + path)
	if failures == 0:
		await _frames(capture.frames)
	print("MINIMAP_BUNKER assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _frames(frames: Array) -> void:
	var viewport := SubViewport.new()
	viewport.disable_3d = true
	viewport.size = Vector2i(220, 220)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var view = preload("res://scripts/minimap.gd").new()
	viewport.add_child(view)
	var map := {"bounds": {"minX": -200, "maxX": 200, "minZ": -200, "maxZ": 200}, "lanes": []}
	view.configure(map, "STEEL")
	view.cadence.warm_until = 0
	for index in frames.size():
		var frame: Dictionary = frames[index]
		var rows: Array = []
		for row: Dictionary in frame.rows:
			rows.append({"kind": row.k, "position": Vector3(row.x, 0, -float(row.z)), "side": row.s,
				"id": rows.size() + 1, "character": "", "peer": 0, "hp": 1, "special": {}})
		var previous: Array = view.draw_frame.get("bunkers", []).duplicate(true)
		view.accept_snapshot({"units": rows, "events": [], "vision_side": "STEEL"})
		_check(view.draw_frame.get("bunkers", []) == previous, "An accepted snapshot cannot mutate an already committed map frame")
		var keys: Array = view.markers.bunkers.keys()
		_check(keys.size() == frame.records.size(), "Original bunker deduplication and persistence count")
		for i in range(mini(keys.size(), frame.records.size())):
			var source: Dictionary = frame.records[i]
			var native: Dictionary = view.markers.bunkers[keys[i]]
			_check(keys[i] == source.key, "Original rounded bunker key and insertion order")
			_check(native.point == Vector2(source.x, source.z) and native.side == source.side,
				"Original bunker world coordinates, axis inversion and latest allegiance")
		_check(view.advance(100 + index * .3), "The next source map frame is due")
		var committed: Array = view.draw_frame.bunkers
		_check(committed.size() == frame.records.size(), "The map draw commits every remembered bunker")
		for i in range(mini(committed.size(), frame.records.size())):
			var expected: Dictionary = frame.records[i]
			_check(committed[i].point == Vector2(expected.x, expected.z) and committed[i].side == expected.side,
				"The committed map frame retains the original bunker record")
		var commands: Array = view._commands_for(view.draw_frame, view.draw_frame.positions)
		var bunker_fills := commands.filter(func(command: Dictionary):
			return command.shape == "rect" and command.fill and float(command.rect[2]) == 5.0)
		_check(bunker_fills.size() == frame.markers.size(), "Every source bunker is drawn once")
		for i in range(mini(bunker_fills.size(), frame.markers.size())):
			var original: Dictionary = frame.markers[i]
			var actual: Dictionary = bunker_fills[i]
			for component in range(4):
				_check(absf(float(actual.rect[component]) - float(original.rect[component])) < .000000000001,
					"Original source bunker marker geometry and order")
			var colour: Array = actual.colour
			_check(Color(colour[0], colour[1], colour[2], colour[3]).is_equal_approx(Color(original.color)),
				"Original source bunker faction color")
		await RenderingServer.frame_post_draw
	view.clear()
	_check(view.markers.bunkers.is_empty() and view.draw_frame.is_empty(), "Leaving the map retires remembered bunker state")
	view.configure(map, "SWARM")
	_check(view.markers.bunkers.is_empty(), "A new match starts with no remembered bunkers")
	view.clear()
	viewport.free()
