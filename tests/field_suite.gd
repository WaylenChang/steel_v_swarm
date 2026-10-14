extends RefCounted

const StatusHelper = preload("res://tests/status_suite.gd")

class FieldSimulation extends BattleSimulation:
	var hits: Array = []

	func damage(_owner: BattleUnit, target: BattleUnit, definition: Dictionary, amount: float,
			_friendly: bool = false, _context: Dictionary = {}, _attack_modifiers: bool = true) -> void:
		hits.append({"target": target.entity_id, "amount": amount, "pen": definition.get("pen", 0)})

	func visible_to(_observer: BattleUnit, _target: BattleUnit) -> bool:
		return true

static func run(h: Node, fixtures: Dictionary) -> void:
	for key: String in ["fieldCube", "fieldFog", "fieldVisibility", "fieldBarriers", "fieldFogGeometry"]:
		if not fixtures.has(key):
			h._check(false, "Regenerate original persistent-field references before final verification: " + key)
			return
	for item: Dictionary in fixtures.fieldCube:
		var simulation := context(h)
		var owner := pilot(simulation, 1, "t10", "STEEL", Vector3.ZERO)
		pilot(simulation, 2, "s09", "SWARM", Vector3(0, 0, -3))
		var before := simulation.rng.state
		simulation._cast_effect(owner, Content.ability("t10", "def", int(item.level)), Vector3.ZERO, item.fraction)
		h._check(simulation.cubic_cages.size() == 1 and simulation.cubic_cages[0].members.size() == 6, "Original cube spawns six owned damage bodies")
		var cage: Dictionary = simulation.cubic_cages[0]
		h._near(cage.dps, item.dps, "Original cube fraction scales damage only")
		h._near(cage.radius, item.radius, "Original cube radius is fixed")
		h._near(cage.until, item.until, "Original cube duration is not fraction scaled")
		for index in range(6):
			var slab: BattleUnit = simulation.units[int(cage.members[index])]
			var expected: Dictionary = item.slabs[index]
			h._check(slab.position.distance_to(vector(expected.position)) < 0.00001, "Original cube hexagonal placement")
			h._near(slab.hp, expected.hp, "Original cube rounded fractional HP")
			h._near(slab.max_hp, expected.max_hp, "Original cube damage-body cap")
			h._near(slab.height, expected.height, "Original cube damage band remains separate from its six-metre model")
			h._near(slab.radius, expected.radius, "Original cube hit radius remains separate from its authored effect radius")
			h._near(slab.effect_radius, expected.effect_radius, "Original explicit slab radius")
			h._near(slab.yaw, -expected.angle, "Original owned slab renderer rotation")
			h._check(slab.collision_layer == 0 and slab.hit_area.get_child_count() == 2, "Owned skill objects do not invent a movement wall; both visible boxes remain shootable")
		for index in range(item.steps.size()):
			var step: Dictionary = item.steps[index]
			simulation.clock = step.now
			if index == 1:
				for member in range(0, 6, 2):
					simulation._remove_field_unit(int(cage.members[member]))
			simulation._tick_cubic_slabs(0.1)
			StatusHelper.compare(h, simulation.hits, step.damage, "Original cube continuous hostile damage")
			simulation.hits.clear()
			h._check(simulation.cubic_cages.size() == int(step.cages), "Original cube expiry and all-slabs-dead cleanup")
			var angles: Array = []
			for id in cage.members:
				if simulation.units.has(id) and simulation.units[id].alive():
					angles.append(simulation.units[id].special.angle)
			StatusHelper.compare(h, angles, step.live, "Original partial slab destruction preserves its remaining panels")
		h._check(simulation.rng.state == before, "Cube placement, damage and expiry do not consume combat randomness")
		simulation.free()
	for item: Dictionary in fixtures.fieldFog:
		var simulation := context(h)
		var owner := pilot(simulation, 1, item.character, "STEEL", Vector3.ZERO)
		var enemy := pilot(simulation, 2, "s09", "SWARM", Vector3(item.radius + (1.01 if item.outside else 1), 0, 0))
		var before := simulation.rng.state
		simulation._cast_effect(owner, Content.ability(item.character, "def", int(item.level)), Vector3.ZERO, item.fraction)
		h._near(simulation.fogs[0].duration, item.duration, "Original fog duration ignores interruption fraction")
		h._near(simulation.fogs[0].until, item.until, "Original fog expiry")
		for step: Dictionary in item.steps:
			simulation.clock = step.now
			simulation._tick_fogs(step.delta)
			StatusHelper.compare(h, simulation.hits, step.damage, "Original toxic fog damage and explicit effect-radius gate")
			simulation.hits.clear()
			h._check(simulation.fogs.size() == int(step.fields), "Original inclusive fog expiry")
			StatusHelper.compare(h, enemy.status.get("element_buildup", {}), step.buildup, "Original continuous poison buildup")
			h._check(int(enemy.status.get("poison_stacks", 0)) == int(step.poison), "Original toxic fog poison stack threshold")
			if step.bleed != null:
				StatusHelper.compare(h, enemy.bleed, step.bleed, "Original toxin bleed attribution")
		h._check(simulation.rng.state == before, "Toxic fog deterministic buildup cannot advance the combat RNG")
		simulation.free()
	for item: Dictionary in fixtures.fieldVisibility:
		var simulation := context(h)
		var observer := StatusHelper.actor(simulation, {"id": 1, "kind": "soldier", "character": "", "side": "SWARM", "position": [item.observer[0], 0, item.observer[1]]})
		var target := pilot(simulation, 2, "m04", "STEEL", Vector3(item.target[0], 0, item.target[1]))
		for field: Dictionary in item.fogs:
			var fog := field.duplicate(true)
			fog.center = Vector2(field.center[0], field.center[1])
			simulation.fogs.append(fog)
		h._near(AbilityFieldRules.observer_factor(simulation.fogs, Vector2(observer.position.x, observer.position.z), "SWARM", 10), item.factor, "Original tactical fog sight contraction applies once")
		h._check(simulation.visible_to_side(target, "SWARM") == item.result, "Original first protecting fog and same-fog observer restriction")
		simulation.free()
	for item: Dictionary in fixtures.fieldBarriers:
		var slabs: Array = item.slabs.duplicate(true)
		for slab: Dictionary in slabs:
			slab.center = Vector2(slab.center[0], slab.center[1])
		h._check(is_finite(AbilityFieldRules.slab_hit(vector(item.start), vector(item.end), slabs)) == item.result, "Original slab LOS finite plane, inclusive endpoints, height and dead-panel gates")
	for item: Dictionary in fixtures.fieldFogGeometry:
		var presentation := SkillFieldPresentation.new()
		h.add_child(presentation)
		var side := "STEEL" if item.ally else "SWARM"
		var states := [{"id": 1, "center": Vector2.ZERO, "radius": item.radius, "start": 10.0, "until": 18.0, "duration": 8.0, "side": "STEEL"}]
		presentation.sync_fogs(states, side, 10)
		var root: Node3D = presentation.fog_nodes[1]
		h._check(root.get_child_count() == item.nodes.size(), "Original fog disk and five ring clouds")
		for index in range(item.nodes.size()):
			var node: MeshInstance3D = root.get_child(index)
			var expected: Dictionary = item.nodes[index]
			var vertices: PackedVector3Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			h._check(vertices.size() == expected.vertices.size(), "Original fog triangle topology")
			for vertex in range(mini(vertices.size(), expected.vertices.size())):
				h._check((node.transform * vertices[vertex]).distance_to(vector(expected.vertices[vertex])) < 0.00001, "Original fog geometry within native float precision")
			var material: StandardMaterial3D = node.material_override
			h._near(material.albedo_color.a, expected.opacity, "Original friendly/enemy fog opacity")
			h._check(material.albedo_color.to_html(false) == Color.hex((int(expected.color) << 8) | 255).to_html(false), "Original tactical fog palette")
		for frame: Dictionary in item.frames:
			presentation.sync_fogs(states, side, 10 + float(frame.age))
			h._near(root.rotation.y, frame.rotation, "Original fog rotation rate")
			h._near(root.get_child(0).material_override.albedo_color.a, frame.opacity, "Only the original disk fades during the final fifth of its lifetime")
		presentation.sync_fogs(states, side, 18)
		h._check(presentation.fog_nodes.is_empty(), "Authority expiry removes fog presentation without an additional fade tail")
		presentation.free()
	print("FIELD_REFERENCE_PASS cube=", fixtures.fieldCube.size(), " fog=", fixtures.fieldFog.size(), " visibility=", fixtures.fieldVisibility.size(),
		" barriers=", fixtures.fieldBarriers.size(), " visuals=", fixtures.fieldFogGeometry.size())

static func context(h: Node) -> FieldSimulation:
	var simulation := FieldSimulation.new()
	h.add_child(simulation)
	simulation.set_physics_process(false)
	simulation.clock = 10
	simulation.world = BattleWorld.new()
	simulation.add_child(simulation.world)
	return simulation

static func pilot(simulation: BattleSimulation, id: int, character: String, side: String, point: Vector3) -> BattleUnit:
	return StatusHelper.actor(simulation, {"id": id, "character": character, "side": side, "position": [point.x, point.y, point.z],
		"hp": 1000, "max_hp": 1000, "shield": 30, "max_shield": 500, "power": 1000, "max_power": 1000})

static func vector(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])
