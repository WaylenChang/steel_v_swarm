class_name VisualSettings
extends VBoxContainer

var preferences: VisualPreferences
var preset_select: OptionButton
var lang_select: OptionButton
var reset_button: Button
var widgets: Dictionary = {}

func configure(profile: VisualPreferences) -> void:
	preferences = profile
	add_child(NativeUi.label(Content.label("visual_settings"), 22))

	if not preferences.rules.get("presets", []).is_empty():
		var row := HBoxContainer.new()
		var label := NativeUi.label(Content.label("visual_preset"))
		label.custom_minimum_size.x = 190
		row.add_child(label)
		preset_select = OptionButton.new()
		preset_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for preset: Dictionary in preferences.rules.presets:
			preset_select.add_item(preset.label)
			preset_select.set_item_metadata(preset_select.item_count - 1, preset.id)
			preset_select.set_item_tooltip(preset_select.item_count - 1, preset.get("description", ""))
		preset_select.item_selected.connect(func(index):
			preferences.select_preset(preset_select.get_item_metadata(index)))
		row.add_child(preset_select)
		add_child(row)

	if preferences.rules.get("knobs", {}).has("worldTextLang"):
		var knob: Dictionary = preferences.rules.knobs.worldTextLang
		var row := HBoxContainer.new()
		var label := NativeUi.label(knob.label)
		label.custom_minimum_size.x = 190
		row.add_child(label)
		lang_select = OptionButton.new()
		lang_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var choices: Array = knob.get("choices", [])
		var choice_labels: Dictionary = knob.get("choiceLabels", {})
		for choice: String in choices:
			lang_select.add_item(choice_labels.get(choice, choice))
			lang_select.set_item_metadata(lang_select.item_count - 1, choice)
			if knob.has("hint"):
				lang_select.set_item_tooltip(lang_select.item_count - 1, knob.hint)
		lang_select.item_selected.connect(func(index):
			preferences.set_value("worldTextLang", lang_select.get_item_metadata(index)))
		row.add_child(lang_select)
		add_child(row)

	reset_button = Button.new()
	var default_preset: Dictionary = preferences._preset(preferences.rules.get("defaultPreset", "messenger"))
	reset_button.text = "↺ %s" % default_preset.get("label", "Reset")
	reset_button.pressed.connect(preferences.reset)
	add_child(reset_button)

	preferences.changed.connect(_sync)
	_sync(preferences.snapshot())

func _sync(_snapshot: Dictionary = {}) -> void:
	if preset_select != null:
		for i in range(preset_select.item_count):
			if preset_select.get_item_metadata(i) == preferences.preset_id:
				preset_select.select(i)
				break
	if lang_select != null:
		var current_lang = preferences.value("worldTextLang")
		for i in range(lang_select.item_count):
			if lang_select.get_item_metadata(i) == current_lang:
				lang_select.select(i)
				break
	if reset_button != null:
		reset_button.disabled = preferences.is_default()
