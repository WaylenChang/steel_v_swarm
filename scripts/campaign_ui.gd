class_name CampaignUi
extends Control

signal deployment_requested(settings: Dictionary)
signal closed
signal return_requested

var progress: CampaignProgress
var side := "STEEL"
var chapter_index := 0
var pilot := ""
var panel: PanelContainer
var body: VBoxContainer
var cards: VBoxContainer
var brief: VBoxContainer
var status: Label
var fight: Button
var result_view := false
var cinematic: CampaignCinematic
var settlement_dialogue: CampaignDialogue

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color("#101b26")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	panel = NativeUi.panel(Vector2(1060, 700))
	add_child(panel)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	panel.add_child(body)
	cinematic = CampaignCinematic.new()
	add_child(cinematic)
	resized.connect(_layout)
	hide()

func _layout() -> void:
	if panel == null:
		return
	panel.size = Vector2(minf(1060, size.x - 24), minf(700, size.y - 24))
	panel.position = -panel.size / 2

func _wipe(control: Control) -> void:
	for child in control.get_children():
		control.remove_child(child)
		child.queue_free()

func open(save: CampaignProgress, faction: String = "STEEL") -> void:
	progress = save
	side = faction if faction in ["STEEL", "SWARM"] else "STEEL"
	pilot = ""
	result_view = false
	show()
	_layout()
	_render_menu()

func _render_menu() -> void:
	if settlement_dialogue != null:
		settlement_dialogue.dispose()
		settlement_dialogue.queue_free()
		settlement_dialogue = null
	_wipe(body)
	var header := HBoxContainer.new()
	body.add_child(header)
	header.add_child(NativeUi.label(Content.label("story_campaign"), 30))
	var factions := OptionButton.new()
	for faction: String in ["STEEL", "SWARM"]:
		factions.add_item(Content.side_info(faction).name)
	factions.select(0 if side == "STEEL" else 1)
	factions.item_selected.connect(func(index):
		side = "STEEL" if index == 0 else "SWARM"
		chapter_index = 0
		pilot = ""
		_render_menu())
	header.add_child(factions)
	var art := OptionButton.new()
	art.add_item(Content.label("story_art_char"))
	art.add_item(Content.label("story_art_mech"))
	art.select(1 if progress.art_mode == "mech" else 0)
	art.item_selected.connect(func(index):
		progress.art_mode = "mech" if index == 1 else "char"
		progress.save()
		_show_brief(chapter_index))
	header.add_child(art)
	header.add_child(NativeUi.button(Content.label("story_world"), _show_world))
	header.add_child(NativeUi.button(Content.label("close"), func(): hide(); closed.emit()))
	status = NativeUi.label("", 15)
	body.add_child(status)
	var columns := HSplitContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.split_offset = 310
	body.add_child(columns)
	var card_scroll := ScrollContainer.new()
	card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card_scroll.custom_minimum_size.x = 285
	columns.add_child(card_scroll)
	cards = VBoxContainer.new()
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("separation", 12)
	card_scroll.add_child(cards)
	var brief_scroll := ScrollContainer.new()
	brief_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	brief_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(brief_scroll)
	brief = VBoxContainer.new()
	brief.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brief.add_theme_constant_override("separation", 12)
	brief_scroll.add_child(brief)
	var chapters: Array = Content.campaign.get("chapters", [])
	if chapters.is_empty():
		status.text = Content.label("story_content_missing")
		return
	var completed := 0
	for index in range(chapters.size()):
		var chapter: Dictionary = chapters[index]
		var cleared: bool = progress.cleared[side].has(chapter.id)
		completed += 1 if cleared else 0
		var state := Content.label("story_cleared" if cleared else "story_ready" if progress.unlocked(side, index) else "story_locked")
		var button := NativeUi.button(chapter.act + " · " + chapter[side].title + "\n" + state, func():
			pilot = ""
			_show_brief(index))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = not progress.unlocked(side, index)
		cards.add_child(button)
	status.text = Content.label("story_progress") % [Content.side_info(side).name, completed, chapters.size()]
	if completed >= chapters.size():
		status.text += Content.label("story_all_cleared")
	_show_brief(clampi(chapter_index, 0, chapters.size() - 1))

func _show_world() -> void:
	_wipe(brief)
	brief.add_child(NativeUi.label(Content.label("story_world"), 25))
	brief.add_child(NativeUi.prose(Content.campaign.get("world", "")))
	brief.add_child(NativeUi.button(Content.label("story_prologue"), _play_prologue))
	brief.add_child(NativeUi.button(Content.label("story_back_brief"), func(): _show_brief(chapter_index)))

func _show_brief(index: int) -> void:
	var chapter := CampaignRules.chapter(index)
	if chapter.is_empty():
		return
	chapter_index = index
	var section: Dictionary = chapter[side]
	var roster: Array = section.heroes + section.mercs
	if not roster.has(pilot):
		pilot = roster[0]
	_wipe(brief)
	brief.add_child(NativeUi.label(chapter.act + " · " + section.title, 26))
	var art := TextureRect.new()
	art.texture = Content.story_texture(section.img)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.custom_minimum_size.y = 240
	brief.add_child(art)
	brief.add_child(NativeUi.prose(section.intro))
	brief.add_child(NativeUi.label(Content.label("story_allies"), 18))
	_roster(roster, true)
	var foe := "SWARM" if side == "STEEL" else "STEEL"
	brief.add_child(NativeUi.label(Content.label("story_enemies"), 18))
	_roster(chapter[foe].heroes + chapter[foe].mercs, false)
	brief.add_child(NativeUi.prose(section.objective, 20))
	var controls := HBoxContainer.new()
	brief.add_child(controls)
	controls.add_child(NativeUi.button(Content.label("story_intro"), func(): _play_intro(false)))
	fight = NativeUi.button(Content.label("story_deploy"), _deploy)
	fight.disabled = not progress.unlocked(side, index) or not Content.campaign_available(index, side)
	controls.add_child(fight)
	if not Content.campaign_available(index, side):
		brief.add_child(NativeUi.prose(Content.label("story_map_missing"), 16))

