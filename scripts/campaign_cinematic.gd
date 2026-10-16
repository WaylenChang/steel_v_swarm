class_name CampaignCinematic
extends Control

signal finished
signal finishing

var scenes: Array = []
var active := -1
var playing := false
var closing := false
var scroll: ScrollContainer
var column: VBoxContainer
var sections: Array[Control] = []
var background: TextureRect
var previous_background: TextureRect
var frame: Control
var image: TextureRect
var previous_image: TextureRect
var card: PanelContainer
var heading: Label
var tag: Label
var finish_button: Button
var caption: Label
var scroll_offset := 0.0
var paused_until := 0.0
var held_at := -1.0
var last_tap := -1.0
var writing_scroll := false
var change_tween: Tween
var exit_tween: Tween
var generation := 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color("#05070a")
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	previous_background = _image()
	background = _image()
	add_child(previous_background)
	add_child(background)
	for item: TextureRect in [previous_background, background]:
		var material := ShaderMaterial.new()
		material.shader = load("res://shaders/cinematic_blur.gdshader")
		item.material = material
	frame = Control.new()
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	previous_image = _image()
	image = _image()
	frame.add_child(previous_image)
	frame.add_child(image)
	card = NativeUi.panel(Vector2(560, 340))
	add_child(card)
	var body := VBoxContainer.new()
	card.add_child(body)
	tag = NativeUi.label("", 14)
	body.add_child(tag)
	heading = NativeUi.label("", 23)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(heading)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 180
	body.add_child(scroll)
	column = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 38)
	scroll.add_child(column)
	caption = NativeUi.label(Content.label("story_skip_hint"), 14)
	body.add_child(caption)
	scroll.get_v_scroll_bar().value_changed.connect(func(value):
		if not writing_scroll:
			scroll_offset = value
		_update_scene())
	scroll.gui_input.connect(_scroll_input)
	resized.connect(_layout)
	hide()
	set_process(false)
	set_process_input(false)

func _image() -> TextureRect:
	var result := TextureRect.new()
	result.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return result

func play(sequence: Array, finish_text: String, start_index: int = 0) -> void:
	if sequence.is_empty():
		finished.emit()
		return
	dispose()
	var token := generation
	scenes = sequence.duplicate(true)
	for scene: Dictionary in scenes:
		var section := VBoxContainer.new()
		section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		section.add_child(NativeUi.label(scene.badge + " · " + scene.title, 19))
		section.add_child(NativeUi.prose("\n\n".join(PackedStringArray(scene.paragraphs)), 18))
		column.add_child(section)
		sections.append(section)
	finish_button = NativeUi.button(finish_text, finish)
	column.add_child(finish_button)
	playing = true
	closing = false
	modulate.a = 1.0
	show()
	set_process(true)
	set_process_input(true)
	_layout()
	_set_scene(clampi(start_index, 0, scenes.size() - 1))
	await get_tree().process_frame
	if token != generation or not playing or closing:
		return
	if start_index > 0 and start_index < sections.size():
		var section: Control = sections[start_index]
		scroll_offset = maxf(0, section.position.y + section.size.y * float(Content.campaign.presentation.crawl.start) - scroll.size.y * float(Content.campaign.presentation.crawl.focus))
	_write_scroll()
	_update_scene()

func _layout() -> void:
	if not is_instance_valid(frame):
		return
	var landscape := size.x >= size.y
	frame.size = Vector2(minf(size.y, size.x * 0.94), size.y) if landscape else size
	frame.position = Vector2((size.x - frame.size.x) / 2, 0)
	var scale_factor: float = Content.campaign.get("presentation", {}).get("art", {}).get("backgroundScale", 1.0)
	for item: TextureRect in [previous_background, background]:
		item.size = size * scale_factor
		item.position = (size - item.size) / 2
	card.size = Vector2(minf(560, size.x - 32), minf(360, size.y * (0.46 if landscape else 0.40)))
	card.position = Vector2(28 if landscape else (size.x - card.size.x) / 2, size.y - card.size.y - 32)
	card.custom_minimum_size = Vector2.ZERO
	_update_scene()

