extends RefCounted

class FlatWorld extends BattleWorld:
	func ground_height(_x: float, _z: float) -> float:
		return 0

# Exercise actual cast/report producers while isolating terrain and settlement.
class CastSimulation extends BattleSimulation:
	var accepted := false
	func _missile_target_altitude(unit: BattleUnit) -> float:
		return unit.position.y
	func _ability_origin(_unit: BattleUnit, _slot: String) -> Vector3:
		return Vector3(-100, 0, -200)
	func _launch_carriers(_unit: BattleUnit, _definition: Dictionary, _point: Vector3, _origin: Vector3) -> void:
		pass
	func _cast_effect(_unit: BattleUnit, _definition: Dictionary, _center: Vector3, _fraction: float = 1.0, _once: bool = true, _count: int = -1) -> void:
		pass

static func context(h: Node, item: Dictionary) -> CastSimulation:
	var simulation := CastSimulation.new()
	h.add_child(simulation)
	simulation.set_physics_process(false)
	simulation.world = FlatWorld.new()
	simulation.clock = 10
	if item.pulse:
		simulation.vision_until = {"STEEL": 20.0, "SWARM": 20.0}
	var other := BattleUnit.new()
	other.entity_id = 71
	other.kind = "soldier"
	other.side = "SWARM" if item.side == "STEEL" else "STEEL"
	other.hp = 100
	other.max_hp = 100
	simulation.add_child(other)
	simulation.units[71] = other
	var unit := BattleUnit.new()
	unit.entity_id = 72
	unit.peer_id = 42
	unit.character = item.character
	unit.kind = Content.heroes[item.character].kind
	unit.side = item.side
	unit.hp = 100
	unit.max_hp = 100
	unit.power = 100000
	unit.defending = true
	unit.lock_target = 71
	simulation.add_child(unit)
	unit.position = Vector3(10000, 12, -10000)
	simulation.units[72] = unit
	simulation.pilots[42] = unit
	simulation.accepted = simulation.cast(unit, "atk" if item.action == "attack" else "def", Vector3(10008, 0, -10000))
	simulation.clock = item.now
	if item.action == "interrupt":
		simulation._interrupt_cast(unit)
	elif item.action == "complete":
		simulation._tick_casts(0)
	if item.removed:
		simulation.units.erase(72)
	return simulation

static func dispose(simulation: BattleSimulation) -> void:
	simulation.world.free()
	simulation.free()

static func check_event(h: Node, actual: Dictionary, expected: Dictionary) -> void:
	const FIELDS := {"e": "type", "ch": "character", "side": "side", "slot": "slot", "fx": "fx",
		"r": "radius", "dur": "duration", "lvl": "level", "frac": "fraction", "interrupted": "interrupted",
		"carrier": "carrier", "castDur": "cast_duration"}
	h._check(int(actual.get("actor", 0)) == 72 and expected.pid == "42", "Cast report retains the source actor/owner identity mapping after removal")
	for key: String in expected:
		if key == "pid":
			continue
		var value: Variant
		if key in ["x", "z", "ox", "oz"]:
			var point: Variant = actual.get("origin" if key.begins_with("o") else "point")
			if point is Vector3:
				value = point.x if key.ends_with("x") else -point.z
		else:
			value = actual.get(FIELDS.get(key, key))
		if expected[key] is float or expected[key] is int:
			h._check(value != null and absf(float(value) - float(expected[key])) < .00001, "Original cast report numeric field " + key)
		else:
			h._check(value == expected[key], "Original cast report field " + key)

static func check_packet(h: Node, packet: Dictionary, expected: Dictionary) -> void:
	h._check(packet.units.map(func(unit): return int(unit.id)) == expected.visible.map(func(id): return int(id)), "Cast publication preserves source unit fog filtering")
	var events: Array = packet.events.filter(func(event): return event.type in ["cast", "cast_start"] and not event.has("only_peer"))
	h._check(events.size() == expected.events.size(), "Hidden and removed casters retain every original report in order")
	for index in mini(events.size(), expected.events.size()):
		check_event(h, events[index], expected.events[index])

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("castEvents"):
		h._check(false, "Regenerate original cast producer/snapshot references")
		return
	for item: Dictionary in fixtures.castEvents:
		var simulation := context(h, item)
		h._check(simulation.accepted, "Native active cast producer accepts the original character and slot")
		var private: Dictionary = simulation.events[0].duplicate(true)
		private.only_peer = 99
		simulation.events.append(private)
		var seed := simulation.rng.state
		var serials: Array = []
		for expected: Dictionary in item.snapshots:
			var packet := simulation.snapshot(0, "" if expected.side == null else expected.side)
			check_packet(h, packet, expected)
			h._check(packet.events.all(func(event): return not event.has("only_peer")), "Public casts never bypass explicit owner-only recipients")
			var current: Array = packet.events.map(func(event): return event.notice_serial)
			if serials.is_empty():
				serials = current
			h._check(current == serials, "Repeated cast recipients share stable event identities")
			if not packet.events.is_empty():
				packet.events[0].point.x = -99999
			h._check(simulation.events[0].point.x != -99999, "Cast event snapshots cannot mutate authority coordinates")
		h._check(simulation.snapshot(99, item.side).events.any(func(event): return event.get("only_peer") == 99), "Explicit cast recipient remains eligible regardless of actor visibility")
		h._check(simulation.rng.state == seed, "Recipient publication does not consume combat RNG")
		dispose(simulation)
	print("CAST_EVENT_REFERENCE_PASS programs=", fixtures.castEvents.size())
