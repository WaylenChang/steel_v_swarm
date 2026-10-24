extends "res://tests/run.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/dialogue_fonts.json")
	var theme := load("res://assets/fonts/dialogue_theme.res") as Theme
	var report: Array = []
	_check(theme != null, "Load published fonts for strict source advance checks")
	if theme != null:
		for sample: Dictionary in capture.metrics:
			var font := theme.default_font if int(sample.weight) == 400 else theme.get_font("font", "DialogueHeader")
			var line := TextLine.new()
			line.add_string(sample.text, font, int(sample.size), capture.source.language)
			var width := TextServerManager.get_primary_interface().shaped_text_get_width(line.get_rid())
			var advances := 0.0
			for glyph: Dictionary in TextServerManager.get_primary_interface().shaped_text_get_glyphs(line.get_rid()):
				advances += float(glyph.advance) * int(glyph.repeat)
			report.append({"text": sample.text, "size": sample.size, "weight": sample.weight, "source": sample.width, "native": width, "glyphAdvances": advances})
			_near(width, sample.width, "Original browser font advance")
	DirAccess.make_dir_recursive_absolute("res://build/dialogue_fonts")
	var file := FileAccess.open("res://build/dialogue_fonts/metrics-report.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	print("DIALOGUE_FONT_METRICS assertions=", assertions, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
