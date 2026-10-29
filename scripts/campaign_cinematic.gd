class_name CampaignCinematic
extends Control

const Buffer = preload("res://scripts/campaign_buffer.gd")
const CrawlSection = preload("res://scripts/campaign_crawl_section.gd")

signal finished
signal finishing

var scenes: Array = []
var active := -1
var playing := false
var closing := false
var scroll: ScrollContainer
var crawl_margin: MarginContainer
var column: VBoxContainer
var sections: Array[Control] = []
var art_host: Control
var art_layers: Array[Control] = []
var shade: ColorRect
var card: Control
var card_panel: PanelContainer
var header_panel: PanelContainer
var header_style: StyleBoxFlat
var badge_label: Label
var heading: Label
var system_bar: Control
var system_bar_content: HBoxContainer
var archive_label: Label
var tag: Label
var end_divider: Label
var end_note: Label
var finish_button: Button
var caption: Label
var hold_indicator: Control
var presentation_group: CanvasGroup
var transition_rules: Dictionary
var card_rules: Dictionary
var header_rules: Dictionary
var ending_rules: Dictionary
var section_marker_rules: Dictionary
var marker_geometry_rules: Dictionary
var section_geometry_rules: Dictionary
var paragraph_rules: Dictionary
var section_opacity_rules: Dictionary
var crawl_inset_rules: Dictionary
var crawl_top := 0.0
var fade_opacity := 1.0:
	set(value):
		fade_opacity = value
		if presentation_group != null:
			presentation_group.self_modulate.a = value
var scroll_offset := 0.0
var last_frame_at := 0.0
var paused_until := 0.0
var held_at := -1.0
var last_tap := 0.0
var finish_touches: Dictionary = {}
var writing_scroll := false
var exit_tween: Tween
var exit_timer: Timer
var exit_deadline := 0.0
var generation := 0
var clock_msec := Callable()
var buffer_loader: Buffer
var buffer_status: Label
var buffer_rules: Dictionary
var buffer_warning := false
var buffer_warning_timers: Array[Timer] = []
var hud_layout_queued := false

func _now_msec() -> float:
	return float(clock_msec.call()) if clock_msec.is_valid() else float(Time.get_ticks_usec()) / 1000.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	transition_rules = Content.read_json("res://data/campaign_transition.json").rules
	card_rules = Content.read_json("res://data/campaign_card.json").rules
	header_rules = Content.read_json("res://data/campaign_header.json").rules
	ending_rules = Content.read_json("res://data/campaign_ending.json").rules
	section_marker_rules = Content.read_json("res://data/campaign_section_marker.json").rules
	marker_geometry_rules = Content.read_json("res://data/campaign_marker_geometry.json").rules
	section_geometry_rules = Content.read_json("res://data/campaign_section_geometry.json").rules
	paragraph_rules = Content.read_json("res://data/campaign_paragraph.json").rules
	section_opacity_rules = Content.read_json("res://data/campaign_section_opacity.json").rules
	crawl_inset_rules = Content.read_json("res://data/campaign_crawl_insets.json").rules
	buffer_rules = Content.read_json("res://data/campaign_buffer.json").rules
	presentation_group = CanvasGroup.new()
	presentation_group.name = "Presentation"
	add_child(presentation_group)
	shade = ColorRect.new()
	shade.color = Color("#05070a")
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	presentation_group.add_child(shade)
	art_host = Control.new()
	art_host.clip_contents = true
	art_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	presentation_group.add_child(art_host)
	card = Control.new()
	card.clip_contents = true
	presentation_group.add_child(card)
	card_panel = NativeUi.panel(Vector2.ZERO)
	card_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	var panel_style := card_panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	panel_style.content_margin_left = card_rules.border
	panel_style.content_margin_right = card_rules.border
	panel_style.content_margin_top = card_rules.border
	panel_style.content_margin_bottom = card_rules.border
	card_panel.add_theme_stylebox_override("panel", panel_style)
	card.add_child(card_panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	card_panel.add_child(body)
	system_bar = Control.new()
	system_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	presentation_group.add_child(system_bar)
	system_bar_content = HBoxContainer.new()
	system_bar_content.add_theme_constant_override("separation", 0)
	system_bar_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	system_bar.add_child(system_bar_content)
	archive_label = NativeUi.label(card_rules.systemBar.archive, 10)
	archive_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	archive_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	system_bar_content.add_child(archive_label)
	tag = NativeUi.label("", 12)
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	system_bar_content.add_child(tag)
	archive_label.resized.connect(_queue_hud_layout)
	tag.resized.connect(_queue_hud_layout)
	header_panel = PanelContainer.new()
	header_style = StyleBoxFlat.new()
	var background: Array = header_rules.background
	var border: Array = header_rules.border
	header_style.bg_color = Color(background[0], background[1], background[2], background[3])
	header_style.border_color = Color(border[0], border[1], border[2], border[3])
	header_style.border_width_bottom = int(header_rules.borderWidth)
	header_panel.add_theme_stylebox_override("panel", header_style)
	body.add_child(header_panel)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 0)
	header_panel.add_child(header)
	badge_label = NativeUi.label("", 14)
	header.add_child(badge_label)
	heading = NativeUi.label("", 23)
	heading.clip_text = true
	heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(heading)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.get_v_scroll_bar().step = 1
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	crawl_margin = MarginContainer.new()
	crawl_margin.mouse_filter = Control.MOUSE_FILTER_PASS
	crawl_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(crawl_margin)
	column = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", int(section_geometry_rules.marginBottom))
	crawl_margin.add_child(column)
	caption = NativeUi.label(Content.label("story_skip_hint"), 14)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	buffer_status = NativeUi.label("", 14)
	buffer_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	buffer_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buffer_status.hide()
	presentation_group.add_child(buffer_status)
	presentation_group.add_child(caption)
	caption.resized.connect(_queue_hud_layout)
	buffer_status.resized.connect(_queue_hud_layout)
	scroll.get_v_scroll_bar().value_changed.connect(func(value):
		if not writing_scroll:
			scroll_offset = value
		_update_scene())
	scroll.gui_input.connect(_scroll_input)
	hold_indicator = preload("res://scripts/campaign_hold.gd").new()
	presentation_group.add_child(hold_indicator)
	resized.connect(_layout)
	hide()
	set_process(false)
	set_process_input(false)

