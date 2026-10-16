class_name CampaignProgress
extends RefCounted

var cleared: Dictionary = {"STEEL": [], "SWARM": []}
var seen: Dictionary = {"STEEL": [], "SWARM": []}
var prologue_seen := false
var art_mode := "char"
var path := "user://campaign.cfg"
var save_error: Error = OK

func load_save(save_path: String = "user://campaign.cfg") -> void:
	path = save_path
	cleared = {"STEEL": [], "SWARM": []}
	seen = {"STEEL": [], "SWARM": []}
	prologue_seen = false
	art_mode = "char"
	var file := ConfigFile.new()
	var error := file.load(path)
	if error == ERR_FILE_NOT_FOUND:
		return
	if error != OK:
		push_error("Cannot read campaign progress: " + error_string(error))
		return
	for side: String in ["STEEL", "SWARM"]:
		cleared[side] = _ids(file.get_value(side, "cleared", []))
		seen[side] = _ids(file.get_value(side, "seen", []))
	prologue_seen = file.get_value("presentation", "prologue_seen", false) == true
	art_mode = "mech" if file.get_value("presentation", "art_mode", "char") == "mech" else "char"

func _ids(value: Variant) -> Array:
	var ids: Array = []
	if value is Array or value is PackedStringArray:
		for id in value:
			if id is String and not ids.has(id):
				ids.append(id)
	return ids

func unlocked(side: String, index: int) -> bool:
	return cleared.has(side) and CampaignRules.unlocked(cleared[side], index)

func has_seen(side: String, id: String) -> bool:
	return cleared.get(side, []).has(id) or seen.get(side, []).has(id)

func mark_seen(side: String, id: String) -> Error:
	if not seen.has(side):
		return ERR_INVALID_PARAMETER
	if not seen[side].has(id):
		seen[side].append(id)
	return save()

func mark_cleared(side: String, id: String) -> Error:
	if not cleared.has(side):
		return ERR_INVALID_PARAMETER
	if not cleared[side].has(id):
		cleared[side].append(id)
	return save()

func save() -> Error:
	var file := ConfigFile.new()
	for side: String in ["STEEL", "SWARM"]:
		file.set_value(side, "cleared", cleared[side].duplicate())
		file.set_value(side, "seen", seen[side].duplicate())
	file.set_value("presentation", "prologue_seen", prologue_seen)
	file.set_value("presentation", "art_mode", art_mode)
	save_error = file.save(path)
	if save_error != OK:
		push_error("Cannot save campaign progress: " + error_string(save_error))
	return save_error
