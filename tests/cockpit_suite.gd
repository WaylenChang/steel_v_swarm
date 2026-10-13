class_name CockpitSuite
extends RefCounted

static func run(h: Node, fixtures: Dictionary) -> void:
	for fixture: Dictionary in fixtures.cockpitElevation:
		var actual := CockpitPose.barrel_elevation(h._reference_vector(fixture.velocity), Vector3(0, fixture.forwardY, 0))
		h._check(absf(actual - fixture.result) < 0.000001, "Original cockpit barrel elevation")
	for fixture: Dictionary in fixtures.cockpitPoses:
		var definition := Content.weapon(fixture.character, fixture.slot, int(fixture.level))
		var offset := CockpitPose.reload_offset(definition, fixture.progress)
		h._check(offset.distance_to(h._reference_vector(fixture.offset)) < 0.000001, "Original cockpit reload curve")
		var pose := CockpitPose.transform_for(Content.balance.cockpit[fixture.character], offset, fixture.suppression, fixture.kick)
		var expected := matrix(fixture.matrix)
		h._check(pose.origin.distance_to(expected.origin) < 0.00001 and basis_error(pose.basis, expected.basis) < 0.00001,
			"Original cockpit pivot, lift/drop/pull clamps: " + fixture.character)
	var mesh_count := 0
	for character: String in Content.heroes:
		var rig := CockpitRig.new()
		h.add_child(rig)
		rig.configure(character)
		var graph: Dictionary = Content.read_json("res://data/cockpits/%s.json" % character)
		h._check(rig.nodes.size() == graph.nodes.size(), "Original cockpit graph node count")
		for spec: Dictionary in graph.nodes:
			var node: Node3D = rig.nodes[int(spec.id)]
			var expected := matrix(spec.matrix)
			h._check(node.transform.origin.distance_to(expected.origin) < 0.00001 and basis_error(node.transform.basis, expected.basis) < 0.00001,
				"Original cockpit local transform: " + character + ": " + spec.name)
			if not spec.has("mesh"):
				continue
			mesh_count += 1
			var mesh_node := node as MeshInstance3D
			var box := mesh_node.global_transform * mesh_node.get_aabb()
			h._check(box.position.distance_to(h._reference_vector(spec.worldBounds[0])) < 0.0001
				and box.end.distance_to(h._reference_vector(spec.worldBounds[1])) < 0.0001,
				"Original Three.js mesh bounds: " + character + ": " + spec.name)
			h._check(mesh_node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Source cockpit casts no shadows")
			var geometry: Dictionary = graph.meshes[int(spec.mesh)]
			var groups: Array = geometry.groups
			var indices: Array = geometry.indices if not geometry.indices.is_empty() else range(geometry.position.size() / 3)
			if groups.is_empty():
				groups = [{"start": 0, "count": indices.size(), "materialIndex": 0}]
			h._check(mesh_node.mesh.get_surface_count() == groups.size(), "Source cockpit material-group topology")
			for surface in range(groups.size()):
				var arrays: Array = mesh_node.mesh.surface_get_arrays(surface)
				var group: Dictionary = groups[surface]
				h._check(arrays[Mesh.ARRAY_VERTEX].size() * 3 == geometry.position.size()
					and arrays[Mesh.ARRAY_INDEX].size() == int(group.count), "Source cockpit vertex/index counts")
				for triangle in [0, int(group.count / 6) * 3, int(group.count) - 3]:
					for corner in range(3):
						var original := int(indices[int(group.start) + triangle + [0, 2, 1][corner]])
						h._check(arrays[Mesh.ARRAY_INDEX][triangle + corner] == original, "Native front-face winding preserves original triangles")
						var offset := original * 3
						h._check(arrays[Mesh.ARRAY_VERTEX][original].distance_to(Vector3(geometry.position[offset], geometry.position[offset + 1], geometry.position[offset + 2])) < 0.000001,
							"Original source cockpit mesh vertex")
		for fixture: Dictionary in fixtures.cockpitMuzzles:
			if fixture.character != character:
				continue
			var point := rig.muzzle_position(fixture.slot, int(fixture.index), fixture.form == "air")
			h._check(rig.gun.to_local(point).distance_to(h._reference_vector(fixture.local)) < 0.00001,
				"Original source indexed gun-local muzzle: " + character)
			h._check(point.distance_to(h._reference_vector(fixture.point)) < 0.00001, "Original FPV rest muzzle position")
		for fixture: Dictionary in fixtures.cockpitVisibility:
			if fixture.character != character:
				continue
			rig.sync_visibility(fixture.aiming, fixture.fov, 68, fixture.flight)
			for spec: Dictionary in fixture.nodes:
				h._check(rig.nodes[int(spec.id)].visible == spec.visible, "Original cockpit aim/FOV/morph visibility: " + character)
		rig.free()
	print("COCKPIT_GEOMETRY_PASS characters=", Content.heroes.size(), " meshes=", mesh_count)
	await weapon_mirrors(h, fixtures.weaponPresentation)
	flash_timing(h, fixtures.cockpitFlash)
	await integration(h)

static func weapon_mirrors(h: Node, fixtures: Array) -> void:
	var frame_count := 0
	for fixture: Dictionary in fixtures:
		var rig := CockpitRig.new()
		h.add_child(rig)
		rig.configure(fixture.character)
		var serial := 0
		for frame: Dictionary in fixture.frames:
			frame_count += 1
			for slot: String in frame.shots:
				serial += 1
				var event := {"slot": slot, "clock": frame.now, "serial": serial}
				rig.fire_feedback(event)
				rig.fire_feedback(event)
			rig.weapons.advance(frame.dt, frame.now)
			rig.apply_mirrors(fixture.form == "air", frame.now)
			rig.sync_emitter(frame.slot, fixture.form == "air")
			h._check(rig.flash.position.distance_to(h._reference_vector(frame.flashPosition)) < 0.00001,
				"Original current-emitter flash placement: %s/%s/%s frame=%d actual=%s expected=%s" % [fixture.character, fixture.form, frame.slot, frame_count, rig.flash.position, frame.flashPosition])
			for slot: String in frame.indices:
				h._check(int(rig.weapons.sequences[fixture.form][slot].index) == int(frame.indices[slot]), "Original barrel wrap and immutable-event deduplication")
			for mirror: Dictionary in frame.mirrors:
				var node: Node3D = rig.nodes[int(mirror.target)]
				var q: Array = mirror.quaternion
				var expected := Quaternion(q[0], q[1], q[2], q[3])
				h._check(node.position.distance_to(h._reference_vector(mirror.position)) < 0.00001
					and node.scale.distance_to(h._reference_vector(mirror.scale)) < 0.00001
					and absf(absf(node.quaternion.dot(expected)) - 1) < 0.00001,
					"Original full-frame cockpit weapon mirror: " + fixture.character + ": " + fixture.form + ": " + str(frame_count))
		rig.free()
	print("WEAPON_PRESENTATION_REFERENCE_PASS sequences=", fixtures.size(), " frames=", frame_count)

static func flash_timing(h: Node, fixtures: Array) -> void:
	var rig := CockpitRig.new()
	h.add_child(rig)
	rig.configure("t06")
	for fixture: Dictionary in fixtures:
		rig.flash.scale = Vector3.ONE
		rig.flash.visible = true
		rig.flash_ttl = Content.balance.cockpitRules.flash.duration
		rig.flash_heavy = fixture.heavy
		rig.step_flash(fixture.dt, fixture.sample)
		h._check(rig.flash.visible == fixture.visible and rig.flash.scale.distance_to(h._reference_vector(fixture.scale)) < 0.000001,
			"Original FPV flash lifetime, heavy size and independent sample")
	rig.sync_visibility(true, 35, 68, false)
	rig.flash.visible = true
	h._check(rig.flash.is_visible_in_tree(), "Original aiming hides cockpit parts while retaining the muzzle flash")
	rig.free()

static func matrix(values: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(values[0], values[1], values[2]), Vector3(values[4], values[5], values[6]), Vector3(values[8], values[9], values[10])),
		Vector3(values[12], values[13], values[14]))

