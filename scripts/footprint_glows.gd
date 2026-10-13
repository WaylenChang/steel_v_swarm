class_name FootprintGlows
extends Node3D

var active: Dictionary = {}
var pool: Array[MeshInstance3D] = []
var quad: QuadMesh
var normal: StandardMaterial3D
var warning: StandardMaterial3D
var material_side := ""

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.no_depth_test = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = load("res://assets/ui/footprint-glow.png")
	material.albedo_color = color
	return material

func _prepare(side: String) -> void:
	if quad == null:
		quad = QuadMesh.new()
		quad.size = Vector2.ONE
	if material_side == side:
		return
	var style: Dictionary = Content.balance.footprintGlow
	var color := Color(Content.constants.SIDES[side].color)
	color.a = style.opacity
	normal = _material(color)
	color = Color.hex((int(style.warningColor) << 8) | 0xff)
	color.a = style.warningOpacity
	warning = _material(color)
	material_side = side

func _drop(id: int) -> void:
	var glow: Variant = active[id]
	active.erase(id)
	if not is_instance_valid(glow) or glow.is_queued_for_deletion():
		return
	glow.visible = false
	glow.reparent(self, false)
	pool.append(glow)

func apply(units: Dictionary, footprint: Dictionary, anchor: int) -> void:
	var lit := {}
	for value in footprint.get("hits", []):
		var id := int(value)
		var unit: BattleUnit = units.get(id)
		if id == anchor or unit == null or not unit.alive() or not unit.presentation_visible:
			continue
		if not unit.visual_dimensions().is_empty():
			lit[id] = unit
	for id: int in active.keys():
		if not lit.has(id):
			_drop(id)
	if lit.is_empty():
		return
	_prepare(footprint.side)
	var style: Dictionary = Content.balance.footprintGlow
	for id: int in lit:
		var unit: BattleUnit = lit[id]
		var cached: Variant = active.get(id)
		var glow: MeshInstance3D = cached if is_instance_valid(cached) else null
		if glow == null:
			glow = pool.pop_back() if not pool.is_empty() else MeshInstance3D.new()
			glow.mesh = quad
			glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if glow.get_parent() == null:
				unit.add_child(glow)
			else:
				glow.reparent(unit, false)
			active[id] = glow
		var dimensions := unit.visual_dimensions()
		var size: float = maxf(style.minimumSize, maxf(dimensions.height, dimensions.radius * 2) * style.sizeFactor)
		glow.position = Vector3.UP * dimensions.centre
		glow.scale = Vector3.ONE * size
		glow.material_override = warning if footprint.warn else normal
		glow.visible = true
