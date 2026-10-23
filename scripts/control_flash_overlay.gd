class_name ControlFlashOverlay
extends ColorRect

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rules: Dictionary = Content.balance.controls.controlEffects
	z_index = int(rules.layer)
	color = Color(str(rules.color))
	set_opacity(0)

func set_opacity(value: float) -> void:
	var alpha := CssDecimal.fixed(clampf(0 if is_nan(value) else value, 0, 1), 3)
	self_modulate.a = alpha
	visible = alpha > 0
