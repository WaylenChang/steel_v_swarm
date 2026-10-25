extends "res://tests/run.gd"

var rules: Dictionary
var held: Array[MarinePresentation] = []
var children: Array[MarineShaderBinding] = []
var resources: Array[WeakRef] = []

func _source() -> Dictionary:
	return {"wind": rules, "appearance": {"school": "a", "tintMaximum": 1,
		"shadowHueNormalized": [1, 1, 1], "weatherSpread": 1, "renderStyles": {}}}

func _rectangle() -> Dictionary:
	return {"minX": 0, "maxX": 40, "minZ": 0, "maxZ": 120}

func _root() -> Node3D:
	var root := Node3D.new()
	var node := MeshInstance3D.new()
	node.mesh = QuadMesh.new()
	root.add_child(node)
	add_child(root)
	return root

func _bind(root: Node3D) -> MarinePresentation:
	var view := MarinePresentation.new()
	held.append(view)
	_check(view.configure(_source(), _rectangle(), func(): return 0,
		func(_x: float, _z: float): return 2), "Configure a bounded marine scanner with original ripple declarations")
	_check(view.bind_surfaces(root, _source(), null), "Bind root lifetime independently of captured shader geometry")
	# A declared shader/quad isolates private resource ownership, not source marine pixels.
	var binding := MarineShaderBinding.new()
	var shader := Shader.new()
	shader.code = "shader_type spatial; uniform float uNativeOpacity = 0.7; void fragment() { ALBEDO = vec3(0.0); }"
	binding.material = ShaderMaterial.new()
	binding.material.shader = shader
	binding.material.set_shader_parameter("uNativeOpacity", .7)
	binding.wind_rules = rules
	root.get_child(0).material_override = binding.material
	view.bindings.append(binding)
	view.reflections.append({"node": root.get_child(0), "binding": binding, "opacity": .7})
	children.append(binding)
	resources.append(weakref(binding.material))
	return view

func _ripples() -> Array:
	return [MarinePresentation.ripples.index, MarinePresentation.ripples.cooldown, MarinePresentation.ripples.packets.duplicate()]

func _closed(view: MarinePresentation) -> void:
	var before := [view.revision, view.generation, view.swamp_z, _ripples()]
	var root := Node3D.new()
	_check(not view.configure(_source(), _rectangle(), Callable(), Callable()) and not view.bind_surfaces(root, _source(), null),
		"Closed marine owners reject source and surface reconfiguration")
	view.advance(.25, 10000, {}, [])
	view.sync_visuals(Visuals)
	view.sync_lighting(null)
	view.retire()
	_check(view.retired and not view.configured and view.source_root == null and view.bounds.is_empty()
		and view.bindings.is_empty() and view.reflections.is_empty() and view.appearance.is_empty(),
		"Marine retirement clears private bindings, borrowed nodes and source declarations")
	_check(view.swamp_cells.is_empty() and view.swamp_pending.is_empty() and view.waves.sources.is_empty()
		and view.waves.shapes.is_empty() and not view.water_height.is_valid() and not view.environment_code.is_valid(),
		"Closed marine owners release incremental scan state, wave buffers and terrain callbacks")
	_check(before == [view.revision, view.generation, view.swamp_z, _ripples()] and root.get_child_count() == 0,
		"Late marine commands cannot advance global ripple slots/cooldown or allocate another observer")
	root.free()

func _lifetimes() -> void:
	var root := _root()
	var view := _bind(root)
	view.advance(.1, 1, {}, [])
	var before := [view.generation, view.swamp_z, view.swamp_pending.duplicate(true), view.bindings[0].material, _ripples()]
	remove_child(root)
	await get_tree().process_frame
	add_child(root)
	var copy := root.duplicate()
	add_child(copy)
	copy.free()
	_check(not view.retired and before == [view.generation, view.swamp_z, view.swamp_pending,
		view.bindings[0].material, _ripples()], "Staging transfers and duplicate observers preserve scans, material identity and global ripple state")
	root.free()
	_closed(view)
	root = _root()
	view = _bind(root)
	var previous: MarineShaderBinding = view.bindings[0]
	var replacement := _root()
	_check(view.bind_surfaces(replacement, _source(), null), "Replace live marine surface ownership")
	_check(previous.retired and previous.material == null and previous.wind_rules.is_empty(),
		"Replacing surfaces closes externally retained old material bindings")
	root.free()
	_check(not view.retired and view.source_root == replacement, "Old root destruction cannot retire the replacement marine binding")
	before = [view.revision, view.swamp_z, _ripples()]
	replacement.queue_free()
	view.advance(.25, 100, {}, [])
	_check(before == [view.revision, view.swamp_z, _ripples()], "Queued marine roots reject scans and global ripple updates")
	await get_tree().process_frame
	_closed(view)
	root = _root()
	view = MarinePresentation.new()
	_check(view.bind_surfaces(root, _source(), null), "Bind a weakly observed marine owner")
	var weak: WeakRef = weakref(view)
	view = null
	_check(weak.get_ref() == null, "A marine root observer cannot retain its controller")
	await get_tree().process_frame
	_check(root.get_child_count() == 1, "Dropping a marine owner removes its observer while preserving borrowed geometry")
	root.free()

