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
var portrait_rules: Dictionary
var radio_layout_rules: Dictionary
var radio_note_rules: Dictionary
var radio_text_rules: Dictionary
var radio_row: HBoxContainer
var radio_note_title: Label
var radio_layout_pending := false
var radio_layout_mode := ""
var clock_msec := Callable()

func _current(token: int) -> bool:
	if token != generation or not is_inside_tree():
		return false
	var owner: Node = self
	while owner != null:
		if owner.is_queued_for_deletion():
			return false
		owner = owner.get_parent()
	return true

func _now_msec() -> float:
	return float(clock_msec.call()) if clock_msec.is_valid() else float(Time.get_ticks_usec()) / 1000.0

func _ready() -> void:
	motion_rules = Content.read_json("res://data/dialogue_motion.json").rules
	portrait_rules = Content.read_json("res://data/dialogue_portrait.json").rules
	radio_layout_rules = Content.read_json("res://data/dialogue_radio_layout.json").rules
	radio_note_rules = Content.read_json("res://data/dialogue_radio_note.json").rules
	radio_text_rules = Content.read_json("res://data/dialogue_radio_text.json").rules
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
	if not _current(generation):
		return
	if is_instance_valid(radio_group):
		radio_group.layout_radio(size)
	_schedule_radio_layout()

func _schedule_radio_layout() -> void:
	if not radio_layout_pending and _current(generation) and is_instance_valid(bar):
		radio_layout_pending = true
		_apply_radio_layout.call_deferred()

func _apply_radio_layout() -> void:
	radio_layout_pending = false
	if not _current(generation) or not is_instance_valid(bar) or not is_instance_valid(radio_row):
		return
	var token := generation
	var viewport_width := get_viewport_rect().size.x
	var mode := "mobile" if viewport_width <= float(radio_layout_rules.mobileMaxWidth) else "desktop"
	var rule: Dictionary = radio_layout_rules[mode]
	if radio_layout_mode != mode:
		radio_layout_mode = mode
		var style := bar.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			style.set_border_width(side, int(rule.border[side]))
			style.set_content_margin(side, float(rule.padding[side]) + float(rule.border[side]))
		bar.add_theme_stylebox_override("panel", style)
		if not _current(token):
			return
		radio_row.add_theme_constant_override("separation", int(rule.rowGap))
		if not _current(token):
			return
		if is_instance_valid(line_label):
			var font_size: int = int(radio_text_rules.mobileLineFont) if mode == "mobile" else int(radio_text_rules.desktopLineFont)
			line_label.add_theme_font_size_override("normal_font_size", font_size)
			if not _current(token):
				return
		for portrait in portraits:
			if is_instance_valid(portrait):
				portrait.custom_minimum_size = Vector2(float(rule.avatar), float(rule.avatar))
			if not _current(token):
				return
	var units := float(radio_layout_rules.layoutUnits)
	var width := floorf(minf(float(radio_layout_rules.maxWidth), viewport_width * float(radio_layout_rules.viewportRatio)) * units) / units
	bar.size = Vector2(width, 0)
	if not _current(token):
		return
	bar.position = Vector2((size.x - bar.size.x) / 2, size.y - float(rule.bottom) - bar.size.y)

func track(stage: int = -1) -> void:
	if not _current(generation):
		return
	var token := generation
	track_label.visible = stage >= 0
	if stage < 0 or not _current(token):
		return
	var names: Array = Content.constants.SIEGE.NAMES
	var parts := PackedStringArray()
	for index in range(names.size()):
		var mark := Content.label("story_stage_done" if index < stage else "story_stage_now" if index == stage else "story_stage_locked")
		parts.append(mark % names[index])
	track_label.text = Content.label("story_stage_separator").join(parts)

func clear() -> void:
	generation += 1
	var old_timers := timers.duplicate()
	timers.clear()
	var old_group := radio_group
	radio_group = null
	bar = null
	radio_row = null
	radio_note_title = null
	radio_layout_mode = ""
	speaker = null
	line_label = null
	var old_portraits := portraits.duplicate()
	portraits.clear()
	portrait_ids.clear()
	lines.clear()
	at = 0
	total = 0
	var old_fade := fade
	var old_entrance := entrance
	fade = null
	entrance = null
	for portrait: Variant in old_portraits:
		if is_instance_valid(portrait):
			portrait.cancel()
			if portrait.get_parent() == null:
				portrait.free()
	for timer: Timer in old_timers:
		timer.stop()
		timer.queue_free()
	if old_fade != null and old_fade.is_valid():
		old_fade.kill()
	if old_entrance != null and old_entrance.is_valid():
		old_entrance.kill()
	if is_instance_valid(old_group):
		old_group.retire()
		if is_instance_valid(old_group):
			old_group.queue_free()

