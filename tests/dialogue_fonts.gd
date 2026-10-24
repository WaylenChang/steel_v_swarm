extends "res://tests/run.gd"

func _run() -> void:
	var data: Dictionary = Content.read_json("res://data/dialogue_fonts.json")
	var fixture: Dictionary = Content.read_json("res://tests/fixtures/dialogue_fonts.json")
	_check(data.source == fixture.source and data.fonts == fixture.fonts and data.glyphs == fixture.glyphs, "Native font manifest retains the frozen browser identity and glyph domain")
	for path: String in data.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == data.source.inputs[path], "Font capture input is current")
	var theme := load("res://assets/fonts/dialogue_theme.res") as Theme
	_check(theme != null, "Published native dialogue font Theme reloads")
	if theme != null:
		_check(theme.get_meta("source") == data.source and theme.get_meta("font_sources") == data.fonts, "Reloaded font Theme retains every pinned source response")
		_check(theme.get_meta("producer_sha256") == FileAccess.get_file_as_string("res://tools/import_dialogue_fonts.gd").replace("\r\n", "\n").replace("\r", "\n").sha256_text(), "Font resource was published by the current importer")
		_check(String(theme.get_meta("licence_text")).sha256_text() == data.source.licence.text_sha256, "Published font Theme includes the original copyright and licence")
		var tag := TextServerManager.get_primary_interface().name_to_tag("wght")
		for weight: float in data.weights:
			var font := theme.default_font if int(weight) == 400 else theme.get_font("font", "DialogueHeader")
			_check(font is FontVariation, "Native source weight has its own variation graph")
			var variants: Array[Font] = [font]
			variants.append_array(font.fallbacks)
			_check(variants.size() == data.fonts.size(), "Native fallback graph contains every recorded Unicode subset")
			for index in range(mini(variants.size(), data.fonts.size())):
				var variant := variants[index] as FontVariation
				_check(variant != null and variant.variation_opentype.get(tag) == weight, "Every subset preserves the requested source CSS weight")
				if variant == null:
					continue
				var file := variant.base_font as FontFile
				_check(file != null and not file.allow_system_fallback, "Native font selection cannot silently borrow an unrecorded system font")
				if file == null:
					continue
				var hash := HashingContext.new()
				hash.start(HashingContext.HASH_SHA256)
				hash.update(file.data)
				_check(hash.finish().hex_encode() == data.fonts[index].sha256, "Native font resource embeds the exact original WOFF2 bytes")
				_check(not file.resource_path.contains("/build/"), "Published font has no temporary cache dependency")
			for code: float in data.glyphs:
				_check(font.has_char(int(code)), "Published weight covers every original dialogue character: " + String.chr(int(code)))
	print("DIALOGUE_FONTS assertions=", assertions, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
