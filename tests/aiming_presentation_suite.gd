extends RefCounted

const StatusHelper = preload("res://tests/status_suite.gd")

class PreviewSimulation extends BattleSimulation:
	func visible_to_side(unit: BattleUnit, _side: String) -> bool:
		return not unit.get_meta("hidden", false)

static func run(h: Node, fixtures: Dictionary) -> void:
	for key: String in ["skillFootprints", "lockGlowPoses", "lockWarnings", "footprintGlowStates"]:
		if not fixtures.has(key):
			h._check(false, "Regenerate original aiming presentation references: " + key)
			return
	for item: Dictionary in fixtures.skillFootprints:
		var targets: Array = item.targets.duplicate(true)
		for target: Dictionary in targets:
			target.position = vector(target.position)
		var result := ShotFootprintMath.skill_victims(item.definition, vector(item.centre), targets, "STEEL")
		StatusHelper.compare(h, result, item.result, "Original ordered skill preview " + item.character + "/" + item.slot)
	for item: Dictionary in fixtures.lockGlowPoses:
		StatusHelper.compare(h, LockGlowPresentation.pose(item.dimensions, item.now, item.hit_at), item.result,
			"Original lockGlow pulse, geometry centre, ring rotation and hit fade")
	for item: Dictionary in fixtures.lockWarnings:
		var until := LockGlowPresentation.warning_until(item.previous, item.event, int(item.viewer), item.now)
		h._near(until, item.until, "Original incoming-lock HUD deadline and own-lock precedence")
		for sample: Dictionary in item.visibility:
			h._check((float(sample.now) < until) == bool(sample.result), "Original incoming-lock warning inclusive expiry")
	preview_integration(h)
	_glow_visibility(h, fixtures.footprintGlowStates)
	print("AIMING_PRESENTATION_REFERENCE_PASS skills=", fixtures.skillFootprints.size(), " lockPoses=", fixtures.lockGlowPoses.size())

static func preview_integration(h: Node) -> void:
	var simulation := PreviewSimulation.new()
	h.add_child(simulation)
	simulation.set_physics_process(false)
	simulation.clock = 10
	var owner := actor(simulation, 1, "STEEL", Vector3.ZERO)
	owner.character = "t05"
	owner.kind = "robot"
	owner.power = 100
	owner.ammo = {"light": 9, "heavy": 4}
	simulation.pilots[owner.peer_id] = owner
	var enemy := actor(simulation, 2, "SWARM", Vector3(0, 100, -5))
	var ally := actor(simulation, 3, "STEEL", Vector3(0, 0, -5))
	var hidden := actor(simulation, 4, "SWARM", Vector3(0, 0, -5))
	hidden.set_meta("hidden", true)
	var garrison := actor(simulation, 5, "SWARM", Vector3(0, 0, -5))
	garrison.special.garrison = true
	var neutral := actor(simulation, 6, "", Vector3(0, 0, -5))
	neutral.special.neutral = true
	owner.cast_preview = {"definition": {"range": 10.0, "target": "enemy"}, "point": Vector3.ZERO, "until": 11.0}
	var rng_state := simulation.rng.state
	var spread_state := simulation.projectile_rng.state
	var preview := simulation._skill_footprint_snapshot(owner)
	h._check(preview.hits == [enemy.entity_id], "Skill footprint ignores altitude and excludes hidden/garrison/neutral actors")
	h._check(simulation._skill_footprint_snapshot(null).is_empty(), "Global snapshots cannot expose private skill preview")
	simulation.apply_skill_footprint(preview)
	simulation.apply_footprint({"hits": [enemy.entity_id], "warn": false, "side": "STEEL"})
	h._check(simulation.skill_glows.active.size() == 1 and simulation.footprint_glows.active.size() == 1,
		"Skill and weapon layers coexist independently")
	var skill: MeshInstance3D = simulation.skill_glows.active[enemy.entity_id]
	var normal: MeshInstance3D = simulation.footprint_glows.active[enemy.entity_id]
	var style: Dictionary = Content.balance.aimingPresentation.skillGlow
	h._check(skill.material_override != normal.material_override and skill.scale.x > normal.scale.x,
		"Skill preview has its own larger cyan material")
	h._near(skill.material_override.albedo_color.a, style.opacity, "Source skill opacity")
	h._check(simulation.apply_lock_glow({"target": enemy.entity_id, "anchor": enemy.entity_id}), "Confirmed anchor activates a new target glow")
	simulation.lock_glow.advance(1.25)
	h._check(simulation.lock_glow.global_transform == enemy.global_transform, "Lock follows the rendered actor pose")
	h._check(simulation.lock_glow.halo_material.albedo_color.is_equal_approx(Color(Content.side_info(enemy.side).color, simulation.lock_glow.halo_material.albedo_color.a)),
		"Lock uses the target faction color")
	h._check(simulation.lock_glow.halo_material.no_depth_test and not simulation.lock_glow.ring_material.no_depth_test,
		"Source lock halo sees through depth while its ground ring retains depth testing")
	simulation.apply_footprint({"hits": [enemy.entity_id], "warn": false, "side": "STEEL"}, {"anchor": enemy.entity_id})
	h._check(simulation.footprint_glows.active.is_empty() and simulation.skill_glows.active.size() == 1,
		"Confirmed lock removes only the duplicate weapon layer")
	var halo := simulation.lock_glow.halo
	h._check(not simulation.apply_lock_glow({"target": enemy.entity_id, "anchor": enemy.entity_id}), "Repeated lock packets do not allocate another glow")
	simulation.lock_glow.flash(1.25)
	simulation.lock_glow.advance(1.25)
	h._near(simulation.lock_glow.halo_material.albedo_color.a, 1.0, "Accepted hit brightens source lock pulse")
	simulation.lock_glow.advance(1.45)
	h._check(simulation.lock_glow.halo_material.albedo_color.a < 1.0, "Source lock hit flash expires at 200 ms")
	simulation.apply_lock_glow({})
	h._check(not simulation.lock_glow.visible and simulation.lock_glow.target_id == 0, "Cleared anchor removes lock presentation")
	simulation.apply_lock_glow({"target": enemy.entity_id, "anchor": enemy.entity_id})
	h._check(simulation.lock_glow.halo == halo, "Lock presentation reuses its native geometry")
	enemy.presentation_visible = false
	simulation.lock_glow.advance(2)
	h._check(not simulation.lock_glow.visible, "Hidden target cannot retain a lock halo")
	enemy.presentation_visible = true
	owner.cast_preview.definition.target = "team"
	preview = simulation._skill_footprint_snapshot(owner)
	h._check(preview.hits == [owner.entity_id, ally.entity_id], "Allied preview can include the caster without a weapon target")
	simulation.apply_footprint({})
	simulation.apply_skill_footprint(preview)
	h._check(simulation.skill_glows.active.size() == 2, "Weapon clearing does not remove active team-cast preview")
	owner.upgrades.def = 3
	h._check(simulation._skill_footprint_snapshot(owner).hits == preview.hits, "Upgrading during cast keeps the accepted preview definition")
	simulation.clock = 11
	h._check(simulation._skill_footprint_snapshot(owner).is_empty(), "Skill preview expires at its inclusive cast deadline")
	simulation.apply_skill_footprint({})
	h._check(simulation.skill_glows.active.is_empty(), "Finished casts recycle all skill sprites")
	simulation.clock = 10
	owner.hp = 0
	h._check(simulation._skill_footprint_snapshot(owner).is_empty(), "Dead caster cannot retain a private preview")
	owner.hp = 100
	simulation.over = true
	h._check(simulation._skill_footprint_snapshot(owner).is_empty(), "Finished match clears the private preview")
	h._near(owner.power, 100, "Aiming presentation cannot spend power")
	h._check(owner.ammo == {"light": 9, "heavy": 4} and enemy.hp == 100, "Aiming presentation cannot spend ammo or damage bodies")
	h._check(simulation.rng.state == rng_state and simulation.projectile_rng.state == spread_state, "Aiming presentation cannot consume combat or spread RNG")
	simulation.over = false
	simulation.apply_lock_glow({"target": enemy.entity_id, "anchor": enemy.entity_id})
	simulation.units.erase(enemy.entity_id)
	enemy.free()
	simulation.lock_glow.advance(3)
	h._check(simulation.lock_glow.target_id == 0 and not simulation.lock_glow.visible, "Freed target clears lock without stale object access")
	simulation.free()

