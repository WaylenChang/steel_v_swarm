class_name CampaignDialogue
extends Control

var side := "STEEL"
var art_mode := "char"
var bar: PanelContainer
var track_label: Label
var speaker: Label
var line_label: RichTextLabel
var portraits: Array[TextureRect] = []
var portrait_ids: Array[String] = []
var lines: Array = []
var at := 0
var total := 0
var timers: Array[Timer] = []
var generation := 0
var fade: Tween
var entrance: Tween
var radio_group: Sprite2D
var motion_rules: Dictionary
var clock_msec := Callable()

func _now_msec() -> float:
	return float(clock_msec.call()) if clock_msec.is_valid() else float(Time.get_ticks_usec()) / 1000.0

func _ready() -> void:
	motion_rules = Content.read_json("res://data/dialogue_motion.json").rules
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	track_label = NativeUi.label("", 16)
	track_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	track_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	track_label.position = Vector2(-260, 110)
	track_label.size = Vector2(520, 30)
	add_child(track_label)
	track_label.hide()
	resized.connect(_layout_radio)

func _layout_radio() -> void:
	if is_instance_valid(radio_group):
		radio_group.layout_radio(size)

func track(stage: int = -1) -> void:
	track_label.visible = stage >= 0
	if stage < 0:
		return
	var names: Array = Content.constants.SIEGE.NAMES
	var parts := PackedStringArray()
	for index in range(names.size()):
		var mark := Content.label("story_stage_done" if index < stage else "story_stage_now" if index == stage else "story_stage_locked")
		parts.append(mark % names[index])
	track_label.text = Content.label("story_stage_separator").join(parts)

func clear() -> void:
	generation += 1
	for timer: Timer in timers:
		timer.stop()
		timer.queue_free()
	timers.clear()
	if fade != null and fade.is_valid():
		fade.kill()
	if entrance != null and entrance.is_valid():
		entrance.kill()
	if is_instance_valid(radio_group):
		radio_group.retire()
		radio_group.queue_free()
	radio_group = null
	bar = null
	portraits.clear()
	portrait_ids.clear()
	lines.clear()
	at = 0
	total = 0

func dispose() -> void:
	clear()
	track(-1)

func _after(seconds: float, callback: Callable) -> void:
	_after_msec(seconds * 1000, callback)

func _after_msec(delay: float, callback: Callable) -> void:
	var token := generation
	var deadline := _now_msec() + delay
	var timer := Timer.new()
	timer.one_shot = true
	timer.ignore_time_scale = true
	timer.process_mode = Node.PROCESS_MODE_ALWAYS
	timer.wait_time = maxf(0.001, delay / 1000)
	add_child(timer)
	timers.append(timer)
	timer.timeout.connect(func():
		if token != generation or not timers.has(timer):
			return
		var remaining := deadline - _now_msec()
		if remaining > 0:
			timer.start(remaining / 1000)
			return
		timers.erase(timer)
		timer.queue_free()
		callback.call())
	timer.start()

func radio(scene: Dictionary) -> void:
	if scene.get("lines", []).is_empty():
		return
	clear()
	lines = scene.lines.duplicate(true)
	total = lines.size()
	radio_group = preload("res://scripts/dialogue_radio_layer.gd").new()
	radio_group.name = "RadioPresentation"
	add_child(radio_group)
	_layout_radio()
	bar = NativeUi.panel(Vector2(860, 152))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	radio_group.content.add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bar.position = Vector2(-430, -260)
	bar.size = Vector2(860, 152)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(column)
	column.add_child(NativeUi.label(scene.title + " · " + scene.note, 15))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(row)
	var leaders := CampaignRules.leaders(lines, side)
	for index in range(2):
		var portrait := TextureRect.new()
		portrait.custom_minimum_size = Vector2(64, 64)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portraits.append(portrait)
		var id: String = leaders[index] if index < leaders.size() else ""
		portrait_ids.append(id)
		portrait.texture = Content.campaign_art(id, "avatar", art_mode)
		portrait.visible = not id.is_empty()
	row.add_child(portraits[0])
	var text_column := VBoxContainer.new()
	text_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_column)
	speaker = NativeUi.label("", 18)
	text_column.add_child(speaker)
	line_label = NativeUi.prose("", 18)
	line_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_column.add_child(line_label)
	row.add_child(portraits[1])
	entrance = _animate_radio("enter")
	_step()

