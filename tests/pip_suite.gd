extends RefCounted

const Helper = preload("res://tests/status_suite.gd")

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("pipSources") or not fixtures.has("pipFrames") or not Content.balance.has("pip"):
		h._check(false, "Regenerate original PiP source selection and camera/render references")
		return
	var rules: Dictionary = Content.balance.pip
	for item: Dictionary in fixtures.pipSources:
		var selected := PipViewState.sources(item.rows, 17, item.drone, item.dead, item.side, item.low, item.scale, rules)
		Helper.compare(h, selected.map(func(row): return row.id), item.ids, "Original PiP owner, drone/decoy, dead/lost, stable squad order and low-power/resolution limits")
	for item: Dictionary in fixtures.pipFrames:
		for index in item.selected.size():
			var row: Dictionary = item.selected[index]
			var position := Vector3(row.position[0], row.position[1], row.position[2])
			var plan := PipViewState.frame(Vector2(item.size[0], item.size[1]), index, position, row.yaw, row.decoy, rules)
			var expected: Dictionary = item.draws[index]
			var rect: Rect2 = plan.rect
			Helper.compare(h, [rect.position.x, rect.position.y, rect.size.x, rect.size.y], expected.rect, "Original CSS-size PiP rounding, cap, padding and vertical stacking")
			Helper.compare(h, [plan.position.x, plan.position.y, plan.position.z], expected.position, "Original PiP camera comes from the presented model with source eye offset")
			h._near(plan.yaw, expected.yaw, "Original PiP camera uses reported yaw without body-facing half turn")
			h._near(plan.fov, expected.fov, "Original PiP vertical FOV")
			h._check(not expected.cockpit and expected.hidden.has(row.id) and item.restored, "Original render hides the cockpit/source only inside its PiP pass and restores renderer state")
	_layer_isolation(h)

static func _layer_isolation(h: Node) -> void:
	var view := PipView.new()
	h.add_child(view)
	var roots: Array[Node3D] = []
	var meshes: Array[MeshInstance3D] = []
	for index in 3:
		var root := Node3D.new()
		h.add_child(root)
		var mesh := MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		mesh.layers = 1 | (1 << (index + 2))
		root.add_child(mesh)
		roots.append(root)
		meshes.append(mesh)
	var original := meshes.map(func(mesh): return mesh.layers)
	var retained := {}
	view._tag(roots[0], PipView.COCKPIT_MASK, retained)
	view._tag(roots[1], PipView.SOURCE_MASKS[0], retained)
	view._tag(roots[2], PipView.SOURCE_MASKS[1], retained)
	for index in 2:
		var mask: int = PipView.ALL_LAYERS & ~PipView.COCKPIT_MASK & ~PipView.SOURCE_MASKS[index]
		h._check((mask & meshes[0].layers) == 0 and (mask & meshes[index + 1].layers) == 0 and (mask & meshes[2 - index].layers) != 0,
			"Native camera layers exclude its own source/cockpit while retaining the other PiP source")
		view._add_view()
		h._check(view.views[index].camera.keep_aspect == Camera3D.KEEP_HEIGHT, "Native camera keeps the source vertical-FOV projection")
	view.clear()
	for index in 3:
		h._check(meshes[index].layers == original[index] and meshes[index].visible, "PiP release restores each original mask without mutating global body visibility")
	for slot: Dictionary in view.views:
		h._check(slot.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and not slot.border.visible and slot.viewport.world_3d == null,
			"Inactive PiP slots stop rendering and release their shared-world binding")
	view.pending_tags = [{"root": roots[1], "mask": PipView.SOURCE_MASKS[0]}]
	view._begin_frame()
	h._check(meshes[1].layers == PipView.SOURCE_MASKS[0], "Temporary source-body layers apply only at the native rendering boundary")
	view._end_frame()
	var retired_copy: MeshInstance3D = meshes[1].duplicate()
	h._check(retired_copy.layers == original[1] and meshes[1].layers == original[1], "Body/effect copies outside rendering cannot inherit a PiP exclusion mask")
	retired_copy.free()
	view.free()
	for root: Node3D in roots:
		root.free()
