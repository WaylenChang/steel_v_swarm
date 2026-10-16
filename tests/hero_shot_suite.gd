extends RefCounted

const Primitives = preload("res://tests/npc_shot_suite.gd")
const Helper = preload("res://tests/status_suite.gd")
const FallbackTests = preload("res://tests/fan_fallback_suite.gd")

class EffectWorld extends BattleWorld:
	func clip_shot(_origin: Vector3, target: Vector3) -> Dictionary:
		return {"to": target, "cut": false}

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("heroShotEffects") or not AuthoredCombatEffect.available():
		h._check(false, "Regenerate and pack original hero discharge/fan scenes and references")
		return
	var effects := CombatEffects.new()
	h.add_child(effects)
	effects.random_sample = func(): return .25
	for item: Dictionary in fixtures.heroShotEffects:
		for index in range(int(item.padding)):
			effects.effects.append({"obj": null})
		var queries: Array = []
		var clip := func(origin: Vector3, target: Vector3):
			var obstruction := func(start: Vector3, end: Vector3):
				if item.scenario != "wall" or start.z == end.z:
					return {}
				var fraction := (30.0 - start.z) / (end.z - start.z)
				return {"position": start.lerp(end, fraction)} if fraction >= 0 and fraction <= 1 else {}
			var result := NpcShotMotion.clip(origin, target, obstruction)
			queries.append({"from": origin, "to": target, "result": result})
			return result
		var origin := BodyPose.vector(item.origin)
		if item.kind == "fan":
			var accepted := effects.fan(origin, BodyPose.vector(item.direction), item.definition, item.definition.range, clip)
			h._check(accepted == item.accepted, "Original authored fan admission, zero direction and crowded-list gates")
		else:
			effects.lance(origin, clip.call(origin, BodyPose.vector(item.target)).to, item.definition, int(item.color))
		h._check(queries.size() == item.queries.size(), "Original fan per-vertex ray-query count and short-circuit ordering")
		for index in range(mini(queries.size(), item.queries.size())):
			var actual: Dictionary = queries[index]
			var expected: Dictionary = item.queries[index]
			Primitives._point(h, actual.from, expected.from, "Original fan ray origin")
			Primitives._point(h, actual.to, expected.to, "Original clamped fan vertex before obstacle clipping")
			Primitives._point(h, actual.result.to, expected.result.to, "Original fan obstacle-backoff endpoint")
			h._check(actual.result.cut == expected.result.cut, "Original fan obstacle cut decision")
		var created: Array = effects.effects.slice(int(item.padding))
		h._check(created.size() == item.initial.size(), "Original authored discharge, payload, EMP and nested budget branching")
		for index in range(mini(created.size(), item.initial.size())):
			h._near(created[index].ttl, item.initial[index].ttl, "Original EMP delay extends only the release effects, preserving the full-width channel")
			_effect(h, created[index], item.initial[index])
		for step: Dictionary in item.steps:
			for index in range(mini(created.size(), step.effects.size())):
				effects._pose(created[index], maxf(0, 1 - float(step.progress)))
				_effect(h, created[index], step.effects[index])
		for effect: Dictionary in created:
			effects._drop(effect)
		effects.effects.clear()
	effects.free()
	_ion_effects(h, fixtures)
	FallbackTests.run(h, fixtures)
	_production_events(h, fixtures.heroShotEffects)
	_terminal_events(h, fixtures)

