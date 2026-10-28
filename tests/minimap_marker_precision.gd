extends "res://tests/run.gd"

class Probe extends "res://scripts/minimap.gd":
	var drawn: Array = []

	func _draw_map() -> void:
		drawn.clear()
		super._draw_map()

	func _draw_marker(command: Dictionary) -> void:
		drawn.append({"kind": "marker", "command": command.duplicate(true)})
		super._draw_marker(command)

	func _missile_rect(point: Vector3, frame: Dictionary, extent: Vector2) -> Rect2:
		var rect := super._missile_rect(point, frame, extent)
		drawn.append({"kind": "missile", "rect": rect})
		return rect

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/minimap_marker_precision.json")
	_check(capture.get("formatVersion") == 1 and capture.get("cases") is Array and capture.cases.size() == 96,
		"Capture original minimap marker drawing programs")
	if failures == 0:
		var provenance: Dictionary = Content.read_json("res://data/provenance.json")
		for path: String in capture.source.inputs:
			var hash := FileAccess.get_sha256("res://" + path)
			if path.ends_with(".mjs"):
				hash = FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n").sha256_text()
			_check(hash == capture.source.inputs[path], "Current minimap marker precision input: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.get("inputs", {}).get(path) == capture.source.sourceInputs[path], "Original minimap marker source identity: " + path)
	if failures == 0:
		var view = preload("res://scripts/minimap.gd").new()
		var witnesses: Array = []
		var mismatches := 0
		for sample: Dictionary in capture.cases:
			var precise := {}
			for index in 4:
				precise[["x0", "z0", "x1", "z1"][index]] = str(sample.componentsBits[index]).hex_decode().decode_double(0)
			var units: Array = []
			var positions := {}
			for row: Dictionary in sample.rows:
				var point := _vector(row.pointBits)
				var position := Vector3(point.x, 0, point.y)
				positions[int(row.id)] = position
				units.append({"id": row.id, "kind": row.kind, "side": row.side,
					"character": "t01" if row.hero else "", "position": position, "special": {"neutral": row.neutral}})
			var known: Array = []
			for row: Dictionary in sample.bunkers:
				known.append({"side": row.side, "point": _vector(row.pointBits)})
			var frame := {"window": MinimapWindow.rectangle(precise), "window_components": precise,
				"size": Vector2(capture.canvas[0], capture.canvas[1]), "focus": _vector(sample.focusBits),
				"side": sample.viewer, "heading": str(sample.headingBits).hex_decode().decode_double(0),
				"own_id": 6, "units": units, "bunkers": known}
			var native: Array = view._commands_for(frame, positions)
			var arrow: Variant = native.pop_back() if not String(sample.viewer).is_empty() else null
			var commands: Array = []
			for command: Dictionary in native:
				commands.append(_capture_command(command))
			var missile: Dictionary = Content.balance.missile.presentation.minimap
			var extent := Vector2(missile.size[0], missile.size[1])
			for row: Dictionary in sample.missiles:
				var point := _vector(row.pointBits)
				var rect: Rect2 = view._missile_rect(Vector3(point.x, 0, point.y), frame, extent)
				commands.append({"shape": "missile", "fill": true, "rectBits": _rect_bits(rect)})
			if arrow != null:
				commands.append(_capture_command(arrow))
			failure_scope = "marker-precision"
			_check(commands.size() == sample.commands.size(), "Original marker primitive count and ordering")
			for index in mini(commands.size(), sample.commands.size()):
				var same: bool = commands[index] == sample.commands[index]
				if not same:
					mismatches += 1
					if witnesses.size() < 8:
						witnesses.append({"map": sample.map, "viewer": sample.viewer, "index": index,
							"expected": sample.commands[index], "actual": commands[index]})
				_check(same, "Original marker coordinates at the native drawing boundary")
		view.free()
		print("MINIMAP_MARKER_PRECISION mismatches=", mismatches, " witnesses=", JSON.stringify(witnesses))
		await _check_live_frame(capture)
	print("MINIMAP_MARKER_PRECISION assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_live_frame(capture: Dictionary) -> void:
	var sample: Dictionary = {}
	for item: Dictionary in capture.cases:
		if item.map == "berlin" and item.viewer == "STEEL":
			sample = item
			break
	_check(not sample.is_empty(), "Capture includes a real-map faction frame")
	if sample.is_empty():
		return
	var source_windows: Dictionary = Content.read_json("res://tests/fixtures/minimap_window_precision.json")
	var window: Dictionary = {}
	for item: Dictionary in source_windows.cases:
		if item.map == sample.map and item.kind == "robot" and item.near and item.componentsBits == sample.componentsBits \
				and item.focusBits == sample.focusBits:
			window = item
			break
	_check(not window.is_empty(), "The live frame retains its original map bounds")
	if window.is_empty():
		return
	var terrain := {}
	for key: String in window.boundsBits:
		terrain[key] = str(window.boundsBits[key]).hex_decode().decode_double(0)
	var viewport := SubViewport.new()
	viewport.disable_3d = true
	viewport.size = Vector2i(capture.canvas[0], capture.canvas[1])
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var view := Probe.new()
	viewport.add_child(view)
	view.configure({"bounds": terrain, "lanes": []}, sample.viewer)
	view.near = true
	view.focus = _vector(sample.focusBits)
	view.hero_kind = "robot"
	view.heading = str(sample.headingBits).hex_decode().decode_double(0)
	view.own_id = 6
	view.view_peer = 17
	view.cadence.warm_until = 0
	var units: Array = []
	var positions := {}
	for row: Dictionary in sample.rows:
		var point := _vector(row.pointBits)
		var position := Vector3(point.x, 0, point.y)
		positions[int(row.id)] = position
		units.append({"id": row.id, "kind": row.kind, "side": row.side, "peer": 17, "hp": 1,
			"character": "t01" if row.hero else "", "position": position, "special": {"neutral": row.neutral}})
	view.state = {"units": units}
	view.positions = positions
	for index in sample.bunkers.size():
		var row: Dictionary = sample.bunkers[index]
		view.markers.bunkers[str(index)] = {"side": row.side, "point": _vector(row.pointBits)}
	for row: Dictionary in sample.missiles:
		var point := _vector(row.pointBits)
		view.missile_points.append(Vector3(point.x, 0, point.y))
	_check(view.advance(100), "The original marker frame is due")
	view.update_fog(100, [])
	await RenderingServer.frame_post_draw
	var actual: Array = []
	for item: Dictionary in view.drawn:
		if item.kind == "marker":
			actual.append(_capture_command(item.command))
		else:
			actual.append({"shape": "missile", "fill": true, "rectBits": _rect_bits(item.rect)})
	_check(actual.size() == sample.commands.size(), "The live canvas draws every original marker in order")
	for index in mini(actual.size(), sample.commands.size()):
		_check(actual[index] == sample.commands[index], "The live canvas receives the original marker geometry")
	viewport.free()

func _capture_command(command: Dictionary) -> Dictionary:
	var result := {"shape": command.shape, "fill": command.fill}
	match String(command.shape):
		"rect":
			result.rectBits = _rect_bits(Rect2(command.rect[0], command.rect[1], command.rect[2], command.rect[3]))
		"circle":
			result.centerBits = _vector_bits(Vector2(command.center[0], command.center[1]))
			result.radiusBits = _float_bits(float(command.radius))
		"polygon":
			result.positionBits = _vector_bits(Vector2(command.position[0], command.position[1]))
			result.rotationBits = _float_bits(float(command.rotation))
			result.pointsBits = []
			for point: Array in command.points:
				result.pointsBits.append(_vector_bits(Vector2(point[0], point[1])))
	if not command.fill:
		result.widthBits = _float_bits(float(command.width))
	return result

func _vector(bits: Array) -> Vector2:
	return Vector2(str(bits[0]).hex_decode().decode_float(0), str(bits[1]).hex_decode().decode_float(0))

func _float_bits(value: float) -> String:
	var bytes := PackedByteArray()
	bytes.resize(4)
	bytes.encode_float(0, value)
	return bytes.hex_encode()

func _vector_bits(value: Vector2) -> Array:
	return [_float_bits(value.x), _float_bits(value.y)]

func _rect_bits(value: Rect2) -> Array:
	return [_float_bits(value.position.x), _float_bits(value.position.y), _float_bits(value.size.x), _float_bits(value.size.y)]