func _make_art_layer() -> Control:
	return preload("res://scripts/campaign_art_layer.gd").new()

func _make_buffer() -> Buffer:
	return Buffer.new()

func play(sequence: Array, finish_text: String, start_index: int = 0) -> void:
	if sequence.is_empty():
		if playing or closing:
			dispose()
		finished.emit()
		return
	dispose()
	_write_scroll()
	var token := generation
	var is_prologue := is_same(sequence, Content.campaign.get("prologue", []))
	scenes = sequence.duplicate(true)
	start_index = clampi(start_index, 0, scenes.size() - 1)
	for scene: Dictionary in scenes:
		var layer := _make_art_layer()
		layer.name = "prologueSceneItem-%d" % art_layers.size()
		art_host.add_child(layer)
		layer.scene = scene
		art_layers.append(layer)
		var section := CrawlSection.new()
		section.scene = scene
		section.marker_rules = section_marker_rules
		section.marker_geometry_rules = marker_geometry_rules
		section.geometry_rules = section_geometry_rules
		section.opacity_rules = section_opacity_rules
		section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_child(section)
		sections.append(section)
	var ending: Dictionary = ending_rules.prologue if is_prologue else ending_rules.chapter
	var ending_box := VBoxContainer.new()
	column.add_child(ending_box)
	end_divider = NativeUi.label(ending_rules.divider, 14)
	end_divider.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ending_box.add_child(end_divider)
	end_note = NativeUi.label(ending.note, 11)
	end_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	end_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ending_box.add_child(end_note)
	var button_text := String(ending.button) if is_prologue or finish_text.is_empty() else finish_text
	finish_button = NativeUi.button(button_text, finish)
	finish_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ending_box.add_child(finish_button)
	closing = false
	modulate.a = 1.0
	fade_opacity = 1.0
	show()
	set_process(true)
	set_process_input(true)
	_layout()
	playing = true
	_set_scene(start_index)
	if is_prologue:
		var loader := _make_buffer()
		buffer_loader = loader
		loader.progress.connect(_buffer_progress.bind(token))
		add_child(loader)
		if token != generation or not playing or closing or is_queued_for_deletion() or buffer_loader != loader:
			return
		buffer_status.show()
		if not is_instance_valid(self) or is_queued_for_deletion() or not is_inside_tree() or token != generation or not playing or closing:
			return
		_render_buffer()
		loader.begin(buffer_rules)
		if token != generation or not playing or closing or is_queued_for_deletion():
			return
	else:
		_render_buffer()
		buffer_status.show()
		if not is_instance_valid(self) or is_queued_for_deletion() or not is_inside_tree() or token != generation or not playing or closing:
			return
	last_frame_at = _now_msec()
	await get_tree().process_frame
	if token != generation or not playing or closing:
		return
	if start_index > 0:
		var section: Control = sections[start_index]
		scroll_offset = maxf(0, section.position.y + crawl_top + section.size.y * float(Content.campaign.presentation.crawl.start) - scroll.size.y * float(Content.campaign.presentation.crawl.focus))
		_write_scroll()
		_update_scene()
		_set_scene(start_index)

