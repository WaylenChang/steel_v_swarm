extends Node

var balance: Dictionary
var maps: Array
var text: Dictionary
var constants: Dictionary
var heroes: Dictionary
var structures: Dictionary

func _ready() -> void:
	balance = read_json("res://data/balance.json")
	maps = read_json("res://data/maps.json")
	constants = balance.constants
	heroes = balance.heroes
	structures = read_json("res://data/structures.json")
	text = read_json("res://data/ui.json")
	_install_input()

func read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Required content missing: " + path)
		get_tree().quit(1)
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		push_error("Invalid content: " + path + ": " + parser.get_error_message())
		get_tree().quit(1)
		return {}
	return parser.data

func weapon(character: String, slot: String, level: int = 1) -> Dictionary:
	var tiers: Array = heroes[character].weapons[slot]
	return tiers[clampi(level - 1, 0, tiers.size() - 1)]

func ability(character: String, slot: String, level: int = 1) -> Dictionary:
	var tiers: Array = heroes[character].abilities[slot]
	return tiers[clampi(level - 1, 0, tiers.size() - 1)]

func map_variant(index: int, size: int) -> Dictionary:
	var entry: Dictionary = maps[clampi(index, 0, maps.size() - 1)]
	var variant: Dictionary = entry.variants[str(clampi(size, 1, 5))].duplicate(true)
	variant.native_world = "res://assets/worlds/%s_%d.res" % [entry.id, clampi(size, 1, 5)]
	return variant

func label(key: String) -> String:
	return str(text.get(key, key))

func _install_input() -> void:
	var keys := {"forward": KEY_W, "back": KEY_S, "left": KEY_A, "right": KEY_D,
		"rise": KEY_SPACE, "descend": KEY_C, "sprint": KEY_SHIFT, "reload": KEY_R,
		"shop": KEY_B, "map": KEY_M, "defense": KEY_Q, "attack": KEY_E,
		"morph": KEY_F, "pause": KEY_ESCAPE, "slot_light": KEY_1, "slot_heavy": KEY_2}
	for action in keys:
		InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = keys[action]
		InputMap.action_add_event(action, event)
	for action in {"fire": MOUSE_BUTTON_LEFT, "aim": MOUSE_BUTTON_RIGHT}:
		InputMap.add_action(action)
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT if action == "fire" else MOUSE_BUTTON_RIGHT
		InputMap.action_add_event(action, event)
	InputMap.action_add_event("fire", _joy_button(JOY_BUTTON_RIGHT_SHOULDER))
	InputMap.action_add_event("rise", _joy_button(JOY_BUTTON_A))
	InputMap.action_add_event("defense", _joy_button(JOY_BUTTON_X))
	InputMap.action_add_event("attack", _joy_button(JOY_BUTTON_Y))
	for spec in [["left", JOY_AXIS_LEFT_X, -1.0], ["right", JOY_AXIS_LEFT_X, 1.0],
		["forward", JOY_AXIS_LEFT_Y, -1.0], ["back", JOY_AXIS_LEFT_Y, 1.0]]:
		var event := InputEventJoypadMotion.new()
		event.axis = spec[1]
		event.axis_value = spec[2]
		InputMap.action_add_event(spec[0], event)

func _joy_button(button: int) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	return event

