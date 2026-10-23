class_name RoomRoles
extends RefCounted

static func pool(side: String) -> Array:
	return Content.balance.get("rooms", {}).get("heroPools", {}).get(side, [])

static func choose(side: String, requested: String, previous: Array, next_random: Callable) -> String:
	if Content.heroes.has(requested) and (side == Content.constants.SUPER_SIDE or Content.heroes[requested].side in [side, "MERC"]):
		return requested
	var complete := pool(side)
	if complete.is_empty():
		push_error("Missing original room character pool; regenerate source content")
		return ""
	var used: Dictionary = {}
	for hero: Dictionary in previous:
		if hero.side == side:
			used[hero.character] = true
	var available: Array = complete.filter(func(character): return not used.has(character))
	var choices: Array = complete if available.is_empty() else available
	return choices[int(floorf(float(next_random.call()) * choices.size()))]
