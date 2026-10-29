extends Node

var assertions := 0
var failures := 0

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("FAILURE: " + label)

func _ready() -> void:
	await _run_acceptance()
	print("FLASH_SETTINGS_ACCEPTANCE assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func _run_acceptance() -> void:
	var visual_fixture: Dictionary = Content.read_json("res://tests/fixtures/visual_preferences.json")
	var fixtures: Dictionary = Content.read_json("res://data/fixtures.json", ["mobilePreferences", "mobileTouchPreferences", "audioPreferences"])
	var audio_rules: Dictionary = Content.balance.audio

	await _test_visual_settings(visual_fixture)
	await _test_control_settings(fixtures)
	await _test_audio_settings(audio_rules, fixtures)

func _test_visual_settings(fixture: Dictionary) -> void:
	var presets: Array = fixture.metadata.presets
	var default_preset_id: String = fixture.metadata.defaultPreset
	_check(not presets.is_empty(), "Visual presets declared in fixture")

	for orientation: Vector2 in [Vector2(1280, 720), Vector2(720, 1280)]:
		var container := Control.new()
		container.size = orientation
		add_child(container)

		var vs := VisualSettings.new()
		container.add_child(vs)
		vs.configure(Visuals)
		await get_tree().process_frame

		_check(vs.preset_select != null, "VisualSettings preset dropdown created")
		_check(vs.preset_select.item_count == presets.size(), "All declared visual presets present in dropdown")

		# Check actual declared preset labels and metadata
		for i: int in range(presets.size()):
			var preset: Dictionary = presets[i]
			_check(vs.preset_select.get_item_metadata(i) == preset.id, "Preset option %d metadata matches %s" % [i, preset.id])
			_check(vs.preset_select.get_item_text(i) == preset.label, "Preset option %d label matches %s" % [i, preset.label])

		# Select a non-default declared preset
		var non_default: Dictionary = presets[1] if presets[0].id == default_preset_id else presets[0]
		var non_default_index := -1
		for i: int in range(vs.preset_select.item_count):
			if vs.preset_select.get_item_metadata(i) == non_default.id:
				non_default_index = i
				break
		_check(non_default_index >= 0, "Found declared non-default preset index")

		vs.preset_select.select(non_default_index)
		vs.preset_select.item_selected.emit(non_default_index)
		_check(Visuals.preset_id == non_default.id, "GUI selection switched VisualPreferences preset")
		_check(not Visuals.is_default(), "VisualPreferences not default after selecting non-default preset")
		_check(not vs.reset_button.disabled, "Reset button enabled when preferences modified")

		# Programmatic sync without feedback writes
		var third_preset: Dictionary = presets[2] if presets.size() > 2 else presets[0]
		Visuals.select_preset(third_preset.id)
		_check(vs.preset_select.get_item_metadata(vs.preset_select.selected) == third_preset.id,
			"External preset change programmatically synchronizes dropdown without feedback")

		# World text language selection
		if vs.lang_select != null:
			var knob: Dictionary = fixture.metadata.knobs.worldTextLang
			var choices: Array = knob.choices
			_check(vs.lang_select.item_count == choices.size(), "WorldTextLang dropdown populates all choices")
			for c_idx: int in range(choices.size()):
				vs.lang_select.select(c_idx)
				vs.lang_select.item_selected.emit(c_idx)
				_check(Visuals.value("worldTextLang") == choices[c_idx], "Selecting language %s updates preference" % choices[c_idx])

		# Reset button
		vs.reset_button.pressed.emit()
		_check(Visuals.is_default(), "Reset button restores VisualPreferences to default")
		_check(Visuals.preset_id == default_preset_id, "Reset restores default preset ID: " + default_preset_id)
		_check(vs.reset_button.disabled, "Reset button disabled when preferences at default")

		container.remove_child(vs)
		vs.free()
		remove_child(container)
		container.free()

func _test_control_settings(fixtures: Dictionary) -> void:
	for orientation: Vector2 in [Vector2(1280, 720), Vector2(720, 1280)]:
		var container := Control.new()
		container.size = orientation
		add_child(container)

		var preferences := ControlPreferences.new()
		preferences.configure(Content.balance.mobile)
		preferences.persist = false
		var gyro := NativeGyro.new()
		gyro.configure(preferences)
		var cs := ControlSettings.new()
		container.add_child(cs)
		cs.configure(preferences, gyro)
		await get_tree().process_frame

		_check(cs.mode_select != null, "ControlSettings creates mode selector")
		_check(cs.scheme_select != null, "ControlSettings creates scheme selector")
		_check(cs.mode_select.item_count == preferences.rules.modeKeys.size(), "Mode selector populates all declared modes")
		_check(cs.scheme_select.item_count == preferences.rules.schemeKeys.size(), "Scheme selector populates all declared schemes")

		# Autowrap checks for status labels in narrow layouts
		_check(cs.mode_status.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART, "Mode status has smart word wrapping")
		_check(cs.gyro_status.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART, "Gyro status has smart word wrapping")

		# Test scheme selection GUI
		for i: int in range(cs.scheme_select.item_count):
			var scheme_key: String = cs.scheme_select.get_item_metadata(i)
			cs.scheme_select.select(i)
			cs.scheme_select.item_selected.emit(i)
			_check(preferences.scheme() == scheme_key, "Selecting scheme %s updates preferences" % scheme_key)

		# Test switches and sliders
		for def: Dictionary in preferences.rules.settings:
			var key: String = def.key
			if def.type == "switch" and cs.widgets.has(key):
				var btn: CheckButton = cs.widgets[key]
				btn.set_pressed(true)
				btn.toggled.emit(true)
				if key == "gyro" and not NativeGyro.supported():
					_check(preferences.values.get("gyro") == false, "Unsupported desktop platform sets gyro preference false")
					_check(cs.gyro_status.text == Content.label("gyro_unsupported"), "Gyro status shows gyro_unsupported")
				else:
					_check(preferences.values.get(key) == true, "Switch %s updates preference to true" % key)
				btn.set_pressed(false)
				btn.toggled.emit(false)
				_check(preferences.values.get(key) == false, "Switch %s updates preference to false" % key)
			elif def.type == "range" and cs.widgets.has(key):
				var slider: SpinBox = cs.widgets[key]
				_check(slider.min_value == def.min, "Range %s min matches declared" % key)
				_check(slider.max_value == def.max, "Range %s max matches declared" % key)
				slider.value = (def.min + def.max) / 2.0
				slider.value_changed.emit(slider.value)
				_near(float(preferences.values.get(key)), slider.value / 100.0, "Slider %s updates percentage" % key)

		# Programmatic sync without feedback writes
		preferences.set_value("invertX", true)
		if cs.widgets.has("invertX"):
			var inv_btn: CheckButton = cs.widgets.invertX
			_check(inv_btn.button_pressed == true, "Programmatic sync updates invertX checkbox")

		container.remove_child(cs)
		cs.free()
		gyro.free()
		preferences.free()
		remove_child(container)
		container.free()

func _test_audio_settings(rules: Dictionary, _fixtures: Dictionary) -> void:
	for orientation: Vector2 in [Vector2(1280, 720), Vector2(720, 1280)]:
		var container := Control.new()
		container.size = orientation
		add_child(container)

		var preferences := AudioPreferences.new()
		preferences.configure(rules)
		preferences.persist = false

		var as_panel := AudioSettings.new()
		container.add_child(as_panel)
		as_panel.configure(preferences)
		await get_tree().process_frame

		_check(as_panel.widgets.has("sfx") and as_panel.widgets.has("bgm"), "AudioSettings creates both sfx and bgm channel widgets")
		_check(as_panel.master_button != null, "AudioSettings creates master toggle button")

		for channel: String in ["sfx", "bgm"]:
			var def: Dictionary = rules.settings[channel]
			var slider: HSlider = as_panel.widgets[channel].slider
			var switch: CheckButton = as_panel.widgets[channel].switch
			var label: Label = as_panel.widgets[channel].label

			_check(slider.min_value == def.minimum, "%s slider minimum matches rules" % channel)
			_check(slider.max_value == def.maximum, "%s slider maximum matches rules" % channel)
			_check(slider.step == def.step, "%s slider step matches rules" % channel)

			# GUI slider change
			slider.value = 45.0
			as_panel._volume_changed(channel, slider.value)
			var current_vol: float = preferences.sfx_volume if channel == "sfx" else preferences.bgm_volume
			_near(current_vol, 0.45, "%s volume updated to 45%%" % channel)
			_check(label.text == "45%", "%s label formatted as 45%%" % channel)

			# Toggle switch
			switch.button_pressed = false
			switch.toggled.emit(false)
			var is_on: bool = preferences.sfx_on if channel == "sfx" else preferences.bgm_on
			_check(not is_on, "%s channel switch toggles off" % channel)

		# Master button toggle
		var initial_master_text: String = as_panel.master_button.text
		as_panel.master_button.pressed.emit()
		_check(as_panel.master_button.text != initial_master_text, "Master button toggles caption on press")

		# Programmatic sync without feedback writes
		preferences.set_sfx(0.72)
		_check(as_panel.widgets.sfx.slider.value == 72, "External audio change programmatically synchronizes slider")
		_check(as_panel.widgets.sfx.label.text == "72%", "External audio change updates volume label")

		container.remove_child(as_panel)
		as_panel.free()
		remove_child(container)
		container.free()

func _near(a: float, b: float, label: String, tol := 0.001) -> void:
	_check(absf(a - b) <= tol, "%s (expected %f, got %f)" % [label, b, a])
