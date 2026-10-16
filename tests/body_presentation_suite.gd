extends RefCounted

const Helper = preload("res://tests/status_suite.gd")
const JointTests = preload("res://tests/body_joint_suite.gd")

static func run(h: Node, fixtures: Dictionary, baseline: Dictionary) -> void:
	for key: String in ["bodyPresentationLod", "bodyCastDirection", "bodyPresentationEvents"]:
		if not fixtures.has(key):
			h._check(false, "Regenerate original body presentation routing references: " + key)
			return
	for item: Dictionary in fixtures.bodyPresentationLod:
		h._check(BodyMotionState.hash_of(item.id) == int(item.hash), "Original UTF-16 FNV body LOD staggering")
		h._check(BodyPresentation.update_stride(item.distance, item.lowPower) == int(item.stride), "Original squared-distance body update bands")
		h._check(BodyPresentation.update_due(int(item.frame), item.id, int(item.stride)) == item.due, "Original frame-wrap body heavy-update schedule")
	for item: Dictionary in fixtures.bodyCastDirection:
		h._check(BodyPresentation.cast_direction(item.effect, item.remote) == int(item.result), "Original source ability cast direction gate")
	for item: Dictionary in fixtures.bodyPresentationEvents:
		var rig := BodyRig.new()
		h.add_child(rig)
		if not rig.configure(item.key):
			h._check(false, "Pack original body event scene: " + item.key)
			rig.free()
			continue
		var presentation := BodyPresentation.new()
		presentation.configure(rig, "events/" + item.key)
		var expected: Dictionary = baseline[item.key].duplicate(true)
		for step: Dictionary in item.steps:
			var event := {"body_serial": int(step.serial), "type": step.type}
			for key: String in ["slot", "fx", "on"]:
				if step.has(key):
					event[key] = step[key]
			if step.has("point"):
				event.point = BodyPose.vector(step.point)
			var accepted := presentation.accept(event, step.now, Vector3.ZERO, step.get("self", false), step.get("authoritative", false))
			h._check(accepted != step.get("reject", false), "Body transport serial rejects only repeated/stale events")
			if step.get("localFire", false):
				presentation.fire_local(step.slot, step.now)
			for field: String in ["fireFx", "heavyFx", "castFx"]:
				var value: Variant = step.fire if field == "fireFx" else step.heavy if field == "heavyFx" else step.cast
				if value == null:
					h._check(presentation.entity.get(field) == null, "Original canceled/unstarted body event: " + field)
				else:
					Helper.compare(h, presentation.entity.get(field), value, "Original body event producer: " + field)
			for form: String in step.forms:
				for slot: String in step.forms[form].indices:
					var sequence: Dictionary = rig.forms[form].weaponSequences[slot]
					h._check(int(sequence.index) == int(step.forms[form].indices[slot]), "Original accepted event advances both morph weapon sequences exactly once")
					for index in range(sequence.entries.size()):
						var time: Variant = step.forms[form].times[slot][index]
						if time == null:
							h._check(sequence.entries[index].firedAt == -INF, "Original unfired emitter clock")
						else:
							h._near(sequence.entries[index].firedAt, time, "Original immediate body emitter event clock")
			for spec: Dictionary in step.nodes:
				expected[int(spec.id)] = spec
			for id: int in expected:
				JointTests.compare_frame(h, rig.nodes[id], expected[id], "Original immediate body event attachment/payload state")
		# A queued respawn clears old frame clocks after delivery, without rewinding emitter identity.
		presentation.entity.loco = {"speed": 100.0}
		presentation.entity.cfx = {"stale": true}
		presentation.request_snap()
		var event_serial := presentation.accepted_event
		presentation.frame(.016, 30, 1, Vector3.ZERO, 0, Vector3.ZERO, {"hero": true, "heroY": 0.0, "isSelf": false, "dead": false}, true)
		h._check(not presentation.entity.cfx.has("stale") and presentation.accepted_event == event_serial, "Respawn resets presentation clocks while preserving transport deduplication")
		h._check(presentation.entity.get("fireFx") == null and presentation.entity.get("castFx") == null and presentation.entity.get("heavyFx") == null,
			"Respawn drops pre-snap weapon/cast events before stepping the new pose")
		if rig.profile["static"]:
			h._check(presentation.entity.get("loco") == null, "Static bodies do not acquire a locomotion state after a snap")
		else:
			h._near(presentation.entity.loco.speed, 0, "Respawn does not turn a teleport into locomotion velocity")
		rig.free()
