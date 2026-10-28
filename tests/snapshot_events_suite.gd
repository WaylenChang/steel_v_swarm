extends RefCounted

# The original snapshotFor/_frame oracle exercises event publication separately
# from geometry and rendering. Units deliberately have no meshes or terrain.
static func context(h: Node, item: Dictionary) -> BattleSimulation:
	var simulation := BattleSimulation.new()
	h.add_child(simulation)
	simulation.set_physics_process(false)
	simulation.clock = 12.3
	if item.pulse:
		simulation.vision_until = {"STEEL": 20.0, "SWARM": 20.0}
	for actor: Dictionary in item.actors:
		var unit := BattleUnit.new()
		unit.entity_id = int(actor.id)
		unit.kind = "soldier"
		unit.side = actor.side
		unit.hp = 100
		unit.max_hp = 100
		simulation.add_child(unit)
		unit.position = Vector3(actor.x, 0, actor.z)
		simulation.units[unit.entity_id] = unit
	var points: Array = []
	for point: Dictionary in item.input.pts:
		var native := {"id": int(point.get("id", 0)), "position": Vector3(point.x, point.y, point.z)}
		if point.get("absolute", false):
			native.absolute = true
		points.append(native)
	simulation.events = [{"type": "lightning_strike", "actor": 0, "points": points}]
	return simulation

static func source_points(points: Array) -> Array:
	var result: Array = []
	for point: Dictionary in points:
		var position: Vector3 = point.position
		var original := {"x": position.x, "y": position.y, "z": position.z}
		if point.get("absolute", false):
			original.absolute = true
		else:
			original.id = float(point.id)
		result.append(original)
	return result

static func check_packet(h: Node, packet: Dictionary, expected: Dictionary) -> void:
	var ids: Array = packet.units.map(func(actor): return int(actor.id))
	h._check(ids == expected.visible.map(func(id): return int(id)), "Original fog still filters units independently of public weather events")
	var reports: Array = []
	for event: Dictionary in packet.events:
		if event.type == "lightning_strike":
			reports.append({"e": event.type, "pts": source_points(event.points)})
	h._check(reports == expected.events, "Original shared event frame retains empty, hidden, removed and absolute lightning points in order")

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("snapshotEvents"):
		h._check(false, "Regenerate original snapshotFor event references")
		return
	for item: Dictionary in fixtures.snapshotEvents:
		var simulation := context(h, item)
		simulation.events.append({"type": "screen_hurt", "actor": 71, "only_peer": 42})
		var seed := simulation.rng.state
		var serial := -1
		for expected: Dictionary in item.snapshots:
			var packet := simulation.snapshot(0, "" if expected.side == null else expected.side)
			check_packet(h, packet, expected)
			h._check(packet.events.all(func(event): return not event.has("only_peer")), "Global weather publication never opens the owner-only event boundary")
			if not packet.events.is_empty():
				var report: Dictionary = packet.events[0]
				if serial < 0:
					serial = int(report.notice_serial)
				h._check(int(report.notice_serial) == serial, "All recipients retain one notice identity for a source report")
				if not report.points.is_empty():
					report.points[0].position.x = 999999
			h._check(source_points(simulation.events[0].points) == item.input.pts, "A recipient cannot mutate the authority report or another recipient's points")
		var owned := simulation.snapshot(42, "STEEL")
		h._check(owned.events.any(func(event): return event.get("only_peer", 0) == 42), "Owner-specific notices retain their original recipient")
		h._check(simulation.rng.state == seed and item.remaining == 0, "Source frame drains once; native publication leaves the combat random stream unchanged")
		simulation.free()
	print("SNAPSHOT_EVENT_REFERENCE_PASS programs=", fixtures.snapshotEvents.size())
