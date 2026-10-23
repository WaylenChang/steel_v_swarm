class_name RoomPlayerEditor
extends VBoxContainer

var sides: OptionButton
var characters: OptionButton

func _ready() -> void:
	sides = OptionButton.new()
	sides.item_selected.connect(func(index):
		var side: String = sides.get_item_metadata(index)
		if side != Session.chosen_side:
			if not side.is_empty():
				Session.deployment.patch({"lastSide": side})
			Session.pick_side(side))
	NativeUi.row(self, "players", sides)
	characters = OptionButton.new()
	characters.item_selected.connect(func(index):
		var character: String = characters.get_item_metadata(index)
		Session.deployment.remember_character(Session.chosen_side, character)
		Session.pick_character(character))
	NativeUi.row(self, "character", characters)
	Session.lobby_changed.connect(_sync)
	_sync()

func _sync() -> void:
	var player := Session.local_member()
	visible = Session.active and not Session.story_mode() and not player.is_empty() and player.get("mode", "player") == "player"
	if not visible:
		return
	var editable := not Session.reconnecting and not Session.leaving
	sides.set_block_signals(true)
	sides.clear()
	if not Session.config.get("super", false) and Content.balance.get("spectator", {}).has("initialFov"):
		sides.add_item(Content.label("room_leave_seat"))
		sides.set_item_metadata(0, "")
		if String(player.side).is_empty():
			sides.select(0)
	var available: Array = [Content.constants.SUPER_SIDE] if Session.config.get("super", false) else ["STEEL", "SWARM"]
	for side: String in available:
		sides.add_item(Content.side_info(side).name)
		sides.set_item_metadata(sides.item_count - 1, side)
		if side == player.side:
			sides.select(sides.item_count - 1)
		else:
			var count := Session.roster.filter(func(member): return member.side == side).size()
			sides.set_item_disabled(sides.item_count - 1, count >= int(Session.config.team_size))
	sides.disabled = not editable or Session.config.get("super", false)
	sides.set_block_signals(false)
	characters.set_block_signals(true)
	characters.clear()
	characters.add_item(Content.label("room_random_character"))
	characters.set_item_metadata(0, "")
	for character: String in RoomRoles.pool(player.side):
		var hero: Dictionary = Content.heroes[character]
		characters.add_item(hero.code + " · " + hero.name)
		characters.set_item_metadata(characters.item_count - 1, character)
		if player.character == character:
			characters.select(characters.item_count - 1)
	characters.get_parent().visible = Session.phase == "room"
	characters.disabled = not editable or Session.phase != "room" or String(player.side).is_empty()
	characters.set_block_signals(false)
