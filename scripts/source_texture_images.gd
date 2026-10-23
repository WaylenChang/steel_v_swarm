class_name SourceTextureImages
extends RefCounted

var images: Array[Image] = []
var variants: Dictionary = {}

func configure(captures: Array) -> bool:
	images.clear()
	variants.clear()
	for capture: Dictionary in captures:
		var image := _decode_level(capture)
		if image == null:
			return false
		if capture.has("mipmaps"):
			var layout := Image.create_empty(image.get_width(), image.get_height(), true, image.get_format())
			if layout == null or layout.is_empty():
				push_error("Cannot allocate original manual texture mip storage")
				return false
			if not capture.mipmaps is Array or capture.mipmaps.size() != layout.get_mipmap_count():
				push_error("Incomplete original manual texture mip chain")
				return false
			var bytes := image.get_data()
			var size := image.get_size()
			for level: Dictionary in capture.mipmaps:
				size = Vector2i(maxi(size.x >> 1, 1), maxi(size.y >> 1, 1))
				var mip := _decode_level(level)
				if mip == null or mip.get_size() != size:
					push_error("Invalid original manual texture mip extent")
					return false
				bytes.append_array(mip.get_data())
			if bytes.size() != layout.get_data_size():
				push_error("Original manual texture mip bytes do not match native storage")
				return false
			image = Image.create_from_data(image.get_width(), image.get_height(), not capture.mipmaps.is_empty(), image.get_format(), bytes)
			if image == null or image.is_empty():
				push_error("Cannot create original manual texture mip storage")
				return false
			image.set_meta("source_manual_mipmaps", true)
		images.append(image)
	return true

static func _decode_level(capture: Dictionary) -> Image:
	var width := int(capture.get("width", 0))
	var height := int(capture.get("height", 0))
	if width <= 0 or height <= 0 or width > Image.MAX_WIDTH or height > Image.MAX_HEIGHT:
		push_error("Missing/invalid original texture dimensions")
		return null
	var image := Image.new()
	if capture.has("rgba"):
		var bytes := Marshalls.base64_to_raw(capture.rgba)
		if bytes.size() != width * height * 4:
			push_error("Invalid original RGBA texture byte count")
			return null
		image = Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, bytes)
	elif capture.has("png"):
		if image.load_png_from_buffer(Marshalls.base64_to_raw(capture.png)) != OK:
			push_error("Invalid original texture PNG")
			return null
	else:
		push_error("Missing original texture pixels")
		return null
	if image == null or image.is_empty() or image.get_width() != width or image.get_height() != height:
		push_error("Original texture dimensions do not match its pixels")
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image

static func coordinates(point: Vector2, spec: Dictionary) -> Vector2:
	var matrix: Array = spec.matrix
	var x := float(matrix[0]) * float(point.x) + float(matrix[3]) * float(point.y) + float(matrix[6])
	var y := float(matrix[1]) * float(point.x) + float(matrix[4]) * float(point.y) + float(matrix[7])
	x /= 2 if spec.wrapS == "mirror" else 1
	y /= 2 if spec.wrapT == "mirror" else 1
	var offset: Array = spec.get("nativeTileOffset", [0, 0])
	var span: Array = spec.get("nativeTileSpan", [1, 1])
	return Vector2((x - float(offset[0])) / float(span[0]), (y - float(offset[1])) / float(span[1]))