func _layout() -> void:
	if not is_instance_valid(card):
		return
	var landscape := size.x > size.y
	shade.size = size
	art_host.size = size
	for layer: Control in art_layers:
		layer.layout_art(size)
	var insets: Dictionary = crawl_inset_rules.landscape if landscape else crawl_inset_rules.portrait
	crawl_top = float(insets.top)
	for side in ["top", "right", "bottom", "left"]:
		crawl_margin.add_theme_constant_override("margin_" + side, int(insets[side]))
	var header_padding: Dictionary = header_rules.landscape if landscape else header_rules.portrait
	for side in ["top", "right", "bottom", "left"]:
		header_style.set("content_margin_" + side, float(header_padding[side]) + (float(header_rules.borderWidth) if side == "bottom" else 0.0))
	var paragraph_gap := int(paragraph_rules.landscapeGap) if landscape else int(paragraph_rules.portraitGap)
	for section: Control in sections:
		if section is CrawlSection:
			section.set_paragraph_gap(paragraph_gap)
	var rule: Dictionary = card_rules.landscape if landscape else card_rules.portrait
	var units := float(card_rules.layoutUnits)
	var width := minf(float(rule.maxWidth), size.x * float(rule.widthRatio) if landscape else size.x - float(rule.widthMargin))
	var height := minf(float(rule.maxHeight), size.y * float(rule.heightRatio))
	var minimum := float(card_rules.border) * 2
	width = maxf(minimum, floor(width * units) / units)
	height = maxf(minimum, floor(height * units) / units)
	var safe := NativeUi.safe_area(self)
	var safe_bottom := maxf(0, size.y - safe.end.y)
	card.size = Vector2(width, height)
	card.position = Vector2((size.x - width) / 2, size.y - height - float(rule.bottom) - safe_bottom)
	card_panel.size = card.size
	_layout_hud(safe, landscape)
	_update_scene()

func _layout_hud(safe: Rect2, landscape: bool) -> void:
	var rule: Dictionary = card_rules.chrome.landscape if landscape else card_rules.chrome.portrait
	var bar_rule: Dictionary = card_rules.systemBar
	var bottom := float(rule.bottom) + maxf(0, size.y - safe.end.y)
	var bottom_side := float(rule.bottomHorizontal)
	for label: Label in [archive_label, tag]:
		var font := label.get_theme_font("font")
		var text_width := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
		label.size_flags_stretch_ratio = maxf(1, text_width)
	system_bar.position = Vector2(float(bar_rule.left), float(bar_rule.top))
	system_bar_content.position = Vector2(float(bar_rule.paddingLeft), float(bar_rule.paddingTop))
	system_bar_content.size.x = maxf(0, size.x - float(bar_rule.paddingLeft) - float(bar_rule.paddingRight))
	system_bar_content.size.y = maxf(archive_label.get_combined_minimum_size().y, tag.get_combined_minimum_size().y)
	system_bar.size = Vector2(size.x - float(bar_rule.left) - float(bar_rule.right), system_bar_content.size.y
		+ float(bar_rule.paddingTop) + float(bar_rule.paddingBottom) + float(bar_rule.borderBottom))
	var available := maxf(0, size.x - bottom_side * 2)
	caption.size.x = available / 2 if landscape else available
	buffer_status.size.x = available / 2 if landscape else available
	var caption_height := caption.get_combined_minimum_size().y
	var status_height := buffer_status.get_combined_minimum_size().y
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if landscape else HORIZONTAL_ALIGNMENT_LEFT
	caption.size = Vector2(available / 2 if landscape else available, caption_height)
	caption.position = Vector2(size.x - bottom_side - caption.size.x if landscape else bottom_side, size.y - bottom - caption_height)
	buffer_status.size = Vector2(available / 2 if landscape else available, status_height)
	buffer_status.position = Vector2(bottom_side, size.y - bottom - status_height if landscape else caption.position.y - float(rule.gap) - status_height)

func _queue_hud_layout() -> void:
	if not hud_layout_queued:
		hud_layout_queued = true
		call_deferred("_refresh_hud")

func _refresh_hud() -> void:
	hud_layout_queued = false
	if is_inside_tree() and is_instance_valid(caption) and is_instance_valid(buffer_status):
		_layout_hud(NativeUi.safe_area(self), size.x > size.y)

