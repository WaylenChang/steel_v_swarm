class_name MinimapLanes
extends Node2D

var groups: Array = []
var lines: Array[Line2D] = []
var images := SourceTextureImages.new()
var textures: Dictionary = {}

func clear() -> void:
	for line: Line2D in lines:
		line.free()
	lines.clear()
	groups.clear()
	textures.clear()
	images.images.clear()
	images.variants.clear()

func configure(source: Array) -> bool:
	clear()
	var rules: Dictionary = Content.balance.minimap.lanes
	var context: Dictionary = Content.balance.minimap.context
	if not images.configure(rules.images) or context.lineJoin != "miter" or context.lineCap != "butt":
		push_error("Missing original minimap dash texture or supported canvas stroke context")
		return false
	for grade: String in rules.styles:
		var image: Variant = rules.styles[grade].image
		if image != null:
			textures[grade] = ImageTexture.create_from_image(images.images[int(image)])
	groups = source
	var palette: Array = Content.constants.LANE_COLORS
	for group: Dictionary in groups:
		var style: Dictionary = rules.styles[group.grade]
		var line := Line2D.new()
		line.width = float(style.width)
		line.default_color = Color.hex((int(palette[posmod(int(group.lane), palette.size())]) << 8) | 0xff)
		line.default_color.a = float(style.alpha)
		line.sharp_limit = float(context.miterLimit)
		line.antialiased = true
		if textures.has(group.grade):
			line.texture = textures[group.grade]
			line.texture_mode = Line2D.LINE_TEXTURE_TILE
			line.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
			line.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(line)
		lines.append(line)
	return true

func update_window(window: Rect2, canvas_size: Vector2) -> void:
	for index in groups.size():
		var points := PackedVector2Array()
		for point: Array in groups[index].points:
			points.append(MinimapWindow.project(Vector2(point[0], point[1]), window, canvas_size))
		lines[index].points = points
