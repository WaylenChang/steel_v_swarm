extends RefCounted

static func run(h: Node, fixtures: Array) -> void:
	var maximum_error := 0.0
	var physical := 0
	for fixture: Dictionary in fixtures:
		var def := Content.weapon(fixture.character, fixture.slot, int(fixture.level))
		var flying: bool = fixture.form == "air"
		var pose := AuthorityWeaponPose.new()
		pose.configure(fixture.character)
		pose.advance(1.0 / 60, 1, fixture.slot, flying, def)
		pose.gun = CockpitSuite.matrix(fixture.gun)
		var camera := CockpitSuite.matrix(fixture.camera)
		var current := pose.current_muzzle(camera)
		var label: String = "%s/%s/%s/%s scenario=%s" % [fixture.character, fixture.form, fixture.slot, fixture.level, fixture.scenario]
		h._check(current.distance_to(h._reference_vector(fixture.advisory)) < 0.0001, "Source advisory uses current muzzle: " + label)
		var before := pose.caches.duplicate()
		var origin := pose.muzzle(camera, fixture.slot, flying, true, false)
		h._check(pose.caches == before, "Previewing a launch port cannot mutate source fallback aliases")
		var expected: Vector3 = h._reference_vector(fixture.bullet.origin if fixture.has("bullet") else fixture.visual[0].from)
		var error := origin.distance_to(expected)
		maximum_error = maxf(maximum_error, error)
		h._check(error < 0.0001, "Source complete _tryFire muzzle: " + label)
		var boxes: Array = []
		if fixture.wall != null:
			boxes.append({"min": [-32000, -32000, fixture.wall - 0.001], "max": [32000, 32000, fixture.wall]})
		var geometry: Node3D = h._lob_geometry({"ground": {"base": fixture.ground, "x": 0, "z": 0}, "boxes": boxes})
		await h.get_tree().physics_frame
		await h.get_tree().physics_frame
		var forward := camera.basis * Vector3.FORWARD
		var endpoint: Vector3 = camera.origin + forward * def.range
		var hit: Dictionary = h._lob_collision(camera.origin, endpoint)
		if not hit.is_empty():
			endpoint = hit.position
		h._check(endpoint.distance_to(h._reference_vector(fixture.reticle)) < 0.001, "Source reticle ray retains camera origin: " + label)
		if fixture.has("bullet"):
			physical += 1
			var state: Dictionary
			if def.trajectory == "lob":
				var request := camera.origin + forward * TargetingMath.maximum_range(def)
				var obstruction: Dictionary = h._lob_collision(camera.origin, request)
				if not obstruction.is_empty():
					request = obstruction.position
				var control := LobFireControl.prepare(def, current, request, def.range, false, func(_x, _z): return fixture.ground, h._lob_collision)
				h._check(control.ok == fixture.control.ok and control.close == fixture.control.close, "Source muzzle-based lob gate and warning: " + label)
				state = ProjectileMotion.ballistic(origin, control.velocity, control.range)
			else:
				state = ProjectileMotion.launch(def, origin, forward, fixture.ground, .37, .8, endpoint, 0) if def.trajectory in ["guide", "fnf"] else ProjectileMotion.ballistic(origin, forward * def.projectile.speed, def.range)
			var velocity_error: float = state.velocity.distance_to(h._reference_vector(fixture.bullet.velocity))
			maximum_error = maxf(maximum_error, velocity_error)
			h._check(velocity_error < 0.001, "Source complete muzzle launch velocity: " + label)
			h._near(state.range, fixture.bullet.range, "Source muzzle launch range")
			h._check(state.origin.distance_to(origin) < 0.00001, "Physical range sphere is centred on the launch muzzle")
			if fixture.bullet.guide:
				h._check(state.guide_point.distance_to(h._reference_vector(fixture.bullet.guidePoint)) < 0.001, "Laser point freezes the camera-ray endpoint")
			if fixture.bullet.launchDistance > 0:
				h._near(state.launch_distance, fixture.bullet.launchDistance, "Source muzzle-height climb budget")
			var body: Vector3 = h._reference_vector(fixture.body)
			h._check(absf(origin.y - fixture.ground - fixture.bullet.relativeMuzzle) < 0.0001, "Source immutable muzzle height is separate from shooter eye")
		elif def.area == "line":
			var line: Vector3 = endpoint - origin
			h._check(line.normalized().distance_to((h._reference_vector(fixture.visual[0].to) - expected).normalized()) < 0.00001,
				"Instant line connects the launch muzzle to the camera endpoint")
		geometry.free()
	print("MUZZLE_LAUNCH_REFERENCE_PASS cases=", fixtures.size(), " physical=", physical, " maximum_error=", maximum_error)
	await integration(h)

