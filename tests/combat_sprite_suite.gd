extends RefCounted

const Helper = preload("res://tests/status_suite.gd")
const Primitives = preload("res://tests/npc_shot_suite.gd")
const ViewTests = preload("res://tests/view_suite.gd")

class PaddedEffects extends CombatEffects:
	func _pose(effect: Dictionary, fraction: float, delta: float = 0.0) -> void:
		if effect.obj != null:
			super._pose(effect, fraction, delta)
	func _drop(effect: Dictionary) -> void:
		if effect.obj != null:
			super._drop(effect)

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("combatSprites") or not Content.balance.npcShots.limits.prewarm.has("sprite_fire"):
		h._check(false, "Regenerate original combat sprite textures, pool budgets and lifecycle references")
		return
	var effects := PaddedEffects.new()
	h.add_child(effects)
	for item: Dictionary in fixtures.combatSprites:
		var draw := {"count": 0}
		effects.random_sample = func():
			var value := float(item.random[int(draw.count) % item.random.size()])
			draw.count += 1
			return value
		for index in range(int(item.padding)):
			effects.effects.append({"obj": null, "ttl": 100.0, "duration": 100.0, "age": 0.0})
		var point := BodyPose.vector(item.point)
		match item.method:
			"embers": effects.embers(point, int(item.variant), 2)
			"smoke": effects.crash_smoke(point, 1.4)
			"plume": effects.death_plume(point)
			"engulf": effects.engulf(ViewTests.frame(item.camera))
		h._check(int(draw.count) == int(item.draws), "Original sprite producers consume only their private visual random samples in source order")
		_compare(h, effects, item.initial, item.initialPools)
		for step: Dictionary in item.steps:
			effects.advance(float(step.delta))
			h._check(effects.effects.size() == step.count, "Original global FX budget evicts oldest sprites before reverse-order stepping")
			_compare(h, effects, step.effects, step.pools)
		for effect: Dictionary in effects.effects:
			effects._drop(effect)
		effects.effects.clear()
	effects.free()

static func _compare(h: Node, effects: CombatEffects, expected: Array, pools: Dictionary) -> void:
	var actual: Array = effects.effects.filter(func(effect): return effect.obj != null)
	h._check(actual.size() == expected.size(), "Original ember/smoke/plume count, expiry and delayed admission")
	for index in range(mini(actual.size(), expected.size())):
		var effect: Dictionary = actual[index]
		var reference: Dictionary = expected[index]
		Primitives._effect(h, effect, reference.merged({"roll": 0.0}))
		Primitives._point(h, effect.velocity, reference.velocity, "Original per-frame ember gravity versus constant smoke drift")
		h._near(float(effect.ttl), reference.ttl, "Original sprite remaining life")
		h._near(float(effect.age), reference.age, "Original sprite accumulated frame time")
		h._near(float(effect.get("delay", 0)), reference.delay, "Original smoke delay is a normalized life fraction")
		h._check((effect.key == "sprite_fire") == reference.fire, "Original fire/smoke texture and blending pool remain distinct")
	for key: String in ["fire", "smoke"]:
		h._check(effects.free_nodes["sprite_" + key].size() == int(pools[key]), "Original prewarm/free-stack cap and overflow recycling: " + key)
