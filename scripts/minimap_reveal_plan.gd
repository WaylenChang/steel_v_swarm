class_name MinimapRevealPlan
extends RefCounted

static func build(sources: Array, shadows: Array, terrain: Dictionary, window: Rect2, canvas: Vector2, precise: Dictionary = {}) -> Array:
	var full := MinimapWindow.bounds(terrain, false, Vector2.ZERO, "")
	var precise_full := MinimapWindow.components(terrain, false, Vector2.ZERO, "") if not precise.is_empty() else {}
	var minimum := float(Content.balance.minimap.fog.minimumPixels)
	var result: Array = []
	for index in sources.size():
		var source: Array = sources[index]
		for soft in [false, true]:
			var frame := window if soft else full
			var frame_components: Dictionary = precise if soft else precise_full
			var center: Vector2
			var radius: Vector2
			if frame_components.is_empty():
				center = MinimapWindow.project(Vector2(source[0], source[1]), frame, canvas)
				radius = Vector2(maxf(minimum, float(source[2]) * canvas.x / frame.size.x),
					maxf(minimum, float(source[2]) * canvas.y / frame.size.y))
			else:
				center = MinimapWindow.project_components(float(source[0]), float(source[1]), frame_components, canvas)
				var span_x := float(frame_components.x1) - float(frame_components.x0)
				var span_z := float(frame_components.z1) - float(frame_components.z0)
				radius = Vector2(maxf(minimum, float(source[2]) * (float(canvas.x) / span_x)),
					maxf(minimum, float(source[2]) * (float(canvas.y) / span_z)))
			var first := (center - radius).floor() - Vector2.ONE
			var last := (center + radius).ceil() + Vector2.ONE
			var clip := Rect2(first, last - first).intersection(Rect2(Vector2.ZERO, canvas))
			if not clip.has_area():
				continue
			var polygons: Array[PackedVector2Array] = []
			if shadows[index] != null:
				for polygon: Array in shadows[index]:
					var points := PackedVector2Array()
					for point: Array in polygon:
						points.append(MinimapWindow.project_components(float(point[0]), float(point[1]), frame_components, canvas) \
							if not frame_components.is_empty() else MinimapWindow.project(Vector2(point[0], point[1]), frame, canvas))
					polygons.append(points)
			result.append({"source": index, "soft": soft, "center": center, "radius": radius, "clip": clip, "polygons": polygons})
	return result
