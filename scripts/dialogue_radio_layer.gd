extends Sprite2D

var viewport: SubViewport
var content: Control
var retired := false
var opacity := 1.0:
	set(value):
		opacity = value
		# The isolated texture stores premultiplied pixels.
		self_modulate = Color(value, value, value, value)

func _ready() -> void:
	if retired or is_queued_for_deletion():
		return
	centered = false
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var blend := CanvasItemMaterial.new()
	blend.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	material = blend
	viewport = SubViewport.new()
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	content = Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.add_child(content)
	texture = viewport.get_texture()
	visibility_changed.connect(_sync_visibility)

func _sync_visibility() -> void:
	if retired or not is_instance_valid(viewport):
		return
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED

func layout_radio(view_size: Vector2) -> void:
	if retired or not is_instance_valid(viewport):
		return
	viewport.size = Vector2i(view_size.ceil()).max(Vector2i.ONE)
	content.size = view_size

func retire() -> void:
	if retired:
		return
	retired = true
	if is_instance_valid(viewport):
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	hide()
