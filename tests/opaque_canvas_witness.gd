extends RefCounted

static func compare(actual: Image, expected: Image) -> Dictionary:
	if actual.get_format() not in [Image.FORMAT_RGB8, Image.FORMAT_RGBA8] or expected.get_format() not in [Image.FORMAT_RGB8, Image.FORMAT_RGBA8]:
		return {}
	var first_image := actual.duplicate() as Image
	var second_image := expected.duplicate() as Image
	first_image.convert(Image.FORMAT_RGBA8)
	second_image.convert(Image.FORMAT_RGBA8)
	var first := first_image.get_data()
	var second := second_image.get_data()
	var maximum := 0
	var pixels := 0
	for offset in range(0, first.size(), 4):
		if first[offset + 3] != 255 or second[offset + 3] != 255:
			return {}
		var error := maxi(absi(first[offset] - second[offset]),
			maxi(absi(first[offset + 1] - second[offset + 1]), absi(first[offset + 2] - second[offset + 2])))
		maximum = maxi(maximum, error)
		if error > 2:
			pixels += 1
	return {"maximumChannelBytes": maximum, "pixelsOverTwoBytes": pixels}
