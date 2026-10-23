extends RefCounted

const MapView = preload("res://scripts/minimap.gd")
const Helper = preload("res://tests/status_suite.gd")

static func run(h: Node, fixtures: Dictionary) -> void:
	if not MinimapWindow.available() or not fixtures.has("minimapWindows") or not fixtures.has("minimapToggles") or not fixtures.has("minimapMarkers") or not fixtures.has("minimapMemory") or not fixtures.has("minimapCadence") or not fixtures.has("minimapLabels") or not fixtures.has("minimapLanes"):
		h._check(false, "Regenerate original minimap display-window and shared-toggle references")
		return
	for item: Dictionary in fixtures.minimapWindows:
		var center := Vector2(item.position[0], item.position[1])
		var window := MinimapWindow.bounds(item.terrain, item.mode == "near", center, item.kind if item.kind != null else "")
		Helper.compare(h, [window.position.x, window.position.y, window.end.x, window.end.y],
			[item.window.x0, item.window.z0, item.window.x1, item.window.z1], "Original near/full window uses authored unit sight, fixed aim margin and independent axis clamps")
		var full := MinimapWindow.bounds(item.terrain, false, center, "")
		var crop := MinimapWindow.texture_region(item.terrain, window, Vector2(250, 220))
		var crop_start: Array = item.points[3].full
		var crop_end: Array = item.points[4].full
		h._check(crop.position.distance_to(Vector2(crop_start[0], crop_start[1])) < .002 and crop.end.distance_to(Vector2(crop_end[0], crop_end[1])) < .002,
			"Native terrain texture crop matches the original full-map coordinates for the selected window")
		for row: Dictionary in item.points:
			var point := Vector2(row.point[0], row.point[1])
			var current := MinimapWindow.project(point, window, Vector2(250, 220))
			var full_point := MinimapWindow.project(point, full, Vector2(250, 220))
			h._check(current.distance_to(Vector2(row.current[0], row.current[1])) < .002,
				"Native projection matches original current-window coordinates within float32 subpixel precision")
			h._check(full_point.distance_to(Vector2(row.full[0], row.full[1])) < .002,
				"Full-map coordinates stay independent of the current vicinity window")
	_markers(h, fixtures)
	_cadence(h, fixtures)
	_lanes(h, fixtures)
	for frame: Dictionary in fixtures.minimapLabels:
		h._check(MinimapWindow.label(frame.mode == "near", frame.width) == frame.text.text,
			"Original full/vicinity legend and positive-half metre rounding")
	var view := MapView.new()
	h.add_child(view)
	view.size = Vector2(250, 220)
	var map := {"bounds": {"minX": -2000, "maxX": 2000, "minZ": -1500, "maxZ": 1500}, "lanes": []}
	view.configure(map, "STEEL")
	var panel_size: Vector2 = view.size
	h._check(panel_size == Vector2(Content.balance.minimap.canvas[0], Content.balance.minimap.canvas[1]), "Minimap canvas dimensions come from the authored source HTML")
	h._check(view.base_canvas.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR, "Native base-map interpolation matches source image smoothing")
	var touch := NativeTouchControls.new()
	h.add_child(touch)
	for row: Dictionary in fixtures.minimapToggles:
		view.cadence.last = 7
		var message := view.toggle_mode()
		touch.set_map_near(view.near)
		h._check(view.near == (row.mode == "near") and touch.map_near == row.active and message == row.message,
			"One mode transition supplies keyboard/touch state and the original localized notice")
		h._check(view.size == panel_size, "Map mode changes world coverage without resizing the HUD panel")
		h._near(view.cadence.last, row.last, "Shared map toggle resets the original draw deadline")
	view.focus = Vector2(900, 800)
	view.hero_kind = "robot"
	view.state = {"units": [{"id": 5}]}
	view.missile_points = [Vector3.ONE]
	view.markers.bunkers["old"] = {"point": Vector2.ONE, "side": "GUER"}
	view.vision.pulse_until = 999
	view.configure(map, "")
	h._check(not view.draw_enabled and view.cadence.last == 0, "A fresh room clears retained canvas commands and starts its own warmup gate")
	h._check(view.vision.pulse_until == 0, "A fresh room cannot inherit the previous room's reconnaissance pulse")
	h._check(not view.near and view.focus == Vector2.ZERO and view.hero_kind.is_empty() and view.state.is_empty() and view.missile_points.is_empty() and view.markers.bunkers.is_empty(),
		"A fresh room resets map mode, view focus and old entity presentation")
	h._check(view.clip_contents, "Native canvas clipping contains near-window lanes and markers")
	view.clear()
	h._check(view.map_data.is_empty() and view.base_texture == null and not view.fog_view.configured and view.fog_view.atlas.pages.is_empty(),
		"Leaving a room releases the map raster and scratch pages and stops fog sampling")
	touch.free()
	view.free()

