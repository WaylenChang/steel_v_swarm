extends RefCounted

const GeometryTests = preload("res://tests/scene_damage_suite.gd")
const ViewTests = preload("res://tests/view_suite.gd")

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("damageFxFrames") or not fixtures.has("damageFxStages") or not DamageFx.available():
		h._check(false, "Regenerate and pack original persistent-damage textures, flame geometry and references")
		return
	for item: Dictionary in fixtures.damageFxFrames:
		var parent := Node3D.new()
		h.add_child(parent)
		parent.transform = ViewTests.frame(item.parent)
		var fx := DamageFx.new()
		parent.add_child(fx)
		var draws := {"count": 0}
		var sample := func():
			var value := float(item.random[int(draws.count) % item.random.size()])
			draws.count += 1
			return value
		if not fx.configure(item.dimensions, item.fire, item.surfaceCracks, sample):
			h._check(false, "Original damage FX resources must be available")
			parent.free()
			continue
		h._check(int(draws.count) == int(item.draws), "Original smoke/crack/flame/ember constructor random draw order, including hidden components")
		_compare(h, fx, item.initial)
		for step: Dictionary in item.steps:
			fx.set_stage(int(step.stage))
			fx.advance(float(step.dt), float(step.now), step.weather)
			_compare(h, fx, step.result)
			h._check(int(draws.count) == int(item.draws), "Persistent damage animation consumes no additional visual or combat randomness")
		parent.free()
	_gates(h, fixtures.damageFxStages, int(fixtures.damageFxFrames[0].draws))
	_visibility(h)
	print("DAMAGE_FX_REFERENCE_PASS frames=", fixtures.damageFxFrames.size(), " gates=", fixtures.damageFxStages.size())

static func _compare(h: Node, fx: DamageFx, reference: Dictionary) -> void:
	h._check(fx.stage == int(reference.stage) and fx.get_child_count() == reference.nodes.size(), "Original persistent damage child order and stage")
	for index in range(mini(fx.get_child_count(), reference.nodes.size())):
		var node := fx.get_child(index) as MeshInstance3D
		var expected: Dictionary = reference.nodes[index]
		h._check(node.position.distance_to(BodyPose.vector(expected.position)) < .0003 and node.scale.distance_to(BodyPose.vector(expected.scale)) < .0003,
			"Original local wind, smoke/ember phase, plume clamp, flame size and zero-delta updates")
		h._check(absf(node.quaternion.dot(BodyPose.quaternion(expected.quaternion))) > .99999 and node.visible == bool(expected.visible),
			"Original independently rotated crack planes, wind lean and fire/surface exclusions")
		var material := node.material_override as ShaderMaterial
		h._near(float(material.get_shader_parameter("opacity")), float(expected.opacity), "Original particle/crack opacity and wall-clock flicker")
		var tint: Vector3 = material.get_shader_parameter("tint")
		h._check(tint.distance_to(BodyPose.vector(expected.color)) < .00002, "Original normal/additive particle linear colour")
		var phase: Variant = fx.smoke[index].phase if index < 4 else fx.flames[index - 14].phase if index >= 14 and index < 17 else fx.embers[index - 17].phase if index >= 17 else null
		if expected.phase != null:
			h._near(float(phase), float(expected.phase), "Original independent phase retention through light/heavy transitions")
		if expected.width != null:
			var quad := node.mesh as QuadMesh
			h._check(quad.size.distance_to(Vector2(expected.width, expected.height)) < .0003, "Original randomized crack-plane dimensions")
		if index >= 14 and index < 17:
			var arrays := node.mesh.surface_get_arrays(0)
			GeometryTests._vectors(h, arrays[Mesh.ARRAY_VERTEX], expected.geometry, "Original authored flame vertices scaled before animation")
			GeometryTests._vectors(h, arrays[Mesh.ARRAY_NORMAL], expected.normals, "Original authored flame normal transformation")

static func _number(value: Variant) -> Variant:
	if not value is String:
		return value
	if value == "NAN":
		return NAN
	if value == "INF":
		return INF
	if value == "-INF":
		return -INF
	return value