func _process(delta: float) -> void:
	if not playing or closing:
		return
	var now := float(Time.get_ticks_msec()) / 1000.0
	if held_at >= 0 and now - held_at >= float(Content.campaign.presentation.skip.hold):
		held_at = -1
		finish()
		return
	if now > paused_until:
		var rules: Dictionary = Content.campaign.presentation.crawl
		var maximum := maxf(0, scroll.get_v_scroll_bar().max_value - scroll.get_v_scroll_bar().page)
		scroll_offset = minf(maximum, scroll_offset + float(rules.speed) * minf(delta, float(rules.maximumFrame)))
		_write_scroll()
	_update_scene()

func _write_scroll() -> void:
	writing_scroll = true
	scroll.scroll_vertical = int(scroll_offset)
	writing_scroll = false

func _scroll_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		paused_until = float(Time.get_ticks_msec()) / 1000.0 + float(Content.campaign.presentation.crawl.pause)

func _input(event: InputEvent) -> void:
	if not playing or closing:
		return
	var now := float(Time.get_ticks_msec()) / 1000.0
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			held_at = now
			if event.double_click:
				finish()
		else:
			held_at = -1
	elif event is InputEventScreenTouch:
		if event.pressed:
			held_at = now
		else:
			held_at = -1
			if last_tap >= 0 and now - last_tap < float(Content.campaign.presentation.skip.doubleTap):
				finish()
			last_tap = now

func _update_scene() -> void:
	if not playing or scenes.is_empty() or sections.is_empty():
		return
	var positions: Array = []
	for section: Control in sections:
		positions.append({"top": section.position.y, "height": section.size.y})
	var focus := CampaignRules.focus_section(scroll.scroll_vertical, scroll.size.y, positions, active)
	_set_scene(int(focus.index))
	var pose := CampaignRules.camera_pose(scenes[active].camera, focus.progress, size.x >= size.y)
	if pose.is_empty():
		return
	var inset: float = Content.campaign.presentation.art.inset
	image.size = frame.size * (1 + inset * 2)
	image.pivot_offset = image.size / 2
	image.scale = Vector2.ONE * float(pose.scale)
	image.position = -frame.size * inset + image.size * Vector2(pose.x, pose.y) / 100

func _set_scene(index: int) -> void:
	if index == active or index < 0 or index >= scenes.size():
		return
	if change_tween != null and change_tween.is_valid():
		change_tween.kill()
	previous_image.texture = image.texture
	previous_image.size = image.size
	previous_image.position = image.position
	previous_image.pivot_offset = image.pivot_offset
	previous_image.scale = image.scale
	previous_background.texture = background.texture
	previous_image.modulate.a = 1
	previous_background.modulate.a = 1
	active = index
	var scene: Dictionary = scenes[index]
	var path: String = scene.img
	if Content.story_texture(path) == null:
		path = scene.get("fallbackImg", "")
	image.texture = Content.story_texture(path)
	background.texture = Content.story_texture(path, true)
	var style: Dictionary = Content.campaign.presentation.art
	for item: TextureRect in [previous_background, background]:
		item.material.set_shader_parameter("brightness", style.brightness)
		item.material.set_shader_parameter("saturation", style.saturation)
		item.material.set_shader_parameter("mip_level", log(float(style.blur)) / log(2.0))
	image.modulate.a = 0
	background.modulate.a = 0
	heading.text = scene.badge + " · " + scene.title
	tag.text = scene.tag
	change_tween = create_tween().set_parallel(true)
	change_tween.tween_property(image, "modulate:a", 1.0, style.fade)
	change_tween.tween_property(background, "modulate:a", 1.0, style.fade)
	change_tween.tween_property(previous_image, "modulate:a", 0.0, style.fade)
	change_tween.tween_property(previous_background, "modulate:a", 0.0, style.fade)

func finish() -> void:
	if not playing or closing:
		return
	closing = true
	finishing.emit()
	held_at = -1
	set_process(false)
	set_process_input(false)
	exit_tween = create_tween()
	exit_tween.tween_property(self, "modulate:a", 0.0, float(Content.campaign.presentation.skip.fade))
	exit_tween.tween_callback(func():
		dispose()
		finished.emit())

func dispose() -> void:
	generation += 1
	playing = false
	held_at = -1
	last_tap = -1
	active = -1
	scroll_offset = 0
	paused_until = 0
	set_process(false)
	set_process_input(false)
	if change_tween != null and change_tween.is_valid():
		change_tween.kill()
	if exit_tween != null and exit_tween.is_valid():
		exit_tween.kill()
	for child in column.get_children():
		column.remove_child(child)
		child.queue_free()
	sections.clear()
	scenes.clear()
	hide()