static func prepare(spec: Dictionary, raw_uv: Array) -> Dictionary:
	var result: Dictionary = spec.duplicate(true)
	if (spec.wrapS == "clamp") == (spec.wrapT == "clamp"):
		return result
	if raw_uv.is_empty() or raw_uv.size() % 2 != 0:
		push_error("Missing UV domain for the original mixed-axis sampler")
		return {}
	# Bake only the finite affine UV domain used by this surface. Native clamp sampling
	# then preserves the clamped axis and repeats the other axis without a runtime sampler.
	var axis := 0 if spec.wrapS != "clamp" else 1
	var low := INF
	var high := -INF
	for index in range(0, raw_uv.size(), 2):
		var point := coordinates(Vector2(raw_uv[index], raw_uv[index + 1]), spec)
		if not point.is_finite():
			push_error("Non-finite original texture domain")
			return {}
		low = minf(low, point[axis])
		high = maxf(high, point[axis])
	if low < -Image.MAX_WIDTH or high > Image.MAX_WIDTH or high - low + 3 > Image.MAX_WIDTH:
		push_error("Original mixed-axis texture domain exceeds native image limits")
		return {}
	var start := floori(low) - 1
	var needed := ceili(high) - start + 1
	var span := 1
	while span < needed:
		span *= 2
	result.nativeTileOffset = [0, 0]
	result.nativeTileSpan = [1, 1]
	result.nativeTileOffset[axis] = start
	result.nativeTileSpan[axis] = span
	return result

func resolve(spec: Dictionary) -> ImageTexture:
	var index := int(spec.image)
	if index < 0 or index >= images.size():
		push_error("Original material references a missing texture image")
		return null
	var span: Array = spec.get("nativeTileSpan", [1, 1])
	var manual := bool(spec.get("manualMipmaps", false))
	var key := JSON.stringify([index, spec.wrapS == "mirror", spec.wrapT == "mirror", spec.flipY, spec.srgb, spec.premultiplyAlpha, spec.mipmaps, manual, span])
	if variants.has(key):
		return variants[key]
	if manual != bool(images[index].get_meta("source_manual_mipmaps", false)) or manual and bool(spec.mipmaps):
		push_error("Original manual mip declaration does not match its captured image")
		return null
	var image := _manual_variant(images[index], spec, span) if manual else _transform_level(images[index], spec, span)
	if image == null:
		return null
	if spec.mipmaps and image.generate_mipmaps() != OK:
		push_error("Cannot generate native mipmaps for the original texture")
		return null
	var texture := ImageTexture.create_from_image(image)
	variants[key] = texture
	return texture

static func _source_level(image: Image, level: int) -> Image:
	if image.get_format() != Image.FORMAT_RGBA8 or level < 0 or level > image.get_mipmap_count():
		push_error("Original image mip level is unavailable")
		return null
	var width := maxi(image.get_width() >> level, 1)
	var height := maxi(image.get_height() >> level, 1)
	var offset := 0 if level == 0 else image.get_mipmap_offset(level)
	return Image.create_from_data(width, height, false, image.get_format(), image.get_data().slice(offset, offset + width * height * 4))

static func _manual_variant(source: Image, spec: Dictionary, span: Array) -> Image:
	var image := _transform_level(_source_level(source, 0), spec, span)
	if image == null:
		return null
	var layout := Image.create_empty(image.get_width(), image.get_height(), true, image.get_format())
	if layout == null or layout.is_empty():
		push_error("Cannot allocate native storage for original manual mips")
		return null
	var bytes := image.get_data()
	for level in range(1, layout.get_mipmap_count() + 1):
		# After the source's terminal 1x1 level, repeat the same authored texel;
		# larger native tiling dimensions must never trigger another downsampler.
		var original := _source_level(source, mini(level, source.get_mipmap_count()))
		var size := Vector2i(maxi(image.get_width() >> level, 1), maxi(image.get_height() >> level, 1))
		var mip := _transform_level(original, spec, span, size)
		if mip == null:
			return null
		bytes.append_array(mip.get_data())
	if bytes.size() != layout.get_data_size():
		push_error("Original transformed mip bytes do not match native storage")
		return null
	return Image.create_from_data(image.get_width(), image.get_height(), layout.get_mipmap_count() > 0, image.get_format(), bytes)

