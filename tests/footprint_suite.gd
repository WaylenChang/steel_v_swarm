class_name FootprintSuite
extends RefCounted

static func run(h: Node, fixtures: Array) -> void:
	for fixture: Dictionary in fixtures:
		var targets: Array = fixture.targets.duplicate(true)
		for target: Dictionary in targets:
			target.position = h._reference_vector(target.position)
		var crosshair: Dictionary = fixture.crosshair.duplicate(true)
		crosshair.point = h._reference_vector(crosshair.point)
		var control: Dictionary = fixture.control.duplicate(true)
		if not control.is_empty():
			control.impact = h._reference_vector(control.impact)
			control.aim = h._reference_vector(control.aim)
		var collision := func(start: Vector3, end: Vector3) -> Dictionary:
			for target: Dictionary in targets:
				if target.get("cut") != null and end.distance_to(ShotFootprintMath.centre(target)) < 0.0001:
					return {"position": start + (end - start).normalized() * target.cut}
			return {}
		var result := ShotFootprintMath.evaluate(Content.weapon(fixture.character, fixture.slot, int(fixture.level)),
			h._reference_vector(fixture.origin), h._reference_vector(fixture.forward), targets, crosshair, control, collision)
		var label: String = fixture.character + " " + fixture.slot + ": " + fixture.name
		h._check(result.is_empty() == fixture.result.is_empty(), "Original shot footprint presence: " + label)
		if not result.is_empty() and not fixture.result.is_empty():
			var expected: Array[int] = []
			for id in fixture.result.hits:
				expected.append(int(id))
			h._check(result.hits == expected, "Original ordered footprint targets: " + label + " actual=" + str(result.hits) + " expected=" + str(expected))
			h._check(result.warn == fixture.result.warn, "Original whole-shot footprint warning: " + label)
	await authority(h)

