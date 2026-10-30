extends "res://tests/run.gd"

const Portrait = preload("res://scripts/dialogue_radio_portrait.gd")

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/dialogue_portrait.json")
	var data: Dictionary = Content.read_json("res://data/dialogue_portrait.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(DisplayServer.get_name() != "headless", "Portrait transitions require a real display driver")
	_check(capture.get("formatVersion") == 1 and capture.get("programs") is Array and capture.programs.size() == 8,
		"Capture original browser portrait transitions")
	_check(data == {"formatVersion": capture.get("formatVersion"), "source": capture.get("source"), "rules": capture.get("rules")},
		"Runtime portrait values retain original CSS")
	if failures == 0:
		for path: String in capture.source.inputs:
			var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(text.sha256_text() == capture.source.inputs[path], "Current portrait capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original portrait input: " + path)
	if failures == 0:
		for program: Dictionary in capture.programs:
			_check_program(program, data.rules)
		await _integration(data.rules)
	print("DIALOGUE_PORTRAIT assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _check_program(program: Dictionary, rules: Dictionary) -> void:
	var portrait := Portrait.new()
	portrait.rules = rules
	add_child(portrait)
	portrait.set_speaking(program.initial, true)
	_check(absf(portrait.opacity - float(program.initialOpacity)) < .000001, "Original initial endpoint before first paint")
	var target: bool = program.initial
	var elapsed := 0.0
	for frame: Dictionary in program.frames:
		var changed: bool = target != bool(frame.on)
		target = bool(frame.on)
		portrait.set_speaking(target)
		if changed:
			elapsed = 0.0
		if portrait.tween != null and portrait.tween.is_valid():
			portrait.tween.pause()
			portrait.tween.custom_step(maxf(0.0, float(frame.time) - elapsed))
		elapsed = float(frame.time)
		_check(absf(portrait.opacity - float(frame.opacity)) < .000001,
			"Original CSS opacity easing and reversal: actual=" + str(portrait.opacity) + " expected=" + str(frame.opacity))
		_check(absf(portrait.modulate.a - portrait.opacity) < .000001, "Portrait alpha tracks its source value in the same frame")
		if portrait.tween != null and portrait.tween.is_valid():
			_check(absf(float(rules.duration) * float(portrait.transition.shortening) - float(frame.duration)) < .000001,
				"Original CSS reversal duration")
	portrait.free()

func _integration(rules: Dictionary) -> void:
	var view := CampaignDialogue.new()
	add_child(view)
	var scene := {"title": "", "note": "", "lines": [{"ch": "t06", "t": "First"}, {"ch": "s01", "t": "Second"}]}
	view.radio(scene)
	_check(view.portraits.size() == 2 and absf(view.portraits[0].modulate.a - float(rules.active)) < .000001
		and absf(view.portraits[1].modulate.a - float(rules.inactive)) < .000001,
		"Initial real radio displays the source speaker endpoints immediately")
	view._step()
	_check(view.portraits[0].get("tween") != null and view.portraits[1].get("tween") != null,
		"Switching the real radio animates both speaker endpoints")
	var previous_scale := Engine.time_scale
	var previous_pause := get_tree().paused
	Engine.time_scale = 0.0
	get_tree().paused = true
	var deadline := Time.get_ticks_usec() + 300000
	while Time.get_ticks_usec() < deadline:
		await get_tree().process_frame
	_check(absf(view.portraits[0].modulate.a - float(rules.inactive)) < .000001
		and absf(view.portraits[1].modulate.a - float(rules.active)) < .000001,
		"Portrait transitions continue during paused zero-speed gameplay")
	get_tree().paused = previous_pause
	Engine.time_scale = previous_scale
	view.portraits[0].call("set_speaking", true)
	var retired: Tween = view.portraits[0].get("tween")
	_check(retired != null and retired.is_valid(), "Replacement test starts an active portrait transition")
	view.clear()
	_check(retired == null or not retired.is_valid(), "Clearing the radio retires portrait transitions")
	view.free()
