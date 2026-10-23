extends RefCounted

const Helper = preload("res://tests/status_suite.gd")

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("vitalBars") or not fixtures.has("vitalBarPoses") or not VitalBar.available():
		h._check(false, "Regenerate original overhead HP/shield bar constructors and transitions")
		return
	for program: Dictionary in fixtures.vitalBars:
		var bar := VitalBar.new()
		h.add_child(bar)
		for frame: Dictionary in program.frames:
			bar.sync(values(program.options, frame.state))
			if frame.bar == null:
				h._check(bar.group == null, "Original self/full/unsupported-scene bar suppression: " + program.name)
				continue
			h._check(bar.group != null and bar.nodes.size() == frame.bar.nodes.size(), "Original bar creation/caching and shield-row lifetime: " + program.name)
			if bar.group == null or bar.nodes.size() != frame.bar.nodes.size():
				continue
			h._near(bar.group.position.y, frame.bar.y, "Original fixed top/collider-height bar anchor")
			for index in bar.nodes.size():
				var node := bar.nodes[index]
				var material := bar.materials[index]
				var expected: Dictionary = frame.bar.nodes[index]
				var size: Vector2 = (node.mesh as QuadMesh).size
				Helper.compare(h, [size.x, size.y], expected.size, "Original bar plane dimensions")
				Helper.compare(h, [node.position.x, node.position.y, node.position.z], expected.position, "Original left-anchored fills and layer offsets")
				Helper.compare(h, [node.scale.x, node.scale.y, node.scale.z], expected.scale, "Original unclamped overcharge and minimum empty-fill width")
				h._check(material.albedo_color.to_html(false) == String(expected.colour).trim_prefix("#") and node.visible == expected.visible, "Original ally/foe/segment colors and empty shield visibility")
				h._near(material.albedo_color.a, expected.opacity, "Original bar material opacity")
				h._check(int(expected.side) == 0 and material.cull_mode == BaseMaterial3D.CULL_BACK, "Original bar planes retain front-face rendering")
				h._check(material.no_depth_test and material.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED and material.render_priority == HeadMarks.render_priority(int(expected.order)),
					"Native bar material preserves original depth flags and cross-marker ordering")
		bar.free()
	for item: Dictionary in fixtures.vitalBarPoses:
		var parent := Node3D.new()
		h.add_child(parent)
		parent.transform = Transform3D(Basis(quaternion(item.rotation)).scaled_local(Vector3(item.scale[0], item.scale[1], item.scale[2])), Vector3(item.position[0], item.position[1], item.position[2]))
		var bar := VitalBar.new()
		parent.add_child(bar)
		bar.sync(values({}, {"hp": 50, "max": 100, "sp": 50, "maxSp": 100, "bossSeg": null, "collapsed": false, "viewer": "STEEL"}))
		bar.pose(bar.group.global_position + Vector3(item.offset[0], item.offset[1], item.offset[2]))
		h._check(absf(bar.group.quaternion.dot(quaternion(item.bar))) > 0.99999, "Original group lookAt, scaled parents, coincident target and vertical up-axis fallback")
		bar.hide_bar()
		h._check(not bar.group.visible, "A retained corpse hides its source HP bar without changing settlement")
		bar.clear_bar()
		h._check(bar.group == null and bar.nodes.is_empty(), "Collapse/full-scene healing releases the cached bar group")
		parent.free()
	_static_presentation(h)

static func _static_presentation(h: Node) -> void:
	var simulation := BattleSimulation.new()
	h.add_child(simulation)
	simulation.set_physics_process(false)
	var unit := BattleUnit.new()
	simulation.add_child(unit)
	unit.entity_id = 99872
	unit.kind = "car"
	unit.model = Node3D.new()
	unit.add_child(unit.model)
	unit.vital_bar = VitalBar.new()
	unit.model.add_child(unit.vital_bar)
	unit.vital_bar.sync(values({"kind": "car", "neutral": true},
		{"hp": 50, "max": 100, "sp": 0, "maxSp": 0, "bossSeg": null, "collapsed": false, "viewer": "STEEL"}))
	simulation.units[unit.entity_id] = unit
	var camera := Camera3D.new()
	simulation.add_child(camera)
	camera.position = Vector3(10000, 30, 10000)
	var stride := BodyPresentation.update_stride(Vector2(camera.position.x, camera.position.z).length_squared(), Controls.low_power())
	for number in stride * 2:
		unit.vital_bar.group.basis = Basis.IDENTITY
		simulation.present_bodies(.016, number * .016, number, camera)
		var due := BodyPresentation.update_due(number, str(unit.entity_id), stride)
		h._check((not unit.vital_bar.group.basis.is_equal_approx(Basis.IDENTITY)) == due,
			"Static scenery without a body rig still faces its bar on the existing source LOD schedule")
	unit.presentation_visible = false
	unit.vital_bar.group.basis = Basis.IDENTITY
	simulation.present_bodies(.016, 1, 0, camera)
	h._check(unit.vital_bar.group.basis.is_equal_approx(Basis.IDENTITY), "Hidden scenery cannot update a retained bar")
	simulation.free()

static func values(options: Dictionary, state: Dictionary) -> Dictionary:
	return {"self": options.get("isSelf", false), "neutral": options.get("neutral", false), "civilian": options.get("civ", false),
		"static": options.get("isStatic", false), "kind": options.get("kind", "robot"),
		"side": options.get("side", "SWARM") if options.get("side", "SWARM") != null else "", "viewer": state.viewer,
		"hp": state.hp, "maximum": state.max, "shield": state.sp, "max_shield": state.maxSp,
		"segment": state.bossSeg, "collapsed": state.collapsed, "top": 9, "collider_height": 7}

static func quaternion(value: Array) -> Quaternion:
	return Quaternion(value[0], value[1], value[2], value[3])
