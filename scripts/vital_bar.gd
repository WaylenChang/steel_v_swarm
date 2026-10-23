class_name VitalBar
extends Node3D

var group: Node3D
var nodes: Array[MeshInstance3D] = []
var materials: Array[StandardMaterial3D] = []
var template: Dictionary = {}

static func available() -> bool:
	return not Content.balance.get("vitalBars", {}).get("templates", {}).is_empty()

func sync(values: Dictionary) -> void:
	if values["self"] or not available():
		return
	var rules: Dictionary = Content.balance.vitalBars
	var scene: bool = values.neutral and not values.civilian
	if scene and (values.collapsed or not Content.balance.destruction.sceneProfiles.has(values.kind)):
		return
	if not scene and float(values.maximum) <= 0:
		return
	var fraction := maxf(0, float(values.hp) / float(values.maximum)) if float(values.maximum) > 0 else 1.0
	var shield := maxf(0, float(values.shield) / float(values.max_shield)) if float(values.max_shield) > 0 else 0.0
	if scene and fraction >= 1:
		clear_bar()
		return
	if group == null:
		if not scene and fraction >= 1 and (float(values.max_shield) <= 0 or shield >= 1):
			return
		var key := "scene" if scene else ("boss" if values.segment != null else "regular") + "_%d_%d" % [int(values["static"]), int(float(values.max_shield) > 0)]
		_create(rules.templates[key], (float(values.collider_height) if values.collider_height else float(rules.sceneDefault)) if scene else float(values.top))
	if scene:
		_fill(int(template.sceneFill), fraction)
		return
	if values.segment != null:
		var palette: Array = Content.constants.BOSS.GLOW
		var colour := Color(palette[clampi(int(values.segment), 0, palette.size() - 1)])
		for index: int in [int(template.glow), int(template.frame)]:
			if index >= 0:
				materials[index].albedo_color = Color(colour, materials[index].albedo_color.a)
		for index in template.fills.size():
			_fill(int(template.fills[index]), SiegeRules.segment_fraction(fraction, index))
	else:
		var fill := int(template.fills[0])
		var friendly: bool = not String(values.side).is_empty() and not String(values.viewer).is_empty() and values.side == values.viewer
		materials[fill].albedo_color = Color(rules.ally if friendly else rules.foe)
		_fill(fill, fraction)
	if int(template.shield) >= 0:
		_fill(int(template.shield), shield)
		nodes[int(template.shield)].visible = shield > 0

func _create(plan: Dictionary, top: float) -> void:
	template = plan
	group = Node3D.new()
	group.set_meta("source_vital_bar", true)
	group.position.y = top + float(plan.offset)
	add_child(group)
	for part: Dictionary in plan.nodes:
		var quad := QuadMesh.new()
		quad.size = Vector2(part.size[0], part.size[1])
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		material.no_depth_test = true
		material.cull_mode = BaseMaterial3D.CULL_BACK
		material.albedo_color = Color(Color(part.colour), part.opacity)
		material.render_priority = HeadMarks.render_priority(int(part.order))
		var node := MeshInstance3D.new()
		node.mesh = quad
		node.material_override = material
		node.position = Vector3(part.position[0], part.position[1], part.position[2])
		node.scale = Vector3(part.scale[0], part.scale[1], part.scale[2])
		node.visible = part.visible
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		group.add_child(node)
		nodes.append(node)
		materials.append(material)

func _fill(index: int, fraction: float) -> void:
	nodes[index].scale.x = maxf(float(Content.balance.vitalBars.minimum), fraction)
	nodes[index].position.x = -(1 - fraction) * float(template.width) / 2

func pose(camera: Vector3) -> void:
	if group == null:
		return
	var direction := camera - group.global_position
	var facing := SceneryTrainMotion._looking_at(direction, float(Content.balance.vitalBars.parallelPerturbation))
	group.basis = global_basis.orthonormalized().inverse() * facing

func hide_bar() -> void:
	if group != null:
		group.hide()

func clear_bar() -> void:
	if is_instance_valid(group):
		group.free()
	group = null
	nodes.clear()
	materials.clear()
	template = {}
