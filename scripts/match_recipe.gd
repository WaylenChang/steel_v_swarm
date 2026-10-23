class_name MatchRecipe
extends RefCounted

static func map_for(settings: Dictionary) -> Dictionary:
	if settings.has("campaign"):
		var selection = settings.campaign
		if not selection is Dictionary or not _integer(selection.get("index")) or selection.get("side") not in ["STEEL", "SWARM"]:
			return {}
		return Content.campaign_map(int(selection.index), selection.side, bool(selection.get("swapped", false)))
	var index = settings.get("map_index")
	var size = settings.get("team_size")
	if not _integer(index) or not _integer(size):
		return {}
	if index < 0 or index >= Content.maps.size() or size < int(Content.constants.TEAM.MIN) or size > int(Content.constants.TEAM.MAX):
		return {}
	return Content.map_variant(int(index), int(size), bool(settings.get("swapped", false)))

static func signature(map_data: Dictionary) -> String:
	var hash := HashingContext.new()
	if hash.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if hash.update(var_to_bytes(map_data)) != OK:
		return ""
	return hash.finish().hex_encode()

static func capture(settings: Dictionary, players: Array, player: int, preferences: Dictionary = {}) -> Dictionary:
	var local := players.filter(func(member): return int(member.peer) == player and not member.get("bot", false))
	if local.is_empty() or local[0].get("mode", "player") != "player" or String(local[0].get("side", "")).is_empty():
		return {}
	var map_data := map_for(settings)
	if map_data.is_empty():
		return {}
	var definition := _definition(settings, map_data)
	var native_settings := settings.duplicate(true)
	# The seed is uint32; ConfigFile text rounds large floating-point values.
	native_settings["architecture_seed"] = int(settings.get("architecture_seed", 0))
	var difficulty = settings.get("env", {}).get("bot_difficulty")
	if not ControlPreferences.truthy(difficulty):
		difficulty = preferences.get("botDiff")
	if not ControlPreferences.truthy(difficulty):
		difficulty = Content.constants.DEFAULT_BOT_DIFF
	var bots: Array = []
	for member: Dictionary in players:
		if member.get("bot", false):
			bots.append({"side": member.side, "ch": member.get("character") if ControlPreferences.truthy(member.get("character")) else null})
	return {"player": {"side": local[0].side, "ch": local[0].get("character") if ControlPreferences.truthy(local[0].get("character")) else null},
		"bots": bots, "teamSize": int(settings.team_size), "botDiff": difficulty,
		"ctrl": settings.get("ctrl") if ControlPreferences.truthy(settings.get("ctrl")) else null,
		"roomName": settings.get("room_name", ""), "battleConfig": definition,
		"native": {"version": 1, "settings": native_settings, "template": signature(map_data),
			"map_id": "" if settings.has("campaign") else Content.maps[int(settings.map_index)].id}}

static func prepare(record: Dictionary) -> Dictionary:
	var native = record.get("native")
	if not native is Dictionary or native.get("version") != 1 or not native.get("settings") is Dictionary or not record.get("player") is Dictionary or not record.get("bots") is Array:
		return {}
	var settings: Dictionary = native.settings.duplicate(true)
	if not settings.get("env") is Dictionary:
		return {}
	for key: String in ["season", "time", "weather"]:
		var value = settings.env.get(key)
		if not value is String or not Content.constants.ENV[key + "s"].has(value):
			return {}
	var lunar = settings.env.get("lunarDay")
	if not (lunar is int or lunar is float) or not is_finite(float(lunar)) or float(lunar) != floorf(float(lunar)) or float(lunar) < 1 or float(lunar) > 30:
		return {}
	var size = settings.get("team_size")
	if not (size is int or size is float) or not is_finite(float(size)) or float(size) != floorf(float(size)) or float(size) < int(Content.constants.TEAM.MIN) or float(size) > int(Content.constants.TEAM.MAX):
		return {}
	if record.get("teamSize") != size:
		return {}
	if settings.has("campaign"):
		var selection = settings.campaign
		if not selection is Dictionary or not selection.get("chapter") is String or selection.get("side") not in ["STEEL", "SWARM"]:
			return {}
		var index: int = Content.campaign.get("chapters", []).find_custom(func(chapter): return chapter.id == selection.chapter)
		if index < 0 or not selection.get("pilot") is String or not CampaignRules.valid_selection(index, selection.side, selection.pilot):
			return {}
		settings.campaign.index = index
	else:
		if not native.get("map_id") is String:
			return {}
		var index := Content.maps.find_custom(func(entry): return entry.id == native.map_id)
		if index < 0:
			return {}
		settings.map_index = index
	var map_data := map_for(settings)
	if map_data.is_empty() or not native.get("template") is String or String(native.template).is_empty() or signature(map_data) != native.template:
		return {}
	if not record.get("battleConfig") is Dictionary or record.battleConfig != _definition(settings, map_data):
		return {}
	var side = record.player.get("side")
	var super_mode := bool(settings.get("super", false)) and not settings.has("campaign")
	if not side is String or side not in ([Content.constants.SUPER_SIDE] if super_mode else ["SWARM", "STEEL"]) or not _valid_character(side, record.player.get("ch")):
		return {}
	var counts := {"STEEL": 0, "SWARM": 0, "SUPER": 0}
	counts[side] += 1
	for bot in record.bots:
		if not bot is Dictionary or bot.get("side") not in ["STEEL", "SWARM"] or not _valid_character(bot.side, bot.get("ch")):
			return {}
		counts[bot.side] += 1
		if counts[bot.side] > int(size):
			return {}
	if not record.get("ctrl") is String or record.ctrl not in Controls.rules.get("modeKeys", []) or not record.get("botDiff") is String or not Content.constants.BOT_DIFF.has(record.botDiff) or not record.get("roomName") is String:
		return {}
	settings["ctrl"] = record.ctrl
	settings["room_name"] = record.roomName
	settings["is_public"] = false
	settings["quick_restart"] = true
	settings.env["bot_difficulty"] = record.botDiff
	return {"settings": settings, "player": record.player.duplicate(true), "bots": record.bots.duplicate(true)}

static func _definition(settings: Dictionary, map_data: Dictionary) -> Dictionary:
	var definition: Dictionary = map_data.config.duplicate(true)
	definition["defSide"] = definition.get("defSide") if definition.get("defSide") in ["STEEL", "SWARM"] else null
	definition["siege"] = definition.defSide != null
	definition["super"] = bool(settings.get("super", false)) and not definition.siege
	definition["teamSize"] = int(settings.team_size)
	definition["architectureSeed"] = int(settings.get("architecture_seed", 0))
	definition["env"] = settings.get("env", {}).duplicate(true)
	definition.env.erase("bot_difficulty")
	return definition

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value))

static func _valid_character(side: String, character: Variant) -> bool:
	if character == null:
		return true
	if not character is String:
		return false
	if character.is_empty():
		return true
	return Content.heroes.has(character) and (side == Content.constants.SUPER_SIDE or Content.heroes[character].side in [side, "MERC"])
