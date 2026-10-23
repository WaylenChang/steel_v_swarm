extends RefCounted

const Helper = preload("res://tests/status_suite.gd")
const Primitives = preload("res://tests/npc_shot_suite.gd")

class EffectWorld extends BattleWorld:
	func clip_shot(_origin: Vector3, target: Vector3) -> Dictionary:
		return {"to": target, "cut": false}
	func source_height(_x: float, _z: float) -> float:
		return 0
	func visual_surface(_point: Vector3) -> float:
		return 0

static func run(h: Node, fixtures: Dictionary) -> void:
	for key: String in ["remoteShotReports", "remoteMuzzleSelection", "remoteBarrelAim", "remoteLaunchRelay"]:
		if not fixtures.has(key):
			h._check(false, "Regenerate original remote report/burst/muzzle references: " + key)
			return
	for item: Dictionary in fixtures.remoteShotReports:
		var definition := {} if item.scenario.begins_with("absent") else Content.weapon(item.character, item.slot, 1)
		var queries: Array = []
		var clip := func(origin: Vector3, target: Vector3):
			var obstruction := func(start: Vector3, end: Vector3):
				if item.scenario not in ["wall", "absent_wall"] or start.z == end.z:
					return {}
				var fraction := (30.0 - start.z) / (end.z - start.z)
				return {"position": start.lerp(end, fraction)} if fraction >= 0 and fraction <= 1 else {}
			var result := NpcShotMotion.clip(origin, target, obstruction)
			queries.append({"from": _array(origin), "to": _array(target), "result": {"to": _array(result.to), "cut": result.cut}})
			return result
		var plan := RemoteShotState.plan(definition, item.slot, BodyPose.vector(item.origin), BodyPose.vector(item.target), item.hit, item.bot, clip)
		Helper.compare(h, _plan(plan), item.initial.plan, "Original tracer/bot heavy-shell, lance and honest-contact branching")
		Helper.compare(h, queries, item.initial.queries, "Original remote report clip-query order")
		queries.clear()
		var queue := BurstPresentationQueue.new()
		if plan.kind == "shot" and not definition.is_empty():
			queue.schedule(definition, 10, {})
		Helper.compare(h, _pending(queue), item.initial.pending, "Original remote visual-only burst count/deadlines")
		for step: Dictionary in item.steps:
			var shots: Array = []
			for callback: Dictionary in queue.take_due(step.now):
				var echo := RemoteShotState.echo(definition, BodyPose.vector(step.origin), BodyPose.vector(item.target), clip)
				shots.append({"kind": "shot", "target": _array(echo.target), "impact": echo.impact})
			Helper.compare(h, shots, step.shots, "Original moving/removed shooter callback endpoints and contact gates")
			Helper.compare(h, queries, step.queries, "Original reverse-order due callbacks re-query every live muzzle")
			Helper.compare(h, _pending(queue), step.pending, "Original repeated/hitched frame queue consumption")
			queries.clear()
	for item: Dictionary in fixtures.remoteMuzzleSelection:
		var candidates: Array = item.candidates.duplicate(true)
		for candidate: Dictionary in candidates:
			candidate.position = BodyPose.vector(candidate.position)
			if candidate.muzzle != null:
				candidate.muzzle = BodyPose.vector(candidate.muzzle)
		Primitives._point(h, RemoteShotState.muzzle(candidates, BodyPose.vector(item.fallback)), item.result,
			"Original closest same-pilot muzzle, insertion ties, hidden meshes, self/fx-only exclusions and fallback")
	for item: Dictionary in fixtures.remoteBarrelAim:
		var body := BodyRig.new()
		body.forms = {"ground": {"weap": {"heavy": item.hand}} if item.hand == "none" else {
			"weap": {"heavy": item.hand}, "gunL": {"aim": .7}, "gunR": {"aim": 1.1}}}
		for step: Dictionary in item.steps:
			RemoteShotState.aim_heavy(body, BodyPose.vector(step.direction))
			Helper.compare(h, body.forms.ground.get("gunL"), step.gunL, "Original cached left heavy barrel compensation")
			Helper.compare(h, body.forms.ground.get("gunR"), step.gunR, "Original cached right heavy barrel compensation, including vertical/zero vectors")
		body.free()
	for item: Dictionary in fixtures.remoteLaunchRelay:
		var arc := {} if item.arc == null else {"aim": BodyPose.vector(item.arc.aim), "speed": item.arc.speed}
		var report := RemoteShotState.relay(BodyPose.vector(item.origin), BodyPose.vector(item.direction), arc)
		Helper.compare(h, {"target": _array(report.target), "speed": report.speed}, item.result,
			"Original short physical tracer versus lob fire-control endpoint and JavaScript speed rounding")
	_integration(h, fixtures.remoteShotReports)
	_unbound_reports(h, fixtures.remoteShotReports)

static func _unbound_reports(h: Node, cases: Array) -> void:
	var simulation := BattleSimulation.new()
	h.add_child(simulation)
	simulation.set_physics_process(false)
	simulation.world = EffectWorld.new()
	simulation.add_child(simulation.world)
	var serial := 0
	for item: Dictionary in cases:
		if item.scenario != "absent_hit" or item.bot:
			continue
		serial += 1
		var report := {"type": "shot", "hero_report": true, "actor": 999, "slot": item.slot, "side": "STEEL",
			"body_serial": serial, "start": BodyPose.vector(item.origin), "end": BodyPose.vector(item.target), "hit": true}
		simulation.receive_body_events([report], 10)
		var effects := simulation.world.combat_effects
		h._check(effects != null and not effects.effects.is_empty() and simulation.remote_bursts.pending.is_empty(),
			"An absent shooter retains the original immediate report primitives without guessing its weapon or burst")
		var count := effects.effects.size()
		simulation.present_world_events([report])
		h._check(effects.effects.size() == count, "Absent-shooter report replay is consumed once before any later entity snapshot")
		for effect: Dictionary in effects.effects:
			effects._drop(effect)
		effects.effects.clear()
	simulation.free()

