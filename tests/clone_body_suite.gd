extends RefCounted

const Helper = preload("res://tests/status_suite.gd")
const JointTests = preload("res://tests/body_joint_suite.gd")

static func run(h: Node, fixtures: Dictionary, baseline: Dictionary) -> void:
	if not fixtures.has("cloneBodies"):
		h._check(false, "Regenerate original entity-only clone shot references")
		return
	for item: Dictionary in fixtures.cloneBodies:
		var actors: Dictionary = {}
		var expected: Dictionary = {}
		for id: String in ["owner", "clone", "sibling"]:
			var body := BodyRig.new()
			h.add_child(body)
			if not body.configure(item.key):
				h._check(false, "Pack original clone body: " + item.key)
				body.free()
				continue
			body.poses.set_position(body.source_root, Vector3(12 + actors.size() * 4, 20, -9))
			var presentation := BodyPresentation.new()
			presentation.configure(body, id)
			presentation.pending_snap = false
			actors[id] = presentation
			expected[id] = baseline[item.key].duplicate(true)
		if actors.size() != 3:
			for actor: BodyPresentation in actors.values():
				actor.body.free()
			continue
		for step: Dictionary in item.steps:
			var clone: BodyPresentation = actors.clone
			var event := {"type": "shot", "body_serial": int(step.serial), "end": Vector3(30, 24, 40)}
			h._check(clone.accept(event, step.now, Vector3(16, 20, -9), false) != step.get("reject", false),
				"Clone shots use their own entity serial without advancing their owner or siblings")
			if step.origin != null:
				h._check(clone.entity.npcMuzzle.distance_to(BodyPose.vector(step.origin)) < .0002,
					"Original clone queries its current light port before the render pass advances its sequence")
			if step.has("step"):
				for actor: BodyPresentation in actors.values():
					actor.body.step_combat(actor.entity, step.now, step.step)
			for result: Dictionary in step.actors:
				var actor: BodyPresentation = actors[result.id]
				Helper.compare(h, actor.entity.get("fireFx"), result.fire, "Original clone-only immutable shot clock")
				Helper.compare(h, actor.entity.get("_aimAt"), result.aim, "Original clone-only target memory")
				for form: String in result.forms:
					for slot: String in result.forms[form].indices:
						var sequence: Dictionary = actor.body.forms[form].weaponSequences[slot]
						h._check(int(sequence.index) == int(result.forms[form].indices[slot]), "Original deferred clone sequence advancement on both morph trees")
						for index in range(sequence.entries.size()):
							var time: Variant = result.forms[form].times[slot][index]
							if time == null:
								h._check(sequence.entries[index].firedAt == -INF, "Unfired owner/sibling/clone emitters retain their absent clock")
							else:
								h._near(sequence.entries[index].firedAt, time, "Original clone emitter clock after the combat pass")
				for node: Dictionary in result.nodes:
					expected[result.id][int(node.id)] = node
				for id: int in expected[result.id]:
					JointTests.compare_frame(h, actor.body.nodes[id], expected[result.id][id], "Original clone/owner/sibling attachment state")
		for actor: BodyPresentation in actors.values():
			actor.body.free()
