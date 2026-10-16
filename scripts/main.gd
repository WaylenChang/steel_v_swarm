extends Node

const Minimap = preload("res://scripts/minimap.gd")

var touch_controls: NativeTouchControls
var gyro: NativeGyro
var scope_overlay: ScopeOverlay
var hurt_overlay: HurtOverlay
var splat_overlay: BloodSplatOverlay
var death_overlay: DeathOverlay
var death_sequence := DeathSequenceState.new()
var death_owner: BattleUnit
var death_was_dead := false
var death_live: Dictionary = {}
var scope_state := ScopeState.new()
var view_lock := ViewLockState.new()
var view_frame := Transform3D.IDENTITY
var view_projection := Projection()
var view_ready := false
var view_alive := false
var view_fov := 0.0
var player_view := PlayerViewState.new()
var view_motion := Vector2.ZERO
var view_firing := false
var view_occlusion := ViewOcclusion.new()
var ui: CanvasLayer
var root: Control
var backdrop: ColorRect
var campaign_ui: CampaignUi
var campaign_dialogue: CampaignDialogue
var campaign_progress := CampaignProgress.new()
var campaign_result_saved := false
var lobby: PanelContainer
var menu: PanelContainer
var shop: PanelContainer
var hud: Control
var stats: Label
var scoreboard: VBoxContainer
var score_rows: Dictionary = {}
var feed: BattleFeed
var civilian_prompt: Label
var lock_warning: Label
var boss_hud: BossHud
var locked_until := 0.0
var ammo_label: Label
var notice: Label
var room_label: Label
var map_select: OptionButton
var side_select: OptionButton
var super_select: CheckButton
var super_buy: Button
var super_auto: CheckButton
var super_detail: Label
var ordinary_shop_hint: Label
var super_request_level := -1
var super_request_at := -100.0
var character_select: OptionButton
var time_select: OptionButton
var weather_select: OptionButton
var season_select: OptionButton
var size_select: SpinBox
var bot_select: OptionButton
var address: LineEdit
var port: SpinBox
var start_button: Button
var minimap: Control
var simulation: BattleSimulation
var selected_slot := "light"
var aiming := false
var aim_request := 0
var aim_state_clock := -INF
var wheel_at := -100.0
var released_controls: Dictionary = {}
var yaw := 0.0
var pitch := 0.0
var held_jump := false
var overlay_open := false
var shop_buttons: Dictionary = {}
var creep_buttons: Array[Button] = []
var creep_shop_column: VBoxContainer
var smoke := false
var capture := false
var smoke_time := 0.0
var smoke_state_seen := false
var network_test := false
var network_lob_test := false
var network_lob_control_seen := false
var network_lob_shot_seen := false
var network_kinetic_test := false
var network_kinetic_light_seen := false
var network_kinetic_terminal_seen := false
var bound_pilot := 0
var bound_view_reset := -1
var capture_finished := false
var presentation_clock := 0.0
var body_frame := 0
var presentation_frame := PresentationFrame.new()

func _ready() -> void:
	death_sequence.output = _death_command
	campaign_progress.load_save()
	Session.battle_started.connect(_begin_battle)
	Session.status_changed.connect(_status)
	Session.lobby_changed.connect(_update_lobby)
	Session.state_received.connect(_receive_state)
	Session.body_event_received.connect(_body_event_feedback)
	Controls.set_view_pref(_argument("--view", Controls.view_pref), false)
	Controls.view_changed.connect(_view_preference_changed)
	player_view.preference_changed.connect(func(value): Controls.set_view_pref(value))
	if not Controls.rules.is_empty():
		gyro = NativeGyro.new()
		add_child(gyro)
		gyro.configure(Controls)
		get_viewport().size_changed.connect(func():
			gyro.state.reset_basis()
			_control_hud_layout())
		gyro.look.connect(func(change):
			if simulation != null and not overlay_open and not simulation.over:
				_look(change))
		Controls.set_pref(_argument("--ctrl", Controls.pref))
	_build_ui()
	view_lock.cycled.connect(func(index, count):
		feed.push_message(Content.label("view_lock_count") % [index, count] if count > 0 else Content.label("view_lock_empty_scope" if aiming else "view_lock_empty_front")))
	Controls.changed.connect(_control_preferences_changed)
	Controls.save_failed.connect(func(_error): _status("controls_save_failed"))
	var arguments := OS.get_cmdline_user_args()
	network_test = arguments.has("--network-test")
	network_lob_test = arguments.has("--network-lob-test")
	network_kinetic_test = arguments.has("--network-kinetic-test")
	Session.dedicated = arguments.has("--server")
	if Session.dedicated:
		ui.visible = false
		var server_port := int(_argument("--port", "8620"))
		var settings := {"map_index": int(_argument("--map", "0")), "team_size": int(_argument("--team-size", "1")), "super": arguments.has("--super"), "ctrl": Controls.pref, "env": {"weather": "clear", "time": "day"}}
		if arguments.has("--campaign"):
			var chapter := _argument("--campaign", "")
			var faction := _argument("--side", "STEEL")
			var chapters: Array = Content.campaign.get("chapters", [])
			var matches: Array = chapters.filter(func(item): return item.id == chapter)
			if matches.is_empty() or faction not in ["STEEL", "SWARM"]:
				get_tree().quit(1)
				return
			settings = CampaignRules.settings(chapters.find(matches[0]), faction, _argument("--character", matches[0][faction].heroes[0]))
			if settings.is_empty():
				get_tree().quit(1)
				return
			settings.map_index = 0
		if settings.map_index < 0 or settings.map_index >= Content.maps.size() or settings.team_size < 1 or settings.team_size > 5 or server_port < 1 or server_port > 65535:
			get_tree().quit(1)
			return
		var error := Session.host(settings, server_port, "websocket" if arguments.has("--websocket") else "enet")
		if error != OK:
			push_error(error_string(error))
			get_tree().quit(1)
		else:
			print("SERVER_READY port=", server_port)
	elif arguments.has("--smoke") or arguments.has("--capture"):
		smoke = arguments.has("--smoke")
		capture = arguments.has("--capture")
		_start_mode("offline")
	elif arguments.has("--connect"):
		Session.chosen_character = _argument("--character", "s01")
		Session.chosen_side = _argument("--side", "SWARM")
		var error := Session.join(_argument("--connect", "127.0.0.1"), int(_argument("--port", "8620")))
		if error != OK:
			get_tree().quit(1)
	elif arguments.has("--capture-lobby"):
		await get_tree().create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/lobby.png")
		get_tree().quit()
	elif arguments.has("--campaign"):
		var chapter_id := _argument("--campaign", "ch1")
		var chapters: Array = Content.campaign.get("chapters", [])
		var matches: Array = chapters.filter(func(item): return item.id == chapter_id)
		var faction := _argument("--side", "STEEL")
		if matches.is_empty() or faction not in ["STEEL", "SWARM"]:
			get_tree().quit(1)
			return
		_start_campaign(CampaignRules.settings(chapters.find(matches[0]), faction, _argument("--character", matches[0][faction].heroes[0])))
	elif arguments.has("--super"):
		_start_mode("offline")
	elif arguments.is_empty() and not campaign_progress.prologue_seen and not Content.campaign.get("prologue", []).is_empty():
		lobby.hide()
		campaign_ui.first_visit(campaign_progress)

