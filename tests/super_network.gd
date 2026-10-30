extends "res://scripts/main.gd"

var elapsed := 0.0
var fixture_at := -1.0
var fixture_pilot: BattleUnit
var fixture_phase := 0
var levels_seen: Dictionary = {}
var death_seen := false
var respawn_seen := false
var reference_sequence: Dictionary = {}

func _physics_process(delta: float) -> void:
	if Session.launch_announced:
		elapsed += delta
	if elapsed > 18:
		push_error("NETWORK_SUPER_TIMEOUT levels=%s death=%s respawn=%s" % [levels_seen, death_seen, respawn_seen])
		get_tree().quit(1)
		return
	if Session.dedicated:
		if simulation == null or not simulation.super_mode:
			return
		if fixture_pilot == null:
			for unit: BattleUnit in simulation.pilots.values():
				if unit.peer_id > 1 and unit.side == "SUPER":
					fixture_pilot = unit
			if fixture_pilot == null:
				return
			simulation.set_physics_process(false)
			simulation.vision_until.SUPER = 10000
			simulation._set_super_level(fixture_pilot, 19)
			fixture_pilot.money = 237.5
			fixture_at = elapsed
		if fixture_phase == 0 and elapsed - fixture_at > 1:
			fixture_phase = 1
			fixture_pilot.money = 437.5
			if not simulation.buy(fixture_pilot, "super"):
				push_error("NETWORK_SUPER_AUTHORITY_PURCHASE")
				get_tree().quit(1)
		elif fixture_phase == 1 and elapsed - fixture_at > 2:
			fixture_phase = 2
			simulation.damage(null, fixture_pilot, {}, 1000000000, false, {}, false)
			if fixture_pilot.alive() or fixture_pilot.money != 0 or int(fixture_pilot.upgrades["super"]) != 19:
				push_error("NETWORK_SUPER_AUTHORITY_PENALTY")
				get_tree().quit(1)
		elif fixture_phase == 2 and elapsed - fixture_at > 3:
			fixture_phase = 3
			var yaw_before := fixture_pilot.yaw
			simulation.respawn(fixture_pilot)
			if not fixture_pilot.alive() or fixture_pilot.yaw != yaw_before or fixture_pilot.hp != fixture_pilot.max_hp:
				push_error("NETWORK_SUPER_AUTHORITY_RESPAWN")
				get_tree().quit(1)
		return
	super._physics_process(delta)
	if levels_seen.has(19) and levels_seen.has(20) and death_seen and respawn_seen:
		print("NETWORK_PASS peer=", Session.player_id(), " units=", simulation.units.size())
		print("NETWORK_SUPER_PASS source=true roster=true scales=true buy=true penalty=true respawn=true")
		Session.stop()
		get_tree().quit()

func _receive_state(state: Dictionary) -> void:
	super_auto.button_pressed = false
	super._receive_state(state)
	if Session.dedicated or simulation == null or not Session.config.get("super", false):
		return
	var pilot: BattleUnit = simulation.pilots.get(Session.player_id())
	if pilot == null:
		return
	if Session.roster.size() != 3 or Session.roster.filter(func(player): return not player.bot).size() != 1 or pilot.side != "SUPER" or not state.stats.has("SUPER"):
		push_error("NETWORK_SUPER_ROSTER_OR_STATS")
		get_tree().quit(1)
		return
	if reference_sequence.is_empty():
		var fixtures: Dictionary = Content.read_json("res://data/fixtures.json", ["superLevels"])
		reference_sequence = fixtures.superLevels.filter(func(item): return item.character == pilot.character and not item.dead)[0]
	var level := int(pilot.upgrades["super"])
	var matches: Array = reference_sequence.steps.filter(func(step): return int(step.state.level) == level)
	if matches.is_empty():
		return
	var expected: Dictionary = matches[0].state
	if absf(pilot.max_hp - float(expected.max_hp)) > 0.01 or absf(pilot.max_shield - float(expected.max_shield)) > 0.01 or absf(pilot.radius - float(expected.radius)) > 0.001 or absf(pilot.height - float(expected.height)) > 0.001:
		push_error("NETWORK_SUPER_SOURCE_DERIVED_CAPACITY_OR_VOLUME")
		get_tree().quit(1)
		return
	levels_seen[level] = true
	death_seen = death_seen or not pilot.alive() and level == 19 and pilot.money == 0
	respawn_seen = respawn_seen or death_seen and pilot.alive() and pilot.hp == pilot.max_hp and level == 19