static func _glow_visibility(h: Node, fixtures: Array) -> void:
	var simulation := PreviewSimulation.new()
	h.add_child(simulation)
	simulation.set_physics_process(false)
	for id in [1, 2, 3]:
		actor(simulation, id, "SWARM", Vector3.ZERO)
	for item: Dictionary in fixtures:
		for id: int in simulation.units:
			simulation.units[id].special.siege_locked = item.locked.any(func(value): return int(value) == id)
		var weapon := {"hits": item.hits, "side": "STEEL", "warn": false} if item.hits != null else {}
		var skill := {"hits": item.skills, "side": "STEEL", "warn": false} if item.casting else {}
		simulation.apply_footprint(weapon, {"anchor": item.anchor})
		simulation.apply_skill_footprint(skill)
		var weapon_ids: Array = simulation.footprint_glows.active.keys()
		var skill_ids: Array = simulation.skill_glows.active.keys()
		weapon_ids.sort()
		skill_ids.sort()
		StatusHelper.compare(h, weapon_ids, item.weapon, "Original weapon glows exclude siege locks and the separate lock anchor after victim math")
		StatusHelper.compare(h, skill_ids, item.skill, "Original skill glows remain independent of siege locks, weapon availability and the lock anchor")
	h._check(simulation.footprint_glows.active.is_empty() and simulation.skill_glows.active.is_empty(),
		"Ending the shot and cast returns both native glow layers to their pools")
	simulation.free()

static func actor(simulation: BattleSimulation, id: int, side: String, position: Vector3) -> BattleUnit:
	var unit := BattleUnit.new()
	simulation.add_child(unit)
	unit.entity_id = id
	unit.peer_id = id
	unit.side = side
	unit.kind = "soldier"
	unit.hp = 100
	unit.radius = 1
	unit.position = position
	unit.geometry_override = {"height": 4.0, "radius": 1.0, "top": 6.0, "centre": 4.0}
	simulation.units[id] = unit
	return unit

static func vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])
