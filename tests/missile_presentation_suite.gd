extends RefCounted

const Helper = preload("res://tests/status_suite.gd")

class FlatWorld extends BattleWorld:
	func source_height(x: float, z: float) -> float:
		return 5 + x * .1 - z * .2

class RecordedEffects extends CombatEffects:
	var bursts: Array = []
	var order: Array = []
	func _ready() -> void:
		pass
	func scene_damage_burst(id: int, _kind: String, point: Vector3, height: float, radius: float, destination: int) -> void:
		order.append("fracture")
		bursts.append({"id": id, "stage": destination, "position": [point.x, point.y, point.z], "height": height, "radius": radius})
	func explosion(_point: Vector3, _radius: float, _colour: int) -> void:
		order.append("boom")
	func shock(_point: Vector3, _radius: float, _colour: int) -> void:
		pass

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("missilePresentation") or not MissilePresentation.available():
		h._check(false, "Regenerate original snapshot missile scenes, puff geometry and presentation fixtures")
		return
	for authoritative: bool in [true, false]:
		for item: Dictionary in fixtures.missilePresentation:
			var simulation := BattleSimulation.new()
			simulation.authoritative = authoritative
			h.add_child(simulation)
			simulation.set_physics_process(false)
			var world := FlatWorld.new()
			simulation.world = world
			simulation.add_child(world)
			var effects := RecordedEffects.new()
			world.combat_effects = effects
			world.add_child(effects)
			var collision_body := MissileBody.new()
			collision_body.position = Vector3(90, 200, -100)
			simulation.add_child(collision_body)
			simulation.missile_bodies[999] = collision_body
			simulation.missiles.append({"id": 999, "position": Vector3(90, 20, -100), "hp": 10.0, "max_hp": 10.0})
			var draws := {"count": 0}
			effects.random_sample = func():
				draws.count += 1
				return .5
			var resources := [simulation.clock, simulation.rng.state, simulation.projectile_rng.state, simulation.next_id,
				simulation.missiles.duplicate(true), simulation.missile_bodies.duplicate(), collision_body.transform, collision_body.collision_layer]
			for step: Dictionary in item.steps:
				var states: Array = []
				for source: Dictionary in step.states:
					var state := source.duplicate(true)
					state.position = BodyPose.vector(source.position)
					state.hp = NAN if source.hp is String else source.hp
					states.append(state)
				effects.bursts.clear()
				simulation.sync_missile_presentations(states, step.reports)
				simulation.step_missile_presentations(float(step.delta))
				effects.advance(float(step.delta))
				_compare(h, simulation, effects, step.result, int(draws.count))
				h._check(resources == [simulation.clock, simulation.rng.state, simulation.projectile_rng.state, simulation.next_id,
					simulation.missiles, simulation.missile_bodies, collision_body.transform, collision_body.collision_layer],
					"Missile view sync, damage and removal cannot mutate authority flight/collision state or RNG")
			simulation.free()
	_publication(h)
	print("MISSILE_PRESENTATION_REFERENCE_PASS fixtures=", fixtures.missilePresentation.size())

static func _publication(h: Node) -> void:
	var simulation := BattleSimulation.new()
	h.add_child(simulation)
	simulation.set_physics_process(false)
	var world := FlatWorld.new()
	simulation.world = world
	simulation.add_child(world)
	var effects := RecordedEffects.new()
	world.combat_effects = effects
	world.add_child(effects)
	simulation.view_snapshot_ready.connect(func(_state): effects.order.append("view"))
	simulation.apply_presentation_view({"units": [], "missiles": [{"id": 7, "position": Vector3(12, 10, -9), "hp": 100.0, "max_hp": 100.0}], "events": [], "clock": 0.0})
	simulation.present_world_events([])
	h._check(simulation.missile_presentations.has(7), "Authority rendering creates missile views from published snapshots")
	var report := {"type": "missile_intercept", "missile": 7, "actor": 0, "position": Vector3(12, 18, -9), "radius": 8.0, "side": "STEEL", "blast_serial": 77}
	var packet := {"units": [], "missiles": [], "events": [report], "clock": 0.0}
	effects.order.clear()
	simulation.apply_presentation_view(packet)
	simulation.present_world_events(packet.events)
	h._check(effects.order == Content.balance.missile.presentation.publicationOrder, "Original private view/death setup and world events precede missile removal fracture")
	effects.order.clear()
	simulation.apply_presentation_view(packet)
	simulation.present_world_events(packet.events)
	h._check(effects.order == ["view"], "Repeated removal snapshots cannot repeat missile fracture or replay the global boom")
	simulation.free()