func _process(_delta: float) -> void:
	if not playing or closing:
		return
	var now := _now_msec()
	var rules: Dictionary = Content.campaign.presentation.crawl
	var delta := minf((now - last_frame_at) / 1000, float(rules.maximumFrame))
	last_frame_at = now
	if held_at >= 0:
		hold_indicator.advance((now - held_at) / (float(Content.campaign.presentation.skip.hold) * 1000))
	if held_at >= 0 and now - held_at >= float(Content.campaign.presentation.skip.hold) * 1000:
		held_at = -1
		hold_indicator.cancel()
		var token := generation
		_try_skip()
		if token != generation or not playing or closing:
			return
	if now > paused_until:
		var maximum := maxf(0, scroll.get_v_scroll_bar().max_value - scroll.get_v_scroll_bar().page)
		if scroll.get_v_scroll_bar().value < maximum:
			scroll_offset = scroll.get_v_scroll_bar().value + float(rules.speed) * delta
			_write_scroll()
			_update_scene()

func _write_scroll() -> void:
	writing_scroll = true
	scroll.get_v_scroll_bar().value = scroll_offset
	scroll_offset = scroll.get_v_scroll_bar().value
	writing_scroll = false

func _scroll_input(event: InputEvent) -> void:
	if (event is InputEventScreenTouch and event.pressed and not event.canceled) or event is InputEventScreenDrag \
			or (event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]):
		paused_until = _now_msec() + float(Content.campaign.presentation.crawl.pause) * 1000

func _finish_target(point: Vector2) -> bool:
	return is_instance_valid(finish_button) and finish_button.is_visible_in_tree() \
		and scroll.get_global_rect().has_point(point) and finish_button.get_global_rect().has_point(point)

func _input(event: InputEvent) -> void:
	if not playing or closing:
		return
	var now := _now_msec()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _finish_target(event.position):
				return
			held_at = now
			hold_indicator.begin(event.position, get_viewport_rect().size)
			if event.double_click:
				_try_skip()
		else:
			held_at = -1
			hold_indicator.cancel()
	elif event is InputEventScreenTouch:
		if event.canceled:
			held_at = -1
			hold_indicator.cancel()
			finish_touches.erase(event.index)
			return
		if event.pressed:
			var button_target := _finish_target(event.position)
			finish_touches[event.index] = button_target
			if not button_target:
				held_at = now
				hold_indicator.begin(event.position, get_viewport_rect().size)
		else:
			held_at = -1
			hold_indicator.cancel()
			if not finish_touches.has(event.index):
				return
			var button_target: bool = finish_touches[event.index]
			finish_touches.erase(event.index)
			if button_target:
				return
			var token := generation
			if now - last_tap < float(Content.campaign.presentation.skip.doubleTap) * 1000:
				_try_skip()
			if token == generation:
				last_tap = now

func _update_scene() -> void:
	if not playing or scenes.is_empty() or sections.is_empty():
		return
	var positions: Array = []
	for section: Control in sections:
		positions.append({"top": section.position.y + crawl_top, "height": section.size.y})
	var focus := CampaignRules.focus_section(scroll.scroll_vertical, scroll.size.y, positions, active)
	_set_scene(int(focus.index))
	var pose := CampaignRules.camera_pose(scenes[active].camera, focus.progress, size.x >= size.y)
	if pose.is_empty():
		return
	art_layers[active].set_pose(pose)

func _set_scene(index: int) -> void:
	if index == active or index < 0 or index >= scenes.size():
		return
	var initial := active < 0
	active = index
	var scene: Dictionary = scenes[index]
	for layer_index in range(art_layers.size()):
		art_layers[layer_index].select(layer_index == index)
	for section_index in range(sections.size()):
		if sections[section_index] is CrawlSection:
			sections[section_index].select(section_index == index, initial)
	badge_label.text = scene.badge
	heading.text = scene.title
	tag.text = scene.tag
	_queue_hud_layout()

func _buffer_progress(_loaded: int, _total: int, _percent: int, _name: String, _ready: bool, token: int) -> void:
	if token == generation and playing and not closing and is_inside_tree() and not is_queued_for_deletion():
		_render_buffer()

func _render_buffer() -> void:
	var complete := buffer_loader == null or buffer_loader.complete
	buffer_status.text = buffer_rules.ready if complete else String(buffer_rules.pending).replace("{percent}", str(buffer_loader.percent))
	caption.text = buffer_rules.readyHint if complete else buffer_rules.pendingHint
	_layout_hud(NativeUi.safe_area(self), size.x > size.y)