func dispose() -> void:
	var token := generation + 1
	clear()
	if token == generation and is_instance_valid(track_label):
		track_label.hide()

func _exit_tree() -> void:
	dispose()

func _after(seconds: float, callback: Callable) -> void:
	_after_msec(seconds * 1000, callback)

func _after_msec(delay: float, callback: Callable) -> void:
	var token := generation
	if not _current(token):
		return
	var deadline := _now_msec() + delay
	if not _current(token):
		return
	var timer := Timer.new()
	timer.one_shot = true
	timer.ignore_time_scale = true
	timer.process_mode = Node.PROCESS_MODE_ALWAYS
	timer.wait_time = maxf(0.001, delay / 1000)
	timers.append(timer)
	timer.timeout.connect(func():
		if not _current(token) or not timers.has(timer):
			return
		var remaining := deadline - _now_msec()
		if not _current(token) or not timers.has(timer):
			return
		if remaining > 0:
			timer.start(remaining / 1000)
			return
		timers.erase(timer)
		timer.queue_free()
		callback.call())
	add_child(timer)
	if _current(token) and timers.has(timer):
		timer.start()

func radio(scene: Dictionary) -> void:
	if not _current(generation) or scene.get("lines", []).is_empty():
		return
	var token := generation + 1
	clear()
	if not _current(token):
		return
	lines = scene.lines.duplicate(true)
	total = lines.size()
	radio_group = preload("res://scripts/dialogue_radio_layer.gd").new()
	radio_group.name = "RadioPresentation"
	add_child(radio_group)
	if not _current(token):
		return
	_layout_radio()
	if not _current(token):
		return
	bar = NativeUi.panel(Vector2.ZERO)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	radio_group.content.add_child(bar)
	if not _current(token):
		return
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	bar.minimum_size_changed.connect(_schedule_radio_layout)
	bar.resized.connect(_schedule_radio_layout)
	if not _current(token):
		return
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", int(radio_layout_rules.desktop.gap))
	bar.add_child(column)
	if not _current(token):
		return
	var note := HBoxContainer.new()
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note.add_theme_constant_override("separation", int(radio_note_rules.gap))
	column.add_child(note)
	if not _current(token):
		return
	radio_note_title = NativeUi.label(scene.title, int(radio_note_rules.fontSize))
	radio_note_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_child(radio_note_title)
	if not _current(token):
		return
	var description := NativeUi.label(scene.note, int(radio_note_rules.fontSize))
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.clip_text = true
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var note_color: Array = radio_note_rules.noteColor
	description.add_theme_color_override("font_color", Color(note_color[0], note_color[1], note_color[2], note_color[3]))
	note.add_child(description)
	if not _current(token):
		return
	var row := HBoxContainer.new()
	radio_row = row
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(row)
	if not _current(token):
		return
	var leaders := CampaignRules.leaders(lines, side)
	for index in range(2):
		var portrait := preload("res://scripts/dialogue_radio_portrait.gd").new()
		portrait.rules = portrait_rules
		portrait.custom_minimum_size = Vector2(float(radio_layout_rules.desktop.avatar), float(radio_layout_rules.desktop.avatar))
		portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portraits.append(portrait)
		var id: String = leaders[index] if index < leaders.size() else ""
		portrait_ids.append(id)
		portrait.texture = Content.campaign_art(id, "avatar", art_mode)
		portrait.visible = not id.is_empty()
	row.add_child(portraits[0])
	if not _current(token):
		return
	var text_column := VBoxContainer.new()
	text_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_column.add_theme_constant_override("separation", int(radio_text_rules.gap))
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(text_column)
	if not _current(token):
		return
	speaker = NativeUi.label("", int(radio_text_rules.speakerFont))
	text_column.add_child(speaker)
	if not _current(token):
		return
	line_label = NativeUi.prose("", int(radio_text_rules.desktopLineFont))
	line_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line_color: Array = radio_text_rules.lineColor
	line_label.add_theme_color_override("default_color", Color(line_color[0], line_color[1], line_color[2], line_color[3]))
	text_column.add_child(line_label)
	if not _current(token):
		return
	row.add_child(portraits[1])
	if not _current(token):
		return
	var endpoint := portraits[1]
	var empty_column := Control.new()
	empty_column.name = "AbsentPortraitColumn"
	empty_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	empty_column.visible = not endpoint.visible
	row.add_child(empty_column)
	if not _current(token):
		return
	endpoint.visibility_changed.connect(func():
		if _current(token) and is_instance_valid(endpoint) and is_instance_valid(empty_column):
			empty_column.visible = not endpoint.visible)
	_schedule_radio_layout()
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
	var token := generation
	if not _current(token) or not is_instance_valid(bar):
		return
	if at >= lines.size():
		var seconds: float = Content.campaign.presentation.radioFade
		if entrance != null and entrance.is_valid():
			entrance.kill()
		fade = _animate_radio("exit")
		_after(seconds, func():
			var old_group := radio_group
			radio_group = null
			bar = null
			if is_instance_valid(old_group):
				old_group.retire()
				if is_instance_valid(old_group):
					old_group.queue_free())
		return
	var line: Dictionary = lines[at]
	at += 1
	var hero: Dictionary = Content.heroes[line.ch]
	var foe := "SWARM" if side == "STEEL" else "STEEL"
	var index := 1 if hero.side == foe else 0
	if portrait_ids[index] != line.ch:
		portraits[index].texture = Content.campaign_art(line.ch, "avatar", art_mode)
		if not _current(token):
			return
		portrait_ids[index] = line.ch
	for position in range(portraits.size()):
		portraits[position].call("set_speaking", position == index, at == 1)
	speaker.text = Content.label("story_speaker") % [hero.code, hero.name]
	if not _current(token):
		return
	var color := Color(Content.label("story_merc_color") if hero.side == "MERC" else Content.side_info(hero.side).color)
	speaker.add_theme_color_override("font_color", color)
	if not _current(token):
		return
	radio_note_title.add_theme_color_override("font_color", color)
	if not _current(token):
		return
	var bar_style := bar.get_theme_stylebox("panel") as StyleBoxFlat
	bar_style.border_color = color
	if not _current(token):
		return
	line_label.text = line.t
	if not _current(token):
		return
	_after(CampaignRules.line_seconds(line.t), _step)

