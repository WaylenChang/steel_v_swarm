extends "res://tests/run.gd"

func _run() -> void:
	var capture: Dictionary = Content.read_json("res://tests/fixtures/pip.json")
	_check(capture.get("formatVersion") == 1 and capture.get("source") is Dictionary and capture.get("pipFrames") is Array,
		"Capture original PiP selection and render methods")
	if not failures.is_empty():
		_finish_pip()
		return
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	for path: String in capture.source.inputs:
		var text := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(text.sha256_text() == capture.source.inputs[path], "PiP capture generator is current: " + path)
	for path: String in capture.source.sourceInputs:
		_check(provenance.get("inputs", {}).get(path) == capture.source.sourceInputs[path], "PiP oracle matches imported source: " + path)
	_check(Content.balance.get("pip") == capture.rules, "Native PiP configuration matches the captured original rules")
	if failures.is_empty():
		preload("res://tests/pip_suite.gd").run(self, capture)
		_lifecycle()
		await _render_isolation(capture.pipFrames[0])
	_finish_pip()

func _lifecycle() -> void:
	var host := Control.new()
	add_child(host)
	var view := PipView.new()
	host.add_child(view)
	view._add_view()
	var slot: Dictionary = view.views[0]
	var world := World3D.new()
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	add_child(mesh)
	var original := mesh.layers
	for action: String in ["self_hide", "parent_hide", "detach", "retire"]:
		view.show()
		host.show()
		slot.border.show()
		slot.viewport.world_3d = world
		slot.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		view.pending_tags = [{"root": mesh, "mask": PipView.SOURCE_MASKS[0]}]
		view._begin_frame()
		_check(mesh.layers == PipView.SOURCE_MASKS[0], "Apply source exclusion only during the active render pass")
		match action:
			"self_hide": view.hide()
			"parent_hide": host.hide()
			"detach", "retire": host.remove_child(view)
		_check(slot.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and slot.viewport.world_3d == null and not slot.border.visible,
			"Inactive PiP stops rendering and releases its shared world: " + action)
		_check(view.pending_tags.is_empty() and view.layers.is_empty() and mesh.layers == original,
			"Inactive PiP clears pending source ownership and restores layers immediately: " + action)
		if action == "detach":
			host.add_child(view)
			_check(slot.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and view.pending_tags.is_empty(),
				"Reattachment requires a new accepted view update before rendering resumes")
	view.free()
	host.free()
	mesh.free()

func _render_isolation(frame: Dictionary) -> void:
	_check(DisplayServer.get_name() != "headless", "PiP isolation requires actual rendered frames")
	if DisplayServer.get_name() == "headless":
		return
	# Simple primary-color probes test visibility only, without substituting actor geometry.
	var main := SubViewport.new()
	main.size = Vector2i(128, 96)
	main.world_3d = World3D.new()
	main.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(main)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLACK
	main.add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6
	camera.position.z = 8
	main.add_child(camera)
	camera.current = true
	var meshes: Array[MeshInstance3D] = []
	for index in range(3):
		var mesh := MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		mesh.position = Vector3([-1.6, 1.6, 0][index], 0, 0)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = [Color.RED, Color.GREEN, Color.BLUE][index]
		mesh.material_override = material
		main.add_child(mesh)
		meshes.append(mesh)
	var view := PipView.new()
	add_child(view)
	for index in range(2):
		view._add_view()
		var slot: Dictionary = view.views[index]
		slot.viewport.size = main.size
		slot.viewport.world_3d = main.world_3d
		slot.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		slot.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		slot.camera.size = camera.size
		slot.camera.position = camera.position
		slot.camera.cull_mask = PipView.ALL_LAYERS & ~PipView.COCKPIT_MASK & ~PipView.SOURCE_MASKS[index]
		view.pending_tags.append({"root": meshes[index], "mask": PipView.SOURCE_MASKS[index]})
	view.pending_tags.append({"root": meshes[2], "mask": PipView.COCKPIT_MASK})
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var output := "res://build/pip_native"
	_check(DirAccess.make_dir_recursive_absolute(output) == OK, "Create native PiP pixel evidence directory")
	var main_image := main.get_texture().get_image()
	_check(main_image.save_png(output + "/main.png") == OK, "Retain the actual main-camera render")
	var main_counts := _colors(main_image)
	print("PIP_PIXELS main=", main_counts)
	_check(main_counts.all(func(count): return count > 0), "Main camera retains both PiP sources and the cockpit during rendering")
	for index in range(2):
		var image: Image = view.views[index].viewport.get_texture().get_image()
		_check(image.save_png(output + "/pip_%d.png" % index) == OK, "Retain the actual PiP render")
		var counts := _colors(image)
		print("PIP_PIXELS slot=", index, " counts=", counts)
		var expected: Dictionary = frame.draws[index]
		for source in range(2):
			var visible: bool = not expected.hidden.has(frame.selected[source].id)
			_check((counts[source] > 0) == visible, "Actual PiP pixels hide only their own source and retain the other camera's source")
		_check((counts[2] > 0) == bool(expected.cockpit), "Actual PiP pixels exclude the cockpit as in the original render pass")
	_check(view.layers.is_empty() and meshes.all(func(mesh): return mesh.layers == 1),
		"Completed native render frames restore source layers before gameplay can copy a body")
	view.free()
	main.free()

func _colors(image: Image) -> Array:
	var counts := [0, 0, 0]
	_check(image != null and not image.is_empty(), "Native shared-world viewport produces readable pixels")
	if image == null or image.is_empty():
		return counts
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if color.r > .8 and color.g < .2 and color.b < .2:
				counts[0] += 1
			elif color.g > .8 and color.r < .2 and color.b < .2:
				counts[1] += 1
			elif color.b > .8 and color.r < .2 and color.g < .2:
				counts[2] += 1
	return counts

func _finish_pip() -> void:
	print("PIP_NATIVE assertions=", assertions, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