func _try_skip() -> void:
	if not playing or closing or not is_inside_tree() or is_queued_for_deletion():
		return
	if buffer_loader == null or buffer_loader.complete:
		finish()
		return
	buffer_warning = true
	buffer_status.text = String(buffer_rules.warning).replace("{percent}", str(buffer_loader.percent))
	_layout_hud(NativeUi.safe_area(self), size.x > size.y)
	var timer := Timer.new()
	timer.one_shot = true
	timer.ignore_time_scale = true
	timer.process_mode = Node.PROCESS_MODE_ALWAYS
	buffer_warning_timers.append(timer)
	var token := generation
	add_child(timer)
	if token != generation or not playing or closing or not buffer_warning_timers.has(timer):
		return
	var deadline := _now_msec() + float(buffer_rules.warningMsec)
	timer.timeout.connect(_buffer_warning_timeout.bind(timer, deadline, generation))
	timer.start(float(buffer_rules.warningMsec) / 1000)

func _buffer_warning_timeout(timer: Timer, deadline: float, token: int) -> void:
	if token != generation or not playing or not buffer_warning_timers.has(timer):
		return
	var remaining := deadline - _now_msec()
	if remaining > 0:
		timer.start(remaining / 1000)
		return
	buffer_warning_timers.erase(timer)
	timer.queue_free()
	buffer_warning = false
	_render_buffer()

func _retire_buffer() -> void:
	if buffer_loader != null:
		buffer_loader.retire()
		buffer_loader.queue_free()
		buffer_loader = null
	for timer: Timer in buffer_warning_timers:
		timer.stop()
		timer.queue_free()
	buffer_warning_timers.clear()
	buffer_warning = false
	if is_instance_valid(buffer_status):
		buffer_status.hide()
		caption.text = Content.label("story_skip_hint")
		_layout_hud(NativeUi.safe_area(self), size.x > size.y)

func finish() -> void:
	if not playing or closing:
		return
	var token := generation
	closing = true
	held_at = -1
	hold_indicator.cancel()
	finish_touches.clear()
	finishing.emit()
	if not is_instance_valid(self) or is_queued_for_deletion() or not is_inside_tree() or token != generation or not playing or not closing:
		return
	set_process(false)
	set_process_input(false)
	exit_tween = create_tween().set_ignore_time_scale(true)
	exit_tween.tween_property(self, "fade_opacity", 0.0, float(Content.campaign.presentation.skip.fade)).set_custom_interpolator(_exit_curve)
	exit_deadline = _now_msec() + float(Content.campaign.presentation.skip.fade) * 1000
	exit_timer = Timer.new()
	exit_timer.one_shot = true
	exit_timer.ignore_time_scale = true
	exit_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(exit_timer)
	exit_timer.timeout.connect(_complete_exit.bind(token))
	exit_timer.start(float(Content.campaign.presentation.skip.fade))

func _complete_exit(token: int) -> void:
	if token != generation or not playing or not closing or not is_inside_tree() or is_queued_for_deletion():
		return
	var remaining := exit_deadline - _now_msec()
	if remaining > 0:
		exit_timer.start(remaining / 1000)
		return
	dispose()
	finished.emit()

func _exit_curve(value: float) -> float:
	var curve: Array = transition_rules.exit.curve
	return HurtFlashState.bezier(value, Vector2(curve[0], curve[1]), Vector2(curve[2], curve[3]))

func dispose() -> void:
	generation += 1
	_retire_buffer()
	playing = false
	held_at = -1
	hold_indicator.reset()
	last_tap = 0
	finish_touches.clear()
	active = -1
	scroll_offset = 0
	last_frame_at = 0
	paused_until = 0
	set_process(false)
	set_process_input(false)
	_cancel_transitions()
	for child in column.get_children():
		column.remove_child(child)
		child.queue_free()
	sections.clear()
	for layer: Control in art_layers:
		art_host.remove_child(layer)
		layer.queue_free()
	art_layers.clear()
	scenes.clear()
	hide()

func _cancel_transitions() -> void:
	for layer: Control in art_layers:
		layer.cancel()
	if exit_tween != null and exit_tween.is_valid():
		exit_tween.kill()
	if exit_timer != null:
		exit_timer.stop()
		exit_timer.queue_free()
		exit_timer = null
	exit_deadline = 0

func _exit_tree() -> void:
	generation += 1
	_retire_buffer()
	playing = false
	closing = false
	held_at = -1
	finish_touches.clear()
	_cancel_transitions()
	if is_instance_valid(hold_indicator):
		hold_indicator.reset()
	set_process(false)
	set_process_input(false)
	hide()
