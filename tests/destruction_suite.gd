extends RefCounted

const Primitives = preload("res://tests/npc_shot_suite.gd")
const ViewTests = preload("res://tests/view_suite.gd")
const Helper = preload("res://tests/status_suite.gd")

class RecordedEffects extends CombatEffects:
	var calls: Array = []
	func _ready() -> void:
		blast_requested.connect(func(point, radius): _record("blast", point, {"radius": radius}))
	func _record(type: String, point: Vector3, settings: Dictionary) -> void:
		calls.append({"type": type, "point": [point.x, point.y, point.z]}.merged(settings))
	func explosion(point: Vector3, radius: float, color: int) -> void:
		_record("explosion", point, {"radius": radius, "color": color})
	func mechanical_debris(point: Vector3, big: bool = false, accent: Variant = null) -> void:
		_record("mechanical", point, {"big": big, "accent": accent})
	func comic(point: Vector3, big: bool = false, hue: Variant = null) -> void:
		_record("comic", point, {"big": big, "hue": hue})

class FlatWorld extends BattleWorld:
	func source_height(_x: float, _z: float) -> float:
		return 23.0

class PaddedEffects extends CombatEffects:
	func _pose(effect: Dictionary, fraction: float, delta: float = 0.0) -> void:
		if effect.obj != null:
			super._pose(effect, fraction, delta)
	func _drop(effect: Dictionary) -> void:
		if effect.obj != null:
			super._drop(effect)

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("mechanicalDebris") or not fixtures.has("comicPops") or not fixtures.has("deathPrimitives") or not fixtures.has("sceneBursts") or not fixtures.has("collapseFrames") or not Content.balance.has("destruction"):
		h._check(false, "Regenerate original mechanical debris, comic textures and fade references")
		return
	var effects := PaddedEffects.new()
	h.add_child(effects)
	for mode: String in ["mechanicalDebris", "comicPops", "sceneBursts"]:
		for item: Dictionary in fixtures[mode]:
			var draws := {"count": 0}
			var samples: Array = item.get("random", [.5])
			effects.random_sample = func():
				var value := float(samples[int(draws.count) % samples.size()])
				draws.count += 1
				return value
			effects.low_power = item.get("low", false)
			for index in range(int(item.get("padding", 0))):
				effects.effects.append({"obj": null, "ttl": 100.0, "duration": 100.0, "age": 0.0})
			if mode == "mechanicalDebris":
				effects.mechanical_debris(BodyPose.vector(item.point), item.big, item.accent)
			elif mode == "sceneBursts":
				var random_state := effects.visual_random.state
				effects.scene_damage_burst(int(item.id), item.kind, BodyPose.vector(item.point), float(item.height), float(item.radius), int(item.stage))
				h._check(effects.visual_random.state == random_state, "Scenery chunks use their own ID/stage stream without consuming the visual RNG")
			else:
				effects.comic(BodyPose.vector(item.point), item.big, item.hue)
			h._check(int(draws.count) == int(item.draws), "Original debris/comic admission and private random draw order")
			_compare(h, effects, item.initial, mode)
			for step: Dictionary in item.steps:
				effects.advance(float(step.delta))
				h._check(effects.effects.size() == step.count, "Original shared effect cap, expiry and reverse-order retirement")
				_compare(h, effects, step.effects, mode)
			for effect: Dictionary in effects.effects:
				effects._drop(effect)
			effects.effects.clear()
	h._check(effects.free_nodes.comic.size() <= int(Content.balance.npcShots.limits.pools.comic), "Retained comic nodes respect the original pool budget")
	var held: int = effects.free_nodes.comic.size()
	for index in range(int(Content.balance.npcShots.limits.pools.comic) + 5):
		effects.comic(Vector3.ZERO)
	effects.advance(1)
	h._check(effects.effects.is_empty() and effects.free_nodes.comic.size() == int(Content.balance.npcShots.limits.pools.comic),
		"Comic overflow recycles its bounded free stack and retires excess native nodes")
	h._check(held >= 1, "Repeated comic fixtures exercise retained sprite reuse")
	effects.free()
	_dispatch(h, fixtures)
	_collapse(h, fixtures)

