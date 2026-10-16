extends RefCounted

const Helper = preload("res://tests/status_suite.gd")
const Points = preload("res://tests/npc_shot_suite.gd")
const Frames = preload("res://tests/view_suite.gd")

static func run(h: Node, fixtures: Dictionary) -> void:
	for key: String in ["firstPersonShieldGeometry", "firstPersonShieldFrames", "firstPersonShieldRetargets", "selfVitalHits"]:
		if not fixtures.has(key) or not FirstPersonShield.available():
			h._check(false, "Regenerate and pack original first-person shield scenes/references: " + key)
			return
	for item: Dictionary in fixtures.firstPersonShieldGeometry:
		var shield := _create(h, item.character)
		if shield == null:
			continue
		_state(h, shield, item.initial)
		var nodes: Array[Node] = [shield.source_root]
		nodes.append_array(shield.source_root.find_children("*", "Node3D", true, false))
		h._check(nodes.size() == item.nodes.size(), "Original camera shield hierarchy excludes cockpit and weapon animation")
		for spec: Dictionary in item.nodes:
			var matches := nodes.filter(func(candidate): return candidate.name == "n_%d" % int(spec.id))
			h._check(not matches.is_empty(), "Original camera shield node ID remains bound")
			if matches.is_empty():
				continue
			var node: Node3D = matches[0]
			var expected := Frames.frame(spec.matrix)
			h._check(node.transform.is_equal_approx(expected), "Original six-sided camera shield placement and local orientation")
			if not spec.has("mesh"):
				continue
			var mesh := node as MeshInstance3D
			var source: Dictionary = item.meshes[int(spec.mesh)]
			var arrays := mesh.mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			h._check(vertices.size() * 3 == source.position.size() and indices.size() == source.indices.size(), "Original camera shield CircleGeometry topology")
			for vertex in range(vertices.size()):
				Points._point(h, vertices[vertex], source.position.slice(vertex * 3, vertex * 3 + 3), "Original camera shield radius and planar vertex")
			for triangle in range(0, indices.size(), 3):
				h._check(indices[triangle] == int(source.indices[triangle]) and indices[triangle + 1] == int(source.indices[triangle + 2])
					and indices[triangle + 2] == int(source.indices[triangle + 1]), "Original camera shield triangles retain Godot front-face winding")
			var profile: Dictionary = item.materials[int(spec.materials[0])]
			for key: String in ["uPlanar", "uHexR", "uHasPattern", "uPatternAspect"]:
				h._near(float(shield.material.get_shader_parameter(key)), float(profile.uniforms[key]), "Original planar shield material: " + key)
		shield.free()
	for item: Dictionary in fixtures.firstPersonShieldFrames:
		var shield := _create(h, item.character)
		if shield == null:
			continue
		shield.hit(1.8)
		for step: Dictionary in item.steps:
			shield.advance(float(step.delta), float(step.get("now", 10)), item.mode, item.defending, item.shield, item.dead, item.expanded,
				step.get("cast"), float(step.get("duration", 0)))
			_state(h, shield, step.result)
		shield.free()
	var retarget := _create(h, fixtures.firstPersonShieldGeometry[0].character)
	if retarget != null:
		retarget.hit(2.5)
		for step: Dictionary in fixtures.firstPersonShieldRetargets:
			var changed := retarget.set_character(step.character)
			h._check(changed == Content.heroes.has(step.character), "Unknown source character styles retain the existing camera shield")
			retarget.advance(.016, 10, "fpv", true, 50, false, 0)
			_state(h, retarget, step.result)
		retarget.free()
	for item: Dictionary in fixtures.selfVitalHits:
		var reaction := VictimHitState.self_reaction(item.previous, item.current)
		h._check(reaction.is_empty() == item.result.is_empty(), "Original private vital-loss half-point threshold, healing and death gates")
		Helper.compare(h, reaction, item.result, "Original FPV shield versus hurt-vignette branch")
	var first := _create(h, fixtures.firstPersonShieldGeometry[0].character)
	var second := _create(h, fixtures.firstPersonShieldGeometry[0].character)
	if first != null and second != null:
		first.hit(2.5)
		first.advance(.1, 10, "fpv", true, 50, false, 0)
		h._near(float(second.material.get_shader_parameter("uFlash")), 0, "Packed camera shields isolate live flash uniforms")
		h._near(float(second.material.get_shader_parameter("uTime")), float(Content.balance.bodyRules.shield.timeWindow) * .25,
			"Packed camera shields isolate animation clocks")
	if first != null:
		first.free()
	if second != null:
		second.free()
	_production(h, fixtures.firstPersonShieldGeometry[0].character)

