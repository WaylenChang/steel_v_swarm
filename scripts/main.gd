extends Node

const Minimap = preload("res://scripts/minimap.gd")

var ui: CanvasLayer
var root: Control
var lobby: PanelContainer
var menu: PanelContainer
var shop: PanelContainer
var hud: Control
var stats: Label
var ammo_label: Label
var notice: Label
var room_label: Label
var map_select: OptionButton
var side_select: OptionButton
var character_select: OptionButton
var time_select: OptionButton
var weather_select: OptionButton
var size_select: SpinBox
var address: LineEdit
var port: SpinBox
var start_button: Button
var minimap: Control
var simulation: BattleSimulation
var selected_slot := "light"
var yaw := 0.0
var pitch := 0.0
var held_jump := false
var overlay_open := false
var shop_buttons: Dictionary = {}
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
var capture_finished := false
var presentation_clock := 0.0

func _ready() -> void:
	Session.battle_started.connect(_begin_battle)
	Session.status_changed.connect(_status)
	Session.lobby_changed.connect(_update_lobby)
	Session.state_received.connect(_receive_state)
	_build_ui()
	var arguments := OS.get_cmdline_user_args()
	network_test = arguments.has("--network-test")
	network_lob_test = arguments.has("--network-lob-test")
	network_kinetic_test = arguments.has("--network-kinetic-test")
	Session.dedicated = arguments.has("--server")
	if Session.dedicated:
		ui.visible = false
		var server_port := int(_argument("--port", "8620"))
		var settings := {"map_index": int(_argument("--map", "0")), "team_size": int(_argument("--team-size", "1")), "env": {"weather": "clear", "time": "day"}}
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

func _argument(key: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	var index := args.find(key)
	return args[index + 1] if index >= 0 and index + 1 < args.size() else fallback

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(root)
	var theme := Theme.new()
	theme.default_font_size = 18
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft JhengHei", "Noto Sans CJK TC", "sans-serif"])
	theme.default_font = font
	root.theme = theme
	var backdrop := ColorRect.new()
	backdrop.color = Color("101b26")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop)
	lobby = _panel(Vector2(800, 740))
	root.add_child(lobby)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	lobby.add_child(column)
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
	side_select = OptionButton.new()
	for side in ["STEEL", "SWARM"]:
		side_select.add_item(Content.constants.SIDES[side].name)
	_row(column, "players", side_select)
	character_select = OptionButton.new()
	_row(column, "character", character_select)
	side_select.item_selected.connect(func(_index): _refresh_characters())
	_refresh_characters()
	time_select = OptionButton.new()
	for key in ["day", "dusk", "night"]:
		time_select.add_item(Content.label(key))
	_row(column, "time", time_select)
	weather_select = OptionButton.new()
	for key in ["clear", "fog"]:
		weather_select.add_item(Content.label(key))
	_row(column, "weather", weather_select)
	address = LineEdit.new()
	address.text = "127.0.0.1"
	_row(column, "address", address)
	port = SpinBox.new()
	port.min_value = 1
	port.max_value = 65535
	port.value = 8620
	_row(column, "port", port)
	var buttons := HBoxContainer.new()
	for entry in [["solo", "offline"], ["host", "enet"], ["join", "join"]]:
		var mode: String = entry[1]
		buttons.add_child(_button(Content.label(entry[0]), func(): _start_mode(mode)))
	column.add_child(buttons)
	start_button = _button(Content.label("start"), Session.start_battle)
	start_button.visible = false
	column.add_child(start_button)
	room_label = _label("")
	column.add_child(room_label)
	var help := _label(Content.label("controls"), 15)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(help)
	column.add_child(_label(Content.label("pending"), 15))
	Session.battle_started.connect(func(_settings, _players): backdrop.hide())
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)
	hud.hide()
	stats = _label("", 22)
	stats.position = Vector2(24, 20)
	hud.add_child(stats)
	ammo_label = _label("", 22)
	ammo_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	ammo_label.position = Vector2(24, -105)
	ammo_label.size = Vector2(950, 80)
	hud.add_child(ammo_label)
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
	menu = _panel(Vector2(440, 230))
	var menu_column := VBoxContainer.new()
	menu.add_child(menu_column)
	menu_column.add_child(_label(Content.label("pause"), 26))
	menu_column.add_child(_button(Content.label("resume"), func(): _overlay(menu, false)))
	menu_column.add_child(_button(Content.label("leave"), _leave))
	root.add_child(menu)
	menu.hide()
	shop = _panel(Vector2(700, 610))
	var shop_column := VBoxContainer.new()
	shop_column.add_theme_constant_override("separation", 12)
	shop.add_child(shop_column)
	shop_column.add_child(_label(Content.label("shop"), 26))
	shop_column.add_child(_label(Content.label("shop_hint"), 15))
	for item in Content.constants.ECON.UPGRADES:
		var track: String = item
		var button := _button(Content.constants.ECON.UPGRADES[item].name, func(): Session.act("buy", track))
		shop_column.add_child(button)
		shop_buttons[item] = button
	shop_column.add_child(_button(Content.label("close"), func(): _overlay(shop, false)))
	root.add_child(shop)
	shop.hide()
	notice = _label("", 22)
	notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	notice.position = Vector2(-420, -170)
	notice.size = Vector2(840, 80)
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(notice)

