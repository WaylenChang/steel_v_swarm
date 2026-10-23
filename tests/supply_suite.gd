extends RefCounted

const StatusHelper = preload("res://tests/status_suite.gd")

class FixedRng extends SourceRng:
	var sample := 0.0
	var draws := 0

	func next() -> float:
		draws += 1
		return sample

class SupplySimulation extends BattleSimulation:
	var mode := "all"
	var points: Array = []
	var placement: Dictionary = {}

	func _missile_target_altitude(unit: BattleUnit) -> float:
		return float(unit.get_meta("relative_altitude", 0))

	func _airdrop_point() -> Dictionary:
		if mode == "integrated":
			return SceneRules.airdrop_point(rng, placement, func(_x, _z): return false)
		var point: Variant = points.pop_front() if not points.is_empty() else null
		return {} if point == null else point

class PickupSimulation extends SupplySimulation:
	var opened: Array = []

	func _open_airdrop(unit: BattleUnit, state: Dictionary) -> void:
		opened.append({"actor": unit.entity_id, "drop": state.id})

static func run(h: Node, fixtures: Dictionary) -> void:
	for key: String in ["supplySizes", "supplyPoints", "supplyWaves", "supplyRewards", "supplyPickups", "supplyOpen", "supplySnapshots", "supplyHeal", "supplyBossCaps", "supplyPower", "supplyPublic", "airdropVisuals"]:
		if not fixtures.has(key):
			h._check(false, "Regenerate original supply references before final verification: " + key)
			return
	for item: Dictionary in fixtures.supplySizes:
		var random := FixedRng.new()
		random.sample = item.sample
		StatusHelper.compare(h, SceneRules.airdrop_size(random), item.result, "Original weighted box size boundaries and fallback")
		h._check(random.draws == 1, "Box size consumes exactly one combat draw")
	for item: Dictionary in fixtures.supplyPoints:
		var random := SourceRng.new(int(item.seed))
		var blocked := func(_x, z): return item.terrain == "all" or item.terrain == "north" and z < 0
		var point := SceneRules.airdrop_point(random, item.state, blocked)
		if item.result == null:
			h._check(point.is_empty(), "Airdrop rejects exhausted placement without inventing a fallback")
		else:
			StatusHelper.compare(h, point, item.result, "Original airdrop bounds, lane/base/obstacle clearance and terrain order")
		check_draws(h, random, int(item.seed), int(item.draws))
	for item: Dictionary in fixtures.supplyWaves:
		var simulation := SupplySimulation.new()
		h.add_child(simulation)
		simulation.set_physics_process(false)
		simulation.clock = 10
		simulation.mode = item.mode
		simulation.points = item.points.duplicate(true)
		simulation.placement = item.state
		for id in range(int(item.players)):
			simulation.pilots[id] = null
		for id in range(int(item.live)):
			simulation.airdrops.append({"id": -id - 1})
		simulation._spawn_airdrop_wave()
		h._check(simulation.airdrops.size() == int(item.result.live), "Original player-count batch and live cap")
		var drops: Array = simulation.airdrops.slice(int(item.live)).map(func(drop): return {
			"x": drop.x, "z": drop.z, "size": drop.size, "multiplier": drop.multiplier, "ttl": drop.ttl, "land_at": drop.land_at})
		StatusHelper.compare(h, drops, item.result.drops, "Original source-ordered batch placement and size rolls")
		StatusHelper.compare(h, simulation.events, item.result.events, "Only successful drops announce a batch")
		check_draws(h, simulation.rng, 42, int(item.draws))
		simulation.free()
	for item: Dictionary in fixtures.supplyRewards:
		var simulation := SupplySimulation.new()
		h.add_child(simulation)
		simulation.set_physics_process(false)
		simulation.clock = 10
		var unit := actor(simulation, item.input)
		var random_state := simulation.rng.state
		StatusHelper.compare(h, simulation._grant_reward(unit, item.reward, item.multiplier), item.result, "Original reward quantities, nominal shield report and actual HP healing")
		compare_actor(h, unit, item.state)
		h._check(simulation.rng.state == random_state, "Granting a known reward consumes no combat draw")
		simulation.free()
	for item: Dictionary in fixtures.supplyPickups:
		var simulation := PickupSimulation.new()
		h.add_child(simulation)
		simulation.set_physics_process(false)
		simulation.clock = 10
		var first := actor(simulation, {"id": 1, "altitude": item.altitude})
		first.position.x = item.distance
		if item.dead:
			first.hp = 0
		actor(simulation, {"id": 2, "side": "SWARM"})
		for id in [50, 51]:
			simulation.airdrops.append({"id": id, "x": 0, "z": 0, "ttl": item.lifetime, "land_at": item.landAt})
		simulation._tick_airdrops(0.125)
		StatusHelper.compare(h, simulation.opened, item.opened, "Original landing gate, inclusive pickup height/radius and insertion-order winner")
		var remaining: Array = simulation.airdrops.map(func(drop): return {"id": drop.id, "ttl": drop.ttl})
		StatusHelper.compare(h, remaining, item.remaining, "Expiry precedes landing and pickup in reverse box order")
		simulation.free()
	for item: Dictionary in fixtures.supplyOpen:
		var simulation := SupplySimulation.new()
		h.add_child(simulation)
		simulation.set_physics_process(false)
		simulation.clock = 10
		simulation.rng = SourceRng.new(int(item.seed))
		var unit := actor(simulation)
		simulation._open_airdrop(unit, {"id": 50, "x": 12, "z": -8, "size": item.size, "multiplier": item.multiplier})
		h._check(simulation.events.size() == 1, "One opened crate produces one source reward event")
		if not simulation.events.is_empty():
			StatusHelper.compare(h, simulation.events[0], item.result.event, "Original equal-probability reward draw and size report")
		compare_actor(h, unit, item.result.state)
		check_draws(h, simulation.rng, int(item.seed), int(item.draws))
		simulation.free()
	for item: Dictionary in fixtures.supplySnapshots:
		var simulation := SupplySimulation.new()
		simulation.clock = 10
		simulation.airdrops.append({"id": 50, "x": item.x, "z": item.z, "size": "L", "land_at": item.landAt})
		StatusHelper.compare(h, simulation._airdrop_snapshot()[0], item.result, "Original public crate snapshot mirrors negative half-tie rounding and landing state")
		simulation.free()
	for item: Dictionary in fixtures.supplyBossCaps:
		h._near(StatusRules.boss_hp_cap(item.segment), item.result, "Original remaining boss-segment healing ceiling")
	for item: Dictionary in fixtures.supplyHeal:
		var simulation := SupplySimulation.new()
		h.add_child(simulation)
		simulation.set_physics_process(false)
		simulation.clock = 10
		var unit := actor(simulation, {"hp": item.hp, "boss": item.boss, "segment": item.segment})
		if not item.hero:
			unit.character = ""
			unit.kind = "soldier"
		h._near(simulation._heal_body(unit, item.amount, item.source), item.result.healed, "Original boss skill/item/source healing eligibility and amplifier")
		h._near(unit.hp, item.result.hp, "Original segmented healing cap does not restore broken segments")
		h._check(bool(unit.status.get("lightning_scorch", false)) == item.result.scorch, "Only real healing clears lightning scorch")
		simulation.free()
	for item: Dictionary in fixtures.supplyPower:
		var simulation := SupplySimulation.new()
		h.add_child(simulation)
		simulation.set_physics_process(false)
		simulation.clock = 10
		simulation.world = BattleWorld.new()
		simulation.add_child(simulation.world)
		simulation.world.bases = {"STEEL": Vector3(100000, 0, 0)}
		var unit := actor(simulation, {"hp": 2000, "shield": 300, "power": item.power})
		unit.wet = int(item.wet)
		unit.upgrades.ch = 2
		unit.damaged_at = 10
		simulation._regenerate(unit, item.delta)
		h._near(unit.power, item.result, "Original power regeneration preserves overcharge and fluid/charge factors")
		simulation.free()
	for item: Dictionary in fixtures.supplyPublic:
		var simulation := SupplySimulation.new()
		h.add_child(simulation)
		simulation.set_physics_process(false)
		simulation.clock = 10
		actor(simulation)
		simulation.events = item.events.duplicate(true)
		for event: Dictionary in simulation.events:
			if event.has("position"):
				event.position = Vector3(event.position[0], event.position[1], event.position[2])
		var packet := simulation.snapshot(1)
		StatusHelper.compare(h, packet.events.map(func(event): return event.type), item.types, "Original public supply and relay events survive missing/hidden actor filtering")
		simulation.free()
	var replica := SupplySimulation.new()
	h.add_child(replica)
	replica.set_physics_process(false)
	replica.authoritative = false
	var receiver := actor(replica)
	var balance := receiver.money
	var random_state := replica.rng.state
	h._check(replica._grant_reward(receiver, "money", 1).is_empty(), "Replica cannot settle supply rewards")
	replica._open_airdrop(receiver, {"size": "S", "multiplier": 1, "x": 0, "z": 0})
	h._check(receiver.money == balance and replica.rng.state == random_state and replica.events.is_empty(), "Replica cannot roll or open a crate")
	replica.free()
	var view := AirdropPresentation.new()
	h.add_child(view)
	view.set_process(false)
	for item: Dictionary in fixtures.airdropVisuals:
		view.sync([], item.born)
		view.sync([{"id": 1, "position": Vector3(12, 7, -8), "size": item.size, "landing": item.landing}], item.born)
		if not view.entries.has(1):
			h._check(false, "Pack original airdrop scenes before final visual verification")
			continue
		preload("res://tests/outline_suite.gd").check_deferred(h, view.entries[1].root)
		for step: Dictionary in item.steps:
			view.clock = float(step.now) - float(step.delta)
			view._process(step.delta)
			var entry: Dictionary = view.entries[1]
			check_vector(h, entry.root.position, step.position, "Original airdrop quadratic descent and zero-clock branch")
			check_vector(h, entry.root.rotation, step.rotation, "Only descending crates rotate their whole parachute")
			for name: String in ["crate", "chute", "groundChute", "halo"]:
				var node: Node3D = entry[name]
				h._check(node.visible == step.nodes[name].visible, "Source landing switches airborne/ground parachutes and halo")
				check_vector(h, node.position, step.nodes[name].position, "Original grounded crate bob leaves parachute and halo fixed")
				check_vector(h, node.rotation, step.nodes[name].rotation, "Original landed crate-only spin")
	view.sync([], 100)
	h._check(view.entries.is_empty(), "Opened or expired crates leave native presentation")
	view.free()
	print("SUPPLY_REFERENCE_PASS placement=", fixtures.supplyPoints.size(), " waves=", fixtures.supplyWaves.size(), " rewards=", fixtures.supplyRewards.size(), " pickup=", fixtures.supplyPickups.size(), " open=", fixtures.supplyOpen.size(), " heal=", fixtures.supplyHeal.size(), " power=", fixtures.supplyPower.size())

