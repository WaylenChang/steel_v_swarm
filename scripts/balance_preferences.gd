class_name BalancePreferences
extends RefCounted

signal changed(values: Dictionary)
signal save_failed(error: Error)

const SAVE_PATH := "user://balance.cfg"

var rules: Dictionary = {}
var values: Dictionary = {}
var persist := false
var save_path := SAVE_PATH

func configure(metadata: Dictionary, saved: Variant = {}) -> void:
	rules = metadata
	values = {}
	for key: String in rules.knobs:
		values[key] = normalize(key, saved[key]) if saved is Dictionary and saved.has(key) else float(rules.knobs[key].def)

func normalize(key: String, input: Variant) -> float:
	if not rules.knobs.has(key):
		return 1.0
	var definition: Dictionary = rules.knobs[key]
	var number := VisualPreferences._number(input)
	if not is_finite(number):
		return float(definition.def)
	var scale := float(rules.roundScale)
	return floorf(clampf(number, float(definition.min), float(definition.max)) * scale + .5) / scale

func pref(key: String) -> float:
	return float(values.get(key, rules.knobs.get(key, {}).get("def", 1.0)))

func multiplier(stat: String) -> float:
	return float(values.get("stat_" + stat, 1.0))

func curve(item: String, level: Variant = 1) -> float:
	var start := pref("upg_" + item + "_start")
	var finish := pref("upg_" + item + "_end")
	if start == 1 and finish == 1:
		return 1.0
	var combat: bool = item in rules.combatTracks
	var minimum := float(rules.combatMinimum if combat else rules.defenseMinimum)
	var maximum := float(rules.combatMaximum if combat else rules.defenseMaximum)
	var number := VisualPreferences._number(level)
	if is_nan(number):
		return NAN
	var fraction := (clampf(number, minimum, maximum) - minimum) / (maximum - minimum)
	return start + (finish - start) * fraction

func snapshot() -> Dictionary:
	return values.duplicate()

func is_default() -> bool:
	for key: String in rules.knobs:
		if values[key] != rules.knobs[key].def:
			return false
	return true

func set_value(key: String, input: Variant) -> float:
	if not rules.knobs.has(key):
		return 1.0
	var normalized := normalize(key, input)
	if normalized == values[key]:
		return normalized
	values[key] = normalized
	_save()
	changed.emit(values)
	return normalized

func reset() -> void:
	var modified := false
	for key: String in rules.knobs:
		if values[key] != rules.knobs[key].def:
			values[key] = float(rules.knobs[key].def)
			modified = true
	if not modified:
		return
	_save()
	changed.emit(values)

func load_save() -> Error:
	if not persist:
		return OK
	if not FileAccess.file_exists(save_path):
		configure(rules)
		return OK
	var reader := FileAccess.open(save_path, FileAccess.READ)
	if reader == null:
		configure(rules)
		return FileAccess.get_open_error()
	var text := reader.get_as_text()
	reader.close()
	for raw_line: String in text.split("\n"):
		var line := raw_line.strip_edges()
		if line.is_empty() or line.begins_with(";") or line.begins_with("#"):
			continue
		if line.begins_with("[") and not line.ends_with("]"):
			configure(rules)
			return ERR_PARSE_ERROR
	var file := ConfigFile.new()
	var error := file.parse(text)
	if error != OK:
		configure(rules)
		return error
	configure(rules, file.get_value("balance", "values", {}))
	return OK

func _save() -> void:
	if not persist:
		return
	var file := ConfigFile.new()
	file.set_value("balance", "values", values)
	var error := file.save(save_path)
	if error != OK:
		save_failed.emit(error)
