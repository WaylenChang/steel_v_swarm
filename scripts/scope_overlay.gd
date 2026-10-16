class_name ScopeOverlay
extends ColorRect

var fire_opacity := 0.0
var weather_opacity := 0.0
var fire_target := 0.0
var weather_target := 0.0
var fire_tween: Tween
var weather_tween: Tween
var shader_material: ShaderMaterial

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shader_material = ShaderMaterial.new()
	shader_material.shader = preload("res://shaders/scope_mask.gdshader")
	material = shader_material
	var rules: Dictionary = Content.balance.view.mask
	shader_material.set_shader_parameter("ring_width", rules.ringWidth)
	shader_material.set_shader_parameter("ring_color", color_value(rules.ringColor))
	shader_material.set_shader_parameter("fire_stops", Vector3(rules.fireStops[0], rules.fireStops[1], rules.fireStops[2]))
	for index: int in range(3):
		shader_material.set_shader_parameter("fire_color_" + str(index), color_value(rules.fireColors[index]))
		shader_material.set_shader_parameter("weather_color_" + str(index), color_value(rules.weatherColors[index]))
	hide()

static func color_value(value: Array) -> Color:
	return Color(value[0], value[1], value[2], value[3])

func update_view(state: ScopeState, scoped: bool) -> void:
	var rules: Dictionary = Content.balance.view.mask
	if fire_target != state.fire_fog:
		fire_target = state.fire_fog
		if fire_tween != null:
			fire_tween.kill()
		fire_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		fire_tween.tween_property(self, "fire_opacity", fire_target, rules.fireTransition)
	if weather_target != state.weather_fog:
		weather_target = state.weather_fog
		if weather_tween != null:
			weather_tween.kill()
		weather_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		weather_tween.tween_property(self, "weather_opacity", weather_target, rules.weatherTransition)
	var radius := ScopeState.radius_vmin(state.fire_fog, state.weather_fog)
	var inner := maxf(float(rules.weatherInnerMinimum), radius - float(rules.weatherInnerInset))
	var stops := ScopeState.weather_stops(state.weather_fog)
	# Original CSS serializes gradient anchors to one decimal place.
	shader_material.set_shader_parameter("radius_vmin", roundf(radius * 10) / 10)
	shader_material.set_shader_parameter("weather_inner_vmin", roundf(inner * 10) / 10)
	shader_material.set_shader_parameter("weather_stops", Vector2(roundf(stops.x * 1000) / 1000, roundf(stops.y * 1000) / 1000))
	shader_material.set_shader_parameter("viewport_size", size)
	shader_material.set_shader_parameter("scoped", scoped)
	shader_material.set_shader_parameter("fire_opacity", fire_opacity)
	shader_material.set_shader_parameter("weather_opacity", weather_opacity)
	shader_material.set_shader_parameter("fire_blur", roundf(state.fire_fog * float(rules.blurPixels) * 100) / 100)
	visible = scoped or fire_opacity > 0 or weather_opacity > 0 or fire_target > 0 or weather_target > 0

func clear() -> void:
	if fire_tween != null:
		fire_tween.kill()
	if weather_tween != null:
		weather_tween.kill()
	fire_opacity = 0
	weather_opacity = 0
	fire_target = 0
	weather_target = 0
	hide()