func _argument(key: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	var index := args.find(key)
	return args[index + 1] if index >= 0 and index + 1 < args.size() else fallback

func _build_ui() -> void:
	var death_layers: Dictionary = Content.balance.get("deathOverlay", {}).get("layers", {})
	ui = CanvasLayer.new()
	add_child(ui)
	root = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(root)
	var theme := Theme.new()
	theme.default_font_size = 18
	if OS.has_feature("web"):
		theme.default_font = preload("res://assets/fonts/NotoSansTC.ttf")
	else:
		var font := SystemFont.new()
		font.font_names = PackedStringArray(["Microsoft JhengHei", "Noto Sans CJK TC", "sans-serif"])
		theme.default_font = font
	root.theme = theme
	backdrop = ColorRect.new()
	backdrop.color = Color("101b26")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop)
	lobby = _panel(Vector2(800, 740))
	root.add_child(lobby)
	var lobby_scroll := ScrollContainer.new()
	lobby_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lobby.add_child(lobby_scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	lobby_scroll.add_child(column)
	root.resized.connect(func():
		lobby.size = Vector2(minf(800, root.size.x - 24), minf(740, root.size.y - 24))
		lobby.position = -lobby.size / 2)
	var title := _label(Content.label("title"), 32)
	title.add_theme_color_override("font_color", Color("6cc8eb"))
	column.add_child(title)
	column.add_child(_label(Content.label("subtitle")))
	column.add_child(HSeparator.new())
	map_select = OptionButton.new()
	for map_data in Content.maps:
		map_select.add_item(map_data.name)
	_row(column, "map", map_select)
	size_select = SpinBox.new()
	size_select.min_value = 1
	size_select.max_value = 5
	size_select.value = 1
	_row(column, "team", size_select)
	bot_select = OptionButton.new()
	for key: String in Content.constants.BOT_DIFF_KEYS:
		bot_select.add_item(Content.constants.BOT_DIFF[key].name)
		bot_select.set_item_metadata(bot_select.item_count - 1, key)
		if key == Content.constants.DEFAULT_BOT_DIFF:
			bot_select.select(bot_select.item_count - 1)
	_row(column, "bot_difficulty", bot_select)
	side_select = OptionButton.new()
	for side in ["STEEL", "SWARM"]:
		side_select.add_item(Content.constants.SIDES[side].name)
	_row(column, "players", side_select)
	super_select = CheckButton.new()
	super_select.text = Content.label("super_mode")
	super_select.disabled = not Content.super_available()
	super_select.button_pressed = OS.get_cmdline_user_args().has("--super")
	column.add_child(super_select)
	character_select = OptionButton.new()
	_row(column, "character", character_select)
	side_select.item_selected.connect(func(_index): _refresh_characters())
	super_select.toggled.connect(func(_enabled): _refresh_characters())
	_refresh_characters()
	season_select = OptionButton.new()
	for key: String in Content.constants.ENV.seasons:
		season_select.add_item(Content.constants.ENV.seasons[key].name)
		season_select.set_item_metadata(season_select.item_count - 1, key)
	season_select.select(1)
	_row(column, "season", season_select)
	time_select = OptionButton.new()
	for key in ["day", "dusk", "night", "dawn"]:
		time_select.add_item(Content.constants.ENV.times[key].name)
		time_select.set_item_metadata(time_select.item_count - 1, key)
	_row(column, "time", time_select)
	weather_select = OptionButton.new()
	for key: String in Content.constants.ENV.weathers:
		weather_select.add_item(Content.constants.ENV.weathers[key].name)
		weather_select.set_item_metadata(weather_select.item_count - 1, key)
	_row(column, "weather", weather_select)
	address = LineEdit.new()
	address.text = "127.0.0.1"
	if not OS.has_feature("solo_web"):
		_row(column, "address", address)
	else:
		column.add_child(address)
		address.hide()
	port = SpinBox.new()
	port.min_value = 1
	port.max_value = 65535
	port.value = 8620
	if not OS.has_feature("solo_web"):
		_row(column, "port", port)
	else:
		column.add_child(port)
		port.hide()
	var buttons := HBoxContainer.new()
	for entry in [["solo", "offline"], ["host", "enet"], ["join", "join"]]:
		var mode: String = entry[1]
		if OS.has_feature("solo_web") and mode != "offline":
			continue
		buttons.add_child(_button(Content.label(entry[0]), func(): _start_mode(mode)))
	column.add_child(buttons)
	column.add_child(_button(Content.label("story_campaign"), _open_campaign))
	start_button = _button(Content.label("start"), Session.start_battle)
	start_button.visible = false
	column.add_child(start_button)
	room_label = _label("")
	column.add_child(room_label)
	var help := _label(Content.label("controls"), 15)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(help)
	column.add_child(_label(Content.label("pending"), 15))
	if gyro != null:
		var settings := ControlSettings.new()
		column.add_child(settings)
		settings.configure(Controls, gyro)
	Session.battle_started.connect(func(_settings, _players): backdrop.hide())
	if Content.balance.has("view"):
		scope_overlay = ScopeOverlay.new()
		root.add_child(scope_overlay)
	if Content.balance.has("hurtPresentation"):
		hurt_overlay = HurtOverlay.new()
		root.add_child(hurt_overlay)
	if Content.balance.get("screenSplats", {}).has("paint"):
		splat_overlay = BloodSplatOverlay.new()
		root.add_child(splat_overlay)
	if Content.balance.has("deathOverlay"):
		death_overlay = DeathOverlay.new()
		root.add_child(death_overlay)
	hud = Control.new()
	hud.z_index = int(death_layers.get("hud", 0))
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)
	hud.hide()
	boss_hud = BossHud.new()
	hud.add_child(boss_hud)
	boss_hud.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	boss_hud.position = Vector2(-250, 8)
	boss_hud.size = Vector2(500, 94)
	stats = _label("", 22)
	stats.position = Vector2(24, 20)
	hud.add_child(stats)
	scoreboard = VBoxContainer.new()
	scoreboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(scoreboard)
	feed = BattleFeed.new()
	hud.add_child(feed)
	feed.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	feed.position = Vector2(-730, 20)
	feed.size = Vector2(420, 0)
	feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ammo_label = _label("", 22)
	ammo_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	ammo_label.position = Vector2(24, -105)
	ammo_label.size = Vector2(950, 80)
	hud.add_child(ammo_label)
	civilian_prompt = _label("", 16)
	civilian_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	civilian_prompt.position = Vector2(-300, -50)
	civilian_prompt.size = Vector2(600, 40)
	civilian_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(civilian_prompt)
	lock_warning = _label(Content.label("lock_warning"), 24)
	lock_warning.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	lock_warning.position = Vector2(-180, 90)
	lock_warning.size = Vector2(360, 40)
	lock_warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lock_warning.add_theme_color_override("font_color", Color(1.0, 0.4, 0.25))
	lock_warning.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock_warning.hide()
	hud.add_child(lock_warning)
	var crosshair := _label("+", 28)
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-8, -20)
	hud.add_child(crosshair)
	minimap = Minimap.new()
	minimap.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	minimap.position = Vector2(-270, 20)
	minimap.size = Vector2(250, 220)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(minimap)
	menu = _panel(Vector2(640, 660))
	menu.z_index = int(death_layers.get("menu", 0))
	var menu_scroll := ScrollContainer.new()
	menu_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	menu.add_child(menu_scroll)
	var menu_column := VBoxContainer.new()
	menu_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_scroll.add_child(menu_column)
	menu_column.add_child(_label(Content.label("pause"), 26))
	menu_column.add_child(_button(Content.label("resume"), func(): _overlay(menu, false)))
	menu_column.add_child(_button(Content.label("leave"), _leave))
	if gyro != null:
		var settings := ControlSettings.new()
		menu_column.add_child(settings)
		settings.configure(Controls, gyro)
	root.resized.connect(func():
		menu.size = Vector2(minf(640, root.size.x - 24), minf(660, root.size.y - 24))
		menu.position = -menu.size / 2)
	root.add_child(menu)
	menu.hide()
	shop = _panel(Vector2(700, 610))
	shop.z_index = int(death_layers.get("shop", 0))
	var shop_column := VBoxContainer.new()
	shop_column.add_theme_constant_override("separation", 12)
	var shop_scroll := ScrollContainer.new()
	shop_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shop.add_child(shop_scroll)
	shop_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_scroll.add_child(shop_column)
	shop_column.add_child(_label(Content.label("shop"), 26))
	shop_column.add_child(_button(Content.label("resume"), func(): _overlay(shop, false)))
	shop_column.add_child(_label(Content.label("shop_hint"), 15))
	super_buy = _button(Content.label("super_upgrade"), func(): Session.act("buy", "super"))
	shop_column.add_child(super_buy)
	super_detail = _label("", 15)
	shop_column.add_child(super_detail)
	super_auto = CheckButton.new()
	super_auto.text = Content.label("super_auto")
	shop_column.add_child(super_auto)
	for item in Content.constants.ECON.UPGRADES:
		var track: String = item
		var button := _button(Content.constants.ECON.UPGRADES[item].name, func(): Session.act("buy", track))
		shop_column.add_child(button)
		shop_buttons[item] = button
	ordinary_shop_hint = _label(Content.label("creep_hint"), 14)
	shop_column.add_child(ordinary_shop_hint)
	creep_shop_column = VBoxContainer.new()
	creep_shop_column.add_theme_constant_override("separation", 8)
	shop_column.add_child(creep_shop_column)
	shop_column.add_child(_button(Content.label("close"), func(): _overlay(shop, false)))
	root.add_child(shop)
	shop.hide()
	campaign_ui = CampaignUi.new()
	campaign_ui.z_index = int(death_layers.get("menu", 0))
	root.add_child(campaign_ui)
	campaign_ui.deployment_requested.connect(_start_campaign)
	campaign_ui.closed.connect(func(): lobby.show(); backdrop.show())
	campaign_ui.return_requested.connect(_leave)
	campaign_dialogue = CampaignDialogue.new()
	campaign_dialogue.z_index = int(death_layers.get("dialogue", 0))
	root.add_child(campaign_dialogue)
	campaign_dialogue.hide()
	notice = _label("", 22)
	notice.z_index = int(death_layers.get("menu", 0))
	notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	notice.position = Vector2(-420, -170)
	notice.size = Vector2(840, 80)
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(notice)
	if gyro != null:
		touch_controls = NativeTouchControls.new()
		touch_controls.z_index = int(death_layers.get("touch", 0))
		root.add_child(touch_controls)
		touch_controls.configure(Controls)
		touch_controls.command.connect(_touch_command)
		touch_controls.look.connect(_look)
		touch_controls.set_gyro_status(gyro.status)
		gyro.status_changed.connect(func(key):
			touch_controls.set_gyro_status(key)
			if key in ["gyro_orientation_missing", "gyro_motion_missing"] and simulation != null:
				_status(key))
		touch_controls.hide()

