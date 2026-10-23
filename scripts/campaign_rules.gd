class_name CampaignRules
extends RefCounted

static func chapter(index: int) -> Dictionary:
	var chapters: Array = Content.campaign.get("chapters", [])
	return chapters[index] if index >= 0 and index < chapters.size() else {}

static func unlocked(cleared: Array, index: int) -> bool:
	if index <= 0:
		return true
	var previous := chapter(index - 1)
	return not previous.is_empty() and cleared.has(previous.id)

static func valid_selection(index: int, side: String, pilot: String) -> bool:
	var data := chapter(index)
	if data.is_empty() or side not in ["STEEL", "SWARM"]:
		return false
	return (data[side].heroes + data[side].mercs).has(pilot)

static func roster(index: int, side: String, pilot: String, human_peer: int = 1) -> Array:
	if human_peer <= 0 or not valid_selection(index, side, pilot):
		return []
	var data := chapter(index)
	var foe := "SWARM" if side == "STEEL" else "STEEL"
	var result: Array = [{"peer": human_peer, "side": side, "character": pilot, "bot": false}]
	var bot_peer := -1
	for faction: String in [side, foe]:
		for character: String in data[faction].heroes + data[faction].mercs:
			if faction == side and character == pilot:
				continue
			result.append({"peer": bot_peer, "side": faction, "character": character, "bot": true})
			bot_peer -= 1
	return result

static func settings(index: int, side: String, pilot: String, swapped: bool = false) -> Dictionary:
	if not valid_selection(index, side, pilot):
		return {}
	var data := chapter(index)
	var difficulties: Array = Content.campaign.difficulties
	var environment: Dictionary = data.env.duplicate()
	environment.bot_difficulty = difficulties[index] if index < difficulties.size() else Content.constants.DEFAULT_BOT_DIFF
	return {"campaign": {"index": index, "chapter": data.id, "side": side, "pilot": pilot, "swapped": swapped},
		"room_name": data[side].title, "is_public": false, "team_size": int(data.teamSize), "env": environment}

static func next_pilot(roster_ids: Array, current: String, direction: int) -> String:
	if roster_ids.is_empty():
		return ""
	var index := roster_ids.find(current)
	if index < 0:
		index = -1 if direction > 0 else 0
	return roster_ids[posmod(index + direction, roster_ids.size())]

static func talk(index: int, side: String, stage: int) -> Dictionary:
	var data := chapter(index)
	if data.is_empty() or stage < 0 or stage >= Content.constants.SIEGE.STAGES.size():
		return {}
	return Content.campaign.get("talk", {}).get(data.id, {}).get(side, {}).get(Content.constants.SIEGE.STAGES[stage], {})

static func line_seconds(value: String) -> float:
	var length := 0
	for index in range(value.length()):
		length += 2 if value.unicode_at(index) > 65535 else 1
	var rules: Dictionary = Content.campaign.presentation.line
	return clampf(float(rules.base) + length * float(rules.perCharacter), float(rules.minimum), float(rules.maximum)) / 1000.0

static func leaders(lines: Array, side: String, transcript: bool = false) -> Array:
	var tally := {}
	for line: Dictionary in lines:
		tally[line.ch] = int(tally.get(line.ch, 0)) + 1
	var order: Array = tally.keys()
	var ranked := order.duplicate()
	ranked.sort_custom(func(first, second): return int(tally[first]) > int(tally[second]) if tally[first] != tally[second] else order.find(first) < order.find(second))
	if ranked.is_empty():
		return []
	var foe := "SWARM" if side == "STEEL" else "STEEL"
	if transcript:
		var pair := ranked.slice(0, 2)
		if pair.size() == 2 and Content.heroes[pair[0]].side == foe and Content.heroes[pair[1]].side != foe:
			pair.reverse()
		return pair
	var left: String = ranked[0]
	for id: String in ranked:
		if Content.heroes[id].side != foe:
			left = id
			break
	var result: Array = [left]
	for id: String in ranked:
		if id != left:
			result.append(id)
			break
	return result

static func focus_section(scroll: float, viewport_height: float, sections: Array, active: int = 0) -> Dictionary:
	var focus := scroll + viewport_height * float(Content.campaign.presentation.crawl.focus)
	var selected := active if active >= 0 else 0
	var progress := 0.0
	var best := INF
	for index in range(sections.size()):
		var section: Dictionary = sections[index]
		var top: float = section.top
		var height: float = section.height
		if focus >= top and focus <= top + height:
			selected = index
			progress = (focus - top) / height if height > 0 else 0.0
			best = -1
		elif best >= 0:
			var distance := top - focus if focus < top else focus - top - height
			if distance < best:
				best = distance
				selected = index
				progress = 0.0 if focus < top else 1.0
	return {"index": selected, "progress": progress}

static func camera_pose(group: Dictionary, progress: float, landscape: bool) -> Dictionary:
	var keys: Dictionary = group.get("landscape" if landscape else "portrait", {})
	if keys.is_empty():
		return {}
	var fraction := clampf(progress, 0, 1)
	var first: Dictionary = keys.start if fraction < 0.5 else keys.mid
	var second: Dictionary = keys.mid if fraction < 0.5 else keys.end
	var position := fraction * 2 if fraction < 0.5 else (fraction - 0.5) * 2
	var eased := 2 * position * position if position < 0.5 else -1 + (4 - 2 * position) * position
	var rules: Dictionary = Content.campaign.presentation.camera
	return {"scale": clampf(lerpf(first.scale, second.scale, eased), rules.scale[0], rules.scale[1]),
		"x": clampf(lerpf(first.x, second.x, eased) * float(rules.xFactor), rules.x[0], rules.x[1]),
		"y": clampf(lerpf(first.y, second.y, eased) * float(rules.yFactor), rules.y[0], rules.y[1])}
