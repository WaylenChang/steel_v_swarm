extends "res://scripts/main.gd"

var elapsed := 0.0
var started_at := -1.0
var fixture_boss: BattleUnit
var fixture_pilot: BattleUnit
var reference: Dictionary = {}
var phase := -1
var segments_seen: Dictionary = {}
var bar_seen := false
var stages_seen := false

func _physics_process(delta: float) -> void:
	if Session.launch_announced:
		elapsed += delta
	if elapsed > 16:
		push_error("NETWORK_BOSS_TIMEOUT segments=%s bar=%s stages=%s" % [segments_seen.keys(), bar_seen, stages_seen])
		get_tree().quit(1)
		return
	if Session.dedicated:
		if simulation == null or simulation.pilots.is_empty():
			return
		if fixture_boss == null:
			for unit: BattleUnit in simulation.pilots.values():
				if unit.peer_id > 1:
					fixture_pilot = unit
			if fixture_pilot == null:
				return
			simulation.set_physics_process(false)
			for unit: BattleUnit in simulation.units.values():
				if unit != fixture_pilot:
					unit.hp = 0
					unit.refresh_collision()
			fixture_pilot.position = Vector3(0, simulation.world.ground_height(0, 0) + 80, 0)
			fixture_pilot.yaw = 0
			fixture_pilot.pitch = 0
			fixture_pilot.rotation.y = 0
			fixture_pilot.sync_view_camera()
			var fixtures: Dictionary = Content.read_json("res://data/fixtures.json", ["bossSync"])
			for item: Dictionary in fixtures.bossSync:
				if item.initial.character == "s01":
					reference = item
			if reference.is_empty():
				push_error("NETWORK_BOSS_SOURCE_REFERENCE_MISSING")
				get_tree().quit(1)
				return
			simulation.siege = true
			simulation.defending_side = "SWARM"
			simulation.siege_open = {"SWARM": 0, "STEEL": 2}
			simulation.siege_left = {"SWARM": [1, 0, 0], "STEEL": [0, 0, 0]}
			simulation.boss_left = simulation.siege_left.duplicate(true)
			fixture_boss = simulation.spawn({"character": "s01", "kind": Content.heroes.s01.kind, "peer": -3002, "side": "SWARM", "bot": true,
				"special": {"boss": true, "boss_segment": 0, "siege_stage": 0},
				"position": Vector3(0, simulation.world.ground_height(0, -60) + 80, -60)})
			started_at = elapsed
		var next_phase := mini(3, int((elapsed - started_at) / 0.8))
		if next_phase != phase:
			phase = next_phase
			var step: Dictionary = reference.steps[phase]
			simulation.clock = step.now
			fixture_boss.hp = floorf(fixture_boss.max_hp * float(step.fraction) + 0.5)
			fixture_boss.shield = 0
			simulation._boss_sync(fixture_boss)
		return
	super._physics_process(delta)
	bar_seen = bar_seen or boss_hud.visible and boss_hud.active_unit != null and boss_hud.active_unit.character == "s01"
	if segments_seen.size() == 4 and bar_seen and stages_seen:
		print("NETWORK_PASS peer=", Session.player_id(), " units=", simulation.units.size())
		print("NETWORK_BOSS_PASS segments=true shield=true upgrades=true scale=true stages=true bar=true authority=true")
		Session.stop()
		get_tree().quit()

# Snapshot levels are integers while the JSON-decoded reference holds floats.
func _upgrades_match(actual: Dictionary, expected: Dictionary) -> bool:
	if actual.size() != expected.size():
		return false
	for key: String in expected:
		if not actual.has(key) or float(actual[key]) != float(expected[key]):
			return false
	return true

func _receive_state(state: Dictionary) -> void:
	super._receive_state(state)
	if Session.dedicated or simulation == null:
		return
	var stage_state: Dictionary = state.get("siege", {})
	stages_seen = stages_seen or stage_state.get("enabled", false) and stage_state.get("defender") == "SWARM" and int(stage_state.open.SWARM) == 0
	if reference.is_empty():
		var fixtures: Dictionary = Content.read_json("res://data/fixtures.json", ["bossSync"])
		for item: Dictionary in fixtures.bossSync:
			if item.initial.character == "s01":
				reference = item
	for input: Dictionary in state.units:
		if int(input.peer) != -3002:
			continue
		var segment: int = int(input.special.boss_segment)
		var expected: Dictionary = reference.steps[segment].result
		# The first trace input stays in segment zero; subsequent inputs break one segment each.
		if absf(float(input.max_hp) - float(expected.max_hp)) > 0.001 or not _upgrades_match(input.upgrades, expected.upgrades) or absf(float(input.shield) - float(expected.shield)) > 0.001:
			push_error("NETWORK_BOSS_SOURCE_STATE_MISMATCH segment=%d actual=%s expected=%s" % [segment, [input.max_hp, input.upgrades, input.shield], expected])
			get_tree().quit(1)
			return
		var unit: BattleUnit = simulation.units[int(input.id)]
		if absf(unit.radius - float(expected.radius)) > 0.001 or absf(unit.height - float(expected.height)) > 0.001:
			push_error("NETWORK_BOSS_SOURCE_SCALE_MISMATCH")
			get_tree().quit(1)
			return
		var health := unit.hp
		var upgrade: Dictionary = unit.upgrades.duplicate()
		simulation._boss_sync(unit)
		if unit.hp != health or unit.upgrades != upgrade:
			push_error("NETWORK_BOSS_REPLICA_SETTLEMENT")
			get_tree().quit(1)
			return
		segments_seen[segment] = true