func _panel(dimensions: Vector2) -> PanelContainer:
	return NativeUi.panel(dimensions)

func _label(value: String, font_size: int = 18) -> Label:
	return NativeUi.label(value, font_size)

func _button(value: String, callback: Callable) -> Button:
	return NativeUi.button(value, callback)

func _row(parent: VBoxContainer, key: String, control: Control) -> void:
	NativeUi.row(parent, key, control)

func _refresh_characters() -> void:
	character_select.clear()
	var side := "STEEL" if side_select.selected == 0 else "SWARM"
	side_select.disabled = super_select.button_pressed
	for id in Content.heroes:
		var hero: Dictionary = Content.heroes[id]
		if not super_select.button_pressed and hero.side not in [side, "MERC"]:
			continue
		character_select.add_item("%s · %s" % [hero.code, hero.name])
		character_select.set_item_metadata(character_select.item_count - 1, id)

func _start_mode(mode: String) -> void:
	Session.chosen_character = character_select.get_item_metadata(character_select.selected)
	Session.chosen_side = Content.constants.SUPER_SIDE if super_select.button_pressed else "STEEL" if side_select.selected == 0 else "SWARM"
	var error: Error
	if mode == "join":
		error = Session.join(address.text.strip_edges(), int(port.value))
	else:
		var settings := {"map_index": map_select.selected, "team_size": int(size_select.value), "super": super_select.button_pressed, "ctrl": Controls.pref,
			"env": {"season": season_select.get_item_metadata(season_select.selected), "time": time_select.get_item_metadata(time_select.selected),
				"weather": weather_select.get_item_metadata(weather_select.selected), "bot_difficulty": bot_select.get_item_metadata(bot_select.selected)}}
		error = Session.host(settings, int(port.value), mode)
	if error != OK:
		_status("host_failed" if mode != "join" else "failed")
		return
	if mode == "offline":
		Session.start_battle()
	elif mode != "join":
		start_button.show()
		_status("waiting")

func _update_lobby() -> void:
	var players := PackedStringArray()
	for player in Session.roster:
		players.append("%s · %s" % [Content.side_info(player.side).name, Content.heroes[player.character].code])
	room_label.text = "\n".join(players)
	start_button.visible = Session.active and Session.multiplayer.is_server() and not Session.started

func _begin_battle(settings: Dictionary, players: Array) -> void:
	_reset_death_view()
	aim_state_clock = -INF
	presentation_frame.clear()
	if simulation != null:
		simulation.queue_free()
	simulation = _create_simulation()
	add_child(simulation)
	var map_data: Dictionary = Content.campaign_map(int(settings.campaign.index), settings.campaign.side, settings.campaign.swapped) if settings.has("campaign") else Content.map_variant(int(settings.map_index), int(settings.team_size))
	if map_data.is_empty():
		_status("story_map_missing")
		return
	map_data.config["super"] = bool(settings.get("super", false)) and not settings.has("campaign")
	super_auto.button_pressed = map_data.config["super"]
	super_request_level = -1
	super_request_at = -100.0
	await simulation.setup(map_data, players, settings.env, Session.multiplayer.is_server())
	if simulation.world == null:
		return
	body_frame = 0
	_refresh_creep_shop()
	Session.simulation = simulation
	simulation.view_snapshot_ready.connect(_prepare_death_snapshot)
	simulation.death_presented.connect(presentation_frame.receive)
	if hurt_overlay != null:
		simulation.self_hurt.connect(hurt_overlay.flash)
	if splat_overlay != null:
		simulation.screen_hurt.connect(_screen_hurt)
	if simulation.authoritative:
		simulation.body_event.connect(Session.broadcast_body_event)
		simulation.body_event.connect(_body_event_feedback)
	view_occlusion.dispose()
	view_occlusion.register_root(simulation.world)
	for unit: BattleUnit in simulation.units.values():
		_register_body_occluders(unit)
	simulation.unit_spawned.connect(_register_body_occluders)
	simulation.unit_view_removed.connect(view_occlusion.unregister_root)
	if simulation.authoritative and not Session.dedicated:
		simulation.apply_presentation_view(simulation.snapshot(multiplayer.get_unique_id()))
	simulation.message.connect(func(peer, key):
		if peer == multiplayer.get_unique_id():
			_status(key))
	simulation.result.connect(_result)
	minimap.map_data = map_data
	minimap.side = Session.chosen_side
	minimap.missile_points.clear()
	lobby.hide()
	hud.show()
	notice.text = ""
	feed.clear()
	locked_until = 0
	lock_warning.hide()
	campaign_result_saved = false
	aiming = false
	selected_slot = "light"
	aim_request = 0
	released_controls.clear()
	view_lock.press(false)
	view_lock.clear_dead()
	view_lock.cycle = false
	view_lock.last_seek = 0
	view_ready = false
	view_alive = false
	view_motion = Vector2.ZERO
	view_firing = false
	bound_pilot = 0
	bound_view_reset = -1
	scope_state.clear()
	if scope_overlay != null:
		scope_overlay.clear()
	if hurt_overlay != null:
		hurt_overlay.clear()
	if splat_overlay != null:
		splat_overlay.reset_room()
	campaign_dialogue.dispose()
	campaign_dialogue.visible = settings.has("campaign")
	if settings.has("campaign"):
		campaign_dialogue.side = settings.campaign.side
		campaign_dialogue.art_mode = campaign_progress.art_mode
		campaign_ui.hide()
	_sync_touch()
	_control_hud_layout()
	var pilot: BattleUnit = simulation.pilots.get(multiplayer.get_unique_id())
	if pilot != null:
		yaw = pilot.yaw
		_bind_camera(pilot)

func _create_simulation() -> BattleSimulation:
	return BattleSimulation.new()

func _bind_camera(pilot: BattleUnit) -> void:
	var changed := bound_pilot != pilot.entity_id
	if changed or bound_view_reset != pilot.view_reset:
		yaw = pilot.yaw
		pitch = pilot.pitch
		bound_view_reset = pilot.view_reset
		bound_pilot = pilot.entity_id
		view_ready = false
		if changed and Content.balance.has("playerView"):
			player_view.configure(Content.balance.playerView, Controls.view_pref, yaw)
			yaw = player_view.set_aiming(aiming, yaw)
		elif not player_view.rules.is_empty():
			player_view.body_yaw = yaw
	if pilot.camera != null:
		pilot.camera.current = true
		pilot.render_view_mode = player_view.mode
		pilot.model.visible = player_view.mode == "tps" and pilot.alive()
		pilot.ensure_cockpit()
		pilot.cockpit.visible = player_view.mode != "tps" and pilot.alive()
		var echo_callback := simulation.present_echo.bind(pilot)
		if not pilot.cockpit.echo_fired.is_connected(echo_callback):
			pilot.cockpit.echo_fired.connect(echo_callback)

