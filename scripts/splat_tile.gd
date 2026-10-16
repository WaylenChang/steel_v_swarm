class_name SplatTile
extends TextureRect

var layout: Dictionary = {}
var kind := "blood"
var passes: Array[SubViewport] = []
var materials: Array[ShaderMaterial] = []
var present: ShaderMaterial
var canvas_size := Vector2.ZERO
var padding := 0.0
var extent := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	present = ShaderMaterial.new()
	present.shader = preload("res://shaders/splat_present.gdshader")
	material = present
	for index in range(6):
		var viewport := SubViewport.new()
		viewport.disable_3d = true
		viewport.transparent_bg = true
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(viewport)
		passes.append(viewport)
		var rectangle := ColorRect.new()
		var shader := ShaderMaterial.new()
		shader.shader = preload("res://shaders/splat_drops.gdshader") if index == 0 else preload("res://shaders/splat_shadow.gdshader") if index == 5 else preload("res://shaders/splat_blur.gdshader")
		rectangle.material = shader
		rectangle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		viewport.add_child(rectangle)
		materials.append(shader)
	for index in range(1, 5):
		materials[index].set_shader_parameter("input_texture", passes[index - 1].get_texture())
		materials[index].set_shader_parameter("direction", Vector2.RIGHT if index % 2 else Vector2.DOWN)
	materials[5].set_shader_parameter("foreground", passes[2].get_texture())
	materials[5].set_shader_parameter("shadow", passes[4].get_texture())
	texture = passes[5].get_texture()

func configure(entry: Dictionary, flavor: String, viewport_size: Vector2) -> void:
	layout = entry.duplicate(true)
	kind = flavor
	canvas_size = Vector2.ZERO
	resize_canvas(viewport_size)
	show()

func resize_canvas(viewport_size: Vector2) -> void:
	if viewport_size == canvas_size or layout.is_empty() or viewport_size.x <= 0 or viewport_size.y <= 0:
		return
	canvas_size = viewport_size
	var rules: Dictionary = Content.balance.screenSplats.paint[kind]
	var unit := minf(viewport_size.x, viewport_size.y) / 100
	extent = float(rules.extent) * unit
	padding = ceilf((float(rules.blur) + float(rules.shadowBlur)) * unit * 3) + 1
	var target := Vector2i(ceili(extent + padding * 2), ceili(extent + padding * 2))
	size = Vector2(target)
	position = Vector2(float(layout.left) * viewport_size.x, float(layout.top) * viewport_size.y) - Vector2.ONE * (padding + extent * .5)
	var drops := PackedVector3Array()
	for drop: Dictionary in layout.drops:
		drops.append(Vector3(drop.x, drop.y, drop.r))
	assert(drops.size() <= 12, "Original splat shader requires the source drop-count ceiling")
	materials[0].set_shader_parameter("drop_count", drops.size())
	drops.resize(12)
	materials[0].set_shader_parameter("drops", drops)
	materials[0].set_shader_parameter("padding", padding)
	materials[0].set_shader_parameter("extent", extent)
	materials[0].set_shader_parameter("vmin", unit)
	var stops := Vector4.ZERO
	var colors := PackedVector4Array()
	for index in range(4):
		stops[index] = float(rules.stops[index].at)
		var color: Array = rules.stops[index].color
		colors.append(Vector4(color[0], color[1], color[2], color[3]))
	materials[0].set_shader_parameter("stops", stops)
	materials[0].set_shader_parameter("colors", colors)
	var shadow: Array = rules.shadowColor
	materials[5].set_shader_parameter("shadow_color", Color(shadow[0], shadow[1], shadow[2], shadow[3]))
	for index in range(6):
		passes[index].size = target
		(passes[index].get_child(0) as ColorRect).size = Vector2(target)
		if index < 5:
			materials[index].set_shader_parameter("target_size", Vector2(target))
		if index in [1, 2, 3, 4]:
			materials[index].set_shader_parameter("sigma", float(rules.blur if index <= 2 else rules.shadowBlur) * unit)
		passes[index].render_target_update_mode = SubViewport.UPDATE_ONCE

func set_opacity(value: float) -> void:
	present.set_shader_parameter("opacity", value)

func retire() -> void:
	hide()
	for viewport: SubViewport in passes:
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
