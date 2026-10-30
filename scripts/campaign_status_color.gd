class_name CampaignStatusColor
extends Label

var rules: Dictionary
var current_color := Color.WHITE
var start_color := Color.WHITE
var target_color := Color.WHITE
var reversing_start := Color.WHITE
var shortening := 1.0
var initialized := false
var warning_text := false
var tween: Tween
var progress := 1.0:
	set(value):
		progress = value
		current_color = start_color.lerp(target_color, value)
		_publish_color()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func set_state(ready: bool, warning: bool, is_warning_text: bool) -> void:
	warning_text = is_warning_text
	var target := _color("warning" if warning else "ready" if ready else "pending")
	if not initialized:
		initialized = true
		current_color = target
		start_color = target
		target_color = target
		reversing_start = target
		shortening = 1.0
		progress = 1.0
		return
	if target == target_color:
		_publish_color()
		return
	var factor := 1.0
	var reversing := current_color
	if tween != null and tween.is_valid():
		if target == reversing_start:
			factor = CssTransition.reversal_factor(progress, shortening)
			reversing = target_color
		tween.kill()
	tween = null
	start_color = current_color
	target_color = target
	reversing_start = reversing
	shortening = factor
	if not is_inside_tree() or start_color == target_color or factor == 0:
		tween = null
		progress = 1.0
		return
	tween = create_tween().set_ignore_time_scale(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(self, "progress", 1.0, float(rules.duration) * factor).set_custom_interpolator(_curve)
	progress = 0.0

func retire() -> void:
	if tween != null and tween.is_valid():
		tween.kill()
	tween = null
	initialized = false
	warning_text = false

func _exit_tree() -> void:
	retire()

func _color(key: String) -> Color:
	var values: Array = rules.colors[key]
	return Color(values[0], values[1], values[2])

func _publish_color() -> void:
	add_theme_color_override("font_color", _color("warning") if warning_text else current_color)

func _curve(value: float) -> float:
	var curve: Array = rules.curve
	return HurtFlashState.bezier_values(value, curve[0], curve[1], curve[2], curve[3])
