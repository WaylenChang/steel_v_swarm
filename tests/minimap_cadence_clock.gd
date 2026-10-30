extends "res://tests/run.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/minimap_cadence_clock.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(capture.get("formatVersion") == 1 and capture.get("programs") is Array and capture.programs.size() == 4,
		"Capture original fractional minimap clock cases")
	if failures == 0:
		for path: String in capture.source.inputs:
			var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(text.sha256_text() == capture.source.inputs[path], "Current minimap clock capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original minimap clock source: " + path)
	if failures == 0:
		for program: Dictionary in capture.programs:
			_check_program(program)
	print("MINIMAP_CADENCE_CLOCK assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_program(program: Dictionary) -> void:
	var exact := MinimapCadence.new()
	var production := MinimapCadence.new()
	var initial := _double(program.initBits)
	exact.configure(initial / 1000.0)
	# configure() and main's draw call currently read integer ticks_msec.
	production.configure(floorf(initial) / 1000.0)
	_check(exact.warm_until == _double(program.warmUntilBits), "Original warm deadline: " + String(program.name))
	for frame: Dictionary in program.frames:
		var milliseconds := _double(frame.msBits)
		var exact_due := exact.advance(milliseconds / 1000.0)
		var production_due := production.advance(floorf(milliseconds) / 1000.0)
		_check(exact_due == bool(frame.due) and exact.last == _double(frame.lastBits),
			"Original double cadence: " + String(program.name) + " at " + str(frame.ms))
		_check(production_due == bool(frame.due),
			"Production millisecond cadence: " + String(program.name) + " at " + str(frame.ms))

func _double(hex: String) -> float:
	return hex.hex_decode().decode_double(0)