func _panel(dimensions: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.position = -dimensions / 2
	panel.size = dimensions
	var style := StyleBoxFlat.new()
	style.bg_color = Color("162736")
	style.border_color = Color("4a7185")
	style.set_border_width_all(1)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _label(value: String, font_size: int = 18) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size.y = 40
	button.pressed.connect(callback)
	return button

func _row(parent: VBoxContainer, key: String, control: Control) -> void:
	var row := HBoxContainer.new()
	var label := _label(Content.label(key))
	label.custom_minimum_size.x = 210
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	parent.add_child(row)

func _refresh_characters() -> void:
	character_select.clear()
	var side := "STEEL" if side_select.selected == 0 else "SWARM"
	for id in Content.heroes:
		var hero: Dictionary = Content.heroes[id]
		if hero.side not in [side, "MERC"]:
			continue
		character_select.add_item("%s · %s" % [hero.code, hero.name])
		character_select.set_item_metadata(character_select.item_count - 1, id)

func _start_mode(mode: String) -> void:
	Session.chosen_character = character_select.get_item_metadata(character_select.selected)
	Session.chosen_side = "STEEL" if side_select.selected == 0 else "SWARM"
	var error: Error
	if mode == "join":
		error = Session.join(address.text.strip_edges(), int(port.value))
	else:
		var settings := {"map_index": map_select.selected, "team_size": int(size_select.value),
			"env": {"time": ["day", "dusk", "night"][time_select.selected], "weather": ["clear", "fog"][weather_select.selected]}}
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
		players.append("%s · %s" % [Content.constants.SIDES[player.side].name, Content.heroes[player.character].code])
	room_label.text = "\n".join(players)
	start_button.visible = Session.active and Session.multiplayer.is_server() and not Session.started

func _begin_battle(settings: Dictionary, players: Array) -> void:
	if simulation != null:
		simulation.queue_free()
	simulation = BattleSimulation.new()
	add_child(simulation)
	var map_data := Content.map_variant(int(settings.map_index), int(settings.team_size))
	await simulation.setup(map_data, players, settings.env, Session.multiplayer.is_server())
	Session.simulation = simulation
	if simulation.authoritative and not Session.dedicated:
		simulation.apply_presentation_view(simulation.snapshot(multiplayer.get_unique_id()))
	simulation.message.connect(func(peer, key):
		if peer == multiplayer.get_unique_id():
			_status(key))
	simulation.result.connect(_result)
	minimap.map_data = map_data
	minimap.side = Session.chosen_side
	lobby.hide()
	hud.show()
	notice.text = ""
	if not Session.dedicated:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var pilot: BattleUnit = simulation.pilots.get(multiplayer.get_unique_id())
	if pilot != null:
		yaw = pilot.yaw
		_bind_camera(pilot)

func _bind_camera(pilot: BattleUnit) -> void:
	if bound_pilot != pilot.entity_id:
		yaw = pilot.target_yaw if not simulation.authoritative else pilot.yaw
		pitch = pilot.pitch
		bound_pilot = pilot.entity_id
	if pilot.camera != null:
		pilot.camera.current = true
		pilot.model.visible = false
		pilot.ensure_cockpit()
		var echo_callback := simulation.present_echo.bind(pilot)
		if not pilot.cockpit.echo_fired.is_connected(echo_callback):
			pilot.cockpit.echo_fired.connect(echo_callback)

func _process(delta: float) -> void:
	if simulation == null or Session.dedicated:
		return
	presentation_clock += delta
	var pilot: BattleUnit = simulation.pilots.get(multiplayer.get_unique_id())
	if pilot == null or pilot.cockpit == null:
		return
	var aiming := Input.is_action_pressed("aim") and not overlay_open
	var clock := simulation.clock if simulation.authoritative else presentation_clock
	pilot.cockpit.update_view(pilot, selected_slot, aiming, delta, clock)
	if simulation.authoritative:
		simulation.world.sync_projectile_view(simulation.projectile_view(pilot))
	simulation.world.step_projectile_visuals(delta)

func _unhandled_input(event: InputEvent) -> void:
	if simulation == null or Session.dedicated:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw = wrapf(yaw - event.relative.x * 0.0025, -PI, PI)
		pitch = clampf(pitch - event.relative.y * 0.0025, -1.4, 1.4)
	if event.is_action_pressed("pause"):
		_overlay(menu, not menu.visible)
	if event.is_action_pressed("shop"):
		_overlay(shop, not shop.visible)
	if overlay_open:
		return
	if event.is_action_pressed("slot_light"):
		selected_slot = "light"
	if event.is_action_pressed("slot_heavy"):
		selected_slot = "heavy"
	if event.is_action_pressed("reload"):
		Session.act("reload", selected_slot)
	if event.is_action_pressed("defense"):
		Session.act("cast", "def")
	if event.is_action_pressed("attack"):
		Session.act("cast", "atk")
	if event.is_action_pressed("morph"):
		Session.act("morph")
	if event.is_action_pressed("map"):
		minimap.size = Vector2(600, 520) if minimap.size.x < 300 else Vector2(250, 220)
		minimap.position.x = -minimap.size.x - 20
		minimap.queue_redraw()
	if event.is_action_pressed("rise"):
		held_jump = true

func _physics_process(delta: float) -> void:
	if simulation == null or Session.dedicated:
		return
	var sticks := Input.get_connected_joypads()
	if not sticks.is_empty() and not overlay_open:
		yaw -= Input.get_joy_axis(sticks[0], JOY_AXIS_RIGHT_X) * delta * 2
		pitch = clampf(pitch - Input.get_joy_axis(sticks[0], JOY_AXIS_RIGHT_Y) * delta * 2, -1.4, 1.4)
	var command := {"move": Input.get_vector("left", "right", "forward", "back") if not overlay_open else Vector2.ZERO,
		"yaw": yaw, "pitch": pitch, "vertical": Input.get_axis("descend", "rise") if not overlay_open else 0.0,
		"jump": held_jump and not overlay_open, "fire": Input.is_action_pressed("fire") and not overlay_open,
		"slot": selected_slot, "aim": Input.is_action_pressed("aim") and not overlay_open,
		"sprint": Input.is_action_pressed("sprint") and not overlay_open}
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
	Session.command(command)
	var local_pilot: BattleUnit = simulation.pilots.get(multiplayer.get_unique_id())
	if local_pilot != null and local_pilot.camera != null:
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
	minimap.state = state
	minimap.queue_redraw()
	simulation.world.sync_projectile_view(state.get("projectile_view", []))
	if Session.multiplayer.is_server():
		simulation.apply_presentation_view(state)
		for event in state.events:
			if event.type == "shot":
				simulation.present_shot(event)
	var pilot: BattleUnit = simulation.pilots.get(multiplayer.get_unique_id())
	if pilot == null:
		return
	simulation.apply_footprint({} if shop.visible else state.get("footprint", {}), state.get("lock", {}))
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
	pilot.cockpit.control = control
	for event: Dictionary in state.events:
		if event.type == "weapon_fire" and int(event.actor) == pilot.entity_id:
			pilot.cockpit.fire_feedback(event)
	pilot.cockpit.sync_authority_pose(state.weapon_pose)
	stats.text = "%s %.0f/%.0f  |  %s %.0f/%.0f  |  %s %.0f\n%s %.0f  |  %s %.0f  |  %s %d" % [
		Content.label("hp"), pilot.hp, pilot.max_hp, Content.label("shield"), pilot.shield, pilot.max_shield,
		Content.label("power"), pilot.power, Content.label("credits"), pilot.money,
		Content.label("score"), pilot.score, Content.label("wave"), int(state.wave)]
	var definition := Content.weapon(pilot.character, selected_slot, int(pilot.upgrades.lw if selected_slot == "light" else pilot.upgrades.hw) + 1)
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
		notice.text = "%s %.1f" % [Content.label("respawn"), maxf(0, pilot.respawn_at - state.clock)]
	elif not state.over and notice.text.begins_with(Content.label("respawn")):
		notice.text = ""
	for item in shop_buttons:
		var level: int = int(pilot.upgrades[item])
		var def: Dictionary = Content.constants.ECON.UPGRADES[item]
		var button: Button = shop_buttons[item]
		if level >= int(def.max):
			button.text = "%s · %s" % [def.name, Content.label("max")]
			button.disabled = true
		else:
			var step: Dictionary = Content.constants.ECON.UPG_STEPS[level]
			button.text = "%s Lv%d · $%d · %s %d" % [def.name, level, int(step.price), Content.label("score"), int(step.score)]
			button.disabled = pilot.money < step.price or pilot.score < step.score or pilot.position.distance_to(simulation.world.bases[pilot.side]) > Content.constants.GAME.HERO_HEAL_RADIUS

func _overlay(panel: Control, show_panel: bool) -> void:
	menu.hide()
	shop.hide()
	panel.visible = show_panel
	if panel == shop and show_panel and simulation != null:
		simulation.apply_footprint({})
	overlay_open = show_panel
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if overlay_open else Input.MOUSE_MODE_CAPTURED

func _result(winner: String) -> void:
	notice.text = Content.label("victory" if winner == Session.chosen_side else "defeat")
	_overlay(menu, true)

func _status(key: String) -> void:
	notice.text = Content.label(key)
	if key in ["disconnected", "failed"] and simulation != null:
		_leave()

func _leave() -> void:
	Session.stop()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().reload_current_scene()
