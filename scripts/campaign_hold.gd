class_name CampaignHold
extends Control

var rules: Dictionary
var active := false
var opacity := 0.0:
	set(value):
		opacity = value
		if group != null:
			group.self_modulate = Color(value, value, value, value)
			viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if active or value > 0 else SubViewport.UPDATE_DISABLED
var dash_offset := 0.0:
	set(value):
		dash_offset = value
		if stroke != null:
			_render_offset()
var dash_target := 0.0
var opacity_tween: Tween
var dash_tween: Tween
var opacity_transition: Dictionary = {}
var dash_transition: Dictionary = {}
var backplate: TextureRect
var group: TextureRect
var viewport: SubViewport
var content: Control
var stroke: TextureRect

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rules = Content.read_json("res://data/campaign_hold.json").rules
	viewport = SubViewport.new()
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.world_2d = World2D.new()
	viewport.size = Vector2i(rules.imageSize[0], rules.imageSize[1])
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	content = Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.position = -Vector2(rules.imageOffset[0], rules.imageOffset[1])
	viewport.add_child(content)
	group = TextureRect.new()
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.texture = viewport.get_texture()
	group.position = Vector2(rules.imageOffset[0], rules.imageOffset[1])
	group.size = Vector2(rules.imageSize[0], rules.imageSize[1])
	group.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var blend := CanvasItemMaterial.new()
	blend.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	group.material = blend
	add_child(group)
	backplate = TextureRect.new()
	backplate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backplate.texture = load(rules.image)
	backplate.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	backplate.position = Vector2(rules.imageOffset[0], rules.imageOffset[1])
	backplate.size = Vector2(rules.imageSize[0], rules.imageSize[1])
	content.add_child(backplate)
	stroke = TextureRect.new()
	stroke.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stroke.position = Vector2(-30, -30)
	stroke.size = Vector2(60, 60)
	stroke.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	content.add_child(stroke)
	reset()

func begin(point: Vector2, viewport_size: Vector2) -> void:
	# Removing and re-adding the source active class in one task does not restart opacity.
	_set_offset(TAU * float(rules.radius))
	var x := float(point.x) if point.x != 0 else float(viewport_size.x) / 2
	var y := float(point.y) if point.y != 0 else float(viewport_size.y) / 2
	var edge: float = rules.edge
	global_position = Vector2(maxf(edge, minf(viewport_size.x - edge, x)), maxf(edge, minf(viewport_size.y - edge, y)))
	_set_active(true)

func advance(progress: float) -> void:
	_set_offset(TAU * float(rules.radius) * (1 - minf(1, progress)))

func cancel() -> void:
	_set_active(false)
	_set_offset(TAU * float(rules.radius))

func _set_active(value: bool) -> void:
	if active == value:
		return
	active = value
	opacity_tween = preload("res://scripts/css_transition.gd").start(self, "opacity", float(value),
		rules.opacityDuration, opacity_tween, opacity_transition, _ease)
	if opacity_tween != null:
		opacity_tween.set_ignore_time_scale(true)

func _set_offset(value: float) -> void:
	if dash_target == value:
		return
	dash_target = value
	dash_tween = preload("res://scripts/css_transition.gd").start(self, "dash_offset", value,
		rules.dashDuration, dash_tween, dash_transition, _linear)
	if dash_tween != null:
		dash_tween.set_ignore_time_scale(true)

static func _ease(value: float) -> float:
	return HurtFlashState.bezier(value, Vector2(.25, .1), Vector2(.25, 1))

static func _linear(value: float) -> float:
	return value

func reset() -> void:
	if opacity_tween != null:
		opacity_tween.kill()
	if dash_tween != null:
		dash_tween.kill()
	active = false
	opacity = 0
	dash_target = rules.initialOffset
	dash_offset = dash_target
	opacity_transition.clear()
	dash_transition.clear()

func _render_offset() -> void:
	var dash: float = rules.dashArray
	var length: float = rules.pathLength
	var covered := false
	for index in range(-1, 3):
		var start := maxf(0, index * dash * 2 - dash_offset)
		var end := minf(length, index * dash * 2 + dash - dash_offset)
		covered = covered or end > start
	stroke.self_modulate.a = 1 if covered else 0
	if not covered:
		return
	var image := Image.new()
	if image.load_svg_from_string(str(rules.progressSvg).replace("OFFSET", str(dash_offset))) != OK:
		push_error("Cannot rasterize original cinematic hold SVG")
		return
	if stroke.texture == null:
		stroke.texture = ImageTexture.create_from_image(image)
	else:
		(stroke.texture as ImageTexture).update(image)
