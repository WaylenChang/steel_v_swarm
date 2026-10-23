extends Node

var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Minimap raster comparisons require an active native renderer")
		get_tree().quit(1)
		return
	var fixtures: Dictionary = Content.read_json("res://data/fixtures.json")
	if not fixtures.has("minimapFog") or not MinimapWindow.available():
		push_error("Regenerate original minimap fog raster sequences")
		get_tree().quit(1)
		return
	var source: Dictionary = fixtures.minimapFog
	var canvas := Vector2(source.size[0], source.size[1])
	var target := SubViewport.new()
	target.disable_3d = true
	target.transparent_bg = true
	target.world_2d = World2D.new()
	target.size = Vector2i(canvas)
	target.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(target)
	var background := ColorRect.new()
	background.size = canvas
	background.color = Color8(int(source.background[0]), int(source.background[1]), int(source.background[2]), int(source.background[3]))
	target.add_child(background)
	var fog := MinimapFog.new()
	target.add_child(fog)
	fog.configure(canvas)
	var preview := TextureRect.new()
	preview.texture = target.get_texture()
	preview.position = Vector2(20, 20)
	preview.size = canvas
	add_child(preview)
	DirAccess.make_dir_recursive_absolute("res://tests/minimap-fog")
	for index in source.frames.size():
		var frame: Dictionary = source.frames[index]
		if frame.get("reset", false):
			fog.configure(canvas)
		var window := Rect2(Vector2(frame.window.x0, frame.window.z0), Vector2(frame.window.x1 - frame.window.x0, frame.window.z1 - frame.window.z0))
		var pulse := float(frame.now) < float(frame.pulseUntil)
		fog.update_view(frame.sources, source.terrain, window, frame.side, pulse, frame.blockers)
		target.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		var actual := target.get_texture().get_image()
		var reference := _decode(frame.image)
		if actual == null or reference == null:
			failures.append("Missing native/reference fog frame " + str(index))
			continue
		actual.convert(Image.FORMAT_RGBA8)
		actual.save_png("res://tests/minimap-fog/%02d-native.png" % index)
		reference.save_png("res://tests/minimap-fog/%02d-source.png" % index)
		var maximum := 0.0
		for point: Array in frame.probes:
			var xy := Vector2i(int(point[0]), int(point[1]))
			maximum = maxf(maximum, _error(actual.get_pixelv(xy), reference.get_pixelv(xy)))
		if maximum > 4.0 / 255.0:
			failures.append("Source/native fog color probe mismatch frame=" + str(index) + " delta=" + str(maximum))
		var seen := fog.explored.get_texture().get_image()
		var expected_seen := _decode(frame.seen)
		if seen != null and expected_seen != null:
			seen.save_png("res://tests/minimap-fog/%02d-explored-native.png" % index)
			expected_seen.save_png("res://tests/minimap-fog/%02d-explored-source.png" % index)
			for point: Array in frame.seenProbes:
				var xy := Vector2i(int(point[0]), int(point[1]))
				if absf(seen.get_pixelv(xy).a - expected_seen.get_pixelv(xy).a) > 4.0 / 255.0:
					failures.append("Persistent exploration probe mismatch frame=" + str(index) + " point=" + str(xy))
		else:
			failures.append("Missing persistent exploration frame " + str(index))
		print("MINIMAP_FOG_FRAME_CAPTURED frame=", index, " probeDelta=", maximum)
	if failures.is_empty():
		print("MINIMAP_FOG_PROBES_PASS frames=", source.frames.size(), " fullRasterReviewRequired=true")
	else:
		for failure: String in failures:
			push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)

func _decode(capture: Dictionary) -> Image:
	var codec := SourceTextureImages.new()
	return codec.images[0] if codec.configure([capture]) else null

func _error(first: Color, second: Color) -> float:
	return maxf(maxf(absf(first.r - second.r), absf(first.g - second.g)), maxf(absf(first.b - second.b), absf(first.a - second.a)))
