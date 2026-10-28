class_name CampaignArtLayer
extends Control

var group: TextureRect
var viewport: SubViewport
var content: Control
var background: TextureRect
var frame: Control
var image: TextureRect
var scene: Dictionary = {}
var selected := false
var loaded := false
var texture_provider := Callable()
var rules: Dictionary
var backdrop_rules: Dictionary
var opacity := 0.0:
	set(value):
		opacity = value
		if group != null:
			# Viewport pixels are premultiplied, so opacity scales every channel.
			group.self_modulate = Color(value, value, value, value)
			group.visible = selected or value > 0
			viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if group.visible else SubViewport.UPDATE_DISABLED
var tween: Tween
var transition: Dictionary = {}
var pose := {"scale": 1.0, "x": 0.0, "y": 0.0}
var pose_rules: Dictionary
var pose_target := {"scale": 1.0, "x": 0.0, "y": 0.0}
var pose_start: Dictionary = pose.duplicate()
var pose_reversing_start: Dictionary
var pose_shortening := 1.0
var pose_tween: Tween
var pose_progress := 1.0:
	set(value):
		pose_progress = value
		pose = {}
		for key: String in pose_target:
			pose[key] = lerpf(float(pose_start[key]), float(pose_target[key]), value)
		_apply_pose()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rules = Content.read_json("res://data/campaign_art.json").rules
	backdrop_rules = Content.read_json("res://data/campaign_backdrop.json").rules
	pose_rules = Content.read_json("res://data/campaign_pose.json").rules
	viewport = SubViewport.new()
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	content = Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.add_child(content)
	group = _image()
	group.texture = viewport.get_texture()
	group.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var blend := CanvasItemMaterial.new()
	blend.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	group.material = blend
	add_child(group)
	background = _image()
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/cinematic_blur.gdshader")
	background.material = material
	content.add_child(background)
	frame = Control.new()
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(frame)
	image = _image()
	frame.add_child(image)
	opacity = 0

func _image() -> TextureRect:
	var result := TextureRect.new()
	result.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return result

func _texture(path: String, mipmaps: bool = false) -> Texture2D:
	return texture_provider.call(path, mipmaps) if texture_provider.is_valid() else Content.story_texture(path, mipmaps)

func _load_art() -> void:
	if loaded:
		return
	loaded = true
	var path: String = scene.img
	if _texture(path) == null:
		path = scene.get("fallbackImg", "")
	image.texture = _texture(path)
	background.texture = _texture(path, true)
	var style: Dictionary = Content.campaign.presentation.art
	background.material.set_shader_parameter("brightness", style.brightness)
	background.material.set_shader_parameter("saturation", style.saturation)
	background.material.set_shader_parameter("mip_level", log(float(style.blur)) / log(2.0))

func select(value: bool) -> void:
	if selected == value:
		return
	selected = value
	if value:
		_load_art()
	group.visible = selected or opacity > 0
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if group.visible else SubViewport.UPDATE_DISABLED
	tween = preload("res://scripts/css_transition.gd").start(self, "opacity", float(value), rules.duration, tween, transition, _curve)
	if tween != null:
		tween.set_ignore_time_scale(true)

func _curve(value: float) -> float:
	var curve: Array = rules.curve
	return HurtFlashState.bezier(value, Vector2(curve[0], curve[1]), Vector2(curve[2], curve[3]))

func layout_art(view_size: Vector2) -> void:
	size = view_size
	viewport.size = Vector2i(view_size)
	content.size = view_size
	group.size = view_size
	var landscape := size.x >= size.y
	frame.size = Vector2(minf(size.y, size.x * .94), size.y) if landscape else size
	frame.position = Vector2((size.x - frame.size.x) / 2, 0)
	var inset := float(backdrop_rules.inset)
	var scale_factor := float(backdrop_rules.scale)
	var width := (float(size.x) + inset * 2) * scale_factor
	var height := (float(size.y) + inset * 2) * scale_factor
	background.size = Vector2(width, height)
	background.position = Vector2((float(size.x) - width) / 2, (float(size.y) - height) / 2)
	_apply_pose()

func set_pose(value: Dictionary) -> void:
	var target := {"scale": CssDecimal.fixed(float(value.scale), 3), "x": CssDecimal.fixed(float(value.x), 2), "y": CssDecimal.fixed(float(value.y), 2)}
	if target == pose_target:
		return
	var shortening := 1.0
	var reversing_start := pose.duplicate()
	if pose_tween != null and pose_tween.is_valid():
		if target == pose_reversing_start:
			shortening = preload("res://scripts/css_transition.gd").reversal_factor(pose_progress, pose_shortening)
			reversing_start = pose_target.duplicate()
		pose_tween.kill()
	pose_start = pose.duplicate()
	pose_target = target
	pose_reversing_start = reversing_start
	pose_shortening = shortening
	pose_progress = 0
	if pose_start == pose_target or shortening == 0:
		pose_progress = 1
		pose_tween = null
		return
	pose_tween = create_tween().set_ignore_time_scale(true)
	pose_tween.tween_property(self, "pose_progress", 1.0, float(pose_rules.duration) * shortening).set_custom_interpolator(_pose_curve)

func _pose_curve(value: float) -> float:
	var curve: Array = pose_rules.curve
	return HurtFlashState.bezier_values(value, curve[0], curve[1], curve[2], curve[3])

func _apply_pose() -> void:
	if image == null:
		return
	var inset: float = Content.campaign.presentation.art.inset
	image.size = frame.size * (1 + inset * 2)
	image.pivot_offset = image.size / 2
	image.scale = Vector2.ONE * float(pose.scale)
	image.position = Vector2(-float(frame.size.x) * inset + float(image.size.x) * float(pose.x) / 100,
		-float(frame.size.y) * inset + float(image.size.y) * float(pose.y) / 100)

func cancel() -> void:
	if tween != null and tween.is_valid():
		tween.kill()
	transition.clear()
	if pose_tween != null and pose_tween.is_valid():
		pose_tween.kill()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
