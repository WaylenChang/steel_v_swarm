extends "res://tests/run.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/spectator_hud_defaults.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(capture.get("formatVersion") == 1 and capture.get("programs") is Array and capture.programs.size() == 6,
		"Capture original spectator HUD defaults")
	for path: String in capture.source.inputs:
		var hash := FileAccess.get_sha256("res://" + path)
		if path.ends_with(".mjs"):
			hash = FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n").sha256_text()
		_check(hash == capture.source.inputs[path], "Current spectator HUD defaults input: " + path)
	for path: String in capture.source.sourceInputs:
		_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original spectator HUD source: " + path)
	var state := SpectatorState.new()
	state.rules = Content.balance.spectator
	state.mode = "fpv"
	state.pid = "17"
	for program: Dictionary in capture.programs:
		var actor: Dictionary = capture.base.duplicate(true)
		actor.merge(program.fields, true)
		if actor.get("cds") is Array:
			for index in actor.cds.size():
				if actor.cds[index] is String and actor.cds[index] == "NaN":
					actor.cds[index] = NAN
		var result: Variant = state.hud([actor])
		_check(result is Dictionary, "Original followed-player HUD is available: " + program.name)
		if result is Dictionary:
			for key: String in program.result:
				_check(_same(result.get(key), program.result[key]), "Original spectator HUD default " + key + ": " + program.name
					+ " native=" + str(result.get(key)) + " source=" + str(program.result[key]))
	print("SPECTATOR_HUD_DEFAULTS assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _same(actual: Variant, expected: Variant) -> bool:
	if expected == null:
		return actual == null
	if expected is Dictionary:
		if not actual is Dictionary or actual.size() != expected.size():
			return false
		for key in expected:
			if not actual.has(key) or not _same(actual[key], expected[key]):
				return false
		return true
	if expected is float or expected is int:
		return (actual is float or actual is int) and float(actual) == float(expected)
	return actual == expected
