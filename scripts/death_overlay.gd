class_name DeathOverlay
extends Control

var state := DeathOverlayState.new()
var rim: ColorRect
var flash: ColorRect
var passes: Array[SubViewport] = []
var materials: Array[ShaderMaterial] = []
var rim_material: ShaderMaterial

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for index in range(3):
		var viewport := SubViewport.new()
		viewport.disable_3d = true
		viewport.transparent_bg = true
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(viewport)
		passes.append(viewport)
		var rectangle := ColorRect.new()
		rectangle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var shader := ShaderMaterial.new()
		shader.shader = preload("res://shaders/death_rim_mask.gdshader") if index == 0 else preload("res://shaders/splat_blur.gdshader")
		rectangle.material = shader
		viewport.add_child(rectangle)
		materials.append(shader)
		if index > 0:
			shader.set_shader_parameter("input_texture", passes[index - 1].get_texture())
			shader.set_shader_parameter("direction", Vector2.RIGHT if index == 1 else Vector2.DOWN)
	rim = ColorRect.new()
	rim.z_index = int(Content.balance.deathOverlay.layers.rim)
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rim)
	rim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rim_material = ShaderMaterial.new()
	rim_material.shader = preload("res://shaders/death_rim_present.gdshader")
	rim_material.set_shader_parameter("shadow_texture", passes[2].get_texture())
	var color: Array = Content.balance.deathOverlay.color
	rim_material.set_shader_parameter("rim_color", Color(color[0], color[1], color[2], color[3]))
	rim.material = rim_material
	flash = ColorRect.new()
	flash.z_index = int(Content.balance.deathOverlay.layers.flash)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.color = Color.WHITE
	add_child(flash)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_bake)
	_bake()
	clear()

func receive(on: bool, whiteout: bool) -> void:
	state.receive(on, whiteout, BodyPresentation.time_now())
	paint(BodyPresentation.time_now())

func paint(now: float) -> void:
	rim.visible = state.active
	rim_material.set_shader_parameter("opacity", state.pulse(now))
	var alpha := state.white(now)
	flash.visible = alpha > 0
	flash.modulate.a = alpha

func _process(_delta: float) -> void:
	paint(BodyPresentation.time_now())

func clear() -> void:
	state.clear()
	if rim != null:
		rim.hide()
		flash.hide()

func _bake() -> void:
	if size.x <= 0 or size.y <= 0 or passes.is_empty():
		return
	var rules: Dictionary = Content.balance.deathOverlay
	var sigma := float(rules.blur) * .5
	var padding := ceilf(sigma * 3) + 1
	var target := Vector2i(ceili(size.x + padding * 2), ceili(size.y + padding * 2))
	for index in range(passes.size()):
		passes[index].size = target
		(passes[index].get_child(0) as Control).size = Vector2(target)
		materials[index].set_shader_parameter("target_size", Vector2(target))
		if index > 0:
			materials[index].set_shader_parameter("sigma", sigma)
		passes[index].render_target_update_mode = SubViewport.UPDATE_ONCE
	materials[0].set_shader_parameter("canvas_size", size)
	materials[0].set_shader_parameter("padding", padding)
	materials[0].set_shader_parameter("spread", float(rules.spread))
	rim_material.set_shader_parameter("target_size", Vector2(target))
	rim_material.set_shader_parameter("canvas_size", size)
	rim_material.set_shader_parameter("padding", padding)
