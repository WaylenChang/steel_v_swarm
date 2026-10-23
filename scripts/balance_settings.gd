class_name BalanceSettings
extends VBoxContainer

var preferences: BalancePreferences
var widgets: Dictionary = {}
var reset_button: Button

func configure(profile: BalancePreferences) -> void:
	preferences = profile
	for group: Dictionary in preferences.rules.ui.groups:
		var heading := NativeUi.label(group.title, 19)
		heading.tooltip_text = group.hint
		add_child(heading)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child(grid)
		for key: String in group.keys:
			var definition: Dictionary = preferences.rules.knobs[key]
			var column := VBoxContainer.new()
			column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			column.tooltip_text = definition.hint
			grid.add_child(column)
			var caption := NativeUi.label(definition.label, 15)
			caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			column.add_child(caption)
			var row := HBoxContainer.new()
			column.add_child(row)
			var slider := HSlider.new()
			slider.min_value = definition.min
			slider.max_value = definition.max
			slider.step = definition.step
			slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slider.tooltip_text = definition.hint
			slider.set_meta("balance_key", key)
			slider.value_changed.connect(func(value): preferences.set_value(key, value))
			row.add_child(slider)
			var value_label := NativeUi.label("", 15)
			value_label.custom_minimum_size.x = 48
			row.add_child(value_label)
			widgets[key] = {"slider": slider, "value": value_label}
	reset_button = Button.new()
	reset_button.text = preferences.rules.ui.reset
	reset_button.pressed.connect(preferences.reset)
	add_child(reset_button)
	preferences.changed.connect(_sync)
	_sync(preferences.values)

func _sync(_values: Dictionary) -> void:
	for key: String in widgets:
		var value := preferences.pref(key)
		widgets[key].slider.set_value_no_signal(value)
		widgets[key].value.text = "%.1fx" % value
	reset_button.disabled = preferences.is_default()
