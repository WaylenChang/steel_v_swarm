class_name AudioSettings
extends VBoxContainer

var preferences: AudioPreferences
var widgets: Dictionary = {}
var master_button: Button

func configure(profile: AudioPreferences) -> void:
	preferences = profile
	for channel: String in ["sfx", "bgm"]:
		var definition: Dictionary = preferences.rules.settings[channel]
		var row := HBoxContainer.new()
		add_child(row)
		var switch := CheckButton.new()
		switch.text = definition.label
		switch.tooltip_text = definition.toggleLabel
		switch.toggled.connect(func(value):
			if channel == "sfx":
				preferences.set_sfx_on(value)
			else:
				preferences.set_bgm_on(value))
		row.add_child(switch)
		var slider := HSlider.new()
		slider.min_value = definition.minimum
		slider.max_value = definition.maximum
		slider.step = definition.step
		slider.tooltip_text = definition.volumeLabel
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed.connect(func(value): _volume_changed(channel, value))
		row.add_child(slider)
		var label := NativeUi.label("", 15)
		label.custom_minimum_size.x = 48
		row.add_child(label)
		widgets[channel] = {"switch": switch, "slider": slider, "label": label}
	master_button = Button.new()
	master_button.pressed.connect(func(): preferences.set_master_on(not ControlPreferences.truthy(preferences.master_on())))
	add_child(master_button)
	preferences.changed.connect(_sync)
	_sync("", preferences.snapshot())

func _volume_changed(channel: String, percent: float) -> void:
	if channel == "sfx":
		preferences.set_sfx(percent / 100.0)
		if percent > 0 and not ControlPreferences.truthy(preferences.sfx_on):
			preferences.set_sfx_on(true)
	else:
		preferences.set_bgm(percent / 100.0)
		if percent > 0 and not ControlPreferences.truthy(preferences.bgm_on):
			preferences.set_bgm_on(true)

func _sync(_operation: String, values: Dictionary) -> void:
	for channel: String in widgets:
		var volume: Variant = values.sfxVol if channel == "sfx" else values.bgmVol
		var enabled: Variant = values.sfxOn if channel == "sfx" else values.bgmOn
		widgets[channel].switch.set_pressed_no_signal(ControlPreferences.truthy(enabled))
		var number := VisualPreferences._number(volume)
		var slider: HSlider = widgets[channel].slider
		# HTML range inputs replace a nonfinite assignment with their midpoint.
		var percent := floorf(number * 100.0 + .5) if is_finite(number) else (slider.min_value + slider.max_value) / 2.0
		slider.set_value_no_signal(percent)
		widgets[channel].label.text = "%d%%" % int(slider.value)
	master_button.text = preferences.rules.settings.masterOff if ControlPreferences.truthy(values.masterOn) else preferences.rules.settings.masterOn