static func _create(h: Node, character: String) -> FirstPersonShield:
	var shield := FirstPersonShield.new()
	h.add_child(shield)
	if not shield.configure(character, func(): return .25):
		h._check(false, "Pack camera shield: " + character)
		shield.free()
		return null
	return shield

static func _state(h: Node, shield: FirstPersonShield, reference: Dictionary) -> void:
	Points._point(h, shield.source_root.position, reference.position, "Original camera-local shield position")
	Points._point(h, shield.source_root.scale, reference.scale, "Original horizontal-only expanded shield")
	h._check(absf(shield.source_root.quaternion.dot(BodyPose.quaternion(reference.quaternion))) > .999999,
		"Original camera shield forward orientation")
	h._check(shield.source_root.visible == reference.visible and shield.character == reference.character,
		"Original FPV/TPS, defending, dead and defense-cast visibility")
	for key: String in ["time", "flash", "hasPattern"]:
		var parameter := {"time": "uTime", "flash": "uFlash", "hasPattern": "uHasPattern"}[key]
		h._near(float(shield.material.get_shader_parameter(parameter)), float(reference[key]), "Original camera shield independent clock/flash: " + key)
	Points._point(h, shield.material.get_shader_parameter("uColor"), reference.color, "Original character shield linear colour")
	Points._point(h, shield.material.get_shader_parameter("uAccent"), reference.accent, "Original character shield linear accent")

static func _production(h: Node, character: String) -> void:
	var simulation := BattleSimulation.new()
	h.add_child(simulation)
	simulation.set_physics_process(false)
	simulation.world = BattleWorld.new()
	simulation.add_child(simulation.world)
	var owner := Helper.actor(simulation, {"id": 1, "character": character, "side": "STEEL", "position": [12, 20, -9],
		"hp": 700, "shield": 120, "power": 80, "ammo": {"light": 4, "heavy": 2}})
	owner.camera = Camera3D.new()
	owner.add_child(owner.camera)
	owner.ensure_cockpit()
	h._check(owner.first_person_shield != null and owner.first_person_shield.get_parent() == owner.camera,
		"Camera shield is independent of cockpit visibility and weapon recoil")
	var hurt := {"count": 0}
	simulation.self_hurt.connect(func(): hurt.count += 1)
	var resources := [owner.hp, owner.shield, owner.power, owner.ammo.duplicate(), simulation.rng.state, simulation.projectile_rng.state]
	simulation.present_victim_snapshot(owner, {"hp": 700, "shield": 120, "defending": true})
	simulation.present_victim_snapshot(owner, {"hp": 700, "shield": 100, "defending": true})
	var flash := float(owner.first_person_shield.material.get_shader_parameter("uFlash"))
	h._check(flash > 0 and int(hurt.count) == 0, "Published shield damage reaches the camera shader without an armor vignette")
	simulation.present_victim_snapshot(owner, {"hp": 680, "shield": 100, "defending": false})
	simulation.present_victim_snapshot(owner, {"hp": 680, "shield": 100, "defending": false})
	h._check(int(hurt.count) == 1, "One published armor loss emits one private hurt presentation")
	simulation.present_victim_snapshot(owner, {"hp": 500, "shield": 100, "defending": false, "view_reset": 1})
	h._check(int(hurt.count) == 1, "A new private view resets the observed vital baseline")
	h._check(resources == [owner.hp, owner.shield, owner.power, owner.ammo, simulation.rng.state, simulation.projectile_rng.state],
		"Camera shield/hurt presentation cannot settle damage or consume authority resources/RNG")
	simulation.free()