func _process(delta: float) -> void:
	if simulation == null or Session.dedicated:
		return
	presentation_clock += delta
	delta = presentation_frame.advance(delta)
	_advance_look(delta)
	lock_warning.visible = float(Time.get_ticks_msec()) / 1000.0 < locked_until
	if simulation.lock_glow != null:
		simulation.lock_glow.advance(float(Time.get_ticks_msec()) / 1000.0)
	var pilot: BattleUnit = simulation.pilots.get(multiplayer.get_unique_id())
	simulation.step_remote_shots(simulation.presentation_time())
	_advance_view(delta, pilot)
	if pilot != null and pilot.alive():
		_remember_death_view(pilot)
	if not death_sequence.state.is_empty() and not simulation.over:
		death_sequence.advance(delta, simulation.world.visual_surface)
		if is_instance_valid(death_owner) and death_owner.camera != null:
			death_owner.camera.global_transform = death_sequence.frame
	if splat_overlay != null:
		splat_overlay.observe(pilot)
		splat_overlay.advance(delta)
	body_frame = (body_frame + 1) & 0xffffffff
	if pilot != null and pilot.first_person_shield != null:
		pilot.first_person_shield.update_view(pilot, delta, simulation.presentation_time(), player_view.mode)
	simulation.present_bodies(delta, simulation.presentation_time(), body_frame, get_viewport().get_camera_3d(), player_view)
	if pilot != null and pilot.body != null and pilot.body.source_root != null:
		view_occlusion.update(simulation.presentation_time(), pilot.camera.global_transform, pilot.body,
			CameraPose.body_height(pilot.character, pilot.flying, SuperRules.body_scale(float(pilot.upgrades.get("super", 0)))), player_view.mode == "tps" and pilot.alive())
	boss_hud.update_view(simulation, pilot.camera if pilot != null else null, float(Time.get_ticks_msec()) / 1000.0)
	simulation.step_dissolve_ghosts(delta)
	simulation.step_missile_presentations(delta)
	minimap.missile_points = simulation.missile_presentations.values().map(func(view: MissilePresentation): return view.global_position)
	minimap.queue_redraw()
	simulation.step_damage_fx(delta, float(Time.get_ticks_msec()) / 1000.0)
	if pilot == null or pilot.cockpit == null:
		return
	var scope := aiming
	var clock := simulation.clock if simulation.authoritative else presentation_clock
	pilot.cockpit.update_view(pilot, selected_slot, scope, delta, clock, player_view.mode)
	pilot.cockpit.visible = player_view.mode != "tps" and (pilot.alive() or not death_sequence.state.is_empty())
	if simulation.authoritative:
		simulation.world.sync_projectile_view(simulation.projectile_view(pilot), simulation.clock)
	simulation.world.step_projectile_visuals(delta)
	simulation.world.sync_fogs(simulation._fog_snapshot() if simulation.authoritative else simulation.fog_view, pilot.side, clock)
	simulation.world.update_mine_view(pilot.global_position, clock)
	if touch_controls != null:
		touch_controls.set_kind(pilot.kind)
	var civilian := simulation.nearest_civilian(pilot)
	if touch_controls != null:
		touch_controls.show_civilian(civilian != null and not overlay_open)
	civilian_prompt.visible = civilian != null and not overlay_open
	if civilian != null:
		var appearance := CivilianRules.appearance(civilian.entity_id, int(civilian.special.profession))
		civilian_prompt.text = Content.label("civilian_prompt") % [appearance.occupation, Content.side_info(civilian.special.civil_side).name]

func _remember_death_view(pilot: BattleUnit) -> void:
	if pilot.camera == null:
		return
	death_live = {"eye": pilot.camera.global_transform, "position": pilot.global_position, "velocity": pilot.velocity,
		"angles": Vector3(pitch, yaw, 0), "flying": pilot.flying, "color": int(Color(Content.side_info(pilot.side).color).to_rgba32() >> 8)}

func _release_death_camera() -> void:
	if not is_instance_valid(death_owner) or death_owner.camera == null:
		return
	var camera := death_owner.camera
	var frame := camera.global_transform
	death_owner.presentation_camera_owned = false
	camera.top_level = false
	camera.global_transform = frame
	if death_owner.alive():
		death_owner.sync_view_camera()

func _reset_death_view() -> void:
	_release_death_camera()
	death_sequence.finish()
	death_owner = null
	death_was_dead = false
	death_live.clear()
	if death_overlay != null:
		death_overlay.clear()

func _observe_death_view(pilot: BattleUnit) -> void:
	if not is_instance_valid(death_owner) or death_owner != pilot:
		_release_death_camera()
		death_sequence.finish()
		death_owner = pilot
		death_was_dead = false
		death_live.clear()
	if pilot.alive():
		if death_was_dead:
			death_sequence.finish()
			_release_death_camera()
		death_was_dead = false
		return
	if death_was_dead or simulation.over:
		return
	death_was_dead = true
	if pilot.camera == null:
		return
	if death_live.is_empty():
		_remember_death_view(pilot)
	death_live.velocity = pilot.velocity
	death_live.flying = pilot.flying
	var camera := pilot.camera
	camera.fov = float(Content.constants.UNITS[pilot.kind].get("fovAir", Content.constants.UNITS[pilot.kind].fov)) if pilot.flying else float(Content.constants.UNITS[pilot.kind].fov)
	_set_aiming(false, false)
	if menu.visible:
		_overlay(menu, false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var effects := simulation.world.ensure_combat_effects()
	death_sequence.random_sample = effects._sample_random
	if not death_sequence.begin(death_live, simulation.world.visual_surface):
		return
	pilot.presentation_camera_owned = true
	camera.top_level = true
	camera.global_transform = death_sequence.frame
	if hurt_overlay != null:
		hurt_overlay.clear()

func _prepare_death_snapshot(state: Dictionary) -> void:
	if Session.dedicated:
		return
	var pilot: BattleUnit = simulation.pilots.get(multiplayer.get_unique_id())
	if pilot == null:
		return
	_bind_camera(pilot)
	if not simulation.authoritative:
		pilot.velocity = state.view_velocity
	_observe_death_view(pilot)

func _death_command(command: Dictionary) -> void:
	match command.type:
		"alert":
			if death_overlay != null:
				death_overlay.receive(command.on, command.flash)
			return
		"hitstop":
			presentation_frame.hold(float(command.seconds))
			return
		"cut":
			# The source's default wipe preference completes this callback synchronously.
			death_sequence.finish()
			return
	if simulation == null or simulation.world == null:
		return
	var effects := simulation.world.ensure_combat_effects()
	match command.type:
		"spark": effects.spark(command.point, float(command.radius), int(command.color))
		"explosion": effects.explosion(command.point, float(command.radius), int(command.color))
		"shock": effects.shock(command.point, float(command.radius), int(command.color))
		"mechanical": effects.mechanical_debris(command.point, command.big, command.accent)
		"comic": effects.comic(command.point, command.big, command.hue)
		"plume": effects.death_plume(command.point)
		"embers": effects.embers(command.point, int(command.count), float(command.spread))
		"smoke": effects.crash_smoke(command.point, float(command.size))
		"engulf": effects.engulf(command.frame)

func _advance_view(delta: float, pilot: BattleUnit) -> void:
	if not Content.balance.has("view"):
		return
	if pilot == null or pilot.camera == null:
		scope_state.clear()
		view_ready = false
		if scope_overlay != null:
			scope_overlay.clear()
		return
	var step := clampf(delta, 0, float(Content.balance.view.frameCap))
	var in_fire := false
	if not pilot.flying and not pilot.fluid_environment.get("air", false):
		for fire: Dictionary in simulation.fire_fields:
			var radius: float = float(Content.constants.HAZARDS[fire.kind].r) * float(fire.scale)
			if Vector2(pilot.position.x - fire.position.x, pilot.position.z - fire.position.z).length() <= radius:
				in_fire = true
				break
	scope_state.advance(step, in_fire, float(simulation.weather_dynamics.get("effectiveFog", 0)), pilot.alive())
	if scope_overlay != null:
		scope_overlay.update_view(scope_state, aiming and pilot.alive())
	if not pilot.alive():
		if view_alive:
			view_lock.clear_dead()
		view_alive = false
		view_ready = false
		if touch_controls != null:
			touch_controls.set_view_lock(false)
		return
	view_alive = true
	var camera := pilot.camera
	if not view_ready:
		view_frame = camera.global_transform
		view_projection = camera.get_camera_projection()
		view_fov = camera.fov
		view_ready = true
	var weapon := Content.weapon(pilot.character, selected_slot, pilot.combat_level(selected_slot))
	var reach := TargetingMath.maximum_range(weapon)
	var viewport := camera.get_viewport().get_visible_rect().size
	# Authority movement may add confusion turning after consuming raw input.
	var status_yaw := BotRules.wrap_pi(pilot.yaw - float(pilot.input_state.get("yaw", pilot.yaw))) if simulation.authoritative else 0.0
	if not player_view.rules.is_empty():
		var move := Basis(Vector3.UP, yaw + status_yaw) * Vector3(view_motion.x, 0, view_motion.y)
		if pilot.has_status("freeze_until", simulation.clock):
			move = Vector3.ZERO
		player_view.advance_body(step, move, yaw + status_yaw, pilot.defending, view_firing)
	var change := view_lock.advance(step, float(Time.get_ticks_msec()) / 1000.0, Vector2(yaw + status_yaw, pitch), view_frame.origin,
		reach, overlay_open or simulation.over or pilot.side.is_empty(),
		func(keep, full): return _view_acquire(pilot, viewport, reach, keep, full), _view_point)
	_look(change, true)
	if touch_controls != null:
		touch_controls.set_view_lock(view_lock.lit)
	# Presentation never writes authority angles or confirms a damage lock.
	# Acquisition reads the preceding rendered camera, as in the source loop.
	var frame: Transform3D
	if player_view.mode == "tps":
		frame = simulation.third_person_camera(pilot, yaw + status_yaw, pitch, camera.get_camera_projection())
	else:
		frame = Transform3D(pilot.recoil.basis(yaw + status_yaw, pitch), simulation.first_person_camera_origin_at(pilot, yaw + status_yaw))
	var unit_stats: Dictionary = Content.constants.UNITS[pilot.kind]
	var base: float = unit_stats.get("fovAir", unit_stats.get("fov", 68)) if pilot.flying else unit_stats.get("fov", 68)
	view_fov = ScopeState.fov_step(view_fov, float(unit_stats.get("zoomFov", base)) if aiming else base, step)
	camera.fov = view_fov
	var ring_y := pilot.body.ring_height(pilot.global_position.y) if pilot.body != null and pilot.body.source_root != null else NAN
	camera.global_transform = CameraPose.frame_ring(frame, camera.get_camera_projection(), Vector3(pilot.position.x, ring_y, pilot.position.z)) if player_view.mode == "tps" and is_finite(ring_y) else frame
	view_frame = camera.global_transform
	view_projection = camera.get_camera_projection()

func _view_candidates(pilot: BattleUnit) -> Array:
	var candidates: Array = []
	for target: BattleUnit in simulation.units.values():
		if not TargetingMath.foe(pilot.side, target.side, target.special.get("neutral", false)) or not target.alive() or not target.visible or target.model == null or not target.model.visible:
			continue
		var point := target.aim_point()
		if point.is_finite():
			candidates.append({"id": target.entity_id, "point": point})
	return candidates

func _view_acquire(pilot: BattleUnit, viewport: Vector2, reach: float, keep: int, full: bool) -> Variant:
	var candidates := _view_candidates(pilot)
	var radius := scope_state.radius(viewport)
	if not full and keep != 0:
		var current := candidates.filter(func(item): return int(item.id) == keep)
		if not TargetingMath.view_roster(pilot.global_position, view_frame, view_projection, viewport, current, reach, keep, aiming, radius, _view_obstruction).is_empty():
			return keep
	var roster := TargetingMath.view_roster(pilot.global_position, view_frame, view_projection, viewport, candidates, reach, keep, aiming, radius, _view_obstruction)
	return roster if full else TargetingMath.view_choice(roster, keep)

func _view_obstruction(start: Vector3, end: Vector3) -> float:
	var hit := simulation.world.obstruction_hit(start, end)
	return start.distance_to(hit.position) if not hit.is_empty() else INF

func _view_point(id: int) -> Vector3:
	var target: BattleUnit = simulation.units.get(id)
	if target == null or not target.alive() or not target.visible or target.model == null or not target.model.visible:
		return Vector3(INF, INF, INF)
	return target.aim_point()

func _control(action_name: String) -> float:
	var value := Input.get_action_strength(action_name)
	if action_name == "fire" and touch_controls != null and touch_controls.visible:
		value = float(Input.is_physical_key_pressed(KEY_KP_MULTIPLY))
		for device: int in Input.get_connected_joypads():
			value = maxf(value, float(Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_SHOULDER)))
	if released_controls.has(action_name):
		if value > 0:
			return 0.0
		released_controls.erase(action_name)
	return value