func _roster(ids: Array, selectable: bool) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	brief.add_child(grid)
	for id: String in ids:
		var hero: Dictionary = Content.heroes[id]
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(cell)
		var portrait := TextureRect.new()
		portrait.texture = Content.campaign_art(id, "avatar", progress.art_mode)
		portrait.custom_minimum_size = Vector2(70, 70)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cell.add_child(portrait)
		if selectable:
			var button := NativeUi.button((Content.label("story_selected") if id == pilot else "") + hero.code + " · " + hero.name, func():
				pilot = id
				_show_brief(chapter_index))
			button.toggle_mode = true
			button.button_pressed = id == pilot
			cell.add_child(button)
		else:
			cell.add_child(NativeUi.label(hero.code + " · " + hero.name, 16))

func _deploy() -> void:
	if not progress.unlocked(side, chapter_index) or not Content.campaign_available(chapter_index, side):
		return
	var chapter := CampaignRules.chapter(chapter_index)
	if progress.has_seen(side, chapter.id):
		_emit_deployment()
	else:
		_play_intro(true)

func _emit_deployment() -> void:
	var settings := CampaignRules.settings(chapter_index, side, pilot)
	if settings.is_empty():
		return
	hide()
	deployment_requested.emit(settings)

func _clear_finished_handlers() -> void:
	for connection: Dictionary in cinematic.finished.get_connections():
		cinematic.finished.disconnect(connection.callable)
	for connection: Dictionary in cinematic.finishing.get_connections():
		cinematic.finishing.disconnect(connection.callable)

func _play_intro(deploy_after: bool) -> void:
	var chapter := CampaignRules.chapter(chapter_index)
	var scenes: Array = Content.campaign.get("scenes", {}).get(chapter.id, {}).get(side, [])
	if progress.mark_seen(side, chapter.id) != OK:
		status.text = Content.label("story_save_failed")
	_clear_finished_handlers()
	cinematic.finished.connect(func():
		if deploy_after:
			_emit_deployment(), CONNECT_ONE_SHOT)
	cinematic.play(scenes, Content.label("story_deploy" if deploy_after else "story_back_brief"))

func _play_prologue() -> void:
	_clear_finished_handlers()
	cinematic.finishing.connect(func():
		progress.prologue_seen = true
		if progress.save() != OK:
			status.text = Content.label("story_save_failed"), CONNECT_ONE_SHOT)
	cinematic.play(Content.campaign.get("prologue", []), Content.label("story_back_brief"))

func first_visit(save: CampaignProgress) -> void:
	progress = save
	show()
	panel.hide()
	_clear_finished_handlers()
	cinematic.finishing.connect(func():
		progress.prologue_seen = true
		progress.save(), CONNECT_ONE_SHOT)
	cinematic.finished.connect(func():
		panel.show()
		hide()
		closed.emit(), CONNECT_ONE_SHOT)
	cinematic.play(Content.campaign.get("prologue", []), Content.label("story_enter_terminal"))

func show_result(index: int, faction: String, won: bool, standings: Dictionary, save: CampaignProgress) -> void:
	progress = save
	side = faction
	chapter_index = index
	result_view = true
	show()
	_wipe(body)
	var chapter := CampaignRules.chapter(index)
	if chapter.is_empty():
		return
	body.add_child(NativeUi.label(Content.label("story_victory" if won else "story_defeat"), 32))
	body.add_child(NativeUi.prose(chapter[side].victory if won else chapter[side].defeat, 20))
	for faction_key: String in standings:
		var row: Dictionary = standings[faction_key]
		var creeps := str(int(row.creepKills)) if is_equal_approx(float(row.creepKills), roundf(row.creepKills)) else str(row.creepKills)
		body.add_child(NativeUi.label(Content.label("story_result_stats") % [Content.side_info(faction_key).name, int(row.kills), int(row.assists), int(row.deaths), creeps], 16))
	var transcript_scroll := ScrollContainer.new()
	transcript_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	transcript_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(transcript_scroll)
	var transcript := VBoxContainer.new()
	transcript.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	transcript_scroll.add_child(transcript)
	settlement_dialogue = CampaignDialogue.new()
	add_child(settlement_dialogue)
	settlement_dialogue.side = side
	settlement_dialogue.art_mode = progress.art_mode
	if won:
		settlement_dialogue.transcript(transcript, CampaignRules.talk(index, side, int(Content.constants.SIEGE.BASE)))
	var buttons := HBoxContainer.new()
	body.add_child(buttons)
	buttons.add_child(NativeUi.button(Content.label("story_return"), func(): return_requested.emit()))
	if won:
		var replay := NativeUi.button(Content.label("story_replay_talk"), func():
			settlement_dialogue.clear()
			_wipe(transcript)
			settlement_dialogue.transcript(transcript, CampaignRules.talk(index, side, int(Content.constants.SIEGE.BASE))))
		buttons.add_child(replay)
	_layout()
