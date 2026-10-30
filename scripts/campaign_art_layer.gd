class_name CampaignArtLayer
extends Control

var group: TextureRect
var viewport: SubViewport
var content: Control
var background: TextureRect
var frame: Control
var foreground_clip: Control
var fallback_image: TextureRect
var image: TextureRect
var frame_edges: Array[ColorRect] = []
var scene: Dictionary = {}
var selected := false
var loaded := false
var texture_provider := Callable()
var rules: Dictionary
var backdrop_rules: Dictionary
var frame_rules: Dictionary
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
	frame_rules = Content.read_json("res://data/campaign_frame_geometry.json").rules
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
	foreground_clip = Control.new()
	foreground_clip.clip_contents = true
	foreground_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(foreground_clip)
	fallback_image = _image()
	foreground_clip.add_child(fallback_image)
	image = _image()
	foreground_clip.add_child(image)
	var edge_color: Array = frame_rules.borderColor
	for index in range(2):
		var edge := ColorRect.new()
		edge.color = Color(edge_color[0], edge_color[1], edge_color[2], edge_color[3])
		edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(edge)
		frame_edges.append(edge)
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
	var primary_path: String = scene.img
	var fallback_path: String = scene.get("fallbackImg", "")
	image.texture = _texture(primary_path)
	fallback_image.texture = _texture(fallback_path) if not fallback_path.is_empty() else null
	var backdrop_path := primary_path if image.texture != null else fallback_path if fallback_image.texture != null else ""
	background.texture = _texture(backdrop_path, true) if not backdrop_path.is_empty() else null
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
	var landscape := size.x > size.y
	var units := float(frame_rules.layoutUnits)
	var border := float(frame_rules.borderWidth) if landscape else 0.0
	var frame_width := float(size.x)
	if landscape:
		frame_width = maxf(border * 2, minf(float(size.y), floorf(float(size.x) * float(frame_rules.maxWidthRatio) * units) / units))
	frame.size = Vector2(frame_width, size.y)
	frame.position = Vector2((float(size.x) - frame_width) / 2, 0)
	foreground_clip.position = Vector2(border, 0)
	foreground_clip.size = Vector2(maxf(0, frame_width - border * 2), size.y)
	for index in frame_edges.size():
		var edge := frame_edges[index]
		edge.visible = landscape
		edge.position = Vector2(0 if index == 0 else frame_width - border, 0)
		edge.size = Vector2(border, size.y)
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
	var inset := float(frame_rules.inset)
	var units := float(frame_rules.layoutUnits)
	var inset_x := floorf(float(foreground_clip.size.x) * inset * units) / units
	var inset_y := floorf(float(foreground_clip.size.y) * inset * units) / units
	for target: TextureRect in [fallback_image, image]:
		target.size = Vector2(float(foreground_clip.size.x) + inset_x * 2, float(foreground_clip.size.y) + inset_y * 2)
		target.pivot_offset = target.size / 2
		target.scale = Vector2.ONE * float(pose.scale)
		target.position = Vector2(-inset_x + float(target.size.x) * float(pose.x) / 100,
			-inset_y + float(target.size.y) * float(pose.y) / 100)

func cancel() -> void:
	if tween != null and tween.is_valid():
		tween.kill()
	transition.clear()
	if pose_tween != null and pose_tween.is_valid():
		pose_tween.kill()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
