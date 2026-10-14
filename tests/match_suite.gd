extends RefCounted

const StatusHelper = preload("res://tests/status_suite.gd")

class MatchSimulation extends BattleSimulation:
	func _missile_target_altitude(unit: BattleUnit) -> float:
		return unit.position.y

	func _on_third_death(_unit: BattleUnit, _attacker: BattleUnit) -> void:
		pass

	func _collapse_scene(_unit: BattleUnit) -> void:
		pass

	func _drop_scene_loot(_unit: BattleUnit) -> void:
		pass

	func _carrier_shot_down(_unit: BattleUnit) -> void:
		pass

static func run(h: Node, fixtures: Dictionary) -> void:
	if not fixtures.has("matchStatsInit") or not fixtures.has("matchDeaths"):
		h._check(false, "Regenerate original match-stat references before final verification")
		return
	for item: Dictionary in fixtures.matchDeaths:
		var simulation := create(h)
		StatusHelper.compare(h, simulation.match_stats, fixtures.matchStatsInit, "Original regular-match counter columns and initial values")
		var first := actor(simulation, 1, "STEEL", true)
		var target := actor(simulation, 2, item.side, item.role == "hero", item.kind)
		var contributor := actor(simulation, 3, "STEEL", true)
		contributor.position.x = float(Content.constants.ECON.ASSIST.R_M) + 1 if item.distant else 0
		if item.role == "third":
			target.special = {"role": "third", "third": true}
		elif item.role == "hazard":
			target.special = {"role": "hazard", "neutral": true}
		elif item.role == "civilian":
			target.special = {"role": "civilian", "neutral": true, "civil_side": "SWARM", "spy": false, "no_respawn": true}
		elif item.role == "carrier":
			target.special = {"role": "carrier"}
		var killer: BattleUnit
		if item.killer == "hero":
			killer = first
		elif item.killer != "none":
			killer = actor(simulation, 4, item.side if item.killer == "ally" else "GUER" if item.killer == "third" else "STEEL", item.killer == "ally")
		target.hp = 0
		target.assists = {1: true, 3: true}
		simulation._kill_unit(target, killer)
		StatusHelper.compare(h, simulation.match_stats, item.result, "Original hero/NPC/third/environment kills, paid assists, weighted last hits and early-return roles")
		h._check(not simulation.match_stats.has("GUER") and not simulation.match_stats.has("MILI"), "Regular match counters omit third-faction columns")
		simulation.free()
	var authority := create(h)
	authority.match_stats.STEEL.kills = 4
	var packet: Dictionary = bytes_to_var(var_to_bytes(authority.snapshot()))
	packet.stats.STEEL.kills = 5
	h._check(authority.match_stats.STEEL.kills == 4, "Snapshot counters are detached from authority state")
	var replica := create(h)
	replica.authoritative = false
	replica.world = BattleWorld.new()
	replica.add_child(replica.world)
	packet.erase("weather")
	replica.apply_snapshot(packet)
	StatusHelper.compare(h, replica.match_stats, packet.stats, "Replica receives public counter columns")
	packet.stats.STEEL.kills = 6
	h._check(replica.match_stats.STEEL.kills == 5, "Replica counters are detached from decoded packet buffers")
	packet.clock = 9
	replica.apply_snapshot(packet)
	h._check(replica.match_stats.STEEL.kills == 5, "Stale snapshots cannot replace newer match counters")
	authority.apply_snapshot(packet)
	h._check(authority.match_stats.STEEL.kills == 4, "Incoming snapshots cannot overwrite authority counters")
	var victim := actor(replica, 1, "SWARM", true)
	victim.hp = 0
	replica._kill_unit(victim, null)
	h._check(replica.match_stats.SWARM.deaths == 0, "Replica cannot settle match death counters")
	authority.free()
	replica.free()
	print("MATCH_REFERENCE_PASS deaths=", fixtures.matchDeaths.size())

static func create(h: Node) -> MatchSimulation:
	var simulation := MatchSimulation.new()
	h.add_child(simulation)
	simulation.set_physics_process(false)
	simulation.clock = 10
	return simulation

static func actor(simulation: BattleSimulation, id: int, side: String, hero: bool, kind: String = "soldier") -> BattleUnit:
	var unit: BattleUnit
	if hero:
		unit = StatusHelper.actor(simulation, {"id": id, "character": "t05", "kind": "robot", "side": side, "position": [0, 0, 0], "hp": 100, "max_hp": 100})
	else:
		unit = BattleUnit.new()
		simulation.add_child(unit)
		unit.entity_id = id
		unit.side = side
		unit.kind = kind
		unit.hp = 100
		unit.max_hp = 100
		simulation.units[id] = unit
	unit.hit_area = Area3D.new()
	unit.add_child(unit.hit_area)
	return unit
