class_name StatusIcon
extends Control

var glyph: Texture2D
var background := Color.BLACK
var foreground := Color.WHITE
var plan: Dictionary = {}
var source_text: Array = []
var glyph_font := SystemFont.new()
var timer: Label
var polarity: Label
var stacks: Label

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	timer = _badge(Color.WHITE)
	polarity = _badge(Color.WHITE, false)
	stacks = _badge(Color("#ffd54f"))
	resized.connect(_layout)

func sync(item: Dictionary, definition: Dictionary, texture: Texture2D, presentation: Dictionary, diameter: float) -> void:
	plan = presentation
	glyph = texture
	background = Color(definition.bg)
	foreground = Color(definition.fg)
	source_text = definition.get("texts", [])
	custom_minimum_size = Vector2.ONE * diameter
	size = custom_minimum_size
	timer.text = plan.timer
	tooltip_text = "%s (%ss)" % [item.get("label", item.id), plan.timer]
	polarity.text = "↑" if item.positive else "↓"
	polarity.add_theme_color_override("font_color", Color("#4cde6a" if item.positive else "#ff4436"))
	stacks.text = str(item.stacks) if item.get("stacks", 0) > 1 else ""
	stacks.visible = not stacks.text.is_empty()
	_layout()
	queue_redraw()

func _badge(color: Color, panel := true) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", color)
	if panel:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0, 0, 0, .75)
		box.border_color = Color(1, 1, 1, .15)
		box.set_border_width_all(1)
		box.set_corner_radius_all(3)
		box.content_margin_left = 2
		box.content_margin_right = 2
		label.add_theme_stylebox_override("normal", box)
	add_child(label)
	return label

func _layout() -> void:
	if timer == null or not is_inside_tree():
		return
	var viewport := get_viewport_rect().size
	var vmin := minf(viewport.x, viewport.y)
	var font_size := maxi(1, roundi(maxf(viewport.y * .0072, minf(vmin * .01, viewport.x * .0072))))
	for label: Label in [timer, stacks]:
		label.add_theme_font_size_override("font_size", font_size)
		label.reset_size()
	polarity.add_theme_font_size_override("font_size", maxi(1, roundi(maxf(viewport.y * .0085, minf(vmin * .0112, viewport.x * .008)))))
	polarity.reset_size()
	timer.position = Vector2(size.x - timer.size.x + 3, -3)
	polarity.position = size - polarity.size + Vector2(3, 3)
	stacks.position = Vector2(-3, size.y - stacks.size.y + 3)

func _draw() -> void:
	if plan.is_empty():
		return
	var scale := size.x / 28.0
	var center := size * .5
	draw_circle(center, size.x * .5, background)
	draw_arc(center, size.x * .5, 0, TAU, 64, Color(1, 1, 1, .18), 1, true)
	var sweep := deg_to_rad(float(plan.degrees))
	if sweep > 0:
		var polygon := PackedVector2Array([center])
		var segments := maxi(1, ceili(sweep / (TAU / 64)))
		for index in range(segments + 1):
			var angle := -PI * .5 + sweep * index / segments
			polygon.append(center + Vector2(cos(angle), sin(angle)) * size.x * .5)
		draw_colored_polygon(polygon, Color(0, 0, 0, .52))
	if glyph != null:
		draw_texture_rect(glyph, Rect2(Vector2.ZERO, size), false)
	for item: Dictionary in source_text:
		glyph_font.font_names = PackedStringArray(item.families)
		glyph_font.font_weight = int(item.weight)
		var text_size := maxi(1, roundi(float(item.size) * scale))
		var width := glyph_font.get_string_size(item.text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
		draw_string(glyph_font, Vector2(float(item.x) * scale - width * .5, float(item.y) * scale), item.text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, Color(item.color))
	var radius := 12.2 * scale
	draw_arc(center, radius, 0, TAU, 64, Color(1, 1, 1, .18), 2 * scale, true)
	draw_line(Vector2(14, 1.8) * scale, Vector2(14, 3.8) * scale, Color(1, 1, 1, .5), 1.2 * scale, true)
	var arc := (76.65 - float(plan.dashOffset)) / 12.2
	if arc > 0:
		draw_arc(center, radius, -PI * .5, -PI * .5 + arc, 64, foreground, 2.3 * scale, true)
		draw_circle(center + Vector2(0, -radius), 1.15 * scale, foreground)
		draw_circle(center + Vector2(sin(arc), -cos(arc)) * radius, 1.15 * scale, foreground)
	if plan.showTip:
		draw_circle(Vector2(plan.tipX, plan.tipY) * scale, 1.4 * scale, Color.WHITE)
