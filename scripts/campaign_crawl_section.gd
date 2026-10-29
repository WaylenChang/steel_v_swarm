extends Container

var scene: Dictionary = {}
var marker_rules: Dictionary = {}
var opacity_rules: Dictionary = {}
var layer: Sprite2D
var content: VBoxContainer
var marker: HBoxContainer
var paragraphs: VBoxContainer
var selected := false
var tween: Tween
var transition: Dictionary = {}
var opacity := 0.0:
	set(value):
		opacity = value
		if is_instance_valid(layer):
			layer.opacity = value

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer = preload("res://scripts/dialogue_radio_layer.gd").new()
	add_child(layer)
	content = VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.content.add_child(content)
	content.minimum_size_changed.connect(_content_changed)
	marker = HBoxContainer.new()
	marker.add_theme_constant_override("separation", int(marker_rules.gap))
	content.add_child(marker)
	marker.add_child(NativeUi.label(scene.badge, 19))
	var title := NativeUi.label(String(marker_rules.prefix) + String(scene.title), 19)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	marker.add_child(title)
	paragraphs = VBoxContainer.new()
	content.add_child(paragraphs)
	for paragraph: String in scene.paragraphs:
		paragraphs.add_child(NativeUi.prose(paragraph, 18))
	opacity = float(opacity_rules.inactive)
	queue_sort()

func _get_minimum_size() -> Vector2:
	return content.get_combined_minimum_size() if is_instance_valid(content) else Vector2.ZERO

func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN and is_instance_valid(layer) and is_instance_valid(content):
		layer.layout_radio(size)
		content.size = size

func _content_changed() -> void:
	update_minimum_size()
	queue_sort()

func set_paragraph_gap(gap: int) -> void:
	paragraphs.add_theme_constant_override("separation", gap)

func select(value: bool, initial: bool = false) -> void:
	if selected == value:
		return
	selected = value
	var target := float(opacity_rules.active) if value else float(opacity_rules.inactive)
	if initial:
		if tween != null and tween.is_valid():
			tween.kill()
		tween = null
		transition.clear()
		opacity = target
		return
	tween = preload("res://scripts/css_transition.gd").start(self, "opacity", target,
		float(opacity_rules.duration), tween, transition, _curve)
	if tween != null:
		tween.set_ignore_time_scale(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)

func _curve(value: float) -> float:
	var curve: Array = opacity_rules.curve
	return HurtFlashState.bezier_values(value, curve[0], curve[1], curve[2], curve[3])

func _exit_tree() -> void:
	if tween != null and tween.is_valid():
		tween.kill()
	if is_instance_valid(layer):
		layer.retire()
