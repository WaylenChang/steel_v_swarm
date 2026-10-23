class_name VisualPreferences
extends Node

signal changed(snapshot: Dictionary)
signal save_failed(error: Error)

const SAVE_PATH := "user://visuals.cfg"
const NUMBER_WHITESPACE := "\u0009\u000a\u000b\u000c\u000d\u0020\u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000\ufeff"

var rules: Dictionary = {}
var values: Dictionary = {}
var preset_id := ""
var revision := 0
var persist := true
var save_path := SAVE_PATH

func _ready() -> void:
	if not Content.balance.has("visual"):
		push_error("Missing original visual preference catalog; regenerate source content")
		return
	configure(Content.balance.visual)
	load_save()

func configure(metadata: Dictionary, saved: Dictionary = {}) -> void:
	rules = metadata.duplicate(true)
	preset_id = _preset(saved.get("preset")).id
	values = _preset(preset_id).values.duplicate()
	if saved.has("worldTextLang"):
		values.worldTextLang = normalize("worldTextLang", saved.worldTextLang)
	revision = 0

func _preset(id: Variant) -> Dictionary:
	for entry: Dictionary in rules.presets:
		if id is String and entry.id == id:
			return entry
	return rules.presets[0]

func selected_preset() -> Dictionary:
	return _preset(preset_id).duplicate(true)

func snapshot() -> Dictionary:
	return values.duplicate()

func value(key: String) -> Variant:
	return values.get(key, 0)

static func _number(input: Variant) -> float:
	var value: Variant = input
	var from_array := value is Array
	while value is Array:
		if value.is_empty():
			return 0.0
		if value.size() != 1:
			return NAN
		value = value[0]
	if value == null:
		return 0.0
	if value is bool:
		return NAN if from_array else float(value)
	if value is int or value is float:
		return float(value)
	if not value is String:
		return NAN
	var begin := 0
	var end: int = value.length()
	while begin < end and value[begin] in NUMBER_WHITESPACE:
		begin += 1
	while end > begin and value[end - 1] in NUMBER_WHITESPACE:
		end -= 1
	var text: String = value.substr(begin, end - begin)
	if text.is_empty():
		return 0.0
	if text in ["Infinity", "+Infinity"]:
		return INF
	if text == "-Infinity":
		return -INF
	var lower := text.to_lower()
	var radix := 16 if lower.begins_with("0x") else 2 if lower.begins_with("0b") else 8 if lower.begins_with("0o") else 0
	if radix > 0:
		if text.length() == 2:
			return NAN
		var result := 0.0
		for character: String in lower.substr(2):
			var digit := "0123456789abcdef".find(character)
			if digit < 0 or digit >= radix:
				return NAN
			result = result * radix + digit
		return result
	return text.to_float() if text.is_valid_float() else NAN

func normalize(key: String, input: Variant) -> Variant:
	if not rules.knobs.has(key):
		return 0
	var definition: Dictionary = rules.knobs[key]
	if definition.has("choices"):
		return input if input in definition.choices else definition.def
	var number := _number(input)
	return clampf(number, definition.min, definition.max) if is_finite(number) else definition.def

func set_value(key: String, input: Variant) -> Variant:
	if not rules.knobs.has(key):
		return 0
	var next: Variant = normalize(key, input)
	if next == values[key]:
		return next
	values[key] = next
	_commit()
	return next

func select_preset(id: Variant) -> String:
	var selected := _preset(id)
	var different: bool = preset_id != selected.id
	preset_id = selected.id
	for key: String in selected.values:
		if key == "worldTextLang":
			continue
		if values[key] != selected.values[key]:
			values[key] = selected.values[key]
			different = true
	if different:
		_commit()
	return preset_id

func reset() -> void:
	select_preset(rules.defaultPreset)

func is_default() -> bool:
	if preset_id != rules.defaultPreset:
		return false
	for key: String in rules.presets[0].values:
		if key != "worldTextLang" and values[key] != rules.presets[0].values[key]:
			return false
	return true

func saved_values() -> Dictionary:
	return {"preset": preset_id, "worldTextLang": values.worldTextLang}

func _commit() -> void:
	if persist:
		var file := ConfigFile.new()
		var saved := saved_values()
		for key: String in saved:
			file.set_value("visual", key, saved[key])
		var error := file.save(save_path)
		if error != OK:
			save_failed.emit(error)
	revision += 1
	var current := snapshot()
	current.make_read_only()
	changed.emit(current)

func load_save(path: String = SAVE_PATH) -> void:
	save_path = path
	var file := ConfigFile.new()
	var error := file.load(path)
	if error != OK:
		return
	var saved := {}
	for key: String in ["preset", "worldTextLang"]:
		if file.has_section_key("visual", key):
			saved[key] = file.get_value("visual", key)
	configure(rules, saved)