static func _compare(h: Node, simulation: BattleSimulation, effects: RecordedEffects, reference: Dictionary, draws: int) -> void:
	h._check(draws == int(reference.draws), "Original missile persistent-damage constructor draws and repeat guards")
	Helper.compare(h, effects.bursts, reference.bursts, "Original missile band/removal burst order, interpolated world anchor and source dimensions")
	h._check(simulation.missile_presentations.size() == reference.missiles.size(), "Original snapshot missile creation, silent removal and boom-ID fracture gating")
	for row: Dictionary in reference.missiles:
		if not simulation.missile_presentations.has(int(row.id)):
			continue
		var view: MissilePresentation = simulation.missile_presentations[int(row.id)]
		for property: String in ["position", "target", "previous"]:
			var point: Vector3 = view.get(property)
			h._check(point.distance_to(BodyPose.vector(row[property])) < .0003,
				"Original missile terrain-relative snapshots, exponential interpolation and prior-target direction")
		h._check(absf(view.quaternion.dot(BodyPose.quaternion(row.quaternion))) > .99999, "Original +Z heading, half-unit squared-distance gate and zero-delta orientation")
		h._near(view.age, float(row.age), "Original presentation-age accumulator")
		h._near(view.smoke, float(row.smoke), "Original strict smoke deadline and single-puff reset")
		h._check(view.mobile_damage.stage == int(row.stage) and view.damage_fx.stage == int(row.fxStage)
			and (view.damage_fx.node != null) == bool(row.fx), "Original finite-health guard, shared mobile tint and persistent-damage stage")
		var nodes := view.model.source_root.get_children().filter(func(node): return node is MeshInstance3D)
		h._check(nodes.size() == row.nodes.size(), "Original standalone missile body and jet topology")
		for index in range(mini(nodes.size(), row.nodes.size())):
			var node: MeshInstance3D = nodes[index]
			var expected: Dictionary = row.nodes[index]
			h._check(node.position.distance_to(BodyPose.vector(expected.position)) < .0003 and node.scale.distance_to(BodyPose.vector(expected.scale)) < .0003,
				"Original missile projectile age/speed jet animation")
			h._near((node.get_active_material(0) as BaseMaterial3D).albedo_color.a, float(expected.opacity), "Original missile per-instance jet opacity")
	h._check(effects.effects.size() == reference.effects.size(), "Original puff count and global effect expiry")
	for index in range(mini(effects.effects.size(), reference.effects.size())):
		var effect: Dictionary = effects.effects[index]
		var expected: Dictionary = reference.effects[index]
		var node: MeshInstance3D = effect.obj
		h._check(effect.type == "missile_smoke" and node.position.distance_to(BodyPose.vector(expected.position)) < .0003
			and node.scale.distance_to(BodyPose.vector(expected.scale)) < .0003, "Original missile smoke world anchor and scalar expansion")
		h._near(float(effect.ttl), float(expected.ttl), "Original missile puff remaining lifetime")
		h._near(float(effect.age), float(expected.age), "Original missile puff age")
		h._near(float(node.material_override.get_shader_parameter("opacity")), float(expected.opacity), "Original missile puff linear opacity fade")
