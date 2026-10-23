extends RefCounted

const Helper = preload("res://tests/status_suite.gd")

static func run(h: Node, fixtures: Dictionary) -> void:
	if not Content.balance.get("minimap", {}).has("fog") or not fixtures.has("minimapVision") or not fixtures.has("minimapBlockers") or not fixtures.has("minimapPulses"):
		h._check(false, "Regenerate original minimap sight, ordered tangent-shadow and pulse references")
		return
	for program: Dictionary in fixtures.minimapVision:
		var view: Dictionary = program.view.duplicate(true)
		view.point = Vector2(view.point[0], view.point[1])
		var rows: Array = []
		for row: Dictionary in program.rows:
			rows.append({"kind": row.kind, "side": row.side, "hero": row.hero, "peer": row.pid,
				"self": row.isSelf, "dead": row.dead, "hp": row.hp, "decoy": row.decoy, "lost": row.lost,
				"point": Vector2(row.point[0], row.point[1])})
		Helper.compare(h, MinimapVision.sources(rows, view), program.sources,
			"Original own/squad aim bonus, team/dead/lost exclusions, authored sight and shared weather fog factor")
	for program: Dictionary in fixtures.minimapBlockers:
		var entries: Array = []
		for index: float in program.references:
			entries.append(program.definitions[int(index)])
		var query := SourceBlockerQuery.new()
		query.configure(entries)
		for frame: Dictionary in program.queries:
			var point := Vector2(frame.point[0], frame.point[1])
			var blockers := query.near(point, frame.radius)
			Helper.compare(h, blockers.map(func(row): return row.tag), frame.tags,
				"Original ordered cell walk, circumscribed boxes, shared object identity and single-cell fast path")
			var shadows: Variant = MinimapVision.shadows(point, frame.radius, blockers)
			if frame.shadows == null:
				h._check(shadows == null, "No candidates preserve the original absent-shadow result")
			else:
				Helper.compare(h, shadows, frame.shadows, "Original tangent quads, radius/angular/range gates and ordered 96-shadow cap")
		query.configure([])
		h._check(query.near(Vector2.ZERO, 10).is_empty(), "Rebuilding blocker queries discards the previous world's entries")
	for program: Dictionary in fixtures.minimapPulses:
		var pulse := MinimapVision.new()
		pulse.pulse_until = program.initial
		var source: Dictionary = program.event
		var event := {"type": source.e, "side": source.side, "character": source.get("ch", ""),
			"slot": source.get("slot", ""), "level": source.get("lvl", 1),
			"fraction": source.get("frac", 1), "notice_serial": 1}
		pulse.observe(event, program.viewer, program.now)
		h._near(pulse.pulse_until, program.until, "Original relay replacement and full-duration accepted-level scout pulse")
		pulse.observe(event, program.viewer, program.now + 100)
		h._near(pulse.pulse_until, program.until, "Repeated snapshot events cannot extend a presentation pulse")
		pulse.clear()
		h._check(pulse.pulse_until == 0 and pulse.events_seen.last_serial == 0, "Room reset clears pulse state and its existing notice-serial filter")
	_cast_reports(h)

static func _cast_reports(h: Node) -> void:
	for interrupted in [false, true]:
		var simulation := Helper.ReferenceSimulation.new()
		h.add_child(simulation)
		simulation.set_physics_process(false)
		simulation.authoritative = true
		simulation.capture_interrupt = true
		simulation.clock = 13 if not interrupted else 11
		var unit := Helper.actor(simulation, {"id": 90073, "character": "t05", "side": "STEEL", "position": [0, 0, 0]})
		unit.cast_state = {"start": 10.0, "duration": 2.0, "slot": "def", "level": 1.0,
			"definition": Content.ability(unit.character, "def", 1), "point": Vector3.ZERO}
		unit.upgrades.def = 3
		if interrupted:
			simulation._interrupt_cast(unit)
		else:
			simulation._tick_ability_states(0)
		var reports := simulation.events.filter(func(event): return event.type == "cast")
		h._check(reports.size() == 1, "A timed defense produces one terminal public cast report")
		if reports.size() == 1:
			var public := ActorSnapshot.event(reports[0], false)
			h._check(public.level == 1 and unit.combat_level("def") == 4, "Completion/interruption reports retain the accepted cast level after an upgrade")
		simulation.free()
