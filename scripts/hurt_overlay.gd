class_name HurtOverlay
extends ColorRect

var state := HurtFlashState.new()
var shader_material: ShaderMaterial

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shader_material = ShaderMaterial.new()
	shader_material.shader = preload("res://shaders/hurt_vignette.gdshader")
	var rules: Dictionary = Content.balance.hurtPresentation
	shader_material.set_shader_parameter("inner", rules.inner)
	shader_material.set_shader_parameter("hurt_color", Color(rules.color[0], rules.color[1], rules.color[2], rules.color[3]))
	material = shader_material
	hide()

func flash() -> void:
	if state.trigger(BodyPresentation.time_now()):
		show()
		shader_material.set_shader_parameter("opacity", 0.0)

func _process(_delta: float) -> void:
	if not state.active:
		return
	var now := BodyPresentation.time_now()
	shader_material.set_shader_parameter("opacity", state.opacity(now))
	if now - state.started >= float(Content.balance.hurtPresentation.duration):
		clear()

func clear() -> void:
	state.finish()
	hide()
