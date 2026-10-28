extends "res://tests/run.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/scope_values.json")
	_check(capture.get("formatVersion") == 1 and capture.get("samples") is Array and not capture.samples.is_empty(),
		"Capture original browser scope and fog values")
	if failures == 0:
		var provenance: Dictionary = Content.read_json("res://data/provenance.json")
		for path: String in capture.source.inputs:
			var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
			_check(text.sha256_text() == capture.source.inputs[path], "Current scope values capture input: " + path)
		for path: String in capture.source.sourceInputs:
			_check(provenance.get("inputs", {}).get(path) == capture.source.sourceInputs[path], "Original scope values source identity: " + path)
	if failures == 0:
		var overlay := ScopeOverlay.new()
		add_child(overlay)
		var state := ScopeState.new()
		var old_mismatches := {"radius": 0, "blur": 0, "stops": 0}
		for sample: Dictionary in capture.samples:
			state.fire_fog = str(sample.fireBits).hex_decode().decode_double(0)
			state.weather_fog = str(sample.weatherBits).hex_decode().decode_double(0)
			# Inspect settled targets without creating hundreds of asynchronous fades.
			overlay.fire_target = state.fire_fog
			overlay.weather_target = state.weather_fog
			overlay.update_view(state, bool(sample.scoped))
			var material := overlay.shader_material
			failure_scope = str(sample.group) + " fire=" + str(sample.fire) + " weather=" + str(sample.weather)
			var radius := float(material.get_shader_parameter("radius_vmin"))
			var blur := float(material.get_shader_parameter("fire_blur"))
			var expected_radius := str(sample.radiusBits).hex_decode().decode_double(0)
			var expected_blur := str(sample.blurBits).hex_decode().decode_double(0)
			if roundf(ScopeState.radius_vmin(state.fire_fog, state.weather_fog) * 10) / 10 != expected_radius:
				old_mismatches.radius += 1
			if roundf(state.fire_fog * float(Content.balance.view.mask.blurPixels) * 100) / 100 != expected_blur:
				old_mismatches.blur += 1
			if radius != expected_radius or blur != expected_blur:
				print("SCOPE_VALUE_MISMATCH ", JSON.stringify({"input": sample, "radius": radius, "blur": blur}))
			_check(radius == expected_radius, "Original serialized scope radius")
			_check(blur == expected_blur, "Original serialized fire blur")
			if sample.gradient != null:
				if sample.scoped:
					_check(float(material.get_shader_parameter("weather_inner_vmin")) == str(sample.gradient.innerBits).hex_decode().decode_double(0),
						"Original serialized scoped weather inner stop")
				else:
					var expected := Vector2(sample.gradient.stops[0], sample.gradient.stops[1])
					var old := ScopeState.weather_stops(state.weather_fog)
					if Vector2(roundf(old.x * 1000) / 1000, roundf(old.y * 1000) / 1000) != expected:
						old_mismatches.stops += 1
					_check(material.get_shader_parameter("weather_stops") == expected,
						"Original serialized unscoped weather stops")
		for key: String in old_mismatches:
			_check(old_mismatches[key] > 0, "Capture includes a previous precision failure: " + key)
		print("SCOPE_VALUE_PREVIOUS_MISMATCHES ", JSON.stringify(old_mismatches))
		overlay.clear()
		for index in range(2):
			var frame: Dictionary = capture.programs[0][index]
			state.fire_fog = float(frame.fire)
			state.weather_fog = float(frame.weather)
			overlay.update_view(state, bool(frame.scoped))
			if overlay.weather_tween != null and overlay.weather_tween.is_valid():
				overlay.weather_tween.pause()
				overlay.weather_tween.custom_step(1.0 if index == 0 else 0.1)
			var stops := Vector2(frame.gradient.stops[0], frame.gradient.stops[1])
			_check(overlay.shader_material.get_shader_parameter("weather_stops") == stops,
				"Unscoped weather retains its original gradient during fade-out")
			_check(overlay.weather_opacity > 0, "Weather gradient is still visible during its fade")
		overlay.clear()
		overlay.free()
	print("SCOPE_VALUES assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
