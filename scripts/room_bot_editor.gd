class_name RoomBotEditor
extends VBoxContainer

var targets: OptionButton
var characters: OptionButton
var difficulty: OptionButton
var remove_button: Button
var add_buttons: Dictionary = {}

func _ready() -> void:
	var additions := HBoxContainer.new()
	for side: String in ["SWARM", "STEEL"]:
		var button := NativeUi.button(Content.side_info(side).name + " " + Content.label("room_add_bot"), Session.edit_bot.bind("add", 0, side))
		additions.add_child(button)
		add_buttons[side] = button
	add_child(additions)
	targets = OptionButton.new()
	targets.item_selected.connect(func(_index): _sync_characters())
	add_child(targets)
	characters = OptionButton.new()
	characters.item_selected.connect(func(index):
		Session.edit_bot("character", _selected_bot(), characters.get_item_metadata(index)))
	NativeUi.row(self, "character", characters)
	difficulty = OptionButton.new()
	var diff_dict: Dictionary = Content.constants.get("BOT_DIFF", {})
	for key: String in diff_dict:
		difficulty.add_item(diff_dict[key].name)
		difficulty.set_item_metadata(difficulty.item_count - 1, key)
	difficulty.item_selected.connect(func(index):
		Session.set_bot_difficulty(difficulty.get_item_metadata(index)))
	NativeUi.row(self, "bot_difficulty", difficulty)
	remove_button = NativeUi.button(Content.label("room_remove_bot"), func(): Session.edit_bot("remove", _selected_bot()))
	add_child(remove_button)
	Session.lobby_changed.connect(_sync)
	_sync()

func _selected_bot() -> int:
	return int(targets.get_item_metadata(targets.selected)) if targets.selected >= 0 else 0

func _sync() -> void:
	visible = Session.active and Session.phase == "room" and not Session.story_mode()
	if not visible:
		return
	var editable := Session.is_room_host() and not Session.reconnecting and not Session.leaving
	for side: String in add_buttons:
		var count := Session.roster.filter(func(player): return player.side == side).size()
		add_buttons[side].disabled = not editable or count >= int(Session.config.team_size)
	var selected := _selected_bot()
	targets.set_block_signals(true)
	targets.clear()
	for player: Dictionary in Session.roster:
		if not player.get("bot", false):
			continue
		targets.add_item(player.name + " · " + Content.side_info(player.side).name)
		targets.set_item_metadata(targets.item_count - 1, int(player.peer))
		if int(player.peer) == selected:
			targets.select(targets.item_count - 1)
	targets.set_block_signals(false)
	targets.disabled = targets.item_count == 0
	remove_button.disabled = not editable or targets.item_count == 0
	var diff_key: String = Session.config.get("env", {}).get("bot_difficulty", Content.constants.DEFAULT_BOT_DIFF)
	difficulty.set_block_signals(true)
	for i in range(difficulty.item_count):
		if difficulty.get_item_metadata(i) == diff_key:
			difficulty.select(i)
			break
	difficulty.disabled = not Session.is_room_host() or Session.reconnecting or Session.leaving
	difficulty.set_block_signals(false)
	_sync_characters()

func _sync_characters() -> void:
	var selected := _selected_bot()
	characters.set_block_signals(true)
	characters.clear()
	for player: Dictionary in Session.roster:
		if int(player.peer) != selected or not player.get("bot", false):
			continue
		characters.add_item(Content.label("room_random_character"))
		characters.set_item_metadata(0, "")
		for character: String in RoomRoles.pool(player.side):
			var hero: Dictionary = Content.heroes[character]
			characters.add_item(hero.code + " · " + hero.name)
			characters.set_item_metadata(characters.item_count - 1, character)
			if character == player.character:
				characters.select(characters.item_count - 1)
		break
	characters.disabled = not Session.is_room_host() or Session.reconnecting or Session.leaving or characters.item_count == 0
	characters.set_block_signals(false)
