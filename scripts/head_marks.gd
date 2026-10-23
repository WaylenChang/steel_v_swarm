class_name HeadMarks
extends Node3D

static var images := SourceTextureImages.new()
static var prepared := false
static var meshes: Dictionary = {}
var marks: Dictionary = {}

static func available() -> bool:
	var data: Dictionary = Content.balance.get("headMarks", {})
	return not data.get("images", []).is_empty() and not data.get("textures", {}).is_empty() and data.get("rules", {}).size() == 3

static func render_priority(source_order: int) -> int:
	var highest: int = Content.balance.headMarks.rules.values().map(func(profile): return int(profile.order)).max()
	return 127 + source_order - highest

static func _mesh(key: String) -> ArrayMesh:
	if meshes.has(key):
		return meshes[key]
	var spec: Dictionary = Content.balance.headMarks.textures[key]
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var arrays := quad.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv := PackedVector2Array()
	for point: Vector3 in points:
		uv.append(SourceTextureImages.coordinates(Vector2(point.x + 0.5, point.y + 0.5), spec))
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	meshes[key] = result
	return result

func advance(unit: BattleUnit, viewer_side: String, delta: float, now: float) -> void:
	var civilian: bool = unit.special.get("role") == "civilian"
	var kind := ""
	if civilian:
		kind = "civilian"
	elif not viewer_side.is_empty() and not unit.side.is_empty():
		if viewer_side != unit.side:
			kind = "enemy"
		elif not (unit.is_pilot() and unit.peer_id == Session.player_id()):
			kind = "ally"
	if kind.is_empty() or not available():
		return
	var side: String = unit.special.get("civil_side", "") if civilian else unit.side
	var key := ("ally:" if kind == "ally" else "enemy:") + side
	if not Content.balance.headMarks.textures.has(key):
		return
	if not prepared:
		prepared = images.configure(Content.balance.headMarks.images)
		if not prepared:
			return
	var rules: Dictionary = Content.balance.headMarks.rules[kind]
	if not marks.has(kind):
		var dimensions := unit.visual_dimensions()
		if dimensions.is_empty():
			return
		var state := HeadMarkState.new()
		state.configure(float(dimensions.height), dimensions.get("top"), rules)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		material.no_depth_test = true
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.billboard_keep_scale = true
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.render_priority = render_priority(int(rules.order))
		var spec: Dictionary = Content.balance.headMarks.textures[key]
		material.albedo_texture = images.resolve(spec)
		if material.albedo_texture == null or not SourceTextureImages.apply_sampling(material, spec):
			return
		var mark := MeshInstance3D.new()
		mark.set_meta("source_sprite", true)
		mark.mesh = _mesh(key)
		mark.material_override = material
		mark.scale = Vector3.ONE * state.size
		mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mark)
		marks[kind] = {"state": state, "node": mark, "material": material}
	var current: Dictionary = marks[kind]
	current.state.advance(delta, now, bool(unit.special.get("following", unit.special.get("follow_peer", 0) != 0)), rules)
	current.node.position.y = current.state.y
	current.material.albedo_color = Color(1, 1, 1, current.state.opacity)