static func _collapse(h: Node, fixtures: Dictionary) -> void:
	var effects := PaddedEffects.new()
	h.add_child(effects)
	for item: Dictionary in fixtures.collapseFrames:
		var target := Node3D.new()
		h.add_child(target)
		target.rotation_order = EULER_ORDER_XYZ
		target.scale = BodyPose.vector(item.scale)
		target.rotation = BodyPose.vector(item.rotation)
		effects.scene_collapse(target, int(item.id), item.instant)
		for index in range(item.frames.size()):
			var frame: Dictionary = item.frames[index]
			if item.evict and index == 1:
				for padding in range(int(Content.balance.npcShots.limits.maximum)):
					effects.effects.append({"obj": null, "ttl": 100.0, "duration": 100.0, "age": 0.0})
			effects.advance(float(frame.delta))
			Primitives._point(h, target.scale, frame.scale, "Original collapse uses shared zero-delta/frozen effect time and finalizes on eviction")
			Primitives._point(h, target.rotation, frame.rotation, "Original deterministic collapse direction and source Euler pose")
		for effect: Dictionary in effects.effects:
			effects._drop(effect)
		effects.effects.clear()
		target.free()
	var removed := Node3D.new()
	h.add_child(removed)
	effects.scene_collapse(removed, 42)
	removed.free()
	effects.advance(1)
	h._check(effects.effects.is_empty(), "Removing a collapsing target safely retires its presentation controller")
	effects.free()
	for authoritative: bool in [true, false]:
		var simulation := BattleSimulation.new()
		simulation.authoritative = authoritative
		h.add_child(simulation)
		simulation.set_physics_process(false)
		var world := BattleWorld.new()
		simulation.world = world
		simulation.add_child(world)
		var output := PaddedEffects.new()
		world.combat_effects = output
		world.add_child(output)
		var unit := BattleUnit.new()
		unit.entity_id = 42
		unit.kind = "car"
		unit.geometry_override = {"height": 6.0, "radius": 12.0}
		simulation.add_child(unit)
		unit.model = Node3D.new()
		unit.model.rotation_order = EULER_ORDER_XYZ
		unit.add_child(unit.model)
		var resources := [unit.hp, unit.shield, unit.power, unit.money, simulation.clock, simulation.rng.state, simulation.projectile_rng.state]
		var random_state := output.visual_random.state
		unit.apply_collapse()
		var count := output.effects.size()
		unit.apply_collapse()
		h._check(count == 3 and output.effects.size() == count, "Authority and replica collapse allocate one controller, seeded debris burst and shock")
		output.advance(0)
		h._check(unit.model.scale == Vector3.ONE, "Frozen presentation time cannot advance scenery collapse")
		output.advance(1)
		var final_scale := unit.model.scale
		unit.apply_collapse()
		h._check(final_scale == unit.model.scale and output.effects.size() == 1, "Repeated collapsed publications neither compound the pose nor restart the effects")
		h._check(resources == [unit.hp, unit.shield, unit.power, unit.money, simulation.clock, simulation.rng.state, simulation.projectile_rng.state]
			and output.visual_random.state == random_state, "Scenery collapse is presentation-only with an isolated per-ID debris stream")
		simulation.free()

