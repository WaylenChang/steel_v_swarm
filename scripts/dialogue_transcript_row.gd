extends Container

var layer: Sprite2D
var content: HBoxContainer
var scroll_target: Control
var motion: Tween
var rules: Dictionary
var revealed := false
var progress := 0.0:
	set(value):
		progress = value
		if is_instance_valid(layer):
			layer.opacity = lerpf(float(rules.from), float(rules.to), value)
			layer.position.y = lerpf(float(rules.fromY), float(rules.toY), value)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rules = Content.read_json("res://data/dialogue_transcript.json").motion
	layer = preload("res://scripts/dialogue_radio_layer.gd").new()
	add_child(layer)
	content = HBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.content.add_child(content)
	content.minimum_size_changed.connect(func(): update_minimum_size(); queue_sort())
	scroll_target = Control.new()
	scroll_target.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scroll_target)
	progress = 0
	queue_sort()

func _get_minimum_size() -> Vector2:
	return content.get_combined_minimum_size() if is_instance_valid(content) else Vector2.ZERO

func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN and is_instance_valid(layer):
		layer.layout_radio(size)
		content.size = size
		scroll_target.position = Vector2(0, float(rules.fromY))
		scroll_target.size = size

func reveal() -> void:
	if revealed:
		return
	revealed = true
	motion = create_tween().set_ignore_time_scale(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	motion.tween_property(self, "progress", 1.0, float(rules.duration)).set_custom_interpolator(_curve)
	_scroll_nearest()

func _curve(value: float) -> float:
	var curve: Array = rules.curve
	return HurtFlashState.bezier_values(value, curve[0], curve[1], curve[2], curve[3])

func _scroll_nearest() -> void:
	var ancestor := get_parent()
	var rectangle := scroll_target.get_global_rect()
	while ancestor != null:
		if ancestor is ScrollContainer:
			var bar: VScrollBar = ancestor.get_v_scroll_bar()
			if bar.max_value > bar.page:
				var branch: Node = scroll_target
				while branch.get_parent() != ancestor:
					branch = branch.get_parent()
				var margin: float = ancestor.get_theme_stylebox("panel").get_margin(SIDE_TOP)
				# ScrollContainer applies its content offset during layout, after Range changes.
				rectangle.position.y -= bar.value + branch.position.y - margin
				var top: float = rectangle.position.y - ancestor.get_global_rect().position.y - margin
				var bottom: float = top + rectangle.size.y
				var delta := 0.0
				if not (top < 0 and bottom > bar.page):
					if top < 0:
						delta = top if rectangle.size.y <= bar.page else bottom - bar.page
					elif bottom > bar.page:
						delta = bottom - bar.page if rectangle.size.y <= bar.page else top
				var previous := bar.value
				ancestor.scroll_vertical = roundi(bar.value + delta)
				rectangle.position.y -= bar.value - previous
				# Outer scrollers consume only the portion visible through this viewport.
				var clip_top: float = ancestor.get_global_rect().position.y + margin
				var clipped_bottom := minf(rectangle.end.y, clip_top + bar.page)
				rectangle.position.y = clampf(rectangle.position.y, clip_top, clip_top + bar.page)
				rectangle.size.y = maxf(0, clipped_bottom - rectangle.position.y)
		ancestor = ancestor.get_parent()

func _exit_tree() -> void:
	if motion != null and motion.is_valid():
		motion.kill()
	if is_instance_valid(layer):
		layer.retire()
