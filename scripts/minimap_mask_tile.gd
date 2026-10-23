class_name MinimapMaskTile
extends Control

var plan: Dictionary = {}
var hard: Control
var soft: ColorRect
var soft_material: ShaderMaterial
var shadows: Array[Polygon2D] = []
var region := AtlasTexture.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	hard = Control.new()
	hard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hard)
	hard.draw.connect(_draw_hard)
	soft = ColorRect.new()
	soft.mouse_filter = Control.MOUSE_FILTER_IGNORE
	soft_material = ShaderMaterial.new()
	soft_material.shader = preload("res://shaders/minimap_soft_reveal.gdshader")
	soft.material = soft_material
	add_child(soft)
	region.filter_clip = true

func configure(value: Dictionary, atlas_position: Vector2, texture: Texture2D) -> void:
	plan = value
	position = atlas_position
	size = plan.clip.size
	region.atlas = texture
	region.region = Rect2(atlas_position, size)
	hard.size = size
	hard.visible = not plan.soft
	soft.visible = plan.soft
	soft.position = plan.center - plan.radius - plan.clip.position
	soft.size = plan.radius * 2
	soft_material.set_shader_parameter("soft_start", float(Content.balance.minimap.fog.softStart))
	for index in plan.polygons.size():
		if index >= shadows.size():
			var polygon := Polygon2D.new()
			polygon.color = Color.BLACK
			polygon.antialiased = true
			add_child(polygon)
			shadows.append(polygon)
		var points := PackedVector2Array()
		for point: Vector2 in plan.polygons[index]:
			points.append(point - plan.clip.position)
		shadows[index].polygon = points
		shadows[index].show()
	for index in range(plan.polygons.size(), shadows.size()):
		shadows[index].hide()
	show()
	hard.queue_redraw()

func _draw_hard() -> void:
	if plan.is_empty() or plan.soft:
		return
	hard.draw_ellipse(plan.center - plan.clip.position, plan.radius.x, plan.radius.y, Color.WHITE, true, -1, true)
