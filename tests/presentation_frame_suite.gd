extends RefCounted

class FlatWorld extends BattleWorld:
	func source_height(_x: float, _z: float) -> float:
		return 0.0

static func run(h: Node, fixtures: Dictionary) -> void:
	for key: String in ["presentationFrameDeaths", "presentationFrameTraces", "presentationFrameReports"]:
		if not fixtures.has(key):
			h._check(false, "Regenerate original hitstop and queued frame references")
			return
	for item: Dictionary in fixtures.presentationFrameDeaths:
		var frame := PresentationFrame.new()
		frame.receive({"kind": item.kind, "death_serial": 1})
		h._near(frame.advance(.016), .016, "A newly applied source death freezes the following frame")
		h._near(frame.remaining, item.remaining, "Original death kind/physical scenery stop gate: " + item.kind)
	for trace: Array in fixtures.presentationFrameTraces:
		var frame := PresentationFrame.new()
		var serial := 0
		for item: Dictionary in trace:
			if item.has("kind"):
				serial += 1
				frame.receive({"kind": item.kind, "death_serial": serial})
			h._near(frame.advance(item.raw), item.delta, "Original capped frame budget and complete crossing-frame freeze")
			h._near(frame.remaining, item.remaining, "Original maximum stop overlap, zero frame and signed remainder")
	for item: Dictionary in fixtures.presentationFrameReports:
		var authority := BattleSimulation.new()
		h.add_child(authority)
		var target := BattleUnit.new()
		authority.add_child(target)
		target.entity_id = int(item.target.id)
		target.kind = item.target.kind
		target.side = item.target.side
		target.position = Vector3(item.target.x, 0, -float(item.target.z))
		target.hit_area = Area3D.new()
		target.add_child(target.hit_area)
		authority._kill_unit(target, null)
		var deaths: Array = authority.events.filter(func(event): return event.type == "die")
		h._check(deaths.size() == 1, "Normal lethal settlement publishes exactly one original death event")
		if deaths.size() == 1:
			var event: Dictionary = deaths[0]
			h._check(event.actor == int(item.event.id) and event.kind == item.event.kind and event.side == item.event.side,
				"Source death identity survives native authority publication")
			h._check(event.position == Vector3(item.event.x, 0, -float(item.event.z)) and event.death_serial == 1,
				"Source planar death position mirrors once and receives a room-local replay serial")
		var viewer := BattleUnit.new()
		viewer.peer_id = 9
		viewer.side = "SWARM"
		authority.add_child(viewer)
		authority.pilots[9] = viewer
		var published: Dictionary = authority.snapshot(9)
		h._check(published.units.is_empty() and published.events.size() == item.visibleEvents.size(),
			"Source death reports reach the other faction after the actor is absent from visible entities")
		authority.free()
	var frame := PresentationFrame.new()
	var simulation := BattleSimulation.new()
	h.add_child(simulation)
	simulation.world = FlatWorld.new()
	simulation.add_child(simulation.world)
	simulation.death_presented.connect(frame.receive)
	var unit := BattleUnit.new()
	unit.entity_id = 4
	unit.kind = "tower"
	unit.hp = 50
	unit.shield = 20
	simulation.add_child(unit)
	var resources := [unit.hp, unit.shield, simulation.rng.state, simulation.projectile_rng.state, simulation.clock]
	simulation._report_death(unit)
	simulation.present_world_events(simulation.events)
	h._check(frame.pending.size() == 1, "Production publication carries the authority death serial to native presentation")
	frame.advance(.016)
	var remaining := frame.remaining
	simulation.present_world_events(simulation.events)
	h._check(frame.pending.is_empty() and frame.remaining == remaining, "Snapshot replay cannot renew a stop")
	frame.advance(1)
	h._check(frame.remaining < 0, "A long rendered frame spends only the source cap and retains its signed remainder")
	h._check(frame.advance(1) == float(Content.balance.view.frameCap), "The next frame resumes with the source cap")
	h._check(resources == [unit.hp, unit.shield, simulation.rng.state, simulation.projectile_rng.state, simulation.clock],
		"Presentation stops never settle authority resources, RNG or simulation time")
	frame.clear()
	h._check(frame.remaining == 0 and frame.last_serial == -1 and frame.pending.is_empty(), "Room replacement resets stop and replay state")
	simulation.free()