static func basis_error(actual: Basis, expected: Basis) -> float:
	return maxf(actual.x.distance_to(expected.x), maxf(actual.y.distance_to(expected.y), actual.z.distance_to(expected.z)))

static func integration(h: Node) -> void:
	var sim := BattleSimulation.new()
	h.add_child(sim)
	var map_data := Content.map_variant(0, 1)
	map_data.erase("native_world")
	await sim.setup(map_data, [{"peer": 951, "side": "STEEL", "character": "t03", "bot": false},
		{"peer": 952, "side": "SWARM", "character": "s01", "bot": false}], {"time": "day", "weather": "clear"}, true)
	sim.set_physics_process(false)
	var actor: BattleUnit = sim.pilots[951]
	var remote: BattleUnit = sim.pilots[952]
	h._check(actor.cockpit == null and remote.cockpit == null, "Authority actors do not allocate first-person cockpit geometry")
	actor.ensure_cockpit()
	var rig := actor.cockpit
	actor.ensure_cockpit()
	h._check(actor.cockpit == rig and rig.get_parent() == actor.camera, "Local cockpit is camera-bound and reused")
	actor.position = Vector3(0, 80, 0)
	actor.yaw = 0
	actor.pitch = -0.15
	actor.input_state = {"aim": true, "slot": "heavy"}
	sim.fire_controls[actor.entity_id] = sim.lob_control(actor, Content.weapon(actor.character, "heavy"))
	var control: Dictionary = sim.snapshot(951).fire_control
	h._check(control.has("elevation") and sim.snapshot(952).fire_control.is_empty(), "Lob barrel elevation remains private to the aiming pilot")
	rig.control = control
	var ammo: int = actor.ammo.heavy
	var hp := actor.hp
	var rng_state := sim.rng.state
	var projectile_rng_state := sim.projectile_rng.state
	rig.kick = 1
	rig.update_view(actor, "heavy", true, 0.05, sim.clock)
	h._check(absf(rig.kick - 0.55) < 0.000001, "Source cockpit kick decays at nine units per second")
	h._check(actor.ammo.heavy == ammo and actor.hp == hp and sim.rng.state == rng_state and sim.projectile_rng.state == projectile_rng_state,
		"Cockpit presentation does not settle combat or consume combat/spread RNG")
	sim.events.clear()
	sim.fire(actor, "heavy")
	sim.fire(actor, "heavy")
	h._check(sim.events.filter(func(event): return event.type == "weapon_fire").size() == 1, "Accepted fire emits one cockpit feedback event; cooldown rejection emits none")
	var event: Dictionary = sim.events.filter(func(item): return item.type == "weapon_fire")[0]
	rig.fire_feedback(event)
	var accepted_serial := rig.weapons.last_serial
	var index: int = rig.weapons.sequences.ground.heavy.index
	rig.kick = 0.4
	rig.fire_feedback(event)
	h._check(rig.weapons.last_serial == accepted_serial and rig.weapons.sequences.ground.heavy.index == index and rig.kick == 0.4,
		"Repeated authority feedback does not advance barrels or restart recoil/flash")
	h._check(event.serial == actor.fire_serial and event.clock == sim.clock, "Authority feedback retains immutable shot serial and accepted clock")
	rig.update_view(actor, "heavy", true, 0.016, sim.clock + 0.016)
	h._check(rig.flash.visible and rig.flash.scale.x >= Content.balance.cockpitRules.flash.minimum * Content.balance.cockpitRules.flash.heavy,
		"Accepted heavy shot presents original flash during aim hiding")
	rig.update_view(actor, "heavy", true, 0.1, sim.clock + 0.116)
	h._check(not rig.flash.visible, "Expired source flash clears without restarting on a flight segment")
	rig.weapons.fire(accepted_serial + 1, "light", NAN)
	h._check(rig.weapons.last_serial == accepted_serial, "Invalid presentation timestamp cannot advance a source weapon sequence")
	actor.ammo.heavy = 0
	sim.reload_weapon(actor, "heavy")
	var definition := Content.weapon(actor.character, "heavy")
	rig.update_view(actor, "heavy", false, 0.2, sim.clock + definition.reload / 2)
	var expected := CockpitPose.transform_for(rig.profile, CockpitPose.reload_offset(definition, 0.5), 0, 0)
	h._check(rig.gun.transform.origin.distance_to(expected.origin) < 0.00001 and basis_error(rig.gun.basis, expected.basis) < 0.00001,
		"Native reload presentation uses authoritative deadline and source gun-root pivot")
	h._check(actor.ammo.heavy == 0 and actor.reload_at.has("heavy"), "Reload animation cannot refill or complete authority ammunition")
	actor.hp = 0
	rig.update_view(actor, "heavy", false, 0.01, sim.clock)
	h._check(not rig.visible, "Dead local pilot hides cockpit presentation")
	sim.queue_free()
	await h.get_tree().process_frame
