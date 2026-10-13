class_name ReachabilitySuite
extends RefCounted

static func run(h: Node, fixtures: Array) -> void:
	for fixture: Dictionary in fixtures:
		var definition := Content.weapon(fixture.character, fixture.slot, int(fixture.level))
		var geometry: Node3D = null
		var collision: Callable
		if definition.reachRule.path == "arc":
			geometry = h._lob_geometry(fixture)
			await h.get_tree().physics_frame
			await h.get_tree().physics_frame
			collision = h._lob_collision
		else:
			collision = func(start: Vector3, end: Vector3) -> Dictionary:
				return {} if fixture.rayCut == null else {"position": start + (end - start).normalized() * fixture.rayCut}
		var target: Dictionary = fixture.target.duplicate(true)
		target.position = h._reference_vector(target.position)
		var actual := ReachabilityMath.evaluate(definition, h._reference_vector(fixture.origin), target, fixture.range, collision)
		var label: String = fixture.character + " " + fixture.slot + ": " + fixture.name
		h._check(actual.ok == fixture.result.ok, "Original reachability geometry: " + label)
		h._check(actual.warn == fixture.result.warn, "Original reachability warning: " + label)
		if geometry != null:
			geometry.free()
	await authority(h)

static func authority(h: Node) -> void:
	var sim := BattleSimulation.new()
	h.add_child(sim)
	var map_data := Content.map_variant(0, 1)
	map_data.erase("native_world")
	await sim.setup(map_data, [
		{"peer": 701, "side": "STEEL", "character": "t09", "bot": false},
		{"peer": 702, "side": "SWARM", "character": "s01", "bot": false}], {"time": "day", "weather": "clear"}, true)
	sim.set_physics_process(false)
	var actor: BattleUnit = sim.pilots[701]
	var target: BattleUnit = sim.pilots[702]
	actor.position = Vector3(0, 80, 0)
	target.position = Vector3(0, 80, -60)
	actor.input_state = {"aim": true, "slot": "heavy"}
	var offset := target.position + Vector3.UP * target.height / 2 - actor.eye()
	actor.yaw = atan2(-offset.x, -offset.z)
	actor.pitch = atan2(offset.y, Vector2(offset.x, offset.z).length())
	await h.get_tree().physics_frame
	await h.get_tree().physics_frame
	var ammo: float = actor.ammo.heavy
	var power := actor.power
	var rng_state := sim.rng.state
	var projectile_rng_state := sim.projectile_rng.state
	var advice: Dictionary = sim.snapshot(701).reachability
	h._check(not advice.is_empty() and advice.target == target.entity_id and advice.slot == "heavy" and advice.ok,
		"Authority publishes target-specific reachability to the aiming pilot")
	h._near(actor.ammo.heavy, ammo, "Advisory query never spends ammunition")
	h._near(actor.power, power, "Advisory query never spends power")
	h._check(sim.rng.state == rng_state and sim.projectile_rng.state == projectile_rng_state,
		"Advisory query never consumes either combat RNG stream")
	h._check(sim.snapshot().reachability.is_empty(), "Global snapshots omit private reachability")
	target.position = Vector3(0, 80, -10)
	offset = target.position + Vector3.UP * target.height / 2 - actor.eye()
	actor.pitch = atan2(offset.y, Vector2(offset.x, offset.z).length())
	await h.get_tree().physics_frame
	advice = sim.snapshot(701).reachability
	h._check(not advice.is_empty() and advice.ok and advice.warn, "Native guided arming distance warns while retaining reachability")
	target.position.z = -1500
	await h.get_tree().physics_frame
	h._check(sim.snapshot(701).reachability.is_empty(), "Hidden or out-of-search-range targets never leak advisory IDs")
	actor.hp = 0
	h._check(sim.snapshot(701).reachability.is_empty(), "Dead pilots receive no aiming advice")
	actor.hp = actor.max_hp
	for character in ["t04", "s04"]:
		actor.character = character
		h._check(sim.snapshot(701).reachability.is_empty(), "Fan/line footprints never use a single-target entrance gate")
	actor.character = "s01"
	target.position = Vector3(0, 80, -100)
	actor.yaw = 0.08
	offset = target.position + Vector3.UP * target.height / 2 - actor.eye()
	actor.pitch = atan2(offset.y, Vector2(offset.x, offset.z).length())
	await h.get_tree().physics_frame
	await h.get_tree().physics_frame
	for slot in ["light", "heavy"]:
		actor.input_state.slot = slot
		var definition := Content.weapon(actor.character, slot)
		h._check(sim._aim_target(actor, TargetingMath.maximum_range(definition)) == target, "Off-ray control retains a valid cone target")
		h._check(sim.snapshot(701).reachability.is_empty(), "Flat/laser advice never promises a hit against an off-ray cone target")
	sim.queue_free()
	await h.get_tree().process_frame