static func _transform_level(source: Image, spec: Dictionary, span: Array, target_size := Vector2i.ZERO) -> Image:
	if source == null:
		return null
	var image: Image = source.duplicate()
	# Three flips source pixels at upload, before sampler wrapping. Flipping UVs
	# instead selects the opposite nearest texel at repeat/mirror boundaries.
	if spec.flipY:
		image.flip_y()
	if spec.premultiplyAlpha:
		image.premultiply_alpha()
	if not spec.srgb:
		# Float storage keeps linear source pixels out of the sRGB texture-view conversion.
		image.convert(Image.FORMAT_RGBAF)
	var mirror_x: bool = spec.wrapS == "mirror" and (target_size == Vector2i.ZERO or image.get_width() > 1)
	var mirror_y: bool = spec.wrapT == "mirror" and (target_size == Vector2i.ZERO or image.get_height() > 1)
	if mirror_x or mirror_y:
		var width := image.get_width()
		var height := image.get_height()
		var tiled := Image.create_empty(width * (2 if mirror_x else 1), height * (2 if mirror_y else 1), false, image.get_format())
		if tiled == null or tiled.is_empty():
			push_error("Original mirrored texture exceeds native image limits")
			return null
		tiled.blit_rect(image, Rect2i(0, 0, width, height), Vector2i.ZERO)
		if mirror_x:
			var horizontal: Image = image.duplicate()
			horizontal.flip_x()
			tiled.blit_rect(horizontal, Rect2i(0, 0, width, height), Vector2i(width, 0))
		if mirror_y:
			var vertical: Image = tiled.get_region(Rect2i(0, 0, tiled.get_width(), height))
			vertical.flip_y()
			tiled.blit_rect(vertical, Rect2i(0, 0, tiled.get_width(), height), Vector2i(0, height))
		image = tiled
	var size := target_size if target_size != Vector2i.ZERO else Vector2i(image.get_width() * int(span[0]), image.get_height() * int(span[1]))
	if size.x <= 0 or size.y <= 0 or size.x > Image.MAX_WIDTH or size.y > Image.MAX_HEIGHT:
		push_error("Original texture domain exceeds native image limits")
		return null
	if size.x % image.get_width() != 0 or size.y % image.get_height() != 0:
		push_error("Original manual mip tiling does not align with native extents; a source shader sampler is required")
		return null
	if size != image.get_size():
		var width := image.get_width()
		var height := image.get_height()
		var tiled := Image.create_empty(size.x, size.y, false, image.get_format())
		if tiled == null or tiled.is_empty():
			push_error("Original mixed-axis texture domain exceeds native image limits")
			return null
		for row in range(size.y / height):
			for column in range(size.x / width):
				tiled.blit_rect(image, Rect2i(0, 0, width, height), Vector2i(column * width, row * height))
		image = tiled
	return image

static func apply_sampling(material: BaseMaterial3D, spec: Dictionary) -> bool:
	if (spec.wrapS == "clamp") != (spec.wrapT == "clamp"):
		if not spec.has("nativeTileSpan"):
			push_error("Original mixed-axis texture domain has not been prepared")
			return false
		material.texture_repeat = false
	else:
		material.texture_repeat = spec.wrapS != "clamp"
	var minimum: String = spec.min
	var nearest := minimum.begins_with("nearest")
	if spec.mag != ("nearest" if nearest else "linear"):
		push_error("Different minification/magnification filters require the original shader sampler path")
		return false
	var mipmapped := minimum.contains("mipmap")
	if mipmapped:
		if not spec.mipmaps and not spec.get("manualMipmaps", false):
			push_error("Original manually supplied mip levels have not been captured")
			return false
		var nearest_mip := bool(ProjectSettings.get_setting("rendering/textures/default_filters/use_nearest_mipmap_filter", false))
		if minimum.ends_with("nearest") != nearest_mip:
			push_error("Mixed mip selection requires the original shader sampler path")
			return false
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS if nearest else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		if float(spec.anisotropy) > 1 and spec.mag == "linear" and minimum.ends_with("mipmap_linear"):
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC if nearest else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	else:
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST if nearest else BaseMaterial3D.TEXTURE_FILTER_LINEAR
	return true

static func sampler_hint(material: BaseMaterial3D) -> String:
	var filters: Array[String] = ["filter_nearest", "filter_linear", "filter_nearest_mipmap", "filter_linear_mipmap",
		"filter_nearest_mipmap_anisotropic", "filter_linear_mipmap_anisotropic"]
	return filters[int(material.texture_filter)] + (", repeat_enable" if material.texture_repeat else ", repeat_disable")
