extends RefCounted

static func compare(actual: Image, expected: Image, tolerance: float = 2.0 / 255) -> Dictionary:
	assert(actual.get_size() == expected.get_size(), "Raster comparison requires matching dimensions")
	var maximum := 0.0
	var mismatched := 0
	for y in range(expected.get_height()):
		for x in range(expected.get_width()):
			var a := actual.get_pixel(x, y)
			var b := expected.get_pixel(x, y)
			# Native offscreen buffers use premultiplied RGB; browser PNGs use straight RGB.
			var error := maxf(absf(a.a - b.a), maxf(absf(a.r - b.r * b.a),
				maxf(absf(a.g - b.g * b.a), absf(a.b - b.b * b.a))))
			maximum = maxf(maximum, error)
			if error > tolerance:
				mismatched += 1
	return {"pixels": mismatched, "maximum": maximum}

static func diagnostic(actual: Image) -> Image:
	var result := actual.duplicate() as Image
	for y in range(result.get_height()):
		for x in range(result.get_width()):
			var value := result.get_pixel(x, y)
			if value.a > 0:
				result.set_pixel(x, y, Color(value.r / value.a, value.g / value.a, value.b / value.a, value.a))
	return result
