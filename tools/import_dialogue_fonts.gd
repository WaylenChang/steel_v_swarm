extends Node

func _ready() -> void:
	var error := await _publish()
	if error != OK:
		push_error("Cannot publish source dialogue fonts: " + error_string(error))
	get_tree().quit(0 if error == OK else 1)

func _publish() -> Error:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/dialogue_fonts.json"))
	var licence := "res://build/dialogue_fonts/OFL.txt"
	if FileAccess.get_sha256(licence) != data.source.licence.sha256:
		return ERR_FILE_CORRUPT
	var files: Array[FontFile] = []
	var characters := {}
	var tag := TextServerManager.get_primary_interface().name_to_tag("wght")
	for source: Dictionary in data.fonts:
		var path := "res://build/dialogue_fonts/" + String(source.path)
		if FileAccess.get_sha256(path) != source.sha256:
			return ERR_FILE_CORRUPT
		var font := FontFile.new()
		var error := font.load_dynamic_font(path)
		if error != OK:
			return error
		if font.data != FileAccess.get_file_as_bytes(path) or not font.get_supported_variation_list().has(tag):
			return ERR_INVALID_DATA
		font.allow_system_fallback = false
		font.set_meta("source_sha256", source.sha256)
		files.append(font)
		for character in font.get_supported_chars():
			characters[character.unicode_at(0)] = true
	for code: float in data.glyphs:
		if not characters.has(int(code)):
			push_error("Missing original dialogue font glyph: " + String.chr(int(code)))
			return ERR_INVALID_DATA
	var theme := Theme.new()
	for weight: float in data.weights:
		var variants: Array[Font] = []
		for font in files:
			var variant := FontVariation.new()
			variant.base_font = font
			variant.variation_opentype = {tag: weight}
			variants.append(variant)
		variants[0].fallbacks = variants.slice(1)
		if int(weight) == 400:
			theme.default_font = variants[0]
		else:
			theme.set_type_variation("DialogueHeader", "Label")
			theme.set_font("font", "DialogueHeader", variants[0])
	theme.set_meta("source", data.source)
	theme.set_meta("font_sources", data.fonts)
	theme.set_meta("licence_text", FileAccess.get_file_as_string(licence).replace("\r\n", "\n").replace("\r", "\n"))
	theme.set_meta("producer_sha256", FileAccess.get_file_as_string("res://tools/import_dialogue_fonts.gd").replace("\r\n", "\n").replace("\r", "\n").sha256_text())
	var directory := "res://assets/fonts"
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		return error
	error = DirAccess.copy_absolute(licence, directory + "/dialogue-OFL.txt")
	if error != OK:
		return error
	error = await preload("res://tools/source_resource_publisher.gd").publish(theme, directory + "/dialogue_theme.res", get_tree())
	if error == OK:
		print("DIALOGUE_FONTS_IMPORT_PASS fonts=%d glyphs=%d" % [files.size(), data.glyphs.size()])
	return error
