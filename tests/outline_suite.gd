extends RefCounted

const Helper = preload("res://tests/status_suite.gd")
const Preferences = preload("res://tests/visual_suite.gd")

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("outlineUniforms") or not fixtures.has("outlineWidths") or not Content.balance.has("outline"):
		h._check(false, "Regenerate original inverted-hull outline material and camera-width references")
		return
	var rules: Dictionary = Content.balance.outline
	if not fixtures.has("outlineUnitWidths"):
		h._check(false, "Regenerate original unit-height outline width references")
		return
	for item: Dictionary in fixtures.outlineUnitWidths:
		h._near(OutlineRules.unit_width(item.target, rules), item.result, "Original unit outline width retains both source clamps")
	for item: Dictionary in fixtures.outlineUniforms:
		var values: Array = item.basis
		var basis := Basis(Vector3(values[0], values[1], values[2]), Vector3(values[3], values[4], values[5]), Vector3(values[6], values[7], values[8]))
		Helper.compare(h, OutlineRules.local_uniforms(basis, item.width, rules), item.result,
			"Original outline width and both viewport limits use one shared world-scale measurement, including mirrors, shear and zero scale")
	for item: Dictionary in fixtures.outlineWidths:
		Helper.compare(h, OutlineRules.displacement(item.uniforms, item.depth, item.projection, item.style, rules), item.result,
			"Original vertex shell offsets clamp bind-pose depth and projection before style scaling")
	var material := SourceOutlineMaterial.create(fixtures.outlineUniforms[0].result, rules, Content.balance.bodyRules.curve)
	for program: Dictionary in fixtures.marineVisualPrograms:
		var preferences := VisualPreferences.new()
		preferences.configure(Content.balance.visual)
		for frame: Dictionary in program.frames:
			if not frame.has("outline"):
				h._check(false, "Regenerate original shared outline style and ink-color transactions")
				continue
			Preferences._apply(preferences, frame.call)
			SourceOutlineMaterial.sync_visuals(material, preferences, rules)
			h._near(float(material.get_shader_parameter("style_scale")), frame.outline.scale,
				"Original live visual presets scale outline shells, including zero-width realistic rendering")
			var color: Color = material.get_shader_parameter("ink_color")
			color = color.srgb_to_linear()
			Helper.compare(h, [color.r, color.g, color.b], frame.outline.ink,
				"Native source-color shader input preserves the original linear ink color")
		preferences.free()
	_binding(h, fixtures.outlineUniforms[0].result)

static func check_deferred(h: Node, root: Node3D) -> void:
	var nodes: Array[Node] = root.find_children("*", "GeometryInstance3D", true, false)
	if root is GeometryInstance3D:
		nodes.push_front(root)
	for node: GeometryInstance3D in nodes:
		if not node.has_meta("source_outline_shells"):
			continue
		var specs: Array = node.get_meta("source_outline_shells")
		var shells: Array = node.get_children().filter(func(child):
			return child.get_meta("source_outline_helper", false) and child.get_meta("isOutline", false))
		h._check(shells.size() == specs.size(), "Prefab factories mount exactly the source-authored shell roster")
		for index in range(mini(shells.size(), specs.size())):
			var shell := shells[index] as MeshInstance3D
			var spec: Dictionary = specs[index]
			h._check(shell.mesh == spec.geometry and shell.get_index() == int(spec.child_index),
				"Prefab shells retain selected source geometry and child order")
			h._check(shell.transform.is_equal_approx(CockpitSuite.matrix(spec.matrix)), "Prefab shell transform follows the authored parent")
			var material := shell.material_override as ShaderMaterial
			h._check(material != null, "Prefab shells use the native outline shader")
			if material != null:
				Helper.compare(h, {"width": material.get_shader_parameter("local_width"),
					"minimum": material.get_shader_parameter("minimum_width"), "maximum": material.get_shader_parameter("maximum_width")},
					spec.uniforms, "Prefab factories preserve captured local outline expansion uniforms")

static func _binding(h: Node, uniforms: Dictionary) -> void:
	var empty := MeshInstance3D.new()
	empty.mesh = BoxMesh.new()
	h._check(SourceOutlineBinding.install(empty) and empty.get_child_count() == 0 and not empty.has_meta("source_outline_binding"),
		"Models without authored shells need no outline node or visual-preference subscription")
	empty.free()
	var root := Node3D.new()
	root.name = "n_0"
	h.add_child(root)
	var parent := MeshInstance3D.new()
	parent.name = "n_1"
	parent.mesh = BoxMesh.new()
	root.add_child(parent)
	parent.set_meta("source_outline_shells", [{"geometry": BoxMesh.new(), "uniforms": uniforms,
		"matrix": [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1], "visible": true, "frustum_culled": false, "child_index": 0}])
	var retained := MeshInstance3D.new()
	retained.name = "n_2"
	retained.mesh = BoxMesh.new()
	retained.set_meta("isOutline", true)
	retained.set_meta("source_outline_uniforms", uniforms)
	var base := StandardMaterial3D.new()
	retained.material_override = base
	parent.add_child(retained)
	h._check(SourceOutlineBinding.install(root), "Native binding accepts retained and deferred source outline shells")
	var binding: SourceOutlineBinding = root.get_meta("source_outline_binding")
	h._check(parent.get_child(0).get_meta("source_outline_helper", false) and parent.get_child(1) == retained,
		"Deferred shells restore original child order before damage geometry traverses the model")
	h._check(binding.bindings.size() == 2, "Each captured shell has one native material binding")
	h._check(SourceOutlineBinding.install(root) and binding.bindings.size() == 2, "Repeated rig setup cannot duplicate outline shells or subscriptions")
	var rig := BodyRig.new()
	rig._collect(root)
	h._check(rig.nodes.size() == 3 and rig.nodes[0] == root and rig.nodes[2] == retained,
		"Native helper and deferred shells cannot overwrite authored source rig IDs")
	rig.free()
	var material := retained.material_override as ShaderMaterial
	h._check(material != null and material.get_meta("source_original_material") == base,
		"Outline rendering preserves the original material referenced by source rig state")
	SourceOutlineBinding.set_layers(retained, PipView.COCKPIT_MASK)
	h._check(retained.layers == PipView.COCKPIT_MASK and int(material.get_shader_parameter("source_layers")) == PipView.COCKPIT_MASK,
		"Native camera-layer changes also update outlines whose frustum culling is disabled")
	var occlusion := ViewOcclusion.new()
	occlusion._fade_one(retained, 1)
	occlusion.previous = 1
	occlusion.advance(1.05)
	var faded := retained.material_override as ShaderMaterial
	h._check(faded != material and float(faded.get_shader_parameter("source_opacity")) < 1,
		"Existing camera occlusion fades the outline shader together with its parent")
	SourceOutlineBinding.set_layers(retained, 1)
	var opacity := float(faded.get_shader_parameter("source_opacity"))
	Visuals.changed.emit(Visuals.snapshot())
	h._check(float(faded.get_shader_parameter("source_opacity")) == opacity and int(faded.get_shader_parameter("source_layers")) == 1,
		"Live style updates preserve current outline fade and per-camera layer state")
	occlusion.clear()
	h._check(retained.material_override == material and material.get_meta("source_original_material") == base,
		"Occlusion restoration returns the bound shader without changing source materials")
	var dissolve := DissolveBinding.new()
	dissolve.set_progress(root, .5)
	h._check(not retained.visible, "Dissolve uses the existing outline flag to hide the complete shell")
	dissolve.set_progress(root, 1)
	h._check(retained.visible, "Dissolve completion restores the native outline shell")
	root.free()