func _look(change: Vector2, system: bool = false) -> void:
	if simulation == null or overlay_open or simulation.over:
		return
	var pilot: BattleUnit = simulation.pilots.get(multiplayer.get_unique_id())
	var frozen := pilot != null and pilot.has_status("freeze_until", simulation.clock)
	var angles := InputRules.look(yaw, pitch, change, frozen, bool(Controls.values.get("invertX", false)), bool(Controls.values.get("invertY", false)), system)
	yaw = angles.x
	pitch = angles.y

func _set_aiming(on: bool, notify: bool = true) -> void:
	if aiming == on:
		return
	if not player_view.rules.is_empty():
		yaw = player_view.set_aiming(on, yaw)
	aiming = on
	selected_slot = "heavy" if aiming else "light"
	if not notify:
		return
	aim_request += 1
	Session.act("aim", ("on" if on else "off") + ":" + str(aim_request))

func _unhandled_input(event: InputEvent) -> void:
	if simulation == null or Session.dedicated:
		return
	if campaign_ui.visible:
		return
	if event is InputEventMouse and touch_controls != null and touch_controls.visible:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look(-event.relative * float(Content.balance.controls.mouseSensitivity))
	if event.is_action_pressed("pause"):
		_input_command("menu", true)
	if event.is_action_pressed("shop"):
		_input_command("shop", true)
	if overlay_open:
		return
	if event.is_action_pressed("aim"):
		var pilot: BattleUnit = simulation.pilots.get(multiplayer.get_unique_id())
		var now := Time.get_ticks_msec() / 1000.0
		if pilot != null and pilot.alive() and now - wheel_at >= float(Content.balance.controls.wheelCooldown):
			wheel_at = now
			_input_command("aim", true)
	var actions := {"stance_ability": "special", "reload": "reload", "defense": "def", "attack": "atk",
		"defend": "shield", "map": "map", "civ_follow": "civ_follow", "civ_away": "civ_away", "rise": "jump"}
	for action_name: String in actions:
		if event.is_action_pressed(action_name):
			_input_command(actions[action_name], true)

func _input_command(action: String, on: bool) -> void:
	if simulation == null or Session.dedicated or not on:
		return
	if action == "menu":
		_overlay(menu, not menu.visible)
		return
	if action == "shop":
		_overlay(shop, not shop.visible)
		return
	if overlay_open:
		return
	if action == "map":
		minimap.size = Vector2(600, 520) if minimap.size.x < 300 else Vector2(250, 220)
		_control_hud_layout()
		minimap.queue_redraw()
		return
	if action == "jump":
		held_jump = true
		return
	var pilot: BattleUnit = simulation.pilots.get(multiplayer.get_unique_id())
	if pilot == null or not pilot.alive():
		return
	match action:
		"aim": _set_aiming(not aiming)
		"special": Session.act("cast_stance")
		"def", "atk": Session.act("cast", action)
		"reload": Session.act("reload", selected_slot)
		"shield": Session.act("defend", "toggle")
		"civ_follow", "civ_away":
			var civilian := simulation.nearest_civilian(pilot)
			if civilian != null:
				Session.act(action, str(civilian.entity_id))

func _touch_command(action: String, on: bool) -> void:
	if action == "lock":
		if Content.balance.has("view"):
			view_lock.press(on)
		return
	if action == "gyro" and on:
		gyro.set_preference(not Controls.values.gyro)
		_status(gyro.status)
	elif action == "lefty" and on:
		Controls.set_value("lefty", not Controls.values.lefty)
	elif action.begins_with("unavailable_") and on:
		_status("touch_lock_pending" if action == "unavailable_lock" else "touch_squad_single")
	else:
		_input_command(action, on)

func _sync_touch() -> void:
	var in_battle := simulation != null and Session.started and not Session.dedicated and not campaign_ui.visible
	if touch_controls != null:
		touch_controls.sync(in_battle, overlay_open or simulation != null and simulation.over)
	if gyro != null:
		gyro.set_enabled(in_battle)
	if in_battle:
		var pad := Controls.scheme() == "pad"
		var mode := Input.MOUSE_MODE_VISIBLE if overlay_open or simulation.over or pad else Input.MOUSE_MODE_CAPTURED
		if Input.mouse_mode != mode:
			Input.mouse_mode = mode

func _control_preferences_changed() -> void:
	_suppress_held_controls()
	if touch_controls != null:
		touch_controls.reset()
	_sync_touch()
	_control_hud_layout()

