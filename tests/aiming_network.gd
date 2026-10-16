extends "res://scripts/main.gd"

var elapsed := 0.0
var started_at := -1.0
var fixture_pilot: BattleUnit
var fixture_enemy: BattleUnit
var fixture_observer: BattleUnit
var lock_seen := false
var skill_seen := false
var independent_clear_seen := false
var hidden_clear_seen := false
var incoming_seen := false

func _physics_process(delta: float) -> void:
	elapsed += delta
	if elapsed > 16:
		push_error("NETWORK_AIMING_TIMEOUT lock=%s skill=%s castClear=%s hidden=%s" % [lock_seen, skill_seen, independent_clear_seen, hidden_clear_seen])
		get_tree().quit(1)
		return
	if Session.dedicated:
		if simulation == null or simulation.pilots.is_empty():
			return
		if fixture_pilot == null:
			for pilot: BattleUnit in simulation.pilots.values():
				if pilot.peer_id > 1:
					fixture_pilot = pilot
			if fixture_pilot == null:
				return
			simulation.set_physics_process(false)
			for unit: BattleUnit in simulation.units.values():
				if unit != fixture_pilot:
					unit.hp = 0
			fixture_pilot.position = Vector3(0, simulation.world.ground_height(0, 0) + 80, 0)
			fixture_enemy = simulation.spawn({"kind": "soldier", "side": "SWARM", "position": fixture_pilot.position + Vector3(0, 0, -5)})
			fixture_observer = simulation.spawn({"kind": Content.heroes.s01.kind, "character": "s01", "peer": 3301, "side": "SWARM",
				"position": fixture_pilot.position + Vector3(30, 0, 0)})
			# Use an executed original-helper oracle input; this does not enable a gameplay skill.
			var fixtures: Dictionary = Content.read_json("res://data/fixtures.json")
			var references: Array = fixtures.skillFootprints.filter(func(item): return item.character == "helper" and item.slot == "enemy" and not item.result.is_empty())
			if references.is_empty():
				push_error("NETWORK_AIMING_SOURCE_REFERENCE_MISSING")
				get_tree().quit(1)
				return
			fixture_pilot.cast_preview = {"definition": references[0].definition.duplicate(true), "point": fixture_pilot.position, "until": simulation.clock + 1.0}
			started_at = elapsed
		simulation.clock += delta
		var phase := elapsed - started_at
		if phase < 1.8:
			simulation._confirm_lock(fixture_pilot, fixture_enemy.entity_id)
			simulation._confirm_lock(fixture_observer, fixture_pilot.entity_id)
		else:
			fixture_enemy.position.x = fixture_pilot.position.x + 2000
		if not simulation.snapshot().skill_footprint.is_empty() or simulation.skill_glows != null or simulation.lock_glow != null:
			push_error("NETWORK_AIMING_PRIVATE_STATE_LEAK")
			get_tree().quit(1)
		return
	super._physics_process(delta)
	incoming_seen = incoming_seen or (lock_warning.visible and locked_until > float(Time.get_ticks_msec()) / 1000.0)
	if lock_seen and skill_seen and independent_clear_seen and hidden_clear_seen and incoming_seen:
		print("NETWORK_PASS peer=", multiplayer.get_unique_id(), " units=", simulation.units.size())
		print("NETWORK_AIMING_PASS lock=true incoming_warning=true skill=true independent_clear=true hidden=true private=true")
		Session.stop()
		get_tree().quit()

func _receive_state(state: Dictionary) -> void:
	super._receive_state(state)
	if Session.dedicated or simulation == null:
		return
	var lock_state: Dictionary = state.get("lock", {})
	var skill: Dictionary = state.get("skill_footprint", {})
	if not lock_state.is_empty() and int(lock_state.anchor) != 0:
		var target: BattleUnit = simulation.units.get(int(lock_state.anchor))
		if target == null or simulation.lock_glow.target_id != target.entity_id or not simulation.lock_glow.visible:
			push_error("NETWORK_AIMING_LOCK_MISSING")
			get_tree().quit(1)
			return
		simulation.lock_glow.advance(1.0)
		if simulation.lock_glow.global_transform != target.global_transform:
			push_error("NETWORK_AIMING_LOCK_POSE")
			get_tree().quit(1)
			return
		lock_seen = true
	if not skill.is_empty() and not skill.hits.is_empty():
		if skill.hits.size() != 1 or simulation.skill_glows.active.size() != 1:
			push_error("NETWORK_AIMING_SKILL_ROSTER")
			get_tree().quit(1)
			return
		var glow: MeshInstance3D = simulation.skill_glows.active[int(skill.hits[0])]
		if not glow.visible or glow.material_override != simulation.skill_glows.normal or not simulation.skill_glows.skill_layer:
			push_error("NETWORK_AIMING_SKILL_MATERIAL")
			get_tree().quit(1)
			return
		skill_seen = true
	elif skill_seen and lock_seen and simulation.skill_glows.active.is_empty() and simulation.lock_glow.visible:
		independent_clear_seen = true
	if independent_clear_seen and lock_state.is_empty() and simulation.skill_glows.active.is_empty() and not simulation.lock_glow.visible:
		hidden_clear_seen = true
