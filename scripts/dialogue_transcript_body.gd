extends Container

var script_scroll: ScrollContainer
var rows: VBoxContainer
var padding: MarginContainer
var portraits: Array[TextureRect] = []
var rules: Dictionary

func _enter_tree() -> void:
	if is_instance_valid(rows):
		get_viewport().size_changed.connect(_viewport_changed)
		_viewport_changed()

func _ready() -> void:
	rules = Content.read_json("res://data/dialogue_body.json").rules
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	script_scroll = ScrollContainer.new()
	script_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var empty := StyleBoxEmpty.new()
	script_scroll.add_theme_stylebox_override("panel", empty)
	var rail := StyleBoxEmpty.new()
	rail.content_margin_left = rules.scrollbarWidth
	script_scroll.get_v_scroll_bar().add_theme_stylebox_override("scroll", rail)
	add_child(script_scroll)
	padding = MarginContainer.new()
	padding.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for index in range(4):
		padding.add_theme_constant_override(["margin_left", "margin_top", "margin_right", "margin_bottom"][index], int(rules.padding[index]))
	script_scroll.add_child(padding)
	rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", int(rules.gap))
	padding.add_child(rows)
	rows.minimum_size_changed.connect(func(): update_minimum_size(); queue_sort())
	get_viewport().size_changed.connect(_viewport_changed)
	_viewport_changed()

func add_portrait(texture: Texture2D, right: bool) -> void:
	var portrait := TextureRect.new()
	portrait.texture = texture
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_SCALE
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.flip_h = right
	portrait.modulate.a = rules.artOpacity
	portrait.set_meta("right", right)
	add_child(portrait)
	move_child(portrait, 0)
	portraits.append(portrait)
	queue_sort()

func _viewport_changed() -> void:
	if not is_inside_tree():
		return
	update_minimum_size()
	queue_sort()
	queue_redraw()

func _source_height() -> float:
	if not is_instance_valid(rows) or not is_inside_tree():
		return 0
	var vertical_padding: float = rules.padding[1] + rules.padding[3]
	var limit := floorf(get_viewport().get_visible_rect().size.y * float(rules.maxHeightRatio) * float(rules.layoutUnits)) / float(rules.layoutUnits)
	return maxf(vertical_padding, minf(rows.get_combined_minimum_size().y + vertical_padding, limit))

func _get_minimum_size() -> Vector2:
	return Vector2(0, _source_height())

func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN and is_inside_tree() and is_instance_valid(script_scroll):
		# Container allocations round to pixels; the visible CSS scrolling box does not.
		var height := _source_height()
		script_scroll.position = Vector2.ZERO
		script_scroll.size = Vector2(size.x, height)
		for portrait in portraits:
			portrait.visible = get_viewport().get_visible_rect().size.x > float(rules.artMaxHiddenWidth)
			if portrait.texture == null:
				continue
			var width := float(rules.artWidth)
			var art_height := width * portrait.texture.get_height() / portrait.texture.get_width()
			portrait.size = Vector2(width, art_height)
			portrait.position = Vector2(size.x - width if portrait.get_meta("right") else 0.0, height - art_height)

func _exit_tree() -> void:
	if get_viewport().size_changed.is_connected(_viewport_changed):
		get_viewport().size_changed.disconnect(_viewport_changed)
