class_name CampaignStatusColor
extends Label

var rules: Dictionary
var flash_rules: Dictionary
var current_color := Color.WHITE
var start_color := Color.WHITE
var target_color := Color.WHITE
var reversing_start := Color.WHITE
var shortening := 1.0
var initialized := false
var warning_text := false
var tween: Tween
var flash_tween: Tween
var flash_class := false
var flash_started := false
var revision := 0
var progress := 1.0:
	set(value):
		progress = value
		current_color = start_color.lerp(target_color, value)
		_publish_color()
var flash_progress := 0.0:
	set(value):
		flash_progress = value
		var token := revision
		modulate.a = lerpf(float(flash_rules.normalOpacity), float(flash_rules.peakOpacity), value)
		if token != revision:
			return
		scale = Vector2.ONE * lerpf(float(flash_rules.normalScale), float(flash_rules.peakScale), value)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	flash_rules = Content.read_json("res://data/campaign_status_flash.json").rules
	pivot_offset = size / 2

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		pivot_offset = size / 2
	elif what == NOTIFICATION_VISIBILITY_CHANGED and is_inside_tree() and not flash_rules.is_empty():
		if is_visible_in_tree():
			if flash_class and not flash_started:
				_start_flash()
		else:
			_stop_flash()

func set_state(ready: bool, warning: bool, is_warning_text: bool) -> void:
	revision += 1
	var token := revision
	warning_text = is_warning_text
	if flash_class != warning:
		flash_class = warning
		if warning and is_visible_in_tree():
			_start_flash()
		elif not warning:
			_stop_flash()
	if token != revision:
		return
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
	revision += 1
	if tween != null and tween.is_valid():
		tween.kill()
	tween = null
	initialized = false
	warning_text = false
	flash_class = false
	_stop_flash()

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

func _start_flash() -> void:
	flash_started = true
	flash_tween = create_tween().set_ignore_time_scale(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	flash_tween.set_loops(int(flash_rules.iterations))
	var half := float(flash_rules.duration) / 2.0
	flash_tween.tween_property(self, "flash_progress", 1.0, half).set_custom_interpolator(_flash_curve)
	flash_tween.tween_property(self, "flash_progress", 0.0, half).set_custom_interpolator(_flash_curve)
	flash_progress = 0.0

func _stop_flash() -> void:
	if flash_tween != null and flash_tween.is_valid():
		flash_tween.kill()
	flash_tween = null
	flash_started = false
	if flash_progress != 0:
		flash_progress = 0.0

func _flash_curve(value: float) -> float:
	var curve: Array = flash_rules.curve
	return HurtFlashState.bezier_values(value, curve[0], curve[1], curve[2], curve[3])