func _animate_radio(phase: String) -> Tween:
	var rule: Dictionary = motion_rules[phase]
	radio_group.opacity = rule.from
	radio_group.position.y = rule.fromY
	var animation := create_tween().set_ignore_time_scale(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	var curve: Array = rule.curve
	var ease := func(value: float): return HurtFlashState.bezier_values(value, curve[0], curve[1], curve[2], curve[3])
	animation.tween_property(radio_group, "opacity", float(rule.to), float(rule.duration)).set_custom_interpolator(ease)
	animation.tween_property(radio_group, "position:y", float(rule.toY), float(rule.duration)).set_custom_interpolator(ease)
	return animation

func _step() -> void:
	if not is_instance_valid(bar):
		return
	if at >= lines.size():
		var seconds: float = Content.campaign.presentation.radioFade
		if entrance != null and entrance.is_valid():
			entrance.kill()
		fade = _animate_radio("exit")
		_after(seconds, func():
			if is_instance_valid(radio_group):
				radio_group.retire()
				radio_group.queue_free()
			radio_group = null
			bar = null)
		return
	var line: Dictionary = lines[at]
	at += 1
	var hero: Dictionary = Content.heroes[line.ch]
	var foe := "SWARM" if side == "STEEL" else "STEEL"
	var index := 1 if hero.side == foe else 0
	if portrait_ids[index] != line.ch:
		portraits[index].texture = Content.campaign_art(line.ch, "avatar", art_mode)
		portrait_ids[index] = line.ch
	for position in range(portraits.size()):
		portraits[position].modulate.a = 1.0 if position == index else 0.5
	speaker.text = Content.label("story_speaker") % [hero.code, hero.name]
	speaker.add_theme_color_override("font_color", Color(Content.label("story_merc_color") if hero.side == "MERC" else Content.side_info(hero.side).color))
	line_label.text = line.t
	_after(CampaignRules.line_seconds(line.t), _step)

func transcript(host: VBoxContainer, scene: Dictionary) -> void:
	if scene.get("lines", []).is_empty():
		return
	host.add_child(NativeUi.label(scene.title, 24))
	host.add_child(NativeUi.prose(scene.note, 16))
	var lead_row := HBoxContainer.new()
	host.add_child(lead_row)
	for id: String in CampaignRules.leaders(scene.lines, side, true):
		var art := TextureRect.new()
		art.texture = Content.campaign_art(id, "portrait", art_mode)
		art.custom_minimum_size = Vector2(200, 180)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lead_row.add_child(art)
	var delay := float(Content.campaign.presentation.transcript.delay) * 1000
	var interval := float(Content.campaign.presentation.transcript.step) * 1000
	for index in range(scene.lines.size()):
		var line: Dictionary = scene.lines[index]
		var hero: Dictionary = Content.heroes[line.ch]
		var row = preload("res://scripts/dialogue_transcript_row.gd").new()
		host.add_child(row)
		var portrait := TextureRect.new()
		portrait.texture = Content.campaign_art(line.ch, "avatar", art_mode)
		portrait.custom_minimum_size = Vector2(52, 52)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_child(NativeUi.label(Content.label("story_speaker") % [hero.code, hero.name], 16))
		column.add_child(NativeUi.prose(line.t))
		var foe := "SWARM" if side == "STEEL" else "STEEL"
		row.content.add_child(column if hero.side == foe else portrait)
		row.content.add_child(portrait if hero.side == foe else column)
		_after_msec(delay + index * interval, func():
			if is_instance_valid(row):
				row.reveal())