func transcript(host: VBoxContainer, scene: Dictionary) -> void:
	if not _current(generation) or not is_instance_valid(host) or not host.is_inside_tree() or host.is_queued_for_deletion() or scene.get("lines", []).is_empty():
		return
	var token := generation
	host.add_child(NativeUi.label(scene.title, 24))
	if not _current(token) or not host.is_inside_tree() or host.is_queued_for_deletion():
		return
	host.add_child(NativeUi.prose(scene.note, 16))
	if not _current(token) or not host.is_inside_tree() or host.is_queued_for_deletion():
		return
	var body = preload("res://scripts/dialogue_transcript_body.gd").new()
	host.add_child(body)
	if not _current(token) or not host.is_inside_tree() or host.is_queued_for_deletion():
		return
	var leaders := CampaignRules.leaders(scene.lines, side, true)
	for index in range(leaders.size()):
		body.add_portrait(Content.campaign_art(leaders[index], "portrait", art_mode), index > 0)
	var delay := float(Content.campaign.presentation.transcript.delay) * 1000
	var interval := float(Content.campaign.presentation.transcript.step) * 1000
	for index in range(scene.lines.size()):
		var line: Dictionary = scene.lines[index]
		var hero: Dictionary = Content.heroes[line.ch]
		var row = preload("res://scripts/dialogue_transcript_row.gd").new()
		body.rows.add_child(row)
		if not _current(token) or not host.is_inside_tree() or host.is_queued_for_deletion():
			return
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
		if not _current(token) or not host.is_inside_tree() or host.is_queued_for_deletion():
			# The second child has not been admitted yet.
			(portrait if hero.side == foe else column).free()
			return
		row.content.add_child(portrait if hero.side == foe else column)
		if not _current(token) or not host.is_inside_tree() or host.is_queued_for_deletion():
			return
		_after_msec(delay + index * interval, func():
			if is_instance_valid(host) and host.is_inside_tree() and not host.is_queued_for_deletion() and is_instance_valid(row) and row.is_inside_tree() and not row.is_queued_for_deletion():
				row.reveal())
		if not _current(token):
			return