static func authority(h: Node) -> void:
	var sim := BattleSimulation.new()
	h.add_child(sim)
	var map_data := Content.map_variant(0, 1)
	map_data.erase("native_world")
	await sim.setup(map_data, [{"peer": 901, "side": "STEEL", "character": "t09", "bot": false}], {"time": "day", "weather": "clear"}, true)
	sim.set_physics_process(false)
	var actor: BattleUnit = sim.pilots[901]
	for unit: BattleUnit in sim.units.values():
		if unit != actor:
			unit.hp = 0
	actor.position = Vector3(0, 80, 0)
	actor.input_state = {"aim": true, "slot": "heavy"}
	var front := sim.spawn({"kind": "soldier", "side": "SWARM", "position": Vector3(0, 80, -30)})
	var rear := sim.spawn({"kind": "soldier", "side": "SWARM", "position": Vector3(0, 80, -35)})
	var observer := sim.spawn({"kind": "soldier", "side": "STEEL", "position": Vector3(0, 80, -45)})
	var offset := front.aim_point() - actor.eye()
	actor.pitch = atan2(offset.y, -offset.z)
	actor.yaw = 0
	var wall := StaticBody3D.new()
	wall.position = Vector3(0, 80, -32.5)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(10, 8, 0.1)
	collider.shape = shape
	wall.add_child(collider)
	sim.world.add_child(wall)
	await h.get_tree().physics_frame
	await h.get_tree().physics_frame
	var rng_state := sim.rng.state
	var projectile_rng_state := sim.projectile_rng.state
	var ammo: float = actor.ammo.heavy
	var power := actor.power
	var hp := rear.hp
	var footprint: Dictionary = sim.snapshot(901).footprint
	h._check(not footprint.is_empty() and footprint.hits.has(front.entity_id) and footprint.hits.has(rear.entity_id),
		"Native blast footprint includes a visible rear victim behind a wall")
	h._check(footprint.warn, "Near arming warns the entire native blast roster")
	h._check(not sim.visible_to(actor, rear) and sim.visible_to_side(rear, actor.side), "Rear blast footprint uses shared sight without adding an LOS gate")
	h._check(sim.snapshot().footprint.is_empty(), "Global snapshots contain no private footprint")
	actor.input_state.aim = false
	h._check(sim.snapshot(901).footprint.is_empty(), "Heavy weapons requiring aim never advertise a footprint after aim release")
	actor.input_state.aim = true
	h._near(actor.ammo.heavy, ammo, "Footprint never spends ammunition")
	h._near(actor.power, power, "Footprint never spends power")
	h._near(rear.hp, hp, "Footprint never settles damage")
	h._check(sim.rng.state == rng_state and sim.projectile_rng.state == projectile_rng_state, "Footprint never consumes either RNG")
	sim.apply_footprint(footprint)
	h._check(sim.footprint_glows.active.size() == 2, "Native billboards display every blast victim")
	var glow: MeshInstance3D = sim.footprint_glows.active[front.entity_id]
	var dimensions := front.visual_dimensions()
	var style: Dictionary = Content.balance.footprintGlow
	h._near(glow.position.y, dimensions.centre, "Glow uses original measured centre")
	h._check(absf(glow.scale.x - maxf(style.minimumSize, maxf(dimensions.height, dimensions.radius * 2) * style.sizeFactor)) < 0.00001, "Glow uses original footprint size")
	h._check(glow.material_override == sim.footprint_glows.warning and sim.footprint_glows.warning.no_depth_test,
		"Warning glow shares additive depth-independent material")
	sim.apply_footprint(footprint, {"anchor": front.entity_id})
	h._check(sim.footprint_glows.active.size() == 1 and sim.footprint_glows.pool.size() == 1, "Confirmed anchor excludes duplicate weapon glow and returns it to the pool")
	sim.apply_footprint(footprint)
	h._check(sim.footprint_glows.active[front.entity_id] == glow, "Returning victim reuses its pooled billboard")
	sim.apply_footprint({})
	h._check(sim.footprint_glows.active.is_empty() and sim.footprint_glows.pool.size() == 2, "Empty footprint removes all active glows")
	observer.hp = 0
	await h.get_tree().physics_frame
	footprint = sim.snapshot(901).footprint
	h._check(not footprint.is_empty() and not footprint.hits.has(rear.entity_id), "Hidden rear victims never leak through private footprint IDs")
	wall.queue_free()
	front.position.z = -20
	rear.position.z = -40
	actor.character = "t04"
	actor.kind = Content.heroes.t04.kind
	actor.height = Content.heroes.t04.height
	offset = front.aim_point() - actor.eye()
	actor.pitch = atan2(offset.y, -offset.z)
	await h.get_tree().physics_frame
	await h.get_tree().physics_frame
	footprint = sim.snapshot(901).footprint
	h._check(not footprint.is_empty() and footprint.hits.has(front.entity_id) and footprint.hits.has(rear.entity_id),
		"Native line footprint passes the first body and lists both penetration victims")
	h._check(not footprint.warn, "Line footprints never inherit blast arming warnings")
	actor.character = "t01"
	actor.kind = Content.heroes.t01.kind
	actor.height = Content.heroes.t01.height
	offset = front.aim_point() - actor.eye()
	actor.pitch = atan2(offset.y, -offset.z)
	var side_target := sim.spawn({"kind": "soldier", "side": "SWARM", "position": Vector3(5, 80, -30)})
	await h.get_tree().physics_frame
	await h.get_tree().physics_frame
	footprint = sim.snapshot(901).footprint
	h._check(not footprint.is_empty() and footprint.hits.has(front.entity_id) and footprint.hits.has(side_target.entity_id) and not footprint.hits.has(rear.entity_id),
		"Native fan footprint lists independent side bins while the front body screens the rear")
	actor.character = "t03"
	actor.kind = Content.heroes.t03.kind
	actor.height = Content.heroes.t03.height
	offset = front.aim_point() - actor.eye()
	actor.pitch = atan2(offset.y, -offset.z)
	var control := sim.lob_control(actor, Content.weapon(actor.character, "heavy"))
	sim.fire_controls[actor.entity_id] = control
	footprint = sim.snapshot(901).footprint
	h._check(not footprint.is_empty() and footprint.hits.has(front.entity_id), "Native lob footprint consumes the current cached fire-control impact")
	actor.upgrades.hw += 1
	h._check(sim.snapshot(901).footprint.is_empty(), "Changed weapon tier never uses an obsolete lob footprint")
	sim.apply_footprint(footprint)
	front.queue_free()
	sim.units.erase(front.entity_id)
	await h.get_tree().process_frame
	sim.apply_footprint({})
	h._check(sim.footprint_glows.active.is_empty(), "Freed target billboards are removed without stale object access")
	sim.queue_free()
	await h.get_tree().process_frame
