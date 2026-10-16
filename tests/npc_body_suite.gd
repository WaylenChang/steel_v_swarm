extends RefCounted

const Helper = preload("res://tests/status_suite.gd")
const JointTests = preload("res://tests/body_joint_suite.gd")

static func run(h: Node, fixtures: Dictionary, baseline: Dictionary) -> void:
	if not fixtures.has("npcBodies") or not fixtures.has("npcShotPoints"):
		h._check(false, "Regenerate original NPC mount, muzzle and acquisition references")
		return
	for item: Dictionary in fixtures.npcShotPoints:
		h._check(BodyMountAim.shot_point(BodyPose.vector(item.position), item.ground, item.altitude, item.raised, item.quantized).distance_to(BodyPose.vector(item.result)) < .00001,
			"Original server NPC altitude quantization and client target-height presentation")
	for item: Dictionary in fixtures.npcBodies:
		var body := BodyRig.new()
		h.add_child(body)
		if not body.configure(item.key):
			h._check(false, "Pack original NPC body scene: " + item.key)
			body.free()
			continue
		var entity := {"id": "npc/" + item.key}
		var expected: Dictionary = baseline[item.key].duplicate(true)
		for step: Dictionary in item.steps:
			body.poses.set_position(body.source_root, Vector3(12, 20, -9))
			body.poses.set_axis(body.source_root, "y", step.yaw)
			if step.has("aim"):
				entity._aimAt = step.aim.duplicate()
			if step.has("arc"):
				entity._arcPitch = step.arc.duplicate()
			if step.has("guns"):
				entity._gunAim = {}
				for index in range(step.guns.size()):
					if step.guns[index] != null:
						entity._gunAim[index] = step.guns[index].duplicate()
			if step.has("batteryYaw") and body.mounts.get("guns") != null:
				body.poses.set_axis(body.mounts.guns, "y", step.batteryYaw)
			BodyMountAim.step(body, entity, step.delta, step.now, Vector3(12, 20, -9), step.yaw,
				null if step.nearest == null else BodyPose.vector(step.nearest))
			for spec: Dictionary in step.nodes:
				expected[int(spec.id)] = spec
			for id: int in expected:
				JointTests.compare_frame(h, body.nodes[id], expected[id], "Original independent NPC turret/aircraft pitch")
		var presentation := BodyPresentation.new()
		presentation.configure(body, entity.id)
		for shot: Dictionary in item.shots:
			var event := {"type": "shot", "body_serial": int(shot.index) + 1, "gun": int(shot.gun),
				"start": Vector3(12, 20, -9), "end": Vector3(30, 24, 40)}
			h._check(presentation.accept(event, shot.now, Vector3(12, 20, -9), false), "Each NPC shot has an independent presentation identity")
			h._check(presentation.entity.npcMuzzle.distance_to(BodyPose.vector(shot.origin)) < .0002,
				"Original NPC alternating muzzle selection")
			h._check(presentation.npc_origin(int(event.body_serial), Vector3(INF, INF, INF)).distance_to(BodyPose.vector(shot.origin)) < .0002,
				"Each transported NPC shot retains its own immutable world-space port until presentation")
			h._check(body.npc_muzzle_index == (-1 if shot.muzzleIndex == null else int(shot.muzzleIndex)),
				"Original NPC turret/aircraft muzzle index")
			h._check(presentation.entity.fireFx.slot == shot.slot, "Original NPC weapon style selects the combat pose slot")
			for index in range(shot.firedAt.size()):
				var expected_time: Variant = shot.firedAt[index]
				var at: float = body.forms.ground.attacks[index].firedAt
				if expected_time == null:
					h._check(at == -INF, "Unfired NPC recoil mounts retain absent clocks")
				else:
					h._near(at, expected_time, "Original NPC recoil mount fire clock")
			h._check(not presentation.accept(event, shot.now, Vector3(12, 20, -9), false), "Snapshot copies cannot advance NPC muzzle/recoil twice")
			h._check(presentation.npc_origin(int(event.body_serial), Vector3.ZERO) == Vector3.ZERO, "Consumed/replayed NPC events cannot reuse another barrel's origin")
		for sample: Dictionary in item.fallback:
			var actual := BodyMountAim.fallback_muzzle(BodyPose.vector(sample.position), sample.ground, sample.height,
				BodyPose.vector(sample.target), sample.garrison, sample.override)
			h._check(actual.distance_to(BodyPose.vector(sample.result)) < .00001,
				"Original hidden/missing NPC muzzle, explicit air height, garrison ports and zero planar distance")
		for trace: Dictionary in item.nearest:
			var state: Dictionary = {}
			for step: Dictionary in trace.steps:
				var candidates: Array = step.candidates.duplicate(true)
				for candidate: Dictionary in candidates:
					candidate.position = BodyPose.vector(candidate.position)
				var id := BodyMountAim.nearest(state, BodyPose.vector(trace.position), trace.side,
					step.now, trace.reach, candidates, trace.structures)
				h._check(id == int(step.result) and int(state._aimTarget) == int(step.cached),
					"Original visual target cache retains dead/hidden entries until expiry and rejects removed identities")
				h._near(state._aimNext, step.next, "Original inclusive quarter-second acquisition deadline")
		body.free()
		var unit := BattleUnit.new()
		h.add_child(unit)
		var side: String = Content.balance.bodies[item.key].side
		var special: Dictionary = {"role": "hologram"} if item.kind == "decoy_beacon" else {"role": "third"} if side in ["GUER", "MILI"] else {"role": "summon"} if item.modelKey.begins_with("summon:") else {}
		unit.configure({"id": 1, "side": side, "kind": item.kind, "position": Vector3.ZERO, "special": special})
		h._check(unit.model == unit.body and unit.body_presentation != null and unit.body.profile.modelKey == item.modelKey,
			"Primary NPCs bind their source procedural body and composed pose driver")
		unit.free()
