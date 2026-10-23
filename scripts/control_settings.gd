class_name ControlSettings
extends VBoxContainer

var preferences: ControlPreferences
var gyro: NativeGyro
var widgets: Dictionary = {}
var mode_select: OptionButton
var scheme_select: OptionButton
var view_select: OptionButton
var gyro_status: Label
var mode_status: Label
var power_switch: CheckButton

func configure(settings: ControlPreferences, sensor: NativeGyro) -> void:
	preferences = settings
	gyro = sensor
	add_child(NativeUi.label(Content.label("input_settings"), 22))
	mode_select = _pick("control_mode", preferences.rules.modeKeys, preferences.rules.modes)
	mode_select.item_selected.connect(func(index):
		var mode: String = mode_select.get_item_metadata(index)
		if Session.active:
			if Session.set_control_mode(mode):
				preferences.set_pref(mode)
		else:
			preferences.set_pref(mode))
	mode_status = NativeUi.label("")
	mode_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(mode_status)
	scheme_select = _pick("control_scheme", preferences.rules.schemeKeys, preferences.rules.schemes)
	scheme_select.item_selected.connect(func(index): preferences.set_scheme(scheme_select.get_item_metadata(index)))
	if Content.balance.has("playerView"):
		view_select = _pick("view_mode", Content.balance.playerView.modeKeys, Content.balance.playerView.modes)
		view_select.item_selected.connect(func(index): preferences.set_view_pref(view_select.get_item_metadata(index)))
	for group: String in ["lookPrefs", "movePrefs"]:
		for key: String in preferences.rules[group]:
			_switch(key, preferences.rules[group][key].label, preferences.rules[group][key].hint)
	for key: String in ["lefty", "screenLefty"]:
		_switch(key, Content.label("touch_" + key), Content.label("touch_" + key + "_hint"))
	for definition: Dictionary in preferences.rules.settings:
		var key: String = definition.key
		if definition.type == "switch":
			_switch(key, definition.label, definition.get("hint", ""))
		elif definition.type == "seg":
			var choices: Dictionary = {}
			for option: String in definition.opts:
				choices[option] = {"label": definition.optLabel[option], "hint": definition.get("hint", "")}
			var select := _pick_caption(definition.label, definition.opts, choices)
			widgets[key] = select
			select.item_selected.connect(func(index): preferences.set_value(key, select.get_item_metadata(index)))
		elif definition.type == "range":
			var slider := SpinBox.new()
			slider.min_value = definition.min
			slider.max_value = definition.max
			slider.step = 1
			slider.suffix = "%"
			_row_caption(definition.label, slider)
			widgets[key] = slider
			slider.value_changed.connect(func(value): preferences.set_value(key, value / 100.0))
	gyro_status = NativeUi.label("")
	gyro_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(gyro_status)
	if preferences.rules.has("lowPower"):
		power_switch = CheckButton.new()
		power_switch.text = preferences.rules.lowPower.label
		power_switch.toggled.connect(preferences.set_low_power)
		add_child(power_switch)
	preferences.changed.connect(_sync)
	preferences.power_changed.connect(_sync)
	preferences.view_changed.connect(func(_value): _sync())
	gyro.status_changed.connect(func(_key): _sync())
	Session.lobby_changed.connect(_sync)
	_sync()

func _switch(key: String, caption: String, hint: String) -> void:
	var button := CheckButton.new()
	button.text = caption
	button.tooltip_text = hint
	button.toggled.connect(func(on):
		if key == "gyro":
			gyro.set_preference(on)
			_sync()
		else:
			preferences.set_value(key, on))
	widgets[key] = button
	add_child(button)

func _row_caption(caption: String, control: Control) -> void:
	var row := HBoxContainer.new()
	var label := NativeUi.label(caption)
	label.custom_minimum_size.x = 190
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	add_child(row)

func _pick(key: String, keys: Array, choices: Dictionary) -> OptionButton:
	return _pick_caption(Content.label(key), keys, choices)

func _pick_caption(caption: String, keys: Array, choices: Dictionary) -> OptionButton:
	var control := OptionButton.new()
	for key: String in keys:
		control.add_item(choices[key].label)
		control.set_item_metadata(control.item_count - 1, key)
		control.set_item_tooltip(control.item_count - 1, choices[key].get("hint", ""))
	_row_caption(caption, control)
	return control

func _select(control: OptionButton, value: String) -> void:
	for index: int in range(control.item_count):
		if control.get_item_metadata(index) == value:
			control.select(index)
			return

func _sync() -> void:
	if power_switch != null:
		power_switch.set_pressed_no_signal(preferences.low_power())
	if view_select != null:
		_select(view_select, preferences.view_pref)
	_select(mode_select, preferences.mode())
	mode_select.disabled = Session.active and (not Session.is_room_host() or Session.reconnecting or Session.leaving)
	var mode := preferences.mode()
	mode_status.text = Content.label("control_room" if not preferences.room.is_empty() else "control_default")
	if mode != preferences.rules.defaultMode and mode != preferences.detected_scheme():
		mode_status.text += "\n" + Content.label("control_mismatch_" + mode)
	_select(scheme_select, preferences.scheme())
	scheme_select.disabled = preferences.mode() != preferences.rules.defaultMode
	for key: String in widgets:
		var control: Control = widgets[key]
		if control is CheckButton:
			control.set_pressed_no_signal(bool(preferences.values[key]) and (key != "gyro" or NativeGyro.supported()))
		elif control is SpinBox:
			control.set_value_no_signal(float(preferences.values[key]) * 100)
		elif control is OptionButton:
			_select(control, preferences.values[key])
	gyro_status.text = Content.label(gyro.status)