static func _integration(h: Node, cases: Array) -> void:
	var matches: Array = cases.filter(func(item): return not item.bot and item.slot == "light" and item.scenario == "clear" and not item.initial.pending.is_empty())
	h._check(not matches.is_empty(), "Original remote references contain a compressed light burst")
	if matches.is_empty():
		return
	var item: Dictionary = matches[0]
	var simulation := BattleSimulation.new()
	h.add_child(simulation)
	simulation.set_physics_process(false)
	simulation.world = EffectWorld.new()
	simulation.add_child(simulation.world)
	var owner := Helper.actor(simulation, {"id": 2, "character": item.character, "side": "STEEL", "position": [0, 20, 0],
		"hp": 700, "shield": 120, "power": 80, "ammo": {"light": 4, "heavy": 2}})
	var clone := Helper.actor(simulation, {"id": 3, "character": item.character, "side": "STEEL", "position": [200, 20, 0],
		"hp": 700, "shield": 120, "power": 80, "ammo": {"light": 4, "heavy": 2}})
	clone.special = {"role": "clone"}
	clone.peer_id = owner.peer_id
	for actor: BattleUnit in [owner, clone]:
		actor._configure_body("steel_" + item.character)
		h._check(actor.body_presentation != null, "Pack actual pilot/clone rigs for remote burst integration")
		if actor.body_presentation == null:
			simulation.free()
			return
		actor.body_presentation.capture_snapshot({"position": actor.position, "yaw": 0, "hp": actor.hp,
			"shield": actor.shield, "defending": false}, 10)
	var resources := [owner.hp, owner.shield, owner.power, owner.ammo.duplicate(), owner.fire_serial,
		clone.hp, clone.shield, clone.ammo.duplicate(), simulation.rng.state, simulation.projectile_rng.state]
	var port := owner.body.next_muzzle("light")
	simulation.receive_body_events([{"type": "weapon_fire", "actor": owner.entity_id, "slot": "light", "serial": 1,
		"clock": 10, "body_serial": 1}], 10)
	var first: Dictionary = owner.body.forms.ground.weaponSequences.light.event
	var clone_first: Dictionary = clone.body.forms.ground.weaponSequences.light.event
	var report := {"type": "shot", "hero_report": true, "actor": owner.entity_id, "slot": "light", "side": owner.side,
		"shot_serial": 1, "body_serial": 2, "start": port, "end": port + Vector3(0, 0, 120), "level": 4, "hit": false}
	simulation.receive_body_events([report], 10)
	var effects := simulation.world.combat_effects
	h._check(effects != null and not effects.effects.is_empty() and effects.effects[0].obj.position.distance_to(port) < .0001,
		"Remote first discharge consumes its pre-fire immutable muzzle instead of the next alternating barrel")
	h._check(is_same(first, owner.body.forms.ground.weaponSequences.light.event) and is_same(clone_first, clone.body.forms.ground.weaponSequences.light.event),
		"A public report cannot advance the first owner/clone pose twice")
	var pending := simulation.remote_bursts.pending.size()
	var count := effects.effects.size()
	simulation.receive_body_events([report], 10)
	simulation.present_world_events([report])
	h._check(simulation.remote_bursts.pending.size() == pending and effects.effects.size() == count, "Immediate/snapshot report replay cannot schedule another burst")
	simulation.receive_body_events([{"type": "body_echo", "actor": owner.entity_id, "slot": "light", "body_serial": 3}], 10.1)
	h._check(is_same(first, owner.body.forms.ground.weaponSequences.light.event), "Private authority echo reports cannot double-drive the public remote pose")
	owner.position.x += 1
	var next_port := owner.body.next_muzzle("light")
	var deadline := float(simulation.remote_bursts.pending[0].at)
	simulation.step_remote_shots(deadline)
	h._check(effects.effects.size() > count and effects.effects[count].obj.position.distance_to(next_port) < .0001, "Actual remote callbacks re-query the current moved barrel")
	h._check(not is_same(first, owner.body.forms.ground.weaponSequences.light.event) and not is_same(clone_first, clone.body.forms.ground.weaponSequences.light.event),
		"One remote callback advances both owner and same-pilot clone rigs exactly once")
	simulation.units.erase(owner.entity_id)
	h._check(simulation._hero_representative(owner.entity_id) == clone, "A visible clone retains the original pilot identity after the main body leaves view")
	simulation.units.erase(owner.entity_id)
	h._check(simulation._hero_representative(owner.entity_id, owner.peer_id) == clone,
		"A report's public player ID resolves a visible clone after owner removal without exposing owner entity IDs")
	h._check(resources == [owner.hp, owner.shield, owner.power, owner.ammo, owner.fire_serial,
		clone.hp, clone.shield, clone.ammo, simulation.rng.state, simulation.projectile_rng.state], "Remote flashes, shells and callbacks cannot spend resources or repeat damage/RNG")
	simulation.free()

static func _array(point: Vector3) -> Array:
	return [point.x, point.y, point.z]

static func _plan(plan: Dictionary) -> Dictionary:
	var result := plan.duplicate()
	result.target = _array(plan.target)
	return result

static func _pending(queue: BurstPresentationQueue) -> Array:
	return queue.pending.map(func(entry): return {"at": entry.at, "index": entry.index, "count": entry.count})
