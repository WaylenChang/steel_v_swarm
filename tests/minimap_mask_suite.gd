extends RefCounted

const Helper = preload("res://tests/status_suite.gd")

static func run(h: Node, fixtures: Dictionary) -> void:
	if not MinimapWindow.available() or not fixtures.has("minimapFog"):
		h._check(false, "Regenerate original minimap fog canvas sequences and reveal geometry")
		return
	var source: Dictionary = fixtures.minimapFog
	var canvas := Vector2(source.size[0], source.size[1])
	var widget := MinimapFog.new()
	h.add_child(widget)
	widget.configure(canvas)
	h._check(widget.explored.get_parent() == widget.current and widget.current.get_parent() == widget,
		"Native viewport nesting orders scratch pages, explored history, fog composition and HUD sampling")
	var query := SourceBlockerQuery.new()
	for frame: Dictionary in source.frames:
		if frame.get("reset", false):
			widget.configure(canvas)
		var window := Rect2(Vector2(frame.window.x0, frame.window.z0), Vector2(frame.window.x1 - frame.window.x0, frame.window.z1 - frame.window.z0))
		var pulse := float(frame.now) < float(frame.pulseUntil)
		if not String(frame.side).is_empty() and not pulse:
			query.configure(frame.blockers)
			var shadows: Array = []
			for item: Array in frame.sources:
				var point := Vector2(item[0], item[1])
				shadows.append(MinimapVision.shadows(point, item[2], query.near(point, item[2])))
			for plan: Dictionary in MinimapRevealPlan.build(frame.sources, shadows, source.terrain, window, canvas):
				var matches: Array = frame.reveals.filter(func(reveal): return int(reveal.source) == int(plan.source) and reveal.soft == plan.soft)
				h._check(matches.size() == 1, "Each native cropped mask retains its original source and explored/current phase")
				if matches.size() != 1:
					continue
				var expected: Dictionary = matches[0]
				Helper.compare(h, [plan.center.x, plan.center.y], expected.center, "Original full/view ellipse center")
				Helper.compare(h, [plan.radius.x, plan.radius.y], expected.radius, "Original independent axis scaling and six-pixel minimum")
				var polygons: Array = []
				for polygon: PackedVector2Array in plan.polygons:
					var points: Array = []
					for point: Vector2 in polygon:
						points.append([point.x, point.y])
					polygons.append(points)
				Helper.compare(h, polygons, expected.polygons, "Original per-source shadow cutouts projected into their own coordinate frame")
				h._check(plan.clip.has_area() and Rect2(Vector2.ZERO, canvas).encloses(plan.clip), "Native scratch tiles cover only the visible portion of a reveal")
		widget.update_view(frame.sources, source.terrain, window, frame.side, pulse, frame.blockers)
		if String(frame.side).is_empty():
			h._check(not widget.overlay.visible and widget.explored.render_target_update_mode == SubViewport.UPDATE_DISABLED,
				"Observers skip fog and do not add exploration")
		elif pulse:
			h._check(widget.full_reveal.visible and not widget.overlay.visible and widget.explored.render_target_update_mode == SubViewport.UPDATE_ONCE,
				"Reconnaissance records the whole map without applying fog")
		else:
			h._check(widget.overlay.visible and not widget.full_reveal.visible and widget.current.render_target_update_mode == SubViewport.UPDATE_ONCE,
				"Normal views compose their retained exploration and source-local current reveals")
			for page: Dictionary in widget.atlas.pages:
				h._check(page.viewport.get_parent().get_viewport() == widget.explored, "Scratch viewports finish before their mask consumers")
	widget.clear()
	h._check(not widget.configured and not widget.overlay.visible and widget.atlas.pages.is_empty() and widget.blockers.entries.is_empty(),
		"Room disposal releases all source scratch pages and disables old mask sampling")
	h._check(widget.explored.render_target_clear_mode == SubViewport.CLEAR_MODE_ONCE, "Next room starts with an empty persistent mask")
	widget.free()
	_packing(h, canvas)

static func _packing(h: Node, canvas: Vector2) -> void:
	var sizes := PackedVector2Array()
	for index in 40:
		sizes.append(canvas)
	var pages := MinimapMaskAtlas._pack(sizes)
	var indices: Array = []
	for page: Dictionary in pages:
		indices.append_array(page.indices)
		h._check(page.atlas.size.x <= MinimapMaskAtlas.PAGE_EDGE and page.atlas.size.y <= MinimapMaskAtlas.PAGE_EDGE,
			"Atlas pages bound texture dimensions without truncating source count")
		var rectangles: Array[Rect2] = []
		for index in page.indices.size():
			var rect := Rect2(page.atlas.points[index], canvas)
			for previous: Rect2 in rectangles:
				h._check(not rect.intersects(previous), "Native atlas packing isolates adjacent source scratch masks")
			rectangles.append(rect)
	h._check(indices == range(40), "Every source remains in its original draw order across atlas pages")