static func _lanes(h: Node, fixtures: Dictionary) -> void:
	for program: Dictionary in fixtures.minimapLanes:
		var classified := MinimapLaneState.classify(program.lanes, {
			"tunnel": func(x: float, _z: float): return program.cases[int(x)].tunnel,
			"deck": func(x: float, _z: float): return program.cases[int(x)].deck,
			"ground": func(x: float, _z: float): return program.cases[int(x)].ground})
		Helper.compare(h, classified, program.classified, "Original lane grading uses the shared samples, closed-tunnel precedence and strict floor/ceiling/deck thresholds")
		var groups := MinimapLaneState.groups(classified, program.ids)
		var view := MinimapLanes.new()
		h.add_child(view)
		if not view.configure(groups):
			h._check(false, "Bind native minimap lane resources")
			view.free()
			continue
		view.update_window(Rect2(0, 0, 250, 220), Vector2(250, 220))
		h._check(view.lines.size() == program.strokes.size(), "Source grade changes split the same polyline spans and include their shared boundary sample")
		for index in mini(view.lines.size(), program.strokes.size()):
			var line: Line2D = view.lines[index]
			var expected: Dictionary = program.strokes[index]
			var points: Array = []
			for point: Vector2 in line.points:
				points.append([point.x, point.y])
			Helper.compare(h, points, expected.points, "Original lane path order, null/short lanes and grade-boundary spans")
			h._check(line.default_color.to_html(false) == String(expected.colour).trim_prefix("#"), "Original lane IDs wrap through the authored neutral color palette")
			h._near(line.default_color.a, expected.alpha, "Original lane opacity")
			h._near(line.width, expected.width, "Original lane stroke width")
			h._check(line.begin_cap_mode == Line2D.LINE_CAP_NONE and line.end_cap_mode == Line2D.LINE_CAP_NONE
				and line.joint_mode == Line2D.LINE_JOINT_SHARP and line.antialiased, "Native lane paths preserve source butt caps, miter joins and antialiasing")
			h._near(line.sharp_limit, Content.balance.minimap.context.miterLimit, "Native miter cutoff comes from the original canvas context")
			if expected.dash.is_empty():
				h._check(line.texture == null, "Ground lanes use a solid native polyline")
			else:
				h._check(line.texture != null and line.texture_mode == Line2D.LINE_TEXTURE_TILE and line.texture_repeat == CanvasItem.TEXTURE_REPEAT_ENABLED,
					"Bridge/tunnel lanes use native tiled textures")
				if line.texture != null:
					var image := line.texture.get_image()
					var period := line.width * float(image.get_width()) / float(image.get_height())
					h._near(period, float(expected.dash[0]) + float(expected.dash[1]), "Native Line2D tile aspect retains the source dash-plus-gap period")
					var ink := 0
					for x in image.get_width():
						if image.get_pixel(x, 0).a > 0:
							ink += 1
					h._near(period * float(ink) / float(image.get_width()), expected.dash[0], "Native repeated alpha image retains the source unequal dash/gap lengths")
		var retained := view.lines.duplicate()
		view.update_window(Rect2(10, 20, 125, 110), Vector2(250, 220))
		h._check(view.lines == retained, "Window changes update cached native lane nodes rather than allocating per-frame paths")
		view.clear()
		h._check(view.lines.is_empty() and view.textures.is_empty() and view.get_child_count() == 0, "Room reset releases old lane nodes and texture bindings")
		view.free()

static func _cadence(h: Node, fixtures: Dictionary) -> void:
	for program: Dictionary in fixtures.minimapCadence:
		var cadence := MinimapCadence.new()
		cadence.configure(program.configuredAt)
		h._near(cadence.warm_until, program.warmUntil, "Original three-second minimap startup window")
		for frame: Dictionary in program.frames:
			if frame.invalidate:
				cadence.invalidate()
			h._check(cadence.advance(frame.now) == frame.due, "Original warm/steady draw gate, exact transition, skipped frames and toggle invalidation")
			h._near(cadence.last, frame.last, "Skipped minimap draws do not advance their source deadline")

static func _markers(h: Node, fixtures: Dictionary) -> void:
	for program: Dictionary in fixtures.minimapMarkers:
		var rows: Array = []
		for row: Dictionary in program.rows:
			rows.append({"kind": row.kind, "side": row.side, "hero": row.hero, "self": row.isSelf,
				"neutral": row.neutral, "point": Vector2(row.point[0], row.point[1])})
		var known: Array = []
		for row: Dictionary in program.bunkers:
			known.append({"side": row.side, "point": Vector2(row.x, row.z)})
		var own: Variant = Vector2(program.own[0], program.own[1]) if program.own != null else null
		var commands := MinimapMarkerState.commands(rows, program.viewer, known, own, program.yaw)
		Helper.compare(h, commands, program.commands,
			"Original faction fills, enemy outlines, hero/aircraft rings, base/tower/bunker squares, own yaw and order-dependent stroke widths")
	var memory := MinimapMarkerState.new()
	for frame: Dictionary in fixtures.minimapMemory:
		var rows: Array = []
		for row: Dictionary in frame.rows:
			rows.append({"kind": row.k, "position": Vector3(row.x, 0, -row.z), "side": row.s})
		memory.remember(rows)
		h._check(memory.bunkers.size() == frame.entries.size(), "Discovered bunker memory survives fog/removal and deduplicates a respawn at its quantized location")
		for index in frame.entries.size():
			var expected: Dictionary = frame.entries[index]
			h._check(memory.bunkers.keys()[index] == expected.key, "Bunker memory preserves original insertion order and negative-half rounding")
			var actual: Dictionary = memory.bunkers.values()[index]
			Helper.compare(h, [actual.point.x, actual.point.y, actual.side], [expected.x, expected.z, expected.side],
				"Bunker memory keeps world Z orientation and the latest observed owner")
