class_name NativeUi
extends RefCounted

static func safe_area(control: Control) -> Rect2:
	var bounds := Rect2(Vector2.ZERO, control.size)
	if OS.get_name() not in ["Android", "iOS"] or not control.is_inside_tree():
		return bounds
	var area := control.get_screen_transform().affine_inverse() * Rect2(DisplayServer.get_display_safe_area())
	var visible := bounds.intersection(area)
	return visible if visible.has_area() else bounds

static func panel(dimensions: Vector2) -> PanelContainer:
	var result := PanelContainer.new()
	result.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	result.position = -dimensions / 2
	result.size = dimensions
	var style := StyleBoxFlat.new()
	style.bg_color = Color("162736")
	style.border_color = Color("4a7185")
	style.set_border_width_all(1)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	result.add_theme_stylebox_override("panel", style)
	return result

static func label(value: String, font_size: int = 18) -> Label:
	var result := Label.new()
	result.text = value
	result.add_theme_font_size_override("font_size", font_size)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

static func button(value: String, callback: Callable) -> Button:
	var result := Button.new()
	result.text = value
	result.custom_minimum_size.y = 40
	result.pressed.connect(callback)
	return result

static func row(parent: VBoxContainer, key: String, control: Control) -> void:
	var result := HBoxContainer.new()
	var caption := label(Content.label(key))
	caption.custom_minimum_size.x = 210
	result.add_child(caption)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.add_child(control)
	parent.add_child(result)

static func prose(value: String, font_size: int = 18) -> RichTextLabel:
	var result := RichTextLabel.new()
	result.text = value
	result.bbcode_enabled = false
	result.fit_content = true
	result.scroll_active = false
	result.add_theme_font_size_override("normal_font_size", font_size)
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return result
