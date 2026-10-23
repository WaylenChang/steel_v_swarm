class_name DeploymentPreferences
extends RefCounted

const SAVE_PATH := "user://lobby.cfg"

var path := SAVE_PATH
var persist := false
var values: Dictionary = {}
var player_name := ""

static func trim(value: String) -> String:
	var begin := 0
	var end := value.length()
	while begin < end and value[begin] in VisualPreferences.NUMBER_WHITESPACE:
		begin += 1
	while end > begin and value[end - 1] in VisualPreferences.NUMBER_WHITESPACE:
		end -= 1
	return value.substr(begin, end - begin)

func load_save() -> Error:
	if not persist:
		return OK
	values = {}
	player_name = ""
	var file := ConfigFile.new()
	var error := file.load(path)
	if error == ERR_FILE_NOT_FOUND:
		return OK
	if error != OK:
		return error
	var saved_name = file.get_value("player", "name", "")
	if saved_name is String:
		player_name = saved_name
	var saved_values = file.get_value("deployment", "values", {})
	if not saved_values is Dictionary:
		return ERR_INVALID_DATA
	values = saved_values.duplicate(true)
	return OK

func patch(changes: Dictionary) -> void:
	if not _refresh():
		return
	# Original savePrefs replaces top-level fields, including whole environment objects.
	values.merge(changes.duplicate(true), true)
	_save()

func remember_name(value: String) -> String:
	var selected := trim(value)
	if selected.is_empty():
		if not Content.balance.get("rooms", {}).get("names", {}).has("fallback"):
			push_error("Missing original player name fallback; regenerate source content")
			return ""
		selected = Content.balance.rooms.names.fallback
	if not _refresh():
		return selected
	player_name = selected
	_save()
	return player_name

func remember_field(ordinary: String, super_key: String, value: Variant, super_mode: bool) -> void:
	var changes := {}
	changes[super_key if super_mode else ordinary] = value
	patch(changes)

func remember_character(side: String, character: String) -> void:
	var changes := {"lastSide": side, "lastChar": null if character.is_empty() else character}
	if side == Content.constants.SUPER_SIDE:
		changes["superChar"] = null if character.is_empty() else character
	patch(changes)

func restore(super_mode: bool, current_size: float) -> Dictionary:
	if not Content.balance.get("rooms", {}).has("deployment"):
		push_error("Missing original deployment preferences; regenerate source content")
		return {}
	var size = values.get("superTeamSize" if super_mode else "teamSize")
	var number := VisualPreferences._number(size)
	if not is_finite(number) or number < int(Content.constants.TEAM.MIN) or number > int(Content.constants.TEAM.MAX):
		number = current_size
	var name = values.get("superRoomName" if super_mode else "roomName")
	if not name is String or name.is_empty():
		name = Content.balance.rooms.deployment.superRoomName if super_mode else ""
	var venue = values.get("superVenueId") if super_mode else values.get("lastVenueId")
	if super_mode and not ControlPreferences.truthy(venue):
		venue = values.get("lastVenueId")
	var environment = values.get("superEnv") if super_mode else values.get("env")
	if super_mode and not ControlPreferences.truthy(environment):
		environment = values.get("env")
	var selected := {}
	for key: String in ["season", "time", "weather"]:
		var item = environment.get(key) if environment is Dictionary else null
		var choices: Dictionary = Content.constants.ENV[key + "s"]
		selected[key] = item if item is String and (item == "random" or choices.has(item)) else "random"
	var difficulty = values.get("superBotDiff") if super_mode else values.get("botDiff")
	if super_mode and not ControlPreferences.truthy(difficulty):
		difficulty = values.get("botDiff")
	if not difficulty is String or not Content.constants.BOT_DIFF.has(difficulty):
		difficulty = Content.constants.DEFAULT_BOT_DIFF
	return {"team_size": number, "room_name": name, "venue_id": venue if venue is String else "", "env": selected,
		"bot_difficulty": difficulty, "side": "SWARM" if values.get("lastSide") == "SWARM" else "STEEL"}

func character(side: String) -> String:
	var requested = values.get("superChar") if side == Content.constants.SUPER_SIDE else values.get("lastChar")
	if side == Content.constants.SUPER_SIDE and not ControlPreferences.truthy(requested):
		requested = values.get("lastChar")
	if not requested is String or not Content.heroes.has(requested):
		return ""
	return requested if side == Content.constants.SUPER_SIDE or Content.heroes[requested].side in [side, "MERC"] else ""

func enter(super_mode: bool, current_size: float) -> Dictionary:
	if not _refresh():
		return {}
	var selected := restore(super_mode, current_size)
	if selected.is_empty():
		return selected
	if not String(selected.venue_id).is_empty() and Content.maps.any(func(entry): return entry.id == selected.venue_id):
		remember_field("lastVenueId", "superVenueId", selected.venue_id, super_mode)
	return selected

func record_match(settings: Dictionary, players: Array, player: int) -> void:
	if not _refresh():
		return
	var record := MatchRecipe.capture(settings, players, player, values)
	if record.is_empty():
		return
	var changes := {"lastSession": record, "lastSide": record.player.side, "lastChar": record.player.ch}
	if record.player.side == Content.constants.SUPER_SIDE and ControlPreferences.truthy(record.player.ch):
		changes["superChar"] = record.player.ch
	patch(changes)

func restart_recipe() -> Dictionary:
	if not _refresh():
		return {}
	var record = values.get("lastSession")
	return MatchRecipe.prepare(record) if record is Dictionary else {}

func _refresh() -> bool:
	var error := load_save()
	if error != OK:
		push_error("Cannot read deployment preferences: " + error_string(error))
		return false
	return true

func _save() -> void:
	if not persist:
		return
	var file := ConfigFile.new()
	file.set_value("player", "name", player_name)
	# A dictionary preserves null choices; ConfigFile removes individual null-valued keys.
	file.set_value("deployment", "values", values)
	var error := file.save(path)
	if error != OK:
		push_error("Cannot save deployment preferences: " + error_string(error))