static func _dispatch(h: Node, fixtures: Dictionary) -> void:
	var recorder := RecordedEffects.new()
	h.add_child(recorder)
	for item: Dictionary in fixtures.deathPrimitives:
		recorder.calls.clear()
		recorder.death({"kind": item.kind, "side": item.side, "position": BodyPose.vector(item.point)}, float(item.ground))
		Helper.compare(h, recorder.calls, item.calls, "Original death kind, faction accent, exact producer order and terrain-based height")
	recorder.free()
	for authoritative: bool in [true, false]:
		var simulation := BattleSimulation.new()
		simulation.authoritative = authoritative
		h.add_child(simulation)
		var world := FlatWorld.new()
		simulation.world = world
		simulation.add_child(world)
		var output := RecordedEffects.new()
		world.combat_effects = output
		world.add_child(output)
		var notifications := {"count": 0}
		simulation.death_presented.connect(func(_event): notifications.count += 1)
		var resources := [simulation.clock, simulation.rng.state, simulation.projectile_rng.state]
		var report := {"type": "die", "actor": 4, "kind": "tower", "side": "STEEL", "position": Vector3(12, 81, -9), "death_serial": 3}
		simulation.present_world_events([report])
		var calls := output.calls.duplicate(true)
		h._check(not calls.is_empty() and notifications.count == 1, "Shared offline/replica receiver produces death effects for an already removed actor")
		simulation.present_world_events([report])
		report.death_serial = 2
		simulation.present_world_events([report])
		h._check(output.calls == calls and notifications.count == 1, "Duplicate/older death reports cannot allocate debris, comic or restart hitstop")
		h._check(resources == [simulation.clock, simulation.rng.state, simulation.projectile_rng.state],
			"Death presentation never settles authority time or consumes either combat RNG stream")
		simulation.free()

static func _compare(h: Node, effects: CombatEffects, expected: Array, mode: String) -> void:
	var actual: Array = effects.effects.filter(func(effect): return effect.obj != null)
	h._check(actual.size() == expected.size(), "Original mechanical burst or comic count")
	for index in range(mini(actual.size(), expected.size())):
		var effect: Dictionary = actual[index]
		var reference: Dictionary = expected[index]
		var node: Node3D = effect.obj
		h._near(float(effect.ttl), reference.ttl, "Original destruction effect remaining life")
		h._near(float(effect.age), reference.age, "Original destruction effect age")
		Primitives._point(h, node.position, reference.position, "Original destruction effect world anchor")
		Primitives._point(h, node.scale, reference.scale, "Original comic overshoot and initial sprite scale")
		if mode == "sceneBursts" and reference.batches == null:
			var material := (node as MeshInstance3D).material_override as ShaderMaterial
			h._near(float(material.get_shader_parameter("opacity")), reference.opacity, "Original scenery shock-ring fade")
			Primitives._point(h, material.get_shader_parameter("tint"), reference.color, "Original scenery shock-ring profile colour")
			continue
		if mode == "comicPops":
			var material := (node as MeshInstance3D).material_override as ShaderMaterial
			h._near(float(material.get_shader_parameter("opacity")), reference.opacity, "Original comic last-30-percent opacity")
			h._near(float(material.get_shader_parameter("roll")), reference.roll, "Original comic private random rotation")
			var texture := material.get_shader_parameter("spark_texture") as Texture2D
			h._check(texture.resource_path.ends_with("combat-%s.png" % reference.texture), "Original randomly selected text and requested hue texture")
			continue
		var debris := node as MechanicalDebris
		var batches: Array = debris.batches.filter(func(batch): return batch.visible)
		h._check(batches.size() == reference.batches.size(), "Original low-power two-batch versus four-batch debris topology")
		for batch_index in range(mini(batches.size(), reference.batches.size())):
			var batch: MultiMeshInstance3D = batches[batch_index]
			var row: Dictionary = reference.batches[batch_index]
			h._check(batch.multimesh.instance_count == row.matrices.size(), "Original per-shape chunk distribution")
			for slot in range(mini(batch.multimesh.instance_count, row.matrices.size())):
				var native := batch.multimesh.get_instance_transform(slot)
				var source := ViewTests.frame(row.matrices[slot])
				h._check(native.origin.distance_to(source.origin) < .0003 and native.basis.x.distance_to(source.basis.x) < .0001
					and native.basis.y.distance_to(source.basis.y) < .0001 and native.basis.z.distance_to(source.basis.z) < .0001,
					"Original chunk semi-implicit gravity, floor bounce, per-axis spin and end-of-life shrink")
				var color := batch.multimesh.get_instance_color(slot)
				Primitives._point(h, Vector3(color.r, color.g, color.b), row.colors[slot], "Original linear debris palette and fourth-chunk accent")
