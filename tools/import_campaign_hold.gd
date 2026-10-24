extends Node

func _ready() -> void:
	_import.call_deferred()

func _import() -> void:
	var data: Dictionary = Content.read_json("res://data/campaign_hold.json")
	if data.get("formatVersion") != 1 or not data.get("rules") is Dictionary or not data.get("source") is Dictionary:
		_fail("Capture original cinematic hold presentation first")
		return
	for path: String in data.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		if text.sha256_text() != data.source.inputs[path]:
			_fail("Stale cinematic hold capture input: " + path)
			return
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in data.source.sourceInputs:
		if provenance.inputs.get(path) != data.source.sourceInputs[path]:
			_fail("Cinematic hold source differs from imported metadata: " + path)
			return
	if FileAccess.get_sha256(data.rules.plate) != data.plateSha256:
		_fail("Original cinematic hold backplate changed after capture")
		return
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(data.rules.plate)) != OK or image.get_size() != Vector2i(data.rules.imageSize[0], data.rules.imageSize[1]):
		_fail("Invalid original cinematic hold pixels")
		return
	var texture := ImageTexture.create_from_image(image)
	texture.set_meta("source", data.source)
	texture.set_meta("plateSha256", data.plateSha256)
	if await preload("res://tools/source_resource_publisher.gd").publish(texture, data.rules.image, get_tree()) != OK:
		_fail("Cannot atomically publish cinematic hold backplate")
		return
	var restored := ResourceLoader.load(data.rules.image, "Texture2D", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
	if restored == null or restored.get_image().get_data() != image.get_data() or restored.get_meta("source") != data.source:
		_fail("Cinematic hold backplate reload must retain every source pixel and source identity")
		return
	print("CAMPAIGN_HOLD_IMPORT_PASS pixels=", image.get_width() * image.get_height())
	get_tree().quit(0)

func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
