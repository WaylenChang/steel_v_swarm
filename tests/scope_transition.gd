extends "res://tests/run.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/scope_transition.json")
	_check(capture.get("formatVersion") == 1 and capture.get("source") is Dictionary and capture.get("programs") is Array,
		"Capture original browser fog transition programs")
	if failures > 0:
		_finish_scope()
		return
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "Scope transition capture is current")
	for path: String in capture.source.sourceInputs:
		_check(provenance.get("inputs", {}).get(path) == capture.source.sourceInputs[path], "Scope transition matches imported CSS")
	if failures > 0:
		_finish_scope()
		return
	for program: Dictionary in capture.programs:
		var duration_key := "fireTransition" if program.channel == "fire" else "weatherTransition"
		_check(Content.balance.view.mask[duration_key] == program.duration, "Native fog duration retains the original CSS value")
		var overlay := ScopeOverlay.new()
		add_child(overlay)
		var state := ScopeState.new()
		var elapsed := 0.0
		var target := -1.0
		for frame: Dictionary in program.frames:
			var changed: bool = target != float(frame.target)
			target = float(frame.target)
			if program.channel == "fire":
				state.fire_fog = target
			else:
				state.weather_fog = target
			overlay.update_view(state, false)
			var tween: Tween = overlay.fire_tween if program.channel == "fire" else overlay.weather_tween
			if changed:
				elapsed = 0.0
			if tween != null and tween.is_valid():
				tween.pause()
				tween.custom_step(maxf(0, float(frame.time) - elapsed))
			elapsed = float(frame.time)
			var opacity: float = overlay.fire_opacity if program.channel == "fire" else overlay.weather_opacity
			_check(absf(opacity - float(frame.opacity)) < .000001, "Original browser ease-out and reversing-shortened fog opacity")
			var parameter: Variant = overlay.shader_material.get_shader_parameter(program.channel + "_opacity")
			_check(absf(float(parameter) - opacity) < .000001, "Native shader receives the presented transition opacity")
		overlay.clear()
		_check(not overlay.visible and overlay.fire_opacity == 0 and overlay.weather_opacity == 0,
			"Clearing fog presentation cancels both channels and discards pending transitions")
		overlay.free()
	await _wall_clock()
	_finish_scope()

func _wall_clock() -> void:
	var previous_scale := Engine.time_scale
	var previous_pause := get_tree().paused
	for sample: Dictionary in [{"name": "zero_speed", "scale": 0.0, "paused": false},
			{"name": "paused_tree", "scale": 1.0, "paused": true},
			{"name": "fast_game", "scale": 5.0, "paused": false}]:
		get_tree().paused = false
		Engine.time_scale = 1.0
		await get_tree().process_frame
		await get_tree().process_frame
		var overlay := ScopeOverlay.new()
		add_child(overlay)
		var state := ScopeState.new()
		state.fire_fog = 1.0
		state.weather_fog = 1.0
		Engine.time_scale = float(sample.scale)
		get_tree().paused = bool(sample.paused)
		overlay.update_view(state, false)
		var started := Time.get_ticks_usec()
		await _wait_wall(.12)
		var elapsed := float(Time.get_ticks_usec() - started) / 1000000.0
		_check(elapsed < .35, "Wall-clock sample precedes the original fire transition deadline: " + String(sample.name))
		if elapsed < .35:
			_check(overlay.fire_opacity > 0 and overlay.fire_opacity < 1 and overlay.weather_opacity > 0 and overlay.weather_opacity < 1,
				"Original CSS fog transitions advance on wall time without early completion: " + String(sample.name)
				+ " elapsed=" + str(elapsed) + " fire=" + str(overlay.fire_opacity) + " weather=" + str(overlay.weather_opacity))
		await _wait_wall(.55)
		_check(absf(overlay.fire_opacity - 1) < .000001 and absf(overlay.weather_opacity - 1) < .000001,
			"Original CSS fog transitions finish on wall time: " + String(sample.name))
		_check(absf(float(overlay.shader_material.get_shader_parameter("fire_opacity")) - overlay.fire_opacity) < .000001
			and absf(float(overlay.shader_material.get_shader_parameter("weather_opacity")) - overlay.weather_opacity) < .000001,
			"Wall-clock transitions update both shader uniforms: " + String(sample.name))
		overlay.clear()
		overlay.free()
	get_tree().paused = previous_pause
	Engine.time_scale = previous_scale

func _wait_wall(seconds: float) -> void:
	var deadline := Time.get_ticks_usec() + int(seconds * 1000000.0)
	while Time.get_ticks_usec() < deadline:
		await get_tree().process_frame

func _finish_scope() -> void:
	print("SCOPE_TRANSITION assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