static func _gates(h: Node, fixtures: Array, constructor_draws: int) -> void:
	for item: Dictionary in fixtures:
		var unit := BattleUnit.new()
		h.add_child(unit)
		unit.kind = item.settings.kind
		unit.model = Node3D.new()
		unit.add_child(unit.model)
		unit.geometry_override = {"radius": 0.0, "top": 0.0, "height": 0.0}
		var effects := CombatEffects.new()
		var draws := {"count": 0}
		effects.random_sample = func():
			draws.count += 1
			return .5
		var values := {"hp": 100.0, "max": 100.0, "dead": false}
		values.merge(item.settings, true)
		var allocated := 0
		var released := 0
		var previous_id := 0
		for step: Dictionary in item.steps:
			for key: String in step.values:
				values[key] = _number(step.values[key])
			unit.character = "t01" if values.get("isSelf", false) else ""
			unit.peer_id = h.multiplayer.get_unique_id() if values.get("isSelf", false) else 0
			unit.special = {"neutral": values.get("neutral", false), "collapsed": values.get("collapsed", false),
				"role": "civilian" if values.get("civ", false) else ""}
			unit.present_damage_fx({"hp": values.hp, "max_hp": values.max, "dead": values.dead}, effects)
			var id := unit.damage_fx.get_instance_id() if unit.damage_fx != null else 0
			if id != previous_id:
				if id != 0:
					allocated += 1
				if previous_id != 0:
					released += 1
			previous_id = id
			h._check(unit.damage_fx_stage == int(step.stage) and (unit.damage_fx != null) == bool(step.present) and (unit.damage_fx != null) == bool(step.active),
				"Original self/civilian/carrier/neutral/collapse and finite/non-finite health admission")
			h._check(allocated == int(step.allocated) and released == int(step.released) and int(draws.count) == allocated * constructor_draws,
				"Original retained stage switches and clear/recreate allocation behavior")
			if unit.damage_fx != null:
				h._check(unit.damage_fx.stage == int(step.fxStage), "Original persistent group receives the observed stage")
				var options: Dictionary = step.options.back()
				var size := unit.damage_fx.source_size
				h._check(float(size.radius) == float(options.r) and float(size.top) == float(options.top) and float(size.height) == float(options.h)
					and unit.damage_fx.fire == bool(options.fire) and unit.damage_fx.surface_cracks == bool(options.surfaceCracks),
					"Original dimension fallbacks and profile-controlled fire/surface cracks")
		effects.free()
		unit.free()

static func _visibility(h: Node) -> void:
	var simulation := BattleSimulation.new()
	h.add_child(simulation)
	simulation.set_physics_process(false)
	simulation.weather_dynamics = {"windAmp": 2.0, "windDir": [.6, -.8]}
	var world := BattleWorld.new()
	simulation.world = world
	simulation.add_child(world)
	var unit := BattleUnit.new()
	simulation.add_child(unit)
	unit.kind = "soldier"
	unit.entity_id = 42
	unit.hp = 100
	unit.model = Node3D.new()
	unit.add_child(unit.model)
	unit.geometry_override = {"radius": 2.0, "top": 5.0, "height": 6.0}
	simulation.units[unit.entity_id] = unit
	var effects := CombatEffects.new()
	effects.random_sample = func(): return .5
	unit.present_damage_fx({"hp": 25.0, "max_hp": 100.0}, effects)
	var resources := [unit.hp, unit.shield, unit.power, unit.money, unit.ammo.duplicate(true), simulation.clock, simulation.rng.state, simulation.projectile_rng.state]
	unit.model.visible = false
	simulation.step_damage_fx(.1, 10)
	h._near(float(unit.damage_fx.smoke[0].phase), 0, "Hidden/garrison bodies pause persistent smoke phase")
	unit.model.visible = true
	simulation.step_damage_fx(.1, 10)
	h._near(float(unit.damage_fx.smoke[0].phase), .033, "Visible bodies resume using the shared presentation delta")
	var phase := float(unit.damage_fx.smoke[0].phase)
	simulation.step_damage_fx(0, 20)
	h._near(float(unit.damage_fx.smoke[0].phase), phase, "Hitstop freezes phase while preserving wall-clock flame updates")
	simulation.apply_presentation_view({"units": [], "clock": 10.0})
	h._check(unit.damage_fx == null and unit.damage_fx_stage == 0, "Authority visibility loss releases persistent groups")
	h._check(resources == [unit.hp, unit.shield, unit.power, unit.money, unit.ammo, simulation.clock, simulation.rng.state, simulation.projectile_rng.state],
		"Persistent damage FX cannot settle health, ammunition, purchases, authority time or combat RNG")
	effects.free()
	simulation.free()