func _view_preference_changed(value: String) -> void:
	if simulation == null or player_view.rules.is_empty():
		return
	yaw = player_view.select_mode(value, yaw)
	if player_view.mode != "tps":
		view_occlusion.clear()
	var pilot: BattleUnit = simulation.pilots.get(multiplayer.get_unique_id())
	if pilot != null:
		_bind_camera(pilot)

func _screen_hurt(event: Dictionary) -> void:
	if splat_overlay != null and simulation != null:
		splat_overlay.receive(event, simulation.pilots.get(multiplayer.get_unique_id()))

func _body_event_feedback(event: Dictionary) -> void:
	if simulation == null or event.get("type") != "weapon_fire" or not event.has("serial"):
		return
	var pilot: BattleUnit = simulation.pilots.get(multiplayer.get_unique_id())
	if pilot == null or int(event.actor) != pilot.entity_id:
		return
	_bind_camera(pilot)
	pilot.cockpit.fire_feedback(event)
	if event.get("empty_heavy", false) and aiming and int(event.get("aim_request", aim_request)) >= aim_request:
		aim_state_clock = maxf(aim_state_clock, float(event.clock))
		_set_aiming(false, false)

func _register_body_occluders(unit: BattleUnit) -> void:
	if unit.model != null:
		view_occlusion.register_root(unit.model)

func _control_hud_layout() -> void:
	if minimap == null:
		return
	var area := NativeUi.safe_area(hud)
	var inset_right := area.end.x - hud.size.x
	var inset_bottom := area.end.y - hud.size.y
	var mirrored := Controls.scheme() == "pad" and bool(Controls.values.get("screenLefty", false))
	minimap.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT if mirrored else Control.PRESET_TOP_RIGHT)
	minimap.position = Vector2(area.position.x + 20 if mirrored else inset_right - minimap.size.x - 20, area.position.y + 20)
	stats.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT if mirrored else Control.PRESET_TOP_LEFT)
	stats.position = Vector2(inset_right - 524 if mirrored else area.position.x + 24, area.position.y + 20)
	stats.size.x = 500
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if mirrored else HORIZONTAL_ALIGNMENT_LEFT
	ammo_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT if mirrored else Control.PRESET_BOTTOM_LEFT)
	ammo_label.position = Vector2(inset_right - 974 if mirrored else area.position.x + 24, inset_bottom - 105)
	ammo_label.size = Vector2(950, 80)
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if mirrored else HORIZONTAL_ALIGNMENT_LEFT
	feed.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT if mirrored else Control.PRESET_TOP_RIGHT)
	feed.position = Vector2(area.position.x + 290 if mirrored else inset_right - 730, area.position.y + 20)
	feed.size.x = 420

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and simulation != null and not Session.dedicated:
		_overlay(menu, true)

func _advance_look(delta: float) -> void:
	_sync_touch()
	if touch_controls != null:
		touch_controls.tick(delta)
	var sticks := Input.get_connected_joypads()
	if not sticks.is_empty() and not overlay_open:
		_look(Vector2(-Input.get_joy_axis(sticks[0], JOY_AXIS_RIGHT_X), -Input.get_joy_axis(sticks[0], JOY_AXIS_RIGHT_Y)) * delta * 2)
	if not overlay_open:
		var keys: Dictionary = {}
		for digit: int in [1, 2, 3, 4, 6, 7, 8, 9]:
			keys["Numpad" + str(digit)] = _control("look_" + str(digit)) > 0
		var pad := InputRules.numpad(keys)
		_look(pad * float(Content.balance.controls.numpadLookSpeed) * delta)

func _physics_process(delta: float) -> void:
	if simulation == null or Session.dedicated:
		return
	var motion := Vector2(_control("right") - _control("left"), _control("back") - _control("forward")).limit_length()
	var touch: Dictionary = touch_controls.held if touch_controls != null and touch_controls.visible else {}
	if motion == Vector2.ZERO and touch_controls != null and touch_controls.visible:
		motion = touch_controls.state.axis
	var pilot: BattleUnit = simulation.pilots.get(multiplayer.get_unique_id())
	if pilot != null and not pilot.alive():
		touch["fire"] = false
		if Input.get_action_strength("fire") > 0:
			released_controls["fire"] = true
	var command := {"move": motion if not overlay_open else Vector2.ZERO,
		"yaw": yaw, "pitch": pitch, "vertical": maxf(_control("rise"), float(touch.get("jump", false))) - maxf(_control("descend"), float(touch.get("dive", false))) if not overlay_open else 0.0,
		"jump": held_jump and not overlay_open, "fire": (_control("fire") > 0 or touch.get("fire", false)) and not overlay_open,
		"jump_held": (_control("rise") > 0 or touch.get("jump", false)) and not overlay_open,
		"level_move": bool(Controls.values.get("levelMove", false)),
		"slot": selected_slot, "aim": aiming,
		"view_mode": player_view.mode if not player_view.mode.is_empty() else "fpv",
		"view_restore": player_view.restore,
		"sprint": (_control("sprint") > 0 or touch.get("sprint", false)) and not overlay_open}
	view_motion = command.move
	view_firing = command.fire
	held_jump = false
	if network_lob_test:
		command.aim = true
		command.fire = true
		command.slot = "heavy"
		command.pitch = -0.15
		selected_slot = "heavy"
	if network_kinetic_test:
		command.aim = true
		command.fire = true
		command.slot = "heavy" if smoke_time > 1 else "light"
		command.pitch = -0.15
		selected_slot = command.slot
	var submitted := command.duplicate()
	if not network_lob_test and not network_kinetic_test and not smoke and not capture:
		submitted.erase("aim")
		submitted.erase("slot")
	Session.command(submitted)
	var local_pilot: BattleUnit = simulation.pilots.get(multiplayer.get_unique_id())
	if local_pilot != null and local_pilot.camera != null and not local_pilot.presentation_camera_owned:
		if not simulation.authoritative:
			local_pilot.yaw = yaw
			local_pilot.pitch = pitch
			local_pilot.sync_view_camera()
		var unit_stats: Dictionary = Content.constants.UNITS[local_pilot.kind]
		local_pilot.camera.fov = unit_stats.get("zoomFov", 35) if command.aim else unit_stats.get("fov", 68)
	if network_test:
		smoke_time += delta
		var lob_ready := not network_lob_test or (network_lob_control_seen and network_lob_shot_seen)
		var kinetic_ready := not network_kinetic_test or (network_kinetic_light_seen and network_kinetic_terminal_seen)
		if smoke_time > 3 and smoke_state_seen and simulation.pilots.has(multiplayer.get_unique_id()) and lob_ready and kinetic_ready:
			print("NETWORK_PASS peer=", multiplayer.get_unique_id(), " units=", simulation.units.size())
			if network_lob_test:
				print("NETWORK_LOB_PASS control=", network_lob_control_seen, " shot=", network_lob_shot_seen)
			if network_kinetic_test:
				print("NETWORK_KINETIC_PASS light=", network_kinetic_light_seen, " heavyTerminal=", network_kinetic_terminal_seen)
			Session.stop()
			get_tree().quit()
		elif smoke_time > 10:
			push_error("NETWORK_TEST_TIMEOUT")
			get_tree().quit(1)
	if (smoke or capture) and not capture_finished:
		smoke_time += delta
		if smoke_time > 6:
			capture_finished = true
			if capture:
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("res://tests/battle.png")
				simulation.world._exit_tree()
			var invalid_positions := false
			for unit: BattleUnit in simulation.units.values():
				if not unit.position.is_finite():
					invalid_positions = true
			var ground_supported := local_pilot != null and (local_pilot.flying or local_pilot.is_on_floor())
			if smoke and (simulation.units.size() < 10 or not smoke_state_seen or invalid_positions or not ground_supported):
				push_error("SMOKE_FAILED")
				get_tree().quit(1)
			else:
				print("SMOKE_PASS units=", simulation.units.size(), " wave=", simulation.wave)
				get_tree().quit()