func _callbacks() -> void:
	for query in ["water", "code"]:
		for replace in [false, true]:
			var root := _root()
			var view := _bind(root)
			var owner := view
			var before := _ripples()
			var calls := {"code": 0}
			var interrupt := func():
				if replace:
					_check(owner.configure(_source(), {"minX": 10, "maxX": 30, "minZ": 20, "maxZ": 40},
						func(): return 0, func(_x: float, _z: float): return 2), "Terrain callbacks can replace the marine scanner")
				else:
					owner.retire()
			view.water_height = func():
				if query == "water": interrupt.call()
				return 0
			view.environment_code = func(_x: float, _z: float):
				calls.code += 1
				if query == "code": interrupt.call()
				return 2
			view.advance(.25, 100, {}, [])
			_check(calls.code == (0 if query == "water" else 1) and view.swamp_pending.is_empty(),
				"Interrupted terrain callbacks stop before later queries or stale cell writes")
			_check(before == _ripples(), "An interrupted scanner cannot advance the shared ripple clock")
			if replace:
				_check(view.swamp_z == 20 and not view.swamp_ready, "Old scan continuations cannot move replacement row cursors")
				view.retire()
			root.free()
			_closed(view)
	var nested_root := _root()
	var nested := _bind(nested_root)
	var nested_owner := nested
	nested.water_height = func():
		nested_owner.water_height = func(): return 0
		nested_owner.advance(.25, 2, {}, [])
		return 0
	nested.advance(.25, 1, {}, [])
	_check(nested.swamp_z == 20 and nested.swamp_pending.size() == 2,
		"A nested scan retains its newer row cursor without an extra outer-frame row")
	nested_root.free()
	_closed(nested)
	var root := _root()
	var view := _bind(root)
	var material: ShaderMaterial = view.bindings[0].material
	var preferences := VisualPreferences.new()
	preferences.persist = false
	preferences.configure(Content.balance.visual)
	_check(preferences.set_value("reflect", .5), "Admit a distinct reflection opacity target before cancellation")
	view.visual_revision = -1
	root.get_child(0).visible = false
	root.get_child(0).visibility_changed.connect(view.retire, CONNECT_ONE_SHOT)
	view.sync_visuals(preferences)
	_check(view.retired and absf(float(material.get_shader_parameter("uNativeOpacity")) - .7) < .000001,
		"Reflection visibility retirement stops the later opacity write and visual revision commit")
	preferences.free()
	root.free()
	_closed(view)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Marine material retirement requires a real renderer")
		get_tree().quit(1)
		return
	var capture: Dictionary = Content.read_json("res://tests/fixtures/marine_native.json")
	var provenance: Dictionary = Content.read_json("res://data/provenance.json")
	_check(capture.formatVersion == 1, "Load original marine packet, scanner and ripple programs")
	for path: String in capture.source.inputs:
		var source := FileAccess.get_file_as_string("res://" + path).replace("\r\n", "\n").replace("\r", "\n")
		_check(source.sha256_text() == capture.source.inputs[path], "Current marine capture producer: " + path)
	for path: String in capture.source.sourceInputs:
		_check(provenance.inputs[path] == capture.source.sourceInputs[path], "Original marine input matches imported provenance: " + path)
	if failures == 0:
		preload("res://tests/marine_suite.gd").run(self, capture)
		rules = capture.marineRules
		await _lifetimes()
		_callbacks()
		for binding: MarineShaderBinding in children:
			_check(binding.retired and binding.material == null and binding.wind_rules.is_empty(), "Closed marine children release all private material references")
			binding.advance({}, MarineWaveSources.new(), MarineRippleState.new())
			binding.sync_visuals(Visuals, {})
			binding.sync_lighting(null)
			_check(not binding.configure_geometry([], false) and not binding.configure(null, {}, {}, null), "Closed material bindings reject later geometry and source setup")
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	for resource: WeakRef in resources:
		_check(resource.get_ref() == null, "Closed retained marine owners release private native materials")
	held.clear()
	children.clear()
	print("MARINE_RETIREMENT assertions=", assertions, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