static func _ion_effects(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("ionBreathEffects"):
		h._check(false, "Regenerate original authored/procedural ion breath references")
		return
	var effects := CombatEffects.new()
	h.add_child(effects)
	effects.random_sample = func(): return .25
	for item: Dictionary in fixtures.ionBreathEffects:
		effects.low_power = item.low
		for index in range(int(item.padding)):
			effects.effects.append({"obj": null})
		effects.ion(BodyPose.vector(item.origin), BodyPose.vector(item.target), 0x7fe8ff, 2.2, .45, float(item.coil), 0xfff3d0,
			{} if item.definition == null else item.definition)
		var created: Array = effects.effects.slice(int(item.padding))
		h._check(created.size() == item.initial.size(), "Original ion authored preference, zero length and nested crowded-list gates")
		for index in range(mini(created.size(), item.initial.size())):
			h._near(created[index].ttl, item.initial[index].ttl, "Original throat/core/coil/arc lifetimes")
			_effect(h, created[index], item.initial[index])
		for step: Dictionary in item.steps:
			for index in range(mini(created.size(), step.effects.size())):
				effects._pose(created[index], maxf(0, 1 - float(step.progress)))
				_effect(h, created[index], step.effects[index])
		for effect: Dictionary in created:
			effects._drop(effect)
		effects.effects.clear()
	effects.free()

static func _terminal_events(h: Node, fixtures: Dictionary) -> void:
	var seen := {}
	for item: Dictionary in fixtures.kineticFlight:
		if not item.has("presentation"):
			h._check(false, "Regenerate original kinetic terminal presentation references")
			return
		if item.presentation.is_empty() or seen.has(item.character):
			continue
		seen[item.character] = true
		var source: Dictionary = item.presentation[0]
		h._check(item.presentation.size() == 1, "Original penetrating flight produces one final presentation from its launch port")
		var simulation := BattleSimulation.new()
		h.add_child(simulation)
		simulation.set_physics_process(false)
		simulation.world = EffectWorld.new()
		simulation.add_child(simulation.world)
		var owner := Helper.actor(simulation, {"id": 1, "character": source.character, "side": source.side, "position": source.origin,
			"hp": 700, "shield": 120, "power": 80, "ammo": {"light": 4, "heavy": 2}})
		var resources := [owner.hp, owner.shield, owner.power, owner.ammo.duplicate(), owner.fire_serial,
			simulation.rng.state, simulation.projectile_rng.state]
		var view := simulation.world.ensure_projectile_visuals()
		view.sync_rounds([{"id": "1/2", "key": "%s-%s-steel" % [source.character, source.slot],
			"position": BodyPose.vector(source.origin), "velocity": BodyPose.vector(item.velocity), "age": 0}], 9)
		var event := {"type": "projectile_terminal", "actor": owner.entity_id, "slot": source.slot, "side": source.side,
			"start": BodyPose.vector(source.origin), "end": BodyPose.vector(source.point), "level": source.level,
			"body_serial": 4, "visual_id": "1/2", "clock": 10}
		simulation.present_projectile_terminal(event)
		h._check(view.rounds.is_empty() and view.retired_rounds.has("1/2"), "Original terminal endpoint retires its actual visual identity")
		var effects := simulation.world.combat_effects
		h._check(effects != null and not effects.effects.is_empty(), "Original kinetic endpoint reaches the shared lance presentation")
		var count := effects.effects.size()
		simulation.receive_body_events([event], 10)
		simulation.present_world_events([event])
		h._check(effects.effects.size() == count, "Immediate/snapshot terminal replay cannot allocate a second channel or payload")
		var later := event.duplicate()
		later.body_serial = 5
		later.visual_id = "1/1"
		simulation.present_projectile_terminal(later)
		h._check(effects.effects.size() > count, "A later terminal event for an older launched projectile remains valid")
		h._check(resources == [owner.hp, owner.shield, owner.power, owner.ammo, owner.fire_serial,
			simulation.rng.state, simulation.projectile_rng.state], "Terminal presentation does not repeat authority penetration damage or spending")
		simulation.free()
	h._check(not seen.is_empty(), "Original kinetic references cover physical penetration terminal presentation")

static func _production_events(h: Node, cases: Array) -> void:
	for kind: String in ["fan", "line"]:
		var matches: Array = cases.filter(func(item): return item.kind == kind and item.level == 1 and item.scenario == "clear" and not item.initial.is_empty())
		h._check(not matches.is_empty(), "Original hero references cover the production " + kind + " event route")
		if matches.is_empty():
			continue
		var item: Dictionary = matches[0]
		var simulation := BattleSimulation.new()
		h.add_child(simulation)
		simulation.set_physics_process(false)
		simulation.world = EffectWorld.new()
		simulation.add_child(simulation.world)
		var owner := Helper.actor(simulation, {"id": 1, "character": item.character, "side": "STEEL", "position": item.origin,
			"hp": 700, "shield": 120, "power": 80, "ammo": {"light": 4, "heavy": 2}})
		var resources := [owner.hp, owner.shield, owner.power, owner.ammo.duplicate(), owner.money, owner.fire_serial,
			simulation.rng.state, simulation.projectile_rng.state]
		simulation.present_shot({"type": "shot", "actor": owner.entity_id, "slot": item.slot, "side": owner.side,
			"area": kind, "level": 1, "start": BodyPose.vector(item.origin), "end": BodyPose.vector(item.target),
			"direction": BodyPose.vector(item.direction), "range": item.definition.range})
		h._check(simulation.world.combat_effects != null and not simulation.world.combat_effects.effects.is_empty(),
			"Live hero shot snapshots reach the shared native authored effect list")
		h._check(resources == [owner.hp, owner.shield, owner.power, owner.ammo, owner.money, owner.fire_serial,
			simulation.rng.state, simulation.projectile_rng.state], "Hero shot presentation cannot spend ammo/power or advance authority damage/RNG")
		if kind == "fan":
			owner.peer_id = 2
			var before := simulation.world.combat_effects.effects.size()
			var report := {"type": "plasma", "plasma_report": true, "body_serial": 10, "actor": owner.entity_id, "slot": item.slot, "side": owner.side,
				"start": BodyPose.vector(item.origin), "direction": BodyPose.vector(item.direction), "radius": item.definition.range}
			simulation.receive_body_events([report], 10)
			h._check(simulation.world.combat_effects.effects.size() > before, "Bot/remote plasma reports use the same authored fan driver")
			var count := simulation.world.combat_effects.effects.size()
			simulation.receive_body_events([report], 10)
			simulation.present_world_events([report])
			h._check(simulation.world.combat_effects.effects.size() == count and owner.remote_burst_driven,
				"Immediate/snapshot plasma copies cannot duplicate discharge or enable private echo posing")
			h._check(resources == [owner.hp, owner.shield, owner.power, owner.ammo, owner.money, owner.fire_serial,
				simulation.rng.state, simulation.projectile_rng.state], "Remote plasma presentation cannot settle combat a second time")
		simulation.free()

static func _effect(h: Node, effect: Dictionary, reference: Dictionary) -> void:
	if effect.type not in ["authored_discharge", "authored_fan", "lance_projectile"]:
		Primitives._effect(h, effect, reference)
		return
	var node: Node3D = effect.obj
	h._check(effect.type == reference.type and node.visible == reference.visible, "Original authored release identity and delayed visibility")
	Primitives._point(h, node.position, reference.position, "Original authored release origin/travel")
	Primitives._point(h, node.scale, reference.scale, "Original authored release radius/envelope")
	if absf(node.scale.x * node.scale.y * node.scale.z) > .000000000000000001:
		h._check(absf(node.quaternion.dot(BodyPose.quaternion(reference.quaternion))) > .999999, "Original authored release orientation")
	var meshes: Array[MeshInstance3D] = []
	_meshes(node, meshes)
	h._check(meshes.size() == reference.meshes.size(), "Original authored release part count")
	for index in range(mini(meshes.size(), reference.meshes.size())):
		var mesh: MeshInstance3D = meshes[index]
		var expected: Dictionary = reference.meshes[index]
		Primitives._point(h, mesh.position, expected.position, "Original release attachment position")
		Primitives._point(h, mesh.scale, expected.scale, "Original release attachment scale")
		var material := mesh.get_active_material(0)
		if material is ShaderMaterial:
			h._near(float(material.get_shader_parameter("opacity")), expected.opacity, "Original source clip opacity envelope")
			var tint: Vector3 = material.get_shader_parameter("tint")
			h._check(int(Color(tint.x, tint.y, tint.z).linear_to_srgb().to_rgba32() >> 8) == int(expected.color), "Original authored material colour")
		else:
			h._near((material as BaseMaterial3D).albedo_color.a, expected.opacity, "Original lance payload retains source default zero-age tail animation")
		var arrays := mesh.mesh.surface_get_arrays(0)
		if expected.has("vertices"):
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			h._check(vertices.size() * 3 == expected.vertices.size(), "Original authored vertex count")
			for vertex in range(vertices.size()):
				Primitives._point(h, vertices[vertex], expected.vertices.slice(vertex * 3, vertex * 3 + 3), "Original authored normalized/clipped vertex")
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			h._check(indices.size() == expected.indices.size(), "Original authored triangle count")
			for triangle in range(0, indices.size(), 3):
				h._check(indices[triangle] == int(expected.indices[triangle]) and indices[triangle + 1] == int(expected.indices[triangle + 2])
					and indices[triangle + 2] == int(expected.indices[triangle + 1]), "Original triangle topology preserves Godot front-face winding")
		if expected.has("colors"):
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var sweep: bool = material.get_shader_parameter("sweep")
			var time := float(material.get_shader_parameter("sweep_time")) if sweep else 0.0
			var count := float(material.get_shader_parameter("sweep_bins")) if sweep else 1.0
			h._check(uv.size() * 3 == expected.colors.size(), "Every authored fan vertex retains its brightness-owner attribute")
			for vertex in range(uv.size()):
				var weight := maxf(.06, 1 - absf(time - float(uv[vertex].x) / count * .55 - .12) / .22) if sweep else 1.0
				h._check(absf(weight - float(expected.colors[vertex * 3])) < .000001, "Original sweep brightness follows its source bin without rotating the clipped cone")

static func _meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		result.append(node)
	for child: Node in node.get_children():
		_meshes(child, result)
