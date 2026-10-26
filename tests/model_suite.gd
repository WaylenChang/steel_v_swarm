class_name ModelSuite
extends RefCounted

static func run(h: Node, fixtures: Variant) -> void:
	var cases: Array = fixtures.modelCentres if fixtures is Dictionary else fixtures
	var actor: BattleUnit
	var previous := ""
	var changed_centres := {}
	for fixture: Dictionary in cases:
		var key: String = fixture.character + fixture.kind + fixture.side
		if key != previous:
			if actor != null:
				actor.free()
			actor = BattleUnit.new()
			h.add_child(actor)
			var special := {}
			var companion_key: String = fixture.side.to_lower() + "_" + fixture.kind
			if Content.balance.get("companions", {}).has(companion_key):
				if fixture.kind in ["decoy", "hyper"]:
					special = {"role": "carrier", "model_key": companion_key, "hp": Content.balance.carrier.hp[fixture.kind]}
				else:
					special.role = "hologram" if fixture.kind == "decoy_beacon" else "summon"
			actor.configure({"id": 99001, "kind": fixture.kind, "character": fixture.character,
				"side": fixture.side, "position": Vector3.ZERO, "special": special})
			previous = key
		actor.position = h._reference_vector(fixture.position)
		var expected: Vector3 = h._reference_vector(fixture.point)
		h._check(actor.aim_point().distance_to(expected) < 0.00001, "Original measured model centre: " + key)
		actor.rotation = Vector3(0.2, 1.2, -0.3)
		actor.flying = not actor.flying
		h._check(actor.aim_point().distance_to(expected) < 0.00001, "Source cached centre ignores body rotation and morph state")
		if not fixture.character.is_empty() and absf(fixture.dimensions.centre - actor.height / 2) > 0.01:
			changed_centres[fixture.character] = true
	if actor != null:
		actor.free()
	h._check(changed_centres.has("s10") and changed_centres.has("t06") and changed_centres.has("m08"),
		"Source weapons and dual-form geometry produce centres outside normalized height halves")
	await acquisition(h)

static func acquisition(h: Node) -> void:
	var sim := BattleSimulation.new()
	h.add_child(sim)
	sim.set_physics_process(false)
	sim.world = BattleWorld.new()
	sim.add_child(sim.world)
	var map_data := Content.map_variant(0, 1)
	map_data.erase("native_world")
	await sim.world.build(map_data, {"time": "day", "weather": "clear"})
	var actor := sim.spawn({"peer": 801, "side": "STEEL", "character": "t09", "kind": Content.heroes.t09.kind, "position": Vector3(0, 80, 0)})
	var target := sim.spawn({"peer": 802, "side": "SWARM", "character": "m08", "kind": Content.heroes.m08.kind, "position": Vector3(0, 80, -100)})
	sim.pilots[801] = actor
	sim.pilots[802] = target
	actor.input_state = {"aim": true, "slot": "heavy"}
	var offset := target.aim_point() - actor.view_origin()
	actor.yaw = 0
	actor.pitch = atan2(offset.y, -offset.z) + Content.balance.targeting.coneAngle - 0.0005
	await h.get_tree().physics_frame
	await h.get_tree().physics_frame
	var maximum := TargetingMath.maximum_range(Content.weapon(actor.character, "heavy"))
	h._check(sim._projectile_aim(actor, maximum).target == null, "Measured-centre boundary fixture misses the exact physical ray")
	h._check(sim._aim_target(actor, maximum) == target, "Native cone includes the original measured centre at its angular boundary")
	var proxy := {"id": target.entity_id, "hero": true, "point": target.position + Vector3.UP * target.height / 2}
	h._check(TargetingMath.cone_acquire(actor.position, actor.view_origin(), actor.aim_direction(), maximum, [proxy]) == 0,
		"Normalized cylinder midpoint would incorrectly reject the same source target")
	var advice: Dictionary = sim.snapshot(801).reachability
	h._check(not advice.is_empty() and advice.target == target.entity_id and advice.ok,
		"Private FNF advice follows the measured-centre cone selection")
	sim.queue_free()
	await h.get_tree().process_frame