static func actor(simulation: BattleSimulation, input: Dictionary = {}) -> BattleUnit:
	var unit := StatusHelper.actor(simulation, {"id": input.get("id", 1), "character": "t05", "kind": "robot", "side": input.get("side", "STEEL"),
		"position": [0, 0, 0], "hp": input.get("hp", 100), "max_hp": 2000, "shield": input.get("shield", 100), "max_shield": 300,
		"power": input.get("power", 150), "max_power": 100, "relative_altitude": input.get("altitude", 0),
		"buffs": [{"until": 20, "key": "healAmp", "value": 1.4, "break_on_hit": false}]})
	unit.money = 10
	unit.cooldowns = {"def": 11.0, "atk": 35.0}
	unit.status.lightning_scorch = true
	if input.get("charged", true):
		unit.ability_charges = {"def": {"max": 2, "recharge_at": [8.0, 11.0, 40.0]}, "atk": {"max": 3, "recharge_at": []}}
	if input.get("boss", false):
		unit.special = {"boss": true, "boss_segment": input.get("segment", 1)}
	return unit

static func compare_actor(h: Node, unit: BattleUnit, expected: Dictionary) -> void:
	for property: String in ["hp", "shield", "power", "money"]:
		h._near(float(unit.get(property)), expected[property], "Original shared supply state: " + property)
	StatusHelper.compare(h, unit.cooldowns, expected.cooldowns, "Battery shortens absolute cooldown deadlines with a zero floor")
	StatusHelper.compare(h, unit.ability_charges, expected.charges, "Battery preserves charge rosters and clamps deadlines at current time")
	h._check(bool(unit.status.get("lightning_scorch", false)) == expected.scorch, "Supply healing clears scorch only when HP increases")

static func check_draws(h: Node, random: SourceRng, seed_value: int, count: int) -> void:
	var expected := SourceRng.new(seed_value)
	for index in range(count):
		expected.next()
	h._check(random.state == expected.state, "Source supply draw count includes rejected placement and successful box/reward rolls")

static func check_vector(h: Node, actual: Vector3, expected: Array, message: String) -> void:
	h._check(actual.distance_to(Vector3(expected[0], expected[1], expected[2])) < 0.00001, message)
