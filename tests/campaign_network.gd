extends "res://scripts/main.gd"

var elapsed := 0.0
var fixture_ready_at := -1.0
var fixture_pilot: BattleUnit
var fixture_boss: BattleUnit
var fixture_tower: BattleUnit
var boss_settled := false
var roster_seen := false
var floor_seen := false
var dialogue_seen := false
var stages_seen := false

func _physics_process(delta: float) -> void:
	elapsed += delta
	if elapsed > 18:
		push_error("NETWORK_CAMPAIGN_TIMEOUT roster=%s floor=%s dialogue=%s stages=%s" % [roster_seen, floor_seen, dialogue_seen, stages_seen])
		get_tree().quit(1)
		return
	if Session.dedicated:
		if simulation == null or not Session.config.has("campaign"):
			return
		if fixture_pilot == null:
			for unit: BattleUnit in simulation.pilots.values():
				if unit.peer_id > 1:
					fixture_pilot = unit
				elif unit.special.get("boss", false) and int(unit.special.get("siege_stage", -1)) == 0:
					fixture_boss = unit
			for unit: BattleUnit in simulation.units.values():
				if unit.kind == "tower" and int(unit.special.get("siege_stage", -1)) == 0 and unit.side == simulation.defending_side:
					fixture_tower = unit
			if fixture_pilot == null or fixture_boss == null or fixture_tower == null:
				return
			simulation.set_physics_process(false)
			simulation.vision_until[fixture_pilot.side] = 10000
			simulation.damage(fixture_pilot, fixture_tower, {}, 1000000000, false, {}, false)
			if fixture_tower.hp != 1 or int(simulation.siege_open[simulation.defending_side]) != 0:
				push_error("NETWORK_CAMPAIGN_AUTHORITY_FLOOR")
				get_tree().quit(1)
				return
			fixture_ready_at = elapsed
		simulation.clock += delta
		if not boss_settled and elapsed - fixture_ready_at > 1.0:
			boss_settled = true
			simulation.damage(fixture_pilot, fixture_boss, {}, 1000000000, false, {}, false)
			if fixture_boss.alive() or not is_inf(fixture_boss.respawn_at) or float(simulation.siege_talk_until[simulation.defending_side][0]) <= simulation.clock:
				push_error("NETWORK_CAMPAIGN_AUTHORITY_BOSS_DIALOGUE")
				get_tree().quit(1)
		return
	super._physics_process(delta)
	dialogue_seen = dialogue_seen or campaign_dialogue.at > 0 and campaign_dialogue.total > 0 and campaign_dialogue.bar != null
	if roster_seen and floor_seen and dialogue_seen and stages_seen:
		print("NETWORK_PASS peer=", multiplayer.get_unique_id(), " units=", simulation.units.size())
		print("NETWORK_CAMPAIGN_PASS roster=true map=true stages=true floor=true boss=true radio=true source=true")
		Session.stop()
		get_tree().quit()

func _receive_state(state: Dictionary) -> void:
	super._receive_state(state)
	if Session.dedicated or simulation == null or not Session.config.has("campaign"):
		return
	var selection: Dictionary = Session.config.campaign
	var expected := CampaignRules.roster(int(selection.index), selection.side, selection.pilot, multiplayer.get_unique_id())
	var current: Array = []
	for unit: Dictionary in state.units:
		if not unit.character.is_empty() and unit.special.get("role") != "clone":
			current.append({"peer": int(unit.peer), "side": unit.side, "character": unit.character, "bot": unit.bot})
		if unit.kind == "tower" and int(unit.special.get("siege_stage", -1)) == 0 and float(unit.hp) == 1:
			floor_seen = true
	if current.size() == expected.size():
		for player: Dictionary in expected:
			if not current.has(player):
				push_error("NETWORK_CAMPAIGN_SOURCE_ROSTER_MISMATCH")
				get_tree().quit(1)
				return
		roster_seen = true
	var stage_state: Dictionary = state.get("siege", {})
	stages_seen = stages_seen or stage_state.get("enabled", false) and stage_state.get("defender") == "SWARM" and campaign_dialogue.track_label.visible
