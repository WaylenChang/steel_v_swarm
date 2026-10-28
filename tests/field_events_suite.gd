extends RefCounted

const REPORTS := ["cube_spawn", "fog_spawn", "phase_start", "phase_exit", "decoy_beacon_spawn", "flashbang_detonate", "heal_aoe"]

# Isolate source field lifecycles and publication from mesh construction,
# populated terrain, damage settlement and decorative rendering.
class FlatWorld extends BattleWorld:
	func ground_height(_x: float, _z: float) -> float:
		return 0

class FieldSimulation extends BattleSimulation:
	func _missile_target_altitude(unit: BattleUnit) -> float:
		return unit.position.y
	func _auto_target(_companion: BattleUnit, _owner: BattleUnit) -> BattleUnit:
		return null
	func _apply_cc(_owner: BattleUnit, _added: Dictionary, _center: Vector3, _radius: float) -> void:
		pass
	func blast(_unit: BattleUnit, _definition: Dictionary, _impact: Vector3, _friendly: bool = false, _relative: bool = false, _level: int = -1, _damage: float = NAN) -> void:
		pass
	func spawn(info: Dictionary, _replica: bool = false) -> BattleUnit:
		var unit := BattleUnit.new()
		unit.entity_id = next_id
		next_id += 1
		unit.kind = info.kind
		unit.side = info.side
		unit.special = info.special.duplicate(true)
		unit.hp = unit.special.get("hp", 100)
		unit.max_hp = unit.hp
		unit.hit_area = Area3D.new()
		unit.add_child(unit.hit_area)
		add_child(unit)
		unit.position = info.position
		units[unit.entity_id] = unit
		return unit

static func context(h: Node, item: Dictionary) -> FieldSimulation:
	var simulation := FieldSimulation.new()
	h.add_child(simulation)
	simulation.set_physics_process(false)
	simulation.world = FlatWorld.new()
	simulation.next_id = 80
	simulation.clock = 10
	if item.pulse:
		simulation.vision_until = {"STEEL": 1000.0, "SWARM": 1000.0}
	var other := BattleUnit.new()
	other.entity_id = 71
	other.kind = "soldier"
	other.side = "SWARM" if item.side == "STEEL" else "STEEL"
	other.hp = 1000
	other.max_hp = 1000
	simulation.add_child(other)
	simulation.units[71] = other
	var unit := BattleUnit.new()
	unit.entity_id = 72
	unit.peer_id = 42
	unit.character = item.character
	unit.kind = Content.heroes[item.character].kind
	unit.side = item.side
	unit.hp = 1000
	unit.max_hp = 1000
	unit.shield = 30
	unit.max_shield = 500
	unit.power = 1000
	unit.max_power = 1000
	unit.upgrades = {"light": item.level - 1, "heavy": item.level - 1, "def": item.level - 1, "atk": item.level - 1}
	simulation.add_child(unit)
	unit.position = Vector3(10000, 0, -10000)
	simulation.units[72] = unit
	simulation.pilots[42] = unit
	simulation._cast_effect(unit, Content.ability(item.character, item.slot, item.level), unit.position, item.fraction)
	return simulation

static func advance(simulation: FieldSimulation, item: Dictionary, index: int) -> void:
	simulation.clock = item.frames[index].now
	if index > 0:
		simulation.events.clear()
		if index == 1 and item.termination == "lethal":
			if item.fx == "phaseshift":
				simulation.pilots[42].hp = 0
			else:
				for id: int in simulation.hologram_decoys:
					simulation.units[id].hp = 0
		match item.fx:
			"phaseshift": simulation._tick_phase_shift(0)
			"decoy_beacon": simulation._tick_holograms(0)
			"cube": simulation._tick_cubic_slabs(0)
			"fog": simulation._tick_fogs(0)
	if item.removed:
		simulation.units.erase(72)

static func check_lifecycle(h: Node, simulation: FieldSimulation, frame: Dictionary) -> void:
	h._check(simulation.units.keys().filter(func(id): return id >= 80) == frame.fields.map(func(id): return int(id)), "Original field body removal order and inclusive expiry")
	h._check(simulation.cubic_cages.size() == int(frame.cubes) and simulation.fogs.size() == int(frame.fogs) and simulation.hologram_decoys.size() == int(frame.holograms), "Original persistent field collection cleanup")
	h._check(bool(simulation.pilots[42].status.get("phase_until", 0)) == frame.phase, "Phase expiry and owner death clear the original state once")

static func check_packet(h: Node, packet: Dictionary, expected: Dictionary) -> void:
	# Field body representations have dedicated geometry/identity fixtures. Here
	# compare the common owner/observer roster and public effect report fields.
	var shared: Array = packet.units.filter(func(unit): return int(unit.id) in [71, 72]).map(func(unit): return int(unit.id))
	h._check(shared == expected.visible.map(func(id): return int(id)), "Field events do not open source owner visibility")
	var reports: Array = packet.events.filter(func(event): return event.type in REPORTS and not event.has("only_peer"))
	h._check(reports.size() == expected.events.size(), "Every source field report survives hidden or removed actors; consumed frames do not replay")
	for index in mini(reports.size(), expected.events.size()):
		var actual: Dictionary = reports[index]
		var source: Dictionary = expected.events[index]
		h._check(actual.type == source.e, "Source field report traversal order")
		for key: String in ["side", "r", "dur", "x", "z"]:
			if not source.has(key):
				continue
			var value: Variant
			if key in ["x", "z"]:
				var point: Variant = actual.get("position")
				if point is Vector3:
					value = point.x if key == "x" else -point.z
			else:
				value = actual.get({"r": "radius", "dur": "duration"}.get(key, key))
			if key == "side":
				h._check(value == source[key], "Source field report side")
			else:
				h._check(value != null and absf(float(value) - float(source[key])) < .00001, "Source field report scalar " + key)

static func dispose(simulation: FieldSimulation) -> void:
	simulation.world.free()
	simulation.free()

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("fieldEvents"):
		h._check(false, "Regenerate original field event/lifecycle references")
		return
	for item: Dictionary in fixtures.fieldEvents:
		var simulation := context(h, item)
		for index in item.frames.size():
			advance(simulation, item, index)
			var frame: Dictionary = item.frames[index]
			check_lifecycle(h, simulation, frame)
			var private := {"type": "flashbang_detonate", "actor": 0, "only_peer": 99, "position": Vector3.ZERO, "radius": 1.0}
			simulation.events.append(private)
			var seed := simulation.rng.state
			var serials: Array = []
			for expected: Dictionary in frame.snapshots:
				var packet := simulation.snapshot(0, "" if expected.side == null else expected.side)
				check_packet(h, packet, expected)
				h._check(packet.events.all(func(event): return not event.has("only_peer")), "Public field reports preserve explicit private recipients")
				var current: Array = packet.events.filter(func(event): return event.type in REPORTS).map(func(event): return event.notice_serial)
				if serials.is_empty():
					serials = current
				h._check(current == serials, "Repeated recipients share the same field report identities")
			h._check(simulation.snapshot(99, item.side).events.any(func(event): return event.get("only_peer") == 99), "Field report owner-only recipient remains eligible")
			h._check(simulation.rng.state == seed, "Field publication does not consume combat random draws")
		dispose(simulation)
	print("FIELD_EVENT_REFERENCE_PASS programs=", fixtures.fieldEvents.size())
