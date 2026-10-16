extends RefCounted

const Helper = preload("res://tests/status_suite.gd")
const Frames = preload("res://tests/view_suite.gd")

static func run(h: Node, fixtures: Dictionary) -> void:
	for key: String in ["bloodSplats", "bloodCurves", "bloodScreenPositions", "hurtBearingLog"]:
		if not fixtures.has(key) or not Content.balance.has("screenSplats"):
			h._check(false, "Regenerate original hurt accumulation/blood/glint references: " + key)
			return
	for item: Dictionary in fixtures.hurtBearingLog:
		var log := HurtBearingLog.new()
		for action: Dictionary in item.actions:
			log.record(int(action.target), int(action.attacker), BodyPose.vector(action.origin), float(action.amount), action.elevation)
		var events := log.flush(item.order)
		h._check(events.size() == item.events.size(), "Original hurt log preserves hero order and ignores removed primary bodies")
		for index in range(mini(events.size(), item.events.size())):
			var event: Dictionary = events[index].duplicate()
			event.origin = _array(event.origin)
			h._check(event.has("elevation") == item.events[index].has("elevation"), "NPC hurt bearings cannot invent an absolute attacker eye height")
			Helper.compare(h, event, item.events[index], "Original same-attacker damage sum, first origin/eye retention and JavaScript decimetre rounding")
		Helper.compare(h, log.flush(item.order), item.repeated, "A second publication cannot re-flush spent hurt records")
	for item: Dictionary in fixtures.bloodCurves:
		h._near(BloodSplatState.alpha(float(item.left)), item.blood, "Original held blood opacity and smoothstep decay")
		h._near(BloodSplatState.alpha(float(item.left), true), item.glint, "Original shorter glint hold/decay")
	for item: Dictionary in fixtures.bloodScreenPositions:
		var point := BloodSplatState.screen_uv(item.bearing, item.elev, item.half, item.half)
		Helper.compare(h, {"u": point.x, "v": point.y}, item.result, "Original front/back bearing, elevation, zero FOV and inset clamps")
	for item: Dictionary in fixtures.bloodSplats:
		var state := BloodSplatState.new()
		var draw := {"count": 0}
		state.random_sample = func():
			var value := float(item.random[int(draw.count) % item.random.size()])
			draw.count += 1
			return value
		var vital: Dictionary = item.vital.duplicate()
		for event: Dictionary in item.events:
			vital.defending = event.defending
			var report := {"origin": BodyPose.vector(event.origin), "amount": event.amount}
			if event.has("elevation"):
				report.elevation = event.elevation
			state.spray(report, Frames.frame(item.frame), item.pose.fov, item.pose.aspect, vital)
		Helper.compare(h, state.blood, item.initial.blood, "Original immutable blood positions, dose-based main/satellite drops and oldest-first cap")
		Helper.compare(h, state.glints, item.initial.glints, "Original defending/shield-empty split and distinct glint radius/cap")
		h._check(state.sequence == item.initial.sequence and int(draw.count) == int(item.initial.draws),
			"Original spray IDs and private visual draw count survive rejected/zero/dead events")
		for step: Dictionary in item.steps:
			var updates := state.advance(float(step.delta))
			var calls: Array = []
			for key: String in ["blood", "glint"]:
				if updates[key] != null:
					calls.append({"kind": key, "list": updates[key]})
			Helper.compare(h, state.blood, step.blood, "Original blood remaining life and removal ordering")
			Helper.compare(h, state.glints, step.glints, "Original glint remaining life and removal ordering")
			Helper.compare(h, calls, step.calls, "Original fading HUD reports, expiry frame, one final empty report and quiet early-out")
		var cleared := state.clear()
		Helper.compare(h, [{"kind": "blood", "list": cleared.blood}, {"kind": "glint", "list": cleared.glint}], item.cleared.calls,
			"Death/view reset explicitly clears both screen layers")
		h._check(state.sequence == item.cleared.sequence and state.blood.is_empty() and state.glints.is_empty(),
			"Clearing glass residue preserves monotonically increasing spray IDs")
	_production(h)

static func _production(h: Node) -> void:
	var simulation := BattleSimulation.new()
	h.add_child(simulation)
	simulation.set_physics_process(false)
	var character: String = Content.heroes.keys()[0]
	var target := Helper.actor(simulation, {"id": 1, "character": character, "side": "STEEL", "position": [0, 0, 0]})
	var attacker := Helper.actor(simulation, {"id": 2, "character": character, "side": "SWARM", "position": [12, 20, -9]})
	var clone := Helper.actor(simulation, {"id": 3, "character": character, "side": "STEEL", "position": [0, 0, 0]})
	clone.special = {"role": "clone", "owner_id": target.entity_id}
	var npc := Helper.actor(simulation, {"id": 4, "character": "", "kind": "soldier", "side": "SWARM", "position": [30, 0, 40]})
	var resources := [target.hp, target.shield, target.power, attacker.ammo.duplicate(), simulation.rng.state, simulation.projectile_rng.state]
	simulation._record_blood_hurt(target, attacker, 10)
	simulation._record_blood_hurt(target, attacker, 20)
	simulation._record_blood_hurt(clone, attacker, 100)
	simulation._record_blood_hurt(npc, attacker, 100)
	simulation._record_blood_hurt(target, null, 100)
	simulation._record_blood_hurt(target, npc, 5)
	simulation.flush_blood_hurt()
	var events: Array = simulation.events.filter(func(event): return event.type == "screen_hurt")
	h._check(events.size() == 2 and events[0].actor == target.entity_id and events[0].peer == target.peer_id and events[0].amount == 30,
		"Authority publication emits one aggregated bearing per attacker only for the primary pilot")
	if events.size() == 2:
		h._check(events[0].has("elevation") and not events[1].has("elevation") and int(events[0].blood_serial) < int(events[1].blood_serial),
			"Human eye metadata stays optional and published spray identities are distinct")
	simulation.flush_blood_hurt()
	h._check(simulation.events.size() == 2, "Repeated native publication cannot duplicate hurt bearings")
	h._check(resources == [target.hp, target.shield, target.power, attacker.ammo, simulation.rng.state, simulation.projectile_rng.state],
		"Hurt bearing aggregation and publication never settle HP or consume combat RNG/resources")
	simulation.free()

static func _array(point: Vector3) -> Array:
	return [point.x, point.y, point.z]