func _receive_state(state: Dictionary) -> void:
	smoke_state_seen = true
	presentation_clock = state.clock
	if simulation == null:
		return
	if Session.config.has("campaign"):
		var stages: Dictionary = state.get("siege", {}).get("open", {})
		var foe := "SWARM" if Session.config.campaign.side == "STEEL" else "STEEL"
		campaign_dialogue.track(int(stages.get(foe, -1)))
		for event: Dictionary in state.events:
			if event.type == "siege_talk" and event.side == foe and int(event.stage) < int(Content.constants.SIEGE.BASE):
				campaign_dialogue.radio(CampaignRules.talk(int(Session.config.campaign.index), Session.config.campaign.side, int(event.stage)))
	minimap.state = state
	minimap.queue_redraw()
	simulation.world.sync_projectile_view(state.get("projectile_view", []), float(state.clock))
	if Session.multiplayer.is_server():
		simulation.apply_presentation_view(state)
		simulation.receive_body_events(state.events, simulation.presentation_time())
		simulation.present_world_events(state.events)
	var pilot: BattleUnit = simulation.pilots.get(multiplayer.get_unique_id())
	if pilot == null:
		return
	_bind_camera(pilot)
	var aim_control: Dictionary = state.get("aim_control", {})
	if not aim_control.is_empty() and int(aim_control.request) >= aim_request and float(state.clock) >= aim_state_clock:
		_set_aiming(bool(aim_control.on), false)
	if not simulation.authoritative:
		simulation.apply_owner_recoil(state)
		pilot.sync_view_camera()
	for event: Dictionary in state.events:
		_supply_notice(event, pilot)
	simulation.apply_footprint({} if shop.visible else state.get("footprint", {}), state.get("lock", {}))
	simulation.apply_skill_footprint(state.get("skill_footprint", {}))
	var lock_changed := simulation.apply_lock_glow(state.get("lock", {}))
	if lock_changed:
		var target: BattleUnit = simulation.units.get(simulation.lock_glow.target_id)
		feed.push_message(Content.label("lock_notice") % Content.constants.UNITS.get(target.kind, {}).get("name", target.kind))
	for event: Dictionary in state.events:
		locked_until = LockGlowPresentation.warning_until(locked_until, event, pilot.peer_id, float(Time.get_ticks_msec()) / 1000.0)
		if event.type == "hurt" and int(event.get("attacker", 0)) == pilot.entity_id and int(event.actor) == simulation.lock_glow.target_id:
			simulation.lock_glow.flash(float(Time.get_ticks_msec()) / 1000.0)
	var control: Dictionary = state.get("fire_control", {})
	if network_kinetic_test:
		for event in state.events:
			if event.type != "shot" or int(event.actor) != pilot.entity_id:
				continue
			if event.get("slot") == "light" and event.start.distance_to(event.end) < 20:
				network_kinetic_light_seen = true
			if event.get("slot") == "heavy" and event.get("terminal", false):
				network_kinetic_terminal_seen = true
	if network_lob_test:
		if not control.is_empty() and control.points is PackedVector3Array and control.points.size() > 1:
			var actor_state: Dictionary = state.units.filter(func(actor): return int(actor.peer) == multiplayer.get_unique_id())[0]
			var eye: Vector3 = actor_state.position + Vector3.UP * Content.heroes[actor_state.character].height * Content.constants.SELF_F.eye
			if not control.origin.is_finite() or control.points[0].distance_to(control.origin) > 0.01 or control.origin.distance_to(eye) < 0.1:
				push_error("NETWORK_LOB_ORIGIN_MISMATCH")
				get_tree().quit(1)
			network_lob_control_seen = true
		for event in state.events:
			if event.type == "shot" and int(event.actor) == pilot.entity_id and event.start.distance_to(event.end) < 20:
				network_lob_shot_seen = true
	simulation.world.aim_arc(control)
	_bind_camera(pilot)
	if not simulation.authoritative:
		pilot.yaw = yaw
		pilot.pitch = pitch
		pilot.sync_view_camera()
	pilot.cockpit.control = control
	for event: Dictionary in state.events:
		if event.type == "weapon_fire" and int(event.actor) == pilot.entity_id:
			pilot.cockpit.fire_feedback(event)
	pilot.cockpit.sync_authority_pose(state.weapon_pose)
	stats.text = "%s %.0f/%.0f  |  %s %.0f/%.0f  |  %s %.0f\n%s %.0f  |  %s %.0f  |  %s %d" % [
		Content.label("hp"), pilot.hp, pilot.max_hp, Content.label("shield"), pilot.shield, pilot.max_shield,
		Content.label("power"), pilot.power, Content.label("credits"), pilot.money,
		Content.label("score"), pilot.score, Content.label("wave"), int(state.wave)]
	stats.text += "\n%s %.0f/%.0f" % [Content.label("lift"), maxf(0, pilot.lift), Content.constants.FLIGHT.LIFT_MAX]
	if pilot.defending:
		stats.text += " · " + Content.label("defending")
	for slot: String in ["def", "atk"]:
		var ability := Content.ability(pilot.character, slot, pilot.combat_level(slot))
		var cooldown: float = pilot.cooldowns.get(slot, 0)
		var remaining := 1 if cooldown <= state.clock else 0
		if int(ability.charges) > 1:
			var charge: Dictionary = pilot.ability_charges.get(slot, {})
			var deadlines: Array = charge.get("recharge_at", []).filter(func(deadline): return float(deadline) > state.clock)
			remaining = maxi(0, int(ability.charges) - deadlines.size())
			cooldown = deadlines.min() if remaining == 0 and not deadlines.is_empty() else 0.0
		stats.text += "\n%s · %s %d/%d" % [ability.name, Content.label("charges"), remaining, int(ability.charges)]
		if cooldown > state.clock:
			stats.text += " · %.1f" % (cooldown - state.clock)
	if not pilot.cast_state.is_empty():
		stats.text += "\n%s %.1f" % [Content.label("casting"), maxf(0, float(pilot.cast_state.start) + float(pilot.cast_state.duration) - state.clock)]
	scoreboard.position = Vector2(stats.position.x, stats.position.y + stats.get_minimum_size().y + 12)
	var standings: Dictionary = state.get("stats", {})
	for side: String in standings:
		if not score_rows.has(side):
			var row := _label("", 16)
			row.add_theme_color_override("font_color", Color(Content.side_info(side).color))
			scoreboard.add_child(row)
			score_rows[side] = row
		var total: Dictionary = standings[side]
		score_rows[side].text = Content.label("match_stats") % [Content.side_info(side).name, int(total.kills), int(total.assists), str(total.creepKills), int(total.deaths)]
	for side: String in score_rows:
		score_rows[side].visible = standings.has(side)
	var definition := Content.weapon(pilot.character, selected_slot, pilot.combat_level(selected_slot))
	ammo_label.text = "%s\n%s %d/%d" % [definition.name, Content.label("ammo"), int(pilot.ammo.get(selected_slot, 0)), int(definition.mag)]
	if pilot.reload_at.has(selected_slot):
		ammo_label.text += " · %s %.1f" % [Content.label("reload"), maxf(0, pilot.reload_at[selected_slot] - state.clock)]
	if not control.is_empty():
		var status := "lob_close" if control.close else "lob_blocked" if not control.ok else "lob_aa" if control.aa else "lob_high" if control.high else "lob_45"
		ammo_label.text += " · " + Content.label(status)
	var lock_state: Dictionary = state.get("lock", {})
	if not lock_state.is_empty() and int(lock_state.get("anchor", 0)) != 0:
		ammo_label.text += " · " + Content.label("locked")
	var reachability: Dictionary = state.get("reachability", {})
	if not reachability.is_empty() and reachability.slot == selected_slot:
		var status := "reach_warning" if reachability.warn else "reach_clear" if reachability.ok else "reach_blocked"
		ammo_label.text += " · " + Content.label(status)
	if not pilot.alive():
		notice.text = "" if not death_sequence.state.is_empty() else Content.label("boss_down") if pilot.special.get("boss", false) else "%s %.1f" % [Content.label("respawn"), maxf(0, pilot.respawn_at - state.clock)]
	elif not state.over and notice.text.begins_with(Content.label("respawn")):
		notice.text = ""
	for item in shop_buttons:
		shop_buttons[item].visible = pilot.side != Content.constants.SUPER_SIDE
		var level: int = int(pilot.upgrades[item])
		var def: Dictionary = Content.constants.ECON.UPGRADES[item]
		var button: Button = shop_buttons[item]
		if level >= int(def.max):
			button.text = "%s · %s" % [def.name, Content.label("max")]
			button.disabled = true
		else:
			var step: Dictionary = Content.constants.ECON.UPG_STEPS[level]
			button.text = "%s Lv%d · $%d · %s %d" % [def.name, level, int(step.price), Content.label("score"), int(step.score)]
			button.disabled = pilot.money < step.price or pilot.score < step.score
	var levels: Array = simulation.creep_upgrades.get(pilot.side, [])
	var super_pilot: bool = pilot.side == Content.constants.SUPER_SIDE
	super_buy.visible = super_pilot
	super_auto.visible = super_pilot
	super_detail.visible = super_pilot
	ordinary_shop_hint.visible = not super_pilot
	creep_shop_column.visible = not super_pilot
	if super_pilot:
		var level := int(pilot.upgrades.get("super", 0))
		var full := level >= int(Content.constants.SUPER_UPG.MAX)
		super_buy.text = Content.label("super_upgrade_state") % [level, int(Content.constants.SUPER_UPG.MAX), int(Content.constants.SUPER_UPG.PRICE)]
		super_buy.disabled = full or pilot.money < float(Content.constants.SUPER_UPG.PRICE)
		super_detail.text = Content.label("super_growth") % [SuperRules.combat_level(level), SuperRules.body_scale(level)]
		if full:
			super_auto.button_pressed = false
		var now := Time.get_ticks_msec() / 1000.0
		if not state.over and super_auto.button_pressed and not super_buy.disabled and (super_request_level != level or now - super_request_at >= float(Content.balance["super"].reserveResend)):
			super_request_level = level
			super_request_at = now
			Session.act("buy", "super")
	for lane in range(creep_buttons.size()):
		var button: Button = creep_buttons[lane]
		var level: int = int(levels[lane]) if lane < levels.size() else 0
		var rule: Dictionary = Content.constants.CREEP_UPG
		button.text = "%s %d · Lv%d · $%d" % [Content.label("creep_upgrade"), lane + 1, level, int(rule.PRICE)]
		button.disabled = lane >= levels.size() or not simulation.upgrades_maxed(pilot) or level >= int(rule.MAX) or pilot.money < rule.PRICE

