extends RefCounted

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("visualPreferencePrograms") or not fixtures.has("marineVisualPrograms") or not Content.balance.has("visual"):
		h._check(false, "Regenerate original visual catalog and preference transaction programs")
		return
	for program: Dictionary in fixtures.visualPreferencePrograms:
		var saved := {}
		if program.raw is String:
			var parser := JSON.new()
			if parser.parse(program.raw) == OK and parser.data is Dictionary:
				saved = parser.data
		var preferences := VisualPreferences.new()
		preferences.persist = false
		preferences.configure(Content.balance.visual, saved)
		var notifications := {"count": 0}
		preferences.changed.connect(func(current: Dictionary):
			notifications.count += 1
			h._check(current.is_read_only() and current == preferences.snapshot(), "Visual preset notification observes one immutable, fully committed snapshot"))
		_state(h, preferences, program.initial)
		for frame: Dictionary in program.frames:
			var call: Array = frame.call
			var result: Variant = _apply(preferences, call)
			h._check(result == frame.result, "Original visual setter/preset return value and invalid-setting handling")
			_state(h, preferences, frame)
			h._check(notifications.count == int(frame.notifications) and preferences.revision == int(frame.notifications),
				"Original visual changes emit once atomically; unchanged setters/reset do not emit")
			h._check(preferences.saved_values() == frame.saved, "Only source preset/signage language persist; renderer overrides remain session-only")
			var restored := VisualPreferences.new()
			restored.persist = false
			restored.configure(Content.balance.visual, preferences.saved_values())
			_state(h, restored, frame.reloaded)
			restored.free()
		var copied := preferences.snapshot()
		copied["reflect"] = -999
		h._check(preferences.value("reflect") != -999, "Visual snapshot mutation never changes live preferences")
		var preset := preferences.selected_preset()
		preset.surface.cutWidth = -999
		h._check(preferences.selected_preset().surface.cutWidth != -999, "Visual preset inspection never mutates the source catalog")
		preferences.free()
	_marine(h, fixtures.marineVisualPrograms)

static func _apply(preferences: VisualPreferences, call: Array) -> Variant:
	match call[0]:
		"set":
			return preferences.set_value(call[1], call[2])
		"select":
			return preferences.select_preset(call[1])
		"reset":
			preferences.reset()
	return null

static func _marine(h: Node, programs: Array) -> void:
	for program: Dictionary in programs:
		var preferences := VisualPreferences.new()
		preferences.persist = false
		preferences.configure(Content.balance.visual)
		var shader := Shader.new()
		shader.code = """shader_type spatial;
uniform float uCelCutWidth;
uniform float uCelShadowV;
uniform float uCelRimScale;
uniform vec3 uCelRampTint;
uniform float uCelWSpread;
uniform float uFoamA;
uniform float uRenderStyle;
uniform float uNativeOpacity;
void fragment() { ALBEDO = vec3(0.0); }
"""
		var saved_material := ShaderMaterial.new()
		saved_material.shader = shader
		saved_material.set_shader_parameter("uNativeOpacity", float(program.reflectionAlpha))
		var binding := MarineShaderBinding.new()
		binding.material = saved_material.duplicate()
		# Duplication resolves shader defaults on real renderers; capture the initialized baseline.
		var saved_foam: Variant = saved_material.get_shader_parameter("uFoamA")
		var node := Node3D.new()
		node.visible = false
		var presentation := MarinePresentation.new()
		presentation.appearance = program.appearance
		presentation.bindings.append(binding)
		presentation.reflections.append({"node": node, "binding": binding, "opacity": program.reflectionAlpha})
		for frame: Dictionary in program.frames:
			_apply(preferences, frame.call)
			presentation.sync_visuals(preferences)
			for key: String in frame.uniforms:
				if program.appearance.school == "a" and key in ["uCelCutWidth", "uCelShadowV"]:
					continue
				var expected: Variant = frame.uniforms[key]
				var actual: Variant = binding.material.get_shader_parameter(key)
				if expected is Array:
					h._check(actual is Vector3 and actual.distance_to(Vector3(expected[0], expected[1], expected[2])) < .000001,
						"Original live environment shadow hue and School B minimum preserve source luminance normalization")
				else:
					h._check(actual != null and absf(float(actual) - float(expected)) < .000001,
						"Original live preset cut width/shadow floor, rim, weather spread, foam and render-style index")
			h._check(node.visible == frame.visible and absf(float(binding.material.get_shader_parameter("uNativeOpacity")) - float(frame.opacity)) < .000001,
				"Original reflection visibility/alpha cap, repeated changes, hidden opacity retention and re-enable")
			h._check(saved_material.get_shader_parameter("uFoamA") == saved_foam and float(saved_material.get_shader_parameter("uNativeOpacity")) == float(program.reflectionAlpha),
				"Live visual preferences preserve saved shared marine material parameters")
		node.free()
		preferences.free()

static func _state(h: Node, preferences: VisualPreferences, expected: Dictionary) -> void:
	h._check(preferences.preset_id == expected.preset, "Original curated visual preset selection/fallback")
	h._check(preferences.snapshot() == expected.values, "Original visual catalog, numeric/choice clamping, preset reset and independent signage language")
	h._check(preferences.is_default() == expected.isDefault, "Original visual reset-state detection excludes signage language")
