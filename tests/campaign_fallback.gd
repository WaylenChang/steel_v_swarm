extends "res://tests/run.gd"

const Raster = preload("res://tests/raster_compare.gd")

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/campaign_fallback.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(DisplayServer.get_name() != "headless", "Cinematic fallback pixels require a real display driver")
	_check(capture.get("formatVersion") == 1 and capture.get("cases") is Array and capture.cases.size() == 12,
		"Capture the original cinematic image stack and missing-image cases")
	if failures == 0:
		for path: String in capture.source.inputs:
			var source := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(source.sha256_text() == capture.source.inputs[path], "Current cinematic fallback capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original cinematic fallback source: " + path)
	if failures == 0:
		await _check_cases(capture)
	print("CAMPAIGN_FALLBACK assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_cases(capture: Dictionary) -> void:
	var textures := {}
	for key: String in capture.textures:
		var image := Image.new()
		_check(image.load_png_from_buffer(Marshalls.base64_to_raw(capture.textures[key])) == OK, "Decode captured source image: " + key)
		textures[key] = ImageTexture.create_from_image(image)
	var stage := SubViewport.new()
	stage.disable_3d = true
	stage.world_2d = World2D.new()
	stage.size = Vector2i(64, 64)
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(stage)
	var backdrop := ColorRect.new()
	backdrop.color = Color8(12, 24, 36)
	backdrop.size = Vector2(64, 64)
	stage.add_child(backdrop)
	for sample: Dictionary in capture.cases:
		var dimensions := Vector2(float(sample.size), float(sample.size))
		stage.size = Vector2i(dimensions)
		backdrop.size = dimensions
		var layer := CampaignArtLayer.new()
		layer.scene = {"img": sample.primary, "fallbackImg": sample.fallback}
		layer.texture_provider = func(path: String, _mipmaps: bool): return textures.get(path)
		stage.add_child(layer)
		layer.layout_art(dimensions)
		layer.select(true)
		if layer.tween != null and layer.tween.is_valid():
			layer.tween.kill()
		layer.opacity = 1
		layer.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		layer.background.hide()
		layer.frame.position = Vector2.ZERO
		layer.frame.size = dimensions
		layer.foreground_clip.position = Vector2.ZERO
		layer.foreground_clip.size = dimensions
		for edge: ColorRect in layer.frame_edges:
			edge.hide()
		for target: TextureRect in [layer.fallback_image, layer.image]:
			target.position = Vector2.ZERO
			target.size = dimensions
			target.scale = Vector2.ONE
			target.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_check(layer.image.texture == textures.get(sample.primary) and layer.fallback_image.texture == textures.get(sample.fallback),
			"Original primary and fallback image bindings: " + String(sample.name))
		for index in range(3):
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
		var actual := stage.get_texture().get_image()
		var expected := Image.new()
		var decoded := expected.load_png_from_buffer(Marshalls.base64_to_raw(sample.png)) == OK and expected.get_size() == actual.get_size()
		_check(decoded, "Captured original fallback raster: " + String(sample.name))
		if decoded:
			var result := Raster.compare(actual, expected)
			if result.pixels > 0:
				for x in range(actual.get_width()):
					var a := actual.get_pixel(x, 0)
					var b := expected.get_pixel(x, 0)
					if absf(a.r - b.r) > 2.0 / 255 or absf(a.g - b.g) > 2.0 / 255 or absf(a.b - b.b) > 2.0 / 255:
						print("CAMPAIGN_FALLBACK_WITNESS ", sample.name, " size=", sample.size, " x=", x, " source=", b, " native=", a)
						break
			_check(result.pixels == 0, "Original ordered image pixels: " + String(sample.name)
				+ " size=" + str(sample.size) + " pixels=" + str(result.pixels) + " maximum=" + str(result.maximum))
		layer.pose = {"scale": 1.17, "x": -3.5, "y": 4.25}
		layer._apply_pose()
		_check(layer.fallback_image.get_transform().is_equal_approx(layer.image.get_transform())
			and layer.fallback_image.size == layer.image.size,
			"Both source image layers share the foreground transform")
		layer.cancel()
		stage.remove_child(layer)
		layer.free()
	stage.free()
