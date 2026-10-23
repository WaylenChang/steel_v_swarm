class_name MinimapRevealPlan
extends RefCounted

static func build(sources: Array, shadows: Array, terrain: Dictionary, window: Rect2, canvas: Vector2) -> Array:
	var full := MinimapWindow.bounds(terrain, false, Vector2.ZERO, "")
	var minimum := float(Content.balance.minimap.fog.minimumPixels)
	var result: Array = []
	for index in sources.size():
		var source: Array = sources[index]
		for soft in [false, true]:
			var frame := window if soft else full
			var center := MinimapWindow.project(Vector2(source[0], source[1]), frame, canvas)
			var radius := Vector2(maxf(minimum, float(source[2]) * canvas.x / frame.size.x),
				maxf(minimum, float(source[2]) * canvas.y / frame.size.y))
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
						points.append(MinimapWindow.project(Vector2(point[0], point[1]), frame, canvas))
					polygons.append(points)
			result.append({"source": index, "soft": soft, "center": center, "radius": radius, "clip": clip, "polygons": polygons})
	return result