static func integration(h: Node) -> void:
	var sim := BattleSimulation.new()
	h.add_child(sim)
	var map_data := Content.map_variant(0, 1)
	map_data.erase("native_world")
	await sim.setup(map_data, [{"peer": 981, "side": "STEEL", "character": "t04", "bot": false}], {"time": "day", "weather": "clear"}, true)
	sim.set_physics_process(false)
	var actor: BattleUnit = sim.pilots[981]
	for unit: BattleUnit in sim.units.values():
		if unit != actor:
			unit.hp = 0
	actor.position = Vector3(0, 80, 0)
	actor.yaw = 0
	actor.pitch = 0
	var origin := actor.weapon_pose.muzzle(actor.aim_transform(), "light", false, true, false)
	var victim := sim.spawn({"kind": "soldier", "side": "SWARM", "position": origin + Vector3(0, -0.5, -30)})
	victim.shield = 0
	victim.hp = 1000
	sim.spawn({"kind": "soldier", "side": "STEEL", "position": victim.position + Vector3(0, 0, -5)})
	var wall := StaticBody3D.new()
	wall.position = origin + Vector3(0, 0, -2)
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.2, 0.4, 0.01)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	wall.add_child(collider)
	sim.add_child(wall)
	await h.get_tree().physics_frame
	await h.get_tree().physics_frame
	h._check(sim._arc_collision(actor.eye(), actor.eye() + Vector3.FORWARD * 10).is_empty(), "Camera ray clears the narrow muzzle obstruction")
	var before := actor.weapon_pose.caches.duplicate()
	sim.snapshot(981)
	h._check(actor.weapon_pose.caches == before, "Authority advisory snapshots never mutate launch-cache aliases")
	sim.fire(actor, "light")
	h._check(sim.projectiles.size() == 1 and sim.projectiles[0].origin.distance_to(origin) < 0.00001,
		"Native flat round launches from the next FPV muzzle")
	var fire: Dictionary = sim.events.filter(func(event): return event.type == "weapon_fire")[-1]
	h._check(fire.muzzle == sim.projectiles[0].origin, "Accepted feedback and physical launch share one immutable port")
	sim._tick_projectiles(1.0 / 60)
	h._check(sim.projectiles.is_empty() and victim.hp == 1000, "Muzzle-side sweep stops at a wall outside the camera ray")
	wall.free()
	actor.fire_at.clear()
	await h.get_tree().physics_frame
	sim.fire(actor, "light")
	actor.position += Vector3(200, 100, 0)
	actor.yaw = PI
	for i in range(60):
		if sim.projectiles.is_empty():
			break
		sim._tick_projectiles(1.0 / 60)
	h._check(victim.hp < 1000, "A physical round follows its muzzle ray after the shooter moves and turns")
	actor.position = Vector3(0, 0.1, 0)
	actor.yaw = 0
	h._check(absf(sim._weapon_surface(Vector3(0, -0.5, 0))) < 0.001, "A muzzle below verified terrain retains the source ground-height reference")
	sim.queue_free()
	await h.get_tree().process_frame
