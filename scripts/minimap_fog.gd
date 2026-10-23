class_name MinimapFog
extends Control

var atlas: MinimapMaskAtlas
var explored: SubViewport
var current: SubViewport
var full_reveal: ColorRect
var fog_base: ColorRect
var seen_cutout: TextureRect
var overlay: TextureRect
var seen_region := AtlasTexture.new()
var explored_read: ShaderMaterial
var current_read: ShaderMaterial
var present: ShaderMaterial
var explored_tiles: Array[TextureRect] = []
var current_tiles: Array[TextureRect] = []
var blockers := SourceBlockerQuery.new()
var configured := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Child viewports render atlas -> explored -> fog before the main HUD samples it.
	current = _viewport(false, self)
	explored = _viewport(true, current)
	atlas = MinimapMaskAtlas.new()
	explored.add_child(atlas)
	full_reveal = ColorRect.new()
	full_reveal.color = Color.WHITE
	full_reveal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	explored.add_child(full_reveal)
	full_reveal.hide()
	fog_base = ColorRect.new()
	fog_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	current.add_child(fog_base)
	explored_read = _material(true, Color.WHITE)
	current_read = _material(true, Color.BLACK)
	seen_cutout = _rectangle(_material(false, Color.BLACK))
	seen_cutout.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	current.add_child(seen_cutout)
	seen_region.filter_clip = true
	seen_region.atlas = explored.get_texture()
	overlay = _rectangle(null)
	present = ShaderMaterial.new()
	present.shader = preload("res://shaders/minimap_fog_present.gdshader")
	overlay.material = present
	overlay.texture = current.get_texture()
	add_child(overlay)
	overlay.hide()

func clear() -> void:
	configured = false
	if overlay == null:
		return
	overlay.hide()
	seen_cutout.texture = null
	for rectangle: TextureRect in explored_tiles + current_tiles:
		rectangle.texture = null
		rectangle.free()
	explored_tiles.clear()
	current_tiles.clear()
	atlas.clear()
	blockers.clear()
	full_reveal.hide()
	explored.render_target_update_mode = SubViewport.UPDATE_DISABLED
	explored.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	current.render_target_update_mode = SubViewport.UPDATE_DISABLED

func configure(canvas_size: Vector2) -> void:
	clear()
	size = canvas_size
	explored.size = Vector2i(canvas_size)
	current.size = Vector2i(canvas_size)
	full_reveal.size = canvas_size
	fog_base.size = canvas_size
	seen_cutout.size = canvas_size
	overlay.size = canvas_size
	var rules: Dictionary = Content.balance.minimap.fog
	var colour: Array = rules.colour
	# Red stores mask alpha, so ordinary black source-over performs destination-out.
	fog_base.color = Color(colour[3], colour[3], colour[3], 1)
	(seen_cutout.material as ShaderMaterial).set_shader_parameter("strength", float(rules.exploredRemove))
	present.set_shader_parameter("fog_colour", Vector3(colour[0], colour[1], colour[2]))
	configured = true

func update_view(sources: Array, terrain: Dictionary, window: Rect2, side: String, pulse: bool, columns: Array, shared_blockers: SourceBlockerQuery = null) -> void:
	if not configured:
		return
	if side.is_empty():
		overlay.hide()
		atlas.suspend()
		explored.render_target_update_mode = SubViewport.UPDATE_DISABLED
		current.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	if pulse:
		_hide(explored_tiles)
		full_reveal.show()
		atlas.suspend()
		explored.render_target_update_mode = SubViewport.UPDATE_ONCE
		current.render_target_update_mode = SubViewport.UPDATE_DISABLED
		overlay.hide()
		return
	full_reveal.hide()
	var query := shared_blockers if shared_blockers != null else blockers
	query.ensure(columns)
	var shadows: Array = []
	for source: Array in sources:
		var point := Vector2(source[0], source[1])
		shadows.append(MinimapVision.shadows(point, source[2], query.near(point, source[2])))
	var entries := atlas.update(MinimapRevealPlan.build(sources, shadows, terrain, window, size))
	var hard: Array = []
	var soft: Array = []
	for entry: Dictionary in entries:
		if entry.plan.soft:
			soft.append(entry)
		else:
			hard.append(entry)
	_sync(explored, explored_tiles, hard, explored_read)
	_sync(current, current_tiles, soft, current_read)
	seen_region.region = MinimapWindow.texture_region(terrain, window, size)
	seen_cutout.texture = seen_region
	explored.render_target_update_mode = SubViewport.UPDATE_ONCE
	current.render_target_update_mode = SubViewport.UPDATE_ONCE
	overlay.show()

func _viewport(persistent: bool, parent: Node) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.size = Vector2i(2, 2)
	viewport.world_2d = World2D.new()
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE if persistent else SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	parent.add_child(viewport)
	return viewport

static func _material(red: bool, ink: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/minimap_mask_read.gdshader")
	material.set_shader_parameter("red_channel", red)
	material.set_shader_parameter("ink", Vector3(ink.r, ink.g, ink.b))
	return material

static func _rectangle(material: Material) -> TextureRect:
	var rectangle := TextureRect.new()
	rectangle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rectangle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rectangle.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rectangle.material = material
	return rectangle

static func _hide(pool: Array[TextureRect]) -> void:
	for rectangle: TextureRect in pool:
		rectangle.hide()
		rectangle.texture = null

static func _sync(viewport: SubViewport, pool: Array[TextureRect], entries: Array, material: ShaderMaterial) -> void:
	for index in entries.size():
		if index >= pool.size():
			var rectangle := _rectangle(material)
			viewport.add_child(rectangle)
			pool.append(rectangle)
		var rectangle: TextureRect = pool[index]
		var entry: Dictionary = entries[index]
		rectangle.position = entry.plan.clip.position
		rectangle.size = entry.plan.clip.size
		rectangle.texture = entry.texture
		rectangle.show()
	for index in range(entries.size(), pool.size()):
		pool[index].hide()
		pool[index].texture = null
