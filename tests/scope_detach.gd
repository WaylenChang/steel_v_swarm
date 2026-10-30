extends "res://tests/run.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/scope_detach.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(DisplayServer.get_name() != "headless", "Scope detachment requires a real display driver")
	_check(capture.get("formatVersion") == 1 and capture.get("programs") is Array and capture.programs.size() == 16,
		"Capture original CSS scope detach and reattachment")
	if failures == 0:
		for path: String in capture.source.inputs:
			var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(text.sha256_text() == capture.source.inputs[path], "Current scope detach capture: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.inputs.get(path) == capture.source.sourceInputs[path], "Original scope detach input: " + path)
	if failures == 0:
		await _programs(capture.programs)
		_both_channels()
	print("SCOPE_DETACH assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _programs(programs: Array) -> void:
	for program: Dictionary in programs:
		var overlay := ScopeOverlay.new()
		add_child(overlay)
		var state := ScopeState.new()
		var channel := String(program.channel)
		var property := channel + "_opacity"
		var tween_property := channel + "_tween"
		var state_property := channel + "_fog"
		var scoped: bool = float(program.time) == .02
		state.set(state_property, float(program.initial))
		overlay.update_view(state, scoped)
		var initial: Tween = overlay.get(tween_property)
		if initial != null and initial.is_valid():
			initial.pause()
			initial.custom_step(1.0)
		state.set(state_property, float(program.target))
		overlay.update_view(state, scoped)
		var old: Tween = overlay.get(tween_property)
		_check(old != null and old.is_valid(), "Changing source opacity begins a transition")
		if old == null or not old.is_valid():
			overlay.free()
			continue
		old.pause()
		old.custom_step(float(program.time))
		_check(absf(float(overlay.get(property)) - float(program.before)) < .000001,
			"Original browser opacity before detachment")
		remove_child(overlay)
		_check(not old.is_valid() and (program.detachedAnimations == null or int(program.detachedAnimations) == 0),
			"Detachment cancels the original CSS transition")
		add_child(overlay)
		_check(absf(float(overlay.get(property)) - float(program.after)) < .000001,
			"Reattachment presents the original settled target")
		_check(overlay.visible == (scoped or float(program.target) > 0), "Reattached overlay visibility matches its target and scope")
		overlay.update_view(state, scoped)
		var same: Tween = overlay.get(tween_property)
		_check((same == null or not same.is_valid()) and int(program.reattachedAnimations) == 0,
			"Reapplying the unchanged target does not resurrect the retired transition")
		state.set(state_property, float(program.initial))
		overlay.update_view(state, scoped)
		var next: Tween = overlay.get(tween_property)
		_check(next != null and next.is_valid(), "A later target change creates a fresh transition")
		overlay.clear()
		overlay.free()

func _both_channels() -> void:
	var host := Node.new()
	add_child(host)
	var overlay := ScopeOverlay.new()
	host.add_child(overlay)
	var state := ScopeState.new()
	state.fire_fog = 1
	state.weather_fog = 1
	overlay.update_view(state, true)
	var fire := overlay.fire_tween
	var weather := overlay.weather_tween
	fire.pause()
	weather.pause()
	fire.custom_step(.1)
	weather.custom_step(.1)
	var material := overlay.shader_material
	var previous_pause := get_tree().paused
	var previous_scale := Engine.time_scale
	get_tree().paused = true
	Engine.time_scale = 0
	remove_child(host)
	_check(not fire.is_valid() and not weather.is_valid(), "Removing an ancestor cancels both independent transitions")
	_check(overlay.fire_opacity == 1 and overlay.weather_opacity == 1 and overlay.visible,
		"Both detached transitions settle even during paused zero-speed gameplay")
	add_child(host)
	_check(overlay.shader_material == material and float(material.get_shader_parameter("fire_opacity")) == 1
		and float(material.get_shader_parameter("weather_opacity")) == 1,
		"Reattachment keeps its private material and settled channel values")
	get_tree().paused = previous_pause
	Engine.time_scale = previous_scale
	overlay.clear()
	host.free()