func _refresh_creep_shop() -> void:
	if creep_shop_column == null:
		return
	creep_buttons.clear()
	for child: Node in creep_shop_column.get_children():
		child.queue_free()
	for lane in range(simulation.world.paths.size()):
		var selected_lane := lane
		var button := _button(Content.label("creep_upgrade"), func(): Session.act("buy_creep", str(selected_lane)))
		creep_shop_column.add_child(button)
		creep_buttons.append(button)

func _suppress_held_controls() -> void:
	held_jump = false
	view_lock.press(false)
	for action_name: String in ["forward", "back", "left", "right", "rise", "descend", "sprint", "fire", "look_1", "look_2", "look_3", "look_4", "look_6", "look_7", "look_8", "look_9"]:
		if Input.get_action_strength(action_name) > 0:
			released_controls[action_name] = true

func _overlay(panel: Control, show_panel: bool) -> void:
	if show_panel:
		_suppress_held_controls()
	menu.hide()
	shop.hide()
	panel.visible = show_panel
	if panel == shop and show_panel and simulation != null:
		simulation.apply_footprint({})
	overlay_open = show_panel
	_sync_touch()

func _result(winner: String) -> void:
	if Session.dedicated:
		return
	death_sequence.finish()
	if Session.config.has("campaign"):
		var selection: Dictionary = Session.config.campaign
		var won: bool = winner == selection.side
		if won and not campaign_result_saved:
			campaign_result_saved = true
			if campaign_progress.mark_cleared(selection.side, selection.chapter) != OK:
				notice.text = Content.label("story_save_failed")
		campaign_dialogue.dispose()
		campaign_dialogue.hide()
		campaign_ui.show_result(int(selection.index), selection.side, won, simulation.match_stats, campaign_progress)
		menu.hide()
		shop.hide()
		overlay_open = true
		_sync_touch()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	notice.text = Content.label("super_result") % Content.side_info(winner).name if Session.chosen_side == Content.constants.SUPER_SIDE else Content.label("victory" if winner == Session.chosen_side else "defeat")
	_overlay(menu, true)

func _supply_notice(event: Dictionary, pilot: BattleUnit) -> void:
	var own := int(event.get("peer", 0)) == pilot.peer_id or int(event.get("actor", 0)) == pilot.entity_id
	match event.type:
		"civact":
			if own:
				feed.push_message(Content.label("civilian_away" if event.action == "away" else "civilian_follow"))
		"civfree":
			if own:
				feed.push_message(Content.label("civilian_freed") % int(event.count))
		"civaid":
			if own:
				var name: String = CivilianRules.appearance(int(event.civilian), int(event.profession)).occupation
				var reward := Content.label("civilian_medkit") % [int(event.hp), int(event.shield)] if event.reward == "medkit" else Content.label("civilian_battery") % [int(event.power), float(event.cooldown)] if event.reward == "battery" else Content.label("civilian_money") % int(event.value)
				feed.push_message(Content.label("civilian_aid") % [name, reward])
		"civkill":
			if own:
				var who := Content.label("civilian_enemy_spy" if event.spy and event.civil_side != pilot.side else "civilian_own_spy" if event.spy else "civilian_enemy" if event.civil_side != pilot.side else "civilian_own")
				feed.push_message(Content.label("civilian_killed") % [who, int(event.value)])
		"airfall":
			feed.push_message(Content.label("airfall") % int(event.count))
		"airdrop":
			if own:
				var size_name := Content.label("airdrop_size_" + str(event.size))
				match event.reward:
					"medkit": feed.push_message(Content.label("airdrop_medkit") % [size_name, int(event.hp), int(event.shield)])
					"battery": feed.push_message(Content.label("airdrop_battery") % [size_name, int(event.power), float(event.cooldown)])
					_: feed.push_message(Content.label("airdrop_money") % [size_name, int(event.value)])
			elif event.side != pilot.side:
				feed.push_message(Content.label("airdrop_enemy") % Content.side_info(event.side).name)
		"loot":
			if not own:
				return
			if event.get("ammo", false):
				feed.push_message(Content.label("loot_ammo"))
			elif event.get("affix", "") != "":
				var affix: Dictionary = Content.constants.AFFIXES[event.affix]
				feed.push_message(Content.label("loot_affix") % [affix.name, affix.desc, float(affix.dur)])
			else:
				feed.push_message(Content.label("loot_money") % int(event.value))
		"relay":
			if event.side == pilot.side:
				feed.push_message(Content.label("relay_allied") % int(Content.constants.FIELD.RELAY.VISION_S))
			else:
				feed.push_message(Content.label("relay_enemy") % Content.side_info(event.side).name)
		"sam":
			if int(event.get("target_peer", 0)) == pilot.peer_id or int(event.get("target", 0)) == pilot.entity_id:
				feed.push_message(Content.label("ambush_warning"))
		"mine_blast":
			if own:
				feed.push_message(Content.label("mine_warning"))
		"siege":
			var stage: int = int(event.stage)
			if stage >= 0 and stage < Content.constants.SIEGE.NAMES.size():
				feed.push_message(Content.label("siege_allied" if event.side == pilot.side else "siege_enemy") % Content.constants.SIEGE.NAMES[stage])

func _status(key: String) -> void:
	notice.text = Content.label(key)
	if key in ["disconnected", "failed"] and simulation != null:
		_leave()

func _leave() -> void:
	_reset_death_view()
	view_occlusion.dispose()
	var selection: Dictionary = Session.config.get("campaign", {}).duplicate()
	campaign_dialogue.dispose()
	campaign_dialogue.hide()
	campaign_ui.cinematic.dispose()
	Session.stop()
	view_lock.press(false)
	view_lock.clear_dead()
	view_ready = false
	scope_state.clear()
	if scope_overlay != null:
		scope_overlay.clear()
	if touch_controls != null:
		touch_controls.sync(false, true)
	if gyro != null:
		gyro.set_enabled(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not selection.is_empty():
		if simulation != null:
			simulation.set_physics_process(false)
			simulation.queue_free()
			simulation = null
		hud.hide()
		menu.hide()
		shop.hide()
		overlay_open = false
		bound_pilot = 0
		selected_slot = "light"
		campaign_ui.open(campaign_progress, selection.side)
		return
	get_tree().reload_current_scene()

func _open_campaign() -> void:
	if Session.active:
		return
	lobby.hide()
	campaign_ui.open(campaign_progress, "STEEL" if side_select.selected == 0 else "SWARM")

func _start_campaign(settings: Dictionary) -> void:
	if settings.is_empty():
		_status("story_content_missing")
		return
	var error := Session.host(settings, int(port.value), "offline")
	if error != OK:
		_status("story_map_missing" if error == ERR_UNAVAILABLE else "host_failed")
		campaign_ui.open(campaign_progress, settings.campaign.side)
		return
	Session.start_battle()
