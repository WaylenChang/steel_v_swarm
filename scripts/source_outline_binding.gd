class_name SourceOutlineBinding
extends Node3D

var bindings: Array[Dictionary] = []

static func install(root: Node3D) -> bool:
	if Session.dedicated:
		return true
	if root.has_meta("source_outline_binding") and is_instance_valid(root.get_meta("source_outline_binding")):
		return true
	var nodes: Array[Node] = root.find_children("*", "GeometryInstance3D", true, false)
	if root is GeometryInstance3D:
		nodes.push_front(root)
	var has_shells := false
	for node: GeometryInstance3D in nodes:
		if node.get_meta("isOutline", false) or not node.get_meta("source_outline_shells", []).is_empty():
			has_shells = true
			break
	if not has_shells:
		return true
	if not Content.balance.has("outline"):
		push_error("Missing original outline rules; regenerate source content")
		return false
	var binding := SourceOutlineBinding.new()
	binding.name = "native_outline_binding"
	binding.set_meta("source_outline_helper", true)
	root.add_child(binding)
	if not binding._mount(nodes):
		binding.queue_free()
		return false
	root.set_meta("source_outline_binding", binding)
	return true

static func set_layers(node: VisualInstance3D, mask: int) -> void:
	node.layers = mask
	if node is GeometryInstance3D:
		var material: Material = node.material_override
		if material is ShaderMaterial and material.get_meta("source_outline", false):
			material.set_shader_parameter("source_layers", mask)

func _enter_tree() -> void:
	if not Visuals.changed.is_connected(_refresh):
		Visuals.changed.connect(_refresh)
	_refresh()

func _exit_tree() -> void:
	if Visuals.changed.is_connected(_refresh):
		Visuals.changed.disconnect(_refresh)

func _mount(nodes: Array[Node]) -> bool:
	for node: GeometryInstance3D in nodes:
		if node.get_meta("isOutline", false) and not node.has_meta("source_outline_uniforms"):
			push_error("Missing original outline vertex uniforms; repack source models")
			return false
	for node: GeometryInstance3D in nodes:
		if node.get_meta("isOutline", false):
			_bind(node, node.get_meta("source_outline_uniforms"), not node.get_meta("source_outline_frustum_culled", false))
		for spec: Dictionary in node.get_meta("source_outline_shells", []):
			var shell := MeshInstance3D.new()
			shell.name = "native_outline_shell"
			shell.set_meta("source_outline_helper", true)
			shell.set_meta("isOutline", true)
			shell.set_meta("geoKeep", bool(spec.get("geo_keep", false)))
			shell.mesh = spec.geometry
			var m: Array = spec.matrix
			shell.transform = Transform3D(Basis(Vector3(m[0], m[1], m[2]), Vector3(m[4], m[5], m[6]), Vector3(m[8], m[9], m[10])), Vector3(m[12], m[13], m[14]))
			shell.visible = spec.visible
			shell.layers = node.layers
			node.add_child(shell)
			if spec.has("child_index"):
				node.move_child(shell, int(spec.child_index))
			_bind(shell, spec.uniforms, not spec.frustum_culled)
	_refresh()
	return true

func _bind(node: GeometryInstance3D, uniforms: Dictionary, ignore_culling: bool) -> void:
	var original := ViewOcclusion._material(node, 0)
	var material := SourceOutlineMaterial.create(uniforms, Content.balance.outline, Content.local_view_curve())
	material.set_meta("source_original_material", original)
	if original != null and original.has_meta("source_material_id"):
		material.set_meta("source_material_id", original.get_meta("source_material_id"))
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bindings.append({"node": node, "material": material, "ignore_culling": ignore_culling})
	set_layers(node, node.layers)

func _refresh(_snapshot: Dictionary = {}) -> void:
	for binding: Dictionary in bindings:
		var node: GeometryInstance3D = binding.node
		if not is_instance_valid(node):
			continue
		SourceOutlineMaterial.sync_visuals(binding.material, Visuals, Content.balance.outline)
		var current := node.material_override as ShaderMaterial
		if current != null and current != binding.material and current.get_meta("source_outline", false):
			SourceOutlineMaterial.sync_visuals(current, Visuals, Content.balance.outline)
		if node.is_inside_tree():
			# This native flag also bypasses layers; the outline shader retains them.
			RenderingServer.instance_set_ignore_culling(node.get_instance(), binding.ignore_culling)
